# Android 原生导航与 PiliPlus 对照

日期：2026-10-26。承接[第一轮底栏性能复查](android-primary-switch-2026-10-26.md)。比较源码结构和 Android 官方实践，并验证本应用两处新增优化；未运行 PiliPlus，也未对原生应用做同机 FPS 比赛。

## 原生应用通常怎样控制切换开销

底栏切换改变当前目的地，同时保留数据和访问位置。Android Navigation 的[多返回栈](https://developer.android.com/guide/navigation/backstack/multi-back-stacks)通过 saveState/restoreState 处理这种需求；保存导航状态不要求所有目的地的完整视图一直参加布局。[ViewModel](https://developer.android.com/topic/libraries/architecture/viewmodel)按 owner 保存业务/页面状态，减少配置变化导致的重复读取；它本身不保存整棵 View 树，也不使请求天然去重。

Fragment 及其 View 各有生命周期，可以据此启停界面观察与任务。需要明确管理隐藏页的最大生命周期和订阅，不能假定 show/hide 会自动停掉业务，见[Fragment 生命周期](https://developer.android.com/guide/fragments/lifecycle)。

| 关注点 | 常见 Android 做法 | 本应用的对应问题与处理 |
| --- | --- | --- |
| 状态保留 | Navigation 保存栈位置，ViewModel 按目的地/导航图持有状态 | 工作区保留页面与滚动状态；此前嵌套 family 覆盖破坏查询归属，已补作用域声明 |
| 页面尺寸 | 各目的地通常把自己的工具栏和内容放在同一容器里 | 公共头部 110/58/0 高度曾改变多棵保留树的内容约束；已隔离隐藏约束 |
| 更新范围 | 选中反馈局部更新；数据观察按 owner 和生命周期管理 | 活动状态中间 Builder 曾反复调用内容工厂；已将输入/焦点门控与稳定 child 分开 |
| 长列表 | RecyclerView 按需创建/复用 ViewHolder；Compose Lazy 使用稳定 key/content type | 已有 Sliver 懒创建和 delegate 缓存，不能把 300 条数据误称为每次创建 300 张卡片 |
| 绘制 | 硬件加速 View 使用 display list，更新受影响区域 | Flutter 同样需要控制绘制失效；整页淡入、重复裁剪和额外动画仍有成本 |

[RecyclerView](https://developer.android.com/develop/ui/views/layout/recyclerview)与 Sliver 的对象复用方式不同，但优化目标一致。Compose 也有 composition、layout、drawing 三阶段，其[性能建议](https://developer.android.com/develop/ui/compose/performance/phases)同样要求缩小状态读取范围、跳过不必要阶段。原生也会因重复请求、错误重组和复杂绘制掉帧。

本应用同时承担单/双/多标签、鼠标预览、快捷键、账号隔离和预测返回，比简单手机底栏壳多出状态与交互门控。窄屏不应为未使用的桌面交互持续工作：保留能力，按实际输入启用监听。

## PiliPlus 的实际写法

本地提交：`936072449e82e3d90c28c728c0087bf5136fa441`，读取时工作树干净。PiliPlus 也是 Flutter；其 pubspec 声明 Flutter 3.47.7，本项目固定 3.47.6。不能从源码对照推断状态框架或 SDK 的性能胜负。

| 源码 | 实际观察 | 本项目的采用判断 |
| --- | --- | --- |
| [主页面](../../../PiliPlus/lib/pages/main/view.dart)、[主布局](../../../PiliPlus/lib/common/widgets/main_layout.dart) | 固定外部约束下的 PageView/TabBarView，底栏与主体分槽布局 | 根容器保持稳定；不必复制自定义 RenderObject 或悬浮底栏样式 |
| [页面枚举](../../../PiliPlus/lib/models/common/nav_bar_config.dart)、[主控制器](../../../PiliPlus/lib/pages/main/controller.dart)、[偏好默认](../../../PiliPlus/lib/utils/storage_pref.dart) | 枚举持有稳定页面 Widget；默认 mainTabBarView=false，一级选择 jumpToPage，可选模式 animateTo | 默认没有本项目这层 220 ms 整页平移；无动画不能算成框架吞吐优势 |
| [首页](../../../PiliPlus/lib/pages/home/view.dart)、[动态](../../../PiliPlus/lib/pages/dynamics/view.dart) | KeepAlive，自己的搜索/频道工具栏放在自己的页面内 | 头部差异不经公共外壳传入所有根页面 |
| [推荐](../../../PiliPlus/lib/pages/rcmd/view.dart)、[稍后再看](../../../PiliPlus/lib/pages/later/child_view.dart)、[动态子页](../../../PiliPlus/lib/pages/dynamics_tab/view.dart) | 滚动控制器随页面保留，Obx 多包在数据区域；使用 SliverGrid/懒列表 | 借鉴局部观察和数据保留，不需要改用 GetX；本项目已有 Riverpod/Sliver 对应能力 |
| [网格](../../../PiliPlus/lib/utils/grid.dart) | 推荐采用比例+附加高度，横向卡可固定 110 高度，缓存同横向尺寸的布局结果 | 固定尺寸便于计算；本项目需保留大字、长标题和元信息换行，不能统一照搬 110 |
| [图片组件](../../../PiliPlus/lib/common/widgets/image/network_img_layer.dart) | 明确宽高、物理像素解码边、gaplessPlayback、FilterQuality.low、默认 120 ms 图片淡入/淡出 | 可对照采样质量；本项目已有 CDN 分桶和解码上限，不直接扩大缓存或加整页淡入 |
| [推荐骨架](../../../PiliPlus/lib/pages/rcmd/view.dart)、[骨架基础组件](../../../PiliPlus/lib/common/skeleton/skeleton.dart) | 骨架复用 gridDelegate，基础骨架有周期动画与 ShaderMask | 借鉴相同几何占位；本项目已有光栅尖峰，初版宜用静态骨架 |

一个关键负载差异：[PiliPlus 我的页](../../../PiliPlus/lib/pages/mine/view.dart)中的稍后再看是 180 高度的横向预览条，完整列表另进 `/later`。本应用“我的—稍后再看”直接展示完整内容分页。可见卡片、图片区域和操作内容不同，不能只看同名入口就当成相同负载。

只读参考范围：PiliPlus 根 LICENSE 为 GPLv3。本轮只借鉴页面归属、局部观察和占位职责，独立修改本项目已有实现；没有复制源码、资源或引入相邻仓库依赖。其 cached_network_image_ce 锁定提交 `733d4aae9cadaafa9e16f20a6f6a3682c935de01`，material_ui 1.6.0，均未采用，未修改 Pub 缓存。

## 本轮完成的优化

### 按真实悬停启用工作

[ScrollAwareHoverRegion](../../lib/shared/ui/scroll_aware_hover_region.dart)此前在依赖变化时扫描滚动祖先，并始终监听 isScrollingNotifier，即使卡片从未有指针进入。触屏列表和底栏切换也因此维护桌面悬停状态。

现在仅在页面活动且指针确实位于组件内时扫描、订阅。指针离开、页面失活或组件移出树时释放监听；恢复时按当前祖先重接。没有按 Android 平台禁用鼠标，保留外接鼠标及桌面行为。

[回归](../../test/shared/ui/scroll_aware_hover_region_test.dart)在修改前失败：100 个未悬停组件有 100 个监听，隐藏组件仍有 1 个。修改后均为 0；真实进入时为 1，退出/隐藏回到 0。覆盖触摸滚动、静止指针恢复、既有嵌套滚动和组件移除。

### 封面只裁剪一次

[VideoCard](../../lib/shared/ui/video_card.dart)原有圆角 6 的 ClipRRect，外层 [VideoCardCover](../../lib/shared/ui/video_card_cover.dart)又在相同边界裁剪一次。移除内层，保留外层对封面、渐变、进度和预览的完整裁剪。[回归](../../test/shared/ui/video_card_variants_test.dart)确认同形裁剪从两层变为一层，菜单、键盘、布局与悬停继续通过。这减少重复渲染节点，不等于证明此前存在一次额外全屏离屏合成。

## 后续优化顺序

1. **根头部归属、选择更新范围。** 逐步把各入口头部移到自己的保留分支，外壳只持有稳定导航和内容槽。第一轮已隔离隐藏约束；进一步重排需要覆盖 PageStorage、输入 scope、桌面窗口、搜索键盘、预测返回，不能直接替换为 PiliPlus 主布局。
2. **视频网格几何。** 为正常字号的纯视频列表试验规则行高/比例网格，同时保留大字和复杂元信息的自然高度路径。目标是减少可见行布局；现状已经懒创建。
3. **封面采样与绘制。** 当前固定 Flutter SDK 的 Image 默认 medium，PiliPlus 显式 low。可仅针对按物理宽度解码的缩略图对照 low，并检查细字/斜线清晰度；不把头像、动态大图、原图查看一起降低。当前未改采样质量，也未把全部尖峰归因于过滤。
4. **首次加载占位。** 无缓存内容时使用最终比例的首屏少量静态骨架；热切换保留原内容，不人为清空再淡入。骨架改善网络等待与几何跳变，无法消除 UI 线程长任务。
5. **分解光栅事件。** [rasterDuration](https://api.flutter.dev/flutter/dart-ui/FrameTiming/rasterDuration.html)记录 rasterStart 到 rasterFinish，不是独立 GPU 硬件执行计时。结合 [DevTools Frame analysis/Timeline](https://docs.flutter.dev/tools/devtools/performance)和系统跟踪，区分绘制命令、纹理处理、线程等待与 GPU 工作，再决定缓存、阴影或动画策略。当前默认已为 Impeller Vulkan。

不直接用加长整页动画、增加透明度层、全量预建、无限保留解码图片或扩大 cacheExtent 作为修复。这些会改变成本和内存分布，需要实际对照。

## 验证与交付

- 三个新回归在修改前均失败；修改后触摸/鼠标、卡片变体、悬停、菜单与真实外壳定向 46 项通过，悬停专项 5 项通过。
- `tool/check.ps1 -SkipPub` 完整通过：根应用 2857、bili_api 460、bili_player 83、bili_danmaku 93、bili_mux 5，共 3498 项通过。13 项 Windows 符号链接测试和 10 项未配置 BILI_MUX_LIBRARY 的原生测试跳过，不计为原生集成通过。日志：`build/primary-switch-reference-check.log`。
- 息屏导致首次安装被拒绝；用户唤醒并要求重试后，独立 `.primaryswitch` 包安装、Profile 基准、正常入口 Debug 启动及 DTD 热重载成功，未发现运行时错误。游客推荐页图片和圆角视觉抽检正常，Debug 帧率未用于结论。
- 同样固定数据/图片、真实外壳的 24 次设备切换：前轮最终包与本轮包的“每次最大帧耗时中位数”，UI 13.32 → 12.30 ms，光栅 21.28 → 18.26 ms。本轮仍有 UI 30.48 ms、光栅 33.95 ms 尖峰。单轮结果有波动，不能将差值全部归给两项修改；监听/裁剪计数是直接验证证据。未测真实账号联网动态。
- 数据及 APK：`build/validation/primary-switch-reference.json`、`primary-switch-reference.apk`；设备日志：`build/primary-switch-reference-device-retry.log`；Debug/热重载日志：`build/primary-switch-reference-debug.log`。没有新 Windows/macOS 构建或 PiliPlus 设备测量。
- 为避免再次息屏，测试期间临时启用 USB 供电常亮；结束后已将 stay_on_while_plugged_in 从 2 恢复为原值 0，screen_off_timeout 保持原值 120000 ms。正常入口 Debug 验证包使用独立 `.primaryswitch`，正式包未覆盖。
- 本轮修改与第一轮性能修复、开发测试包配置一并提交，未推送；PiliPlus 工作树未改动。
