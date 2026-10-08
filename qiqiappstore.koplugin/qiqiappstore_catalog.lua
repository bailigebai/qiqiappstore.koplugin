-- Public, account-scoped snapshot for devices that cannot use the GitHub API.
-- It contains data only; downloading still goes through the normal safe installer.
local json = require('json')
local Net = require('qiqiappstore_net')
local Policy = require('qiqiappstore_policy')
local Catalog = {}
local INDEX_URL = 'https://raw.githubusercontent.com/bailigebai/qiqiappstore.koplugin/main/catalog.json'
local MAX_AGE, CACHE_SECONDS = 86400, 60
local cached, fetched_at

local function array(value)
    if type(value) ~= 'table' then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key > #value or key % 1 ~= 0 then return false end
        count = count + 1
    end
    return count == #value
end

local function safePath(path)
    return type(path) == 'string' and path ~= '' and path:sub(1,1) ~= '/'
        and not path:find('\\',1,true) and not path:find(':',1,true)
        and not path:find('%c') and path ~= '..' and not path:match('^%.%./')
        and not path:match('/%.%./') and not path:match('/%.%.$')
end

local function under(target, prefix)
    return type(target) == 'string' and target:sub(1,#prefix) == prefix
        and safePath(target:sub(#prefix + 1))
end

local function validRelease(release, full_name)
    if release == false then return true end
    if type(release) ~= 'table' or release.draft ~= false or not array(release.assets) then return false end
    local api = 'https://api.github.com/repos/' .. full_name .. '/'
    if release.url and not under(release.url, api .. 'releases/') then return false end
    if release.zipball_url and not under(release.zipball_url, api .. 'zipball/') then return false end
    if release.tarball_url and not under(release.tarball_url, api .. 'tarball/') then return false end
    if release.html_url and not under(release.html_url, 'https://github.com/' .. full_name .. '/releases/tag/') then return false end
    for _, asset in ipairs(release.assets) do
        if type(asset) ~= 'table' or type(asset.name) ~= 'string'
            or not under(asset.browser_download_url, 'https://github.com/' .. full_name .. '/releases/download/')
            or (asset.url and not under(asset.url, api .. 'releases/assets/')) then return false end
    end
    return true
end

local function validIndex(document, now)
    if type(document) ~= 'table' or document.schema_version ~= 1 or document.owner ~= Policy.owner
        or type(document.generated_at) ~= 'number' or document.generated_at % 1 ~= 0
        or document.generated_at > now + 300 or document.generated_at < now - MAX_AGE
        or not array(document.repos) then return false end
    local seen = {}
    for _, entry in ipairs(document.repos) do
        local metadata = type(entry) == 'table' and entry.metadata
        if not Policy.accepts(metadata) or metadata.private ~= false
            or type(metadata.full_name) ~= 'string' or type(metadata.id) ~= 'number'
            or type(metadata.default_branch) ~= 'string' or metadata.default_branch == '' then return false end
        local identity = metadata.full_name:lower()
        if seen[identity] then return false end
        seen[identity] = true
        local tree = entry.tree
        if type(tree) ~= 'table' or tree.truncated ~= false or not array(tree.tree)
            or type(tree.sha) ~= 'string' or not tree.sha:match('^[0-9a-f]+$')
            or (#tree.sha ~= 40 and #tree.sha ~= 64)
            or tree.url ~= 'https://api.github.com/repos/' .. metadata.full_name .. '/git/trees/' .. tree.sha then return false end
        for _, file in ipairs(tree.tree) do
            if type(file) ~= 'table' or not safePath(file.path)
                or (file.type ~= 'blob' and file.type ~= 'tree' and file.type ~= 'commit') then return false end
        end
        if not validRelease(entry.release, metadata.full_name) then return false end
    end
    return true
end

--- Return validated entries {metadata, tree, release}; absent releases are false.
--- A failed or stale snapshot is never cached or returned as current data.
function Catalog.load()
    local now = os.time()
    if cached and now >= fetched_at and now - fetched_at < CACHE_SECONDS
        and cached.generated_at >= now - MAX_AGE and cached.generated_at <= now + 300 then
        return cached.repos
    end
    local body = {}
    local ok, code = pcall(Net.requestToTable, {
        url=INDEX_URL, headers={['User-Agent']='KOReader-QiqiAppStore', ['Accept']='application/json'},
    }, body)
    if not ok or tonumber(code) ~= 200 then
        return nil, '无法读取公开插件索引，请检查网络后重试。'
    end
    local decoded, document = pcall(function() return json.decode(table.concat(body)) end)
    if not decoded or not validIndex(document, now) then
        return nil, '公开插件索引不完整、已过期或不属于本账号，请稍后重试。'
    end
    cached, fetched_at = document, now
    return document.repos
end

return Catalog
