-- Safe, transactional archive installation for QiqiAppStore.
--
-- Tests may inject opts.fs. The generic adapter contract is:
--   attributes, symlinkAttributes, makePath, list, readFile, writeFile,
--   copyFile, removeTree, rename, and uniqueSuffix.
-- Production uses KOReader's lfs/util together with os/io.

local Archive = {}

local MANIFEST = ".qiqiappstore-install-manifest"
local unique_counter = 0

local function join(left, right)
    if left == "" then return right end
    if right == "" then return left end
    return left .. "/" .. right
end

local function dirname(path)
    return path:match("^(.*)/[^/]+$") or ""
end

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function valid_plugin_dirname(name)
    return type(name) == "string"
        and name:match("^[%w_.%-]+%.koplugin$") ~= nil
        and name ~= ".koplugin"
        and not name:find("..", 1, true)
end

local function safe_archive_path(path)
    if type(path) ~= "string" or path == "" then return nil end
    if path:find("%z") or path:find("\\", 1, true) then return nil end
    if path:sub(1, 1) == "/" or path:match("^%a:") then return nil end
    if path:find("//", 1, true) then return nil end
    local checked = path:sub(-1) == "/" and path:sub(1, -2) or path
    if checked == "" then return nil end
    for component in checked:gmatch("[^/]+") do
        if component == "." or component == ".." or component == "" then return nil end
    end
    return true
end

local function safe_relative_path(path)
    return safe_archive_path(path) and path:sub(-1) ~= "/"
end

local function decode_quoted(source, start)
    local quote = source:sub(start, start)
    local i, out = start + 1, {}
    local escapes = { a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v" }
    while i <= #source do
        local char = source:sub(i, i)
        if char == quote then return table.concat(out), i + 1 end
        if char == "\n" or char == "\r" then return nil, i + 1 end
        if char ~= "\\" then
            out[#out + 1] = char
            i = i + 1
        else
            local escaped = source:sub(i + 1, i + 1)
            if escaped == "" then return nil, i + 1 end
            if escaped:match("%d") then
                local digits = source:sub(i + 1):match("^(%d%d?%d?)")
                local value = tonumber(digits)
                if not value or value > 255 then return nil, i + 1 end
                out[#out + 1] = string.char(value)
                i = i + 1 + #digits
            elseif escaped == "\n" then
                out[#out + 1] = "\n"
                i = i + 2
            elseif escaped == "\r" and source:sub(i + 2, i + 2) == "\n" then
                out[#out + 1] = "\n"
                i = i + 3
            else
                out[#out + 1] = escapes[escaped] or escaped
                i = i + 2
            end
        end
    end
    return nil, i
end

local function tokens(source)
    local result, i = {}, 1
    while i <= #source do
        local char = source:sub(i, i)
        if char:match("%s") then
            i = i + 1
        elseif source:sub(i, i + 1) == "--" then
            local equals = source:match("^%-%-%[(=*)%[", i)
            if equals then
                local close = "]" .. equals .. "]"
                local finish = source:find(close, i + 4 + #equals, true)
                i = finish and (finish + #close) or (#source + 1)
            else
                local finish = source:find("[\r\n]", i + 2)
                i = finish or (#source + 1)
            end
        elseif char == "\"" or char == "'" then
            local value, next_i = decode_quoted(source, i)
            if value ~= nil then result[#result + 1] = { kind = "string", value = value } end
            i = next_i
        elseif char:match("[%a_]") then
            local value = source:sub(i):match("^([%a_][%w_]*)")
            result[#result + 1] = { kind = "identifier", value = value }
            i = i + #value
        else
            result[#result + 1] = { kind = char, value = char }
            i = i + 1
        end
    end
    return result
end

function Archive.readMeta(source)
    local result = {}
    if type(source) ~= "string" then return result end
    local parsed = tokens(source)
    for index = 1, #parsed - 2 do
        local field = parsed[index]
        if field.kind == "identifier"
            and (field.value == "name" or field.value == "version")
            and parsed[index + 1].kind == "="
            and parsed[index + 2].kind == "string"
            and result[field.value] == nil then
            result[field.value] = parsed[index + 2].value
        end
    end
    return result
end

local function rewind(reader)
    if reader and type(reader.rewind) == "function" then reader:rewind() end
end

local function scan(reader)
    if not reader or type(reader.iterate) ~= "function" then
        return nil, "Archive reader is unavailable."
    end
    rewind(reader)
    local entries, seen, files = {}, {}, {}
    for entry in reader:iterate() do
        local path = entry and entry.path
        local mode = entry and entry.mode
        if not safe_archive_path(path) then
            return nil, "Archive contains an unsafe path: " .. tostring(path)
        end
        if mode == "symlink" or mode == "link" or mode == "hardlink" then
            return nil, "Archive links are not allowed: " .. path
        end
        if mode ~= "file" and mode ~= "directory" and mode ~= "dir" then
            return nil, "Archive contains an unsupported entry type at: " .. path
        end
        if seen[path] then return nil, "Archive contains a duplicate path: " .. path end
        seen[path] = true
        entries[#entries + 1] = { path = path, mode = mode }
        if mode == "file" then files[path] = true end
    end
    if reader.err ~= nil then
        return nil, "Archive reader failed: " .. tostring(reader.err)
    end
    return { entries = entries, files = files }
end

local function candidate_roots(files)
    local roots = {}
    for path in pairs(files) do
        local root = path:match("^(.*)/_meta%.lua$")
        if root == nil and path == "_meta.lua" then root = "" end
        if root ~= nil and files[join(root, "main.lua")] then roots[#roots + 1] = root end
    end
    table.sort(roots)
    return roots
end

function Archive.detect(reader, repo)
    local scanned, scan_err = scan(reader)
    if not scanned then return nil, scan_err end
    local roots = candidate_roots(scanned.files)
    if #roots == 0 then
        local has_meta, has_main = false, false
        for path in pairs(scanned.files) do
            if path == "_meta.lua" or path:match("/_meta%.lua$") then has_meta = true end
            if path == "main.lua" or path:match("/main%.lua$") then has_main = true end
        end
        if not has_meta then return nil, "Could not locate _meta.lua in the archive." end
        if not has_main then return nil, "Could not locate main.lua beside _meta.lua in the archive." end
        return nil, "main.lua and _meta.lua must be in the same plugin directory."
    end
    if #roots > 1 then return nil, "Archive contains multiple plugin directories." end

    local root = roots[1]
    local root_name = root ~= "" and basename(root) or nil
    local repo_name = repo and repo.name
    local plugin_dirname
    if root_name and valid_plugin_dirname(root_name) then
        plugin_dirname = root_name
    elseif valid_plugin_dirname(repo_name) then
        plugin_dirname = repo_name
    else
        return nil, "Archive plugin directory could not be identified safely."
    end

    local meta_path = join(root, "_meta.lua")
    local source = reader:extractToMemory(meta_path)
    if type(source) ~= "string" then return nil, "Could not read archive metadata: " .. meta_path end
    local metadata = Archive.readMeta(source)
    local plugin_name = metadata.name
    if not plugin_name or plugin_name == "" then
        plugin_name = plugin_dirname:gsub("%.koplugin$", "")
    end
    return {
        plugin_root = root,
        plugin_dirname = plugin_dirname,
        plugin_name = plugin_name,
        plugin_version = metadata.version,
    }
end

local function default_fs()
    local lfs = require("libs/libkoreader-lfs")
    local util = require("util")
    local fs = {}

    function fs.attributes(path) return lfs.attributes(path) end
    function fs.symlinkAttributes(path)
        if lfs.symlinkattributes then return lfs.symlinkattributes(path) end
        return lfs.attributes(path)
    end
    function fs.makePath(path)
        if path == "" then return true end
        return util.makePath(path)
    end
    function fs.list(path)
        local result = {}
        local iterator, state, initial = lfs.dir(path)
        if not iterator then return nil, state end
        for name in iterator, state, initial do
            if name ~= "." and name ~= ".." then result[#result + 1] = name end
        end
        table.sort(result)
        return result
    end
    function fs.readFile(path)
        local file, err = io.open(path, "rb")
        if not file then return nil, err end
        local content = file:read("*a")
        local ok_close, close_err = file:close()
        if not ok_close then return nil, close_err end
        return content
    end
    function fs.writeFile(path, content)
        local ok_make, make_err = fs.makePath(dirname(path))
        if not ok_make then return nil, make_err end
        local file, err = io.open(path, "wb")
        if not file then return nil, err end
        local ok_write, write_err = file:write(content)
        local ok_close, close_err = file:close()
        if not ok_write then return nil, write_err end
        if not ok_close then return nil, close_err end
        return true
    end
    function fs.copyFile(source, destination)
        local input, read_err = io.open(source, "rb")
        if not input then return nil, read_err end
        local ok_make, make_err = fs.makePath(dirname(destination))
        if not ok_make then input:close(); return nil, make_err end
        local output, write_err = io.open(destination, "wb")
        if not output then input:close(); return nil, write_err end
        local ok, err = true, nil
        while true do
            local chunk = input:read(65536)
            if not chunk then break end
            if not output:write(chunk) then ok, err = nil, "write failed"; break end
        end
        input:close()
        local close_ok, close_err = output:close()
        if not ok then return nil, err end
        if not close_ok then return nil, close_err end
        return true
    end
    function fs.removeTree(path)
        local attributes = fs.symlinkAttributes(path)
        if not attributes then return true end
        if attributes.mode == "directory" then
            local names, list_err = fs.list(path)
            if not names then return nil, list_err end
            for _, name in ipairs(names) do
                local ok_remove, remove_err = fs.removeTree(join(path, name))
                if not ok_remove then return nil, remove_err end
            end
            return lfs.rmdir(path)
        end
        return os.remove(path)
    end
    function fs.rename(source, destination) return os.rename(source, destination) end
    function fs.uniqueSuffix()
        unique_counter = unique_counter + 1
        return tostring(os.time()) .. "-" .. tostring(unique_counter)
    end
    return fs
end

local function mode(fs, path, no_follow)
    local attributes = no_follow and fs.symlinkAttributes(path) or fs.attributes(path)
    return attributes and attributes.mode or nil
end

local function find_link(fs, path, relative)
    local current_mode = mode(fs, path, true)
    if current_mode == "link" or current_mode == "symlink" then return relative or "" end
    if current_mode ~= "directory" then return nil end
    local names, err = fs.list(path)
    if not names then return false, err end
    for _, name in ipairs(names) do
        local child_relative = relative and relative ~= "" and (relative .. "/" .. name) or name
        local found, find_err = find_link(fs, join(path, name), child_relative)
        if found ~= nil then return found, find_err end
    end
    return nil
end

local function read_manifest(fs, target)
    local content = fs.readFile(join(target, MANIFEST))
    if type(content) ~= "string" then return nil end
    local result = {}
    for line in (content .. "\n"):gmatch("([^\r\n]*)[\r\n]+") do
        if line ~= "" then
            if not safe_relative_path(line) or line == MANIFEST then return nil end
            result[line] = true
        end
    end
    return result
end

local function copy_preserved(fs, source, destination, shipped, relative)
    local names, list_err = fs.list(source)
    if not names then return nil, list_err end
    for _, name in ipairs(names) do
        local rel = relative == "" and name or (relative .. "/" .. name)
        local source_path, destination_path = join(source, name), join(destination, name)
        local current_mode = mode(fs, source_path, true)
        if current_mode == "directory" then
            local ok_make, make_err = fs.makePath(destination_path)
            if not ok_make then return nil, make_err end
            local ok_copy, copy_err = copy_preserved(fs, source_path, destination_path, shipped, rel)
            if not ok_copy then return nil, copy_err end
        elseif current_mode == "file" and rel ~= MANIFEST and (not shipped or not shipped[rel]) then
            local ok_copy, copy_err = fs.copyFile(source_path, destination_path)
            if not ok_copy then return nil, copy_err end
        elseif current_mode ~= "file" then
            return nil, "Unsupported existing entry at: " .. rel
        end
    end
    return true
end

local function cleanup(fs, path)
    if not mode(fs, path, true) then return true end
    return fs.removeTree(path)
end

local function fail_with_cleanup(fs, stage, message)
    local ok_remove, remove_err = cleanup(fs, stage)
    if not ok_remove then
        return false, message .. " Staging cleanup failed; inspect " .. stage .. ": " .. tostring(remove_err)
    end
    return false, message
end

function Archive.install(reader, info, dest_root, opts)
    opts = opts or {}
    local fs = opts.fs or default_fs()
    if type(dest_root) ~= "string" or dest_root == "" then return false, "Destination root is required." end
    if type(info) ~= "table" or not valid_plugin_dirname(info.plugin_dirname) then
        return false, "Plugin installation information is invalid."
    end
    if type(info.plugin_root) ~= "string" or (info.plugin_root ~= "" and not safe_relative_path(info.plugin_root)) then
        return false, "Plugin archive root is unsafe."
    end

    local scanned, scan_err = scan(reader)
    if not scanned then return false, scan_err end
    local root = info.plugin_root
    local prefix = root == "" and "" or (root .. "/")
    local archive_files = {}
    local meta_path, main_path = join(root, "_meta.lua"), join(root, "main.lua")
    for _, entry in ipairs(scanned.entries) do
        if entry.mode == "file" and (root == "" or entry.path:sub(1, #prefix) == prefix) then
            local relative = root == "" and entry.path or entry.path:sub(#prefix + 1)
            if relative == MANIFEST then return false, "Archive may not replace the install manifest." end
            archive_files[#archive_files + 1] = { archive = entry.path, relative = relative }
        end
    end
    if not scanned.files[meta_path] or not scanned.files[main_path] then
        return false, "Archive no longer contains main.lua and _meta.lua in the detected plugin directory."
    end
    table.sort(archive_files, function(a, b) return a.relative < b.relative end)

    local meta_source = reader:extractToMemory(meta_path)
    if type(meta_source) ~= "string" then return false, "Could not read plugin metadata before installation." end
    local archive_meta = Archive.readMeta(meta_source)
    if archive_meta.name and info.plugin_name and archive_meta.name ~= info.plugin_name then
        return false, "Archive metadata changed after detection; installation was refused."
    end

    local ok_root, root_err = fs.makePath(dest_root)
    if not ok_root then return false, "Could not create plugin directory: " .. tostring(root_err) end
    local target = join(dest_root, info.plugin_dirname)
    local target_mode = mode(fs, target, true)
    if target_mode and target_mode ~= "directory" then
        return false, "Installation target exists but is not a directory: " .. target
    end
    if target_mode == "directory" then
        local link, link_err = find_link(fs, target, "")
        if link == false then return false, "Could not inspect existing plugin: " .. tostring(link_err) end
        if link ~= nil then return false, "Existing plugin contains a symbolic link at: " .. link end
        local existing_source = fs.readFile(join(target, "_meta.lua"))
        if type(existing_source) ~= "string" then
            return false, "Existing target cannot be identified safely; _meta.lua is missing or unreadable."
        end
        local existing_name = Archive.readMeta(existing_source).name
        if not existing_name or existing_name == "" then
            return false, "Existing target cannot be identified safely because metadata has no literal name."
        end
        local incoming_name = archive_meta.name or info.plugin_name
        if not incoming_name or incoming_name == "" or existing_name ~= incoming_name then
            return false, "Installation target belongs to a different plugin: " .. existing_name
        end
    end

    local suffix = fs.uniqueSuffix()
    local stage = target .. ".qiqi-stage-" .. tostring(suffix)
    local backup = target .. ".qiqi-backup-" .. tostring(suffix)
    if mode(fs, stage, true) or mode(fs, backup, true) then
        return false, "Could not allocate a unique transactional installation path."
    end
    local ok_stage, stage_err = fs.makePath(stage)
    if not ok_stage then return false, "Could not create staging directory: " .. tostring(stage_err) end

    if target_mode == "directory" then
        local shipped = read_manifest(fs, target)
        local ok_copy, copy_err = copy_preserved(fs, target, stage, shipped, "")
        if not ok_copy then
            return fail_with_cleanup(fs, stage, "Could not preserve local plugin files: " .. tostring(copy_err))
        end
    end

    rewind(reader)
    for _, entry in ipairs(archive_files) do
        local destination = join(stage, entry.relative)
        local ok_parent, parent_err = fs.makePath(dirname(destination))
        if not ok_parent then
            return fail_with_cleanup(fs, stage, "Could not create staging subdirectory: " .. tostring(parent_err))
        end
        local ok_extract, extract_err = reader:extractToPath(entry.archive, destination)
        if not ok_extract then
            return fail_with_cleanup(fs, stage,
                "Failed to extract archive entry " .. entry.archive .. ": " .. tostring(extract_err))
        end
    end

    for _, entry in ipairs(archive_files) do
        if mode(fs, join(stage, entry.relative), true) ~= "file" then
            return fail_with_cleanup(fs, stage,
                "Staged plugin validation failed: extracted file is missing: " .. entry.relative)
        end
    end

    local manifest_lines = {}
    for _, entry in ipairs(archive_files) do manifest_lines[#manifest_lines + 1] = entry.relative end
    local ok_manifest, manifest_err = fs.writeFile(join(stage, MANIFEST), table.concat(manifest_lines, "\n") .. "\n")
    if not ok_manifest then
        return fail_with_cleanup(fs, stage, "Could not write install manifest: " .. tostring(manifest_err))
    end
    if mode(fs, join(stage, "main.lua"), true) ~= "file" or mode(fs, join(stage, "_meta.lua"), true) ~= "file" then
        return fail_with_cleanup(fs, stage, "Staged plugin validation failed: required entry files are missing.")
    end
    local staged_link, staged_link_err = find_link(fs, stage, "")
    if staged_link == false then
        return fail_with_cleanup(fs, stage, "Could not validate staged plugin: " .. tostring(staged_link_err))
    end
    if staged_link ~= nil then
        return fail_with_cleanup(fs, stage, "Staged plugin contains a symbolic link at: " .. staged_link)
    end

    if target_mode == "directory" then
        local ok_backup, backup_err = fs.rename(target, backup)
        if not ok_backup then
            return fail_with_cleanup(fs, stage, "Could not prepare existing plugin for replacement: " .. tostring(backup_err))
        end
    end
    local ok_replace, replace_err = fs.rename(stage, target)
    if not ok_replace then
        local rollback_ok, rollback_err = true, nil
        if target_mode == "directory" then rollback_ok, rollback_err = fs.rename(backup, target) end
        local cleanup_ok, cleanup_err = cleanup(fs, stage)
        local message = "Could not replace plugin with staged installation: " .. tostring(replace_err)
        if not rollback_ok then
            message = message .. "; rollback failed, recover the old plugin from " .. backup .. ": " .. tostring(rollback_err)
        end
        if not cleanup_ok then message = message .. "; staging remains at " .. stage .. ": " .. tostring(cleanup_err) end
        return false, message
    end

    if target_mode == "directory" then
        local ok_cleanup, cleanup_err = cleanup(fs, backup)
        if not ok_cleanup then
            return false, "Plugin was installed, but backup cleanup failed; recoverable backup remains at "
                .. backup .. ": " .. tostring(cleanup_err)
        end
    end
    return true, target
end

return Archive
