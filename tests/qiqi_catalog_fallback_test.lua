-- The public index is an API fallback, never a reason to widen account scope.
local now, calls, decoded, http_code, network_error = 200000, 0, nil, 200, nil
package.preload['json'] = function() return {decode=function()
    if decoded == 'invalid json' then error('decode failed') end
    return decoded
end} end
package.preload['qiqiappstore_net'] = function() return {requestToTable=function(request, body)
    calls = calls + 1
    assert(request.url == 'https://raw.githubusercontent.com/bailigebai/qiqiappstore.koplugin/main/catalog.json')
    assert(request.headers.Authorization == nil, 'the public index must not receive credentials')
    body[1] = 'fixture'
    return http_code, {}, network_error
end} end
os.time = function() return now end

local function index(name)
    name = name or 'future.koplugin'
    local full_name = 'bailigebai/' .. name
    local sha = string.rep('a', 40)
    return {schema_version=1, owner='bailigebai', generated_at=now, repos={{
        metadata={id=123, owner={login='bailigebai'}, name=name, full_name=full_name,
            private=false, default_branch='main'},
        tree={sha=sha, url='https://api.github.com/repos/' .. full_name .. '/git/trees/' .. sha,
            truncated=false, tree={{path='_meta.lua', type='blob', mode='100644'},
                {path='main.lua', type='blob', mode='100644'}}},
        release={id=1, draft=false, assets={{id=2, name=name .. '-v1.zip',
            browser_download_url='https://github.com/' .. full_name .. '/releases/download/v1/' .. name .. '-v1.zip'}}},
    }}}
end
local function fresh()
    package.loaded['qiqiappstore_catalog'] = nil
    return require('qiqiappstore_catalog')
end
local function reject(value, message)
    decoded = value
    local repos, err = fresh().load()
    assert(repos == nil and type(err) == 'string', message)
end

local loaded, Catalog = pcall(fresh)
assert(loaded, 'public catalog fallback is not implemented')
decoded = index()
local repos = assert(Catalog.load())
assert(#repos == 1 and repos[1].metadata.name == 'future.koplugin', 'new suffix plugins must remain discoverable')
local before = calls
assert(Catalog.load() == repos and calls == before, 'one operation must reuse the successful index')
now = now + 61
decoded = index('another.koplugin')
assert(Catalog.load()[1].metadata.name == 'another.koplugin' and calls == before + 1, 'short cache must expire')

reject('invalid json', 'broken JSON must fail closed')
reject({message='not an index'}, 'malformed successful response must fail closed')
local broken = index(); broken.generated_at = now - 86401
reject(broken, 'stale index must not authorize installation')
broken = index(); broken.generated_at = now + 301
reject(broken, 'far future timestamps must be rejected')
broken = index(); broken.owner = 'someoneelse'
reject(broken, 'foreign index owner must be rejected')
broken = index(); broken.repos[1].metadata.owner.login = 'someoneelse'
reject(broken, 'foreign repo must be rejected')
broken = index(); broken.repos[1].metadata.private = true
reject(broken, 'private repo must be rejected')
broken = index(); broken.repos[1].metadata.private = nil
reject(broken, 'unknown privacy must be rejected')
broken = index(); broken.repos[2] = broken.repos[1]
reject(broken, 'duplicate identity must reject the complete index')
broken = index(); broken.repos.bad = broken.repos[1]
reject(broken, 'repos must be an array')
broken = index(); broken.repos[3] = broken.repos[1]
reject(broken, 'array holes must reject the complete index')
broken = index(); broken.repos = {broken.repos[1], broken.repos[1], broken.repos[1], broken.repos[1]}; broken.repos[2] = nil
reject(broken, 'a JSON null hole must not hide later duplicate or foreign repositories')
broken = index(); broken.repos[1].tree.truncated = true
reject(broken, 'truncated tree must reject the complete index')
broken = index(); broken.repos[1].tree.url = 'https://api.github.com/repos/bailigebai/other.koplugin/git/trees/' .. string.rep('a', 40)
reject(broken, 'tree must belong to the same repository')
broken = index(); broken.repos[1].release.assets[1].browser_download_url = 'https://github.com/elsewhere/plugin.koplugin/releases/download/v1/plugin.zip'
reject(broken, 'release assets must remain inside the same public repository')

http_code, network_error = 'sink timeout', 'timeout'
decoded = index()
Catalog = fresh()
local result, err = Catalog.load()
assert(result == nil and type(err) == 'string', 'network failures must be reported')
http_code, network_error = 200, nil
assert(Catalog.load(), 'a failed fetch must not poison the next attempt')
decoded = {schema_version=1, owner='bailigebai', generated_at=now, repos={}}
assert(#assert(fresh().load()) == 0, 'a verified empty account is valid')
print('public catalog: cache, new suffixes, malformed/expired/foreign/private indices, tree and asset scope, network recovery checked')
