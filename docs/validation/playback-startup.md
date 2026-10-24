# 点播打开优化

日期：2026-10-10。基于 Windows 当前环境检查“正在准备音视频…”耗时，承接[非阻塞云端续播](cloud-playback-progress.md#2026-10-10-非阻塞续播与打开耗时检查)。

## 对照与选择

使用 Flutter 3.47.6 Windows Profile、锁定的 media_kit 1.2.6 / mpv 0.36，通过实际游客 GET 解析两段 480P H.264/AAC 双轨。每个样本解析一次，交替比较原首地址与同响应常规 CDN，再交替比较视频就绪后 `audio-add` 与打开前 `audio-files`。每组 3 次；不读取已保存凭据、不发账户写请求。结果仅表示本机本轮小样本，不是统计分位数或所有网络环境的结论。

| 样本 | 首地址 + audio-add 中位数 | 首地址 + audio-files 中位数 | 常规 CDN + audio-add 中位数 | 常规 CDN + audio-files 中位数 |
| --- | ---: | ---: | ---: | ---: |
| BV14sHj62EzS | 368 ms | 396 ms | 782 ms | 826 ms |
| BV1rhHv6sEVm | 715 ms | 717 ms | 240 ms | 230 ms |

常规 CDN 并非总是最快，所以自动模式首地址仍按接口顺序。`audio-files` 没有稳定缩短正常网络耗时，本轮采用它的依据是取消与恢复能力：锁定 SDK 的 `setAudioTrack(uri)` 在命令锁内等待 `audio-add`，Dart Future 超时不能取消底层命令；[mpv 0.36 文件加载源码](https://github.com/mpv-player/mpv/blob/v0.36.0/player/loadfile.c) 将预配置外部文件交给 worker，加载期间可响应 stop/abort。视频和音频的网络 demux 仍有顺序依赖，本轮不声称并行下载。

Profile 对照探针和脱敏结果位于本地忽略目录 `artifacts/playback-open-analysis/optimization_probe.dart`、`optimization-results.jsonl`。普通播放五分钟预读、悬停五秒预读保持现有配置。

## 2026-10-10 实现与竞态边界

- 点播有不同的备用视频或音轨地址时，首地址打开预算最多 8 秒，两次源打开共用 35 秒总预算，包含前一次打开及释放耗时。最多尝试两次；没有不同备用地址的点播及直播源保持原来的 35 秒预算。API 解析和后续 play 解码确认仍使用各自既有 deadline。
- 自动模式在首地址失败后，从本次响应剩余地址优先挑选常规 `upos-*.bilivideo.com`，避免两次尝试都落在 PCDN/edge 而遗漏第三个常规备选。显式 CDN 偏好继续遵守对应顺序。视频与音频各自选择，仅一轨有备用时保留另一轨原地址；不重写签名 URL。
- 只有 nativePlayback 故障可尝试备用。无效源、请求头不支持及 disposed 立即结束；每次尝试前重新检查 source generation、账号 scope/epoch、取消及销毁，旧源不能启动备用。
- 外部音轨在 loadfile 前配置 `audio-files`，读回核对并转义 mpv 的平台路径列表分隔符；原始 URL 的 query、编码、端口不变。[mpv 路径列表语义](https://mpv.io/manual/stable/#list-options)规定 Windows 用分号、Unix 用冒号。
- 继续使用单个播放器和同一份允许的请求头。通过原生 `current-tracks/audio/external-filename` 确认选中了当前源的外部文件，避免把内嵌音轨误判为外部音轨成功；播放时仍等待真实音频解码。就绪信号随 generation 变化中断，原生观察器由播放器持有，成功时取消观察，异常/取消时随播放器销毁。
- 保留暂停意图、seek、倍速、音量、缓存窗口与实际纹理就绪规则；没有引入代理、第二个音频播放器或新依赖。

## 验证

`tool/check.ps1 -SkipPub` 通过：根应用 1618、API 350、播放器 34、弹幕 72、合并包 2 项通过，合并包另有 7 项因未提供原生库跳过；格式和静态分析通过。会话与 CDN 专项 124 项通过，覆盖备用选择、签名 URL 保留、预算、故障分类及失败后账号切换不重试。

新增 Windows 原生测试 `windows_playback_startup_test.dart` 4 项通过，受控服务器保持音轨请求无响应，验证 stop、换源、dispose 和 deadline 后恢复；确认带分号/冒号的 query 完整到达，释放迟到响应不会改变新 generation 或制造旧失败。停止/销毁与换源均在 3 秒行为断言内完成；2 秒 deadline 后也能重新打开本地双轨。测试绑定持续 pump 帧，避免新 VideoController 的 post-frame 初始化被测试自身阻塞。上述 Debug 耗时仅为取消上界断言，不能作为性能基准。

既有 Windows 请求头/302 重定向/Range/双轨解码/seek/重复打开专项通过；完整播放套件 7 项通过、1 项仍失败于 `windows_playback_test.dart:798` 的控件隐藏断言（期望没有 player-controls，实际仍有 1 个）。它与前一轮同样失败；本轮保留控件实现。非阻塞云进度、本地优先、多标签、工作区恢复用例通过。原生脱敏 HTTP 403 诊断和预读窗口各 1 项通过。

修改后的实际 `MediaKitEngine` Windows Profile 探针通过：本地 3 次打开 151–251 ms，两段游客在线视频共 4 次打开 479–1343 ms，实际双轨解码与 native 视频输出均确认，硬解为 `d3d11va-copy`。入口与结果为本地 `optimized_engine_probe.dart`、`optimized-engine-results.jsonl`。CDN 地址会随每次解析变化，不能将这些结果与前一轮直接相除当作固定提速比例。完整原生套件未启用线上游客开关；本轮线上证据来自上述 Profile 探针，不代表真实账号高清或完整页面性能验收。

最后 `flutter build windows --profile --no-pub -t lib/main.dart` 成功，已恢复默认 Profile 产物为正常应用入口，日志 `artifacts/playback-open-analysis/optimized-app-profile-build.log`。

日志位于本地 `artifacts/playback-open-analysis/optimization-check.log`、`startup-races-native.log`、`optimization-full-native.log`、`optimization-diagnostics-native.log`、`optimization-buffer-native.log`。Debug SDK 将热重启指针保存在带 PID 的系统临时文件中；初次完整验证在 `NativeReferenceHolder: Located` 后退出，疑似进程 ID 重用读取了旧指针。重跑使用独立 TEMP/TMP 目录后正常，未修改 SDK 或用户应用。构建重跑时串行执行，避免共享 Windows 构建目录的安装目标互相覆盖。

Android/macOS 原生音轨加载、真实账号高清双轨和更广泛 CDN/设备尚未验证；Windows Profile 正常源优化幅度不能从这两段样本概括为统一百分比。未提交或发布。

```powershell
$env:BILI_TEST_MEDIA_DIR = (Resolve-Path test/fixtures/media).Path
flutter test integration_test/windows_playback_startup_test.dart -d windows --no-pub
flutter test integration_test/windows_playback_test.dart -d windows --no-pub --plain-name 'Windows native DASH pair: headers, redirects, ranges, seek and lifecycle'
```

## 2026-10-11 明确终止失败提前切备用

本机安装的 `0.5.6+2` 日志在 15:28:33.558 开始打开，5.251 秒时记录 `stream/openFailed`，8.001 秒时达到首地址 deadline；备用地址打开 0.685 秒就绪。该日志是资源打开报错的分类，缺少终止原因、CDN 主机和轨道信息，不能单凭它确认整个原生文件加载已经终止或指定某个 CDN。

本轮将有备用地址的普通点播首地址预算改为 **6 秒**；两次打开仍共享 35 秒预算，没有备用地址与直播的预算保持原值。首次失败仍仅对 `nativePlayback` 尝试一个服务端备用地址。

播放器适配器通过 `media_kit 1.2.6` 的公开 `NativePlayer.handle` / `mpv` 接口，为当前播放器创建一个 libmpv weak client。它只消费自己的事件队列，不读取 SDK 主 client 的队列或替换其 wakeup callback，不创建第二个播放器。只有与 `START_FILE` 的 playlist entry ID 匹配的 `END_FILE(reason=ERROR, error<0)` 才中断视频轨道、外部音频及输出就绪等待；EOF、stop、quit、redirect、未知原因和普通 native error/log 均不触发提前失败。原生回调只通过 `NativeCallable.listener` 通知 Dart isolate，Dart 收到通知后用零超时读取事件。

每个播放器持有独立 observer；generation、播放器对象与 disposed 检查隔离旧事件。取消／换源与失败同时发生时，取消优先；observer 在 native Player 销毁前注销回调并释放 weak client，已排队的 Dart 回调检查 detached 后直接返回。应用每次尝试仍重新核对 source generation、关闭、取消、账号 scope 和 session epoch；旧失败不能启动备用。诊断新增 `openTerminated` 与数值 `nativeErrorCode`，不记录媒体地址、凭据或 native 原文。

ABI 字段与数值来自 [mpv 0.36.0 libmpv/client.h](https://github.com/mpv-player/mpv/blob/v0.36.0/libmpv/client.h)：独立编写所需的前三个 `mpv_event_end_file` 字段，没有复制播放器实现或修改生成绑定。该公开 client API 头文件为 ISC，许可保留于 [mpv-client.LICENSE](../../packages/bili_player/third_party/mpv-client.LICENSE)。未新增依赖或原生二进制。

本轮在已提交基线 `0a2f77a` 加本次修复的独立源码快照中执行 `tool/check.ps1`，格式、静态分析和全套测试通过：根应用 1857、API 390、播放器 51、弹幕 86、合并包 2；合并包另有 7 项因未配置原生库跳过。快照用于避免将并行直播功能的未完成代码混入验收，日志为本地忽略文件 `artifacts/playback-open-analysis/terminal-failure-isolated-check.log`。终止状态回归覆盖错误原因／entry ID 分类、错误先于就绪、取消优先和销毁后迟到事件；会话回归覆盖关闭、换源、账号 scope 和 session epoch 改变后不启动旧源备用。

Windows 原生 `windows_playback_startup_test.dart` 5 项通过：受控 HTTP 403 在最后一次运行中约 625 ms 结束打开，捕获 `END_FILE` 的 `errorCode=-13` 后在 500 ms 行为断言内报告失败；随后同一 engine 打开备用夹具并确认真实视频和音频解码。无响应外部音轨的 stop、换源、dispose 和 timeout 恢复及迟到事件回归仍通过。另有独立原生 HTTP 403 脱敏诊断 1 项通过。上述 Debug 耗时是提前结束／取消的行为证据，不是性能基准。日志为 `terminal-failure-native-final.log` 和 `terminal-failure-diagnostics.log`，位于同一忽略目录。

按用户安排，后续应用构建、安装和实机回归由用户手动完成；本轮仅进行了原生集成测试所需的 Windows Debug 测试入口构建，没有构建应用 Release 或替换系统已安装版本。Android/macOS 原生事件、真实账号与故障 CDN 未验证；受控 HTTP 失败验证不等于复现上述网络根因。

## 2026-10-21 阻止仅音频的打开假成功

针对 Windows/macOS 偶发打开缓慢、随后只有音频和黑屏，核对当前锁定 fork `63b7ea7dd95fc348cecf250df5f54ff87d69d8a9` 后发现：普通点播使用 `open(play: false)`，旧实现只等待视频轨道列表和外部音轨选中；后续 `play` 只确认音频解码。视频解码器或原生输出失败而音频正常时，打开仍可能成功，现有备用地址重试也不会触发。`NativeErrorMonitor` 以播放位置推进判断恢复，音频持续推进不能证明视频正常。

受控 Windows 原生复现保留合成 MP4 的视频轨道和样本，只将视频 sample entry 的 `avc1` 改为不支持的 `zzzz`，同时提供正常 AAC 外部音轨。修复前真实 `MediaKitEngine.open(play: false)` 返回成功，`play()` 后诊断为 `hasDecodedAudio=true`、`hasDecodedVideo=false`、`hasVideoOutput=false`，回归断言失败。日志 `build/black-screen-before.log` 是本地忽略文件。本机现有应用日志另有 HTTP 503 后达到 6 秒 deadline 再切备用的记录，但缺少对应黑屏时刻的视频状态，不能把它确定为本次偶发问题的根因或归咎于特定 CDN/GPU。

修复在共享 `MediaKitEngine.open` 内，对 DASH 视频及实际发现视频轨道的 progressive/manifest 源，先在暂停状态确认非零视频解码尺寸，再等待本源原生输出信号，之后才发布 `openReady`。桌面端、Android、悬停预览和暂停打开共用同一规则；纯音频源只等待媒体轨道发现。没有主动播放探测、第二个播放器、全局软解或固定等待。视频失败在原有打开 deadline 内退出并释放，应用沿用最多两次、同一 35 秒预算及服务端备用 URL；换源、关闭、账号边界仍沿用既有隔离。

结构化诊断增加 `readinessStage`（`tracks` / `externalAudio` / `videoDecode` / `videoOutput`）与三个解码/输出布尔值，便于区分解复用、解码及输出故障；不记录 URL、codec 原文或凭据。锁定 SDK 的输出信号来自有效原生输出尺寸，不等于实际屏幕像素或人工画面验收。

`integration_test/native_video_readiness_test.dart` 可在 Windows/macOS 原生执行：覆盖暂停/自动播放时拒绝无法解码的视频、同一 engine 换正常备用后恢复视频输出与真实音频解码、暂停意图和倍速保留，以及 progressive 视频与纯音频。已加入 `tool/test-windows-media.ps1`。

```powershell
$env:BILI_TEST_MEDIA_DIR = (Resolve-Path test/fixtures/media).Path
flutter test integration_test/native_video_readiness_test.dart -d windows --no-pub
```

macOS 在对应主机设置同一环境变量并用 `-d macos` 执行。

本轮验证：

- `tool/check.ps1 -SkipPub` 通过：根应用 1962、API 426、播放器 73、弹幕 93、mux 2，共 2556 项通过；格式、分析和打包边界脚本通过。mux 另有 10 项因未设置 `BILI_MUX_LIBRARY` 跳过，不视为原生通过。日志为 `build/black-screen-check-final.log`。
- 新增视频就绪原生回归 3 项通过；启动终止失败/stop/replace/dispose/timeout 原生回归 5 项通过。一次多入口原生测试调用的第二入口未建立调试连接，未进入测试；拆为独立调用后 5 项通过。日志为 `build/black-screen-native-regression.log`、`build/black-screen-startup.log`。
- 既有真实 DASH 请求头、302、Range、双轨解码、seek 和重复打开 1 项通过；悬停 5 秒缓冲窗口及普通打开恢复缓存 1 项通过；本地 HLS/FLV 共用直播会话 1 项通过。未启用在线 PGC/直播 CDN 用例，测试函数按开关直接返回，不计为在线验证。日志为 `build/black-screen-dash.log`、`build/black-screen-preview.log`、`build/black-screen-content.log`。
- `tool/test-windows-video-dispose.ps1` 的 9 项原生生命周期、渲染队列和尺寸回归通过，日志为 `build/black-screen-dispose.log`。
- 按 `bili_mux` README 准备 Windows 原生资产后，`flutter build windows --release --no-pub` 成功（51.4 秒）。运行入口为 `build/windows/x64/runner/Release/bilisail.exe`，分发须保留整个 Release 目录；未替换已安装应用或执行人工长时间播放验收。日志为 `build/black-screen-release.log`。

本轮没有访问真实账号、修改相邻 fork 或升级依赖。低概率线上故障、macOS/Android 原生执行和实机画面仍需验证，不能由 Windows 受控故障推导三端已验收。

## 2026-10-24 音频解码失败复用有界备用恢复

此前 `PlaybackSession` 的备用循环只包含 `engine.open(play: false)`，外部音轨已选中但首次 `engine.play()` 无法解码音频时，只会报错。现在共享会话将首次音频准备接入同一次解析的恢复状态，普通视频、影视和离线 DASH 共用该路径，播放器契约及原生实现不变。

- 媒体打开失败与首次音频解码失败共用最多两次打开额度。已经因打开失败用过备用时，后续音频失败不会再开第三次；没有备用地址或故障不属于 `nativePlayback` 时直接报错。备用仍来自原响应，视频和音频分别选择，只有音频有备用时保留原视频地址，不新增 playurl 刷新或额外循环。
- 原生打开及首次音频准备累计共享 35 秒；有备用地址的首轮打开与音频准备共用 6 秒。暂停打开保留剩余额度与预算，首次播放前的用户暂停时间不计入累计。音频成功解码后结束这次启动恢复，不把后续暂停/播放当作新的自动重试机会。
- 解码失败或等待超时后，先 stop 旧 generation 并等待释放，再在同一 engine 打开备用成对轨道；Dart Future 超时不会被当作底层命令已取消。超时耗尽同样 stop，迟到解码结果不能恢复旧源。恢复使用已确认进度、当前倍速和音量，按最新播放意图与播放许可决定是否继续；用户暂停或被标签互斥暂停时保持暂停。
- 每一步沿用 source generation、取消、关闭、账号 scope 和 session epoch 检查。恢复中的临时失败不直接写入页面错误，最终失败才交回既有错误提示与手动重新加载入口。

自动回归使用 fake engine/repository 和可控时钟，覆盖立即/暂停后首次播放恢复、仅音频备用与 PGC 身份、累计预算及超时、打开和解码混合失败不超过两次、无备用/不可恢复错误、恢复时暂停/许可变化，以及 stop/close/换源/账号切换/epoch 变化后的旧失败隔离。用例位于 [playback_session_test.dart](../../test/features/playback/playback_session_test.dart)。

本项只处理首次播放明确报告的音频解码失败及准备超时，没有添加持续的可听音频输出检测；正常进度继续但突然无声仍不能由此保证自动发现。按用户要求只运行自动检查，不构建应用或执行原生/实机验收；Windows、Android、macOS 实际声音、故障线路恢复与体验由后续运行构建确认。

本轮验证结果：

- 新增 17 项会话行为回归，包含音频解码成功后的暂停命令失败不能误用备用额度；完整 `playback_session_test.dart` 191 项通过。日志 `build/audio-recovery-session.log`。
- `tool/check.ps1 -SkipPub` 最终通过：根应用 2025、API 434、播放器 81、弹幕 93、mux 2，共 2635 项通过；格式、静态分析及打包边界脚本通过。mux 另有 10 项因未设置 `BILI_MUX_LIBRARY` 跳过，不计作原生验证。日志 `build/audio-recovery-check-final.log`。
- 两份播放文档的本地相对链接及本任务 `git diff --check` 通过。工作区同期评论相关改动保留；未修改播放器包、依赖或锁文件，未找到可热重载的调试进程。
