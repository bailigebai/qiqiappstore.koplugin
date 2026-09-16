# 来源与修改

本项目基于 [omer-faruq/appstore.koplugin](https://github.com/omer-faruq/appstore.koplugin) 开发。

- 上游版本：1.14.0
- 固定参考提交：`9d6c5795a264e924006e8f002271db0869ddd861`
- 本分支版本：0.1.0，2026-09-16
- 许可证：沿用 GPL-3.0，完整条款见 LICENSE；上游作者版权及贡献归原作者所有。

本分支隔离了插件标识、模块、配置、缓存与安装记录；将发现来源改为 bailigebai 公开仓库分页列表与 `.koplugin` 后缀校验；关闭补丁入口；增加目录结构预检、静态元数据读取、分阶段安装与失败回滚、README 共享缓存及自动化测试。

这是独立维护的定制版本，不代表上游作者背书。保留上游主体界面代码以便追踪差异；账号规则见 qiqiappstore_policy.lua，入口限制见 qiqiappstore_scope.lua，安装事务见 qiqiappstore_archive.lua。
