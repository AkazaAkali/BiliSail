# Android 预测式返回

日期：2026-10-25。

## 行为与边界

- Android Manifest 显式开启 `android:enableOnBackInvokedCallback`。Android 14 及以上通过 Flutter 的系统返回手势事件驱动工作区内容的位移、缩放、圆角和透明度；左右边缘均支持，取消手势回到原位。旧系统、实体返回键及三键导航沿用现有返回入口。
- 工作区保留页面，不在 go_router 的占位路由上执行 pop。`WorkspaceTabs.backDestination` 只读取返回目标；手势确认动画结束后才调用既有返回逻辑。双标签关闭离开的临时浏览页，播放先回退媒体历史，历史为空才关闭会话；多标签沿访问历史选择上一页。
- 可复用的上一页在当前页后方预览，保持 `WorkspaceActivity.active=false`、无焦点、无指针和无障碍参与，不激活隐藏播放器。共用同一槽位的旧媒体或消息入口根页面，显示目标名称提示；不为预览重载旧媒体、创建第二个播放器或抓取屏幕快照。
- `PageBackHandler` 的页内详情优先于工作区返回。弹窗、图片查看和全屏等已有独立路由继续由自己的返回入口处理；本轮不新增这些路由的手势动画。根页保留退出确认，因此不直接触发系统返回桌面的预览。
- 手势期间页面特征树不随进度逐帧重建，只有局部变换更新。路由、导航模式、账号身份、页内返回能力、模态、窗口尺寸、输入法或应用活动状态改变时废弃旧手势；迟到的确认不能返回新页面。遵循系统减少动画设置，省略缩放／位移和结束过渡。

## 实现与来源

- [手势区域与局部变换](../../lib/core/presentation/predictive_back_region.dart)、[工作区接入](../../lib/app/shell.dart)、[只读返回目标](../../lib/app/workspace_tabs.dart)、[Android Manifest](../../android/app/src/main/AndroidManifest.xml)。
- 采用 Flutter 3.47.6 自带的 `WidgetsBindingObserver` 预测手势 API，不增加依赖，不修改 Flutter SDK 或 Pub 缓存。普通 Material 路由沿用 SDK 默认的预测式返回过渡。
- 官方依据：[Android 预测式返回迁移](https://docs.flutter.dev/release/breaking-changes/android-predictive-back)、[Flutter 默认 Android 过渡](https://docs.flutter.dev/release/breaking-changes/default-android-page-transition)、[Android 接入要求](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture)。本轮使用公开 API 和独立工作区变换实现，没有复制上游实现代码。

## 验证

- [平台通道组件测试](../../test/app/predictive_back_test.dart)覆盖双／多标签、左右边缘、取消保留页面状态、确认关闭、媒体历史、根页退出确认、页内返回／模态／全屏优先、路由／键盘／模态中途变化、确认收尾期间导航、减少动画及逐帧构建次数。[工作区模型测试](../../test/app/workspace_tabs_test.dart)比较预览与实际返回目标，验证读取不消耗历史。
- 导航、评论详情和工作区专项回归 174 项通过，日志 `build/predictive-back-regression.log`。此后新增的全屏、减少动画和确认收尾竞态用例随完整检查通过。
- `tool/check.ps1 -SkipPub` 通过：根应用 2355、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 2987 项测试通过，五处格式／静态分析和打包边界检查通过。10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。日志 `build/predictive-back-check.log`；这是检查时的共享工作区快照，包含同期其他任务改动。
- `tool/build-download-mux.ps1 -Target android-arm64` 通过，日志 `build/predictive-back-android-mux.log`。
- `flutter build apk --profile --target-platform android-arm64 --no-pub` 通过，产物 `build/app/outputs/flutter-apk/app-profile.apk`（约 118.5 MB），日志 `build/predictive-back-android-profile.log`。这是使用调试签名的 Profile 测试包，不能覆盖正式发布签名安装的应用；构建仍输出已有的 CupertinoIcons 字体资源提示，本轮未修改字体依赖。
- 本地未连接 Android 设备，本轮未启动模拟器；真实系统边缘手势、输入法关闭优先级、画面手感与 Profile/Release 性能仍待设备验收。组件事件注入不等同于系统手势验收。未构建或实机验证 Windows/macOS；现有 Windows/macOS 导航组件回归通过。没有运行中的 DTD／调试应用，热重载请求未能执行。
- 文档索引和本页共 135 个本地链接、Manifest XML 解析及任务文件的 `git diff --check` 通过。
