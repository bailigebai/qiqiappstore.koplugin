-- Plan downloads of the exact selected release; never substitute a source ZIP.
local Policy = require('qiqiappstore_policy')
local Packages = {}

function Packages.plan(repo, asset, mirrored)
    if not Policy.accepts(repo) or type(asset) ~= 'table'
        or type(asset.name) ~= 'string' or not asset.name:lower():match('%.zip$') then return nil end
    local prefix = 'https://github.com/' .. Policy.owner .. '/' .. repo.name .. '/releases/download/'
    local browser = asset.browser_download_url
    if type(browser) ~= 'string' or browser:sub(1,#prefix) ~= prefix then return nil end
    local digest = type(asset.digest) == 'string' and asset.digest:match('^sha256:([a-fA-F0-9]+)$')
    if digest and #digest ~= 64 then digest = nil end
    local plan = {urls={}, size=tonumber(asset.size), sha256=digest and digest:lower()}
    if mirrored then plan.urls[1]=browser; return plan end
    local ref, matches = repo.qiqi_commit, {}
    if digest and type(ref)=='string' and #ref==40 and ref:match('^[a-fA-F0-9]+$') then
        for _, entry in ipairs(repo.qiqi_download_tree and repo.qiqi_download_tree.tree or {}) do
            local path=entry.path
            if type(path)=='string' and path:match('^[%w_%.%/-]+$')
                and not path:find('..',1,true) and path:sub(1,1)~='/'
                and (path:match('([^/]+)$')==asset.name)
                and entry.type=='blob' and entry.mode~='120000' and entry.size==plan.size then
                matches[#matches+1]=path
            end
        end
        if #matches==1 then
            plan.urls[#plan.urls+1]='https://raw.githubusercontent.com/'..Policy.owner..'/'..repo.name..'/'..ref..'/'..matches[1]
        end
    end
    local id=tonumber(asset.id)
    if id and id>0 and id%1==0 then
        plan.urls[#plan.urls+1]='https://api.github.com/repos/'..Policy.owner..'/'..repo.name..'/releases/assets/'..string.format('%.0f',id)
    end
    plan.urls[#plan.urls+1]=browser
    return plan
end

function Packages.verify(path, plan)
    local file,err=io.open(path,'rb')
    if not file then return false,err end
    local size=file:seek('end');file:seek('set',0)
    if not size or (plan.size and size~=plan.size) then
        file:close();return false,'安装包大小不符，下载不完整。'
    end
    local magic=file:read(4);file:seek('set',0)
    if magic~='PK\003\004' then file:close();return false,'下载内容不是 ZIP 安装包。' end
    if plan.sha256 then
        local update=require('ffi/sha2').sha256()
        while true do local chunk=file:read(65536);if not chunk then break end;update(chunk) end
        if update():lower()~=plan.sha256 then
            file:close();return false,'安装包校验失败，文件与所选版本不一致。'
        end
    end
    file:close();return true
end

return Packages
