# 高能进度条实现方案

日期：2026-10-11。状态：协议、设置、会话和时间轴实现已落地。性能预算与实际验证结果分开记录，见 [实现验证](validation/high-energy-progress.md)。

## 1. 结论与范围

采用 **官网聚合趋势数据 + 现有播放时间轴 + 有界静态曲线**。不下载全量弹幕，不在播放过程中统计弹幕，不增加播放器、Ticker、定时刷新或原生依赖。

- Windows、macOS 默认开启；Android、iOS 等移动端默认关闭。已保存的用户选择优先于平台默认。
- 首批接入普通视频和分 P；影视共用展示组件，但须取得当前集的完整内容身份并通过时长校验。直播和离线播放不查询此接口。
- 开启后，控制栏显示时展示曲线；控制栏隐藏时保留现有底部细进度，不显示曲线。关闭弹幕画面不关闭高能曲线，两项设置独立。
- **存在章节时不请求、不显示高能曲线**。先等待现有章节元数据确认；章节读取失败或字段无效时也跳过高能请求，避免先显示曲线再切换章节。
- 没有数据、数据不匹配、接口失败时使用现有普通进度条。高能数据不参与媒体解析、打开、续播、seek、清晰度和语音切换的成功条件。

“不影响性能”落实为启动链路不增加依赖、后台零工作、绘制/内存有上限，以及开关 A/B 验收。附加功能有少量请求和绘制成本，不能在未测量前承诺绝对零开销。

## 2. 官网实际实现与证据

本轮以游客打开 [官网视频 BV1VEHn6TEKq](https://www.bilibili.com/video/BV1VEHn6TEKq/)，核对真实网络响应、播放器 DOM 和画面。官网请求：

```text
GET https://bvc.bilivideo.com/pbp/data
  ?aid=117385700835607&cid=42471916291&bvid=BV1VEHn6TEKq&r=loader
```

响应是顶层 `modules`，本次 `pbp` 模块的 `params.data` 包含 `events.default`、`step_sec`、`tagstr`。同一响应还带模块版本与脚本 URL，客户端只读取数据，绝不下载/执行返回的脚本。

| 项目 | 本轮观察 |
| --- | --- |
| 聚合数据 | UGC 响应 716 字节，74 个趋势值，`step_sec=1`；数值包含小数 |
| 视觉 | `.bpx-player-pbp` 为 SVG 面积曲线，实际高度 28 CSS px，位于进度轨道上方 |
| 曲线 | `viewBox="0 0 1000 100"`，使用贝塞尔曲线和裁剪路径；不随播放位置改变曲线几何 |
| 颜色 | 低透明度底色和主题色覆盖层；当前样本 `fill-opacity=0.2`，主题色默认蓝色 |
| 动态更新 | 播放位置改变已观看覆盖区和竖线；曲线与章节进度、时间预览共存 |
| 显隐 | 游客样本随控制栏显示曲线，另有“打开《高能进度条》常驻”入口 |

官网返回的 [PBP 3.6.2 脚本](https://i0.hdslb.com/bfs/static/pbp/pbp-3.6.2.min.js) 中也可见按最大值归一化、创建曲线、单独更新已观看裁剪区的职责。它含旧播放器适配逻辑；本方案以当前实际 DOM 为样式证据，独立实现 Dart/Flutter 绘制，不导入或复制该脚本。

曲线表示服务端提供的相对互动趋势。本次 UGC 数据中的聚合值与视频当前弹幕总数并不相等，因此不把纵轴显示为“每秒 X 条弹幕”，也不宣称这是精确弹幕计数或播放量曲线。服务端聚合算法、权重和更新频率没有被本轮核实。

### 2.1 身份与时长的实际问题

本轮控制变量读取发现，只有 `cid` 的旧式地址返回 HTTP 404；`cid+r=loader` 返回 HTTP 400。实现采用官网实际发送的完整 `aid+cid+bvid+r=loader`，不依赖旧接口示例。

另对游客可读的《名侦探柯南（中配）》`ep323085` 对应 `BV1wi4y1b7rM` / `aid=540491915` / `cid=184593713` 读取：HTTP 200，771 字节，100 个值，`step_sec=45`，数据调试字段 `max_time=4479`；视频详情当前 P 的时长为 1494 秒。同一稿件包含三个 P，时长和约为 4477 秒。

**推测**：该响应可能包含稿件级聚合，而不是当前 P 的趋势；仅凭这组数字不能确认服务端原因。它证明 HTTP 200 和有数组不足以认定曲线可用于当前单集。首版对此样本隐藏高能曲线，保留播放和预览，禁止把整条曲线强行缩放到当前集。多 P/影视均按同一时长规则检查。

官网参考与公开接口仍可能变化；本轮完成游客读取，未验证登录态、所有分区或所有影视内容。

## 3. 与现有项目的接入位置

当前已经有 [PlaybackTimelineBar](../lib/features/playback/presentation/playback_timeline_bar.dart)、章节轨道和雪碧图预览；[PlaybackPanel](../lib/features/playback/presentation/playback_panel.dart) 已把 position/buffered 更新限制在局部。[PlaybackSession](../lib/features/playback/application/playback_session.dart) 管理源 generation、账号 scope/epoch 和可选元数据。

```mermaid
flowchart LR
  API[官网 PBP 聚合接口] --> Client[bili_api HighEnergyClient]
  Client --> Repo[HighEnergyRepository / ApiPlaybackRepository]
  Repo --> Session[PlaybackSession 源级趋势状态]
  Session --> Curve[PlaybackTimelineBar 静态曲线]
  Snapshots[已有确认位置快照] --> Clip[局部已播放裁剪与滑块]
  Curve --> Clip
```

| 层 | 实现 |
| --- | --- |
| `bili_api` | 独立 `HighEnergyClient` 读取与有界解析；`BiliApiClient.highEnergyBytes` 固定公开 host/path；公共入口导出不可变结果 |
| playback/domain | 独立可选 `HighEnergyRepository` 能力，保持现有元数据接口兼容；纯 Dart `HighEnergyTrend` 包含采样跨度与归一化点，不含 JSON、脚本地址或 Flutter Path |
| playback/data | `ApiPlaybackRepository` 映射，`HighEnergyCache` 提供容量受限缓存和在途合并；`OfflinePlaybackRepository` 转发在线能力，离线返回不适用 |
| playback/application | `PlaybackSession` 管理趋势状态、取消和来源校验；独立 `ValueNotifier` 发布源级变化，不通过会话整体 `_notify()` 驱动播放页重建 |
| playback/presentation | `PlaybackTimelineBar` 复用现有轨道范围、RTL 映射、缩略图、菜单及一次 seek；增加局部曲线层 |
| settings/app | 一个持久化布尔设置；平台默认在 `app/platform_defaults.dart` 计算并注入设置仓储 |

不修改 `bili_player` 或 `bili_danmaku`，不把趋势统计放进弹幕控制器。网络、缓存和 JSON 解析仍不进入 UI。

影视入口已通过 `bili_app.dart` 的 `_episodeDetail` 传递剧集真实 aid/bvid 和 part；高能读取复用这些资料并核对当前 cid。缺少完整身份时跳过，不为高能曲线额外查询详情。

## 4. 请求、解析与缓存

### 4.1 端点登记

| 项目 | 策略 |
| --- | --- |
| Profile | Public PBP，仅只读 |
| Host / Method / Path | `bvc.bilivideo.com` / GET / `/pbp/data` |
| 参数 | 字符串 `aid`、`cid`、`bvid`；固定 `r=loader`；只编码一次 |
| 鉴权/签名 | 本轮游客可用；不带 Cookie、Authorization、CSRF 或 WBI |
| Header / TLS | `Referer: https://www.bilibili.com/`；本轮核实可用的浏览器 UA；保留系统 TLS |
| 响应 | 顶层 `modules` 中匹配 `name=pbp` 的 `params.data`；无分页；不执行 `script_src` |
| 超时与重试 | 6 秒总 deadline；网络/超时/部分 5xx 至多额外一次读重试；限流、403、404、空数据和协议错误不自动重试 |
| 失败展示 | 本地脱敏诊断；不 toast，不使用播放器主错误位，不阻塞视频 |

当前 `BiliApiClient.requestJson` 仅允许 Bilibili API 域名，并按 `code/data` 包装解析；PBP 域名和顶层 `modules` 均不符合该入口。应增加固定 host/path 的公开数据读取入口，复用 `ApiTransport`、取消、deadline 和错误分类，**不能只把新 host 加入通用鉴权白名单**。默认拒绝重定向；不向该媒体域发送账号凭据。

### 4.2 解析规则

1. 响应解压后上限 256 KiB，在接收过程中计数并中断超限，不能等全量缓冲完再判断。最多 16 个模块、20000 个原始趋势值；无 `pbp`/无数据/空数组表示无可用趋势。
2. `step_sec` 必须有限、正数，精度转成有单位的 `Duration`；趋势值允许非负有限整数/小数。跨度不得超过七天，禁止用 debug 字符串作为 UI/时间轴的必需字段。
3. `tagstr` 只作为有界协议字段。发现服务端显式隐藏标记时保守判为不可用；其余实验标签不驱动产品逻辑，隐藏标记语义须补 fixture 和官网对照后固定。
4. 用原始数量与 `step_sec` 计算采样覆盖跨度，在降采样前与当前 P/集可信时长比较。首版容差 `max(2 × step, 2 秒)`；超过容差隐藏曲线。媒体时长暂未确认时先保留候选数据，待 duration 就绪后校验再显示，不压缩跨度、不把缺失数据补成虚假热度。
5. 全零数据隐藏；其余按该视频最大值归一化到 `[0,1]`，不添加对数拉伸、额外权重或随播放漂移的归一化。
6. 保留端点和时间位置，按时间桶提取先后有序的 min/max，输出最多 512 个点；短视频不扩充点数。构造平滑曲线时控制点不得超出相邻值和合法范围，避免制造尖峰。悬停查询采用这些有界点的二分/插值，不显示未经核实的绝对计数。

采用与官网相近的全宽展示：对通过跨度校验的数据按有序采样的相对位置映射轨道，显式保留尾部闭合点；seek 与预览始终由播放器真实 duration 映射。短暂的端点取整差由上述容差吸收；明显跨度差不能靠归一化掩盖。

解析/降采样只发生在数据到达时。超过 32 KiB 的响应在 isolate 中一次完成校验、归一化和降采样，只向 UI isolate 返回紧凑不可变结果；小响应走有界直接解析。只允许当前可见播放页发起可选读取，避免后台多标签同时创建解析任务。禁止在 `build()`、`paint()` 或 position 回调中重新处理数组。

### 4.3 生命周期与缓存

- 内存 LRU 最多 32 条且总计不超过 1 MiB，只保存归一化结果；成功 TTL 30 分钟、空/不可用结果 TTL 10 分钟，不写 SQLite 或文件。数量/字节上限同时约束；在用会话只持有本源的一份结果引用。
- 键为 `(sessionEpoch, aid, cid, bvid)`；epoch 在每次账号切换时递增，隔离账号并立即清除缓存和在途请求。同键单飞；各消费者独立取消，最后一个退出后取消底层操作。会话另核对 accountScope。
- 同一内容的 seek、倍速、音量、全屏、同 cid 清晰度/语音切换复用成功结果；新 generation 重新绑定并校验，不让旧回调写入新会话。换 P/集/视频立刻清除旧曲线。
- 一次逻辑读取最多两次实际 HTTP 尝试；空数据和失败负缓存 10 分钟，开关切换、换清晰度或重复 hover 复用负缓存。取消不计作无数据，返回可见状态可重新读取。无轮询、后台补试或下载其他 P。
- 关闭设置立即取消当前消费者、移除绘制状态；关闭标签释放请求、Notifier 和 Path/Picture 等局部资源。后台标签取消未完成的可选读取且不绘制，返回时优先缓存。缓存本身受 LRU/TTL 约束。

## 5. 加载与展示时机

```text
媒体打开与恢复确认完成
  → 检查设置、在线点播、页面可见性、真实内容身份
  → 等待已有章节元数据确认成功且没有章节
  → 首次控制栏实际可见时 ensureHighEnergy()
  → 查缓存 / 发起独立可取消请求
  → 解析、时长匹配、校验 generation + scope + epoch + 仍开启
  → 仅发布趋势 Notifier，更新局部曲线
```

请求不能放入准备播放的 `Future.wait` 或统一 ready 屏障。播放已就绪但曲线请求悬挂时，仍可播放、暂停、seek 和关闭。初始控制栏可见时会自动加载，用户无须先 hover；隐藏控制栏和隐藏标签不主动加载。移动端关闭时无请求，手动开启后使用同一有界实现。

确认无章节且数据有效后增加曲线行；加载失败不占空行。变化只影响画面内的控制栏高度，不改视频 surface 尺寸或页面布局，不在每次 position 更新时重新测量曲线路径。

## 6. 样式与交互

- 曲线贴在现有进度轨道上方，桌面常规高度 24 logical px，小窗/手动开启的移动端 16 px；透明度约 0.2。峰值不发光、不循环动画，不叠加阴影/模糊。
- 使用播放器主题主色；未播放部分为低透明度中性底色，已播放部分轻量着色。保持滑块、缓冲色、章节分隔和轨道点击的辨识度。
- 章节与高能曲线互斥；章节标题、菜单及分段轨道保持原交互。缩略图卡片在曲线上方避让；320 px 小窗仍优先显示时间。失败不新增占位文字或 spinner。
- 曲线层 `IgnorePointer`，沿用现有 Slider 的点击/拖动与 hover 映射；拖动只预览，松开一次 seek。不新增覆盖整段时间轴的手势竞争层，不实现吸附峰值或自动跳转。
- 保留现有时间/章节/缩略图预览；首版不增加“弹幕 X 条”等未知单位提示。曲线作为装饰排除独立语义节点，读屏继续使用现有 Slider 时间语义。
- 一个“高能进度条”开关，位于播放设置；播放器设置入口复用同一个值，两处都说明存在章节时不显示。

## 7. 绘制隔离与性能上限

`HighEnergyCurve` 分开持有趋势/几何与动态位置：

1. 静态底色曲线是独立 `CustomPaint + RepaintBoundary`。State 缓存至多 512 点的 Path；只在数据身份、轨道尺寸或有效 duration 改变时重建。主题变化更新 Paint，不重新降采样。
2. 已播放色使用同一条缓存几何，由已有局部位置快照驱动裁剪范围；复用静态子树或录制结果，仅修改 clip 与位置。禁止复制点列表、生成 SVG 字符串或重新创建曲线路径。
3. 曲线应与 Slider 实际 `getPreferredRect()` 对齐，包含 thumb 内缩和 RTL；不能凭两套硬编码宽度近似。悬停、seek、缓冲变化不改变曲线几何。
4. 页面不可见、设置关闭或控制栏折叠时不挂载曲线绘制和位置订阅。控制栏显隐只使用已有过渡，不加动画控制器。全屏共用会话和数据，只重建新的局部几何。
5. 不预生成整张大位图；如果使用 Picture，替换/销毁时显式 dispose。缓存只保留本组件当前尺寸，窗口 resize 合并为每帧最多一次几何计算。

## 8. 设置兼容

新增 `AppSettings.highEnergyProgressEnabled`，贯通 defaults、copyWith、读取、保存、controller 与两处入口。domain 保持纯 Dart；平台判断在 app 层，以默认值参数注入 `SqliteSettingsRepository`。

| 平台 | 新安装 / 旧设置缺键 |
| --- | --- |
| Windows / macOS | `true` |
| Android / iOS | `false` |
| 其他未纳入平台 | `false`，不扩大支持声明 |

旧快照缺键/值类型无效时使用本平台默认；合法 bool 原样保留，包括桌面已关闭和移动已开启。`preferences.v1` 快照 schemaVersion 从 19 增至 20。无需改数据库表或清空设置。

## 9. 验收与实施顺序

### 9.1 必须通过的行为与结构检查

- 关闭设置、默认移动端、直播、离线源：该功能请求/解析/绘制计数均为 0。
- 正常数据、空模块、全零、非有限/负值、超限、超时、限流、隐藏标记、身份和跨度不匹配都有脱敏 fixture；保留小数与字符串 ID。
- 请求无限等待或失败不影响 media ready、首帧、续播和 seek；关闭设置/标签/账号变化取消等待，迟到数据无效。
- 1000 次位置/缓冲更新：静态曲线几何构建次数保持 1，静态层不因位置重绘，页面/影视侧栏重建数不增加；动态层只更新本地裁剪。计数测试按相同数据和尺寸计算，避免仅测试实现细节。
- 全屏/窗口改变只更新几何；同 cid 换清晰度不增加网络读取；换 P 切换数据，旧响应不覆盖。hover 不 seek、拖动只 seek 一次；章节/缩略图与 RTL/320 px/双倍文字继续正常。
- 反复切换源/开关、长视频和 16 个标签验证 LRU、失败预算、订阅/取消及资源回收，正常 CI 不联网。

### 9.2 Profile/Release A/B 门槛

同一提交、设备、媒体、弹幕 fixture、窗口、主题、刷新率和热缓存，交替运行关闭/开启各至少 3 次。覆盖曲线加载、控制栏常显/折叠、密集弹幕、拖动、窗口连续 resize、全屏及多标签返回。固定输入播放 10 分钟，长时间资源另测 30 分钟。

| 指标 | 拟定门槛；实施后实测记录 |
| --- | --- |
| 媒体启动依赖 | 0 个新增等待；fake 仓储挂起时原有 ready/seek 流程照常完成 |
| UI / raster p95 | 相对关闭分别增加不超过 0.3 ms，且符合现有场景帧预算；p99 同时报告 |
| 超帧预算比例 | 增幅不超过 0.2 个百分点，60/120 Hz 分别按实际帧预算计算 |
| CPU | 热稳态进程 CPU 增幅不超过 1 个百分点，记录口径及采样区间 |
| 内存 | 单可见会话热稳态 Dart heap 增量不超过 1 MiB；RSS 增量目标不超过 4 MiB，native 绘制缓存单独统计 |
| 解析/几何 | 小响应解析和一次几何各 p95 目标不超过 1 ms；超出转 isolate/降低点上限后重新验收 |
| 持续资源 | 不增加 Ticker/Timer/engine；折叠/隐藏无新增位置订阅和绘制；关闭后资源回到规定缓存热稳态，无持续增长 |

这些门槛用于拒绝明显回归，非当前保证。噪声超过门槛时延长固定脚本采样并报告误差，不能把单次更快当作通过。失败先减轻绘制和任务负担，保留用户平台默认要求；仍不能达标则不交付开启状态的功能。

实施顺序：协议和 fixture → 纯 Dart 映射/缓存/默认值 → 会话取消与局部订阅 → 时间轴绘制和交互 → `tool/check.ps1` → Windows Profile/Release → macOS 真机 → Android 真机默认关闭及手动开启。不需要先加入 Rust、Canvas 热力图库或新原生库。

实现检查、Windows Profile 及未测项见 [实现验证](validation/high-energy-progress.md)。以上长时、多标签、密集弹幕与跨平台预算仍是后续完整性能验收范围，不能由短时单机场景替代。

## 10. 来源和调研文件

采用来源是官网实际网络响应、DOM 和只读脚本。只借鉴协议字段、视觉和职责，独立编写实现；不复制官网代码、图片、字体或资源，不将官网脚本加入依赖。上游脚本未取得明确再分发许可，调研副本只保留在忽略的 `artifacts/high-energy-research/`。

- [官网样本](https://www.bilibili.com/video/BV1VEHn6TEKq/)、[官网聚合响应](https://bvc.bilivideo.com/pbp/data?aid=117385700835607&cid=42471916291&bvid=BV1VEHn6TEKq&r=loader)、[官网模块](https://i0.hdslb.com/bfs/static/pbp/pbp-3.6.2.min.js)。
- 调研副本：`ugc-loader.json`、`pgc-loader.json`、`official-core.js`、`official-pbp-3.6.2.js`；PBP 脚本 SHA-256 `74ceadb266ccc7ba3f8c72de377d1ca81536b4d5e927a9d9ae1db965d9a0344a`。没有保存 Cookie/Authorization、账号或二维码信息。
- 当前工程边界：[章节与缩略图](validation/playback-timeline.md)、[播放设计](playback-and-danmaku.md)、[API 设计](api-design.md)、[性能验收口径](implementation-plan.md#性能预算与记录)。
