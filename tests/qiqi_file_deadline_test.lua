local clock,wall=0,1000
local http={}
local socketutil
socketutil={LARGE_BLOCK_TIMEOUT=10,LARGE_TOTAL_TIMEOUT=30,total_timeout=300,
 set_timeout=function(self,_,total)self.total_timeout=total end,reset_timeout=function(self)self.total_timeout=-1 end,
 file_sink=function(file)
  local started=wall
  return function(chunk)
   if wall-started>socketutil.total_timeout then return nil,'sink timeout' end
   return file:write(chunk)
  end
 end}
package.preload['socket.http']=function()return http end
package.preload['socketutil']=function()return socketutil end
package.preload['logger']=function()return {warn=function()end}end
package.preload['ui/time']=function()return {now=function()return clock end,to_s=function(v)return v end}end
local Net=require('qiqiappstore_net')
local file={write=function()return true end,close=function()end}
http.request=function(req)
 clock=20;wall=wall+3600;socketutil.total_timeout=15
 local ok,err=req.sink('ZIP');if not ok then return nil,err end
 req.sink(nil);return 1,200,{},'OK'
end
assert(Net.requestToFile({url='https://example.test/file.zip'},file,45,300)==200,
 'wall-clock change or another shared timeout must not expire a 20-second file transfer')
print('file deadline: monotonic time and per-request sink budget isolation checked')
