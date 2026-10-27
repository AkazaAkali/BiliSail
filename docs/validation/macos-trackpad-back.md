# macOS 触控板滑动返回

日期：2026-10-27。

## 行为

macOS 内容区支持触控板双指向右滑动返回。左侧圆形箭头的位置、透明度和大小随拖动距离变化，达到 120 逻辑像素时切换为主题强调色。只有松手时仍达到阈值才返回一次；短滑、快速但不足距离的滑动、达到阈值后拖回均取消，箭头在 160ms 内收回。系统减少动画开启时立即收回，拖动期间仍保留直接反馈。

返回沿用工作区已有规则：页内详情优先，其次为当前窗口的页面或视频历史。单／多标签按已有访问顺序返回；双标签浏览窗口回退浏览历史，独立播放窗口回退视频历史，历史耗尽时按原行为关闭播放窗口。预览期间不消费历史、不切换媒体源、不创建播放器。没有可用返回步骤时不参与手势。

实现覆盖主工作区和独立播放 View，视频、PGC、直播、离线播放使用同一工作区返回入口。模态弹窗、全屏呈现和图片查看器保留自身的路由／手势处理，不允许底层工作区响应穿透事件。

## 输入边界

- 仅处理 macOS 的 `PointerPanZoom` 序列，不将鼠标滚轮、鼠标按住拖动或触屏拖动转换为导航。依据 [Flutter 触控板手势说明](https://docs.flutter.dev/release/breaking-changes/trackpad-gestures)，使用现有水平拖动识别器参与 gesture arena，不添加全局 pointer route、计时猜测松手或原生拦截。
- 起始方向必须明确向右，横向距离大于纵向距离的 1.5 倍；纵向、向左、缩放及旋转使当前序列失效。方向确认后保持轴锁定，避免垂直抖动影响反馈。
- 内层横向列表、分页和自定义拖动控件先进入 arena，保留自身交互；列表已到边界时也不会把同一手势转交给导航。
- Flutter 3.47.6 的 Material Slider 渲染对象没有向内部拖动识别器转发 pan/zoom 开始事件。共享播放器进度条通过 `TrackpadBackBlocker` 保护该区域，触控板滑动不会误返回，鼠标／触摸 seek 沿用原实现；弹出音量／设置菜单沿用模态隔离。
- 页面身份、账号或导航模式改变，页面隐藏、窗口缩放、应用进入后台或窗口失焦会取消当前手势。窗口焦点复用 `WindowInputFocus`，包括已有的 macOS 原生焦点补偿；重新获得焦点后只接受新手势。

## 源码

- [共享手势和箭头](../../lib/core/presentation/trackpad_back_region.dart)：识别器只收窄手势意图，Flutter 管理竞争与拖动生命周期；动画仅更新指示器子树。
- [工作区组合](../../lib/app/shell.dart)：主窗口和独立播放窗口复用 `_goBack`／`_playbackWindowBack`，不另建历史。
- [播放器进度条](../../lib/features/playback/presentation/playback_timeline_bar.dart)：保护现有 Slider 交互区域。
- [手势测试](../../test/core/presentation/trackpad_back_region_test.dart)、[导航和进度条测试](../../test/app/macos_trackpad_back_test.dart)、[独立 View 测试](../../test/app/windowed_workspace_test.dart)。

## 验证

定向 70 项 Widget 测试通过，日志 `build/trackpad-back-targeted.log`。覆盖箭头随动／松手确认、短滑／拖回／方向取消、缩放取消、内层横向列表及其边界、竖向列表、受保护滑块与鼠标 seek、非 macOS 和非触控板输入隔离、页面／窗口状态变化、弹窗隔离、原生焦点恢复、减少动画、三种导航模式、页内返回优先、保留原页面以及独立播放 View 的媒体历史。进度条和触屏 seek 原有回归同时通过。新增实现及其定向测试静态分析通过，日志 `build/trackpad-back-analysis.log`。

工作区早期检查受同期未完成修改阻塞；提交前仅提取本任务的代码块和文件，导出隔离快照运行 `tool/check.ps1 -SkipPub`，完整通过根应用与四个包的格式、静态分析、打包边界脚本和离线测试。根应用 3105 项、四个包 659 项，共 3764 项通过；根应用 13 项按平台／配置跳过，另 10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。日志 `build/trackpad-back-commit-check.log`。同期已完成的其他提交继续保留，合并到当前提交基线后再次运行本功能定向测试与分析。

此前工作区分阶段测试为根应用 3127 项、四个包 659 项通过，日志 `build/trackpad-back-root-tests.log` 和 `build/trackpad-back-packages.log`；数量差异来自隔离快照排除其他任务当时新增的测试。本次涉及的六份 Dart 源码／测试格式检查、177 条文档本地链接和任务文件差异空白检查通过。

本轮在 Windows 主机进行自动验证，没有运行 macOS 构建、真实触控板、系统滚动方向切换或原生窗口验收。Widget 注入的触控板序列不代表真机手感、原生取消事件或性能结论。
