-- Execute the shipped download helper; substitute only network, clock and disk.
local source = assert(io.open("qiqiappstore.koplugin/main.lua", "rb")):read("*a"):gsub("\r\n", "\n")
local body = assert(source:match("downloadToFile = function%(url, local_path%)(.-)\nend\n"))
local steps, calls, opens, clock, disk, removed = {}, {}, {}, 1000, "", false
local env = setmetatable({}, { __index = _G })
env.Mirror = { apply = function(url) return url end }
env.util = { makePath = function() end, removeFile = function() disk = nil; removed = true end }
env.os = { time = function() return clock end }
env.socketutil = {
    FILE_BLOCK_TIMEOUT = 15, FILE_TOTAL_TIMEOUT = 60,
    TIMEOUT_CODE = "timeout", SSL_HANDSHAKE_CODE = "wantread",
    SINK_TIMEOUT_CODE = "sink timeout", USER_AGENT = "test",
}
env.io = { open = function(path, mode)
    assert(mode == "wb", "every attempt must truncate any partial archive")
    disk = ""
    local file = { closed = false }
    function file:write(chunk) assert(not self.closed); disk = disk .. chunk end
    function file:close() self.closed = true end
    opens[#opens + 1] = file
    return file
end }
env.Net = { requestToFile = function(request, file, block, total)
    calls[#calls + 1] = { block = block, total = total, url = request.url }
    local step = assert(steps[#calls], "unexpected extra network attempt")
    clock = clock + (step.elapsed or 0)
    file:write(step.body or "partial archive")
    return step.code, step.headers, step.status
end }
local loader = assert(loadstring("return function(url, local_path)" .. body .. "\nend"))
setfenv(loader, env)
local download = loader()
local function run(fixture)
    steps, calls, opens, clock, disk, removed = fixture, {}, {}, 1000, "", false
    return download("https://github.com/bailigebai/legado.koplugin/releases/download/v1/plugin.zip", "/tmp/plugin.zip")
end

local ok, err = run({ { code = "wantread", elapsed = 45 }, { code = 200, headers = {}, body = "valid ZIP" } })
assert(ok, "transient TLS wantread must retry with a fresh file: " .. tostring(err))
assert(#calls == 2 and #opens == 2 and opens[1].closed and opens[2].closed)
assert(disk == "valid ZIP", "retry must never append to the partial first response")
assert(calls[1].block == 45 and calls[2].block == 45, "file TLS connections need a longer wait")
assert(calls[1].total == 300 and calls[2].total == 255, "attempts share a finite total budget")
assert(calls[1].url == calls[2].url, "retry must keep the selected download source")

for _, code in ipairs({ "wantwrite", "timeout" }) do
    assert(run({ { code = code }, { code = 200, headers = {} } }))
    assert(#calls == 2)
end
assert(run({ { status = "wantread" }, { code = 200, headers = {} } }), "request exceptions reported as status can also be transient")

ok, err = run({ { code = "wantread" }, { code = "wantread" } })
assert(not ok and #calls == 2 and removed and disk == nil)
assert(err:find("wantread", 1, true), "retain the network reason in the visible error")
for _, code in ipairs({ 403, 404, "sink timeout", "certificate verify failed" }) do
    assert(not run({ { code = code, headers = {}, status = tostring(code) } }))
    assert(#calls == 1 and removed and opens[1].closed, "do not replay HTTP, certificate or exhausted-sink errors")
end
assert(not run({ { code = "wantread", elapsed = 300 } }))
assert(#calls == 1, "never open a second transfer after the shared budget expires")
assert(env.socketutil.FILE_BLOCK_TIMEOUT == 15 and env.socketutil.FILE_TOTAL_TIMEOUT == 60, "do not change KOReader global defaults")
print("TLS downloads: transient retry, truncation, shared budget, permanent failures and bounded attempts checked")
