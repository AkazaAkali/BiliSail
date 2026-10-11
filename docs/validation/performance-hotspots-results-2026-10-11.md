# 首页推荐与三类播放性能热点：第一批优化结果

日期：2026-10-11。实施基线：`11ecf172d5d42622295dbb41784126e11adf08f9`。对应[热点调查](performance-hotspots-2026-10-11.md)的第一批 P1：F1、F2、V1、V2、V3、G1、G2、L1、L2；P2 保持后续测量范围。三个 Astra xhigh 子代理分别负责图片、共享播放、直播，主代理负责影视、交叉审查和集成验证。

本轮没有修改原生播放器、网络端点、依赖或设置默认值。结构计数用于确认额外工作已消除，不把 widget 测试耗时或 Dart CLI JIT 微基准解释为设备帧率、首帧或功耗收益。

## 1. 已实施范围

| 热点 | 改动与作用 | 主要源码 |
| --- | --- | --- |
| F1 图片交付等待磁盘维护 | 下载结果直接交付并释放网络名额；可选写入独立排队，启动一次扫描建立索引，后续增量维护配额 | [ImageByteCache](../../lib/core/storage/image_byte_cache.dart) |
| F2 离屏任务与可见队列竞争 | URL 单飞任务按消费者租约计数；最后一个消费者离开取消未完成任务，当前视口优先于预取；保留已经解码的图片帧 | [图片提供器](../../lib/core/presentation/app_image_provider.dart)、[图片视图](../../lib/shared/ui/app_network_image.dart) |
| V1 快照扩大视图更新 | 相同快照不再重复发布；位置／buffer 只更新时间、字幕、进度等局部；稳定 surface、弹幕组件与控件菜单不跟随每次 position 更新 | [播放器视图](../../lib/features/playback/presentation/playback_panel.dart)、[局部快照订阅](../../lib/features/playback/presentation/playback_snapshot_builder.dart)、[播放器契约](../../packages/bili_player/lib/src/player_contract.dart) |
| V2 重复设置与全分段排序 | 比较相关弹幕设置；分段到达时排序一次，取窗使用二分切片和有序归并，同轮响应合并一次刷新 | [PlaybackSession](../../lib/features/playback/application/playback_session.dart)、[CommentSegment](../../lib/features/playback/domain/comment_window.dart) |
| V3 隐藏点播继续准备弹幕 | 隐藏时取消分段请求、冻结弹幕时钟并回收可重建的 raster；恢复时按后端确认位置重建当前窗口 | [PlaybackSession](../../lib/features/playback/application/playback_session.dart)、[DanmakuController](../../packages/bili_danmaku/lib/src/danmaku_controller.dart) |
| G1 影视系列全量挂载 | 简介改为 CustomScrollView，系列使用 SliverList 懒创建并保留稳定委托与条目 key；选集仍有界 | [PgcScreen](../../lib/features/pgc/presentation/pgc_screen.dart) |
| G2 影视局部操作更新播放器 | 简介展开状态下沉；相同 season／episode／builder 复用播放器子树，主题和设置等 inherited 依赖仍正常传播 | [PgcScreen](../../lib/features/pgc/presentation/pgc_screen.dart) |
| L1 直播无关事件复制状态 | 只有涉及的聊天／SC 窗口才复制，相同人数、状态及重复内容不再发布无变化状态 | [LiveController](../../lib/features/live/application/live_controller.dart) |
| L2 直播整页订阅 | 页面只订阅房间／加载／错误，人数、聊天、SC 各自订阅；同一房间复用播放器子树 | [LiveScreen](../../lib/features/live/presentation/live_screen.dart) |

另外收敛 L4 中的一个局部问题：最近 SC 绝对到期时刻未变化且已有有效 Timer 时，不再重设 Timer。没有修改 HTTP 对账周期或 SC 倒计时组件。

## 2. 容量与生命周期边界

### 图片

- 保留 6 个传输名额、最多 64 个已接纳任务、单图 4 MiB，以及磁盘 64 MiB／512 文件上限。后台写入含运行任务最多 16 个／16 MiB；满时跳过可选持久化，已下载图片照常显示。关闭服务等待已接纳写入排空。
- 仍使用临时文件加原子替换、摘要完整性校验、TTL，以及 scope／session generation／缓存开关代次／清理代次检查；旧任务不能在账号切换或清理后重新写入。
- 可见与预取需求在当前轮合并后分配名额。同 URL 的多个消费者共享下载，释放一个不会中断另一个；没有消费者的排队项直接移除、运行项取消。保留已有图片帧与未完成网络需求是两个独立生命周期。
- 磁盘读取与可选写队列分离。读取只更新身份仍匹配的现存索引，不能用旧字节长度覆盖新文件大小或恢复已删除索引；损坏读作为 miss，不并发删除可能刚替换的新文件。
- 已交付但尚未落盘的字节可由同 URL 读取复用，占用的仍是上述写队列预算，不另建无界缓存。损坏解码的 skipDisk 重试绕过该复用；开关、账号和清理代次检查继续生效。

### 视频与影视

- `PlaybackSnapshotBuilder` 只派生视图更新，不采样或节流后端媒体时钟。每标签仍只有一个 PlaybackSession，进度记录、云上报、互斥与多标签播放策略不变。
- 每分段最多 6000 条、会话最多邻近 3 个分段。归并仅减少取窗工作，必须把完整有效时间窗交给渲染器；不能先截成 pending 500 条，否则会误删仍显示的活动弹幕。
- 弹幕设置的显示属性与过滤属性分别判断；过滤、偏移、速度、字号变化仍刷新所需窗口，无关设置不触发整理。
- 隐藏标签可继续媒体播放，停止的是点播弹幕请求与呈现准备。返回时清除旧动画年龄，按确认位置恢复；全屏切换仍属同一可见 owner。布局缓存继续有界保留，原生 raster 可以重建。
- 影视缓存随资料／选集／注入 builder 变化失效；缓存内部 Builder 继续接收主题等 inherited 变化。简介选集、滚动位置、切 tab、侧栏、权限与刷新操作保留原行为。

### 直播

- 聊天 500、SC 100 的容量与删除顺序不变。无视图变化的事件仍更新必要的实时序号，防止迟到 HTTP 快照覆盖较新 WS 状态。
- SC 仍以绝对到期时间移除，最近 deadline 改变才换 Timer。隐藏、下播、退出、账号 epoch 与连接生命周期继续由原控制器负责。
- 局部订阅不会新增连接或媒体实例；主题等 inherited 变化仍能进入缓存的播放器子树。

## 3. 优化前后结构证据

以下比较复用调查时的 fake 输入和探针。旧数值来自调查保留的 JSON，优化后基于本轮工作区；无真实 CDN、原生视频或设备 FrameTiming。

| 场景 | 优化前 | 优化后 |
| --- | --- | --- |
| 图片：512 个种子文件，再下载 20 张 | 21 次全目录扫描；10,772 个遍历／stat 调度 | 1 次扫描；512 个遍历／stat 调度 |
| 图片：阻塞可选磁盘，7 个请求 | loader 完成 6，调用方完成 0，第 7 个未开始 | loader 与调用方均完成 7，第 7 个正常开始 |
| 播放器：20 次 position 更新，元素重建通知 | 7,300 | 344 |
| 播放器：20 次 buffered 更新，元素重建通知 | 7,300 | 320 |
| 播放器：20 次值相同快照，元素重建通知 | 7,300 | 0 |
| 播放器：上述每组的 surface／弹幕组件／主控件重建 | 20／20／20 | 0／0／0 |
| 影视：宽 1200、5000 集、100 系列，首屏挂载图片 | 100 | 3 |
| 同上，简介展开触发图片可见性检查／playerBuilder | 100／1 | 0／0 |
| 影视：宽 390、5000 集、100 系列，首屏挂载图片 | 100 | 0（系列尚未进入视口） |
| 同上，固定滚动后的图片可见性检查 | 101 | 4 |
| 直播：500 聊天、0 SC，20 批忽略人气；通知／聊天替换／SC 替换／playerBuilder | 20／20／20／20 | 0／0／0／0 |
| 直播：同输入，20 批新聊天；通知／聊天替换／SC 替换／playerBuilder | 20／20／20／20 | 20／20／0／0 |

影视 1275 集／20 系列场景首屏图片也从 20 降至 3，选集挂载仍为 6。简介长季结构用例另验证滚到最后一个系列、跳转、返回顶部和展开状态保留。直播相同人数探针第一批首次设置人数，因此优化后是 1 次通知；永久测试预先设置相同值后，20 批为 0 次。

共享播放探针使用暂停源、可见控件、DPR 1、宽 1200、每次 pump 16 ms；前后新增 engine open 都是 0、同时挂载 surface 最大都是 1。指标是 Flutter 元素 rebuild 通知，不是绘制帧数或原生视频出帧。

窗口另有 Dart CLI JIT 合成微基准：先预热 20 次，再采样 50 次，只计取窗，排除首次分段索引、过滤、控制器替换、分配测量、Flutter 和 native。普通分布、窗口 1267 条时，1×6000 的 P50 为 0.849→0.033 ms，3×6000 为 3.183→0.036 ms。全部同秒都落窗时仍完整处理 6000／18000 条，P50 分别为 0.200→0.153 ms、0.840→0.662 ms；18000 条这一组的 P95 则为 1.509→2.215 ms。这一场景仍然是线性工作，且尾部样本没有一致改善，不能用它承诺高密度播放的固定收益。

## 4. 审查与验证

交叉审查发现并修复两处图片竞态：完整释放后的延迟 resolve 重新启动请求；并行读取以旧长度覆盖新文件配额索引。增加终止标记及读后替换／淘汰的确定性交错测试。联调发现时间轴图片尺寸探测和缩略图解码会在异步落盘前重复下载，已用有界待写字节复用修复，保留原有 `loads == 1` 断言。

共享播放交叉审查还发现隐藏页面后台换集会被 `activate()` 误标为可见。已让两处 Panel 激活显式传入实际可见性，并强化真实 PGC 连播回归：隐藏切到下一集继续播放，但不新增弹幕请求／同步；返回才补当前窗口且不重新 open。三项审查问题均由交叉审查者复核关闭。

定向验证已通过：图片／可见性／首页滑动／时间轴首轮 61 项，补充动态布局和分页后相关 75 项均完成验证；影视页面 22 项；共享播放最终 312 项，弹幕包 85 项、快照／尺寸 11 项；直播首轮 94 项，后补主题传播测试由全仓检查覆盖。播放器、影视、直播各 1 项结构探针通过，图片 CLI 结构探针完成。这些集合有重叠，不相加作为全仓测试总数。

首次全仓检查发现两种旧图片测试语义：要求离屏慢请求继续占槽；用 `ImageLoadCancelled` 冒充下载失败并期待错误图标。已改为会响应取消的 fake，严格验证旧请求取消、当前视口前进、活动／峰值均为 1；真实失败用 `HttpException`，原有图片恢复、错误占位、尺寸和滚动锚点断言继续保留。没有放宽真实错误重试或并发预算。

检查期间另一任务修改并提交紧凑播放控件，因此使用隔离工作树提取本轮 31 个文件，保留主工作区的并发改动。首次 `./tool/check.ps1 -EnforceLockfile` 通过后，合入紧凑控件提交 `7544526da33bd9f062a086ae8e56419480e4effe`，以该提交加本轮改动执行最终 `./tool/check.ps1 -SkipPub`，退出码为 0。最终日志保存到本机 `artifacts/performance-hotspots-2026-10-11/full-check.log`。

| 最终全仓检查 | 结果 |
| --- | --- |
| 根应用 | 1743 项通过 |
| bili_api | 379 项通过 |
| bili_player | 35 项通过 |
| bili_danmaku | 85 项通过 |
| bili_mux | 2 项通过，7 项原生测试跳过 |
| 根应用与上述四个包的格式、静态分析 | 全部通过 |
| Android 版本／签名边界脚本 | 34／21 项通过 |
| Windows 安装包版本脚本 | 14 项通过 |
| macOS 发布权限与 smoke 确认脚本 | 22 项通过 |

测试合计 2244 项通过、7 项跳过，另有上述发布脚本检查。跳过项需要未配置的 `BILI_MUX_LIBRARY`，不视为原生 mux 验收。验证 SDK 为 Flutter 3.47.6／Dart 3.13.5。本轮没有运行应用构建、真实 CDN 播放或三端设备 Profile；脚本检查通过也不代表安装包或实机 smoke 已完成。

本机原始材料位于忽略的 `artifacts/`，关键结果已抄录本文：`home-performance-hotspots/results.json`；`performance-audit/vod-structure-probe-after-p1.log`、`comment-window-p1-results.json`；`performance-hotspots-2026-10-11/{pgc-structural-after,live-structural-results}.json`。旧结果另存 before 文件，未把日志、JSON 或探针临时脚本提交为产品代码。长期行为断言保留在相应 `test/` 与 package 测试中。

## 5. 未实施范围与后续验收

P2 尚未整体实施：图片连接池、长期 feed 数据与频道订阅、hover 媒体复用；首帧串行阶段、字幕索引、评论构建与高 DPR fallback；PGC 分组／解析／起播依赖；直播富文本缓存及周期性对账。L4 仅处理上述 Timer 重设。

后续按[原测量矩阵](performance-hotspots-2026-10-11.md#7-后续测量与验收设计)做 Profile／Release 配对采样：推荐图片交付和可见排队 P95、取消浪费字节；点播窗口 CPU、UI／raster P95/P99、原生 render gap；多标签 CPU／RSS／GPU；影视首开与滚动；直播突发和真实表情。Windows 窄窗口不替代 Android 真机，macOS 也需单独验收。本轮不声称三端真实性能或网络收益已通过。
