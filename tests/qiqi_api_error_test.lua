local response_code, response_headers, decoded = 403, {['x-ratelimit-remaining']='0'}, {}
package.preload['json']=function()return {decode=function()return decoded end}end
package.preload['logger']=function()return {dbg=function()end,warn=function()end}end
package.preload['socket.url']=function()return {escape=function(s)return s end}end
package.preload['qiqiappstore_net']=function()return {requestToTable=function(_,body)
 body[1]='fixture';return response_code,response_headers,'timeout'
end}end
local Client=require('qiqiappstore_net_github')
local meta,err=Client.fetchRepoMetadata('bailigebai','webdavmanga.koplugin')
assert(not meta and err.headers==response_headers)
assert(Client.describeError(err):find('次数受限',1,true))
assert(Client.describeError{code=401,body='secret'}:find('授权失效',1,true))
assert(not Client.describeError{code=401,body='secret'}:find('secret',1,true))
assert(Client.describeError{code=403}:find('拒绝访问',1,true))
assert(Client.describeError{code=429}:find('次数受限',1,true))
assert(Client.describeError{code='wantread'}:find('wantread',1,true))
response_code=200;decoded='invalid'
assert(Client.fetchRepoMetadata('bailigebai','webdavmanga.koplugin')==nil)
print('API diagnostics: status, rate headers, TLS errors, malformed JSON and no response secrets checked')
