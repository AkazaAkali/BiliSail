# 硬解播放后端与 Flutter 画面交付调研

日期：2026-10-11。本记录比较官方文档与当前工程接口；候选后端尚未接入或在本项目测量。现有 Windows 优化的实测结果另行记录，不能把维护者的性能声明当成本项目结果。

## 判断与优先级

GPU 占用涉及四段工作：硬件解码、解码帧送入渲染器、渲染结果交给 Flutter、Flutter 合成与呈现。开启硬解只确认第一段；后端声称零复制，也未必覆盖最后两段。当前 Windows `d3d11va-copy`、Android `mediacodec-copy` 都包含解码帧回到系统内存的路径；不能通过把配置名称中的 `-copy` 删除就保证直接 GPU 输出可用。[mpv 硬解与渲染上下文要求](https://mpv.io/manual/stable/#options-hwdec)

本项目 Windows 输出还有 ANGLE 渲染、`glFinish`、D3D11 `CopyResource`/`Flush` 与 Flutter 纹理合成。减少重复渲染和按可见物理像素确定中间纹理尺寸，是当前接口内可验证的优化。移除同步或复制则涉及资源共享、跨显卡、生产者/消费者顺序和纹理生命周期，必须另做实验。Flutter 已提供 Windows D3D11/DXGI 外部 GPU 纹理入口，因此现有插件路径的全部成本不能一概视为 Flutter 不可改变的限制。[Flutter Windows 纹理接口](https://api.flutter.dev/windows-embedder/flutter__texture__registrar_8h_source.html)

Android 曾记录到无手势、1 倍速时视频时间从约 51.9 秒退到 0.34 秒，音频时间继续前进；应用没有对应 seek 或换源。该故障仍需追踪 demux 输入、解码输入/输出 PTS 和音频时钟。降低渲染负载不足以证明修复时间戳回跳，Windows 性能优化也不作为 Android 修复验收。

| 路线 | 适用性与收益假设 | 主要边界 | 建议 |
| --- | --- | --- | --- |
| 保留 media_kit/libmpv | 已有分轨、单会话、倍速、seek 和生命周期回归；可定点减少渲染工作 | 仍有 copy-back、ANGLE 与最终合成成本；PTS 故障需单查 | 当前生产路线 |
| fvp/libmdk | 三端后端、平台 GPU 输出和外部音轨 API；已是架构 D3 备选 | SDK 许可独立；每轨请求策略、Flutter 最终交付和生命周期须实测 | 首个跨平台对照候选 |
| Android Media3/ExoPlayer | Google 维护，MediaCodec、DASH、自定义请求及原生 Surface 完整 | Android 专用；需要分轨合并或 MPD，Flutter 弹幕/字幕覆盖须适配 | Android 并列对照候选 |
| libmpv 直接硬解与 GPU interop | 保留 mpv 控制语义，有机会去除 CPU 往返 | 渲染上下文、同显卡共享、同步与插件维护工作较多 | 在 Profile 证明复制仍是主瓶颈后考虑 |
| Windows Media Foundation | 系统 D3D11 解码与自适应媒体支持 | 单平台；常见 TransferVideoFrame 明确执行复制；分轨/MPD及呈现适配成本高 | 暂不优先 |
| libVLC | 成熟原生多平台核心 | 常见内存帧回调会禁用硬解或引入 GPU→CPU 复制；Flutter 封装平台不统一 | 不能仅凭硬解支持直接替换 |
| macOS AVPlayer | 系统播放器与 VideoToolbox | 原始双 URL 到统一时间轴、请求与 Flutter 输出须专门验证 | 无当前三端替代优势 |

## 候选能力与证据

本次在线核验的稳定版本仍为 `media_kit 1.2.6`、`media_kit_video 2.0.1`，与项目锁定版本一致。Dart 包、原生 mpv/FFmpeg 二进制及本项目 Windows 补丁是三个独立版本边界；不存在已证实的“升级包即可修复”结论。[media_kit](https://pub.dev/packages/media_kit)、[media_kit_video](https://pub.dev/packages/media_kit_video)

**fvp/libmdk**：调查版本为 fvp 0.39.0。`Player.setMedia` 的媒体类型参数及 `setExternalAudio` 扩展可表达外部音轨；MDK 有 `avio.headers` 等请求选项。仍须证明两条 CDN URL 各自获得正确 headers、Range 和重定向策略，并在同一会话 seek/倍速后保持同步，不能用两个独立 Player 拼音视频。MDK 的零复制声明不等于 Flutter 端到端零复制。fvp 插件采用 BSD-3-Clause，libmdk SDK 的授权与再分发条件需要单独确认；维护者说明对 Flutter 用户免费商用，仍应锁定实际 SDK archive 与 SHA-256，并核对附带 FFmpeg 等组件的许可。0.39.0 的变更记录包含 Windows 销毁后回调修正，也说明替换后仍需要生命周期压力测试。[fvp](https://pub.dev/packages/fvp)、[变更记录](https://pub.dev/packages/fvp/changelog)、[Player API](https://pub.dev/documentation/fvp/latest/mdk/Player-class.html)、[扩展 API](https://pub.dev/documentation/fvp/latest/fvp/FVPControllerExtensions.html)、[MDK Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)、[MDK SDK 与许可说明](https://github.com/wang-bin/mdk-sdk)

**Media3/ExoPlayer**：可用 `MergingMediaSource` 合并媒体源，或根据 B 站实际 representation 的 init/index range、timescale、duration 等生成 MPD；不得猜测字段。`ResolvingDataSource` 可按请求 URI 设置头。Google 建议优先 `SurfaceView` 以降低功耗，但嵌入 Flutter 后还须验证弹幕/字幕层级、手势、裁剪与全屏迁移。官方 Flutter `video_player` 的常规接口不足以直接覆盖本项目完整分轨契约，需要专门的 `PlayerEngine` 适配。[DASH](https://developer.android.com/media/media3/exoplayer/dash)、[媒体源](https://developer.android.com/media/media3/exoplayer/media-sources)、[自定义请求](https://developer.android.com/media/media3/exoplayer/customization)、[功耗建议](https://developer.android.com/media/media3/exoplayer/battery-consumption)、[Flutter SurfaceProducer](https://docs.flutter.dev/release/breaking-changes/android-surface-plugins)、[Platform Views](https://docs.flutter.dev/platform-integration/android/platform-views)

**其他路线**：Windows `IMFMediaEngine::TransferVideoFrame` 是向 DXGI/WIC surface 复制当前帧的 API，采用它并不能宣称零复制。VideoLAN 也明确说明内存视频回调可能使硬解失效或产生慢速 GPU→CPU 复制。应先审查封装的画面输出路径，再比较播放器核心的成熟度。[TransferVideoFrame](https://learn.microsoft.com/en-us/windows/win32/api/mfmediaengine/nf-mfmediaengine-imfmediaengine-transfervideoframe)、[Windows 自适应媒体](https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/adaptive-streaming)、[libVLC 内存回调说明](https://docs.videolan.me/libvlcsharp/api/LibVLCSharp.Shared.MediaPlayer.html)

## 替换前必须通过的实验

1. 用受控本地 HTTP 提供独立视频和 AAC 音轨，覆盖 206/Content-Range、302、不同每轨 headers、403、限速和取消；检查头不会转发到不允许的域，确认真实音频解码和单一播放时钟。
2. 同片源、编码、分辨率、帧率、可见物理尺寸、刷新率和电源模式，用 Profile/Release 比较现有后端与 fvp；Android 再比较 Media3。记录实际硬解器、GPU 各引擎、CPU、帧间隔、掉帧、音频时钟和 A/V 偏差。
3. 覆盖暂停、seek、3x→1x、清晰度/音轨切换、换 P、URL 刷新、关闭中的旧回调、紧凑/全屏迁移、弹幕/字幕覆盖及多个标签；保留 source generation、账号 scope 和唯一会话约束。
4. 在 Android 原故障路径同时采集 demux/decoder PTS，定位第一次回跳。软件解码、现有硬解及候选后端使用同源对照。
5. 基础门槛通过后，再测真实授权 CDN、至少 15 分钟 1080p60、HEVC/AV1、不同 GPU 和 macOS 设备。按各平台证据决定是否替换，不预先承诺全平台统一后端一定更快。

当前建议继续采用现有生产后端；把 fvp 与 Android Media3 留作隔离对照，未经上述实验不直接迁移。
