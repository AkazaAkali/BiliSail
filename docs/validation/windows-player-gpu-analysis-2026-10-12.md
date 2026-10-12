# Windows 播放器 3D 负载与网页端对照分析

日期：2026-10-12。用户环境：Windows、RTX 4070 Ti SUPER、Release，任意视频均可观察到网页约 5%、应用约 15–20% 的 3D 占用。以下区分用户观察、当前源码和本轮独立 Profile 探针；本轮没有修改正式播放逻辑。

## 结论

排查重点是**硬解后的帧交付和视频输出链路**。当前 Windows 实测后端使用 `d3d11va-copy`，硬解帧回读系统内存后，由 mpv/ANGLE 上传和渲染为 BGRA，插件复制到共享纹理，最后作为普通 Flutter 外部纹理参与窗口合成。解码器资源占用相近，不代表这些后续工作相近。

同机独立探针关闭弹幕、字幕、控件及其他业务 UI，仅播放视频，仍得到 **12.97% 的进程 3D 均值**。因此高负载可以在视频后端本身复现，不能主要归因于整个业务页面重建或弹幕文字绘制。尚未用 GPU trace 将回读、上传、shader、复制和最终合成逐项计时，不能宣称某一条 API 已独占全部额外负载。

另确认一项独立浪费：空弹幕控制器在播放中仍使 `needsFrame` 为真，驱动约 180 次/秒的 Dart 帧调度。本轮增加空弹幕后 3D 均值没有升高；它是可修复热点，但当前证据不支持把它当作 15–20% 的主因。

## 实际网页端观察

通过浏览器检查 [Bilibili 视频 BV1HX8v6UEZ3](https://www.bilibili.com/video/BV1HX8v6UEZ3/)：

- Windows Chromium 155，DPR 1；WebGPU adapter 信息为 NVIDIA / Lovelace。
- 视频由 `.bpx-player-video-wrap` 内的原生 `<video>` 承载，`currentSrc` 是 MediaSource 的 blob URL。
- 本次游客播放为 960×720、30fps，video 元素区域 972×547，`object-fit: contain`，没有 CSS filter 或 transform。
- 播放器容器内没有 Canvas，弹幕容器当时为空。不能据此推广为网页所有弹幕模式均不用 Canvas，但本次视频画面没有经过网页 Canvas 的逐帧绘制。
- 2.2 秒 `requestVideoFrameCallback` 观察到 66 帧，累计 `getVideoPlaybackQuality` 为 3283 帧、掉帧 0。

网页将视频交给浏览器的媒体与呈现系统。Chromium Windows 的 [SwapChainPresenter 源码](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/ui/gl/swap_chain_presenter.cc) 包含 NV12/P010 视频交换链、DirectComposition、硬件 overlay 和 VideoProcessorBlt 路径；可在满足条件时避免将视频完全当作普通 RGB UI 图层处理，也保留失败回退和视频处理操作。

**网页使用 `<video>` 已实查，当前这一次播放是否实际被提升为 MPO/硬件 overlay 尚未证实。** DOM、WebGPU adapter 或 5% 读数都不能单独证明 overlay 生效。需要浏览器媒体诊断和呈现 trace 才能确定本次所选解码器与呈现方式。尝试追加同一本地素材的浏览器量化对照时，浏览器连接已关闭（9222 连接拒绝），因此没有得到可信的网页 GPU A/B 数据；随后采集的 WebView 空闲数据不作为视频结果。

## 应用源码定位

| 环节 | 当前实现及证据 | 性能意义 |
| --- | --- | --- |
| 硬解选择 | [MediaKitEngine](../../packages/bili_player/lib/src/media_kit_engine.dart) 自动模式不覆盖 `hwdec`；锁定 SDK `NativeVideoController.create` 默认 `vo=libmpv`、`hwdec=auto`。本轮读取实际 `hwdec-current=d3d11va-copy` | 硬解不等于 GPU 内帧交付；本次是 copy-back |
| 硬解帧回读 | [mpv 官方手册](https://mpv.io/manual/stable/#options-hwdec) 明确 `d3d11va-copy` 将视频拷回系统 RAM | 后续 OpenGL 输出需要重新交付/上传帧；纹理上限不会降低源解码尺寸或这次回读的源帧面积 |
| mpv 输出 | `media_kit_video 2.0.1/windows/video_output.cc` 用 `MPV_RENDER_API_TYPE_OPENGL` 创建 render context，`Render` 调用 `mpv_render_context_render`；ANGLE 的内部输出纹理为 `DXGI_FORMAT_B8G8R8A8_UNORM` | 源 NV12 视频转换为 RGB 输出，并进行所需缩放；这些工作在图形输出链上 |
| GPU 同步 | `angle_surface_manager.cc::Draw → SwapBuffers` 每次执行 `glFinish` | 强制等待 GL 工作完成，可能妨碍跨阶段流水并行；等待时间与实际 GPU 执行时间需分开测量 |
| 插件纹理交付 | `angle_surface_manager.cc::Read` 对内部与外部 BGRA 纹理执行 `CopyResource`，随后 `Flush`；`Resize` 注册的 GPU texture callback 调用 `Read` | 已确认有一次输出纹理 GPU 复制和命令提交。不能依据 Copy 引擎为 0 就断言没有复制 |
| Flutter 合成 | [共享 VideoSurface](../../packages/bili_player/lib/src/video_surface.dart) 最终挂载 SDK `Video`；Flutter Windows 导入 DXGI shared handle，作为外部 RGB texture 绘制 | 当前路径没有把原始 NV12 解码 surface 作为独立视频平面送给 DWM 的实现 |
| 空弹幕调度 | [DanmakuController](../../packages/bili_danmaku/lib/src/danmaku_controller.dart) 的 `needsFrame` 包含无条件的 `isAnimating`；[DanmakuOverlay](../../packages/bili_danmaku/lib/src/danmaku_overlay.dart) 因此继续跑 Ticker；[PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart) 在弹幕设置开启时挂载该层 | 即使 `_active`、`_events` 为空，也可按屏幕刷新率重新调度/绘制空层 |

SDK 源码位置由根 `pubspec.lock` 和 `.dart_tool/package_config.json` 确认：`media_kit 1.2.6`、`media_kit_video 2.0.1`、Windows native libs `1.0.11`；本轮 mpv 为 `v0.36.0-403-g652a1dd907`。本机缓存根是 `C:/Users/14562/AppData/Local/Pub/Cache/hosted/pub.dev/`。本轮只读上游源码，未修改 Pub 缓存。

Flutter 引擎源码亦核对了 `shell/platform/windows/external_texture_d3d.cc` 与 `shell/platform/embedder/embedder_external_texture_gl.cc`：shared handle 未变化时复用 EGL 导入；`last_image_` 在新视频帧标记时清空，普通 UI 绘制复用已有外部 image。**不能把 180Hz 的弹幕/UI 刷新直接写成每秒 180 次视频回读或插件 `CopyResource`。** 本轮 native 日志确认使用 Impeller OpenGLES 后端。

已存在的 [Windows 中间纹理优化](windows-video-render-performance-2026-10-11.md) 只按可见物理像素缩小输出纹理并合并通知；它保留了 copy-back、RGB 输出、`glFinish`、`CopyResource/Flush` 和 Flutter 合成，因而不能消除这里的结构差异。

## 本轮受控测量

独立探针复用同一锁定 native 后端和生产 viewport 通道，仅创建一个 Player。素材是既有本地 1920×1080 H.264/yuv420p、60fps、AAC 测试图；输出固定为 960×540，屏幕 1920×1080/180Hz，Windows Profile。音频仍解码但音量为 0。无网络、字幕、控件、账号与业务页面。该素材与上述游客网页的 720p30 不同，**下表用于隔离应用内部原因，不能与网页的 5% 直接计算差距比例**。

GPU 使用现有 `windows_gpu_engine_probe.ps1`，按新探针 PID 40816 过滤；样本只来自 LUID `0x00000000_0x0000c4f8`。每阶段移除前段转换区间，仅纳入完整稳定区间。表中 3D 与 VideoDecode 分列，未相加成“总 GPU”。

| 稳态阶段 | 完整 GPU 点数 | 3D 均值 / 范围 | VideoDecode 均值 | Dart 上报的 FrameTiming 次数/秒 |
| --- | --- | --- | --- | --- |
| 纯视频，无弹幕层 | 13 | 12.97% / 6.82–14.90% | 14.63% | 0 |
| 同一视频，挂载空弹幕层 | 13 | 12.08% / 3.66–15.71% | 11.71% | 180.2 |
| 暂停并移除弹幕层 | 3 | 0% | 0% | 约 0.8，主要是阶段切换残余 |

FrameTiming 的 0 表示探针没有收到新的 Dart UI 帧时序上报，**不表示 native 视频或 Flutter raster 没有呈现**；纯视频的位置持续推进，mpv `estimated-vf-fps=60`、输出纹理有效。空弹幕阶段的数字用于证明额外 Dart 调度频率，也不等于最终显示器呈现计数。

两段播放均无 buffering，播放器/解码器掉帧均为 0；每秒采样的最大绝对 A/V 偏差分别为 1.46ms、1.84ms。空弹幕阶段最大上报 raster 时间为 3.494ms。这里发现的是资源开销，并没有在这段素材上复现稳态丢帧。

同时记录了 NVIDIA 时钟、P-state、整卡利用率和功耗。开场曾为 P0/2655MHz，随后下降至 P5/P8，后段出现约 225–465MHz；因此百分比有较大波动。NVIDIA 整卡 utilization 与 Windows 进程 3D 计数是不同口径。不能用两段均值证明空弹幕降低 GPU 开销，也不能据此承诺优化后的固定百分比。

## 非 copy-back 路径的可行性检查

在另一独立进程中显式配置 `hwdec=d3d11va`，保留同样的 viewport、输出和素材。21 个逐秒样本实际均为 **`hwdec-current=no`、`video-params/pixelformat=yuv420p`**，即回退到了软件解码，未得到可用的非 copy-back 硬解路径。

因此不能直接把正式代码改成 `hwdec: 'd3d11va'`，或只加一个 `d3d11va-zero-copy` 字符串就宣称完成。需要定位锁定 libmpv/ANGLE 组合的 hwdec interop 初始化、扩展与 D3D11 device 交付，确认实际 `hwdec-current` 和 GPU 资源身份。[mpv Render API 文档](https://raw.githubusercontent.com/mpv-player/mpv/v0.40.0/include/mpv/render_gl.h) 也明确非 copy-back 硬解需要额外的图形互操作条件；该文档用于说明契约，不能代替当前旧版二进制实测。

早期没有套用生产 viewport 上限的探针在尺寸切换时退出，Windows Application Error 记录为 `flutter_windows.dll / 0xc0000409`；它不是生产应用的复现，不用于证明 d3d11va 或 GPU 高占用的具体根因。加入固定 viewport 后，自动硬解和上述软件回退的两轮都正常退出。

## 优化顺序

1. **先修小范围调度浪费**：空弹幕或只有未来事件时，不保持连续 Ticker；用已经存在的确认位置同步唤醒到期事件。存在移动弹幕时继续使用平滑插值，暂停、缓冲、seek 和有界 admission 语义保持。需要空事件/间隙、事件到期、暂停 seek、倍速等行为回归。此项不能承诺解决纯视频的约 13%。
2. **重点验证 GPU 内交付**：在独立原生探针中建立并确认可用的 D3D11→ANGLE/libmpv 硬解互操作，先去掉 GPU→RAM→GPU 往返。不能接受“配置写成功”作为硬解零回读证据；若锁定组合无法实现，再比较可直接交付 GPU texture 的后端。
3. **测量并改进输出同步/复制**：给 mpv render、`glFinish`、纹理回调 `CopyResource/Flush`、Flutter raster/present 加 trace，结合 GPUView/ETW 分解成本。考虑带 release/fence 所有权的纹理池，验证消费者释放与生产者写入顺序；不能直接删掉同步或共享同一可写纹理，避免撕裂、读取竞争和销毁崩溃。
4. **如目标是接近浏览器的呈现效率，再评估原生视频平面**：DirectComposition/NV12 视频交换链或等价输出，需要验证 Flutter 弹幕、字幕、控件的层级，缩放/DPR、全屏、多标签、截图、HDR 和生命周期。仅修 API 参数不能让普通 Flutter RGB texture 自动成为浏览器的视频 overlay。

后续量化使用同一本地素材、相同物理画面尺寸和帧率，交替运行两条路径，每稳态至少 30–60 秒并重复；一并记录 GPU clocks/P-state、进程引擎、整机其他任务和屏幕刷新率。[微软任务管理器说明](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/) 解释了 3D、VideoDecode 等独立引擎以及最繁忙引擎的聚合口径。

## 产物与验证边界

- 忽略目录 `artifacts/windows-hwdec-chain/` 保存探针 `probe.dart`、构建与 native 日志、`chain-c.json/jsonl`、`chain-c-summary.json`、`chain-c-clocks.csv`、`chain-d.json/jsonl`。GPU 原始计数另在 `build/validation/windows-gpu-engine-chain-c.jsonl`。
- `chain-c` 为本轮有效的固定 viewport 自动硬解/空弹幕/暂停实验；`chain-d` 为显式 d3d11va 回退检查。早期 `chain-a/b` 和未成功打开视频的 `browser-*` 不纳入结论。
- 独立 Windows Profile 探针构建成功，`chain-c/d` 均退出 0。正式播放器代码未修改；未进行账户写操作或覆盖用户设置。
- 排查开始时运行的安装版 EXE 资源版本为 `0.5.7+5`，工作区为 `1.0.3+0`。本轮独立探针验证当前工作区，不能把较新 viewport 优化假定为该安装版已经包含。
- 未完成与用户原始 Release 进程/真实网页相同片源的成对 GPU 测量，未确认网页本次 MPO、未逐段分解 GPU trace，也未验证 Android/macOS。以上不会被本轮源码与 Profile 数据替代。
