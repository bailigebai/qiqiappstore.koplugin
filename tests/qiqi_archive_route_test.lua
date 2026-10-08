local values = {}
package.preload['qiqiappstore_settings'] = function() return {
    readSetting = function(_, key) return values[key] end,
    saveSetting = function(_, key, value) values[key] = value end,
    flush = function() end,
} end
package.preload['qiqiappstore_gettext'] = function() return function(s) return s end end
package.preload['qiqiappstore_configuration'] = function() return {} end
-- Only custom-prefix parsing is substituted; execute the actual routing module.
package.preload['socket.url'] = function() return { parse = function(s)
    local scheme, host = s:match('^(https?)://([^/]+)')
    if scheme then return { scheme = scheme, host = host } end
end } end
local Mirror = require('qiqiappstore_mirror')
local api = 'https://api.github.com/repos/bailigebai/webdavmanga.koplugin/zipball/'
local sha = '98645c8f185db8ec2e6bcc8af18de4a036fb4c68'
assert(Mirror.apply(api .. sha) == 'https://codeload.github.com/bailigebai/webdavmanga.koplugin/zip/' .. sha,
    'direct source download must skip the API redirect and retain the checked revision')
assert(Mirror.apply(api .. 'HEAD') == 'https://codeload.github.com/bailigebai/webdavmanga.koplugin/zip/HEAD')
assert(Mirror.apply(api:sub(1, -2)) == 'https://codeload.github.com/bailigebai/webdavmanga.koplugin/zip/HEAD')
local raw = 'https://raw.githubusercontent.com/bailigebai/mangaweb.koplugin/main/README.md'
local release = 'https://github.com/bailigebai/mangaweb.koplugin/releases/download/v1/a.zip'
assert(Mirror.apply(raw) == raw and Mirror.apply(release) == release)
for _, other in ipairs({api .. 'HEAD?x=1', api:gsub('api.github.com', 'api.github.com.evil'), 'http://example.test/a.zip'}) do
    assert(Mirror.apply(other) == other, 'unrecognized URLs must not be rewritten')
end
assert(Mirror.setPreset('custom', 'https://mirror.test/'))
assert(Mirror.apply(api .. sha) == 'https://mirror.test/https://github.com/bailigebai/webdavmanga.koplugin/archive/' .. sha .. '.zip',
    'keep the archive URL understood by the selected mirror')
assert(Mirror.apply(release) == 'https://mirror.test/' .. release)
local prefixed = 'https://mirror.test/' .. raw
assert(Mirror.apply(prefixed) == prefixed, 'never duplicate a selected prefix')
assert(Mirror.apply('https://example.test/a.zip') == 'https://example.test/a.zip')
print('archive routing: direct official ZIP, pinned revision, mirror compatibility and foreign URLs checked')
