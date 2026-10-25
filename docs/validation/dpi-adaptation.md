# DPI 与文字缩放检查

日期：2026-10-25。基于当前工作区源码，工具链为 Flutter 3.47.6 / Dart 3.13.5。

## 修复结果（2026-10-25）

按用户要求，优先处理常见密度和系统字号范围内的问题，不针对极端自定义 DPI 扩大改造：

- [共享网格](../../lib/shared/ui/responsive_card_grid.dart) 改为采样实际视频标题的 15 逻辑像素字号，再按该比例计算卡宽阈值。Android 非线性缩放下，小字号变大、大字号不变时也能正确减少列数；保留原有默认列数、三列平板策略、间距和缩放上限。320 dp／200% 字体时由双列约 153 宽变为单列约 312 宽；360 dp／130% 字体时单列约 352 宽。
- [溢出标题提示](../../lib/shared/ui/highlighted_text.dart) 支持触摸长按全文，桌面悬停继续可用。新增普通／搜索高亮标题的行为回归，确认长按不会误打开视频，随后正常点击仍只打开一次。
- Windows 主窗口保留原来 420×560 的逻辑最小尺寸，在插件处理 `WM_GETMINMAXINFO` 后，按[当前显示器工作区限制物理最小尺寸](../../windows/runner/window_size_constraints.h)。尺寸足够时不变；较小屏幕或高缩放时保留任务栏空间，避免最小窗口超出工作区。每次消息都读取当前显示器，不缓存 DPI 或工作区。

验证结果：

- 四项新增问题回归先失败、修复后全部通过；非线性字体样本来自前一轮真实 Android 系统曲线。
- `tool/check.ps1 -SkipPub` 的格式、分析、打包边界和 **3221 项测试全部通过**：根应用 2589、API 456、播放器 81、弹幕 93、mux 2；另有 10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/validation/dpi-fix/check.log`。
- Android API 36 模拟器 **6 组配置、18 个页面状态通过**：420 dpi 的 100%／150% 字体、480 dpi 的 130%／200%、540 dpi 的 130%／200%。除布局断言外，设备上实际长按普通／搜索标题查看全文，再恢复列表位置；原生尺寸、字体曲线与列数均记录在同目录 `device-results.json`，截图保存在对应日志中。
- [Windows 约束回归](../../tool/test-window-size.ps1) 通过 18 组 100%–250% 像素比例／工作区组合及无效工作区检查；Windows Debug 构建与[实际 runner 消息验证](../../integration_test/windows_dpi_constraints_test.dart)通过。真实窗口查询包括正常最小尺寸和超过工作区的请求，最后限制为当前 1920×1032 工作区。未切换用户桌面的系统 DPI。
- Windows 离线预览热重载成功，Dart 工具检查无运行时错误。没有加载真实账号或写入账号数据。

本轮未生成发行包，Android 手机／macOS 实机、真实跨屏 DPI 切换和原生视频纹理仍未验收。全量日志记录的是运行时工作区，其他同期任务的后续改动不自动继承通过结论。

以下保留前两轮检查和修复前问题的证据。

## 修复前检查结论

Windows 已配置按显示器感知 DPI，核心 Flutter 布局在本轮合成 DPI／字号矩阵中通过。视频卡片标题保留两行高度，超出两行省略并提供全文提示；播放详情主标题可以换行。未发现本轮样本中的标题上下裁切、作者行重叠或 DPI 重复放大字号。

这不是全部页面、全部字体和三端真实显示器验收。当时发现普通主窗口的固定最小高度可能在高缩放下超过工作区；现已按顶部修复结果处理。

## 源码检查

- [Windows manifest](../../windows/runner/runner.exe.manifest) 声明 `PerMonitorV2`；[Win32Window](../../windows/runner/win32_window.cpp) 创建窗口时读取目标显示器 DPI，收到 `WM_DPICHANGED` 后使用系统建议的矩形更新窗口。
- 主应用的 [MaterialApp](../../lib/app/bili_app.dart) 没有覆盖全局 `textScaler` 或固定设备像素比例。独立播放窗口由 [DetachedPlaybackWindow](../../lib/core/platform/detached_playback_window.dart) 创建独立的 Flutter View，并通过自己的 `MaterialApp` 获取该 View 的布局环境。
- [共享网格](../../lib/shared/ui/responsive_card_grid.dart) 根据局部逻辑宽度和文字缩放选择列数；[视频卡片](../../lib/shared/ui/video_card.dart) 根据文字缩放预留两行标题高度；[全文提示](../../lib/shared/ui/highlighted_text.dart) 在宽度、字号、字体变化时重新测量溢出。
- [封面](../../lib/shared/ui/app_cover_image.dart) 与 [头像](../../lib/shared/ui/network_avatar.dart) 根据当前设备像素比例选择图片解码尺寸。
- Android Activity 的 [configChanges](../../android/app/src/main/AndroidManifest.xml) 包含 `density`、`fontScale`、`screenSize`；后续 Android 窄屏专项使用 API 36 模拟器验证，见下文。

Flutter 在逻辑像素中布局，像素比例变化会通知依赖 `MediaQuery` 的组件。Windows `WM_DPICHANGED` 的建议矩形用于跨显示器和运行中 DPI 变化。依据：[Flutter devicePixelRatio](https://api.flutter.dev/flutter/dart-ui/FlutterView/devicePixelRatio.html)、[Microsoft WM_DPICHANGED](https://learn.microsoft.com/en-us/windows/win32/hidpi/wm-dpichanged)。

## 修复前自动验证

新增 [DPI widget 回归](../../test/shared/ui/dpi_adaptation_test.dart)，加载项目实际使用的 HarmonyOS Sans Regular／Medium／Bold 字体，使用离线视频数据与占位播放画面。

| 场景 | 覆盖 |
| --- | --- |
| 固定逻辑窗口、运行中切换像素比例 | 1200×800 逻辑像素；0.75、1、1.25、1.5、1.75、2、2.5、3、4，最后返回 1；验证卡片几何、字号和挂载元素保持 |
| 固定物理窗口下的浏览壳与共享视频网格 | 1280×720、1920×1080；像素比例 0.75／1／1.25／1.5／1.75／2／2.5／3；文字比例 0.8／1／1.5／2，共 64 项 |
| 播放详情长标题 | 1920×1080；上述八档像素比例与四档文字比例，共 32 项 |

合计 **97 项通过**。断言包含实际文本自然高度不超过布局高度、标题与作者不重叠、封面 16:9、全文提示与实际溢出一致、详情主标题不截断和布局无异常。0.75 像素比例与 0.8 文字比例属于合成压力场景，不表示 Windows 标准设置提供这些选项。

另运行现有导航壳、播放窗口／窗口服务、共享卡片／网格／标题测量、首页响应式、视频详情与设置页面回归，**146 项通过**。这 146 项不全是 DPI 矩阵测试。日志位于 `build/validation/dpi-audit/matrix.log` 与 `regression.log`。

`tool/check.ps1 -SkipPub` 通过格式、静态分析、打包边界脚本和 **3087 项测试**：根应用 2455、`bili_api` 456、`bili_player` 81、`bili_danmaku` 93、`bili_mux` 2。另有 10 项 mux 原生测试因未设置 `BILI_MUX_LIBRARY` 跳过，不作为原生集成通过。完整日志为 `build/validation/dpi-audit/check.log`。这些数字记录本轮检查运行时的工作区；其他同期任务的后续改动不自动继承本记录。

重跑新增回归：

```powershell
flutter test --no-pub test/shared/ui/dpi_adaptation_test.dart
```

## Android 窄屏补充检查

同日新增 [Android widget 矩阵](../../test/shared/ui/android_dpi_adaptation_test.dart) 和 [Android 设备集成测试](../../integration_test/android_dpi_adaptation_test.dart)，共用[离线页面样本及文字边界断言](../../test/support/dpi_test_app.dart)。样本使用现有浏览壳、首页同款懒网格和留白、真实搜索页面与播放详情；不加载账号，不访问真实视频服务。

widget 矩阵包含 125 项测试：

- 280／320／360／375／393／412／480／599 dp 竖屏，文字比例 0.85／1／1.3／1.5／2。
- 浏览与搜索分别在 DPR 1／2.625／4 检查；详情在 DPR 2／3.5 检查。
- 固定 360×800 dp，在 DPR 1／1.5／2／2.625／3／3.5／4 间切换，检查逻辑卡片几何保持一致。
- 固定 1080×2400 物理像素，改变密度以覆盖约 270–540 dp 宽度；另检查 24 dp 顶／底安全区和 320 dp 窄屏的键盘弹出、收回及卡片挂载保留。

最终定向运行这 125 项 Android 布局回归和此前 97 项 DPI 回归，**222 项全部通过**，日志为 `build/validation/android-dpi-audit/widget-matrix.log`。新增／调整的四份 Dart 测试文件定向静态分析通过，日志为同目录 `analysis.log`。

### 系统字体曲线

Android 14 起支持最大 200% 的非线性字体缩放；不能把 widget 测试的 `TextScaler.linear(2)` 等同于系统实际行为。[Android 官方说明](https://developer.android.com/about/versions/14/features#non-linear-font-scaling)

当前 Flutter SDK 的 `TestPlatformDispatcher.scaleFontSize` 强制使用线性比例。因此设备集成测试通过真正的 `ui.PlatformDispatcher.instance.views.single` 构造 `MediaQueryData.fromView`，读取与普通应用相同的 Android 系统曲线，不从测试框架的线性 dispatcher 推导结论。

设备为只读、无界面的 `Medium_Phone_API_36.0` x86_64 模拟器，1080×2400；宿主图形驱动无法启动默认 Vulkan 路径，改用软件图形启动。检查的系统密度为 420／480／540 dpi，对应约 411／360／320 dp 宽度，各自检查系统字体 100% 和 200%。这不是 Android 手机实机、原生视频解码或性能验证。

已确认的系统曲线样本：200% 字体下，15 sp 实际为 27、14 sp 为 26，而 140／300 sp 仍为 140／300。设备测试同时记录真实 View 尺寸、DPR、各字号映射、卡宽和列数，并导出离线页面截图。

| 模拟器系统密度 | DPR | 逻辑宽度 | 系统字号 | 结果 |
| --- | --- | --- | --- | --- |
| 420 dpi | 2.625 | 411.43 dp | 100%／200% | 两组通过 |
| 480 dpi | 3 | 360 dp | 100%／200% | 两组通过 |
| 540 dpi | 3.375 | 320 dp | 100%／200% | 两组通过 |

共 **6 组配置、18 个页面状态通过**，平台尺寸与原生字体曲线记录校验一致。日志与汇总保存在 `build/validation/android-dpi-audit/android-density-*-font-*.log` 和 `device-results.json`。各页面 PNG 同目录保存，例如 `native-320-font-2-browser.png`。模拟器设置已恢复至启动时的 420 dpi／100% 字号，随后关闭本任务启动的模拟器；没有修改个人手机或 Windows 系统缩放。

### 修复前的可读性与触摸限制

以下两项问题均已在本次修复中处理，保留原始现象与探针日志：

1. **非线性大字体下网格列数响应不足。** [共享网格](../../lib/shared/ui/responsive_card_grid.dart) 用 `textScaler.scale(140)`／`scale(160)`／`scale(300)` 计算卡宽阈值。这些大字号在本机系统曲线中不会跟随 15 sp 标题放大，因此字体变大时网格仍可能保留双列。约 411 dp 宽时卡宽约 198.7，320 dp 时约 153，均保持双列，标题由 15 变成 27；标题两行高度正确，但每行能显示的字数明显减少，作者和封面计数也更容易省略。已查看导出的真实模拟器 Flutter 页面截图。后续可按实际标题字号的缩放比例确定最小卡宽，保留不同宽度下的合理列数。
2. **手机无法长按卡片标题查看全文。** [全文提示](../../lib/shared/ui/highlighted_text.dart) 使用 `TooltipTriggerMode.manual`，鼠标悬停可触发提示，触摸长按不会自动显示。独立触摸探针已复现长按后没有全文提示，日志为 `build/validation/android-dpi-audit/touch-title.log`，探针源保留在同目录 `touch_title_probe_test.dart`，不纳入通过的布局矩阵。当前需要打开播放详情读取完整主标题；后续可补充不会与卡片点击冲突的触摸全文入口。

前两轮只补充验证与测试；本轮按用户授权修改了网格和 Tooltip 行为。检查期间工作区另有网格三列阈值与导航的同期修改，保留这些改动。

Android 补充检查当时的 `tool/check.ps1 -SkipPub` 格式与静态分析通过，根应用测试为 **2583 通过、2 失败**，在此停止，未进入后续子包阶段。失败均为 [懒网格生命周期回归](../../test/shared/ui/sliver_grid_lifecycle_test.dart) 的 `invalidates cached row layout on width and text scaling`（responsive／video 两个变体）：同期网格三列阈值使卡宽实际为 220，旧断言仍预期 340。没有为凑全量通过修改同期布局或相关旧测试；日志为 `build/validation/android-dpi-audit/check.log`。这是历史检查结果，本次修复后的完整通过结果见顶部。

上述旧断言随后由同期任务更新，保留其修改并定向复跑整个文件，**10 项通过**，日志为同目录 `sliver-grid-recheck.log`。没有再次完整运行根脚本，不将定向复测记为本轮全量脚本通过。

重跑 Android widget 和单个设备配置：

```powershell
flutter test --no-pub test/shared/ui/android_dpi_adaptation_test.dart
# 先在指定模拟器设置待测密度／字号，勿在个人手机上直接改系统参数。
flutter test --no-pub integration_test/android_dpi_adaptation_test.dart -d <emulator-id>
```

## 原生窗口验证边界与未验项目

- [WindowService.initialize](../../lib/core/platform/window_service.dart) 仍将主窗口逻辑最小尺寸设为 **420×560**。插件乘以像素比例后，现由 runner 结合当前工作区限制物理最小尺寸；原来的 1080p／200% 缩放下最小高度约 1120、超过屏幕的问题已处理。真实系统 DPI 切换与跨显示器拖动尚未进行。
- widget 测试可以直接设置小于原生最小尺寸的 View。因此小视口布局通过，不代表原生窗口一定能调整到该大小。
- 尚未执行真实 Windows 显示缩放切换、不同 DPI 显示器之间拖动主窗／播放窗、安装包兼容性设置和屏幕清晰度视觉验收。本轮没有修改系统缩放设置。
- Android 系统非线性文字缩放已在上述模拟器检查；尚未进行 Android 手机或 macOS 实机、其他已安装字体及原生视频纹理的 DPI 验收。占位播放器不作为原生解码、音画同步或性能验证。
- 前两轮只检查；本轮已修改卡片列宽缩放、触摸全文提示和 Windows 最小尺寸约束，尚未生成发行包。
