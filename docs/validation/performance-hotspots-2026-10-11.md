# 首页推荐与三类播放的性能热点调查

日期：2026-10-11。源码基线：`484bb03b98a1d3665a93c17cb2af4efd3a571b6f`。本次仅分析、运行离线探针及编写文档，不修改业务实现。

## 1. 结论与证据边界

优先减少三类确定存在的额外工作：图片显示等待串行磁盘维护；直播无关事件复制列表并通知整页；视频／影视局部操作重复应用播放设置并整理弹幕。影视系列列表的全量挂载也是明确的结构热点。首帧网络、原生播放器创建和多实例资源开销需要分阶段采样后决定优化力度。

本次以三个 Astra xhigh 子代理分别检查首页推荐、普通视频／共享播放链路、影视，主代理检查直播并交叉核对公共路径。结论依据当前源码，不把历史已修复问题当作新增问题。

证据分为四类：

| 标记 | 含义 | 能证明什么 |
| --- | --- | --- |
| S | 当前源码及调用链 | 工作确实会发生、复杂度与容量边界；不能证明用户已经掉帧 |
| C | 本轮受控结构计数 | 固定输入下通知、构建、扫描或资源等待次数；不是帧耗时 |
| J | 本轮 Dart CLI JIT 微基准 | 合成 CPU 路径的规模趋势；不能换算 Flutter Profile 帧耗时 |
| H | 仓库前序 Profile／结构记录 | 仅适用于原记录的输入、平台、版本和排除项；本轮未重新采样 |

下文 P1 表示优先实施有明确收益的局部修复；P2 表示先补指定测量，再决定实现或参数。它们是优化顺序，不是线上故障严重等级。没有足够证据判断这些热点在真实设备上的占比，也不承诺固定的首帧或帧率提升。

## 2. 首页推荐

主链路是 `FeedScreen → FeedController → ApiFeedRepository → getRecommended → SliverVideoGrid → VideoCardCover → AppNetworkImage → AppImageProvider → ImageByteCache`。列表结构已经虚拟化，当前更值得先查图片交付和长时间浏览的数据成本。

### F1：每张图片等待写盘与全目录清理，且继续占用下载槽（P1，S/C）

位置：[ImageByteCache 加载](../../lib/core/storage/image_byte_cache.dart#L275) 275–330 行、[清理与磁盘队列](../../lib/core/storage/image_byte_cache.dart#L342) 342–384 行、[图片解码入口](../../lib/core/presentation/app_image_provider.dart#L165)。

下载完成后仍需等待串行磁盘队列：SHA-256、写临时文件、flush／close、rename、mtime、`_prune()`，之后才返回字节供解码。6 个传输名额直到整个过程结束才释放。每写一张图都递归列举整个缓存目录、逐文件 stat、排序和淘汰；磁盘命中读也共用该队列。异步文件 I/O 不等于同步堵塞 UI，但这里确实延迟了图片交付，摘要与排序另有调用 isolate 上的 CPU 成本。

本轮纯 Dart 结构探针得到：

| 受控输入 | 结果 |
| --- | --- |
| 512 个种子缓存文件，再下载 20 张 fake 图片 | 21 次全目录扫描，10,772 个文件遍历／stat 调度 |
| 7 个请求，人为阻塞磁盘目录回调 | 6 个 loader 已返回，但调用方完成数为 0，第 7 个 loader 尚未开始 |
| 解除磁盘阻塞 | 7 个 loader 和调用方均完成 |

这证明磁盘维护处于解码前关键路径且占传输槽，不代表实盘有同样的阻塞时长。

方案：下载成功后交付字节并释放传输名额；可选持久化进入独立、有任务数和字节上限的后台队列，满时可放弃缓存写入。启动扫描建立大小／LRU 索引，写入增量维护，越界或合并批次后清理。保留账号代次、缓存开关、原子写入、损坏校验及关闭时排空；不能以无界后台写入换首屏速度。

验收：同一批新图不再每图全扫；阻塞可选持久化不阻塞下载字节交付或第 7 个网络任务；记录 download-end→decode-start P50/P95、磁盘队列等待和实际缓存容量，仍满足 64 MiB／512 文件配额。

### F2：离屏不取消已接纳图片任务，当前视口与旧任务共享 FIFO（P1，S）

位置：[AppNetworkImage 离屏处理](../../lib/shared/ui/app_network_image.dart#L190)、[图像流释放](../../lib/shared/ui/app_network_image.dart#L447)、[AppImageProvider._codec](../../lib/core/presentation/app_image_provider.dart#L160)、[字节任务入口](../../lib/core/storage/image_byte_cache.dart#L198)与[等待队列](../../lib/core/storage/image_byte_cache.dart#L387)。

离屏会停止容量等待、释放图像流保活句柄，但没有消费者取消信息传到字节任务。一旦接纳，任务可能继续下载、写盘和解码。当前 6 并发、最多 64 个已接纳任务按 FIFO 服务；慢网中多个短暂停留的视口可能让旧请求排在新可见图片之前。已有快速滚动延期，因此这里只针对已接纳任务，不是所有经过的图片都会请求。

方案：共享 URL 任务增加消费者租约与可见／预取优先级；零消费者排队项立即移除，运行项按短宽限期／完成程度决定取消，取消后不再发起解码。只有最后一个消费者离开才取消，保留 URL 单飞、已解码首帧和返回滚动时的图片稳定性。

验收：6 个慢请求加新视口场景，测无消费者任务数、浪费字节、可见图片排队 P95；同 URL 双消费者不得互相取消。账号切换、关闭缓存、取消与真实失败的处理仍区分。真实流量收益尚待测量。

### F3：每张图独占 HttpClient，连接不能跨图片复用（P2，S）

位置：[loadPublicImage](../../lib/core/storage/image_byte_cache.dart#L49) 49–102 行。

每次创建 `HttpClient`，结束时 `close(force: true)`。这是为单图取消建立的所有权边界，同时失去了同 CDN 跨图片连接复用。不能推断每张图必然完整重做 DNS／TLS，系统缓存和会话恢复的效果没有测量。

方案：先完善 F2 的请求级取消，再让图片传输服务持有有限连接数的公共图片 client；取消只 abort 该请求／响应订阅，不能关闭其他图片的连接。继续禁止 Cookie／Authorization，保留重定向来源校验、TLS 验证和服务关闭释放。

验收：两批同 host 图片测连接建立数、connect／TLS／TTFB、首屏完成时间；确认单图取消不影响其他图，并发预算不扩大。真实网络对照有收益再实施。

### F4：分页合并及频道保留的数据成本随浏览增长（P2，S）

位置：[FeedController 保存频道](../../lib/features/feed/application/feed_controller.dart#L95)、[分页与合并](../../lib/features/feed/application/feed_controller.dart#L322) 322–365 行、[推荐请求](../../packages/bili_api/lib/src/api_client.dart#L740)。

推荐每页 20 条，非空可继续分页；连续两页没有新增才暂停自动加载，没有最大保留条目数。每页 `_mergeItems` 对全部已有条目建立 Map，再生成完整不可变列表，单次 O(N+20)，长期连续翻页的累计复制量近似随页数平方增长。已访问视频频道还保留自己的完整领域列表。Sliver 只减少挂载组件，不减少这些模型或分页分配。

方案：先测 20／500／2,000／10,000 条的合并和 retained heap。若确需限制，定义明确的推荐浏览容量，到上限停止追加并提供刷新入口，避免静默删除旧数据破坏回滚。长列表确有需求时考虑分块快照／增量 ID 索引；数据语义不变时复用列表身份，服务端对旧条目的真实更新仍传播。稍后再看等完整播放队列不随推荐优化被截断。

验收：长时间浏览内存与单次分页成本满足明确预算；去重替换、反馈、旧位置返回、刷新及账号取消正确。容量策略属于需要明确的产品行为，不能在性能修复中悄悄改变。

### F5：全局 FeedState 通知所有已访问频道外壳（P2，S）

位置：[频道订阅](../../lib/features/feed/presentation/feed_screen.dart#L313)、[stateForChannel](../../lib/features/feed/application/feed_controller.dart#L104)、[内容与版本](../../lib/features/feed/presentation/feed_screen.dart#L213)、[分页检查](../../lib/shared/ui/paged_scroll_viewport.dart#L57)、[页面保留](../../lib/shared/ui/retained_tab_view.dart#L301)。

每个已保留 `_HomeChannelPage` 都 watch 同一 provider，连使用 HomeContent 的非视频频道外壳也会收到通知。`stateForChannel()` 派生新 FeedState／反馈 Set，`contentVersion` 身份变化又引起后帧分页检查。访问全部 12 个频道后，一次推荐更新可能波及全部频道外壳。既有网格／行委托缓存仍保护多数卡片，不能说它又全量重建所有卡片。

方案：提供稳定的按频道状态／选择器，非视频频道不订阅无关视频状态；分页版本依据实际查询／数据版本及必要尾部状态，反馈集合只在变化时重建。保留隐藏页面的滚动状态和图片帧。

验收：访问全部频道后推荐 loadingMore／完成时，未变化隐藏频道 build 和分页检查为 0；当前仅尾部状态变化仍不重建卡片。此处本轮只有调用链证据，正式修改前补构建计数。

### F6：重复悬停仍重新解析媒体并创建原生预览（P2，S/H）

位置：[VideoCardCover](../../lib/shared/ui/video_card_cover.dart#L82)、[VideoCardController](../../lib/features/video/application/video_card_controller.dart#L111)、[预览解析](../../lib/features/playback/data/api_video_preview_repository.dart#L22)、[预览打开／释放](../../lib/features/video/application/video_card_preview_playback.dart#L45)。

有效悬停 200 ms 后每次 resolve；仅首 P 元数据有最多 24 条缓存，媒体解析结果没有复用。退出即取消、stop／dispose，下次重新建 engine。它是主动释放策略，不是泄漏。[前序 Windows 本地素材记录](video-preview-contention.md)在修复同步尺寸查询后仍记录 open 103–120 ms、主视频最大 render gap 52 ms；不能当作本轮真实 CDN 的结果。

方案：先分别记录 hover delay、resolve、release wait、engine create、open、first texture。解析占主导才做账号／设置隔离、短时、有容量的内存复用；`PlaybackMedia` 尚无 expiry，必须先定义可靠失效策略。原生创建占主导再评估单个 warm engine 和短闲置期限，不直接建设播放器池。

验收：A→B→A 及 20 次往返的请求数、创建／释放数、悬停到首纹理 P95、主视频 render gap P99/max、CPU／GPU／内存；保留单 active engine、5 秒预读、滚动／离屏取消、串行释放及过期 URL 处理。Flutter FrameTiming 不能独自证明 native 视频没有停顿。

## 3. 视频播放与共用播放路径

### V1：每种播放快照都重建整个播放器内部子树（P1，S/C；三类播放共用）

位置：[native 快照发布](../../packages/bili_player/lib/src/media_kit_engine.dart#L680)、[Session 转发](../../lib/features/playback/application/playback_session.dart#L689)、[PlaybackPanel 内部 ValueListenableBuilder](../../lib/features/playback/presentation/playback_panel.dart#L816)。

position、duration、buffer 等变化分别创建快照；没有值相等过滤。视图以整个 snapshot 重建 VideoSurface、弹幕层、手势、字幕、时间轴和控件的 Stack。已有控件尺寸缓存只减少文字测量，没有缩小订阅范围。

本轮使用真实 PlaybackPanel、fake engine／repository、暂停状态、可见控件，1280×900、DPR 1、播放器宽 1200。每类注入 20 个事件，每事件后 pump 16 ms：

| 输入 | element 重建通知 | VideoSurface／DanmakuOverlay／ControlBar | 父 PlaybackPanel／PlayerView | 新增 engine.open |
| --- | ---: | ---: | ---: | ---: |
| position 改变 | 7,300 | 各 20 | 各 0 | 0 |
| 仅 buffered 改变 | 7,300 | 各 20 | 各 0 | 0 |
| 字段全部相同的新快照对象 | 7,300 | 各 20 | 各 0 | 0 |

最大挂载 surface 为 1。这证明内部重建范围过大，不代表产生新 native engine，也不证明生产每秒有多少事件或多少毫秒损失。重建计数不包含所有 layout／paint 开销。

方案：确认位置继续及时交给弹幕时钟；稳定画面和手势子树，进度、buffer、按钮、音量、字幕按所需字段分别订阅；相同快照去重。只节制展示更新，不能将整个播放时钟粗暴降频。控制条隐藏时进一步停掉不需要的 UI 订阅，但保留必要的折叠进度。

验收：纯 position／buffer 更新不重建画面、弹幕 Widget 和设置／手势子树；字段相同快照无 UI 更新；暂停、seek、完播即时生效；Profile 同时检查 UI／raster 和 native 出帧间隔。

### V2：点播弹幕窗口重复全量整理，无变化设置会额外触发（P1，S；视频／影视共用）

位置：[分段与窗口触发](../../lib/features/playback/application/playback_session.dart#L1120)、[分段返回](../../lib/features/playback/application/playback_session.dart#L1180)、[窗口整理](../../lib/features/playback/application/playback_session.dart#L1201)、[控制器替换](../../packages/bili_danmaku/lib/src/danmaku_controller.dart#L229)。

最多前／当前／后三段、各 6000 条，窗口变化时先展平并全排序最多 18,000 条，再筛历史区间与未来 60 秒、屏蔽词／密度并生成渲染事件，控制器又排序和维护 ID 后限制待处理项。每 15 秒窗口变化、分段返回、seek 和配置应用均可能触发。历史长度至少 16 秒，倍速／活动寿命可要求更长，不能固定按 76 秒截断。

额外触发链为 [VideoScreen 简介 setState](../../lib/features/video/presentation/video_screen.dart#L268) → playerBuilder → [PlaybackPanel.didUpdateWidget](../../lib/features/playback/presentation/playback_panel.dart#L184) 无条件 `_configure()` → [configureSettings](../../lib/features/playback/application/playback_session.dart#L973) 无条件 `_refreshCommentWindow()`。PGC 的 G2 也进入该链。V1 的内部快照 builder 不会触发父 Panel 的 didUpdateWidget，不能说每次 position 都在排序 18,000 条。

方案：先按相关设置差异决定刷新；分段各排序一次，以二分切片和有限合并获取时间窗，分开管理分段 revision 与过滤配置 revision，合并同一轮分段返回的重复刷新。保留权威窗口对活动项的身份校验，不提前截成 500 条而使仍在屏幕中的弹幕再次消失。

验收：简介／侧栏切换且设置相同时刷新次数为 0；以 1／3×6000、同秒密集事件、关键词和多倍速测整理耗时 P50/P95/max 与分配量。保留 seek、过滤删除、活动寿命、500 待处理／120 活动／每帧 32 项准备上限。[此前 0.130 ms 的窗口替换记录](danmaku-performance.md)直接测控制器 500 条，不覆盖本应用层整理。

### V3：隐藏播放标签仍获取、整理弹幕并保留绘制缓存（P1，S；视频／影视共用）

位置：[deactivate](../../lib/features/playback/application/playback_session.dart#L351)、[快照后台处理](../../lib/features/playback/application/playback_session.dart#L701)、[_ensureComments](../../lib/features/playback/application/playback_session.dart#L1120)、[隐藏视图](../../lib/features/playback/presentation/playback_panel.dart#L737)、[绘制缓存预算](../../packages/bili_danmaku/lib/src/danmaku_text_style.dart#L31)、[PlaybackManager](../../lib/features/playback/application/playback_manager.dart#L25)。

允许并发播放时，隐藏标签继续播放是预期行为；当前 `_ownerVisible` 不参与弹幕预取与窗口更新判断，隐藏时仍随确认位置跨段获取、每 15 秒整理。Overlay 被移除不等于 Session 的 DanmakuController 被销毁，已生成图像也可继续驻留。

每控制器的图像像素预算为 32 MiB、布局上限 256；每播放标签还有独立 native 资源。工作区最多 16 页并不等于存在进程级媒体内存预算。不能把单实例预算乘标签数写成实测 RSS 或 GPU 占用。

方案：媒体播放许可与弹幕呈现可见性分别管理；不可见时暂停纯展示预取和窗口整理，恢复时按确认位置补窗。提供隐藏会话可重建图像缓存的回收点，继续保留音频、进度、账号与播放意图；全屏仍是可见呈现，不能误停其弹幕。测 1／4／8 标签后再确定共享资源预算。

验收：隐藏且继续播放的标签不持续拉取或整理不可见弹幕；音频和进度保持；恢复没有旧弹幕重播、异常缺窗或重复 engine。记录 CPU、网络、图像估算字节、RSS／GPU、关闭后的释放，不通过禁止多标签播放达标。

### V4：换源释放、解析、续播和 native 准备串行执行（P2，S/H；先补阶段测量）

位置：[PlaybackSession.open](../../lib/features/playback/application/playback_session.dart#L439) 439–545 行、[本地续播](../../lib/features/playback/application/playback_session.dart#L824)、[MediaKitEngine.open](../../packages/bili_player/lib/src/media_kit_engine.dart#L349)、[释放](../../packages/bili_player/lib/src/media_kit_engine.dart#L772)。

详情之后的主要路径为：旧进度保存 → engine.stop／旧 native 释放 → playurl resolve → 必要的本地续播读取 → 新 mk.Player／VideoController → 缓冲配置 → 视频／外部音轨准备 → rate／volume／seek → play 和真实音频确认。已有显式 position 的换源会跳过续播读取；直播无点播续播。包装层 Session／Engine 保留，但每次 open 都重新创建底层 native player。

[前序启动调查](playback-startup.md)包含 audio-files 路径的实际游客 open 479–1343 ms；这是该记录的环境和测量边界，不是当前全部页面首帧，不能归因为纯 CPU 或固定网络成本。

方案：先测旧源释放、resolve、本地读、native 配置、轨道准备、音频确认和首纹理；确认独立后，在 generation／账号隔离下重叠网络解析、旧源释放与可提前确定的本地读取。后端复用只在测出收益后做受控原型，彻底重置 headers、audio-files、解码偏好与失败状态。

验收：冷／暖打开、换 P／清晰度／语音、故障 CDN 的阶段 P50/P95、取消和释放尾延迟。保留单音频、源隔离及当前普通播放预读语义。有不同备用地址的点播，首地址最多 8 秒、两次 native open 共用 35 秒预算；单地址点播及直播保持既有预算。API 解析和后续 play 音频确认不包含在该 35 秒内；不能删除音轨确认或使用双播放器预热来掩盖问题。

注意：普通 DASH 的 `openReady` 在真正 play 前发出；预览分支才显式等待 `waitUntilFirstFrameRendered`。优化验收必须独立记录首纹理／可见首帧，不能把 openReady 当作首帧。观测首帧不要求阻塞正常播放流程。

### V5：每种快照都从头线性查找字幕（P2，S；视频／影视共用）

位置：[字幕查找](../../lib/features/playback/presentation/playback_panel.dart#L824)、[字幕加载](../../lib/features/playback/application/playback_session.dart#L1425)、[API cue 映射](../../packages/bili_api/lib/src/api_client.dart#L1211)。

`where(...).firstOrNull` 每次从头扫描，长字幕后半段或无字幕间隙可扫描大部分乃至全部 cue；buffer 等无关事件也执行。当前保留 API 顺序，没有已排序／互不重叠的强契约。

方案：独立订阅位置，用顺播游标与 seek 索引，只在当前 cue／样式／避让变化时重建字幕。建立索引前定义乱序／重叠兼容规则，保留现有“原顺序第一个匹配”语义，不能简单排序后二分导致显示改变。

验收：500／5000／20,000 cues 的顺播、正反 seek、间隙、重叠比较结果和查找次数；纯 buffer 更新不查字幕。真实长字幕 CPU 占比仍待 Profile。

### V6：评论状态变化预创建全部已加载条目的 Widget（P2，S；视频／影视共用）

位置：[CommentsPanel 状态](../../lib/shared/ui/comments_panel.dart#L174)、[entry 工厂](../../lib/shared/ui/comments_panel.dart#L206)、[ListView.children](../../lib/shared/ui/comments_panel.dart#L298)、[评论容量](../../lib/features/comments/application/comments_controller.dart#L161)。

翻页 loading／结果、回复目标和动作 busy 变化都会 `...comments.map(entry)`，最多 500 条的 Widget／回调闭包重新分配。ListView 仍懒挂载与布局，不能说 500 条富评论都已绘制；[正文解析已有内容变化缓存](../../lib/shared/ui/comment_rich_content.dart#L60)。

方案：builder／sliver builder、稳定评论 key，header／composer 与条目集合分开订阅，行内动作只更新相关行，同时保留全局写入约束。用分配和可见行构建计数评估收益。

验收：500 条含回复预览／表情／图片的评论，切回复目标和分页 loading 不创建可见区域之外的 entry；保持位置、回复返回、busy 及未知写结果不重放。

### V7：高 DPR／长文本可能触发弹幕图像缓存回退（P2，S/H；三类播放共用）

位置：[DanmakuTextLayouts 图像准备](../../packages/bili_danmaku/lib/src/danmaku_text_style.dart#L141)与[直接绘制回退](../../packages/bili_danmaku/lib/src/danmaku_text_style.dart#L191)。

同一逻辑文字的图像像素占用约随 DPR² 增长，预算仍固定为每控制器 32 MiB；单图任一维超过 4096 或活动工作集占满预算时，溢出项直接绘制。当前保护活动图像的策略正确避免循环淘汰，但阴影可能重新进入逐帧 raster 路径。[既有性能对照](danmaku-performance.md)主要为 DPR 1、无视频解码，并不覆盖此条件。

方案：先统计缓存命中、回退原因和直接绘制项帧数；DPR 1／2／3、长短文本及 native 视频共同测量。达到预算外才评估分块图像、分摊准备或明确的密度／效果降级，不直接扩大每会话上限。

验收：UI／raster P95/P99、超过设备刷新预算的帧、可见数量与寿命、图片峰值和回退比例一起报告。此项是条件热点，尚未复现高 DPI 真机卡顿。

## 4. 影视播放

影视共用第 3 节播放会话和控件，以下只列 PGC 特有的入口和放大条件。

### G1：系列作品仍全量挂载（P1，S/H）

位置：[PgcScreen 简介](../../lib/features/pgc/presentation/pgc_screen.dart#L270)、[系列循环](../../lib/features/pgc/presentation/pgc_screen.dart#L539)、[PGC 解析容量](../../packages/bili_api/lib/src/clients/pgc_client.dart#L45)。

简介为 `SingleChildScrollView → Column`，系列最多 100 条由 for 全量创建封面。可见性门控减少下载，却不能免除全部组件、布局、监听器和滚动检查。[前序结构／Profile 调查](pgc-page-performance-scroll.md)的 5000 集／100 系列样本只挂载 6 个选集条目，却挂载 100 个系列封面；外层滚动约 100 次图片检查。独立 Windows Profile 三次打开最慢 UI 帧：5000／0 为 2.02–2.14 ms，5000／100 为 5.75–11.27 ms，390 宽样本为 5.61–14.43 ms；没有超过 16.67 ms 的采样帧。

方案：简介使用 CustomScrollView，标题／简介／有界选集用 SliverToBoxAdapter，系列用 SliverList.builder 和稳定 key。选集保持固定高度、自己的控制器和懒加载，不能为简化外层滚动全量挂载数千集。

验收：12／1275／5000 集 × 0／20／100 系列、390／1200 宽度，系列挂载数及图片检查随视口而非总数增长；保留选集位置和触摸边界衔接。前序数字是 H，未覆盖 native、弹幕或真实账号，不能宣称证明真实影视播放卡顿。

### G2：简介操作重建整页，并触发共享播放配置链（P1，S/H）

位置：[简介展开](../../lib/features/pgc/presentation/pgc_screen.dart#L507)、[信息 tab](../../lib/features/pgc/presentation/pgc_screen.dart#L248)、[侧栏开关](../../lib/features/pgc/presentation/pgc_screen.dart#L195)、[播放器 builder](../../lib/features/pgc/presentation/pgc_screen.dart#L214)。

这些局部状态保存在 PgcScreen，变化时重新计算选集／相邻集、创建播放器和系列子树。前序 100 系列探针展开简介触发 100 次图片检查、1 次 playerBuilder。真实播放器再沿 `PlaybackPanel.didUpdateWidget → configureSettings → _refreshCommentWindow` 放大为共享弹幕整理，见 V2。前序探针使用空播放器，并没有测这条放大链的耗时。

方案：简介展开状态下沉到局部组件；稳定播放器、选集数据和系列委托，同时修复 V2 的无变化设置重应用。仅减少页面 build 不是共享配置层的完整修复。

验收：100 系列＋3×6000 合成弹幕时，简介展开不应用播放器设置、不重建弹幕窗口；真正切集、字号／屏蔽词／密度变化仍生效。检查 engine open 始终不随简介变化增加；当前代码本来就保留 engine，不将此当作修复前的缺陷。

### G3：每次 build 重分组、拷贝、倒序和线性查找长季数据（P2，S/H）

位置：[PgcEpisodePanel.build](../../lib/features/pgc/presentation/pgc_episode_panel.dart#L101)、[悬停状态](../../lib/features/pgc/presentation/pgc_episode_panel.dart#L168)、[episode 检索](../../lib/features/pgc/domain/pgc_repository.dart#L119)、[相邻剧集](../../lib/features/pgc/domain/pgc_playback_sequence.dart#L10)。

最多 5000 集在每次 build 重新分组、复制当前组、按需倒序、查当前集；分组悬停、列表／网格切换和父级重建都会进入此路径。页面 hasNext 还重新筛选相邻集分组。前序排序操作 UI P95 约 1.46–2.19 ms，没有单独证明其造成卡顿。

方案：以不可变 episodes 身份／资料版本缓存分组、ID 和组内位置索引；倒序用索引映射；悬停只更新局部。若 controller、sequence 和 panel 共用索引，应明确一个所有者及失效点，避免维护三套缓存。

验收：悬停、简介展开不重新分组；排序不复制全部模型；资料刷新、正片／SP、权限集停止点、选中居中正确。可随 G1/G2 拆分完成，未测出收益前不扩大抽象层。

### G4：长季响应的 JSON、DTO、领域映射同步执行（P2，S/J；Profile 后决定是否升为 P1）

位置：[API JSON 解码](../../packages/bili_api/lib/src/api_client.dart#L1523)、[PgcClient.getSeason](../../packages/bili_api/lib/src/clients/pgc_client.dart#L29)、[领域映射](../../lib/features/pgc/data/api_pgc_repository.dart#L36)、[不可变列表构造](../../lib/features/pgc/domain/pgc_repository.dart#L107)。

HTTP await 之后直接在调用 isolate 解码 JSON、解析最多 5000 集／100 系列，再分配领域模型和不可变列表。异步 HTTP 不会让这些 CPU 工作自动并行。

本轮调用实际 `PgcClient.getSeason`，fake transport 返回预生成 JSON。Windows Dart 3.13.5 CLI JIT，每组预热 10 次、采样 40 次：

| 集数 | JSON 字节 | getSeason 中位／P95（ms） | 仅 UTF-8＋JSON 中位／P95（ms） |
| ---: | ---: | ---: | ---: |
| 12 | 2,858 | 0.184／0.424 | 0.081／0.186 |
| 1275 | 302,754 | 3.351／5.660 | 2.166／4.467 |
| 5000 | 1,196,754 | 19.197／21.922 | 8.369／8.863 |

这些是合成 CPU 微基准，包含 API 调用与 DTO 解析，不含 repository 领域映射、HTTP、账号或 Flutter 帧；19.197 ms 不能写成真实 UI 卡顿时长。

方案：先在 Flutter Profile 分段计时 UTF-8／JSON、DTO、领域映射；超过阈值的大响应将 JSON＋纯解析批量交给有界 isolate，小响应仍本地执行。优先传 bytes 并返回精简不可变数据，测跨 isolate 复制和峰值内存。保留账号 scope／epoch、generation、取消、deadline、非法字段和容量规则。

验收：上述规模加真实脱敏长季响应，比较 UI 同步任务耗时、总延迟、分配／峰值内存；取消后结果不回写。只移走 jsonDecode 而留下全部 DTO 整理可能不足，也不能无条件让所有小响应启动新 isolate。

### G5：完整季详情在首播 URL 请求之前（P2，S）

位置：[PgcController.load](../../lib/features/pgc/application/pgc_controller.dart#L93)、[页面 loading 分支](../../lib/features/pgc/presentation/pgc_screen.dart#L178)、[PGC 媒体解析](../../lib/features/playback/data/api_content_playback_repository.dart#L38)。

详情完成、选出 episode 后才创建播放器并请求 playurl；ep 直链没有较短准备路径，跨标签重复打开也没有季详情缓存／同请求合并。一般同页切集只更新选择，不重新请求完整详情，不能将该成本归于每次切集。

方案：先测导航→详情等待／解析→playurl→续播→native 首帧。重复打开占比高时做有容量、TTL、账号隔离的季详情缓存及 episode→season 索引，显式刷新绕过。已知 ep 的 playurl 并行准备最后评估，仍须校验权限、身份和 generation；不提前创建第二个 engine，不因预取扩大无用请求。

验收：ep／ss 首次打开、同季新标签、同页／快速切集、账号切换分别记录详情与 playurl 请求数和首帧；缓存不能复用旧账号权益。

## 5. 直播播放

### L1：每个实时批次都复制聊天／SC 窗口，忽略事件也发布状态（P1，S/C）

位置：[LiveController._acceptRealtime](../../lib/features/live/application/live_controller.dart#L569)，重点为 571–576、622–625、654–683 行；[LiveChatSession](../../packages/bili_api/lib/src/live/live_chat_session.dart#L267)逐个解码包输出事件。

每个批次先把最多 500 条聊天和 100 条 SC 放入新 Map，再转换为新列表和不可变列表。`LivePopularityChanged` 虽在 switch 中忽略，末尾仍无条件赋值 `state`。相同的在看人数和仅连接状态变化也会替换两个未变化的列表，并取消／重新创建 SC 到期计时器。输入解压已在独立 isolate，但这些合并、复制及通知发生在应用侧。

方案：按事件类型延迟创建需要修改的集合，保留未变化列表的身份；相同计数、被忽略的人气事件直接结束；只有 SC 集合／最早到期时间变化才重设计时器。批次密集时可进一步将聊天 UI 快照按帧合并，但必须保留有界队列、原始到达时间、SC 删除及离线事件的顺序，不能用延迟批处理改变弹幕寿命或延迟关键状态。

验收：被忽略的事件产生 0 次 state 通知、0 次列表替换；只更新人数时聊天／SC 列表身份保持；新聊天仍保持最近 500 条、SC 100 条、去重、账号 epoch、HTTP 与实时先后关系及到期移除。

### L2：直播页订阅整个 LiveState，消息波及播放器和房间信息（P1，S/C）

位置：[LiveScreen.build](../../lib/features/live/presentation/live_screen.dart#L193) 的完整 `ref.watch`，232–233 行创建播放器与侧栏；[聊天视图](../../lib/features/live/presentation/live_screen.dart#L491)和[SC 视图](../../lib/features/live/presentation/live_screen.dart#L650)。

只要 state 变化，页面就重新调用 `_player`、`_sidebar` 和注入的 `playerBuilder`。已有 GlobalKey 保持播放器 State，不能将此描述成每条消息重新创建 native engine。收起侧栏仍保留树，不能仅靠 Offstage 消除这种构建。

方案：页面只订阅 room／loading／错误等页面字段；房间人数、聊天、SC 分别由局部消费者订阅；以房间身份／开播状态稳定播放器子树。聊天委托只在消息或交互依赖改变时更新，人数变化不更新聊天委托。先实施 L1 再隔离 L2，避免只隐藏 UI 重建却保留所有 reducer 成本。

本轮结构探针使用真实 `LiveScreen`／`LiveController`、fake repository 和空播放器，1280×800，初始 500 条聊天、0 条 SC：

| 输入 | 状态通知 | 聊天列表替换 | SC 列表替换 | playerBuilder 调用 |
| --- | ---: | ---: | ---: | ---: |
| 20 批被忽略的人气事件，每批后 pump 一帧 | 20 | 20 | 20 | 20 |
| 20 批相同在看人数，每批后 pump 一帧 | 20 | 20 | 20 | 20 |
| 20 批新聊天，每批后 pump 一帧 | 20 | 20 | 20 | 20 |
| 20 批被忽略的人气事件后只 pump 一帧 | 20 | 20 | 20 | 1 |

最后一行表明 Flutter 可以合并同帧构建，但应用状态处理不会因此消失。`pump(16 ms)` 是模拟时间推进，不是实测每帧 16 ms。探针没有原生播放、网络、图片或真实账号。

验收：只有聊天／人数变化时 `playerBuilder` 调用为 0；聊天更新不重建不相关房间信息和 SC；换房间、开播状态变化及隐藏／恢复时仍正确更新唯一播放器和消息连接。

### L3：聊天按下标复用条目，富文本在每次 build 重做匹配（P2，S）

位置：[LiveScreen 聊天 itemBuilder](../../lib/features/live/presentation/live_screen.dart#L561) 及 [LiveChatBubble.build](../../lib/features/live/presentation/live_chat_bubble.dart#L49)。

当前已经使用 `ListView.builder`，不会挂载全部 500 条聊天。但条目缺少消息 key，窗口满后每次删除头部会改变后续消息下标。可见元素需要重新绑定消息；每个气泡 build 重新排序最多 50 个表情 token，并反复 `indexOf` 切分内容。L2 的无关重建会重复这些解析。

方案：以稳定去重键保持消息身份，并为列表重排提供索引映射；将文本／表情 token 切分缓存于不可变消息派生结果，缓存受 500 条窗口约束。样式、DPR 和点击回调留在 UI，不能缓存带旧 context 的 Widget。必要时评估以尾部为锚的列表结构，必须保留用户上翻暂停跟随、连接提示位置及 SC 插入行为。

验收：满容量连续追加时记录已有气泡 build、图片重新绑定、文本解析次数；无内容变化不重复分词；用户上翻时可见消息和位置稳定。先用 0／普通表情／50 token 三种 fixture 测量，再决定是否需要复杂匹配算法。

### L4：定期对账和 SC 显示计时存在可合并工作（P2，S）

位置：[20 秒轮询](../../lib/features/live/application/live_controller.dart#L229)、[历史合并](../../lib/features/live/application/live_controller.dart#L380)、[SC 合并](../../lib/features/live/application/live_controller.dart#L444)、[SC 倒计时](../../lib/features/live/presentation/live_super_chat_card.dart#L248)。

实时连接正常时仍每 20 秒读取历史／SC／精确人数。历史和 SC 每次先发布 loading、完成后发布新列表，即使数据相同；人数也缺少显示值相等时的通知抑制。每个已挂载的 SC 倒计时在 `didUpdateWidget` 中取消并重建自己的周期 Timer，页面无关更新会放大重设工作。

方案：对账保留正确性职责，后台刷新无变化时复用列表、抑制状态通知；人工刷新继续显示明确状态。只有到期时间／clock／启用状态变化才重设倒计时，或在实测 Timer 数量有成本时共用可见 SC 的秒时钟。延长历史／SC 轮询须以实时健康度及漏消息恢复验证为前提，精确人数不能直接被截断的 WS 人数替代。

验收：无变化对账不重建播放器／聊天；隐藏页无 Timer 或网络持续工作；SC 依旧按绝对结束时间到期，不因批处理或刷新延长寿命。此项不是“后台无限轮询／全局每秒重建”的缺陷：当前已有 inactive 停止网络、TickerMode 停止显示计时及单次最近到期 Timer。

## 6. 优化顺序与系统边界

建议按下表分批实施，每批独立对照，避免多个改动一起落地后无法归因。

| 顺序 | 工作包 | 涉及热点 | 先验收的确定收益 | 主要约束 |
| --- | --- | --- | --- | --- |
| 1 | 图片交付与维护解耦 | F1，再 F2 | 无每图全扫；可选写盘不占传输槽；可见任务优先 | 后台队列有界、共享消费者取消、账号及磁盘配额 |
| 2 | 直播按变化发布／按字段订阅 | L1、L2，再 L3/L4 | 无关事件零通知；聊天不重建播放器 | SC 顺序、绝对到期、精确人数、聊天跟随 |
| 3 | 共用播放状态与弹幕工作隔离 | V1、V2、V3 | 稳定层零快照重建；相同设置零刷新；隐藏停止展示工作 | 确认时钟、全屏呈现、活动寿命、并发音频和进度 |
| 4 | 影视简介与长季派生数据 | G1、G2，顺带 G3 | 系列按视口挂载；简介操作只更新简介 | 有界选集、资料失效、触摸边界衔接 |
| 5 | 有实测再扩展 | F3–F6、V4–V7、G4/G5 | 连接／CPU／内存／首帧的配对收益 | 不扩大 native 生命周期风险、不改变权限与产品语义 |

架构仍沿用现有所有者：图片队列放在 `core/storage`／`core/presentation` 的图片服务；每个标签保留唯一 PlaybackSession，视图派生订阅不能另建第二套播放状态；PGC 分组索引由不可变资料的一个所有者维护；直播业务合并仍在 LiveController，协议 worker 继续只负责受限解码。无需为了这些热点引入 Rust、全局 service locator 或新的播放器后端。

跨模块收益不可直接相加。例如 G2 与 V2 是同一条放大链，V1 与 V5 的订阅隔离重叠，L1 与 L2 分别降低状态处理和通知后的构建；要分别统计端点次数、同步 CPU 和视图更新。

## 7. 后续测量与验收设计

性能结论使用 Profile／Release 和真实目标设备；widget 探针只计数，CLI JIT 只观察 CPU 规模。按刷新率报告预算：60 Hz 为约 16.67 ms，120 Hz 为约 8.33 ms；UI 与 raster 分开统计 P50/P95/P99、最慢帧和超预算帧比例。还需单独记录 Timer／异步回调里的同步 CPU，因为仅看 buildDuration 会遗漏这些工作。测量方法参考 [Flutter 性能分析](https://docs.flutter.dev/perf/ui-performance)，局部订阅与懒创建原则参考 [Flutter 性能实践](https://docs.flutter.dev/perf/best-practices)。

| 场景 | 输入与操作 | 核心指标 |
| --- | --- | --- |
| 推荐图片 | 空／512 文件缓存；同 host 冷暖；快速滚动、短暂停留、回滚 | 下载、写盘、解码阶段；目录扫描；当前可见队列等待；浪费字节 |
| 推荐长列表 | 20／500／2,000／10,000 条；访问全部频道再分页 | 合并与分配耗时、隐藏频道 build、retained heap |
| 视频／影视稳态 | 控件显隐、字幕 0／500／5000／20,000、1／3 个密集弹幕分段 | 快照与窗口次数、稳定层重建、同步任务 CPU、native 出帧 |
| 页面交互 | 简介展开、信息 tab、侧栏、seek／倍速、键盘／全屏 | 设置应用次数、窗口整理次数、草稿／焦点、唯一 engine |
| 影视长季 | 12／1275／5000 集 × 0／20／100 系列，390／1200 宽 | 解码／映射、分组、挂载、图片检查、首次打开与滚动 |
| 直播 | 0／500 聊天、0／100 SC；重复人数、人气、聊天突发、表情 | reducer／通知／build、SC Timer 重设、跟随位置、到期精度 |
| 多标签 | 1／4／8 个播放标签，隐藏／恢复／关闭 | 每会话与进程 CPU／网络／RSS／GPU、图像预算、释放尾延迟 |
| 首帧与悬停 | 同素材、同清晰度／编码，冷暖打开及故障 CDN；A→B→A 悬停 | 每阶段 P50/P95、首纹理、主视频 render gap P99/max |

控制主题、字体、DPR、视口、内容、编解码、网络与缓存状态；相同设备做前后配对，轮换样本顺序并重复，不同时跑构建和测试污染样本。打开只有少量帧时报告每次最慢帧与各阶段时长，不对三四帧机械计算 P95。Windows 的窄窗口不代替 Android 真机，macOS 的 native 与高 DPI 另验。

首帧诊断仅记录阶段名、耗时、计数、编码和尺寸；不能记录 Cookie、token、签名 URL query、聊天正文或未过滤 native 日志。真实账号仅用于经授权的读取／播放，不用发送、投币等操作做性能采样。

实施后的回归遵循项目规则：纯 Dart 数据／窗口逻辑用 fake clock／transport，生命周期与订阅用 widget fake engine；完成一批后运行 `tool/check.ps1`。如果修改 native 创建、释放、headers 或音轨准备，另外做受影响平台 native 测试、构建和实机播放；仅 Widget 重建下降不作为 native 播放验收。

## 8. 已排除或已有防线

| 不应重复报告的旧问题 | 当前依据／保留要求 |
| --- | --- |
| 推荐和视频相关推荐全量挂载 | 推荐为 Sliver 网格，相关推荐为 SliverList.builder；[列表记录](feed-scroll-performance.md)与[当前 VideoScreen](../../lib/features/video/presentation/video_screen.dart#L696) |
| 滚动不停启动 hover preview | 任一祖先滚动会取消，静止后重新等待；保留 eviction／账号／迟到结果处理 |
| 预览持续预读五分钟 | 预览已显式 5 秒；普通播放五分钟是向前预读上限，不是起播等待时间 |
| Windows 预览仍有旧同步 mpv 尺寸查询等待 | [仓库补丁与前序证据](video-preview-contention.md)已修复；剩余 native 创建成本另测 |
| 每帧布局全部弹幕、默认阴影没有缓存 | 已有每帧 32 项准备、布局／图像缓存、轨道索引和活动保护；本次重点是应用层窗口与预算外条件 |
| 键盘高度变化始终重建整页和清空直播弹幕缓存 | [WidthLayoutBuilder／缓存保留](mobile-danmaku-keyboard-performance.md)已实现 |
| 影视选集挂载全部数千集或仍无法衔接外层滚动 | 有界 GridView/ListView.builder 和 ScrollBoundaryHandoff；问题在系列与重复数据整理 |
| 直播解压在 UI、聊天和 SC 无容量 | WS 有独立 worker 与受限队列；聊天 500／SC 100；问题在解码之后的 reducer 和视图传播 |
| 直播后台无限拉取，SC 每秒全局重建 | inactive 会停止连接／轮询，显示 Timer 受 TickerMode 控制，倒计时局部刷新 |
| 云续播、字幕或弹幕阻塞 native open | 云续播异步；辅助字幕／弹幕在媒体准备后启动；本地读取与详情依赖需分开分析 |
| 普通 DASH 仍用旧 audio-add 锁路径 | [启动优化](playback-startup.md)已改 audio-files；仍须保留真实音频确认 |
| 页面重建等同新播放器／第二路音频 | 本轮点播探针新增 open 为 0、同时 surface 为 1；需区分 Widget 更新与换源时底层 native 重建 |

## 9. 本轮产物与验证

关键结果已写入本文，忽略目录中的原始入口／JSON／log 为本机复核材料，不随 Git 文档自动分发：

| 探针 | 本机目录 | 本轮结果 |
| --- | --- | --- |
| 图片缓存结构 | `artifacts/home-performance-hotspots/`：`cache_probe.dart`、`results.json` | 全目录扫描与传输槽等待复现完成 |
| 共用播放器结构 | `artifacts/performance-audit/`：`vod_structure_probe_test.dart`、`vod-structure-results.json`、`vod-structure-probe.log` | 1 项 widget 探针通过，覆盖三类快照输入 |
| 长季解析 | `artifacts/pgc-performance-readonly/`：`parse_probe.dart`、`parse-results.json` | 三种规模的 CLI JIT 微基准完成 |
| 直播状态／页面结构 | `artifacts/performance-hotspots-2026-10-11/`：`live_structural_probe_test.dart`、`live-structural-results.json`、`live-structural-probe.log` | 1 项 widget 探针通过，覆盖四种投递场景 |

在仓库根目录可复现本轮入口：

```powershell
dart --packages=.dart_tool/package_config.json artifacts/home-performance-hotspots/cache_probe.dart
flutter test artifacts/performance-audit/vod_structure_probe_test.dart --no-pub --no-test-assets --reporter expanded
dart --packages=.dart_tool/package_config.json artifacts/pgc-performance-readonly/parse_probe.dart
flutter test --no-pub artifacts/performance-hotspots-2026-10-11/live_structural_probe_test.dart --reporter expanded
```

本次只新增本文并更新文档索引，探针位于忽略目录；没有业务代码、依赖、原生补丁或设置改变。本文和索引的 186 个本地链接、81 个源码行号范围检查通过，三个子代理完成对应章节的只读复核，差异检查通过；未运行完整 `tool/check.ps1` 或应用构建。前序全套测试和 Windows Profile 结果只作为 H 引用，不属于本轮新验证。

本轮没有真实账号／CDN、Windows 原生出帧、Android／macOS 构建或实机性能采样。上述优化尚未实施，因此没有优化后收益或线上卡顿已解决的结论。
