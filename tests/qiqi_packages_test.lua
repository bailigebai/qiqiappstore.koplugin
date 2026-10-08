local Packages=require('qiqiappstore_packages')
local sha=string.rep('a',40)
local digest=string.rep('b',64)
local repo={owner='bailigebai',name='demo.koplugin',qiqi_commit=sha,
 qiqi_download_tree={tree={{path='downloads/demo-v1.zip',type='blob',mode='100644',size=10}}}}
local asset={name='demo-v1.zip',size=10,digest='sha256:'..digest,id=123,
 browser_download_url='https://github.com/bailigebai/demo.koplugin/releases/download/v1/demo-v1.zip'}
local p=assert(Packages.plan(repo,asset,false))
assert(p.urls[1]=='https://raw.githubusercontent.com/bailigebai/demo.koplugin/'..sha..'/downloads/demo-v1.zip')
assert(p.urls[2]=='https://api.github.com/repos/bailigebai/demo.koplugin/releases/assets/123')
assert(p.sha256==digest and p.size==10)
assert(Packages.plan(repo,asset,true).urls[1]==asset.browser_download_url,'selected mirror must keep original URL')
repo.qiqi_download_tree.tree[1].mode='120000'
assert(Packages.plan(repo,asset,false).urls[1]:find('api.github.com',1,true),'never follow a symlink raw package')
repo.qiqi_download_tree.tree[1].mode='100644';asset.size=11
assert(Packages.plan(repo,asset,false).urls[1]:find('api.github.com',1,true),'wrong-size copies cannot replace release')
asset.size=10;asset.digest=nil
assert(Packages.plan(repo,asset,false).urls[1]:find('api.github.com',1,true),'no digest cannot prove raw equivalence')
asset.name='demo.zip.sha256';assert(not Packages.plan(repo,asset,false))
asset.name='demo-v1.zip';repo.owner='foreign';assert(not Packages.plan(repo,asset,false))
print('packages: pinned raw, same release, mirror choice, scope, hash and symlink guards checked')
