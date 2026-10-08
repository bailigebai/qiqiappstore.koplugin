local clock,calls,code,remaining=1000,0,403,'0'
local entry={metadata={owner={login='bailigebai'},name='new.koplugin',private=false,default_branch='main'},
 tree={sha=string.rep('a',40),tree={}},release={tag_name='v1',assets={}}}
package.preload['json']=function()return {decode=function()return {}end}end
package.preload['socket.url']=function()return {escape=function(s)return s end}end
package.preload['logger']=function()return {dbg=function()end,warn=function()end}end
package.preload['qiqiappstore_net']=function()return {requestToTable=function()
 calls=calls+1;return code,{['x-ratelimit-remaining']=remaining},'error'
end}end
local loads=0
package.preload['qiqiappstore_catalog']=function()return {load=function()loads=loads+1;return {entry}end}end
os.time=function()return clock end
local Client=require('qiqiappstore_net_github')
assert(Client.listAccountRepositories()[1]==entry.metadata)
assert(Client.fetchRepoMetadata('bailigebai','new.koplugin')==entry.metadata)
assert(Client.fetchRepoTree('bailigebai','new.koplugin','main')==entry.tree)
assert(Client.fetchLatestRelease('bailigebai','new.koplugin')==entry.release)
assert(calls==1,'once rate-limited, one operation must not keep hammering the API')
clock=clock+61;code=401
local before=loads
assert(Client.fetchRepoMetadata('bailigebai','new.koplugin')==nil)
assert(loads==before,'invalid authorization cannot be bypassed through public index')
code=404
assert(Client.fetchRepoMetadata('bailigebai','new.koplugin')==nil)
assert(loads==before,'missing or now-private repositories must not fall back')
code=403;remaining='1'
assert(Client.fetchRepoMetadata('bailigebai','new.koplugin')==nil)
assert(loads==before,'ordinary authorization denial must not be mistaken for rate limiting')
assert(Client.fetchRepoMetadata('foreign','new.koplugin')==nil)
print('GitHub fallback: complete refresh, metadata/tree/releases, cooldown, 401/404 and account guards checked')
