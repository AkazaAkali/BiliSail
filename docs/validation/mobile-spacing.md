# 手机首页与视频详情间距（2026-10-28）

## 范围

仅 Android/iOS、物理显示短边小于 600 逻辑像素且窗口宽度小于 600 的手机布局收紧装饰留白；折叠显示特征及较大字体（14sp 缩放后超过 18）保留原间距。窄桌面窗口和窄平板分屏不套用手机间距。

- 首页搜索工具栏高度 52 → 48，频道栏 58 → 50；搜索框、频道按钮样式、图标及字号不改。
- 视频详情顶端间距 16 → 12，作者与标题间距 18 → 12，信息分隔线高度 36 → 20。
- 不改视频裁切/填充、不推断源内黑边；不重设计导航、不缩小账号、关注、互动按钮或文字。

## 验证

已通过：

- `flutter pub get --enforce-lockfile`。
- 本次 6 个 Dart 文件格式检查与静态分析（No issues found）。
- `flutter test --no-pub test/shared/ui/compact_phone_spacing_test.dart test/app/shell_layout_test.dart test/features/video/video_screen_test.dart`：113 项通过。
- `git diff --check`。
- 整合回归发现旧 Android DPI fixture 只设置窗口尺寸，未同步物理显示尺寸。补齐 `TestDisplay` 尺寸/DPR 和 teardown 后，上述测试与 `android_dpi_adaptation_test.dart` 共 242 项通过；最终 DPI 文件单独重跑 129 项通过。不改产品逻辑或几何断言。

覆盖手机首页工具栏、搜索框尺寸、频道按钮尺寸、视频详情分隔与作者区域尺寸，以及 Android/iOS/Windows、平板显示和大字条件的 widget 测试。相关既有首页布局与视频页面测试一起回归。

本记录不代表 Android/iOS 真机视觉或点击体验已验收；需在整合测试包中由用户检查。未在本独立分支运行全仓 `tool/check.ps1` 或原生构建，由整合任务执行并单独记录。
