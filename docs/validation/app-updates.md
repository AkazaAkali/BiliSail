# 关于页与每日更新检查

日期：2026-10-06。在已有工作区修改上增量实现。

## 行为与边界

关于页显示真实应用版本、可点击的 `https://github.com/CKopoer/BiliSail` 和“检查更新”。应用启动后不阻塞首屏，每个本地日历日首次启动检查一次；先持久化尝试日期，自动检查失败或没有新版本时不弹窗，当天重启不再次检查。手动检查不受日期限制，有加载状态和明确结果，与正在进行的自动检查共享同一次请求。

2026-10-24 调整自动提醒规则：按 `major.minor.patch` 持久化最后自动提醒的版本，同一版本跨日、重启或仅增加 `+N` 构建号均不再自动弹窗；例如已提醒 `1.1.1+3` 后，`1.1.1+4` 保持安静，发现 `1.1.2` 时再次提醒。记录只向更新的版本推进，远端候选回退不会重新提醒旧版本。每日查询仍照常进行；手动点击“检查更新”绕过自动提醒记录，每次仍可提示包含最新构建号的新版本，合并进自动请求的手动检查也遵守此规则。

2026-10-25 调整版本渠道：手动与每日自动检查均排除 GitHub 标记为 `prerelease: true` 的预览版本和 `draft: true` 的草稿，只从正式 Release 中选择候选；即使预览版使用普通 `v1.2.3+4` 标签也会排除。只有草稿／预览版时不报协议错误，手动检查提示“暂无已发布的正式版本”，自动检查保持安静，也不写入自动版本提醒记录。

新版本弹窗显示版本与更新说明；“稍后再说”关闭弹窗，“前往 Release”调用系统浏览器打开该版本页面。只有用户点击才打开外部页面，不自动下载、安装或打开浏览器。提示由进程级宿主管理，切换或关闭设置标签不会取消整个应用的更新检查；同一请求不产生重复弹窗。退出或请求超时会取消网络读取，迟到响应不更新状态。

## 协议、版本与存储

- 独立无凭据 `HttpClient`，单次 GET `https://api.github.com/repos/CKopoer/BiliSail/releases?per_page=100`；`Accept: application/vnd.github+json`、`X-GitHub-Api-Version: 2026-03-10`。不附 Bilibili Cookie/token，不跟随重定向、不自动重试，保留系统 TLS 验证。
- 检查列表第一页最多 100 个 Release，要求 `draft`、`prerelease` 为 JSON 布尔值，且二者均为 `false` 才参与版本比较；不根据标签名称推断 GitHub 的预览标记。空列表或全部被渠道筛选排除表示暂无正式发布；存在正式候选但格式错误时不伪装成“已是最新”。仍保留最多 100 项的查询上限，不继续翻页查找更早的正式版。
- 2026-10-25 核对 [GitHub List releases 官方协议（API 2026-03-10）](https://docs.github.com/en/rest/releases/releases?apiVersion=2026-03-10#list-releases)：公开资源可匿名读取，响应为 Release 数组，分页参数只有 `per_page`（最多 100）和 `page`，不提供服务端排除预览版的查询参数，因此在客户端检查 `draft`／`prerelease`。另有 [Get the latest release](https://docs.github.com/en/rest/releases/releases?apiVersion=2026-03-10#get-the-latest-release) 返回单个非草稿、非预览版对象；官方说明其 latest 选择关联 `created_at`，不等同于本项目按语义版本和数字构建号取最大值，因此继续使用列表端点筛选正式版。
- 版本先按 `major.minor.patch` 与预发布标识比较，再比较数字 Flutter `+N` 构建号，支持 `v0.1.0+2`。同一语义版本的不同数字构建仍被识别为更新，但自动弹窗按三段版本号去重，手动检查不受此限制；非数字构建元数据不改变优先级，不按字符串字典序比较。
- `package_info_plus 10.2.2` 从已有锁定的传递依赖提升为直接依赖，BSD-3-Clause，支持 Android/Windows/macOS，未改变解析版本。常规运行读取平台包版本，[Release 脚本](../../tool/build-release.ps1) 通过 `BILISAIL_RELEASE_VERSION` 注入实际 `x.y.z+N`，避免 Android split APK 的 `versionCode +2000` 被当作 Release 构建号。自行执行 split APK 构建时应传相同 Dart define。
- 网络总读取期限 12 秒，整个检查期限 20 秒；响应最多 2 MiB，展示说明最多 12000 字符。说明以纯文本显示；只接受本仓库的 HTTPS Release 链接，拒绝其他 host、仓库、端口、userinfo、query 或 fragment。
- 日期写入既有 `settings` 表的 `app_update.last_startup_day.v1`，最后自动提醒的三段版本号写入 `app_update.last_prompted_version.v1`，与账号无关。提醒记录在发布待显示提示前通过事务认领，读取或保存失败时自动检查保持安静；退出或超时后的存储响应不能恢复弹窗。不改表、不改变当前 SQLite schemaVersion 3、不清空设置或历史；版本查询、HTTP、日期及提醒存储与链接打开均通过应用层注入。

## 参考与采用范围

只读参考相邻 biliuwp-lite 提交 `7c1baab53a5afb80235323ef5b37463e4b93db9f`：

- [AboutSettingsControl.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/AboutSettingsControl.xaml) / [代码](../../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/AboutSettingsControl.xaml.cs)：关于页检查入口。
- [BiliExtensions.CheckVersion](../../../biliuwp-lite/src/BiliLite.UWP/Extensions/BiliExtensions.cs)：版本比较、更新说明弹窗和查看详情。
- [App.xaml.cs](../../../biliuwp-lite/src/BiliLite.UWP/App.xaml.cs)：窗口启动后的静默检查入口。
- [GitApi.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/GitApi.cs)：参考项目使用自有 `new_version.json`，本项目独立接入自己的 GitHub Release。

仅借鉴流程与职责，独立编写 Dart/Flutter；未复制 C#/XAML、资源、版本描述 schema，亦不依赖或修改相邻仓库。参考项目每次 release 启动检查，本项目按用户要求增加每日尝试记录；未加入忽略版本或镜像更新地址功能。

## 验证

离线测试覆盖版本及构建号排序、预览/草稿、空列表、错误协议与链接、容量、SQLite 日期重开、跨日/失败后重启、手动合并、取消/超时与迟到结果、窄窗口、弹窗确认及浏览器打开失败。Windows 原生入口为 [windows_app_updates_test.dart](../../integration_test/windows_app_updates_test.dart)，在线读取需显式 `--dart-define=BILI_UPDATES_ONLINE=true`，正常检查不访问真实账号或外网。

2026-10-25 正式版筛选：更新专项 33 项测试通过，覆盖高版本预览版不遮挡正式版、只有草稿／预览版时无候选、GitHub 布尔字段校验，以及实际 Repository 到手动／自动检查控制器的行为。`tool/check.ps1 -SkipPub` 通过格式、静态分析、打包边界和离线测试：根应用 2687、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2 项通过；mux 另有 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，日志 `artifacts/app-updates-stable-check-20261025.log`。另通过实际 `GitHubUpdateRepository` 的匿名 HTTP 请求取得正式版 `1.1.1+7`，确认 `prerelease: false`，日志 `artifacts/app-updates-stable-online-20261025.log`。Windows 集成测试 fixture 已加入更高版本的预览版并保留正式版提示断言，但本次未执行原生集成测试、构建或三端实机验收；未发现运行中的调试实例可供热重载。

2026-10-24 自动提醒调整：更新专项 28 项离线测试通过，包含数据库重开后保留提醒记录、同版本跨日与构建号变化静默、下一三段版本再次弹窗、手动重复检查与合并请求仍提示、存储迟到响应不恢复弹窗。`tool/check.ps1 -SkipPub` 通过根应用与四个包的格式、静态分析、离线测试和打包边界检查；mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，日志 `artifacts/app-updates-version-reminders-check.log`。此次未构建或进行 Windows／Android／macOS 实机验收，无运行中的调试实例可供热重载；下方为 2026-10-06 的历史验证记录。

本轮在 Windows / Flutter 3.47.6 / Dart 3.13.5 完成：

- `tool/check.ps1 -EnforceLockfile` 通过：根应用 641、bili_api 207、bili_player 16、bili_danmaku 21 项，共 885 项；根应用和三个包格式检查、静态分析均通过。更新专项 24 项包含在根应用计数中；日志 `artifacts/app-updates-check.log`。
- `flutter test integration_test/windows_app_updates_test.dart -d windows --dart-define=BILI_UPDATES_ONLINE=true` 通过 2 项。真实 Windows 包读取 `0.1.0+1`，原生窗口显示更新提示，SQLite 当日标记与弹窗操作正确；实际无凭据 GitHub 查询取得已公开的 `0.1.0+2`。外部打开端口在此测试中记录目标 URI，没有实际启动浏览器；日志 `artifacts/app-updates-windows.log`。
- 原生截图 `artifacts/app-updates-windows.png` 已查看，关于页、版本、GitHub 地址、检查入口与更新弹窗布局正常。
- 显式 `BILISAIL_RELEASE_VERSION=1.2.3+45` 的版本读取回归通过，验证发布版本覆盖平台包的原生版本码；日志 `artifacts/app-updates-version-override.log`。
- `flutter build windows --debug` 的普通应用入口构建成功，产物 `build/windows/x64/runner/Debug/bilisail.exe`；日志 `artifacts/app-updates-build.log`。PowerShell 构建脚本语法、110 条本地文档链接及 `git diff --check` 通过。

正常离线检查不访问真实账号或外网，本轮只读访问 GitHub，没有发布 Release、下载更新包或更改账号。Android/macOS 构建与实机运行、真实系统浏览器打开，以及修改后版本的 MSIX 安装升级待验证；Windows 原生验证不代表这些平台或安装链路已经验收。
