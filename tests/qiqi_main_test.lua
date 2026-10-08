package.path = 'qiqiappstore.koplugin/?.lua;' .. package.path
-- Only KOReader's platform/UI boundary is substituted. Execute actual main methods.
local shown, writes, rows = {}, {}, {}
local settings={readSetting=function()end,saveSetting=function()end,flush=function()end}
local widget={}
function widget:extend(t) t=t or {}; return setmetatable(t,{__index=self}) end
function widget:new(t) return self:extend(t) end
function widget:addWidget() end
local ui={show=function(_,x)shown[#shown+1]=x end,close=function()end,setDirty=function()end,forceRePaint=function()end}
local device={screen={getWidth=function()return 600 end,getHeight=function()return 800 end,scaleBySize=function(_,n)return n end},input={group={}}}
setmetatable(device,{__index=function()return function()return false end end})
local text=setmetatable({},{__call=function(_,s)return s end})
local json={null={},encode=function()return '{}' end,decode=function()return {}end}
local cache={getLastFetched=function()return 1 end,listRepos=function()return rows end,
 storeRepos=function(kind,repos) writes[#writes+1]=repos;return true end}
local client={listAccountRepositories=function()return rows end,fetchRepoTree=function()return {tree={{path='README.md',type='blob',mode='100644'}}}end}
local stores={list=function()return {}end,getGeneration=function()return 1 end}
local specials={['device']=device,['ui/uimanager']=ui,['qiqiappstore_gettext']=text,
 ['qiqiappstore_cache']=cache,['qiqiappstore_settings']=settings,['qiqiappstore_net_github']=client,
 ['qiqiappstore_installs']=stores,['json']=json,['datastorage']={getDataDir=function()return '/data' end},
 ['logger']={warn=function()end,dbg=function()end},['libs/libkoreader-lfs']={attributes=function()return nil end},
 ['qiqiappstore_plugin_paths']={getLookupPaths=function()return {}end},
 ['qiqiappstore_archive']={readMeta=function()return {}end},
 ['ui/network/manager']={runWhenOnline=function(_,fn)return fn()end}}
local source=assert(io.open('qiqiappstore.koplugin/main.lua','rb')):read('*a')
for name in source:gmatch('require%(["\']([^"\']+)["\']%)') do
    if name~='qiqiappstore_policy' and name~='qiqiappstore_scope' then
        local stub=specials[name] or widget
        package.preload[name]=function()return stub end
    end
end
G_reader_settings=settings
local Store=assert(loadfile('qiqiappstore.koplugin/main.lua'))()
local app=Store:extend{}
assert(app.name=='qiqiappstore')
local menu={};app:addToMainMenu(menu)
assert(menu.QiqiAppStore and not menu.AppStore)
rows={{owner='foreign',name='bad.koplugin',full_name='foreign/bad.koplugin',repo_id=1},
{owner='bailigebai',name='future.koplugin',full_name='bailigebai/future.koplugin',repo_id=2}}
local descriptors=app:getRepoDescriptors('plugin')
assert(#descriptors==1 and descriptors[1].name=='future.koplugin','catalog must reject foreign cached rows')
assert(#app:getRepoDescriptors('patch')==0,'patch catalog must be inaccessible')
app:matchPluginWithRepo({dirname='other.koplugin'}, {owner='foreign',name='bad.koplugin'})
assert(#shown>0,'foreign matching should be refused visibly')
app:promptRepoAction{owner='bailigebai',name='webdavmanga.koplugin',kind='plugin',qiqi_status='old failure'}
local detail=shown[#shown]
assert(detail.other_buttons[1][1].text=='重试检查',
 'old cached failures must offer a visible retry without requiring cache reset')
app:installPluginFromRepo({owner='foreign',name='bad.koplugin'})
app:installPluginFromReleaseAsset({owner='foreign',name='bad.koplugin'}, {}, {})
app:deletePlugin('unrelated.koplugin')
app:disablePlugin('unrelated.koplugin')
app:enablePlugin('unrelated.koplugin')
app:deletePlugin('qiqiappstore.koplugin')
assert(#shown>=7,'out-of-scope operations and self deletion must be rejected')
app:beginRefreshPhase(0,1)
rows={}
local n,ok=app:fetchAndStore('plugin')
assert(n==0 and ok and #writes==1,'valid empty account must replace old cache')
client.listAccountRepositories=function()return nil,'network failure'end
local called=pcall(function()app:fetchAndStore('plugin')end)
assert(not called and #writes==1,'network failure must not clear cached projects')
print('main: real catalog, menus, mutation guards and refresh transaction boundaries checked')

client.listAccountRepositories=function()return {
 {owner={login='bailigebai'},name='first.koplugin',private=false},
 {owner={login='bailigebai'},name='second.koplugin',private=false}}end
local tree_calls=0
client.fetchRepoTree=function()
 tree_calls=tree_calls+1
 if tree_calls==2 then return nil,'rate limited' end
 return {tree={}}
end
assert(not pcall(function()app:fetchAndStore('plugin')end), 'partial tree failure must abort refresh')
assert(#writes==1,'partial tree failure must preserve the entire old cache')
