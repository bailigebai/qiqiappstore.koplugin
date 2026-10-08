local files = {}
local directories = { ["/data/cache/qiqiappstore/readme"] = true }
local requests = {}
local replies = {}

package.loaded["qiqiappstore_repo_content"] = nil
package.preload["datastorage"] = function()
    return { getDataDir = function() return "/data" end }
end
package.preload["ui/uimanager"] = function() return { show = function() end } end
package.preload["ui/widget/infomessage"] = function() return { new = function(_, value) return value end } end
package.preload["apps/filemanager/filemanager"] = function() return { openFile = function() end } end
package.preload["qiqiappstore_gettext"] = function() return function(value) return value end end
package.preload["logger"] = function() return { warn = function() end } end
package.preload["version"] = function()
    return {
        getNormalizedVersion = function() return 202607 end,
        getNormalizedCurrentVersion = function() return 202607 end,
    }
end
package.preload["qiqiappstore_mirror"] = function() return { apply = function(url) return url end } end
package.preload["qiqiappstore_net"] = function()
    return {
        requestToTable = function(request, response)
            requests[#requests + 1] = request.url
            local reply = table.remove(replies, 1) or { code = nil, status = "offline" }
            if reply.body then response[#response + 1] = reply.body end
            return reply.code, nil, reply.status
        end,
    }
end
package.preload["util"] = function()
    return {
        makePath = function(path) directories[path] = true; return true end,
        writeToFile = function(content, path) files[path] = content; return true end,
        readFromFile = function(path) return files[path] end,
    }
end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, field)
            local mode = directories[path] and "directory" or (files[path] and "file" or nil)
            if field == "mode" then return mode end
            return mode and { mode = mode } or nil
        end,
        dir = function(path)
            local names = { ".", ".." }
            local prefix = path .. "/"
            for filename in pairs(files) do
                if filename:sub(1, #prefix) == prefix then
                    local name = filename:sub(#prefix + 1)
                    if not name:find("/", 1, true) then names[#names + 1] = name end
                end
            end
            local index = 0
            return function() index = index + 1; return names[index] end
        end,
    }
end

local RepoContent = require("qiqiappstore_repo_content")

do
    local before = #requests
    local content, err = RepoContent.fetchReadmeContent("someoneelse", "a.koplugin")
    assert(content == nil and type(err) == "string")
    assert(#requests == before, "out-of-policy repositories must not reach the network")
    local cached = RepoContent.readCachedReadme("bailigebai", "not-a-plugin")
    assert(cached == nil, "out-of-policy cache names must be refused")
end

do
    replies[#replies + 1] = { code = 200, body = "# Dotted\n<img src='x'>keep" }
    local content = assert(RepoContent.fetchReadmeContent("bailigebai", "a.b.koplugin"))
    assert(content == "# Dotted\nkeep", "downloaded README must retain text and strip inline images")
    local cached, dotted_path = RepoContent.readCachedReadme("bailigebai", "a.b.koplugin")
    assert(cached == content)
    assert(dotted_path:find("a.b.koplugin", 1, true), "legal dots must remain in cache filenames")

    replies[#replies + 1] = { code = 200, body = "# Underscore" }
    assert(RepoContent.fetchReadmeContent("bailigebai", "a_b.koplugin"))
    local _, underscore_path = RepoContent.readCachedReadme("bailigebai", "a_b.koplugin")
    assert(dotted_path ~= underscore_path, "a.b and a_b repositories must not collide")
end

do
    replies[#replies + 1] = { code = nil, status = "network timeout" }
    local content, err = RepoContent.fetchReadmeContent("bailigebai", "a.b.koplugin")
    assert(content == "# Dotted\nkeep" and err == nil,
        "modern README fetch must fall back to the shared disk cache")

    replies[#replies + 1] = { code = nil, status = "offline" }
    local ok, path = RepoContent.fetchReadme("bailigebai", "a.b.koplugin")
    assert(ok and files[path] == "# Dotted\nkeep",
        "legacy README fetch must reuse the same cached file")
end

do
    replies[#replies + 1] = { code = 404, status = "Not Found" }
    local content, err = RepoContent.fetchReadmeContent("bailigebai", "missing.koplugin")
    assert(content == nil and err == "HTTP 404", "cache misses must preserve the network error")
end

print("readme: policy-scoped shared disk cache, dotted names and offline fallback checked")
