# 播放与弹幕合成性能复查

日期：2026-10-28。范围：当前源码分析、共享弹幕调度优化和 Windows Profile 对照。保留原生解码/纹理交付与 Flutter 合成方式。

## 当前链路

`PlaybackSession → PlayerEngine/MediaKitEngine → MediaKitVideoOutput → VideoSurface → FlutterVideoCompositionAdapter`。libmpv 负责拉流、音视频解码和时钟，Flutter 负责视频纹理及弹幕、字幕、控件的最终组合。一个会话仍只有一个播放器。

主要源码：[共享播放面板](../../lib/features/playback/presentation/playback_panel.dart)、[输出对象](../../packages/bili_player/lib/src/media_kit_video_output.dart)、[合成适配器](../../packages/bili_player/lib/src/video_composition.dart)、[点播调度](../../packages/bili_danmaku/lib/src/danmaku_controller.dart)、[直播调度](../../packages/bili_danmaku/lib/src/live_danmaku_controller.dart)、[文字缓存](../../packages/bili_danmaku/lib/src/danmaku_text_style.dart)、[Windows GPU 交付补丁](../../windows/patches/media_kit_video/angle_gpu_queue.inc)。

Windows 当前固定 mpv 使用 D3D11/ANGLE 输出；原生补丁保留有序 GPU 提交、渲染通知合并、按视口限制纹理尺寸、不同设备之间的保护性纹理复制。这不是原生独立合成或全链路零复制。Android/macOS 沿用各自 media-kit 输出，本次不修改原生后端。

点播弹幕按确认的媒体位置触发，独立的单调动画时钟决定移动和停留，暂停/缓冲/seek 冻结，700ms 之后不再外推。直播按消息到达的单调时间运行。二者使用有界文字排版和 32MiB 图像缓存、Canvas 和独立 RepaintBoundary。文字首次绘制创建图像，后续绘制图像；`toImageSync` 同步返回句柄，栅格化异步完成，不能把它误称为同步 CPU 像素回读（[Flutter API](https://api.flutter.dev/flutter/dart-ui/Picture/toImageSync.html)）。

## 热点与优先级

| 路径 | 当前证据 | 本次处理 |
| --- | --- | --- |
| 固定弹幕连续刷新 | `needsFrame` 将所有活动项视作动画，live `isAnimating` 对所有 pending/visible 项返回 true | 固定内容等待下一次入场/到期，停止连续 Ticker |
| 直播延迟消息 | 尚未到点的 pending 队列也保持 Ticker | 单次定时唤醒，保留每帧有界 admission |
| 位置确认重画静止层 | VOD 每次 sync 都让可见文字重绘 | 内容/布局修订与时钟确认分离，确认只重排唤醒时间 |
| 滚动合成与组透明度 | 每帧移动缓存图像，整个弹幕层有 Opacity，仍有填充/混合成本 | 保留刷新率和组透明度，避免改变高刷手感及重叠颜色 |
| 文字首次排版、栅格化和缓存溢出 | 每帧最多准备 32 项，超预算退回 paragraph | 保留既有上限及统计；不凭假设增大缓存 |
| 每帧索引、缓存保护 | 当前源码已按 admission/成员变化更新，与早期记录不同 | 不重复优化、不把历史问题算作当前收益 |
| 原生复制和全屏像素量 | 不同 D3D11 device 仍需保护性复制 | 暂保留同步保证；独立原生合成需要另行设计和跨平台验证 |

`RepaintBoundary` 隔离重绘录制，但不会消除最终纹理混合（[Flutter API](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)）。本轮不把既有低密度/旧工作区的性能数据算作当前测量。

## 实施方案

1. 两种控制器分别提供即时帧需求、下一次唤醒时间、内容/布局修订。固定弹幕到期按动画时间；点播入场按媒体时间及倍速，不能混用。点播唤醒不得越过插值上限。
2. Overlay 在滚动、到期清理、有界待入场时使用原 Ticker；静止时取消 Ticker，至多保留一个 Timer。时钟确认重新计算 Timer，不主动重绘未改变的固定文字。
3. 换控制器、尺寸/设置变化、过滤清空、seek、暂停/恢复、隐藏/销毁必须取消或重排旧任务。保留最终清屏帧和无有效视口时的停转。
4. 不改用户设置、解码器、fork、渲染质量、透明度及滚动帧率，不引入新依赖。

## 验收

- 组件测试观察真实绘制计数和 `hasScheduledFrame`，覆盖固定弹幕无连续帧/无时钟确认重绘、到期清屏、混合滚动、未来入场、倍速、插值冻结、暂停/缓冲、seek admission、重布局和控制器替换/释放。
- 当前源码 Windows Profile 前后使用同一探针、素材、尺寸、DPR 和场景，分别记录纯视频、固定、密集滚动；核对 GPU、Flutter 帧、A/V、drop 和缓存回退。测量时窗口可见，串行采样。
- 根 `tool/check.ps1 -SkipPub`，定向包/面板回归；如全量检查遇到同期修改的问题，记录具体阻塞。
- 记录 Windows 构建与受控播放证据；Android/macOS 和用户实际视频体验单列，不把自动化算作三端验收。

## PiliPlus 设计复查与补充方案

按用户要求只读核对本地 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的播放器、点播/直播弹幕入口和实际锁文件。其 `canvas_danmaku` 固定到 `275046d8647a6a26cba1d0dadb9e28688cb3dbf1`，核心 media-kit 为 `73771ec38176be2d984a3049c28177bce23b54a0`，视频输出为 `fd8421d21eade4d6d12de137fa7df902fec20292`，不能将三个分支视作同一上游版本。

参考入口：[PiliPlus 播放视图](../../../PiliPlus/lib/plugin/pl_player/view/view.dart)、[点播弹幕](../../../PiliPlus/lib/pages/danmaku/view.dart)、[直播视图](../../../PiliPlus/lib/pages/live_room/view.dart)、[锁文件](../../../PiliPlus/pubspec.lock)；弹幕依赖核对的是上述精确提交的 `lib/danmaku_screen.dart`、`base_danmaku_painter.dart`、`models/danmaku_item.dart` 及静止/滚动 painter。本地参考副本保存在忽略目录 `build/validation/piliplus-canvas-danmaku-20261028/`。

| 设计 | 本项目判断 |
| --- | --- |
| 图片只准备一次、重复使用绘制资源 | 已有文字图片缓存；补充让命中路径跳过文字尺寸/像素预算重算，缓存源矩形和逻辑尺寸，每个缓存实例复用一个 Paint |
| 固定/滚动/特殊弹幕分层 RepaintBoundary | 能减少混合场景中的固定文字录制，但会将当前按入场顺序交错绘制改为按类型分层；本次保留叠放顺序，仅在整层静止时停帧 |
| 按原尺寸使用 drawImage | 可能省去矩形处理，但本项目需要保持小数坐标、DPR 和双线性采样完全一致；继续使用 drawImageRect，只缓存不变参数 |
| 密集弹幕每帧录制临时 Picture 再 drawPicture | 没有跨帧复用，不能仅凭“批量”认定更快；不引入额外录制层 |
| 倍速同时缩短弹幕动画寿命 | 与本项目媒体入场时钟和独立动画时钟的约定不同，不采用 |
| SimpleVideo 和独立视频 RepaintBoundary | 本项目已隔离视频输出和叠加层；没有证据说明替换现有 VideoSurface 能减少原生复制，不更换播放器/fork |

补充实现保持 256 项排版上限、32MiB 像素预算、4096 像素尺寸限制、可见图片保护、LRU 及 fallback 统计；图片和几何信息共同失效/释放，DPR 或样式变化时重建。沿用 Flutter 组件测试和静态分析流程，检查像素一致性、缓存命中/失效及释放，再以 Windows Profile 记录绘制录制成本。

PiliPlus 应用的 GPL-3.0 与所用 `canvas_danmaku` 的 MIT（2024 Predidit）分别核对。本轮只借鉴设计，独立修改现有实现，没有复制参考源码/资源、引入依赖或修改相邻仓库。

## 实施结果

控制器的 `needsFrame` 现在区分滚动、到点 admission 和到期清理；`nextFrameDelay` 计算下一次固定内容退出或未来事件入场。一次计算只采一个单调时间值，避免时钟恰好跨 deadline 时漏掉唤醒。`visualRevision` 仅用于内容/布局失效，不替代媒体时间或业务状态。

两个 Overlay 保留单 Ticker 和单 Timer，静止时停转；live 移除了 controller 和 repaint notifier 的重复绘制订阅。TickerMode 关闭会同时取消 Timer，恢复后重新核对当前状态。点播在两次刷新之间暂停滚动弹幕时仍绘制最后确认的动画位置。固定与滚动混合时继续整层随刷新率绘制，不改变组透明度或 z-order。

收尾的确定性时钟回归发现：时钟若在 Overlay 的“当前不需要帧”检查和下一次唤醒计算之间跨过 deadline，有界入场可能只画出第一批就停住。现在无未来定时器且已经到点时立即恢复 Ticker；Ticker 已运行时跳过无用的唤醒计算。点播、直播各有一项回归在修复前失败、修复后通过，日志 `build/danmaku-deadline-before-fix.log` / `danmaku-deadline-after-fix.log`。

图片缓存补充使用 `_TextRaster` 将图片、DPR、源矩形和逻辑尺寸绑定到同一生命周期，命中后只更新 LRU 和目标位置。每个 `DanmakuTextLayouts` 复用独立的双线性采样 Paint，保持原来的 drawImageRect、6 逻辑像素效果留白和所有回退路径。

### 缓存命中路径 Profile 对照

Windows Profile AOT 同一进程加载修改前后的本项目文字缓存实现。每组 48 条中文文字，预热 200 次录制并完成一次栅格化；测量 360 帧/批，30 轮交替 AB/BA，各种效果和 DPR 分别重建独立缓存。计时包含 Canvas/Picture 的创建、录制和释放，排除首次文字排版、首次图片准备、视频解码与 GPU 最终合成；不是播放帧率或端到端帧耗时。

| 效果 | DPR | 360 帧录制耗时中位数 ms，前 → 后 | 降幅 |
| --- | ---: | ---: | ---: |
| 阴影 | 1 | 10.207 → 9.338 | 8.5% |
| 阴影 | 1.25 | 9.686 → 8.966 | 7.4% |
| 阴影 | 2 | 9.666 → 8.924 | 7.7% |
| 描边 | 1 | 10.115 → 9.295 | 8.1% |
| 描边 | 1.25 | 9.723 → 9.059 | 6.8% |
| 描边 | 2 | 9.922 → 9.043 | 8.9% |
| 无效果 | 1 | 9.554 → 8.876 | 7.1% |
| 无效果 | 1.25 | 9.942 → 8.984 | 9.6% |
| 无效果 | 2 | 9.990 → 9.211 | 7.8% |

各组前后都只生成 48 张图片，像素缓存字节数相同，直接文字回退为 0。缓存条目额外保留少量几何信息，不能将“像素缓存相同”表述为所有堆内存完全相同。节省主要来自每次命中不再新建 Paint、源矩形或读取不变尺寸。该微基准每帧约省 2 微秒，不能直接宣称实际播放提速 6.8%～9.6%。

证据在 `build/validation/danmaku-raster-recording-20261028.json`；可复现探针 `danmaku_raster_recording_probe_20261028.dart`、修改前源码 `danmaku_text_style_before_reference_20261028.dart` 和完整 `danmaku-raster-recording-profile-20261028/` bundle 均保存在同一忽略目录。构建命令为 `flutter build windows --profile --no-pub -t build/validation/danmaku_raster_recording_probe_20261028.dart`，新运行用 `BILI_RASTER_LABEL` 指定唯一输出标签。图像绘制命令仍与生产代码一致，没有使用参考项目的实现作为对照基线。

### Windows Profile 对照

本机 RTX 4070 Ti SUPER，驱动 32.0.16.1742，Flutter 3.47.6 / Dart 3.13.5，运行日志为 Impeller OpenGLES。复用同一个本地合成 H.264/AAC、1920×1080、60fps、65 秒视频，实际硬解 `d3d11va`，输出纹理始终 960×540，日志始终 `GPU delivery: copied`。每场景先采 10 秒纯视频，再预热弹幕 8 秒、采样 30 秒；每秒输入 20 条合成中文文字、字号 25、75% 区域、0.8 组透明度，音量 0。无账号或网络请求，未改用户设置。

探针调用 `windowManager.show()`，避免隐藏窗口改变呈现调度。前后各保存完整 AOT bundle，采样时没有同时运行本任务的构建/测试。GPU 未锁频，桌面其他活动未隔离，因此不能仅凭占用百分比或整卡功耗认定收益。

| 场景 | Flutter 上报帧/秒，前 → 后 | 30 秒文字图像绘制，前 → 后 | UI P95 ms，前 → 后 | raster P95 ms，前 → 后 |
| --- | ---: | ---: | ---: | ---: |
| 固定弹幕，第 1 组 | 165.73 → 42.33 | 89,201 → 11,376 | 0.302 → 0.384 | 0.775 → 0.836 |
| 固定弹幕，连续复测 | 165.23 → 42.37 | 89,025 → 11,382 | 0.252 → 0.356 | 0.725 → 0.756 |
| 密集滚动 | 165.83 → 165.53 | 236,664 → 236,382 | 0.342 → 0.380 | 0.957 → 1.016 |

固定弹幕第 1 组同屏均值完全相同（17.967，峰值 18），帧调度减少约 74.5%，文字图像绘制减少约 87.2%。纯静止且无入场/退出的组件测试不再连续调度；这里仍有每秒 20 次输入、到期、每秒窗口更新和有界 admission，因此帧数不会为零。滚动同屏均值 47.57 → 47.63、峰值均为 49，刷新和绘制量保持原水平。

第 1 组固定弹幕进程 3D 占用均值为 3.00% → 3.93%，但 GPU 核心频率均值为 1828 → 451MHz；滚动场景 3D 为 8.71% → 5.33%，频率也不同。两个方向的占用变化均不直接换算成性能百分比。优化针对重复工作总量，不宣称单帧 P95 变快或纯视频解码变快。

连续复测的固定弹幕 3D 为 **6.07% → 4.33%**（20/19 个有效计数点），核心频率均值 283 → 210MHz、中位数 285 → 210MHz，VideoDecode 为 16.07% → 15.76%。整卡功耗 17.31 → 14.99W，属于本机采样，不能只归因于此改动。两组调度/绘制次数降幅一致，可以确认减少了重复工作；未建立跨硬件或固定功耗收益。

上述首轮和连续复测的纯视频场景 Flutter 上报帧数均为 0，媒体位置仍正常推进；这不等于视频没有呈现。已完成样本的原生输出/解码 drop 增量、buffering 样本、直接文字绘制回退均为 0，A/V 差值绝对值最高 1.39ms。第 1 组旧版固定/滚动分别有 2/1 个 raster 帧超过 5.56ms，其余 UI 无此超限；不能由少数离群点认定偶发卡顿已修复。

合并图片缓存和 deadline 边界修复后，用最终 Profile bundle 再跑相同场景：

| 场景 | Flutter 上报帧/秒 | 30 秒文字图像绘制 | UI P95 ms | raster P95 ms | 同屏均值/峰值 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 固定 | 42.17 | 11,406 | 0.333 | 0.745 | 18 / 18 |
| 滚动 | 165.80 | 236,109 | 0.323 | 0.951 | 47.57 / 49 |

最终两组仍为 `d3d11va`、960×540 输出和保护性复制；drop 增量、buffering、文字回退均为 0，A/V 差值绝对值最高 0.863ms，UI/raster 没有超过 5.56ms 的帧。固定场景相对首轮原实现约少 74.6% Flutter 帧调度、87.2% 图像绘制，滚动保持原刷新率。对应纯视频阶段分别上报 0/1 个 Flutter 帧，视频正常推进。最终 GPU 3D 均值固定 4.06%、滚动 7.61%，频率仍不固定，继续只作为本机诊断数据；不将本轮与上轮的单帧 P95 或 GPU 差异都归因于缓存优化。

原始数据和复现入口：

- [探针](../../tool/validation/windows_danmaku_gpu_probe.dart) 和 [GPU 采样脚本](../../tool/test-windows-gpu-playback.ps1)；生产模式 `BILI_GPU_RENDERER=production`，场景 `BILI_GPU_MODE=fixed/scroll`，输入 `BILI_GPU_ARRIVALS=20`、透明度 `BILI_GPU_OPACITY=0.8`。
- `build/validation/windows-gpu-playback-{fixed,scroll}-{before,after}-20261028.jsonl`，配套 `windows-gpu-engine-*`、`windows-gpu-clocks-*`、`.fixture.json`（素材和 mpv 哈希）。固定场景连续复测标签为 `fixed-{before,after}-r2-20261028`。
- 前后 bundle：`build/validation/danmaku-composition-before-20261028/`、`build/validation/danmaku-composition-after-final-20261028/`。这些是自动播放后退出的探针。
- 汇总及脚本：`build/validation/danmaku-composition-summary-20261028.json`、`summarize-danmaku-composition-20261028.py`。上述生成物在 Git 忽略目录保留。
- 最终 bundle：`build/validation/danmaku-composition-after-reference-final-20261028/`；最终标签为 `{fixed,scroll}-after-reference-final-20261028`，同样保留 playback/engine/clocks/fixture 文件。汇总 `danmaku-composition-reference-final-summary-20261028.json` 和脚本 `summarize-danmaku-composition-reference-final-20261028.py` 在同一目录。中间的 `after-reference` 标签保留作过程记录，最终以 `after-reference-final` 为准。

### 自动检查与边界

- 新增 18 项回归，最终弹幕包 **111 项通过**，覆盖固定/混合、延迟、清屏、倍速、插值上限、暂停最终位置、重布局、TickerMode、替换/释放、跨 deadline 唤醒、小数 DPR 像素一致性及缓存命中后的 LRU。原有时钟/样式/缓存/有界 admission 回归继续通过。首轮调度回归在旧实现中复现 5 项失败，收尾时钟边界另外复现 2 项失败。
- 最终 `tool/check.ps1 -SkipPub` 通过，格式、静态分析、打包边界检查通过；根 3187、API 495、播放器 83、弹幕 111、mux 5，共 **3881 项测试通过**。13 项 Windows 符号链接用例因权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，均不计为通过。日志 `build/danmaku-reference-final-check.log`。首次静态分析发现本次使用的弃用 TickerMode API，已改为当前 `valuesOf`。
- 前后 Windows Profile 构建通过；文档相对链接和本次 diff 空白检查通过。没有活动 DTD/debug 实例，热重载返回未连接应用；本轮运行证据来自重新编译的 Profile。
- 最终共享播放面板/会话定向回归 **467 项通过**（`build/danmaku-composition-final-playback.log`），弹幕包独立静态分析通过（`build/danmaku-composition-package-analysis.log`）。
- 首轮收尾曾被同期登录/App 推荐重构阻塞，日志 `build/danmaku-composition-final-analysis.log`；本轮没有改动这些文件。同期工作完成后，补充缓存阶段和最终时钟边界阶段的全量检查均通过，分别记录于 `build/danmaku-reference-check.log` 和上述最终日志。工作区仍有其他并行修改，测试结果只代表对应执行时的源码快照。
- 最终 `flutter build windows --release --no-pub -t lib/main.dart` 构建通过，复用已准备的固定来源 Windows mux 资产；正常入口为 `build/windows/x64/runner/Release/bilisail.exe`，使用时保留整个 Release 目录。日志 `build/danmaku-reference-final-release.log`；最终 Profile 探针构建日志为 `build/danmaku-reference-final-video-build.log`。本轮没有制作安装包或安装升级验收。

本轮不覆盖 Android/macOS 实机、全屏/高 DPR、真实 PGC/直播网络、HDR、可听音频卡顿和长时间稳定性。混合场景里的固定文字仍随滚动层绘制，组透明度与原生保护性复制仍是后续可能的成本，需进一步测量和视觉/同步验收。
