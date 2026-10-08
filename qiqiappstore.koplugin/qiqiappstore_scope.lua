-- Adapt the upstream UI at explicit seams; keep account policy out of UI widgets.
local Policy = require('qiqiappstore_policy')
local Scope = {}

function Scope.attach(Store, deps)
    local UI, Info, Net, GitHub, Cache = deps.UI, deps.Info, deps.Network, deps.GitHub, deps.Cache
    local function tell(text) UI:show(Info:new{text=text,timeout=6}) end
    local function allowed(repo)
        if Policy.accepts(repo) then return true end
        tell('本商店仅支持 bailigebai 账号下以 .koplugin 结尾的公开项目。')
        return false
    end
    local function inspect(repo, fresh)
        if not allowed(repo) then return end
        if not fresh and repo.qiqi_layout then return repo.qiqi_layout end
        local metadata, err = GitHub.fetchRepoMetadata(Policy.owner, repo.name)
        if type(metadata) ~= 'table' then
            repo.qiqi_layout = nil
            repo.qiqi_inspection_error = true
            repo.qiqi_status = '仓库信息校验失败：' .. GitHub.describeError(err) .. '\n可点击“重试检查”。'
            return nil, err
        end
        repo.qiqi_inspection_error = nil
        if metadata.private ~= false or not Policy.accepts(metadata) then
            repo.qiqi_layout = nil
            repo.qiqi_status = '项目不再是本账号下的公开插件项目，不能安装。'
            return nil
        end
        local tree, tree_err = GitHub.fetchRepoTree(Policy.owner, repo.name, metadata.default_branch or 'HEAD')
        local layout, reason = Policy.pluginFromTree(tree, repo.name)
        repo.qiqi_layout, repo.qiqi_status = layout, reason
        repo.qiqi_commit = tree and tree.sha
        if tree_err or type(tree) ~= 'table' or tree.truncated or type(tree.tree) ~= 'table' then
            repo.qiqi_layout = nil
            repo.qiqi_inspection_error = true
            repo.qiqi_status = '安装文件检查失败：' .. GitHub.describeError(tree_err or '文件列表不完整') .. '\n可点击“重试检查”。'
            return nil, tree_err
        end
        return layout
    end

    local descriptors = Store.getRepoDescriptors
    function Store:getRepoDescriptors(kind)
        if kind ~= 'plugin' then return {} end
        local scoped = {}
        for _, repo in ipairs(descriptors(self, kind)) do
            if Policy.accepts(repo) then
                local data = repo.data or {}
                repo.qiqi_layout = data.qiqi_layout
                repo.qiqi_status = data.qiqi_status
                scoped[#scoped+1] = repo
            end
        end
        return scoped
    end

    function Store:fetchAndStore(kind)
        if kind ~= 'plugin' then return 0, false end
        local repos, err = GitHub.listAccountRepositories{
            should_stop=function()return self:refreshCancelled()end,
            on_progress=function(page)self:reportRefreshProgress(math.min(0.4,page*0.02))end,
        }
        if not repos then
            if not self:refreshCancelled() then error(err or '无法读取账号仓库列表。') end
            return 0, false
        end
        for i, repo in ipairs(repos) do
            if self:refreshCancelled() then return 0, false end
            local tree, tree_err = GitHub.fetchRepoTree(Policy.owner, repo.name, repo.default_branch or 'HEAD')
            if not tree or tree_err or tree.truncated or type(tree.tree) ~= 'table' then
                error(tree_err or '项目文件列表不完整，已保留原缓存。')
            end
            repo.qiqi_layout, repo.qiqi_status = Policy.pluginFromTree(tree, repo.name)
            if repo.qiqi_layout then
                for _, entry in ipairs(tree.tree) do
                    if entry.path == repo.qiqi_layout.meta_path then repo.qiqi_layout.meta_sha = entry.sha end
                end
            end
            self:reportRefreshProgress(0.4 + 0.4*i/#repos)
        end
        if self:refreshCancelled() then return 0, false end
        local ok = Cache.storeRepos('plugin', repos,
            function(done,total)self:reportRefreshProgress(0.8+0.2*done/math.max(total,1))end,
            function()return self:refreshCancelled()end, true)
        if ok then Store._refresh_wrote_anything = true end
        return ok and #repos or 0, ok
    end
    function Store:isFullRefreshDue() return true end
    function Store:browserSwitchTab() end
    local browser = Store.showBrowser
    function Store:showBrowser() self:ensureBrowserState();self.browser_state.kind='plugin';return browser(self,'plugin') end

    local action = Store.promptRepoAction
    function Store:promptRepoAction(repo)
        if not allowed(repo) then return end
        -- Cached descriptions remain accessible offline. Fresh checks gate mutations below.
        if not repo.qiqi_inspection_error and (repo.qiqi_layout or repo.qiqi_status) then return action(self,repo) end
        Net:runWhenOnline(function() inspect(repo,true);action(self,repo) end)
    end
    function Store:retryRepoInspection(repo)
        if not allowed(repo) then return end
        Net:runWhenOnline(function() inspect(repo,true);action(self,repo) end)
    end
    local options = Store.promptPluginInstallOptions
    function Store:promptPluginInstallOptions(repo, release)
        if not allowed(repo) then return end
        Net:runWhenOnline(function()
            if not inspect(repo,true) then tell(repo.qiqi_status);return end
            return options(self,repo,release)
        end)
    end
    local install = Store._installPluginFromRepoInternal
    function Store:_installPluginFromRepoInternal(repo)
        if not allowed(repo) then return end
        if not inspect(repo,true) then tell(repo.qiqi_status);return end
        return install(self,repo)
    end
    local install_entry = Store.installPluginFromRepo
    function Store:installPluginFromRepo(repo)
        if not allowed(repo) then return end
        return install_entry(self,repo)
    end
    local asset = Store.installPluginFromReleaseAsset
    function Store:installPluginFromReleaseAsset(repo,release,file)
        if not allowed(repo) then return end
        local prefix='https://github.com/'..Policy.owner..'/'..repo.name..'/releases/download/'
        local raw=file and file.browser_download_url
        local source_prefix='https://api.github.com/repos/'..Policy.owner..'/'..repo.name..'/zipball/'
        if type(raw)~='string' or (raw:sub(1,#prefix)~=prefix and raw:sub(1,#source_prefix)~=source_prefix) then
            tell('安装包地址不属于本项目的 GitHub 发布附件。');return
        end
        Net:runWhenOnline(function()
            if not inspect(repo,true) then tell(repo.qiqi_status);return end
            return asset(self,repo,release,file)
        end)
    end
    local match = Store.matchPluginWithRepo
    function Store:matchPluginWithRepo(plugin,repo)
        if not allowed(repo) then return end
        Net:runWhenOnline(function()
            local layout=inspect(repo,true)
            if not layout or layout.dirname~=plugin.dirname then tell('项目插件目录与本地插件不一致，不能关联。');return end
            plugin.meta_path_hint=layout.meta_path
            return match(self,plugin,repo)
        end)
    end
    for _, method in ipairs({'disablePlugin','enablePlugin','deletePlugin','performPluginDeletion'}) do
        local original=Store[method]
        Store[method]=function(self,dirname,...)
            if dirname=='qiqiappstore.koplugin' and (method=='deletePlugin' or method=='performPluginDeletion') then
                tell('不能在商店运行时卸载自身，请退出 KOReader 后手动移除。');return false
            end
            if not deps.findInstalled(dirname) then tell('此插件尚未验证为本账号的插件，不能操作。');return false end
            return original(self,dirname,...)
        end
    end
    -- These entry points remain in upstream source for a small, reviewable fork diff,
    -- but no patch UI or action is exposed in this account-only plugin store.
    for _, method in ipairs({'showPatchUpdatesDialog','promptInstallPatchFromURL','installPatchFromRepo',
        '_installPatchFromRepoInternal','fetchAndShowPatchRepo','matchPatchWithRepo','deletePatch','enablePatch','disablePatch'}) do
        Store[method]=function() tell('qiqi 应用商店仅管理 .koplugin 插件。') end
    end
end

return Scope
