--[[--
HTTP requests with a deadline on them.

`socketutil`'s timeouts are global: set, request, reset. Should the request throw in between,
the reset never runs and the rest of KOReader keeps waiting as long as we asked to. Here the
request goes through pcall, so the reset happens whatever the outcome.

API sinks are built after `set_timeout`. File downloads use an independent,
monotonic deadline, so other requests and system clock updates cannot expire them.

    local body_parts = {}
    local code, _, status = Net.requestToTable(request, body_parts)
    local code, headers, status = Net.requestToFile(request, file, socketutil.FILE_BLOCK_TIMEOUT,
        socketutil.FILE_TOTAL_TIMEOUT)

`code` is nil only when the request threw, and the error message takes the place of the status
line. A timeout arrives as a string where `code` would be. Callers pass either on, so the
reason reaches their log instead of turning into a bare nil.
]]

local http = require("socket.http")
local socketutil = require("socketutil")
local logger = require("logger")
local Time = require('ui/time')

local Net = {}
function Net.now() return Time.to_s(Time.now()) end

local function perform(request, make_sink, block_timeout, total_timeout)
    socketutil:set_timeout(block_timeout or socketutil.LARGE_BLOCK_TIMEOUT,
        total_timeout or socketutil.LARGE_TOTAL_TIMEOUT)
    local ok, result, code, headers, status = pcall(function()
        request.sink = make_sink()
        return http.request(request)
    end)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("qiqiappstore: request failed:", request.url, result)
        -- The reason goes where a status line would: callers already read it.
        return nil, nil, result
    end
    return code, headers, status
end

--- Collect the response body into `response_parts`, to be concatenated by the caller.
function Net.requestToTable(request, response_parts, block_timeout, total_timeout)
    return perform(request, function()
        return socketutil.table_sink(response_parts)
    end, block_timeout, total_timeout)
end

--- Write the response body to an open file.
function Net.requestToFile(request, file, block_timeout, total_timeout)
    local budget = total_timeout or socketutil.FILE_TOTAL_TIMEOUT
    local started = Net.now()
    return perform(request, function()
        -- Independent of socketutil's mutable global total and wall-clock/NTP jumps.
        return function(chunk)
            if not chunk then file:close();return 1 end
            if budget >= 0 and Net.now()-started > budget then
                file:close();return nil,'sink timeout'
            end
            return file:write(chunk)
        end
    end, block_timeout or socketutil.FILE_BLOCK_TIMEOUT, budget)
end

return Net
