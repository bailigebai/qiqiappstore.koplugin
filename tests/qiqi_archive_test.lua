local ok, Archive = pcall(require, "qiqiappstore_archive")
assert(ok, "transactional archive module must exist")

local function contains(value, needle)
    return type(value) == "string" and value:find(needle, 1, true) ~= nil
end

local function make_fs(initial)
    local fs = { nodes = { [""] = { mode = "directory" } }, serial = 0 }

    local function parent(path)
        return path:match("^(.*)/[^/]+$") or ""
    end

    function fs.makePath(path)
        local current = ""
        for part in path:gmatch("[^/]+") do
            current = current == "" and part or current .. "/" .. part
            if not fs.nodes[current] then
                fs.nodes[current] = { mode = "directory" }
            elseif fs.nodes[current].mode ~= "directory" then
                return nil, "not a directory: " .. current
            end
        end
        return true
    end

    function fs.writeFile(path, content)
        local dir = parent(path)
        local ok_make, err = fs.makePath(dir)
        if not ok_make then return nil, err end
        fs.nodes[path] = { mode = "file", content = content }
        return true
    end

    function fs.readFile(path)
        local node = fs.nodes[path]
        if not node or node.mode ~= "file" then return nil, "not a file" end
        return node.content
    end

    function fs.attributes(path)
        local node = fs.nodes[path]
        return node and { mode = node.mode } or nil
    end

    function fs.symlinkAttributes(path)
        return fs.attributes(path)
    end

    function fs.list(path)
        local prefix = path == "" and "" or path .. "/"
        local seen, result = {}, {}
        for candidate in pairs(fs.nodes) do
            if candidate:sub(1, #prefix) == prefix then
                local rest = candidate:sub(#prefix + 1)
                local name = rest:match("^([^/]+)$")
                if name and name ~= "" and not seen[name] then
                    seen[name] = true
                    result[#result + 1] = name
                end
            end
        end
        table.sort(result)
        return result
    end

    function fs.copyFile(source, destination)
        local content, err = fs.readFile(source)
        if not content then return nil, err end
        return fs.writeFile(destination, content)
    end

    function fs.removeTree(path)
        if fs.fail_remove and fs.fail_remove(path) then
            return nil, "injected remove failure"
        end
        for candidate in pairs(fs.nodes) do
            if candidate == path or candidate:sub(1, #path + 1) == path .. "/" then
                fs.nodes[candidate] = nil
            end
        end
        return true
    end

    function fs.rename(source, destination)
        if fs.fail_rename and fs.fail_rename(source, destination) then
            return nil, "injected rename failure"
        end
        if not fs.nodes[source] then return nil, "source missing" end
        if fs.nodes[destination] then return nil, "destination exists" end
        local moved = {}
        for candidate, node in pairs(fs.nodes) do
            if candidate == source or candidate:sub(1, #source + 1) == source .. "/" then
                moved[candidate] = node
            end
        end
        for candidate in pairs(moved) do fs.nodes[candidate] = nil end
        for candidate, node in pairs(moved) do
            fs.nodes[destination .. candidate:sub(#source + 1)] = node
        end
        return true
    end

    function fs.uniqueSuffix()
        fs.serial = fs.serial + 1
        return "test" .. fs.serial
    end

    for path, value in pairs(initial or {}) do
        if type(value) == "table" and value.mode == "link" then
            fs.makePath(parent(path))
            fs.nodes[path] = { mode = "link", target = value.target }
        elseif value == true then
            fs.makePath(path)
        else
            assert(fs.writeFile(path, value))
        end
    end
    return fs
end

local function reader(entries, fs, fail_path)
    local r = { entries = entries, fs = fs, fail_path = fail_path }
    function r:rewind() self.rewound = (self.rewound or 0) + 1 end
    function r:iterate()
        local index = 0
        return function()
            index = index + 1
            return self.entries[index]
        end
    end
    function r:extractToMemory(path)
        for _, entry in ipairs(self.entries) do
            if entry.path == path then return entry.content end
        end
    end
    function r:extractToPath(path, destination)
        if path == self.fail_path then return nil, "injected extraction failure" end
        local content = self:extractToMemory(path)
        if content == nil then return nil, "archive entry missing" end
        return self.fs.writeFile(destination, content)
    end
    return r
end

local function files(spec)
    local result = {}
    for path, content in pairs(spec) do
        result[#result + 1] = { path = path, mode = "file", content = content }
    end
    table.sort(result, function(a, b) return a.path < b.path end)
    return result
end

local meta = 'return { name = "Game", fullname = "A game", version = "2.0" }'

do
    _G.QIQI_META_EXECUTED = nil
    local parsed = Archive.readMeta([[return {
        fullname = "Wrong Name",
        name = "Right Name",
        version = '1.2.3',
        run = (function() _G.QIQI_META_EXECUTED = true end)(),
    }]])
    assert(parsed.name == "Right Name", "name must not be read from fullname suffix")
    assert(parsed.version == "1.2.3")
    assert(_G.QIQI_META_EXECUTED == nil, "metadata reader must never execute archive code")
end

do
    local r = reader(files({
        ["repo-ref/inkgomoku.koplugin/_meta.lua"] = meta,
        ["repo-ref/inkgomoku.koplugin/main.lua"] = "return true",
        ["repo-ref/README.md"] = "docs",
    }))
    local info = assert(Archive.detect(r, { name = "wuziqi.koplugin" }))
    assert(info.plugin_root == "repo-ref/inkgomoku.koplugin")
    assert(info.plugin_dirname == "inkgomoku.koplugin", "inner plugin directory is the install identity")
    assert(info.plugin_name == "Game" and info.plugin_version == "2.0")
end

do
    local r = reader(files({ ["_meta.lua"] = meta, ["main.lua"] = "return true" }))
    local info = assert(Archive.detect(r, { name = "rootless.koplugin" }))
    assert(info.plugin_root == "" and info.plugin_dirname == "rootless.koplugin")
end

do
    local no_main, err_main = Archive.detect(reader(files({ ["p.koplugin/_meta.lua"] = meta })), { name = "p.koplugin" })
    assert(no_main == nil and contains(err_main, "main.lua"))
    local no_meta, err_meta = Archive.detect(reader(files({ ["p.koplugin/main.lua"] = "x" })), { name = "p.koplugin" })
    assert(no_meta == nil and contains(err_meta, "_meta.lua"))
end

do
    local _, err = Archive.detect(reader(files({
        ["a.koplugin/_meta.lua"] = meta, ["a.koplugin/main.lua"] = "a",
        ["b.koplugin/_meta.lua"] = meta, ["b.koplugin/main.lua"] = "b",
    })), { name = "repo.koplugin" })
    assert(contains(err, "多个"), "ambiguous archives must be refused")
end

-- WebDAV's repair ZIP also carries graydither. The freshly inspected repository
-- layout identifies the one plugin selected by the user; companions stay out.
do
    local Policy = require("qiqiappstore_policy")
    local layout = assert(Policy.pluginFromTree({ tree = {
        { path = "webdavmanga.koplugin/_meta.lua", type = "blob" },
        { path = "webdavmanga.koplugin/main.lua", type = "blob" },
    } }, "webdavmanga.koplugin"))
    local bundle = {
        ["repair/webdavmanga.koplugin/_meta.lua"] = 'error("must not execute"); return {name="webdavmanga",version="0.4.21"}',
        ["repair/webdavmanga.koplugin/main.lua"] = "webdav main",
        ["repair/webdavmanga.koplugin/lib.lua"] = "webdav helper",
        ["repair/graydither.koplugin/_meta.lua"] = 'error("must not execute"); return {name="graydither"}',
        ["repair/graydither.koplugin/main.lua"] = "companion main",
        ["repair/README.md"] = "bundle instructions",
    }
    local function scoped_repo(overrides)
        local repo = {
            owner = "bailigebai", name = "webdavmanga.koplugin",
            full_name = "bailigebai/webdavmanga.koplugin", qiqi_layout = layout,
        }
        for key, value in pairs(overrides or {}) do repo[key] = value end
        return repo
    end

    local fs = make_fs()
    local r = reader(files(bundle), fs)
    local info, err = Archive.detect(r, scoped_repo())
    assert(info, "a scoped bundle must identify its unique target plugin: " .. tostring(err))
    assert(info.plugin_root == "repair/webdavmanga.koplugin")
    assert(info.plugin_dirname == "webdavmanga.koplugin")
    local installed, path = Archive.install(r, info, "plugins", { fs = fs })
    assert(installed and path == "plugins/webdavmanga.koplugin")
    assert(fs.readFile(path .. "/main.lua") == "webdav main")
    assert(fs.readFile(path .. "/lib.lua") == "webdav helper")
    assert(fs.attributes("plugins/graydither.koplugin") == nil,
        "bundled companion plugins must not be installed implicitly")
    assert(fs.attributes("plugins/README.md") == nil)

    local existing_fs = make_fs({
        ["plugins/graydither.koplugin/_meta.lua"] = 'return {name="graydither"}',
        ["plugins/graydither.koplugin/main.lua"] = "existing companion",
    })
    local existing_reader = reader(files(bundle), existing_fs)
    local selected = assert(Archive.detect(existing_reader, scoped_repo()))
    assert(Archive.install(existing_reader, selected, "plugins", { fs = existing_fs }))
    assert(existing_fs.readFile("plugins/graydither.koplugin/main.lua") == "existing companion",
        "an already installed companion must not be upgraded as a bundle side effect")

    for _, repo in ipairs({
        scoped_repo({ qiqi_layout = false }),
        scoped_repo({ qiqi_layout = "invalid" }),
        scoped_repo({ qiqi_layout = { dirname = "../webdavmanga.koplugin" } }),
        scoped_repo({ qiqi_layout = { dirname = "mangaweb.koplugin" } }),
        scoped_repo({ owner = "other" }),
        scoped_repo({ full_name = "bailigebai/other.koplugin" }),
        scoped_repo({ private = true }),
        scoped_repo({ data = { private = true } }),
    }) do
        assert(Archive.detect(reader(files(bundle)), repo) == nil,
            "ambiguous archives require an allowed repository with a matching checked layout")
    end
    local no_layout = scoped_repo()
    no_layout.qiqi_layout = nil
    assert(Archive.detect(reader(files(bundle)), no_layout) == nil)

    local duplicate = {}
    for path, content in pairs(bundle) do duplicate[path] = content end
    duplicate["other/webdavmanga.koplugin/_meta.lua"] = bundle["repair/webdavmanga.koplugin/_meta.lua"]
    duplicate["other/webdavmanga.koplugin/main.lua"] = "second target"
    assert(Archive.detect(reader(files(duplicate)), scoped_repo()) == nil,
        "two candidate directories with the same checked basename must remain ambiguous")

    local nested = {
        ["repair/webdavmanga.koplugin/_meta.lua"] = bundle["repair/webdavmanga.koplugin/_meta.lua"],
        ["repair/webdavmanga.koplugin/main.lua"] = "webdav main",
        ["repair/webdavmanga.koplugin/graydither.koplugin/_meta.lua"] = 'return {name="graydither"}',
        ["repair/webdavmanga.koplugin/graydither.koplugin/main.lua"] = "nested companion",
    }
    assert(Archive.detect(reader(files(nested)), scoped_repo()) == nil,
        "selecting a root must not cause nested companion plugins to be extracted")

    local unsafe = {}
    for path, content in pairs(bundle) do unsafe[path] = content end
    unsafe["repair/graydither.koplugin/../../escape"] = "outside"
    local rejected, unsafe_err = Archive.detect(reader(files(unsafe)), scoped_repo())
    assert(rejected == nil and contains(unsafe_err, "unsafe"),
        "the complete archive must still be checked for unsafe companion paths")
end

for _, unsafe in ipairs({ "../escape", "dir/../escape", "dir\\escape", "/absolute", "C:/absolute" }) do
    local entries = files({ ["p.koplugin/_meta.lua"] = meta, ["p.koplugin/main.lua"] = "x", [unsafe] = "bad" })
    local info, err = Archive.detect(reader(entries), { name = "p.koplugin" })
    assert(info == nil and contains(err, "unsafe"), "unsafe archive path accepted: " .. unsafe)
end

do
    local entries = files({ ["p.koplugin/_meta.lua"] = meta, ["p.koplugin/main.lua"] = "x" })
    entries[#entries + 1] = { path = "p.koplugin/link", mode = "symlink" }
    local info, err = Archive.detect(reader(entries), { name = "p.koplugin" })
    assert(info == nil and contains(err, "link"), "archive links must be refused")
end

do
    local damaged = reader(files({
        ["p.koplugin/_meta.lua"] = meta,
        ["p.koplugin/main.lua"] = "partial main",
    }))
    damaged.err = "truncated archive"
    local info, err = Archive.detect(damaged, { name = "p.koplugin" })
    assert(info == nil and contains(err, "truncated archive"),
        "reader errors after partial iteration must reject the archive")
end

local function install_reader(fs, overrides)
    local spec = {
        ["bundle/game.koplugin/_meta.lua"] = meta,
        ["bundle/game.koplugin/main.lua"] = "new main",
        ["bundle/game.koplugin/new.lua"] = "new code",
    }
    for path, content in pairs(overrides or {}) do spec[path] = content end
    return reader(files(spec), fs), {
        plugin_root = "bundle/game.koplugin",
        plugin_dirname = "game.koplugin",
        plugin_name = "Game",
        plugin_version = "2.0",
    }
end

do
    local fs = make_fs({
        ["plugins/game.koplugin/_meta.lua"] = 'return { name = "Game" }',
        ["plugins/game.koplugin/main.lua"] = "old main",
        ["plugins/game.koplugin/user.cfg"] = "keep me",
    })
    local r, info = install_reader(fs)
    r.fail_path = "bundle/game.koplugin/new.lua"
    local installed, err = Archive.install(r, info, "plugins", { fs = fs })
    assert(not installed and contains(err, "extract"))
    assert(fs.readFile("plugins/game.koplugin/main.lua") == "old main")
    assert(fs.readFile("plugins/game.koplugin/user.cfg") == "keep me")
end

do
    local fs = make_fs({
        ["plugins/game.koplugin/_meta.lua"] = 'return { name = "Game" }',
        ["plugins/game.koplugin/main.lua"] = "old main",
    })
    local r, info = install_reader(fs)
    local extract = r.extractToPath
    function r:extractToPath(path, destination)
        if path == "bundle/game.koplugin/new.lua" then return true end
        return extract(self, path, destination)
    end
    local installed, err = Archive.install(r, info, "plugins", { fs = fs })
    assert(not installed and contains(err, "validation"),
        "a reader that reports success without creating every file must be detected")
    assert(fs.readFile("plugins/game.koplugin/main.lua") == "old main")
end

do
    local fs = make_fs({
        ["plugins/game.koplugin/_meta.lua"] = 'return { name = "Game" }',
        ["plugins/game.koplugin/main.lua"] = "old main",
        ["plugins/game.koplugin/stale.lua"] = "old shipped code",
        ["plugins/game.koplugin/user.cfg"] = "local config",
        ["plugins/game.koplugin/.qiqiappstore-install-manifest"] = "_meta.lua\nmain.lua\nstale.lua\n",
    })
    local r, info = install_reader(fs)
    local installed, path = Archive.install(r, info, "plugins", { fs = fs })
    assert(installed and path == "plugins/game.koplugin")
    assert(fs.readFile(path .. "/main.lua") == "new main")
    assert(fs.readFile(path .. "/new.lua") == "new code")
    assert(fs.attributes(path .. "/stale.lua") == nil, "old shipped files must be removed")
    assert(fs.readFile(path .. "/user.cfg") == "local config", "local config must survive upgrade")
    local manifest = assert(fs.readFile(path .. "/.qiqiappstore-install-manifest"))
    assert(contains(manifest, "main.lua\n") and contains(manifest, "new.lua\n"))
end

do
    local fs = make_fs({
        ["plugins/game.koplugin/_meta.lua"] = 'return { name = "Game" }',
        ["plugins/game.koplugin/main.lua"] = "old main",
        ["plugins/game.koplugin/legacy.lua"] = "unknown ownership",
    })
    local r, info = install_reader(fs)
    assert(Archive.install(r, info, "plugins", { fs = fs }))
    assert(fs.readFile("plugins/game.koplugin/legacy.lua") == "unknown ownership",
        "an old install without a manifest must be preserved conservatively")
end

do
    local fs = make_fs({
        ["plugins/game.koplugin/_meta.lua"] = 'return { name = "Game" }',
        ["plugins/game.koplugin/main.lua"] = "old main",
    })
    fs.fail_rename = function(source, destination)
        return contains(source, ".qiqi-stage-") and destination == "plugins/game.koplugin"
    end
    local r, info = install_reader(fs)
    local installed, err = Archive.install(r, info, "plugins", { fs = fs })
    assert(not installed and contains(err, "replace"))
    assert(fs.readFile("plugins/game.koplugin/main.lua") == "old main", "rename failure must roll back")
end

do
    local fs = make_fs({
        ["plugins/game.koplugin/_meta.lua"] = 'return { name = "Other Plugin" }',
        ["plugins/game.koplugin/main.lua"] = "other main",
    })
    local r, info = install_reader(fs)
    local installed, err = Archive.install(r, info, "plugins", { fs = fs })
    assert(not installed and contains(err, "different plugin"))
    assert(fs.readFile("plugins/game.koplugin/main.lua") == "other main")
    assert(fs.serial == 0, "collision must be refused before creating staging paths")
end

do
    local fs = make_fs({
        ["plugins/game.koplugin/_meta.lua"] = 'return { name = "Game" }',
        ["plugins/game.koplugin/main.lua"] = "old main",
        ["plugins/game.koplugin/user-link"] = { mode = "link", target = "outside" },
    })
    local r, info = install_reader(fs)
    local installed, err = Archive.install(r, info, "plugins", { fs = fs })
    assert(not installed and contains(err, "symbolic link"))
    assert(fs.readFile("plugins/game.koplugin/main.lua") == "old main")
end

print("archive: safe detection, static metadata, transactional upgrade and rollback checked")

-- KOReader permits metadata without a name; pluginhealth 0.1.2 uses this layout.
do
    local legacy_meta = 'return { fullname = "Plugin Health", version = "0.1.2" }'
    local function attempt(existing_main, incoming_main, old_meta)
        local fs = make_fs({
            ["plugins/pluginhealth.koplugin/_meta.lua"] = old_meta or legacy_meta,
            ["plugins/pluginhealth.koplugin/main.lua"] = existing_main,
            ["plugins/pluginhealth.koplugin/user.cfg"] = "keep settings",
        })
        local r = reader(files({
            ["bundle/pluginhealth.koplugin/_meta.lua"] = legacy_meta,
            ["bundle/pluginhealth.koplugin/main.lua"] = incoming_main,
        }), fs)
        local info = assert(Archive.detect(r, { name = "pluginhealth.koplugin" }))
        local installed, err = Archive.install(r, info, "plugins", { fs = fs })
        return installed, err, fs
    end
    local old = 'local P = Widget:extend{ name = "pluginhealth" }; return P'
    local new = 'error("must never execute"); local P = Widget:extend{ name = "pluginhealth" }; return P'
    local installed, err, fs = attempt(old, new)
    assert(installed, "valid legacy pluginhealth install must upgrade: " .. tostring(err))
    assert(fs.readFile("plugins/pluginhealth.koplugin/main.lua") == new)
    assert(fs.readFile("plugins/pluginhealth.koplugin/user.cfg") == "keep settings")
    for _, pair in ipairs({
        {'return {}', new},
        {'local example = [[name = "pluginhealth"]]; return Widget:extend{ name = "other" }', new},
        {'local example = { name = "pluginhealth" }; return Widget:extend{ name = "other" }', new},
        {'local P = Widget:extend{ name = "pluginhealth" .. "other" }; return P', new},
        {'local P = Widget:extend{ name = "pluginhealth", name = "other" }; return P', new},
        {'local P = Widget:extend{ name = "pluginhealth" }; return Other', new},
        {'return { name = "other" }', new},
        {old, 'return { name = "other" }'},
        {old, 'return {}'},
        {'local P = Widget:extend{ name = "pluginhealth", ["name"] = "other" }; return P', new},
    }) do
        local ok, _, rejected_fs = attempt(pair[1], pair[2])
        assert(not ok and rejected_fs.serial == 0, "unverified identity must remain protected")
        assert(rejected_fs.readFile("plugins/pluginhealth.koplugin/main.lua") == pair[1])
    end
    assert(not attempt(old, new, 'return {name="other"}'), "explicit conflicting metadata must win")
end
