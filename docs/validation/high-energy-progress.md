# 高能进度条实现验证

日期：2026-10-11。功能已经接入；Windows 短时 Profile 与自动化不能替代 macOS、移动端真机和长期资源验收。

## 实现与互斥

- Windows/macOS 新安装、旧设置缺键默认开启；Android/iOS 及其他平台默认关闭。合法手动选择优先。全局播放设置与播放器设置共用 `highEnergyProgressEnabled`，设置快照版本 20，不改变 SQLite 表结构。
- 先等待现有 `/x/player/wbi/v2` 章节结果。存在任何章节、章节读取失败或字段无效时不请求、不显示高能曲线；界面另外检查章节互斥。
- 初始控件可见时独立读取 PBP。直播、离线、移动默认关闭、隐藏控件/标签不发请求；没有完整 aid/cid/bvid 或可信时长也跳过。后台继续原有播放行为。
- 可选请求不参与媒体打开/续播屏障。6 秒总 deadline、至多 2 次网络尝试；固定公开域名，Cookie/Authorization 不发送，不跟随重定向，不执行返回脚本。
- 解压后流式上限 256 KiB、最多 20,000 原始值，超过 32 KiB 的响应在 isolate 内完成解析、归一化和降采样；最终最多 512 点。全零、无数据与时长不符回退普通轨道。
- 进程内 LRU 最多 32 项及 1 MiB 估算容量；成功 30 分钟、无数据/失败 10 分钟，同键单飞，最后一个消费者退出取消底层请求。账号 epoch 变化清空缓存和在途读取。
- `HighEnergyCurve` 缓存 Path 和两层绘制子树，位置只改变外部 ClipRect。没有新增 Ticker、轮询、播放器、运行时依赖、数据库缓存或全量弹幕读取。性能驱动显式声明已有 Flutter SDK 内的 `flutter_driver` 开发依赖。曲线为装饰，不拦截手势；seek 仍只在拖动松开时触发一次。

相关实现：[协议客户端](../../packages/bili_api/lib/src/clients/high_energy_client.dart)、[有界传输](../../packages/bili_api/lib/src/transport.dart)、[缓存](../../lib/features/playback/data/high_energy_cache.dart)、[会话](../../lib/features/playback/application/playback_session.dart)、[曲线](../../lib/features/playback/presentation/high_energy_curve.dart)。[设计及官网来源](../high-energy-progress-design.md) 保留调研证据与预算。

## 自动化

`tool/check.ps1 -SkipPub` 已通过：根应用 1905 项、bili_api 411 项、bili_player 51 项、bili_danmaku 86 项、bili_mux 2 项（7 项需要原生 mux 库的测试按既有规则跳过）；格式、分析与打包边界脚本通过。依赖保持原锁定版本。

覆盖公开参数与小数、隐藏标记、解压后接收上限、20,000 点极值保留、取消/deadline/HTTP 重试、LRU/TTL/失败负缓存/单飞与账号清理、章节未确认与故障零请求、直播/离线/关闭零请求、旧源/账号/设置/隐藏/stop 的晚到响应、纯局部通知、seek 复用、时长不符、平台默认与设置保存。

绘制测试连续更新 1000 次 position 只构建 1 次 Path；改宽度重建一次，改变 RTL 不重建 Path。章节存在时找不到曲线组件，保留菜单；拖动只 seek 一次，数据清空后保留原 Slider。

## 在线与 Windows Profile

游客实际数据回归：

| 视频 | 当前 P 时长 | 章节 | 曲线跨度 | 处理 |
| --- | ---: | ---: | ---: | --- |
| BV1VEHn6TEKq | 72 秒 | 5 | 74 秒 | 章节优先，应用不请求高能 |
| BV1xx411c7mD | 2055 秒 | 0 | 2058 秒（98 点） | 有效曲线，原生音视频均解码 |
| BV1GJ411x7h7 | 213 秒 | 0 | 855 秒 | 多 P/跨度不一致，回退普通进度条 |

Windows Flutter 3.47.6 Profile 原生集成脚本检查实际曲线、窗口/全屏/320 px 小窗与同一 engine generation，随后切到真实章节视频检查互斥。性能对照采用同一个媒体、960 px 窗口、固定主题和热数据，弹幕关闭；交替开启/关闭各三次、每段 20 秒。资源采样由 VM 强制 GC 后读取 heap/external，并按进程 CPU 秒数/墙钟时间/逻辑处理器数计算 CPU 百分比；采样安排在计时区间外。

最终轮在完整检查结束后独立采样，刷新率 180 Hz，每段约 3600 帧，共 21,601 帧；窗口、全屏、320 px 小窗、真实章节互斥均通过。主应用 `flutter build windows --release --no-pub` 通过。构建存在上游 in_app_webview 的 CMake/C++ 警告，本功能未修改原生代码。

| 轮次 | UI p95 关闭/开启 | raster p95 关闭/开启 | CPU 关闭/开启 | GC 后 heap 开启减关闭 |
| --- | --- | --- | --- | --- |
| 1 | 0.318 / 0.337 ms | 0.628 / 0.681 ms | 1.75% / 2.05% | -7.3 KiB |
| 2 | 0.315 / 0.349 ms | 0.663 / 0.683 ms | 1.78% / 1.97% | -2.1 KiB |
| 3 | 0.324 / 0.342 ms | 0.617 / 0.685 ms | 1.81% / 1.68% | +33.0 KiB |

开启后的最大配对 UI/raster p95 增量为 0.034/0.068 ms，CPU 为 +0.30 个百分点，heap 为 +33 KiB，external 为 +224 字节。开启样本 0 帧超过实际 180 Hz 的 5.56 ms UI/raster 预算；关闭样本有 1 帧超过，共 0 帧超过 16.67 ms。UI p99 开启最大 0.429 ms，raster p99 开启最大 0.796 ms。这一场景达到帧耗时、CPU 与 Dart 内存的拟定预算。

RSS 经 GC 后仍有波动：配对差异 -4.84 / +18.69 / +7.63 MiB，未证明 4 MiB 的预算。关闭样本的 RSS 本身也从约 307 MiB 增至 324 MiB；原生媒体缓冲、绘制缓存及测量波动尚未拆分，不能将差异归因于曲线，也不能声称 RSS/长期资源验收通过。

原始输出仅在忽略的 `artifacts/high-energy-research/` 中：`check.log`、`windows-profile.log`、`profile.json`、`resources.json`、`windows-release.log`、`window.png`、`compact.png`、`chapters.png`。最初的探索采样与最终受控轮分开保存；结论采用最后一轮。

复现（明确选择在线测试，普通 CI 不联网）：

```powershell
$env:BILI_HIGH_ENERGY_OUTPUT = Join-Path $PWD 'artifacts/high-energy-research'
New-Item -ItemType Directory -Force $env:BILI_HIGH_ENERGY_OUTPUT | Out-Null
flutter drive -d windows --profile --no-pub `
  --driver tool/validation/high_energy_driver.dart `
  --target integration_test/windows_high_energy_test.dart `
  --dart-define=BILI_ONLINE_SMOKE=true
```

## 验证边界

macOS 构建/真机、Android/iOS 真机默认关闭与手动开启尚未验证。以上短时场景没有覆盖 10 分钟密集弹幕、30 分钟资源稳定性、16 标签、连续 resize、512 点原生渲染或所有媒体源；不能把单个样本的低耗时解释为所有设备绝对零开销。
