# 热门四子标签与协议依据

日期：2026-10-25。

## 来源与采用边界

本次只读核对相邻仓库的实际提交：

- PiliPlus：`936072449e82e3d90c28c728c0087bf5136fa441`，`lib/http/api.dart`、`lib/http/video.dart` 的期数目录、单期和入站必刷请求，以及 `lib/pages/popular_series/controller.dart`、`lib/pages/popular_precious/controller.dart`。其应用为 GPLv3，只用于理解接口和选择期数的职责，没有复制 Dart 实现、测试、资源或 GetX 状态结构。
- biliuwp-lite：`baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0`，`src/BiliLite.UWP/Models/Requests/Api/RankAPI.cs`，核对排行 `rid/type` 和 WBI；不导入 C# 或静态全局服务。
- bili-kernel：`e26f6dbd071e20d4220806fcff7bd675f3c29fc5`，`src/Services/Services.Media/Core/VideoDiscoveryClient.cs` 和 `src/BiliKernel.Abstractions/Bili/BiliApis.cs`。其热门/全站榜包含 App gRPC 路径，未将该 profile 当成现有 Web Cookie 能力。许可边界沿用[参考文档](../references.md)。

权威协议依据来自本次读取的[综合热门](https://www.bilibili.com/v/popular/all)、[每周必看](https://www.bilibili.com/v/popular/weekly)、[入站必刷](https://www.bilibili.com/v/popular/history)、[排行榜](https://www.bilibili.com/v/popular/rank/all)以及该 HTML 引用的[官方公开脚本 index.55b42adc.js](https://s1.hdslb.com/bfs/static/2233-monorepo/popular/static/js/index.55b42adc.js)。浏览工具已访问上述页面，但未提取到正文；随后以普通 HTTPS 只读读取官网 HTML、官方脚本和公开 API 确认字段。没有浏览或操作正在运行的客户端，没有账号写请求。

脚本的每周必看先获取目录，再以 `number` 获取单期；入站页使用 `page_size=100/page=1`，其列表适配显式视作无后续页。PiliPlus 额外为这些端点加 WBI 参数；本实现以官网可见的 Web GET 参数为依据，不照搬 App 参数或参考项目的请求封装。

## 端点登记

所有新增请求使用 Web profile、HTTPS GET、`api.bilibili.com`、Cookie 可选，无 CSRF 和自动账户写操作。综合热门与新增精选读取不添加 WBI；既有排行榜继续保留 WBI，动态分区目录不改变。

| 内容 | path / 参数 | 数据与分页 |
| --- | --- | --- |
| 综合热门 | `/x/web-interface/popular?pn=<page>&ps=20` | `data.list[]/no_more`；按服务端持续分页，不新增 500 条截断 |
| 每周期数目录 | `/x/web-interface/popular/series/list` | `data.list[]` 的 `number/name/subject`；保留服务端顺序，按期号去重，最多 1024 期 |
| 每周单期 | `/x/web-interface/popular/series/one?number=<number>` | `data.list[]`，完整单期，无分页；视频沿用公共模型映射 |
| 入站必刷 | `/x/web-interface/popular/precious?page_size=100&page=1` | `data.list[]`，沿用官网单份列表语义，不根据列表长度猜测下一页 |
| 排行榜 | `/x/web-interface/ranking/v2?rid=<tid>&type=all` | 现有 WBI 路径、单份榜单；不替换为普通 newlist 分区 ID |
| 排行分区 | `/x/kv-frontend/namespace/data?appKey=333.1339&nscode=10` | 继续使用 `RankingClient` 的动态官网 UGC 目录，详见[排行榜分区记录](ranking-regions.md) |

单期/入站响应最多 500 个视频，期号范围 `1..1000000`，目录名称最多 256 字符、主题最多 1024 字符。损坏或超限响应返回协议错误，不伪装成空成功。长视频/作者 ID 继续走既有字符串映射；周次为受限整数。

请求沿用 `BiliApiClient` 与 `ApiRequests.run` 的取消、账号 epoch、每次仓储读取 25 秒 deadline 和有界只读重试。目录和单期共享本次页面取消信号，Feature 不增加重试层。HTTP/网络之外的业务拒绝不自动重放，尤其 `-352` 不回退综合热门，也不把其他内容冒充每周结果。

## 页面与状态

热门依次展示“综合热门、每周必看、入站必刷、排行榜”。排行榜仍可由旧 `HomeChannel.ranking` 进入，但统一显示热门的排行榜子标签；主频道顺序 `HomeChannel.primaryValues` 排除独立排行项。旧 URI 由组合根规范为 `channel=popular&section=排行榜`。

四个子标签使用共享 `ContentSectionTabs`，与番剧等内容子标签一致：左对齐纯文字、选中玫红、浅灰圆角悬停，无图标和下划线。内容保留 `RetainedTabView`，列表仍使用 `SliverVideoGrid` 和现有 `VideoCard`。首次选中才加载，返回保留内容与独立滚动。嵌入首页一级滑动容器时，子标签通过点击或横向滚轮选择，避免嵌套水平 PageView 抢占原有一级频道滑动；独立热门页面保留子标签滑动。选中项仅在需要时滚入可见区，普通数据重建不重置手动横向位置。

沿用当前工作区的 `FeedController`，不另起进程级热门控制器。每周切期先取消旧请求并增加 generation；目录加载或单期的迟到响应不能覆盖新选择。刷新目录时保留有效选中期，若该期被移除则选服务端最新一期。最多缓存 6 个历史期及当前期，数据索引和周次滚动 bucket 均有相同容量边界；新期从顶部开始，缓存期返回恢复其位置。

隐藏 pane 的分页、操作和目录撤下监听都以 pane 选择及外层 `WorkspaceActivity` 合成活动状态。只有当前 pane 接收刷新，页面不叠加新的 F5 目标；组合根现有视频频道命令调用同一 `FeedController.refresh`。排行榜 F5、下拉和按钮刷新都重新获取动态目录，已撤下的分区回到全站。

直播的业务子项同时收敛为“推荐直播、我的关注、观看记录”，旧“全部分区”规范到推荐直播，分区选择仍保留在推荐内容中。`FeedScreen.showLiveSectionTabs` 允许组合根在桌面抑制重复子行，`onSectionChanged` 同步当前频道 URI；受控入口缺少 section 时使用推荐直播，显式 section 优先。该改动不复制直播协议或删除分区浏览能力。

## 当前在线证据与验证边界

本次无 Cookie 的只读抽样：

- [期数目录](https://api.bilibili.com/x/web-interface/popular/series/list) 返回 `code=0`，首项为第 396 期。
- [入站必刷](https://api.bilibili.com/x/web-interface/popular/precious?page_size=100&page=1) 返回 `code=0`，列表 98 项。试用较小 page_size 时服务仍给出完整列表，不把这一抽样当成通用分页承诺。
- 第 396 期的 `series/one` 读取返回业务 `-352`，未取得在线单期数据，不能称四类全部在线通过；页面保留真实错误与显式重试。

自动测试使用虚构数据和 fake transport/repository，覆盖端点参数、目录顺序/去重/边界、共享视频字段、业务拒绝不重试、账号旧响应、切期竞态、有限缓存、期数撤下回退、综合热门超过 500 条仍分页，以及子标签/滚动/隐藏活动/窄屏。此记录不代表 UI 人工验收、设备播放、性能或原生集成通过。按用户要求仅做自动回归与构建，未执行 UI/实机/native 集成验证，未操作现有客户端。

| 定向检查 | 结果 |
| --- | --- |
| `flutter test --no-pub test/features/feed` | 271 项全部通过；日志 `build/popular-feed-tests.log` |
| bili_api 的 `popular_client_test.dart`、`ranking_client_test.dart`、`api_client_test.dart` | 47 项全部通过 |
| 受影响 Feed 源码/测试、bili_api 源码与新协议测试静态分析 | 通过 |
| 受影响文件格式、差异空白检查 | 通过 |

全量检查及目标平台构建由主代理统一执行，本代理没有运行构建或原生集成测试。
