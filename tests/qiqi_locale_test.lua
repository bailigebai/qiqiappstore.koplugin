local gettext=setmetatable({current_lang='zh_CN'}, {__call=function(_,s)return s end})
package.preload['gettext']=function()return gettext end
package.preload['logger']=function()return {warn=function()end}end
local translate=require('qiqiappstore_gettext')
assert(translate('qiqi App Store')=='qiqi 应用商店')
assert(translate('qiqi App Store · Plugins')=='qiqi 应用商店 · 插件')
assert(translate('QiqiAppStore settings')=='qiqi 应用商店 设置')
local metadata=assert(loadfile('_meta.lua'))()
assert(metadata.name=='qiqiappstore' and metadata.version=='0.1.7')
assert(metadata.fullname=='qiqi 应用商店')
print('locale: real Chinese translation loading and plugin metadata checked')
