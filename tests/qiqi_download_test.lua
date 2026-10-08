-- Exercise the actual download helper with a simulated slow transport.
local source=assert(io.open("main.lua","rb")):read("*a")
source=source:gsub("\r\n","\n")
local body=assert(source:match("downloadToFile = function%(url, local_path%)(.-)\nend\n"))
local elapsed, removed, closed, observed = 90, false, false, nil
local env=setmetatable({}, {__index=_G})
env.Mirror={apply=function(url)return url end}
env.util={makePath=function()end,removeFile=function()removed=true end}
env.socketutil={FILE_BLOCK_TIMEOUT=15,FILE_TOTAL_TIMEOUT=60,SINK_TIMEOUT_CODE="sink timeout",TIMEOUT_CODE="timeout",SSL_HANDSHAKE_CODE="ssl handshake failed",USER_AGENT="test"}
env.io={open=function()return {close=function()closed=true end}end}
env.Net={requestToFile=function(req,file,block,total)
 observed={block=block,total=total,url=req.url}
 if elapsed>total then return "sink timeout",nil,"sink timeout" end
 return 200,{},"OK"
end}
local loader=assert(loadstring("return function(url, local_path)"..body.."\nend"))
setfenv(loader,env)
local download=loader()
local ok,err=download("https://api.github.com/repos/bailigebai/legado.koplugin/zipball/HEAD","/tmp/plugin.zip")
assert(ok, "an active 90-second archive transfer must succeed: "..tostring(err))
assert(observed.total==300 and observed.block==45,"keep finite total and connection budgets")
assert(closed and not removed,"successful file must be closed and retained")
elapsed=301; removed=false;closed=false
assert(not download("https://example.test/file.zip","/tmp/plugin.zip"))
assert(removed and closed,"expired partial download must close and be deleted")
assert(env.socketutil.FILE_TOTAL_TIMEOUT==60,"do not mutate KOReader global defaults")
print("download: slow transfer, finite deadline, close and cleanup checked")
