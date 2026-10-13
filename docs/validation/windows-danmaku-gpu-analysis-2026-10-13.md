# 有弹幕时的 Windows GPU 负载

日期：2026-10-13。生产源码基线 `7a6fd7803478bc092253acd21c9407747f8b51a9`，已包含[视频输出优化](windows-gpu-optimization-2026-10-13.md)。本轮新增独立探针，测量真实视频与合成弹幕同播，并比较候选绘制调度；生产播放器、弹幕包和设置没有修改。

用户后续要求按首页实际视频、1080p、Release 登录和完整 30 秒复测。正式页面及现有设置的结果见[真实视频复测](windows-real-video-gpu-2026-10-13.md)；本报告的固定尺寸、合成密度和候选收益不作为实际全屏负载的预测。

## 测量条件

- Windows、RTX 4070 Ti SUPER，驱动 `32.0.16.1742`；屏幕 1920×1080、180Hz、DPR 1，Flutter 3.47.6 Profile。
- 复用本地 1920×1080 H.264、60fps、AAC 素材，输出 960×540。素材 SHA-256 `afdbabbfb17447cc6345e331d7b9fa1faac59f5a055c528a3791ab873710154a`；bundle 中 libmpv SHA-256 `222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`。
- 弹幕采用系统字体、25px、阴影、不加粗、面积 0.75、速度 1、底部预留 48px；透明度默认为 0.8，与生产设置一致。合成文本为不同 ID 的中文短句，包含递增编号；每秒更新一次含历史的有界时间窗。不是重复一条文字伪造缓存命中。
- 稀疏滚动输入 2 条/秒；密集滚动及固定弹幕输入 20 条/秒。同屏数受现有防碰撞轨道限制，报告实际可见数量，不将输入速率当作同屏数。
- 每个独立进程先测 3 秒预热、10 秒纯视频，再 seek 回开头，测 8 秒弹幕预热、30 秒弹幕稳态，最后暂停退出。GPU 探针按 PID 和实际活动适配器 LUID `0x00000000_0x0000c3a9` 过滤，排除最初两秒和不完整的一秒区间。LUID 会随系统会话变化，本轮没有沿用前一轮的旧 LUID。
- 串行运行八个场景，不与构建或其他播放测试并行。弹幕阶段每组 23–24 个完整 GPU 点；密集生产和限帧候选各重复两轮。所有弹幕稳态的核心时钟均为 210MHz、P8。

## 实测结果

| 场景 | 实际同屏均值 | Dart 帧时序上报/秒 | 进程 3D 均值 | raster P95 |
| --- | ---: | ---: | ---: | ---: |
| 纯视频，无弹幕层 | 0 | 约 0 | 1.56–1.75% | 没有持续 Dart 时序上报 |
| 生产：稀疏滚动，2 条/秒 | 16.0 | 180.3 | **6.23%** | 0.772ms |
| 生产：密集滚动，20 条/秒，两轮 | 47.7 | 180.1 / 180.2 | **9.09% / 8.50%** | 0.965 / 0.953ms |
| 探针候选：同一密集滚动，约 60Hz，两轮 | 47.6 / 47.7 | 62.0 / 62.2 | **4.75% / 4.71%** | 1.058 / 1.032ms |
| 生产：固定顶部/底部，20 条/秒 | 18.0 | 180.3 | **6.13%** | 0.784ms |
| 探针候选：固定弹幕只在内容变化时重绘 | 18.0 | 4.4 | **2.58%** | 0.826ms |
| 生产透明度对照：密集滚动，opacity=1.0 | 47.7 | 180.4 | **6.51%** | 0.826ms |

这里的 3D 包含该进程的视频呈现和弹幕合成，不是弹幕的独占计时。Dart 数值为 Flutter FrameTiming 上报次数，不代表 native 视频的呈现帧率，纯视频上报约 0 时视频仍正常播放。候选使用相同控制器、字体图像缓存、布局与播放时钟，只替换探针中的绘制触发方式：16.667ms Timer 获取当前 placement，滚动坐标改变时重绘；固定文字内容/坐标不变时不重绘。实测约 62 次/秒，因此不能把它描述为严格的 60fps 生产实现。

密集候选的总进程 3D 比生产低约 45–48%，固定候选低约 58%；都不是通过升高 GPU 时钟取得。降低弹幕绘制频率会降低高刷新屏上的移动平滑度，需要体验与帧间隔验收后选择默认值；固定弹幕的内容去重绘制没有这种持续移动的需求。

所有场景实际硬解均 `d3d11va`，解码 1920×1080、输出 960×540；播放器和解码器掉帧均 0，没有 buffering。采样最大绝对 A/V 偏差不超过 1.43ms。弹幕稳态 UI/raster 均没有超过本机 180Hz 的 5.56ms 单线程预算，当前主要表现为额外资源开销，而非本段素材的卡顿。

生产滚动的文字缓存命中约 **99.93%**，密集缓存峰值约 **4.05 MiB**，直接绘制回退为 **0**。候选固定弹幕命中率约 94.5%，是总绘制次数减少后首次建图比例变大；并未发生预算回退。缓存命中省去的是重复字形/阴影栅格化，仍需绘制图像、混合透明像素及合成窗口。

## 优化点及优先顺序

1. **固定弹幕按入场、退出和变化重绘。** [needsFrame](../../packages/bili_danmaku/lib/src/danmaku_controller.dart) 只判断存在活动项，不区分滚动与固定；[overlay](../../packages/bili_danmaku/lib/src/danmaku_overlay.dart) 因此在固定文字没有变化时也保持 Ticker。应为纯固定场景安排下一次入场/到期唤醒；混合场景可保留固定子层，让滚动层独立刷新。暂停、缓冲、确认时钟、seek 后有界 admission、倍速、最后清屏及 dispose 必须保持。直播有独立时钟，但其固定弹幕同样需要检查连续 Ticker。
2. **滚动弹幕提供可控绘制帧率。** 默认没有上限的 Ticker 在本机 180Hz 运行，稀疏弹幕也承担高频呈现成本。约 60Hz 候选已有同机证据，可进一步比较 90/120Hz 的平滑度与资源取舍；不应直接把所有高刷屏强制为 60Hz。调度必须按经过时间计算位置，不能按“每帧移动若干像素”；只在 Ticker 回调内跳过绘制也未必停止 Flutter 的帧请求，需要同时控制帧调度。
3. **保留透明度效果，减少整层透明度的成本。** [PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart) 把整个弹幕层包在 `Opacity` 中，默认 0.8；同一密集场景改为 1.0 的探针对照降低约 2.0–2.6 个百分点。Flutter [官方说明](https://docs.flutter.dev/perf/best-practices#minimize-use-of-opacity-and-clipping) 建议在可行时直接给图像应用透明度。本机源码的 `RenderOpacity` 也说明了中间缓冲路径。可以验证在文字图像绘制时一次性应用文字、阴影、描边的 alpha，或缩小必须整体合成的范围；需对照重叠区域像素，逐条 alpha 和整层 alpha 的重叠语义不同。本轮尚未用 GPU trace 确认每个 offscreen pass，不能把整个差值归给某一次 `saveLayer`。
4. **次要 CPU/分配优化。** `frame()` 每帧重建轨道列表、活动图像保护集合和 placement 对象；这些工作可在活动成员变化时更新或复用。但本机 UI P95 仅约 0.14–0.26ms，应排在上述呈现开销之后。当前没有证据需要增加 32 MiB 缓存预算、换库或引入 isolate 逐帧绘制。

视频后端仍按视频帧工作。不能把 Dart 约 180 次/秒的弹幕绘制解释为 180 次硬解回读或 `CopyResource`；前序 GPU 回读修复没有因开启弹幕失效。本轮没有与相同素材、尺寸、密度的网页弹幕成对测量，不用这些数字直接推导与网页的差距。

## 复现与产物

[独立探针](../../tool/validation/windows_danmaku_gpu_probe.dart) 共用正式 PlayerEngine/VideoSurface 和弹幕公开入口，无账号或网络请求，无新增依赖。生产路径直接挂载 DanmakuOverlay；`limited` 仅用于验证候选收益，尚未覆盖生产调度的全部行为与平台。

```powershell
flutter build windows --profile --no-pub -t tool/validation/windows_danmaku_gpu_probe.dart
# 先复制完整 bundle，再用新的 label 串行运行，避免后续构建覆盖探针。
$env:BILI_GPU_RENDERER = 'production' # 或 limited
$env:BILI_GPU_MODE = 'scroll' # 或 fixed
$env:BILI_GPU_ARRIVALS = '20' # 稀疏场景为 2
$env:BILI_GPU_OPACITY = '0.8' # 1.0 仅作透明度成本对照
pwsh -NoProfile -File tool/test-windows-gpu-playback.ps1 `
  -Label dm-verify-new -Seconds 30 `
  -ExePath C:\Users\14562\code\bili-lite\build\validation\windows-danmaku-gpu-bundle\bilisail.exe `
  -MediaPath C:\Users\14562\code\bili-lite\build\validation\windows-render-1080-media\main.mp4
```

正式结果标签为 `dm-dense-a/b`、`dm-60-a/b`、`dm-normal-a`、`dm-opaque-a`、`dm-fixed-a`、`dm-fixed-limited-a`。`build/validation/windows-gpu-playback-<label>.jsonl` 记录播放、UI/raster、同屏数、缓存计数；配对的 `windows-gpu-engine-<label>.jsonl`、`windows-gpu-clocks-<label>.csv` 和 `.fixture.json` 保留 GPU、时钟、整卡功耗及素材/DLL 哈希。汇总与分析脚本在忽略目录 `artifacts/windows-gpu-native/danmaku-comparison.json`、`summarize-danmaku.py`；探针 bundle 保存在 `build/validation/windows-danmaku-gpu-bundle`。

探针格式、静态分析和 Windows Profile 构建通过，八个 GPU 场景均正常退出。`tool/check.ps1 -SkipPub` 通过：根应用 1932、API 426、播放器 54、弹幕 90、合流包 2，共 2504 项；合流包另 10 项因未设置 `BILI_MUX_LIBRARY` 跳过，格式与静态分析通过。之后串行运行 `flutter build windows --profile --no-pub -t lib/main.dart` 成功，正常应用入口已恢复。日志分别为 `danmaku-analysis-check.log`、`danmaku-main-build.log`。

结论限定本机 Windows、960×540 输出、DPR 1、本地 SDR 视频和合成中文短句。真实弹幕分布、全屏/高 DPR/超长文字、直播实测、长时间资源稳定性、Android/macOS，以及候选帧率的主观流畅度尚未由本轮替代。候选只在探针中实现，未再次提交、推送或触发 Release。
