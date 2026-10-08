-- Regression: a successful empty account refresh must remain distinguishable
-- from "never refreshed" after the cache module is loaded again.
local database = { refresh = {} }

package.preload['datastorage'] = function()
    return { getDataDir = function() return '/data' end }
end
package.preload['ffi/util'] = function()
    return { joinPath = function(left, right) return left .. '/' .. right end }
end
package.preload['util'] = function()
    return {
        makePath = function() return true end,
        trim = function(value) return value:match('^%s*(.-)%s*$') end,
    }
end
package.preload['json'] = function()
    return { null = {}, encode = function() return '{}' end, decode = function() return {} end }
end
package.preload['logger'] = function()
    return { warn = function() end, dbg = function() end }
end
package.preload['lua-ljsqlite3/init'] = function()
    local function statement(sql)
        local stmt = { values = {} }
        function stmt:bind(...)
            self.values = { ... }
        end
        function stmt:step()
            if sql:find('INSERT OR REPLACE INTO refresh_state', 1, true) then
                database.refresh[self.values[1]] = self.values[2]
            elseif sql:find('SELECT fetched_at FROM refresh_state', 1, true) then
                local value = database.refresh[self.values[1]]
                return value and { value } or nil
            end
        end
        function stmt:reset() end
        function stmt:close() end
        return stmt
    end
    local connection = {}
    function connection:rowexec() return 20260808 end
    function connection:prepare(sql) return statement(sql) end
    function connection:exec(sql)
        if sql:find('DELETE FROM refresh_state', 1, true) then database.refresh = {} end
    end
    function connection:close() end
    return { open = function() return connection end }
end

local Cache = require('qiqiappstore_cache')
local before = os.time()
assert(Cache.storeRepos('plugin', {}, nil, nil, true))

package.loaded['qiqiappstore_cache'] = nil
local ReloadedCache = require('qiqiappstore_cache')
local fetched = ReloadedCache.getLastFetched('plugin')
assert(type(fetched) == 'number' and fetched >= before,
    'successful empty refresh timestamp must survive a process restart')

ReloadedCache.clear()
package.loaded['qiqiappstore_cache'] = nil
local ClearedCache = require('qiqiappstore_cache')
assert(ClearedCache.getLastFetched('plugin') == nil,
    'clearing the repository cache must also clear its refresh timestamp')

print('cache: empty refresh timestamp persists and clear removes it')
