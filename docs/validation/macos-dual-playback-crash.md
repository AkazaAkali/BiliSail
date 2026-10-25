# macOS 双标签打开播放页崩溃

日期：2026-10-25。用户报告 BiliSail 1.2.1+0 在 Apple M2 / macOS 26.5.1 上，双标签点击视频立即退出。本轮在 Windows 主机修复，macOS 新构建与设备复测待执行。

## 原因与证据

- 用户崩溃栈为主线程 `InternalFlutter_WindowController_CreateRegularWindow + 88 → NSAssertionHandler → SIGABRT`，与固定 Flutter 3.47.6 的原生窗口入口吻合。
- [MainFlutterWindow](../../macos/Runner/MainFlutterWindow.swift) 在 `awakeFromNib` 创建 `FlutterViewController()`，为 engine 关联 implicit 主 view；应用和插件基于该 view 启动。
- 固定 SDK 的窗口 FFI 在创建第二个窗口前调用 `FlutterEngine.enableMultiView`。该方法要求没有已关联的主 view controller，断言文字为 `Multiview can only be enabled before adding any view controllers.`。现有启动方式不满足条件，原生 Objective-C 异常跨 FFI 终止进程，Dart `try/catch` 和既有打开失败回退不能拦截。
- 本轮核对本地 SDK 提交 `5fc346839b5d0eef006ed8404392afb4dfae428d` 的 [FlutterWindowController.mm](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterWindowController.mm) 和 [FlutterEngine.mm](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm)。只修改 Dart 实验功能开关不能改变原生 engine 的前置条件。

## 修复与行为

- [窗口适配](../../lib/core/platform/detached_playback_window.dart) 集中判断能力：macOS 已有 implicit view 时不支持独立窗口；`create` 同样在启用窗口 owner 和调用原生 FFI 之前拒绝，保护未来直接调用者。
- [组合根](../../lib/app/bili_app.dart) 按能力注入窗口构建器。当前 macOS 双标签使用已有应用内浏览／播放槽：打开媒体显示播放页，保留隐藏浏览状态，媒体返回恢复上一内容，关闭释放播放会话并回浏览页。视频、影视、直播与离线共用此规则；导航偏好仍是双标签，不改数据库或保存设置。
- Windows 保持独立播放窗。设置说明与 README 同步区分当前平台行为。
- macOS 独立播放窗仍是后续迁移目标：需从原生启动开始使用无 implicit view 的 engine，并一起验证主窗口创建、插件 registrar、输入、全屏、退出和 Release smoke；本轮不通过移除断言或修改 SDK 绕过该约束。

## 验证

- 窗口适配回归：macOS implicit view 条件下直接创建返回 `UnsupportedError`，不启用实验窗口 owner、不新增 view；Windows 保留支持。
- 工作区回归：macOS 能力检查下不创建原生播放窗，浏览／播放页面及 ProviderScope 保留，媒体历史返回和关闭行为正确。
- 真实 router 与 fake player 回归：macOS 双标签连续打开两个视频、缩放、返回、关闭，复用唯一会话和 engine，关闭后仅释放一次。
- [原生窗口 smoke](../../integration_test/detached_playback_window_smoke_test.dart) 加入 macOS implicit-view 防护分支，供 Mac 运行；Windows 原有窗口覆盖保留。
- `tool/check.ps1 -SkipPub` 通过：根应用 2249、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2，共 2871 项测试；五处格式、静态分析及打包边界脚本通过。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不能计为原生通过。日志为 `build/macos-dual-playback-check.log`。
- 238 条相关 Markdown 本地链接与 `git diff --check` 通过，依赖和锁文件未变。
- 当前主机无 macOS/Xcode，未执行 macOS 构建、原生 smoke 或真实音视频复测；本轮也未构建 Android/Windows 或进行性能测量。DTD 未发现可连接的调试应用，热重载请求返回无活动连接，未执行成功。
