# 双标签与多标签弹窗一致性

日期：2026-10-25。

## 问题与修复

桌面双标签打开独立播放窗口时，窗口适配器开启固定 Flutter 3.47.6 的实验性 windowing。SDK 的 `showDialog` 在发现 `WindowRegistry` 后会通过 `showRawDialog` 创建原生 DialogWindow，导致弹幕配置、播放配置、收藏等组件多出独立系统窗口。该标志在播放窗口关闭后仍保持开启，影响范围不限于当前播放页面。

应用统一通过 `lib/shared/ui/app_dialog.dart` 的 `showAppDialog` 显式推入 `DialogRoute`。播放配置、收藏/投币、下载、登录、评论/直播表情、字体选择、快捷键设置和更新提示共用此入口，继续使用原组件、Material 动画、遮罩、主题、焦点循环和返回结果。主窗口、多标签与 Android 也使用同一入口，不按导航模式另建弹窗样式。

默认选择当前 Flutter View 内的最外层 Navigator，遇到 View 边界停止祖先查找，避免独立播放窗的弹层进入浏览窗口。`useRootNavigator: false` 继续允许使用当前嵌套 Navigator。模态路由仍为 PopupRoute，既有输入宿主可继续隔离快捷键与原生返回按钮。已有图片预览和全屏直接使用 DialogRoute/RawDialogRoute；菜单、下拉框及账号抽屉已有的窗口内弹层路径保持。

没有修改 SDK、Pub 缓存或切换全局 windowing 标志来显示弹窗；独立播放窗口继续由原适配器创建。

## 回归

- `test/shared/ui/app_dialog_test.dart` 覆盖 windowing 开/关、双 View 各自的 Navigator、嵌套导航选择、主题/遮罩、焦点循环、结果返回、遮罩关闭、Escape 及模态观察状态。
- 实际播放/弹幕设置、收藏与投币组件测试在开启 SDK windowing 的环境中继续验证设置持久化、失败回退及显式确认后单次写入；使用 fake 仓储，不访问真实账号。
- `integration_test/workspace_dialogs_test.dart` 在 Windows/macOS 原生宿主创建浏览及播放两个 View，验证两窗分别打开/关闭弹层时 View 数量保持两个、弹层归属正确，关闭播放窗后恢复原数量。

## 本轮结果

- `tool/check.ps1 -SkipPub` 通过，日志 `build/validation/workspace-dialogs/check.log`：根应用 2237、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2，共 2859 项通过，五处格式/静态分析和打包边界脚本通过。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生封装通过。计数包含检查时工作区中的其他同期修改。
- `flutter test --no-pub -d windows integration_test/workspace_dialogs_test.dart --reporter expanded` 通过，日志 `build/validation/workspace-dialogs/windows-integration.log`。Windows Debug 构建和实际原生双窗口弹层打开/关闭、归属及窗口数量回归通过。第三方 inappwebview 既有 CMake CMP0175 开发警告不影响构建。
- DTD 未发现运行中的调试应用，热重载工具返回无活动连接；代码已通过上述新启动的 Windows 原生测试应用验证。
- 未执行 Windows Release 构建、真实账号收藏/投币或真实视频手动操作；未构建/运行 Android、macOS，未测性能。本次没有账号在线写操作。保留同期窗口、图片等修改，提交只包含本次弹窗入口、调用点、测试和文档。
