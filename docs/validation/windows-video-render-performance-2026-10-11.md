# Windows 硬解视频输出性能

日期：2026-10-11 测量与实施，10-12 验证。本轮先测量，再修改 Windows 视频输出；保持同一媒体源、硬解和原生音画同步策略。后端替换的资料调研见 [硬解后端调研](playback-backend-research-2026-10-11.md)。

## 定位与实现

锁定的 `media_kit_video 2.0.1` 把视频显示尺寸传给 Windows 原生输出。改动前，即使 Flutter 可见区域只有 640×360，720p 和 1080p 素材分别仍分配 1280×720 和 1920×1080 的中间纹理。ANGLE 输出、D3D11 纹理复制处理了可见区域不需要的像素。

新增可选的 `VideoViewportSource` 契约，由共享 `VideoSurface` 在布局后发送可见区域与 DPR；应用页面继续只依赖播放器契约。`MediaKitEngine` 仅在 Windows 启用此能力。输出按 contain 比例和可见物理像素确定上限，向上分档避免微小窗口变化反复分配，并且不超过源显示尺寸。放大立即应用，缩小等待连续布局稳定 300ms。源视频、码率、解码分辨率和音频设置不改变，全屏恢复所需尺寸。

布局约束不包含祖先的绘制缩放，因此 `VideoSurface.paintScale` 可预留绘制缩放的像素预算。卡片预览与既有悬停动画共用 1.05 常量，避免先按卡片原始布局缩小纹理，再被动画二次放大；普通播放与本次固定探针默认值仍为 1。

viewport 上限与解码器尺寸独立保存，后续解码尺寸事件不会覆盖小窗设置。新 surface 取得所有权时先解除旧上限，旧 surface 的延迟回调不能操作新 surface；跨线程请求另带单调 revision，在原生渲染队列拒绝晚到的旧请求。该机制覆盖进入/退出全屏、换源和暂停后的尺寸更新。

更新通知现在最多保留一个待执行渲染任务；渲染期间的新通知会在队尾安排下一次任务，让其他播放器和尺寸操作有机会执行。保留原有注销回调、渲染上下文销毁顺序和尺寸事件缓存补丁。两轮基线中正常更新通知与渲染次数几乎相等，不能把稳定播放的主要收益归因于消除了大量重复渲染；队列合并主要防止突发积压。

没有移除 `glFinish`、D3D11 `CopyResource`/`Flush`，也没有改动 `hwdec`、倍速、音频时钟或 mpv 同步算法。Flutter 会复用已取得的外部纹理，普通弹幕/UI 重绘不能直接等同于每次重新执行视频复制。

实现入口：[共享 surface](../../packages/bili_player/lib/src/video_surface.dart)、[媒体适配器](../../packages/bili_player/lib/src/media_kit_engine.dart)、[原生补丁](../../windows/patches/media_kit_video/README.md)、[原生行为测试](../../tool/native_tests/video_output_dispose_test.cpp)。

## 测量口径

- Windows，RTX 4070 Ti SUPER，驱动 32.0.16.1742，1920×1080/180Hz；Flutter 3.47.6，Dart 3.13.5，Profile 构建。
- DXGI 只读枚举确认本次 PDH LUID `0x00000000_0x0000c4f8` 对应 RTX 4070 Ti SUPER，另一 AMD 核显的计数不混入该结果。LUID 是本次开机状态，不是永久硬件 ID。
- 本地 H.264/yuv420p 测试图，主片 60fps、50 秒、AAC/48kHz 音轨；720p 和 1080p 分别比较。预览为 854×480/30fps 无音轨素材，仅在指定阶段播放，之后释放。
- 同一探针依次运行小窗、同时预览、3x→1x、暂停、seek、大窗、实际填满窗口的全屏及退出全屏。前后均读取 native `avsync`、`frame-drop-count`、`decoder-frame-drop-count` 和输出尺寸。
- GPU 用 Windows `GPU Engine` 性能计数器，锁定探针 PID；过滤非成功、非有限及负样本。排除阶段切换后的首秒，并只纳入完整落在稳定阶段的一秒计数区间。短阶段点数较少，必须和重复轮次一起阅读。
- 按每个采样时刻取各引擎最大值作为进程最繁忙引擎口径，同时单列 3D 和 VideoDecode；不能相加各引擎百分比冒充“总 GPU”。此口径依据 [微软的任务管理器说明](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/)。没有测量官网的实际呈现路径，也不比较两个不同进程的整机总占用。
- 原生 trace 是渲染调用间隔，mpv drop 是播放器计数；均不等同于屏幕最终呈现帧时间。暂停、启动和 seek 的间隔单独处理，不能作为稳定播放卡顿峰值。

探针入口为 [Dart 播放流程](../../tool/validation/windows_video_render_probe.dart) 与 [GPU 采集](../../tool/validation/windows_gpu_engine_probe.ps1)。原始日志和 JSON 保存在忽略的 `build/validation/windows-video-render-*`、`windows-gpu-engine-*`，旧 Profile bundle 保存在 `build/validation/windows-render-baseline-bundle`，便于再次对照。

复测入口：[test-windows-video-render.ps1](../../tool/test-windows-video-render.ps1)。例如 `pwsh -NoProfile -File tool/test-windows-video-render.ps1 -Label verify-1080 -Height 1080 -GenerateFixture`；`-MediaDir` 复用既有素材，`-ExePath` 运行保存的基线 bundle。每个 label 的素材路径、字节数和 SHA-256 另存 `.fixture.json`，已有结果不覆盖。脚本结束后恢复环境和普通 CMake 配置。本轮原始测量通过等价手工命令运行，新增包装脚本只完成静态 PowerShell 语法检查，尚未端到端执行。

## 前后对照结果

每种分辨率各有两轮优化前、两轮优化后数据；1080p 在首轮后用保存的旧、新 Profile bundle 再交替运行。以下为 640×360 小窗稳定阶段，各轮只含 3–4 个完整 GPU 采样点，百分比保留两位便于核对原始数据，不表示有相应精度。

| 素材与小窗指标 | 优化前两轮 | 优化后两轮 |
| --- | --- | --- |
| 720p 中间纹理 | 1280×720 | 640×360（像素面积减少 75%） |
| 720p GPU 最繁忙引擎均值 | 6.68%、7.17% | 5.89%、7.21% |
| 720p GPU 3D 均值 | 5.64%、5.51% | 4.57%、6.99% |
| 1080p 中间纹理 | 1920×1080 | 640×360（像素面积减少 88.9%） |
| 1080p GPU 最繁忙引擎均值 | 14.13%、14.04% | 6.92%、11.98% |
| 1080p GPU 3D 均值 | 10.74%、12.08% | 4.39%、11.49% |

**确认的收益是更小的中间纹理和有界的通知队列，不能宣称已取得固定比例的 GPU 降幅。** 720p 的 GPU 范围重叠；1080p 两次最繁忙引擎读数都较低，但优化后的波动较大，第二轮 3D 只小幅下降。未改变解码策略的 VideoDecode 同时从约 14.1% 变为 6.9%/11.3%，说明不能仅凭这些百分比把变化全部归因于输出尺寸。当前未锁定或记录全程 GPU 频率，需要更长的受控采样才能稳定量化 GPU 占用收益。

音画与流畅度观察：

- 八轮实际硬解器均为 `d3d11va-copy`，正常播放时音频解码持续存在；没有 buffering 样本。1080p 的 1280×720 大窗与 1920×1080 全屏输出均恢复正确，退出全屏后回到 640×360。
- 正常 1x 阶段原生 A/V 偏差绝对值：优化前最高 2ms，优化后最高 1ms；包含 3x 阶段时，优化后采样峰值为 5ms。这是每 500ms 读取一次的播放器指标，不是对所有瞬时偏差的保证。
- 小窗稳态与 seek 恢复后的稳态没有新增播放器丢帧，未观察到稳态超过 40ms 的渲染调用间隔记录。转换过程仍有停顿；不能称播放流畅度已经改善。
- 720p 的 3x→1x 阶段各轮均新增约 36 个播放器丢帧；1080p 前后均新增约 37–39 个。此前预览打开和倍速阶段的累计值必须扣除，seek 后计数会重置。
- 1080p 追加对照的倍速恢复间隔为 69ms→102ms，seek 后一次渲染间隔为 614ms→765ms；全程约 1104ms 的峰值包含主动暂停，不能拿来比较稳态帧率。现有转换停顿仍待进一步定位。

数据标签：720p 为 `base-final-a`、`base-final-b`、`opt-final-a`、`opt-final-b`；1080p 为 `base-1080`、`base-1080-b`、`opt-1080`、`opt-1080-b`。本地独立汇总为 `artifacts/windows-render-comparison.json`，复核脚本为 `artifacts/windows-render-analysis.py`，均不随源码提交。

另用同一 1080p 素材无转码拆出 `video.mp4` 和 `audio.m4a`，运行独立的 [DASH 分轨 Profile 探针](../../tool/validation/windows_dash_render_probe.dart)，结果不混入单文件 GPU A/B 数据。`windows-dash-render.json` 的各阶段均确认音视频已解码、无 buffering，硬解仍为 `d3d11va-copy`；小窗 A/V 偏差采样为 0ms，3x 峰值 6ms，恢复 1x 与 seek 后不超过 1ms，全屏和恢复尺寸正确。decoder drop 全部为 0，seek 后播放器 drop 清零且不再增长。这是本地双文件同步验证，HTTP 请求策略由原生集成回归另行覆盖。

## 自动化与构建

- `tool/check.ps1 -SkipPub` 最终通过：根应用 1932、API 426、播放器 54、弹幕 86、合流包 2，共 2500 项测试通过；合流包另外 10 项依赖 `BILI_MUX_LIBRARY` 的原生测试按配置跳过。格式与静态分析均通过，日志 `build/validation/windows-render-check-verified.log`。
- `tool/test-windows-video-dispose.ps1` 的 9 项原生测试通过，覆盖突发通知合并、渲染期间再通知、其他队列任务先行、销毁屏障、旧纹理注销、暂停尺寸重绘及逆序 viewport 请求。日志 `windows-render-native-unit.log`。
- `tool/test-windows-media.ps1` 通过 18 项真实 Windows 原生回归：主播放/分轨/界面 8、HTTP 错误诊断 1、启动与取消 5、预览缓冲 1、音量均衡 2、预读窗口 1。日志 `windows-render-native-media.log`；最终共享 surface 修正后，主播放 8 项及预览缓冲 1 项再次通过，见 `windows-render-playback-final.log`、`windows-render-preview-final.log`。
- 两个新增 Dart 探针的独立格式与分析通过；PowerShell 包装器/采集器静态语法检查、文档相对链接和 `git diff --check` 通过。包装器端到端运行边界见测量口径章节。
- 正式入口 `flutter build windows --release --no-pub` 最终通过，日志 `windows-render-release-final.log`；构建目录中的生产补丁副本确认没有 `VIDEO_RENDER_TRACE` 及逐帧诊断计数。产物位于 `build/windows/x64/runner/Release/`，未打包或安装 MSIX。

## 验收边界

本地 Profile 对照只能说明这台 Windows 设备、这些素材和显示条件下的行为。按可见物理像素缩放不是更换低清晰度片源，但最终缩放滤镜产生的像素不保证与旧链路逐位相同；HDR、广色域、不同 DPR/显卡及实际内容仍需画质验收。

Android 原有视频 PTS 回跳与随后视频追赶的问题尚未修复；本轮不修改 Android 原生输出。也没有据此宣称 macOS、真实 CDN、长时间播放或所有设备的同步和性能通过。
