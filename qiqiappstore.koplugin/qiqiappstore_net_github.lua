local json = require("json")
local Net = require("qiqiappstore_net")
local url = require("socket.url")
local logger = require("logger")

local ok_cfg, QiqiAppStoreConfig = pcall(require, "qiqiappstore_configuration")
if not ok_cfg then
    QiqiAppStoreConfig = {}
end

local GitHubClient = {}
local Policy = require('qiqiappstore_policy')

local BASE_URL = "https://api.github.com"
local USER_AGENT = "KOReader-QiqiAppStore"

local function joinQueryParts(parts)
    if not parts or #parts == 0 then
        return ""
    end
    return table.concat(parts, " ")
end

local function getAuthHeaders()
    local auth = QiqiAppStoreConfig.auth and QiqiAppStoreConfig.auth.github
    if not auth then
        return nil
    end
    local token = auth.token
    if not token or token == "" or token == "your_github_token" then
        return nil
    end
    local scheme = auth.scheme or "token"
    return {
        ["Authorization"] = string.format("%s %s", scheme, token),
    }
end

local function request(path, query)
    local response_body = {}
    local target = BASE_URL .. path
    if query and query ~= "" then
        target = target .. "?" .. query
    end
    logger.dbg("QiqiAppStore HTTP", target)
    local headers = {
        ["Accept"] = "application/vnd.github+json",
        ["User-Agent"] = USER_AGENT,
    }
    local auth_headers = getAuthHeaders()
    if auth_headers then
        for key, value in pairs(auth_headers) do
            headers[key] = value
        end
    end
    -- Without a deadline a single stalled connection hangs the interface for good: every
    -- one of these runs on the UI thread. The API answers in well under a second when it
    -- answers at all, so the large-content values are already generous.
    local code, _, status = Net.requestToTable({
        url = target,
        headers = headers,
    }, response_body)
    if not code then
        return status, ""
    end
    local body = table.concat(response_body)
    -- A timeout reports itself as a string where a status would be. Callers only ever
    -- compare against 200, so passing it through keeps them working and names the reason
    -- in their logs instead of turning it into a bare nil.
    return tonumber(code) or code, body
end

local function buildQuery(opts)
    local query_parts = {}
    if opts.q and opts.q ~= "" then
        table.insert(query_parts, "q=" .. url.escape(opts.q))
    end
    if opts.sort and opts.sort ~= "" then
        table.insert(query_parts, "sort=" .. opts.sort)
    end
    if opts.order and opts.order ~= "" then
        table.insert(query_parts, "order=" .. opts.order)
    end
    table.insert(query_parts, "page=" .. tostring(opts.page or 1))
    table.insert(query_parts, "per_page=" .. tostring(opts.per_page or 30))
    return table.concat(query_parts, "&")
end

local function buildTopicQuery(topics, extra_terms)
    local parts = {}
    if topics then
        for _, topic in ipairs(topics) do
            if topic and topic ~= "" then
                table.insert(parts, string.format("topic:%s", topic))
            end
        end
    end
    if extra_terms and extra_terms ~= "" then
        table.insert(parts, extra_terms)
    end
    return joinQueryParts(parts)
end

function GitHubClient.listAccountRepositories(opts)
    opts = opts or {}
    local collected, seen, page = {}, {}, 1
    while true do
        if opts.should_stop and opts.should_stop() then return nil, '已取消刷新。' end
        local code, body = request('/users/' .. Policy.owner .. '/repos',
            'type=owner&sort=full_name&direction=asc&per_page=100&page=' .. page)
        if code ~= 200 then return nil, 'GitHub 请求失败：' .. tostring(code) end
        local ok, entries = pcall(json.decode, body)
        if not ok or type(entries) ~= 'table' then return nil, 'GitHub 返回的数据无法解析。' end
        for key in pairs(entries) do
            if type(key) ~= 'number' or key < 1 or key > #entries or key % 1 ~= 0 then
                return nil, 'GitHub 未返回完整仓库列表。'
            end
        end
        for _, repo in ipairs(entries) do
            if type(repo) ~= 'table' or type(repo.name) ~= 'string' or not repo.id then
                return nil, 'GitHub 仓库信息不完整。'
            end
            if repo.private == false and Policy.accepts(repo) and not seen[repo.id] then
                seen[repo.id] = true
                collected[#collected + 1] = repo
            end
        end
        if opts.on_progress then opts.on_progress(page, #collected) end
        if #entries < 100 then break end
        page = page + 1
    end
    if opts.should_stop and opts.should_stop() then return nil, '已取消刷新。' end
    return collected
end

function GitHubClient.searchRepositories(opts)
    opts = opts or {}
    -- README search stays inside the same account even if a caller supplies qualifiers.
    opts.q = (opts.q or '') .. ' user:' .. Policy.owner
    local query = buildQuery(opts)
    local code, body = request("/search/repositories", query)
    if code ~= 200 then
        logger.warn("GitHub search error", code, body)
        -- GitHub's search endpoint rejects fine-grained PATs outright (they're
        -- not in its list of supported token types), returning a 403 with this
        -- wording rather than an actual rate-limit response. Classic tokens work.
        local is_fine_grained_unsupported = code == 403
            and body
            and body:lower():find("fine%-grained", 1, true) ~= nil
        local err_info = {
            code = code,
            body = body,
            is_rate_limit = (code == 403 or code == 429) and not is_fine_grained_unsupported,
            is_fine_grained_unsupported = is_fine_grained_unsupported,
        }
        return nil, err_info
    end
    local ok, parsed = pcall(json.decode, body)
    if not ok then
        logger.warn("GitHub search decode error", parsed)
        return nil, { code = 0, body = "decode", is_rate_limit = false }
    end
    return parsed, nil
end

function GitHubClient.hasAuthToken()
    local auth = QiqiAppStoreConfig.auth and QiqiAppStoreConfig.auth.github
    if not auth then
        return false
    end
    local token = auth.token
    if not token or token == "" or token =="your_github_token" then
        return false
    end
    return true
end

function GitHubClient.searchByTopics(topics, opts)
    opts = opts or {}
    local q = buildTopicQuery(topics, opts.extra)
    opts.q = q
    opts.sort = opts.sort or "stars"
    opts.order = opts.order or "desc"
    opts.per_page = opts.per_page or 100
    return GitHubClient.searchRepositories(opts)
end

function GitHubClient.fetchRepoTree(owner, repo, ref)
    if not Policy.allows(owner, repo) then return nil, '不属于本商店的插件项目。' end
    if not owner or not repo then
        return nil, "missing owner/repo"
    end
    ref = ref or "HEAD"
    local path = string.format("/repos/%s/%s/git/trees/%s", owner, repo, ref)
    local code, body = request(path, "recursive=1")
    if code ~= 200 then
        logger.warn("GitHub fetch tree error", owner .. "/" .. repo, ref, code, body)
        return nil, { code = code, body = body }
    end
    local ok, parsed = pcall(json.decode, body)
    if not ok then
        logger.warn("GitHub fetch tree decode error", parsed)
        return nil, "decode"
    end
    return parsed, nil
end

function GitHubClient.fetchRepoMetadata(owner, repo)
    if not Policy.allows(owner, repo) then return nil, '不属于本商店的插件项目。' end
    if not owner or not repo then
        return nil, "missing owner/repo"
    end
    local path = string.format("/repos/%s/%s", owner, repo)
    local code, body = request(path)
    if code ~= 200 then
        logger.warn("GitHub fetch repo metadata error", owner .. "/" .. repo, code, body)
        return nil, { code = code, body = body }
    end
    local ok, parsed = pcall(json.decode, body)
    if not ok then
        logger.warn("GitHub fetch repo metadata decode error", parsed)
        return nil, "decode"
    end
    return parsed, nil
end

function GitHubClient.fetchLatestRelease(owner, repo)
    if not Policy.allows(owner, repo) then return nil, '不属于本商店的插件项目。' end
    if not owner or not repo then
        return nil, "missing owner/repo"
    end
    local path = string.format("/repos/%s/%s/releases/latest", owner, repo)
    local code, body = request(path)
    if code == 404 then return nil end
    if code ~= 200 then
        logger.warn("GitHub fetch latest release error", owner .. "/" .. repo, code, body)
        return nil, { code = code, body = body }
    end
    local ok, parsed = pcall(json.decode, body)
    if not ok then
        logger.warn("GitHub fetch latest release decode error", parsed)
        return nil, "decode"
    end
    return parsed, nil
end

-- Fetch all releases of a repository (sorted from newest to oldest by GitHub).
-- Pagination is performed transparently up to `max_pages` to avoid hammering
-- the API for repositories with hundreds of releases.
function GitHubClient.fetchReleases(owner, repo, opts)
    if not Policy.allows(owner, repo) then return nil, '不属于本商店的插件项目。' end
    if not owner or not repo then
        return nil, "missing owner/repo"
    end
    opts = opts or {}
    local per_page = tonumber(opts.per_page) or 100
    local max_pages = tonumber(opts.max_pages) or 5
    local results = {}
    for page = 1, max_pages do
        local path = string.format("/repos/%s/%s/releases", owner, repo)
        local query = string.format("per_page=%d&page=%d", per_page, page)
        local code, body = request(path, query)
        if code ~= 200 then
            logger.warn("GitHub fetch releases error", owner .. "/" .. repo, code, body)
            if #results > 0 then
                return results, nil
            end
            return nil, { code = code, body = body }
        end
        local ok, parsed = pcall(json.decode, body)
        if not ok or type(parsed) ~= "table" then
            logger.warn("GitHub fetch releases decode error", parsed)
            if #results > 0 then
                return results, nil
            end
            return nil, "decode"
        end
        if #parsed == 0 then
            break
        end
        for _, rel in ipairs(parsed) do
            table.insert(results, rel)
        end
        if #parsed < per_page then
            break
        end
    end
    return results, nil
end

-- Fetch the list of commits between two refs (tags, branches, SHAs).
-- Uses the GitHub compare endpoint: /repos/{owner}/{repo}/compare/{base}...{head}
-- Returns the parsed JSON table (contains `commits`, `total_commits`, etc.) or nil + err.
function GitHubClient.fetchCompareCommits(owner, repo, base, head)
    if not owner or not repo or not base or not head then
        return nil, "missing parameters"
    end
    local path = string.format("/repos/%s/%s/compare/%s...%s", owner, repo, base, head)
    local code, body = request(path)
    if code ~= 200 then
        logger.warn("GitHub compare error", owner .. "/" .. repo, base .. "..." .. head, code, body)
        return nil, { code = code, body = body }
    end
    local ok, parsed = pcall(json.decode, body)
    if not ok then
        logger.warn("GitHub compare decode error", parsed)
        return nil, "decode"
    end
    return parsed, nil
end

return GitHubClient
