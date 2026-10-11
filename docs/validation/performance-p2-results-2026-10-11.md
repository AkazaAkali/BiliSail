# 首页推荐与三类播放性能热点：P2 优化结果

日期：2026-10-11。实施基线：`c91e8ab`。承接[热点调查](performance-hotspots-2026-10-11.md)与[第一批 P1 结果](performance-hotspots-results-2026-10-11.md)。三个 Astra xhigh 子代理分别处理首页、共享播放、影视；主代理处理评论与直播，统一交叉 review、检查和提交。

本轮对 11 项热点实施优化；F6 完成解析阶段采样，V7 增加有界诊断和受控绘制探针，两者的媒体复用／绘制策略调整仍等待实机证据。未更换依赖、网络端点或原生播放器后端，也未增加自动遥测。

## 1. 范围与证据

下文 C 为受控结构计数，J 为 Windows Dart 3.13.5 CLI JIT 微基准，O 为少量匿名在线请求。它们分别证明工作量、合成 CPU 趋势和当次网络观察，均不能换算真实设备帧率、首帧、功耗或内存改善。Flutter widget 测试用于行为回归，不作性能验收。

| 热点 | 本轮结果 | 主要源码 |
| --- | --- | --- |
| F3 图片连接复用 | 缓存所有者持有最多 6 个独占请求 lane，成功请求可复用连接，取消只关闭对应 lane | [ImageByteCache](../../lib/core/storage/image_byte_cache.dart) |
| F4 长列表合并 | ID 增量索引、128 项分块不可变快照；更新命中项时只复制受影响块 | [FeedItemIndex](../../lib/features/feed/application/feed_item_index.dart)、[FeedController](../../lib/features/feed/application/feed_controller.dart) |
| F5 隐藏频道订阅 | 视频频道订阅自己的状态，非视频频道不订阅 FeedState；使用当前工作区 controller，保留嵌套作用域隔离 | [FeedScreen](../../lib/features/feed/presentation/feed_screen.dart) |
| F6 悬停媒体／native 重复准备 | 已采样详情、playurl 与映射阶段；暂不增加媒体缓存或 warm engine 池 | [预览控制器](../../lib/features/video/application/video_card_preview_playback.dart) |
| V4 播放准备串行 | 保存旧进度后并发 stop、解析媒体和适用的本地进度读取；原生 open 仍等待 stop 完成 | [PlaybackSession](../../lib/features/playback/application/playback_session.dart)、[启动诊断](../../lib/features/playback/application/playback_startup_diagnostics.dart) |
| V5 字幕线性扫描 | 单次构建显示区间索引；顺播游标、跳转二分，同位置不查询，同 cue 不重建字幕 | [SubtitleCueIndex](../../lib/features/playback/domain/subtitle_cue_index.dart)、[PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart) |
| V6 评论全量构造／大订阅 | 懒创建列表、稳定 key 与 ID 索引；头部、编辑器、列表、单行分别订阅 | [CommentsPanel](../../lib/shared/ui/comments_panel.dart) |
| V7 高 DPR 图像缓存回退 | 增加生命周期累计计数，测到预算／尺寸回退；保留原 32 MiB 和直接绘制策略 | [文字样式与诊断](../../packages/bili_danmaku/lib/src/danmaku_text_style.dart) |
| G3 影视重复分组／定位 | 不可变 season 惰性拥有共享索引；倒序只转换位置，hover 仅更新局部滚动条 | [PgcSeason](../../lib/features/pgc/domain/pgc_repository.dart)、[选集面板](../../lib/features/pgc/presentation/pgc_episode_panel.dart) |
| G4 大影视响应同步解码 | 响应字节达到 512 KiB 时将 JSON／DTO 转 worker；复用进程级 2 运行／4 等待配额 | [PgcClient](../../packages/bili_api/lib/src/clients/pgc_client.dart)、[纯解码](../../packages/bili_api/lib/src/decoding/pgc_season_decoder.dart) |
| G5 影视重复详情请求 | 同账号代次内 8 季、2 分钟 TTL、LRU 和独立消费者单飞；显式刷新绕过缓存 | [ApiPgcRepository](../../lib/features/pgc/data/api_pgc_repository.dart) |
| L3 聊天重复解析／条目移动 | 有界纯内容缓存、复用未变化行、稳定 key；淘汰窗口头部时保持已滚动的可见消息位置 | [LiveChatContent](../../lib/features/live/domain/live_chat_content.dart)、[LiveScreen](../../lib/features/live/presentation/live_screen.dart)、[聊天气泡](../../lib/features/live/presentation/live_chat_bubble.dart) |
| L4 对账通知／倒计时重设 | 周期读取保持静默，相同结果保留列表；手动刷新保留反馈；无关更新不重置倒计时相位 | [LiveController](../../lib/features/live/application/live_controller.dart)、[SC 卡片](../../lib/features/live/presentation/live_super_chat_card.dart) |

## 2. 首页推荐

### F3：有所有者的有界连接复用

默认公开图片传输由 `ImageByteCache` 按需持有最多 6 个 lane，每个 lane 的 HttpClient 同时只服务一个请求，`maxConnectionsPerHost=1`，空闲超时 15 秒。只复用相同来源的空闲 lane；池满时接纳新来源会淘汰一个闲置 lane，跨来源重定向、失败或取消会退休当前 lane。账号 scope／epoch 改变及 close 清理连接池；没有无所有者的全局 client。独立 `loadPublicImage` 调用使用一次性池。

取消在 DNS／TLS／getUrl 尚未产生 request 时也能关闭自己的 client，不影响其他 lane。继续限制 HTTPS、来源白名单、最多 3 次手动重定向、4 MiB、原超时，并使用系统 TLS 校验；请求不携带 Cookie／Authorization。测试仅在 loopback server 注入独立测试信任根，同时验证默认传输拒绝自签证书。

C：本地 TLS 服务连续两批、每批 6 张图，HttpClient 创建数和 TCP 连接数均从 12 降到 6，第二批新连接从 6 降到 0。该结果证明连接可以复用，没有测真实 CDN 的 DNS／TLS／下载时延或流量。

### F4／F5：分页增量维护与频道隔离

ID 索引保留旧列表顺序，同 ID 更新仍取最后一份值；快照不可变，旧快照不受后续分页修改。每次合并复制块目录和发生变化的 128 项块，目录成本仍为 O(N/128)。没有新增产品级条目截断；索引随已加载条目增长，会增加常驻内存，不能宣称列表 heap 已有界。provider dispose 同步清理频道快照、ID 索引和反馈状态。

J：同一规模预热 20 次、采样 50 次，单次追加 20 项的 P50／P95（µs）：

| 已加载项数 | 原整表合并 | 分块增量合并 |
| --- | --- | --- |
| 20 | 11 / 25 | 10 / 19 |
| 500 | 42 / 104 | 14 / 119 |
| 2000 | 82 / 103 | 3 / 5 |
| 10000 | 645 / 1157 | 5 / 10 |

以上不含首次建索引、API、UI 或 heap profiling；500 项 P95 更慢，不能声称所有规模稳定改善。500 页／10000 项完整保留及重复项更新已做行为回归。

C：保留并访问 12 个频道、500 项 fake 数据，推荐频道进入 loading 和完成各阶段，频道 build 从 12 降至 1，PagedViewport build 从 16 降至 1，隐藏的 11 个频道各阶段为 0。最初派生 family Provider 在嵌套 workspace 下误用了父作用域，review 后改为直接订阅当前 controller；select 使用传入快照读取当前状态，隐藏频道读取该 controller 的频道缓存，不读取 Ref／Notifier.state。父 scope 预读、子 scope override 和工作区路由已回归。

### F6：暂缓媒体和原生实例复用

O：匿名读取两个公开视频，顺序 A→B→A，共 3 次，详情阶段为 191.892／67.805／0 ms，playurl 解析为 108.306／56.953／58.412 ms，映射为 1.773／0.078／0.080 ms。冷解析包含 WBI 准备，不同样本清晰度为 32／16，不能当作同条件配对或计算有意义的 P95。

没有下载媒体、测 native 创建／首帧或真实快速 hover 占比。`PlaybackMedia` 仍缺统一可靠的 URL 有效期契约；一次响应含 deadline 参数不证明所有 URL 可安全缓存。因此保留 200 ms 悬停延迟、单个活动预览 engine、5 秒预读及取消／串行释放，暂不增加媒体缓存或预热播放器。

## 3. 视频与共享播放

### V4：并发准备但保留状态机屏障

保存旧播放进度仍是前置屏障，随后独立进行旧媒体 stop、媒体解析与适用的本地进度读取。所有 future 立即纳入等待和错误处理；stop 成功完成前不会 open 新媒体。原账号代次、源 generation、取消、closing、声音轨道和用户续播选项检查保留。review 补充了“解析期间续播由关闭改为开启”的本地进度补读回归。

新增最多 32 条的会话内阶段记录，只含枚举、generation、单调开始／耗时和完成标记，不含 URL、账号、正文或原始错误，不落盘、不上传。C：fake stop=10 ms、解析=20 ms、本地读取=5 ms 时，原生 open 的串行准备 35 ms 变为并行 20 ms；这证明依赖关系改变，不能说明真实首帧减少 15 ms。原 35 秒打开预算、首 CDN 8 秒策略和云端续播非阻塞语义不变。

### V5：保持字幕重叠语义的索引

按时间边界构造不相交显示区间，重叠时仍选择原始列表最靠前的 cue，遵守 `start <= position < end`；支持乱序、seek 和相邻边界。顺播使用游标，其他位置二分；相同 position 跳过查询，buffer 更新不查询。

C：1000 次顺播＋1000 次随机查询，结果逐次与旧线扫一致：

| cue 数 | 旧扫描 cue 次数 | 新区间边界比较次数 | 显示区间数 |
| --- | ---: | ---: | ---: |
| 500 | 431751 | 16068 | 668 |
| 5000 | 4214373 | 30555 | 6668 |
| 20000 | 16935909 | 34548 | 26668 |

旧计数每访问一个 cue 记一次，内部可能进行一到两次时间判断；新计数每次区间边界判断记一次，不能直接按比例推导 CPU 耗时。100 次同位置额外查询为 0。同 cue 内 20 次位置更新的字幕 Text build 为 0，随后 20 次 buffer 更新的额外查询和 Text build 均为 0。首次索引构造和存储增加一次性成本，未测真实长字幕的 Profile CPU 占比。

### V6：评论懒创建与局部订阅

保留 500 条数据容量、主评论／楼中楼页面回退、草稿、滚动位置、显式写操作与全局写入互斥。列表使用 builder 与稳定 ID 定位，头部、编辑器、列表和单行分别订阅；回复目标变化无需替换评论 ListView，单行忙碌状态仍能禁用操作。C：500 条输入的 delegate 为 501 项（含页尾），初始挂载富评论组件少于 30；回复目标变化保留原列表 Widget／Element。没有将 500 条评论全部挂载来维持滚动状态。

### V7：先观测回退，保留预算

点播／直播控制器的 `rasterStatistics` 在读取时生成快照，内部只累加整数：image paint、命中、创建、尺寸／单图预算／活动预算回退、直接绘制项帧和峰值 RGBA 字节；不保存弹幕正文。`directPaints` 是条目×绘制次数，并非 Flutter 帧数。

C：Ahem 测试字体、24px、60 个唯一文本、每组绘制 10 次、保护全部活动图像，PictureRecorder 结果如下：

| 字符数 | DPR | 直接绘制项帧 / 600 | 原因 | 峰值 RGBA bytes |
| --- | --- | --- | --- | --- |
| 12 | 1 / 2 / 3 | 0 / 0 / 0 | 无 | 2592000 / 10368000 / 23328000 |
| 42 | 1 | 0 | 无 | 8812800 |
| 42 | 2 | 30 | 活动工作集满 | 33488640 |
| 42 | 3 | 350 | 活动工作集满 | 33048000 |
| 302 | 1 / 2 / 3 | 600 / 600 / 600 | 图像尺寸超过 4096 | 0 / 0 / 0 |

回退可复现，但这不是实际视频同播或 FrameTiming。保留每控制器 32 MiB、视觉密度和直接绘制，DPR 1／2 像素一致性测试继续通过。是否分块 raster、调整效果或预算，等待真实高 DPR 设备 UI／raster P95/P99 和 GPU／进程内存配对数据。

## 4. 影视

### G3：season 拥有索引

controller、选集面板和连续播放复用不可变 season 的惰性索引。展示分组继续 trim／空标题归“正片”，连续播放继续保留原始 sectionTitle 语义；跨章节重复 ep ID 分别用原始／展示分组内索引，不能假设全季唯一。倒序转换位置不复制全部剧集，刷新同 ID 的新 season 仍重新定位。

J：5000 集重复分组＋复制倒序 P50／P95 为 0.100／0.144 ms，缓存查询＋倒序位置计算为 0.006／0.007 ms。首次 domain＋完整索引为 2.825／5.545 ms，普通 domain 映射为 0.104／0.152 ms，增加一次性构造与存储以换取复用。测试覆盖 hover 不替换剧集 ListView、5000 集倒序／网格选中项可见、同 ID 改组刷新及连续播放顺序。

### G4：大响应移出调用 isolate

UTF-8、JSON 和 DTO 解析作为纯函数一起迁移；小于 512 KiB 保持同步。大响应使用 TransferableTypedData＋Isolate.run，与弹幕共享 2 个运行／4 个等待配额。取消／deadline／账号代次变化丢弃结果，正在运行的任务须实际结束才归还名额。原 HTTP 鉴权、重试、错误分类保留；传输和纯 decoder 都检查 4 MiB，最多 5000 集、30 附加章节、100 系列。领域映射仍在调用 isolate，索引惰性构造。

J：预热 10 次、采样 40 次；JSON＋DTO P50／P95（ms）：

| 合成集数／字节 | 同步 | worker 总延迟 |
| --- | --- | --- |
| 12 / 2858 | 0.071 / 0.240 | 0.305 / 0.532 |
| 1275 / 302754 | 3.592 / 5.627 | 5.538 / 7.571 |
| 5000 / 1196754 | 16.138 / 21.950 | 25.793 / 30.364 |

worker 含传递、spawn、返回，**总延迟更慢**；改动移走的是调用 isolate 的大块同步工作，不是已证实的总加载加速。512 KiB 是保守工程门槛，尚未经三端实机验证。响应字节上限不等于 JSON／DTO 对象 heap 上限；同进程 RSS 混合 JIT、fixture、GC，不用于证明内存收益。

### G5：有界缓存与独立取消

每个 Repository 只保留当前 scope／epoch 的最多 8 季、2 分钟 TTL 和最多 8 个在途读取，ep→season 索引随季淘汰。相同 key 单飞；一个消费者取消不影响其他消费者，最后一个取消才停止底层请求。账号 lifetime 结束立即清理；显式刷新绕过旧缓存与 flight，旧响应不能再填回缓存。首次自动加载允许命中，用户刷新保持强制读取，同页切集仍不重新取详情。

C：实际 repository＋fake 5000 集响应对照旧基线：ep 首开→同季 ss 新标签→已知 ep 的详情请求 3→1；随后显式刷新累计 4→2；新 epoch 四个并发同季读取 4→1。未测真实命中率，未把 playurl 或 native 首帧包括在收益中；冷启动仍需详情完成后解析播放 URL。

## 5. 直播

### L3：缓存纯内容并保持窗口锚点

`LiveChatContent` 只保存文本／图片描述，按完整表情映射判断语义一致；同位置 token 仍优先较长者，大表情与未知文本语义保留。缓存最多 500 项，随聊天保留窗口淘汰，不缓存 BuildContext。未变消息行复用 Widget，主题／缩放等 inherited 依赖仍正常响应。

列表提供 ID→index 映射和稳定 key。非跟随、非拖动时，淘汰前记录仍存活的首个可见消息相对 viewport 的位置，布局后作一次有界偏移修正；保留跟随／用户手势优先。review 将绝对屏幕坐标改为相对 viewport，避免布局整体移动污染修正值。500 条满窗追加一条测试确认原可见 Element 和屏幕位置（±1px）保持。

C：500 条消息，分别使用 0／3／50 个表情 token，重复处理 20 次，旧解析调用 10000 次，新缓存首次 500 次后额外解析 0，复用 10000 次，保留 500 项。这里测的是重复内容；新消息及内容／表情元数据变化仍会解析。没有用未预热的单次 CLI 时间作帧耗时结论。

### L4：静默后台对账

周期仍为 20 秒，后台读取不切换 loading；数据语义相同则复用原消息对象和列表，不发布新状态。真实变化、错误清除和手动刷新仍可见；相同背景错误不重复通知。单飞由真实在途 cancellation 标记管理，手动刷新遇到背景请求时复用读取并显示反馈。HTTP／WS 顺序、SC 删除 tombstone、绝对到期语义不变。

C：旧／新生产 LiveController、500 条聊天＋100 条 SC、fake clock 连续 20 次周期对账，通知 80→0，聊天列表替换 20→0，SC 列表替换 20→0。手动刷新仍产生开始／完成反馈；变化和错误恢复另有行为测试。

SC 卡片仅在绝对到期时间、时钟或 TickerMode 状态变化时重设计时器，无关价格／文本更新不推迟下一秒。5 秒倒计时每 200 ms 无关重建，首个 1000 ms 仍显示 4 秒；隐藏／恢复和过期删除继续沿用原边界。

## 6. 统一 review 与验证

交叉 review 已修复：嵌套 workspace 的频道订阅作用域、重复 ep ID 的分组顺序、准备期间开启续播的本地读取、直播滚动锚点的相对坐标。新增回归覆盖消费者取消、账号切换、缓存 TTL／刷新、worker 排队、source generation、评论详情回退和隐藏状态；不使用真实账号写操作。

最终 `tool/check.ps1 -SkipPub` 通过：根应用与四个包格式检查、静态分析无问题，Android 版本 34 项／签名边界 21 项、Windows 安装器 14 项、macOS 发布约束 22 项脚本检查通过（均不等于对应平台构建或安装实测）。首次检查发现 7 项 lint，修正后完整重跑通过。

| 测试集合 | 最终结果 |
| --- | --- |
| 根应用 | 1801 通过 |
| bili_api | 388 通过 |
| bili_player | 35 通过 |
| bili_danmaku | 86 通过 |
| bili_mux | 2 通过，7 项原生测试因未设置 BILI_MUX_LIBRARY 跳过 |
| 合计 | 2312 通过，7 跳过 |

最终直播／评论／详情回退定向集成另有 138 项通过，已包含在根应用集合，不重复累加。连接复用、隐藏频道、启动并行、字幕索引、影视 worker／请求数、直播对账及 DPR 探针分别用于本报告相应结构或 JIT 结论，不加入全仓测试总数。6 份本轮文档共 279 个本地链接目标检查通过；`git diff --check` 通过。

Windows x64 本机运行以下两项集成文件，Debug 构建成功、退出码为 0：

- `flutter test --no-pub integration_test/windows_playback_test.dart -d windows`：框架报告 8 项通过。其中 1 项在线 UGC smoke 因未开启 BILI_ONLINE_SMOKE 直接返回，实际执行 7 项本地测试，覆盖原生 DASH 分轨、headers／Range／重定向、seek、续播、倍速、多标签、全屏／布局和生命周期，以及独立安全存储 probe。
- `flutter test --no-pub integration_test/windows_playback_startup_test.dart -d windows`：4 项通过，覆盖音轨阻塞期间 stop、replace、dispose、timeout 及迟到事件隔离。

构建出现既有 inappwebview 的 CMake CMP0175 开发警告，未阻断构建／测试。这些是 Windows 原生功能回归，没有测 Profile／Release 帧率或证明启动提速；没有重新执行预览缓冲／长缓冲脚本、在线 UGC smoke、Android／macOS 原生测试或发布包构建。最终集成保留并行已提交的 `fecdf23` 评论按钮／视频菜单提示调整，并在该 HEAD 上复跑全仓检查；该提示调整不属于本轮性能提交。

原始探针、JSON、日志保存在忽略目录 `artifacts/performance-p2-2026-10-11/`，不作为发布文件。可重复的边界行为测试纳入根应用与相关包 test。

## 7. 后续实机验收

本轮没有 Android／macOS 实机配对数据，也没有真实 CDN 图片收益、真实账号长季、稳定网络冷启动首帧、高 DPR 视频同播 FrameTiming 或分阶段 heap 测量。以下工作继续保留：

1. F6 先分离详情、playurl、native 创建、prepare 和首帧，并验证 URL 过期／账号边界，再决定媒体缓存或实例预热。
2. V7 在各平台真实高 DPR 同播下记录回退比例、UI／raster P95/P99 和 GPU／进程内存，再选择分块或效果策略。
3. G4 用真实脱敏长季在 Profile／Release 比较主 isolate 阻塞、总延迟和 heap 峰值，校准 512 KiB 门槛。
4. F3／F4、V4 和 G5 记录真实 CDN 连接／排队、长时间分页内存、冷／热打开和缓存命中率；以上结构收益不能代替这些指标。
