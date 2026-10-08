local ok, Policy = pcall(require, 'qiqiappstore_policy')
assert(ok, 'account policy must exist before scoped discovery can run')
assert(Policy.allows('bailigebai', 'future-plugin.koplugin'))
assert(Policy.allows('BAILIGEBAI', 'new.koplugin'))
for _, name in ipairs({'x.koplugin.zip', 'xkoplugin', '../x.koplugin', 'x/y.koplugin', '.koplugin', 'x.KOPLUGIN'}) do
    assert(not Policy.allows('bailigebai', name), 'must reject nonliteral suffix or unsafe name: ' .. name)
end
assert(not Policy.allows('someoneelse', 'new.koplugin'))
assert(not Policy.allows('bailigebai.evil', 'new.koplugin'))
assert(Policy.accepts({owner={login='bailigebai'}, name='new.koplugin', private=false, fork=true, stargazers_count=0}))
assert(not Policy.accepts({owner={login='bailigebai'}, name='new.koplugin', private=true}))
assert(not Policy.accepts({owner='bailigebai', name='new.koplugin', full_name='other/new.koplugin'}))
local function tree(paths)
    local entries={}
    for _, p in ipairs(paths) do entries[#entries+1]={path=p,type='blob',mode='100644'} end
    return {tree=entries,truncated=false}
end
local p=assert(Policy.pluginFromTree(tree({'inkgomoku.koplugin/_meta.lua','inkgomoku.koplugin/main.lua','README.md'}),'wuziqi.koplugin'))
assert(p.dirname=='inkgomoku.koplugin' and p.meta_path=='inkgomoku.koplugin/_meta.lua')
assert(Policy.pluginFromTree(tree({'README.md'}),'legado.koplugin')==nil)
assert(Policy.pluginFromTree(tree({'_meta.lua'}),'new.koplugin')==nil)
local root=assert(Policy.pluginFromTree(tree({'_meta.lua','main.lua'}),'qiqiappstore.koplugin'))
assert(root.dirname=='qiqiappstore.koplugin' and root.meta_path=='_meta.lua')
assert(not Policy.pluginFromTree(tree({'a.koplugin/_meta.lua','a.koplugin/main.lua','b.koplugin/_meta.lua','b.koplugin/main.lua'}),'new.koplugin'))
assert(not Policy.pluginFromTree({truncated=true,tree={}},'new.koplugin'))
assert(not Policy.pluginFromTree(tree({'../_meta.lua','../main.lua'}),'new.koplugin'))
print('policy: future names, owner/suffix, public scope, alias and installability checked')

local repo={owner='bailigebai',name='wuziqi.koplugin',repo_id=42,data={private=false,qiqi_layout={dirname='inkgomoku.koplugin'}}}
local record={owner='bailigebai',repo='wuziqi.koplugin',repo_id=42,dirname='inkgomoku.koplugin',repo_full_name='bailigebai/wuziqi.koplugin',plugin_name='inkgomoku'}
assert(Policy.recordMatches(record,repo,'inkgomoku.koplugin'))
assert(not Policy.recordMatches(record,repo,'unrelated.koplugin'))
record.repo_full_name='other/wuziqi.koplugin'; assert(not Policy.recordMatches(record,repo,'inkgomoku.koplugin'))
record.repo_full_name='bailigebai/wuziqi.koplugin';record.repo_id=99;assert(not Policy.recordMatches(record,repo,'inkgomoku.koplugin'))
