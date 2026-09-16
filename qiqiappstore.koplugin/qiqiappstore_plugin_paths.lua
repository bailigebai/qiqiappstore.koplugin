-- qiqiappstore_plugin_paths.lua
local DataStorage = require("datastorage")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")

local DEFAULT_PLUGIN_PATH = "plugins"

local M = {}

function M.getDefaultPluginsRoot()
    return DataStorage:getDataDir() .. "/plugins"
end

-- Same lookup order as frontend/pluginloader.lua's PluginLoader:_discover:
-- the bundled "plugins" directory, then every entry configured in the
-- extra_plugin_paths setting (existing directories only). Entries are
-- deduplicated by resolved real path (via ffiUtil.realpath), not by string
-- identity: on most on-device deployments DataStorage:getDataDir() equals
-- the process's cwd, so the bundled "plugins" entry and an auto-populated
-- extra_plugin_paths entry of `data_dir .. "/plugins/"` are two different
-- strings pointing at the exact same physical directory, and must only be
-- scanned (and listed) once. The first-seen path string for a given real
-- directory is the one kept, since downstream code (main.lua) builds
-- target directories from these strings directly.
function M.getLookupPaths()
    local paths = {}
    local seen_real_paths = {}

    local function tryAdd(p)
        if not p or p == "" then
            return
        end
        if lfs.attributes(p, "mode") ~= "directory" then
            return
        end
        local real_p = ffiUtil.realpath(p)
        if real_p and seen_real_paths[real_p] then
            return
        end
        table.insert(paths, p)
        if real_p then
            seen_real_paths[real_p] = true
        end
    end

    tryAdd(DEFAULT_PLUGIN_PATH)

    local extra = G_reader_settings:readSetting("extra_plugin_paths")
    if type(extra) == "string" then
        extra = { extra }
    end
    if type(extra) == "table" then
        for _, p in ipairs(extra) do
            tryAdd(p)
        end
    end

    return paths
end

-- Lookup paths minus the bundled "plugins" dir and minus the historical
-- default data-dir location -- i.e. directories the user genuinely
-- configured on top of the defaults. Compared by resolved real path so an
-- extra_plugin_paths entry that merely looks different from "plugins" or
-- from getDefaultPluginsRoot(), but resolves to the same physical
-- directory, is correctly excluded rather than counted as custom.
function M.getCustomLookupPaths()
    local bundled_real = ffiUtil.realpath(DEFAULT_PLUGIN_PATH)
    local default_root_real = ffiUtil.realpath(M.getDefaultPluginsRoot())
    local custom = {}
    for _, p in ipairs(M.getLookupPaths()) do
        local real_p = ffiUtil.realpath(p)
        if real_p and real_p ~= bundled_real and real_p ~= default_root_real then
            table.insert(custom, p)
        end
    end
    return custom
end

-- QiqiAppStoreSettings key for the user's per-path hide/show preference (an
-- array of path strings, compared by resolved real path -- see
-- isPathHidden). Exposed here as a field on this module's table, rather
-- than as a main.lua file-level local, because main.lua's chunk is
-- already at LuaJIT's 200-local ceiling (see the NOTE above
-- QiqiAppStore:resolveNewInstallDestination in main.lua).
M.HIDDEN_PLUGIN_PATHS_KEY = "hidden_plugin_paths"

-- Returns whether `path` resolves (via ffiUtil.realpath) to the same real
-- directory as any entry in `hidden_paths`. A nil/empty hidden_paths, or a
-- path with no resolvable real path, never counts as hidden.
function M.isPathHidden(path, hidden_paths)
    if not hidden_paths or #hidden_paths == 0 then
        return false
    end
    local real_path = ffiUtil.realpath(path)
    if not real_path then
        return false
    end
    for _, h in ipairs(hidden_paths) do
        if ffiUtil.realpath(h) == real_path then
            return true
        end
    end
    return false
end

-- Returns whether `path` resolves (via ffiUtil.realpath) to the same real
-- directory as any entry currently in M.getLookupPaths(). A nil realpath
-- (path doesn't exist) never matches anything.
local function pathInLookup(path)
    if not path or path == "" then
        return false
    end
    local real_path = ffiUtil.realpath(path)
    if not real_path then
        return false
    end
    for _, p in ipairs(M.getLookupPaths()) do
        if ffiUtil.realpath(p) == real_path then
            return true
        end
    end
    return false
end

-- Resolves the directory a freshly installed (non-update) plugin should be
-- written to.
--
-- config_override: string|nil  -- `plugin_install_path` from qiqiappstore_configuration.lua
-- remembered_path:  string|nil -- previously remembered choice (QiqiAppStoreSettings)
-- hidden_paths:     table|nil  -- paths the user hid via "Manage plugin paths"
--                                 (same shape as isPathHidden's 2nd arg)
--
-- Returns dest_root (string|nil), needs_prompt (boolean), candidates (table|nil,
-- only set when needs_prompt is true), all_hidden (boolean, true when custom
-- paths exist but every one of them is currently hidden -- distinct from "no
-- custom paths configured at all", which silently falls back to the default
-- root exactly as before this parameter existed).
function M.resolveInstallDestination(config_override, remembered_path, hidden_paths)
    if config_override and config_override ~= "" and pathInLookup(config_override)
        and not M.isPathHidden(config_override, hidden_paths) then
        return config_override, false, nil, false
    end

    if remembered_path and remembered_path ~= "" and pathInLookup(remembered_path)
        and not M.isPathHidden(remembered_path, hidden_paths) then
        return remembered_path, false, nil, false
    end

    local custom = M.getCustomLookupPaths()
    local visible_custom = {}
    for _, p in ipairs(custom) do
        if not M.isPathHidden(p, hidden_paths) then
            table.insert(visible_custom, p)
        end
    end

    if #custom > 0 and #visible_custom == 0 then
        return nil, false, nil, true
    elseif #visible_custom == 1 then
        return visible_custom[1], false, nil, false
    elseif #visible_custom >= 2 then
        return nil, true, visible_custom, false
    end

    return M.getDefaultPluginsRoot(), false, nil, false
end

return M
