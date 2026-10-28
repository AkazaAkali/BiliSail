# 滚动与混合弹幕性能复查

日期：2026-10-28。基线：`0c961e4`。本轮专门检查纯滚动和固定＋滚动混合，沿用屏幕刷新率 Ticker、独立动画时钟、组透明度、入场顺序、文字质量和缓存上限。

## 热点与方案

1. 生产 Overlay 每帧先构建整份 `Placement` 列表，再遍历绘制；控制器还在逐条重复构造动画寿命、年龄 Duration、计算视口顶部和底边。为生产绘制增加直接访问当帧位置的路径，每帧只计算一次公共量，保留原有 `frame()` 的独立位置快照 API，使用同一调度实现避免时钟/入场分叉。
2. 混合场景不能直接将所有固定项提到同一图层，否则改变固定与滚动的交错覆盖关系。逐条保留图层的历史实验也没有证明 GPU 优于批量绘制。本次不恢复已撤回的合帧/限频方案。
3. 进一步用探针比较有界 atlas 批绘制：把当前图片合成到同一图集，再按原顺序用 `drawRawAtlas` 绘制。Flutter API 明确支持此类批绘制，但现有图片各自独立，建立图集会增加准备成本和内存，必须计入整体测量。该候选先只进入探针，不直接作为生产默认。

来源：当前两种控制器、Overlay、文字缓存，以及 [Flutter drawRawAtlas](https://api.flutter.dev/flutter/dart-ui/Canvas/drawRawAtlas.html)、[drawImageRect](https://api.flutter.dev/flutter/dart-ui/Canvas/drawImageRect.html)。历史图层和帧驱动取舍见 [高刷实验记录](danmaku-frame-cadence-2026-10-13.md)；上轮结果见 [调度与图像缓存优化](playback-composition-performance-2026-10-28.md)。

## 验证计划

- 对比原快照绘制和直接绘制的像素、入场数量、缓存统计，覆盖 VOD/live、混合重叠、DPR、暂停/seek、视口/样式/缓存释放和低容量回退；保留所有既有测试。
- 同一 Profile AOT 进程交替比较原控制器和新路径，分离调度/录制成本与实际视频帧时序，避免把微基准当成整窗 GPU 收益。
- 扩充 GPU 探针的 mixed 场景，持续输入 20 条/秒，其中 80% 滚动、10% 顶部、10% 底部。与纯滚动使用相同素材、尺寸、透明度和高刷调度，记录实际同屏数、FrameTiming、原生 drop、缓存成本和 GPU 时钟。
- 运行根检查和 Windows Profile 构建/播放；Android/macOS 实机和其他 GPU 不由本机结果推导。只保留有证据、行为一致且资源有界的生产改动。

## 已实施的直接绘制路径

点播和直播控制器新增 `paintFrame(Canvas)`，Overlay 直接调用。调度、过期清理、入场、图片保护和位置计算仍由各自单一 `_visitFrame` 执行；原 `frame()` 继续通过它返回独立位置快照，供调用方和测试使用。生产绘制不再先分配整份 Placement 列表和逐条 Placement；寿命、动画时间的微秒值、顶部和底边在每帧统一计算。

这一改动减少 Dart 侧临时对象和重复计算，没有减少屏幕刷新次数或实际图像绘制数。滚动与固定项仍按入场顺序交错绘制；固定项与移动项重叠时的前后关系、阴影/描边、双线性采样、组透明度均沿用原路径。32MiB 图片预算、256 项排版上限和原生媒体后端不变。

### Profile CPU 微基准

Windows Profile AOT 同一进程同时加载 `0c961e4` 的完整弹幕包副本与当前包。点播/直播分别测纯滚动和混合场景，每组同屏 72 条、1920×1080 视口、默认字号/阴影；先预热 500 帧，再交替 AB/BA 测量 30 轮，每批 360 帧。每次录制将单调时间推进 10 微秒，保持可见集合与媒体外推窗口稳定。每组前后累计图像绘制均为 813,600 次。

| 场景 | 360 帧批次中位数折合 μs/帧，前 → 后 | 降幅 |
| --- | ---: | ---: |
| 点播纯滚动 | 38.986 → 36.825 | 5.5% |
| 点播混合 | 39.872 → 36.863 | 7.5% |
| 直播纯滚动 | 39.106 → 36.403 | 6.9% |
| 直播混合 | 39.840 → 36.647 | 8.0% |

计时包含每帧调度、位置计算、缓存命中、Canvas/Picture 创建和录制释放，不包括视频解码及最终 GPU 栅格化/合成。每帧节省约 2～3 微秒，不能表述为视频播放或整窗渲染提速 5.5%～8.0%。这也不是实际堆分配采样。

原始数据和探针保存在本地忽略目录 `build/validation/scrolling-mixed-cpu-20261028.json`、`scrolling_mixed_cpu_probe_20261028.dart`；旧版源码为 `scrolling-mixed-baseline-20261028/lib/`，完整构建为 `scrolling-mixed-cpu-profile-20261028/`。构建命令为 `flutter build windows --profile --no-pub -t build/validation/scrolling_mixed_cpu_probe_20261028.dart`。复跑前应为输出选择新文件名，保留本次原始样本。

## Windows 实际播放对照

本机 RTX 4070 Ti SUPER，Flutter 3.47.6 / Dart 3.13.5，Profile AOT、Impeller OpenGLES，DPR 1。本轮 Flutter 实际帧调度约为 60Hz，不能和上一轮约 166Hz 的数值混算。程序继续使用系统 Ticker，没有启用探针中已有的 `limited` 渲染器或改动系统刷新率。

同一段本地 H.264/AAC 1920×1080 60fps 合成视频，输出纹理 960×540、`d3d11va`、`GPU delivery: copied`。每组 10 秒纯视频、8 秒弹幕预热、30 秒弹幕采样；字号 25、75% 区域、组透明度 0.8。窗口可见，运行串行，采样期间没有同时执行本任务的构建/测试。GPU 未锁频，桌面其他活动未隔离。

| 输入场景 | 同屏均值，前 → 后 | Flutter 帧/秒，前 → 后 | UI P95 ms，前 → 后 | raster P95 ms，前 → 后 |
| --- | ---: | ---: | ---: | ---: |
| 纯滚动，2 条/秒 | 16 → 16 | 60.17 → 60.20 | 0.203 → 0.207 | 0.917 → 0.876 |
| 纯滚动，20 条/秒 | 47.57 → 47.67 | 60.13 → 60.00 | 0.387 → 0.453 | 1.060 → 1.187 |
| 混合，20 条/秒 | 62.70 → 62.70 | 60.07 → 60.37 | 0.433 → 0.409 | 1.158 → 1.111 |

混合输入为 80% 滚动、10% 顶部、10% 底部；各类有独立轨道/寿命，实际同屏比纯滚动更多，不能将混合与纯滚动直接视作相同负载。前后峰值同屏分别为 16、49、64；30 秒图像绘制为 28,863 → 28,880、85,848 → 85,749、113,102 → 113,161。微小差别来自实时到点和帧调度，不存在主动减帧或丢弃更多弹幕的优化。

六组生产路径均没有原生输出/解码 drop 增量、buffering、文字直接绘制回退，A/V 差值绝对值最高 1.267ms，UI/raster 没有超过 5.56ms 的样本；图片缓存峰值前后一致。此处是短时受控素材验证，不代表真实网络、可听音频或长期稳定性验收。

GPU 3D 均值：稀疏 2.90% → 2.01%（核心均频 683 → 1387MHz）；密集纯滚动 5.43% → 4.86%（210 → 212MHz）；混合 5.39% → 5.44%（均为 210MHz）。每组只有 22～24 个有效计数点，未锁频且存在桌面干扰。UI/raster P95 方向也不一致，因此本轮只确认 CPU 微基准中较少的工作量，**不宣称整窗 GPU、播放帧率或 P95 获得稳定提升**。

前后探针仅替换弹幕包源码，完整 bundle 为 `build/validation/scrolling-mixed-video-before-20261028/` 和 `scrolling-mixed-video-after-20261028/`。`data/app.so` SHA-256 分别为 `01061094E6346B96F6568C2387A5459CE72DE67D0DA297962B3FA83B72DF68E4` 和 `2E209822AFB166877CAB141A583902B0FA25F0164EB9A8784B0FCD8F6BE21F44`。

原始标签为 `{scroll2,scroll20,mixed20}-{before,after}-production-mixed-20261028`。对应 `build/validation/windows-gpu-playback-<label>.jsonl/.log/.err/.fixture.json`、`windows-gpu-engine-<label>.jsonl` 和 `windows-gpu-clocks-<label>.csv` 保留帧时序、进程 GPU、素材/mpv 哈希和频率；汇总脚本 `summarize-scrolling-mixed-20261028.py`，结果 `scrolling-mixed-summary-20261028.json`，均在同一本地忽略目录。

### 图集候选的取舍

探针增加 `BILI_GPU_RENDERER=atlas`，先把可见文字图像按整数像素装入带间隔的图集，再通过 `drawRawAtlas` 按原顺序移动。可见成员或 DPR 改变时重建，额外图集预算 16MiB；没有通过增大生产缓存或降低刷新率取得收益。该实现仅在 `tool/validation/windows_danmaku_gpu_probe.dart`，正常应用不引用它。

| 场景，20 条/秒 | 生产 → atlas UI P95 ms | 生产 → atlas raster P95 ms | 生产 → atlas 进程 3D 均值 | 30 秒重建次数 | 额外图片峰值 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 纯滚动 | 0.453 → 0.775 | 1.187 → 0.669 | 4.86% → 6.97% | 351 | 2.39MiB |
| 混合 | 0.409 → 1.001 | 1.111 → 0.746 | 5.44% → 7.09% | 454 | 2.94MiB |

两组 atlas 核心频率均值均为 210MHz，帧调度约 60Hz，同屏均值 47.63、62.67，峰值 49、64。合批降低了逐帧 raster 时长，但重建图集增加 UI 和 GPU 工作，不能由 raster P95 单独判定整体优化。单次测量不建立跨设备统计结论，但已足以阻止这版候选作为默认方案。

图集预算和表中图片字节按当前图像宽×高×4 计算，不是进程/GPU 实际内存峰值，也没有计入提交后仍在途的旧资源。

预热后取同一份位置快照，分别用原图片路径和 atlas 进行离屏像素对照：DPR 1 的纯滚动没有差异；混合有 43 个 RGBA 通道相差 1（总计 2,073,600 个通道）。因此 atlas 不能声称完全像素等价，也没有覆盖其高 DPR、字体/样式变化和长期缓存生命周期。生产直接绘制的像素回归不使用 atlas，仍完全一致。

本轮不采用“可见集合变化就重建整张图集”的设计。若后续继续研究，需要有界的增量图集、统一图片预算及完整采样/生命周期验证；本次结果也不等于所有 atlas 设计都无收益。将固定和滚动直接按类型分层同样没有采用，因为会改变交错覆盖关系。当前仍有整层透明混合和视频纹理最终合成成本，减少 Dart 对象不会消除它们。

候选原始标签为 `scroll20-after-atlas-mixed-20261028`、`mixed20-after-atlas-mixed-20261028`，位于上述同一证据目录。后续可用当前探针复现，先运行 `flutter build windows --profile --no-pub -t tool/validation/windows_danmaku_gpu_probe.dart` 并保存完整 bundle，再设置 `BILI_GPU_MODE=scroll/mixed`、`BILI_GPU_ARRIVALS=20`、`BILI_GPU_OPACITY=0.8`、`BILI_GPU_RENDERER=production/atlas`，用 `tool/test-windows-gpu-playback.ps1 -Label <新标签> -Seconds 30 -ExePath <bundle中的exe> -MediaPath <本地素材>` 串行采样。

## 自动检查

- `tool/check.ps1 -SkipPub` 完成格式、静态分析、打包边界及根/四包测试：根 3187、API 495、播放器 83、弹幕 116、mux 5，共 **3886 项通过**。另有 13 项 Windows 符号链接权限跳过、10 项 mux 原生用例因缺少 `BILI_MUX_LIBRARY` 跳过，不计为通过；日志 `build/scrolling-mixed-check.log`。该结果对应运行时工作区，其他任务的同期文件没有纳入本次提交。
- 新增 5 项直接绘制回归：点播/直播 × 纯滚动/混合的像素对照，以及位置快照不被后续绘制改变。对照包含 DPR 1/1.25/2、组透明度、阴影/描边、尺寸变化、过期、每帧仅入场 2 项及仅 3 项排版缓存的回退；点播另外覆盖暂停、seek、倍速和图片释放。没有将直播不存在的暂停/seek API 作为已验收能力。
- 旧包/新包播放探针和 CPU 探针的 Windows Profile 构建通过，完整 bundle 均分别保存。没有活动 DTD/debug 应用，未完成热重载；运行证据来自 AOT 构建。
- 最终探针单独 `dart analyze` 通过（`build/scrolling-mixed-probe-analysis.log`）；文档链接和本次 diff 空白检查通过。

本轮没有修改原生解码/同步、fork 或用户设置，未做安装包及安装升级验收。Android/macOS 实机、其他 GPU、当前代码在高刷新率屏上的性能、全屏/HDR、真实网络及长时间播放仍未测；已有历史记录不代替本次验收。
