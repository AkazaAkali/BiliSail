# macOS 双标签打开播放页崩溃

日期：2026-10-25。用户报告 BiliSail 1.2.1+0 在 Apple M2 / macOS 26.5.1 上，双标签点击视频立即退出。本轮在 Windows 主机修复，macOS 新构建与设备复测待执行。

## 原因与证据

- 用户崩溃栈为主线程 `InternalFlutter_WindowController_CreateRegularWindow + 88 → NSAssertionHandler → SIGABRT`，与固定 Flutter 3.47.6 的原生窗口入口吻合。
- [MainFlutterWindow](../../macos/Runner/MainFlutterWindow.swift) 在 `awakeFromNib` 创建 `FlutterViewController()`，为 engine 关联 implicit 主 view；应用和插件基于该 view 启动。
- 固定 SDK 的窗口 FFI 在创建第二个窗口前调用 `FlutterEngine.enableMultiView`。该方法要求没有已关联的主 view controller，断言文字为 `Multiview can only be enabled before adding any view controllers.`。现有启动方式不满足条件，原生 Objective-C 异常跨 FFI 终止进程，Dart `try/catch` 和既有打开失败回退不能拦截。
- 本轮核对本地 SDK 提交 `5fc346839b5d0eef006ed8404392afb4dfae428d` 的 [FlutterWindowController.mm](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterWindowController.mm) 和 [FlutterEngine.mm](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm)。只修改 Dart 实验功能开关不能改变原生 engine 的前置条件。

## 修复与行为

- 第一次提交 `472883d` 加入能力防护，并临时使用应用内双标签。用户随后明确要求保留与 Windows 一致的双窗口，当前实现改为修正 macOS 的原生初始化顺序。
- [AppDelegate](../../macos/Runner/AppDelegate.swift) 持有唯一 headless engine；[MainMenu.xib](../../macos/Runner/Base.lproj/MainMenu.xib) 仅保留菜单，不提前创建原生主窗口／FlutterViewController。[原生宿主](../../macos/Runner/MainFlutterWindow.swift) 注册现有插件与通道，`prepareWindowing` 通过公开的 `engine.viewController` 确认无 implicit 原生控制器。
- [平台适配](../../lib/core/platform/macos_application_window.dart) 在创建任何窗口前完成原生预检；第一个 `RegularWindowController` 进入 multiview 并创建明确的主浏览 view，以 `runWidget` 挂载。Dart 侧仍可能存在没有原生控制器的占位 view 0，因此不能靠 `PlatformDispatcher.implicitView == null` 判断原生条件。
- [组合根](../../lib/app/dependencies.dart) 注入该主窗口的 `WindowService`；SDK 管理的窗口跳过 `window_manager.ensureInitialized`，避免其强取不存在的 implicit 原生 view 并覆盖 SDK 的 NSWindow delegate。核对固定依赖：其他已注册插件不依赖 registrar.view；media_kit 输出使用 engine 的纹理注册器，其旧原生全屏工具不用作应用全屏路径。
- [独立播放适配](../../lib/core/platform/detached_playback_window.dart) 继续复用同一 engine、isolate 和现有工作区。双标签保留主浏览窗与唯一播放窗，覆盖视频、影视、直播和离线，媒体返回、关闭与页面／会话保留规则不变。Windows 和 Android 继续各自的现有启动方式。
- 主窗口关闭通过 `ServicesBinding.exitApplication` 发起退出，沿用 `AppLifecycleListener` 等待资源释放；重复关闭合并。热重启期间 SDK 关闭所有窗口时，AppDelegate 不因暂时无窗口而终止进程。正常启动失败页面与 Release smoke 卸载同样挂到明确的主 view。
- 保留原生预检和 FFI 前的防护：未取得原生确认的替代入口不能创建窗口。没有修改 Flutter SDK、Pub 缓存、插件依赖、账号数据或设置快照。

## 全屏原生标签关闭（2026-10-25）

用户复测确认双窗口可以播放，但先全屏再打开视频时，macOS 会将浏览窗和播放窗显示为带关闭按钮的原生标签；点击主浏览窗标签的关闭按钮会退出并弹出崩溃提醒。本轮没有取得该次崩溃栈，以下修正针对源码中确认存在的退出重入风险，是否消除该设备上的崩溃仍需 Mac 复测。

- 固定 SDK 的 `FlutterWindowOwner.windowShouldClose` 进入 `IsolateScope` 后，通过 isolate-local FFI 回调通知 Dart。主窗口原来在这个回调内立即调用 `ServicesBinding.exitApplication`。现改为 `Timer.run` 投递退出请求，先退出原生窗口关闭回调，再进入既有应用清理流程；等待期间仍合并重复关闭。
- 原生 `ApplicationTerminationCoordinator` 原来在 `System.requestAppExit` 的回复回调内同步调用 `NSApp.terminate`，会在 Flutter 消息栈尚未返回时进入 `applicationWillTerminate` 并关闭 engine。现改为下一轮主线程队列终止，清理获准至队列执行之间仍保持等待状态，重复 Cmd+Q 不能提前放行；取消后仍可重试。
- 保留主窗口标签的关闭入口以及播放窗口只关闭自身的行为；关闭主窗口仍表示清理后退出整个应用。没有更换 SDK 的窗口 delegate、禁用原生标签、修改 Flutter SDK 或增加设置。
- [原生单元测试](../../macos/RunnerTests/RunnerTests.swift) 扩展为 4 项，覆盖清理等待／排队期间重复退出、取消重试、同步清理回复仍延后终止，以及默认调度器在主线程等待回复返回。须在 Mac 执行：`xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -only-testing:RunnerTests`。
- `tool/check.ps1 -SkipPub` 通过：根应用 2606、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 3238 项离线测试；格式、静态分析和打包边界检查通过。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生验证。日志为 `build/macos-fullscreen-close-check.log`。两份改动文档的 24 个本地链接及 `git diff --check` 通过。DTD 没有可连接的调试应用，热重载请求未能执行；Swift 改动需要重新编译宿主。
- 当前 Windows 主机没有 macOS/Xcode，尚未编译 Swift 或执行上述 XCTest。设备验收需覆盖先全屏再打开视频并关闭主标签、非当前主标签的关闭、播放标签单独关闭与重开、普通主窗关闭和重复 Cmd+Q；确认退出后进程正常结束且没有系统崩溃提示。未进行性能测量。

## 验证

- 原生预检通过、拒绝和错误时的能力撤销；未准备的引擎在 FFI 前拒绝直接创建。主窗口握手传递自身 view／handle，失败不被吞掉。
- 明确的主 view 与播放 view 同时挂载、反复移除播放 view 后浏览子树与窗口服务保持；主窗口初始化、激活和全屏不调用 window_manager。
- Mac 平台变体使用已获原生确认的独立窗口路径：四类媒体复用一个播放窗，浏览状态与 ProviderScope 保留，聚焦、返回、关闭行为正确。真实 router 与 fake player 覆盖连续打开两个视频、缩放、返回、关闭，复用唯一会话和 engine，关闭只释放一次。
- [原生窗口 smoke](../../integration_test/detached_playback_window_smoke_test.dart) 使用生产初始化并创建、关闭两轮播放窗；[Release startup](../../lib/app/release_smoke.dart) 在同一待打包 bundle 执行该流程，验证 view 数量、非空视口、标题栏返回通道、窗口激活和回收，能力回退不算通过。
- 本轮 `tool/check.ps1 -SkipPub` 通过：根应用 2332、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 2964 项测试；格式、静态分析及打包边界检查通过。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/macos-dual-window-check.log`，计数包含检查时工作区的同期修改；提交仅包含本任务文件。
- 44 项窗口／启动定向回归与 64 项工作区回归通过，日志为 `build/macos-window-bootstrap-targeted.log`、`build/macos-window-bootstrap-workspace.log`。128 条相关 Markdown 本地链接、MainMenu XML 解析与 `git diff --check` 通过。
- 当前主机无 macOS/Xcode，尚未执行 macOS 构建、原生 smoke、真实音视频或输入／全屏／安装复测；新增发布门槛须在 Mac 运行才算通过。
- 固定 SDK 的旧截图和原生语义桥仍存在只查 implicit 控制器的实现；VoiceOver／语义与截图能力需在 Mac 单独验收，本轮不据窗口 Widget 回归宣称通过。未发现可连接的调试应用，热重载请求未成功；未进行性能测量。
