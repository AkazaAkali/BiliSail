# 播放合成重绘隔离与卡顿分析

日期：2026-10-24。范围：共享播放面板与默认 Flutter 合成路径，Windows Profile 对照。用户报告的偶发视频和弹幕同时慢放尚未在本轮受控采样中确认复现，不能将以下局部热点直接等同于故障根因。

## 源码与回归定位

- 点播、直播弹幕已使用独立 RepaintBoundary、随刷新率运行的 Ticker、文字图像缓存及有限候选准备；播放进度通过 PlaybackSnapshotBuilder 局部订阅。当前不是整个播放页面每帧重建。
- 底部进度／缓冲、字幕和控件原先没有独立绘制边界。控件显示与隐藏两种状态下，12 次进度更新均引起视频合成 Stack 重绘 12 次。
- 仅隔离底部仍不足：高频订阅位于 WidthLayoutBuilder 的 build scope 中，子节点变脏会调度布局回调，外层 RenderObject 的布局完成又向祖先标记重绘。通过 markNeedsPaint 调用栈确认这一传播路径。因此默认合成 Stack 本身也需要独立边界。
- [Flutter RepaintBoundary 契约](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)允许隔离不同更新频率的绘制列表；它不会把视频移出 Flutter 最终合成，也不保证消除 GPU 纹理复制。

## 实现

1. [默认 Flutter 合成器](../../packages/bili_player/lib/src/video_composition.dart)为视频和有序前景的 Stack 增加 RepaintBoundary，防止外部布局／页面绘制重新录制未变化的合成子树。
2. [共享播放面板](../../lib/features/playback/presentation/playback_panel.dart)单独隔离底部细进度条，以及包含字幕、控件和实测控件高度布局的底部层。字幕长度变化导致的布局和控件渐隐仍留在该层中。
3. 保留视频／PGC／直播／离线共享入口、单一 engine、普通／全屏同一输出、弹幕帧率、组透明度、时钟、文字效果和用户偏好。没有增加 native 复制、定时采样或遥测，没有修改 fork 或解码参数。
4. [真实视频探针](../../tool/validation/windows_real_video_gpu_probe.dart)等待源真正进入播放，再 seek；seek 缓冲期间按 desiredPlaying 判断是否需要恢复，避免因 phase 尚未回到 playing 而误暂停。显示测试窗口，避免隐藏窗口的帧调度影响测量；[采样脚本](../../tool/test-windows-real-video-gpu.ps1)使用 GPU 采样器实际支持的可执行路径与进程启动时间参数。

## 复现与证据边界

绘制传播回归见 [playback_panel_test.dart](../../test/features/playback/playback_panel_test.dart)：计数器放在默认合成器内部，验证实际绘制传播，不以组件是否存在作为性能证明。原实现日志为 `build/playback-paint-before.log`；优化后日志为 `build/playback-paint-after.log`。

Profile 使用正式 BiliApp／VideoScreen／PlaybackPanel、同一视频时间窗、真实 DASH 音视频及对应服务端弹幕；设置复制到内存，进度上报端口为空实现。探针的音量为零，不能验证可听音频卡顿。帧耗时和 GPU 为受控采样，不代表长时间偶发故障、其他显卡或移动平台验收。

初次基线在 `inline-off-seek` 等待超时，无有效样本，不纳入性能对照。探针修正后重新构建、重测；原失败保留在 `build/validation/windows-real-playback-composition-before-20261024.jsonl`。

## 验证结果

### Windows Profile 同片段对照

环境为 RTX 4070 Ti SUPER、驱动 32.0.16.1742，Flutter 3.47.6 / Dart 3.13.5；运行日志报告 Impeller OpenGLES 后端。同一 `BV1GbnE6ZE6R`、CID `42862774454`，1080p H.264 + AAC DASH，`d3d11va`；每场景预热 8 秒、采样 30 秒。DPR 1.25，窗口视频逻辑区域约 887.2×670.8、输出纹理 1138×640；全屏逻辑区域 1536×864、输出 1920×1080。

沿用当前保存的阴影、加粗、HarmonyOS Sans、字号 0.85、透明度 0.8、40% 区域、每秒上限 20、合并重复、动态控件配置。开启弹幕的两组同屏峰值仅 1，逐秒样本均值 0.167，不是密集弹幕压力测试。正式 UI、网络、图片与缓冲更新继续运行。

| 场景 | UI P95 ms，前 → 后 | raster P95 ms，前 → 后 | 进程 GPU 3D 均值，前 → 后 |
| --- | ---: | ---: | ---: |
| 窗口，弹幕关 | 0.373 → 0.383 | 1.307 → 1.319 | 2.20% → 2.21% |
| 窗口，弹幕开 | 0.389 → 0.394 | 1.339 → 1.339 | 2.60% → 2.60% |
| 全屏，弹幕关 | 0.256 → 0.229 | 1.505 → 1.450 | 5.19% → 4.84% |
| 全屏，弹幕开 | 0.268 → 0.249 | 1.509 → 1.493 | 5.53% → 5.30% |

八组采样均无上报帧的 UI 或 raster 超过 5.56ms，原生 decoder/output drop 增量均为 0，Flutter 错误为 0；可见弹幕没有退回直接绘制。GPU 只纳入阶段开始至少 1 秒后、结束之前的完整采样，指标是同一 PID／适配器的 3D 引擎利用率，不是整卡所有引擎的总占用。

窗口场景基本持平，全屏存在小幅下降；仅一组前后对照且未锁定 GPU 频率，不将其表述为稳定性能百分比收益。可以确认的改进是绘制传播被隔离，无法由本轮证明用户偶发慢放已消失。FrameTiming 是实际收到的帧耗时，不是所有呈现间隔／系统停顿的完整记录。

原始数据位于 `build/validation/windows-real-playback-composition-{before-r2,after}-20261024.jsonl`、对应的 `windows-gpu-engine-*` 和 `windows-real-clocks-*`。汇总及脚本位于 `artifacts/playback-composition-2026-10-24/comparison.json`、`summarize.py`；两个完整 Profile 探针目录保留在该目录的 `baseline/`、`optimized/`。这些探针会自动播放固定片段并退出，不是普通应用分发包。

### 自动化与交付

- 播放面板 194 项测试通过，包含新增四组普通／全屏与控件显隐绘制回归；进度、缓冲数值与字幕消失正常，合成容器重绘增量为 0。未优化实现两组普通窗口回归均为 12 次重绘并失败。
- 两份 Windows Profile 探针均构建成功，修正后的两个真实视频采样进程正常完成；首次探针失败单独保留，不算作通过。
- 没有活动 DTD／debug 应用，热重载尝试返回无应用连接；上述验证使用重新编译的 Profile 进程。
- `tool/check.ps1 -SkipPub` 通过格式、静态分析、打包边界和 2,599 项测试（根应用 2,000／API 426／播放器 78／弹幕 93／mux 2）。另外 10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。日志为 `build/playback-composition-check-final.log`。首轮在播放器包格式检查停止，修正后完整重跑通过。
- `flutter build windows --release --no-pub -t lib/main.dart` 通过，使用现有已准备的 Windows mux 原生资产。正常应用入口为 `build/windows/x64/runner/Release/bilisail.exe`，运行／复制时保留整个 Release 目录；日志为 `build/playback-composition-release.log`。此次未生成安装包，也未做安装升级验收。
- 文档相对链接和 `git diff --check` 通过。

Android/macOS 运行、密集弹幕／高 DPI 压力、可听音频与用户偶发症状未完成本轮验收；没有调整用户持久化设置，也没有修改同期直播相关工作。

## 偶发慢放仍需区分的路径

视频和弹幕同时慢放可能来自 UI／raster 调度，也可能来自媒体时钟或缓冲。点播弹幕在 buffering／seeking 时冻结，确认位置超过 700ms 未刷新时也停止外推，因此弹幕一起停顿本身无法证明 Flutter 合成算力不足。

若声音也慢放，需把复现时的媒体位置推进、音频时钟、缓冲、掉帧与 UI／raster／系统调度 trace 对齐；单次平均 GPU 占用或历史样本无法判定 CPU、GPU、音频设备或驱动根因。现有受控探针可重复验证改动的绘制成本，但未覆盖用户发生卡顿的确切时刻。
