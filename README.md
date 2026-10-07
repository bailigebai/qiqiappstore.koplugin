# qiqi 应用商店 · qiqiappstore.koplugin

版本：0.1.2。用于 KOReader，仅展示 GitHub 账号 **bailigebai** 下名称以 **`.koplugin`** 结尾的公开项目。

后续上传的新插件符合上述命名规则后，在商店点“刷新缓存”即可发现，无须修改商店代码。不要求 topics、星标，也支持该账号的公开 fork；名称如 `demo.koplugin.zip` 不会被纳入。

## v0.1.2 下载超时修复

仓库源码和发布附件的文件下载总时限从 60 秒提高至 300 秒，修复较慢网络下载 Legado、WebDAV 漫画等较大仓库时的 `sink timeout`。单次网络等待仍为 KOReader 原有时限，失败会关闭并清理不完整文件，不修改 KOReader 全局默认值。下载期间界面可能等待；超过 5 分钟仍会停止。请手动升级本商店并重启后重试。

## v0.1.1 修复

修复安装或重装 pluginhealth 0.1.2 时出现“Existing target cannot be identified safely because metadata has no literal name”的错误。原因是合法插件可能只在 main.lua 声明名称。新版本在元数据缺少名称时，交叉核对新旧入口文件的静态名称和目标目录，保留拒绝误覆盖、配置保留和回滚保护。

遇到此错误，请先手动覆盖升级 qiqi 应用商店至 v0.1.1，重启后再安装健康管家。无需删除健康管家，也不需要重置它的设置。

## 解压安装

1. 下载 [qiqiappstore.koplugin-v0.1.2.zip](https://github.com/bailigebai/qiqiappstore.koplugin/releases/download/v0.1.2/qiqiappstore.koplugin-v0.1.2.zip)，解压得到 `qiqiappstore.koplugin` 文件夹。
2. 将整个文件夹放入设备的 `koreader/plugins/` 目录。Kindle 常见位置为 `/mnt/us/koreader/plugins/`；请以设备实际 KOReader 目录为准。
3. 检查最终路径是 `koreader/plugins/qiqiappstore.koplugin/main.lua`。不要多套一层同名目录，也不要直接放 ZIP。
4. 完全退出并重新启动 KOReader，在主菜单中找到“qiqi 应用商店”（英文环境为 qiqi App Store）。
5. 联网后点“刷新缓存”，打开项目详情，阅读说明后选择安装。安装、更新或启用状态改变后按提示重启 KOReader。

升级本商店时，退出 KOReader 后用新文件覆盖原 `qiqiappstore.koplugin` 目录；自行创建的配置文件请保留。首次安装不需要 GitHub 登录或维护者的账号密码。

## 功能与使用

- **浏览**：项目列表、分页、搜索、排序、项目说明及 README。刷新完整读取账号项目列表，未来新增或更名项目按同一规则处理。
- **安装**：支持项目源码快照及 GitHub Releases 的版本/ZIP 附件；源码安装使用预检时的提交。目录由插件实际结构决定，不能只按仓库名称重命名。
- **更新**：在已安装管理中检查更新、选择发布版本、查看发布说明、忽略指定发布版本；没有 Releases 的项目仍可使用源码快照安装。
- **管理**：关联项目、启用、禁用、卸载及重启提示。只管理能通过本商店记录与缓存项目结构确认、或元数据与账号项目一致的本地插件；首次手动安装后先刷新目录。
- **离线查看**：已缓存列表可浏览；首次阅读 README 需要联网，之后显示缓存。需要新 README 时在设置里清理 README 缓存后重新打开。
- **下载来源**：默认 GitHub 直连，可在设置中自行选择上游支持的下载来源。第三方来源由使用者自行选择，不内置维护者令牌。

本商店与原 `appstore.koplugin` 使用不同的模块、配置、缓存和安装记录，可以同时安装。本商店不提供补丁市场。

## 当前项目示例

| GitHub 项目 | 实际安装目录 | 当前状态 |
| --- | --- | --- |
| ink2048.koplugin | ink2048.koplugin | 可安装 |
| wuziqi.koplugin | inkgomoku.koplugin | 可安装，保留实际目录名 |
| smartambientlight.koplugin | smartambientlight.koplugin | 可安装 |
| sokoban.koplugin | sokoban.koplugin | 可安装 |
| legado.koplugin | legado.koplugin | 已有公开源码和安装包 |

此表是项目示例（Legado 状态于 2026-10-07 更新），**不是程序白名单**。Legado 的代码、书源、安装包均未包含在本商店交付物中。

## 安装保护与说明

下载后先检查 `_meta.lua` 和 `main.lua`，拒绝不明确的多个插件目录、越界路径、符号链接和损坏归档。读取插件名和版本不执行下载的元数据代码。

新版本先解压到临时目录，通过检查后才替换原插件；替换失败尝试恢复旧版本。保留未随安装包分发的本地配置与存档；后续通过安装清单清理旧程序文件。第一次接管没有清单的旧目录时保守保留旧文件。设备外部的 KOReader 设置与书籍存档不由安装器清理。

运行时禁止卸载商店自身。安装需要临时空间容纳新文件、原插件及备份。无法模拟所有设备断电/磁盘故障；如提示备份清理或回滚失败，应保留提示中的备份目录，退出 KOReader 后恢复。

## 网络与兼容性

GitHub 请求失败或限流时保留原项目缓存，稍后刷新重试。可选个人配置模板为 `qiqiappstore_configuration.sample.lua`；使用时复制为 `qiqiappstore_configuration.lua`。配置自己的令牌时不要分享该文件，安装包不会收录它。

在 Lua 5.1、LuaJIT 2.1 做了自动化行为与语法检查，并对照 KOReader v2026.07.1 的归档接口核对。现代 KOReader 可弹窗阅读 Markdown，旧版本使用缓存文件阅读。**未在 Kindle/其他阅读器真机完成触摸、显示、Wi-Fi 与重启验收**；建议先安装本商店并尝试一个插件。

## 开发与来源

本仓库包含已发布安装包及对应运行源码。v0.1.2 发布前在 Lua 5.1、LuaJIT 2.1 共完成 18 组测试，包内 Lua 语法、模块完整性、可重复打包和凭据排除检查通过。慢速下载回归测试见 `tests/download_timeout_test.lua`，可在仓库根目录用 Lua 5.1 或 LuaJIT 执行。

新版本下载最长可等待 5 分钟；下载失败仍会清理不完整文件。真实 Kindle 网络环境尚待使用者验收。

基于 [omer-faruq/appstore.koplugin](https://github.com/omer-faruq/appstore.koplugin) 1.14.0 定制，沿用 GPL-3.0。作者版权、参考提交与改动说明见 [UPSTREAM.md](UPSTREAM.md)，完整许可证见 [LICENSE](LICENSE)。
