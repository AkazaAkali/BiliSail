# 倍速 seek 供帧缓冲实验

日期：2026-10-13。用户观察到倍速播放点击进度条后约 1 秒画面掉帧，随后恢复流畅；本轮增加构建开关供手动对照，不将这个症状认定为缓存不足。

## 启用与对照

按用户后续要求，未传构建参数时 **Android 默认开启，macOS 和 Windows 默认关闭**；其他平台默认关闭。默认值在播放器适配层按实际运行平台选择，不修改已有持久化设置。

Android arm64 普通构建即可启用：

```powershell
flutter build apk --release --target-platform android-arm64
```

所有平台仍可用 `--dart-define=BILISAIL_VIDEO_FRAME_QUEUE=true/false` 显式覆盖。Windows 开启对照：

```powershell
flutter build windows --release --dart-define=BILISAIL_VIDEO_FRAME_QUEUE=true
```

Android 关闭对照：

```powershell
flutter build apk --release --target-platform android-arm64 --dart-define=BILISAIL_VIDEO_FRAME_QUEUE=false
```

显式覆盖为编译期开关，测试时退出并重新启动对应构建的应用；修改命令不会改变已经运行的客户端，也没有持久化设置迁移。覆盖优先级为构造器显式值、构建参数、平台默认；缺失或非法参数采用平台默认。正式应用构建与实际视频观感由用户手动验证。

## 实现与边界

- 共用 [MediaKitEngine](../../packages/bili_player/lib/src/media_kit_engine.dart) 在 DASH 视频解码器创建前配置 mpv `vd-queue`，覆盖普通视频、影视及以 DASH 打开的离线双轨内容。
- 上限设为 8 帧、0.1 秒媒体时间、64 MiB，由达到的最小限制约束队列；帧边界可能少量超出，不是保证预填满 100 毫秒再开始播放。在 2 倍速下，100 毫秒媒体时间约对应 50 毫秒实际播放时间。
- 保留自动／软件解码选择、音频队列、网络预读窗口和精确 seek 策略；不开启直播、progressive／manifest 或悬停预览的队列。每个源重建 native player，seek 的旧帧清理由 mpv 的解码器 reset 负责。
- SDK 会丢弃属性设置错误，因此四个参数逐项回读验证，受原打开 deadline 和 source generation 约束。不能应用时该次打开失败，避免实验无效却误判为已开启；重新以关闭开关的版本构建可恢复原路径。
- `videoFrameQueueActive` 只说明配置已确认，不表示队列当前有多少帧。硬解表面和驱动显存未必全部计入字节统计，64 MiB 不能解释为播放器总内存／显存上限。

[mpv 官方手册](https://mpv.io/manual/stable/#options-vd-queue-enable) 提醒该队列可能增加 seek 延迟和内存占用，并不建议与硬解一起使用。按用户要求 Android 默认启用，硬解兼容性和掉帧改善仍待实机验证，可显式传 `false` 关闭；macOS／Windows 保持默认关闭。核对的 Windows 固定源码为 [88eb9f2](https://github.com/mpv-player/mpv/blob/88eb9f2e73945d8bc9c133a2f67babaa9af34680/filters/f_decoder_wrapper.c)，其中队列在 decoder wrapper reset 时清空；本轮只使用公开配置参数，没有复制上游代码或改动原生二进制。

## 验证与手动观察

新增有界配置、属性拒绝、源替换和超时行为测试；[Windows 原生脚本](../../tool/test-windows-frame-queue.ps1) 使用已有本地 H.264／AAC 分轨素材，检查开／关 × 自动／软件解码、2 倍速多次 seek、暂停跳转、重开和预览隔离。它验证基本兼容性，不是资源受压性能测试。

- `tool/test-windows-frame-queue.ps1` 通过 4 项原生用例，并成功构建 Windows 集成测试入口。主样片为 320×180／24fps／12 秒，预览为 160×90／24fps／60 秒。两次自动模式实际解码器均为 `d3d11va`，软件模式均为 `no`；这只证明本机小样片兼容性。日志 `artifacts/video-frame-queue/native.log`。
- `tool/check.ps1 -SkipPub` 的根应用 1939、API 426、播放器 62 项均通过，格式和静态分析通过；播放器包含本轮新增 8 项配置行为测试。日志 `artifacts/video-frame-queue/check.log`。
- 全量检查在本轮开始前已有的未跟踪 `packages/bili_danmaku/test/danmaku_frame_driver_test.dart` 上出现 9 项失败，涉及刷新间隔、TickerMode 暂停和固定弹幕到期。未修改该并行工作。弹幕包不依赖播放器包；另按 Git 已跟踪的弹幕测试清单运行，90 项全部通过，日志 `artifacts/video-frame-queue/danmaku-tracked-tests.log`。不能把这次全量检查写为全绿。
- 补跑合流包格式／分析和测试，2 项通过，另 10 项因未配置 `BILI_MUX_LIBRARY` 跳过。正式应用 Release 构建和原视频视觉对照按用户要求留给用户执行。
- 平台默认调整新增 7 项测试，覆盖 Android／非 Android 默认、显式 true／false、非法参数回退和构造器覆盖优先级；播放器包现为 69 项通过。真实 `--dart-define=true` 和 `false` 各执行该专项的 15 项测试，均通过。再次运行完整检查时根应用 1939、API 426 通过，仍仅在上述未提交弹幕帧驱动的 9 项测试失败；日志 `artifacts/video-frame-queue/platform-default-check.log`、`default-override-true.log`、`default-override-false.log`。没有进行 Android／macOS 原生构建或实机验收。

随后按用户要求整合全部本地修改以提交远端：已补齐上述弹幕帧驱动的 overlay 接入，`tool/check.ps1 -EnforceLockfile` 完整通过：根应用 1939、API 426、播放器 69、弹幕 100、合流 2，共 2536 项，另 10 项依赖 `BILI_MUX_LIBRARY` 的原生测试按配置跳过。格式／分析通过，五份锁文件没有变化。历史 9 项失败记录对应接入前快照，不代表整合后的状态；完整提交前检查日志为 `artifacts/video-frame-queue/release-check.log`。

手动测试保持同一视频、编码、清晰度、弹幕设置和跳转点，在开／关两次构建中对比 1 倍、2 倍及常用倍速，观察跳转后首秒连续性、恢复时间、音画同步及任务管理器内存／显存。优先在已缓存区域或离线双轨内容上测试，减小网络差异。

Android/macOS 原生运行、高分辨率／高帧率、真实 CDN、资源受压和长时间硬解稳定性未由本地自动测试代替。
