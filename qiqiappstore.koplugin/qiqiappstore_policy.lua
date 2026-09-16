-- Account scope is a rule, not a list of today's plugins.
local Policy = { owner = 'bailigebai' }

function Policy.allows(owner, name)
    return type(owner) == 'string' and owner:lower() == Policy.owner
        and type(name) == 'string' and name:match('^[%w_%-%.]+%.koplugin$') ~= nil
        and name ~= '.koplugin' and not name:find('..', 1, true)
end

function Policy.accepts(repo)
    if type(repo) ~= 'table' then return false end
    local owner = type(repo.owner) == 'table' and repo.owner.login or repo.owner
    if not Policy.allows(owner, repo.name) or repo.private == true then return false end
    if repo.data and repo.data.private == true then return false end
    if repo.full_name and repo.full_name:lower() ~= (owner .. '/' .. repo.name):lower() then return false end
    return true
end

function Policy.pluginFromTree(tree, repo_name)
    if type(tree) ~= 'table' or tree.truncated or type(tree.tree) ~= 'table' then
        return nil, '无法完整读取项目文件，请重新联网刷新。'
    end
    local files = {}
    for _, entry in ipairs(tree.tree) do
        local path = entry.path
        if type(path) ~= 'string' or path:find('\\',1,true) or path:sub(1,1)=='/'
            or path:find(':',1,true) or path:match('^%.%./') or path:match('/%.%./') then
            return nil, '项目包含不安全的文件路径。'
        end
        if entry.type == 'blob' and entry.mode ~= '120000' then files[path] = true end
    end
    local candidates = {}
    for path in pairs(files) do
        local root = path == '_meta.lua' and '' or path:match('^(.*)/_meta%.lua$')
        if root and files[(root == '' and '' or root .. '/') .. 'main.lua'] then
            local dirname = root == '' and repo_name or root:match('([^/]+%.koplugin)$')
            if dirname and Policy.allows(Policy.owner, dirname) then
                candidates[#candidates+1] = {dirname=dirname,meta_path=path,root=root}
            end
        end
    end
    if #candidates == 0 then return nil, '暂未发布：项目没有可安装的插件文件。' end
    if #candidates ~= 1 then return nil, '项目包含多个插件目录，无法确定安装目标。' end
    return candidates[1]
end

function Policy.recordMatches(record, repo, dirname)
    if type(record) ~= 'table' or not Policy.accepts(repo) then return false end
    local layout = repo.data and repo.data.qiqi_layout or repo.qiqi_layout
    return Policy.accepts{owner=record.owner,name=record.repo,full_name=record.repo_full_name}
        and layout ~= nil and layout.dirname == dirname and record.dirname == dirname
        and record.repo == repo.name
        and (not record.repo_id or record.repo_id == (repo.repo_id or repo.id))
end

return Policy
