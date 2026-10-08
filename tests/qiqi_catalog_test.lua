local pages, calls, fail_page, cancel, decoded = {}, {}, nil, false, nil
package.preload['json']=function() return {decode=function() return decoded end} end
package.preload['logger']=function() return {warn=function()end,dbg=function()end} end
package.preload['socket.url']=function() return {escape=function(s) return s end} end
package.preload['qiqiappstore_net']=function() return {requestToTable=function(opts,body)
    local page=tonumber(opts.url:match('[?&]page=(%d+)'))
    assert(opts.url:match('^https://api.github.com/users/bailigebai/repos%?'), 'only account listing may be requested')
    calls[#calls+1]=page
    if fail_page==page then return 403,{},'rate limited' end
    decoded=pages[page]
    body[1]='fixture'
    return 200,{},'OK'
end} end
local Client=require('qiqiappstore_net_github')
assert(type(Client.listAccountRepositories)=='function','dynamic account pagination is not implemented')
pages[1]={}
for i=1,100 do pages[1][i]={id=i,name='utility'..i,owner={login='bailigebai'},private=false} end
pages[1][1]={id=1,name='one.koplugin',owner={login='bailigebai'},private=false,fork=true,stargazers_count=0}
pages[2]={
    {id=101,name='future.koplugin',owner={login='bailigebai'},private=false},
    {id=1,name='one.koplugin',owner={login='bailigebai'},private=false},
    {id=103,name='foreign.koplugin',owner={login='foreign'},private=false},
    {id=104,name='private.koplugin',owner={login='bailigebai'},private=true},
    {id=105,name='almost.koplugin.zip',owner={login='bailigebai'},private=false},
}
local result=assert(Client.listAccountRepositories())
assert(#result==2 and result[2].name=='future.koplugin')
assert(#calls==2 and calls[2]==2)
fail_page=2
assert(Client.listAccountRepositories()==nil, 'failed later page must not publish partial catalog')
fail_page=nil
assert(Client.listAccountRepositories({should_stop=function()return true end})==nil)
pages[1]={}
assert(#assert(Client.listAccountRepositories())==0, 'valid empty account is a successful catalog')
pages[1]={message='not a list'}
assert(Client.listAccountRepositories()==nil, 'malformed successful response must not clear old cache')
print('catalog: complete pagination, new plugin, deduplication, failures, cancellation, empty and malformed responses checked')
