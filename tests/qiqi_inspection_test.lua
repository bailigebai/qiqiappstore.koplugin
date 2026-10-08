package.path = 'qiqiappstore.koplugin/?.lua;' .. package.path
local Scope = require('qiqiappstore_scope')
local calls, actions, installs = 0, 0, 0
local failure = true
local repo = {owner='bailigebai',name='webdavmanga.koplugin',kind='plugin'}
local Store = {promptRepoAction=function()actions=actions+1 end,
 getRepoDescriptors=function()return {}end,
 promptPluginInstallOptions=function()installs=installs+1 end}
local GitHub = {
 fetchRepoMetadata=function()
  calls=calls+1
  if failure then return nil,{code='timeout'} end
  return {owner={login='bailigebai'},name=repo.name,private=false}
 end,
 fetchRepoTree=function()return {sha='commit',tree={
  {path='main.lua',type='blob'},{path='_meta.lua',type='blob'}}}end,
 describeError=function(err)return 'GitHub 请求失败：' .. tostring(err.code)end,
}
Scope.attach(Store,{UI={show=function()end},Info={new=function(_,x)return x end},
 Network={runWhenOnline=function(_,fn)return fn()end},GitHub=GitHub,Cache={}})
Store:promptRepoAction(repo)
assert(not repo.qiqi_layout and repo.qiqi_status:find('timeout',1,true),
 'failed inspection must show the actual transport error')
failure=false
Store:promptRepoAction(repo)
assert(calls==2 and repo.qiqi_layout and not repo.qiqi_inspection_error,
 'reopening after a transient failure must perform fresh inspection')
failure=true
Store:promptPluginInstallOptions(repo)
assert(installs==0 and not repo.qiqi_layout,'cached layout must never bypass a failed fresh check')
failure=false
GitHub.fetchRepoMetadata=function()return {owner={login='foreign'},name=repo.name,private=false}end
Store:retryRepoInspection(repo)
assert(not repo.qiqi_layout and installs==0,'retry must reject foreign metadata')
assert(repo.qiqi_status:find('公开',1,true),'policy denial must differ from network failure')
print('inspection: retry recovery, diagnostics and fresh mutation guards checked')
