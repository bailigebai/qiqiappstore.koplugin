local source=assert(io.open('main.lua','rb')):read('*a'):gsub('\r\n','\n')
local body=assert(source:match('downloadToFile = function%(url, local_path%)(.-)\nend\n'))
local clock,calls,removed=0,{},false
local env=setmetatable({},{__index=_G})
env.Mirror={apply=function(u)return u end}
env.io={open=function()return {close=function()end}end}
env.util={makePath=function()end,removeFile=function()removed=true end}
env.socketutil={USER_AGENT='test',TIMEOUT_CODE='timeout'}
env.InstallHelpers={Packages={verify=function()return true end}}
env.Net={now=function()return clock end,requestToFile=function(req,_,_,budget)
 calls[#calls+1]=req.url
 if #calls==1 then clock=clock+30;return 'timeout' end
 assert(req.headers.Accept=='application/octet-stream','asset API requires exact binary Accept')
 return 200,{},'OK'
end}
local f=assert(loadstring('return function(url,local_path)'..body..'\nend'));setfenv(f,env)
local download=f()
local plan={urls={'https://raw.githubusercontent.com/a.zip','https://api.github.com/a'},sha256='digest'}
assert(download(plan,'/tmp/plugin.zip'),'a blocked first endpoint must switch to the next official endpoint')
assert(#calls==2 and calls[1]==plan.urls[1] and calls[2]==plan.urls[2])
calls={};clock=0;env.InstallHelpers.Packages.verify=function()return false,'bad hash' end
local ok,err=download(plan,'/tmp/plugin.zip')
assert(not ok and removed and err=='bad hash','a wrong version or corrupt ZIP must never install')
calls={};clock=0
env.Net.requestToFile=function(req)calls[#calls+1]=req.url;return 200,{},'OK'end
env.InstallHelpers.Packages.verify=function()return #calls>1,'bad hash'end
assert(download(plan,'/tmp/plugin.zip') and #calls==2,
 'bad data from the first source must be deleted and the next exact-version source checked')

-- Device-reported connection errors must not strand a valid release on its
-- first endpoint. Exercise both normal transport returns and caught exceptions.
for _,reason in ipairs({'Cannot assign requested address','Connection reset by peer','closed',
 'cannot assign requested address','connection reset by peer'}) do
 for _,exception in ipairs({false,true}) do
  calls={};clock=0;removed=false
  env.InstallHelpers.Packages.verify=function()return true end
  env.Net.requestToFile=function(req)
   calls[#calls+1]=req.url
   if #calls==1 then
    clock=clock+15
    if exception then return nil,nil,reason end
    return reason
   end
   return 200,{},'OK'
  end
  local ok,err=download(plan,'/tmp/plugin.zip')
  assert(ok and #calls==2 and removed,
   'connection failure must clean the first attempt and try the exact release backup: '..reason..' / '..tostring(err))
 end
end

calls={};clock=0
env.Net.requestToFile=function(req)
 calls[#calls+1]=req.url;return 'Connection reset by peer'
end
local three={urls={plan.urls[1],plan.urls[2],'https://github.com/a.zip'}}
local ok,err=download(three,'/tmp/plugin.zip')
assert(not ok and #calls==3,'unavailable endpoints must stop after one pass, without infinite retry')
assert(err:find('Connection reset by peer',1,true) and err:find('github.com',1,true),
 'the final error must identify the connection failure and last endpoint')
print('sources: exact binary request, alternate endpoint and integrity failure cleanup checked')
