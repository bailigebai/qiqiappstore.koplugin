local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local settings_path = DataStorage:getSettingsDir() .. "/qiqiappstore.lua"

return LuaSettings:open(settings_path)
