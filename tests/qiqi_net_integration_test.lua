-- Exercise the shipped request wrapper with KOReader's real timeout and sink
-- implementation. Only platform modules, the transport and the clock are fake;
-- this test does not make a native TLS connection or assert device connectivity.
local socketutil_path = "../tests/fixtures/socketutil-v2026.07.1.lua"
local source_handle = assert(io.open(socketutil_path, "rb"),
    "integration fixture requires the local KOReader v2026.07.1 source checkout")
source_handle:close()

local clock = 1000
local real_time = os.time
os.time = function() return clock end
local http = { USERAGENT = "LuaSocket/test", TIMEOUT = 60 }
local https = { TIMEOUT = 60 }
local observed_tcp = {}
local warnings = 0

package.preload["device"] = function() return { model = "test" } end
package.preload["version"] = function()
    return { getShortVersion = function() return "v2026.07.1" end }
end
jit = jit or { os = "test", arch = "test" }
package.preload["socket.http"] = function() return http end
package.preload['ui/time'] = function() return {now=function()return clock end,to_s=function(v)return v end} end
package.preload["ssl.https"] = function() return https end
package.preload["socket"] = function()
    return {
        tcp = function()
            return { settimeout = function(_, value, mode) observed_tcp[mode] = value end }
        end,
    }
end
package.preload["ffi/util"] = function()
    return { template = function(value) return value end }
end
package.preload["ltn12"] = function()
    return { sink = {
        file = function(handle)
            return function(chunk)
                if chunk then return handle:write(chunk) end
                handle:close()
                return 1
            end
        end,
        table = function(parts)
            return function(chunk)
                if chunk then parts[#parts + 1] = chunk end
                return 1
            end
        end,
    } }
end
package.preload["logger"] = function()
    return { warn = function() warnings = warnings + 1 end }
end
package.preload["socketutil"] = function() return dofile(socketutil_path) end

local socketutil = require("socketutil")
local Net = require("qiqiappstore_net")

local function assertDefaults()
    assert(socketutil.block_timeout == 60 and socketutil.total_timeout == -1)
    assert(http.TIMEOUT == 60 and https.TIMEOUT == 60,
        "the wrapper must restore both HTTP and HTTPS timeout constants")
    assert(socketutil.FILE_BLOCK_TIMEOUT == 15 and socketutil.FILE_TOTAL_TIMEOUT == 60,
        "request-specific budgets must not modify KOReader's file defaults")
end

local function openFile()
    return {
        body = "", closed = false,
        write = function(self, chunk)
            assert(not self.closed)
            self.body = self.body .. chunk
            return true
        end,
        close = function(self) self.closed = true end,
    }
end

local function transfer(elapsed, expected_code)
    clock = 1000
    local file = openFile()
    http.request = function(request)
        assert(http.TIMEOUT == 45 and https.TIMEOUT == 45)
        assert(socketutil.block_timeout == 45 and socketutil.total_timeout == 300)
        socketutil.tcp()
        assert(observed_tcp.b == 45 and observed_tcp.t == 300,
            "real socketutil must apply both budgets to new sockets")
        clock = clock + elapsed
        local ok, err = request.sink("ZIP data")
        if not ok then return nil, err end
        request.sink(nil)
        return 1, 200, {}, "HTTP/1.1 200 OK"
    end
    local code = Net.requestToFile({ url = "https://github.com/example/plugin.zip" }, file, 45, 300)
    assert(code == expected_code, "unexpected real sink outcome: " .. tostring(code))
    assert(file.closed, "the real sink must close the file after success or deadline expiry")
    assert(file.body == (expected_code == 200 and "ZIP data" or ""))
    assertDefaults()
end

transfer(90, 200)
transfer(300, 200)
transfer(301, "sink timeout")

http.request = function()
    assert(http.TIMEOUT == 45 and https.TIMEOUT == 45)
    error("simulated TLS exception")
end
local code, _, status = Net.requestToFile({ url = "https://github.com/example/plugin.zip" }, openFile(), 45, 300)
assert(code == nil and tostring(status):find("simulated TLS exception", 1, true))
assert(warnings == 1, "request exceptions should reach the diagnostic logger")
assertDefaults()

-- The API path has a different budget; exercise its actual table sink too.
clock = 1000
http.request = function(request)
    assert(http.TIMEOUT == 10 and https.TIMEOUT == 10)
    assert(socketutil.block_timeout == 10 and socketutil.total_timeout == 30)
    clock = clock + 31
    local ok, err = request.sink("API data")
    assert(not ok and err == "sink timeout")
    return nil, err
end
local parts = {}
assert(Net.requestToTable({ url = "https://api.github.com/example" }, parts) == "sink timeout")
assert(#parts == 0)
assertDefaults()
os.time = real_time
print("Net integration: real KOReader sinks, 90/300/301 seconds, socket budgets and exception reset checked")
