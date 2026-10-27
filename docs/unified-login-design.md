# 统一 Web / App 登录

日期：2026-10-28。取代 App 推荐的独立扫码授权，由既有 SessionRepository 统一拥有 Cookie、App token 和登录提交。

## 协议与职责

- 只读参考 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的 `http/login.dart`、`pages/login/controller.dart` 和账号拦截器，独立实现。HD 扫码成功结果是顶层 token 字段与 `cookie_info.cookies`，兼容有明确 token_info 的响应；不能仅使用之前测试虚构的嵌套结构。
- 普通扫码改用 HD auth_code / poll，一次扫码同时取得两种凭据。密码/短信继续复用内嵌官网，在隔离 Cookie/nav 校验后执行 auth_code → Cookie/CSRF confirm → poll，不增加第二个扫码窗口。confirm 仅作为明确登录动作的组成部分，单次提交，失败不自动重放。Cookie 转 token 的补充依据为 bili-kernel TvAuthorizeClient 与 PiliPlus 端点声明。
- API 包解析 Cookie 的域、path、secure、有效期和数量/长度，允许的 Cookie 只归属 bilibili.com HTTPS；nav.mid 必须与 token.mid 匹配。确认端点只允许 passport.bilibili.com 的固定路径，不拓宽 App 推荐的无 Cookie 传输。
- SessionRepository 在既有凭据串行队列内写一份 version=2 的完整安全快照，再提交内存会话；保留 generation、取消、账号清理和失败回滚。version=1 的已有 Web 会话可恢复，不凭空产生 App token。不提供“更新登录”入口；缺少 App 凭据时在设置中提示重新登录，旧 Web 会话不自动执行凭据转换。
- 通过 auth/domain 的纯 Dart 凭据端口供 data 层读取 App token，UI 只获取是否可用的摘要。推荐身份仓储继续管理 buvid 和旧安全槽兼容读取；统一凭据优先，即使失效也不回退旧 token。修改设备标识使对应 token 失效，通过正常流程重新登录。
- 移除推荐设置的独立扫码入口、授权控制器和授权 attempt 接口。推荐反馈继续显式点击、单次写入，授权失效指向正常登录。

## 验证

覆盖真实结构的 HD 双凭据响应、Cookie/CSRF 与目的地限制、nav/token UID 一致、单次 confirm、旧快照恢复、双凭据一起保存/回滚、取消/登出/迟到写入、内嵌官网登录、推荐立即复用及失效隔离。执行定向测试后运行根 check.ps1 -SkipPub；保留已有弹幕、窗口、版本及文档修改，只提交本任务文件。没有真实账号登录与设备性能验收时明确列为未测，不自动操作保存的真实凭据。

## 实施入口

- [扫码与 Cookie 交换客户端](../packages/bili_api/lib/src/clients/app_passport_client.dart)同时解析顶层/嵌套 token，返回有界且校验过的 Cookie 模型；自生成 auth_code 的 confirm 使用单次 Cookie/CSRF POST。确认后的 pending 结果最多读取三次，间隔 250 ms，不重放 confirm，仍受总 deadline 约束。
- [统一会话仓储](../lib/features/auth/data/session_repository.dart)继续拥有唯一登录 generation、Cookie jar、凭据队列和账号提交。两种登录在 nav/token UID 校验、安全快照保存及旧账号任务清理后才进入 signedIn。App token/refresh token、过期时间、buvid 和失效标记只进入系统安全存储。
- [纯 Dart 凭据端口](../lib/features/auth/domain/app_session_credentials.dart)只供数据层使用。[推荐身份仓储](../lib/features/feed/data/app_recommendation_identity_store.dart)继续保存设备标识并按当前账号隔离旧槽；冷启动期间读到的旧 token 在 Web 账号恢复确认前不可用，避免丢失有效旧授权，也不跨账号暴露。统一 token 优先，过期/失效时不回退旧槽或游客。
- [推荐设置](../lib/features/settings/presentation/app_recommendation_identity_settings.dart)只显示设备编辑与登录摘要，缺少/失效时提示重新登录。独立授权控制器、attempt 端口和扫码模态已删除；不存在“更新登录”入口。
- [API 回归](../packages/bili_api/test/unified_login_test.dart)新增 8 项，[统一登录回归](../test/features/auth/unified_login_test.dart)新增 12 项；原会话/WebView 测试按双凭据接口更新，[旧槽与设备测试](../test/features/feed/app_recommendation_identity_test.dart)覆盖冷启动恢复、账号隔离、统一凭据优先、设备变更及旧槽删除失败。设置 Widget 明确断言独立扫码与更新登录入口不存在。

本轮没有真实账号 HD 扫码、官网密码/短信提交、Cookie confirm 在线写入或设备构建/运行验收。公开源码和 fixture 证明实现与离线契约，不代表上述真实账号流程已经在线通过；未读取或转换机器上保存的真实凭据。

## 最终检查（2026-10-28）

`tool/check.ps1 -SkipPub` 通过，日志 `build/unified-login-check-commit.log`：根应用 3185、bili_api 495、bili_player 83、bili_danmaku 109、bili_mux 5，共 3877 项测试通过，格式/静态分析及打包边界检查通过。Windows 符号链接 13 项、未配置 `BILI_MUX_LIBRARY` 的原生 mux 10 项跳过，不计为原生通过。数量为检查时整个工作区，含同期其他任务的已有测试，不将其列为本任务新增。

相关 7 份文档的相对链接和 `git diff --check` 通过。提交范围限于统一登录、推荐身份适配、相关 API/测试与文档，窗口、弹幕性能、版本及其他文档改动保留在工作区。
