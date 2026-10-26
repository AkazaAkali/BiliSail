# 晴湾界面与双标签实施记录

日期：2026-10-25。依据[候选方案与最新确认](proposals.md)。

同日默认值修订：各平台统一默认双标签，已保存的有效双／多标签选择保持。下文各轮的旧默认值为历史记录，当前行为与验证见[多标签与播放窗口记录](../validation/multi-tab-playback.md)。

## 第一轮确认范围（后续修订见文末）

- 保留单标签、多标签和全部现有业务功能，新增可保存且即时生效的双标签模式。默认仍为 Windows/macOS 多标签、Android 单标签；有效旧设置不变。
- 桌面首页、动态、直播、我的分组，另有消息、下载、设置。番剧、国创、放映厅留在首页，不新增影视一级入口或媒体库。
- 可用宽度小于 600 时，底部严格为首页、动态、我的、设置；直播与影视频道都在首页。播放与用户详情收起底部导航。
- 不修改视频卡、封面比例、懒加载网格、弹幕或播放器控件实现；共享主题采用淡蓝灰背景、白色内容面板、原玫红强调色及相应深色层次。

## 实现

- [shell](../../lib/app/shell.dart) 使用 LayoutBuilder：小于 600 为底部导航；默认自动模式在 600–1599 为 76 宽导航轨，1600 起为 164 宽侧栏（2026-10-25 平板适配将展开阈值从 1180 延后）。2026-10-27 增加可保存的完整／上下排布侧栏选择及完全收起按钮，见[宽屏侧栏](../validation/wide-sidebar.md)。内容面板统一圆角与留白。布局树和页面身份保持稳定，宽度变化不会更换 ProviderScope 或媒体 owner。推荐等共享网格在默认字号下支持更小的三列卡片；较宽平板可以显示四列，见[共享视频卡片](../validation/shared-video-cards.md)。
- [导航分组](../../lib/app/workspace_navigation.dart) 覆盖全部 12 个既有 HomeChannel。频道页继续保留现有横向分页、各自状态和筛选；跨分组滑动时一级入口同步选中。[频道条](../../lib/shared/ui/paging_tab_strip.dart) 将完整分页进度映射到当前分组，不把不同组的索引当作同一组。
- [我的页面](../../lib/features/auth/presentation/account_screen.dart) 使用独立账号卡、观看入口与账号服务布局，复用账号、等级、关注／粉丝、消息未读及登录控制器；首页头像仍打开原 [AccountMenu 抽屉](../../lib/features/auth/presentation/account_menu.dart)。页面导航和账号变化不关闭“我的”页。
- [工作区模型](../../lib/app/workspace_tabs.dart) 将已保留页面投影为一个浏览槽和一个播放槽；新的媒体导航复用播放页 ID，UGC／PGC／直播／离线播放统一处理。原有页面缓存 16、访问历史 64 不变，双标签内部媒体返回历史最多 16 条。
- 返回优先处理页内详情，再返回播放历史，历史为空回到浏览槽；关闭播放槽释放其会话、清空媒体历史并回到原浏览页。浏览槽不能被关闭。现有关闭快捷键和侧键配置继续使用共享输入宿主，Ctrl+Tab 只循环两个可见槽。
- [PlaybackSession](../../lib/features/playback/application/playback_session.dart) 为双标签保留有界媒体快照，保存身份、分 P、位置、暂停意图及可恢复选项，不保存媒体 URL、凭据或额外 engine。缓存最多 17 项（16 个返回目标及捕获中的当前目标），scope/epoch 校验阻止跨账号恢复；关闭会话时清空。历史目标重新解析媒体源，继续使用既有 generation、取消及互斥播放许可。
- 自动连播／选集更新沿用原页内导航，不逐项加入媒体返回历史；迟到的页内回调须匹配当前 URI，不能覆盖后来选择的视频。单／多模式本身不增加媒体快照逻辑。
- 设置增加 `dualTabs` 枚举值，沿用已有字符串序列化与未知值平台回退，无新依赖、数据库表或 SQLite migration；并发播放仅在多标签模式开启时生效。

## 第一轮验证（第二轮改动前）

- `tool/check.ps1 -SkipPub` 通过，日志 `build/validation/qingwan/check.log`：根应用 2080、bili_api 437、bili_player 81、bili_danmaku 93、bili_mux 2，共 2693 项测试通过；五处格式／静态分析及打包边界脚本通过。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不能视作原生封装通过。
- 行为覆盖：三种模式的设置保存与并发限制、两槽复用／媒体回退／关闭／有界缓存、旧回调隔离、账号 epoch、真实路由与播放 ProviderScope 保留、分 P、进度与暂停恢复、缩放不重建会话、键盘／鼠标侧键、完整频道分组及四项底部导航、我的页登录变化和全部入口。已有搜索、评论、消息、下载、全屏等回归继续通过。
- `tool/build-download-mux.ps1 -Target windows-x64` 已通过，准备本机构建所需资产，日志 `build/validation/qingwan/mux-assets.log`。
- `tool/test-windows-media.ps1` 通过，日志 `build/validation/qingwan/windows-media.log`。包含主播放、诊断、启动／首帧、预览缓冲、音量均衡与前向缓冲。新增本地双标签 A→B→返回 A→关闭的原生断言通过，A 恢复约 1700ms、暂停和 1.5x，音视频两轨解码成立，播放页／surface 数量保持一份，关闭回到原浏览页。未开启 `-Online` 公网分支。
- `tool/test-windows-content.ps1` 通过，日志 `build/validation/qingwan/windows-content.log`：实际执行本地受控影视／直播播放，未开启 `-Online` 的 CDN 验证分支。
- `flutter build windows --release --no-pub` 通过，日志 `build/validation/qingwan/windows-release.log`。运行入口 `build/windows/x64/runner/Release/bilisail.exe`，运行时保留整个 Release 目录。构建仍输出第三方 inappwebview 的既有 CMake CMP0175 开发警告。
- 已启动该路径的 Release 窗口，实际查看桌面首页、外观设置的三种模式和双标签即时切换，以及窄窗口动态页的四项底部导航。检查期间原多标签偏好被暂时切为双标签；检测到用户开始操作预览窗口后停止自动操作，预览保持双标签，由用户在设置中选择。没有改动平台默认值。
- 本轮未做 Android/macOS 构建和实机、完整账号操作或性能测量。窄屏与平台变体 Widget 测试、Windows 受控原生回归不替代其他平台的窗口、触控与媒体验收。
- 六份相关 Markdown 的本地链接检查、`git diff --check` 通过。未提交或推送代码。

## 第二轮：独立播放窗口与页面收整

依据[第二轮方案](refinement-plan.md)及用户确认：Windows/macOS 双标签改为主窗口浏览、一个独立播放窗口；视频、影视、直播、离线播放共享同一窗口和会话。Android 继续应用内切换，浏览页提供“返回播放”入口。双标签取消顶部标签栏，Windows 仅保留 32px 的拖动/系统控制栏，macOS 使用原生标题栏。

- 主窗口与播放窗口共用同一 Flutter engine、Riverpod 依赖、账号和进程级下载任务。两个窗口可同时可见，浏览页不会抢走播放所有权；返回媒体沿用有界历史，关闭播放清理会话，主浏览位置保留。单/多标签及平台默认偏好不变。
- [平台适配](../../lib/core/platform/detached_playback_window.dart) 集中使用固定 Flutter 3.47.6 中的实验 `RegularWindow`/`ViewAnchor` API，保留原 implicit 主 view，避免现有插件对主 view 的依赖失效。此 API 尚非稳定公开接口，未来 SDK 升级需重新审查；不修改 SDK、Pub 缓存、全局 Flutter 配置或依赖版本。官方背景见 [Flutter 窗口 API](https://flutter.dev/blog/desktop-windowing-apis)。
- [窗口内宿主](../../lib/app/workspace_playback_window.dart) 提供独立 Navigator、快捷键和通知区域；全屏通过窗口级 WindowService 操作目标窗口。输入宿主按 viewId 隔离键鼠；Windows IME 按 viewId 查找真实 HWND，保留已有输入法上下文策略。窗口销毁前先卸载其 Flutter view。
- 主浏览 view 重新获得焦点时同步浏览路由，再点同一视频也会激活已有播放窗口；自动连播、换 P 等页内更新不会因主窗口仍在浏览而强行抢焦点。macOS 与 Android 的用户详情页保留紧凑返回行，不依赖 Windows 自绘标题栏。
- Windows 的 `window_manager 0.5.2` 只对 implicit 主窗口应用隐藏标题栏等策略；[构建补丁](../../windows/patches/window_manager/apply.cmake) 校验锁定版本源码 SHA256 后修改构建副本。子窗口保留原生标题栏与独立最小尺寸。Windows AX 可达性保护改为按 SemanticsOwner 分离缓存，避免两个 view 的根节点 ID 0 互相污染。
- 创建、激活、修改标题及销毁原生窗口统一延后至帧结束后的下一轮 idle 事件循环，避免同步焦点回调打断 Flutter build，以及原生消息循环重入尚未退栈的帧回调；快速关闭会取消尚未执行的请求。等待创建期间暂存同一播放子树，再按 GlobalKey 迁移到新 view，切换模式不释放页面、ProviderScope 或播放会话。关闭后迟到的 IME 回调只取消已销毁的目标 view，其他平台错误仍正常报告。
- 新 view 创建成功后直接向 PlatformDispatcher 请求一次引擎帧：旧 view 的待调度标记可能已失效，而 `scheduleFrame`/`scheduleForcedFrame` 都会受该标记拦截。真实工作区回归曾复现等待首帧停滞，运行时补发帧立即解除，修正后本地完整工作区用例通过；没有增加轮询或独立重试链。
- 品牌使用既有正式图标；消息/下载/设置固定到桌面侧栏底部，小高度上方导航可滚动。动态、直播、我的及关联频道移除通用头像/搜索/工具按钮；保留业务频道、筛选和必要返回入口。
- “我的”支持游客登录、账号资料/等级/关注统计、观看入口、未读消息与失败重试；宽屏分栏、窄屏堆叠、放大字体可滚动，不把抽屉嵌进页面。

### 第二轮验证

- 最终 `tool/check.ps1 -SkipPub` 通过，日志 `build/validation/qingwan/refinement-check-final.log`：根应用 2134、bili_api 437、bili_player 81、bili_danmaku 93、bili_mux 2，共 2747 项；五处格式、静态分析及打包边界脚本通过。mux 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不算原生封装通过。
- 最终窗口时机修正后的定向测试 57 项通过，日志 `refinement-window-idle-tests.log`，覆盖 adapter 的 8 项用例、WindowService、双 view 工作区和真实播放路由，包括帧回调结束到 idle Timer 执行之间取消窗口请求。独立“我的”页 15 项、Windows 多 view AX 16 项亦通过并包含在全量检查中。
- `tool/test-windows-media.ps1` 通过，日志 `build/validation/qingwan/refinement-windows-media.log`；最终 idle 时机修正后再次运行完整 `windows_playback_test.dart` 目标，8 项全部通过，日志 `refinement-playback-idle-final.log`。本地双窗口断言确认一份会话、两个 view、播放窗复用、返回时进度/暂停/倍速恢复和关闭回到浏览。
- `tool/test-windows-content.ps1` 在最终 idle 时机修正后通过，日志 `build/validation/qingwan/refinement-content-idle-final.log`。实际执行本地 UGC DASH → PGC DASH → HLS → FLV，核对同一会话、view 与 surface，关闭后回收窗口并停止播放；未开启 `-Online`，第二条公网用例提前返回，不算在线通过。
- `tool/test-windows-video-dispose.ps1` 的 9 项原生生命周期测试通过；`tool/test-windows-ime.ps1 -NativeOnly` 的 TSF/IME 上下文、隔离与销毁测试通过。日志分别为 `refinement-video-dispose.log`、`refinement-ime.log`；不是第三方输入法候选与中文输入的实机验收。
- Windows Debug GUI 检查中，正式图标、底部固定消息/下载/设置、动态与直播页的工具栏隐藏、我的页账号资料加载和双栏入口正常。真实直播打开第二窗口，返回主窗口浏览首页后打开普通视频，复用相同原生窗口；播放窗返回恢复上一直播，点击系统关闭按钮后只剩主窗口，原首页位置保留。初次运行完整日志发现的帧重入断言已通过 idle 调度修正。
- 最终 Debug 应用已完成热重载与实际视频播放复验：关闭播放窗后主窗口保留，再次打开创建新播放窗并继续出画；播放中关闭主窗口后进程正常退出，未残留 bilisail 进程。最终 GUI 日志 `refinement-ui-final.log` 与最终主播放、影视/直播原生日志均未出现未处理异常、Flutter 异常、断言或布局溢出。未执行关注、点赞、发送、退出账号等账户操作，未更改保存的双标签偏好。
- 最终源码的 `flutter build windows --release --no-pub` 与 `flutter build apk --debug --target-platform android-arm64 --no-pub` 均通过；日志为 `refinement-windows-release.log`、`refinement-android-debug.log`。Windows 运行入口为 `build/windows/x64/runner/Release/bilisail.exe`（保留整个 Release 目录），Android 安装包为 `build/app/outputs/flutter-apk/app-debug.apk`。Windows 仍有第三方 inappwebview 的既有 CMake CMP0175 开发警告。
- 320/390/600 等窄屏、放大字体、四项底部导航和 macOS 无自绘标题栏返回入口由 Widget 测试覆盖。本次 GUI 验收为 Windows 宽窗口，未将它等同于 Android/macOS 实机或性能验收。
- 当前 Windows 主机未执行 macOS 构建；Android/macOS 实机、完整账号流程、真实第三方输入法输入与性能测量仍未验收。八份相关 Markdown 本地链接及 `git diff --check` 通过；保留原有工作区修改，未提交或推送代码。

## 第三轮：导航精简、原生标题栏与个人内容标签

依据[第三轮方案](third-round-plan.md)修订以上产品行为；前两轮测试数字与构建记录仅代表当时源码。

- 导航模式删除 `singlePage`，仅保留 `dualTabs`、`multipleTabs`。旧单标签设置显式迁移至双标签，Android 缺失/非法值默认双标签，Windows/macOS 默认多标签；有效双/多模式选择保持。preferences JSON 快照升至 22，SQLite 表结构不变，不清理用户数据。
- 首页保留真实账号头像入口和搜索，移除顶部历史、下载、设置按钮。侧栏底部的消息、下载、设置保留；首页头像继续弹出原账号抽屉。
- “我的”顶部收为头像、名称、等级和登录/退出。历史记录、稍后再看、我的收藏、下载直接分标签展示；不再显示大统计卡、消息或直播关注入口。
- [组合根](../../lib/app/router.dart) 将既有 HistoryScreen、FeedScreen 和 DownloadsScreen 注入账号标签容器，各标签独立保留 ProviderScope、分页/筛选和滚动位置，下载仍使用进程级仓储。未访问标签懒初始化，隐藏标签关闭 WorkspaceActivity、Ticker 和焦点参与，刷新快捷键只操作当前标签；游客可直接访问下载，云端内容提供登录提示。
- 桌面播放窗删除 44px 的 Flutter 工具行，通过原生标题栏提供返回；系统关闭按钮保持关闭播放窗语义。Windows 标题栏左侧返回区保留其余原生标题栏操作，macOS 使用标题栏 accessory；平台代码不侵入 SDK 或 Pub 缓存。
- Windows 缩小根因是固定 SDK 的 `activate()` 无条件调用 `SW_RESTORE`，将已最大化窗口还原。激活按 viewId 定位目标 HWND，仅最小化时还原，普通/最大化窗口保留已有几何和状态；媒体导航仍复用原 view 与会话。

### 第三轮验证

- 账号容器 17 项定向 Widget 测试通过；组合根与原有历史/下载展示 22 项通过（`build/validation/qingwan/third-account-composition-tests.log`）。覆盖 390/1200 宽度四标签直接展示、标签切换不改变 `/me` 路由、滚动与子筛选保留、按需读取、游客下载以及 F5 只刷新当前标签。标签容器另覆盖 320/390/600/宽屏、大字体和隐藏状态。
- 最终 `tool/check.ps1 -SkipPub` 通过（`build/validation/qingwan/third-check.log`）：根应用 2115、bili_api 437、bili_player 81、bili_danmaku 93、bili_mux 2，共 2728 项测试；五处格式、静态分析和打包边界脚本通过。移除单标签后相应旧用例同步退役，不能与前两轮数量直接比较。mux 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不算原生封装通过。
- 刷新和输入注册专项 17 项通过（`third-refresh-input-tests.log`）：稍后再看的 F5 只刷新当前筛选，隐藏筛选/收藏夹不重载；空命令作用域不占用输入目标容量，并保留取消、导航回调。窗口/路由专项 55 项通过（`refinement-native-caption-tests.log`），包括原生返回事件的模态隔离。
- Windows 原生窗口 smoke 通过（`third-window-native.log`）：手动尺寸、最大化、最小化后恢复最大化、标题栏返回和双击、全屏、IME 与关闭。主播放目标先通过 7 项，剩余工作区用例修正测试等待后单独通过（`third-playback-native.log`、`third-workspace-transfer-native.log`）。测试等待现在同时核对 view 数量及播放树已迁入目标 view，避免把创建窗口与下一帧挂载混为同一步；继续断言双/多切换保留同一 State、源代次、暂停位置及倍速，以及新媒体复用窗口并保留尺寸和最大化。
- 本地 `tool/test-windows-content.ps1` 通过（`third-content-native.log`）：UGC DASH → PGC DASH → HLS → FLV 共用会话和原生 view，关闭后回收。未开启 `-Online`；第二条公网用例提前返回，不算在线验证。
- Windows Debug 已热重载，实际查看首页头像/搜索精简、我的页紧凑账号条及四个直接内容标签。收藏中连续打开两个真实视频，复用同一 HWND，最大化状态保持并正常出画。点击原生标题栏返回前用户按 Escape 停止 UI 自动操作，随即停止；该次 GUI 的返回和关闭步骤未完成，相关行为仅有上述自动回归证据。停止前完整日志及 Dart 运行时检查未发现未处理异常、Flutter 断言或布局溢出（`third-ui-debug.log`）。
- 用户随后明确要求“无需实机测试，单元回归后构建，由用户手动测试”；后续不再操作运行窗口或追加设备测试。当前预览窗口保留给用户，Android/macOS 实机、完整账号流程、真实第三方输入法及性能不在本轮完成范围；macOS 无本机构建环境，原生标题栏仍需对应主机验证。
- Windows Release 构建通过（`third-windows-release.log`），入口 `build/windows/x64/runner/Release/bilisail.exe`，运行时保留整个 Release 目录。第三方 inappwebview 的既有 CMake CMP0175 开发警告仍存在。
- Android arm64 Debug 构建通过（`third-android-debug.log`），安装包为 `build/app/outputs/flutter-apk/app-debug.apk`，未安装或执行设备测试。12 份改动 Markdown 的本地链接检查、`git diff --check` 通过；保留原有工作区修改，未提交或推送。

## 第四轮：一级导航与栏目整合

依据[第四轮方案](fourth-round-plan.md)。以上历史测试、GUI 和原生记录不代表本轮验证；本轮遵循用户要求，仅执行自动回归与构建，实机验收由用户完成。

- 多标签模式移除外壳左上角返回按钮。双标签浏览返回关闭所离开的临时页，并释放其请求、缓存与作用域；首页、动态、直播、我的作为固定根页的不同选择，不新增可关闭标签。“我的”与频道页分别懒加载并保留树、筛选和滚动，账号 scope/epoch 变化重建私有内容。
- 双标签播放返回逐个消费已有媒体历史，继续复用同一播放会话；历史耗尽时关闭播放页及独立播放窗口、释放会话。浏览窗口的原位置保留。现有系统关闭及键鼠快捷键继续使用共享入口。
- 桌面直播直接展示“推荐直播、我的关注、观看记录”，删除重复的外层“直播”和“全部分区”子标签，保留推荐内容的分区选择、头像与搜索。窄屏直播仍从首页进入；底部保持首页、动态、我的、设置四项。显式 URI 与重入时记住的筛选保持一致，旧“全部分区”链接规范到推荐直播。
- 消息的五类入口改用与首页相同的 `PagingTabStrip`，保留未读数、横向滚动、窄屏分栏切换及原业务。侧栏底部消息、下载、设置使用圆角消息框、下载和调节图标。
- 热门直接提供综合热门、每周必看、入站必刷、排行榜；原独立排行榜入口合并并兼容旧链接。每周可选官方期数，四类内容独立保留状态；继续复用现有视频卡和列表。期数切换隔离迟到响应，最多缓存六个历史期及当前期；综合热门保留连续分页，排行榜保留动态官网分区与 WBI。协议来源、端点和在线抽样边界见[热门四子标签记录](../validation/popular-tabs.md)。
- 首页一级频道的横向手势保持；嵌入首页时热门子栏目通过标签切换。共享保留式分页中，尚未访问的相邻页加载占位停用 ticker，避免滑动中止后隐藏进度指示器持续调度帧；已访问页面继续沿用各自活动状态与账号监听。

### 第四轮验证

- Feed 目录全部 271 项定向回归通过（`build/popular-feed-tests.log`），新热门与既有排行榜/API 客户端定向 47 项通过。新单元测试覆盖期数目录、切期竞态、账号旧响应、有界缓存、错误不冒充其他内容，以及综合热门超过 500 条仍继续分页。
- 工作区模型、根容器、账号组合、真实路由 64 项通过（`build/validation/qingwan/fourth-workspace-final-tests.log`），包括 390/1200 宽度初始进入“我的”后双向保留树和实际滚动、筛选/F5 隔离、一级导航不创建新标签、搜索返回取消请求、播放返回恢复前项以及耗尽后释放 fake engine。
- 外壳/导航 70 项及缺省直播 URI 与重入一致性补充回归通过；消息既有 14 项通过（`fourth-messages-tests.log`），包括窄屏、大字体、横向滚动和私信状态。受影响源码的定向格式及静态分析通过。
- 官方只读抽样中期数目录与入站必刷为 `code=0`，每周第 396 期单期返回 `-352`，未称每周内容在线通过；完整来源和端点证据见上述协议记录。测试使用虚构数据和 fake 服务，没有账户写操作。
- 最终 `tool/check.ps1 -SkipPub` 通过（`build/validation/qingwan/fourth-check.log`）：根应用 2142、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2，共 2764 项测试通过；五处格式、静态分析及打包边界脚本通过。mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不能记作原生封装通过。
- Windows Release 构建通过（`build/validation/qingwan/fourth-windows-release.log`），入口 `build/windows/x64/runner/Release/bilisail.exe`，运行时须保留整个 Release 目录。第三方 inappwebview 的既有 CMake CMP0175 开发警告仍存在，不影响本次构建结果。
- 用户在本轮构建期间进一步明确“不需要构建 Android，先只测试 Windows”，因此未执行本轮 Android 构建；磁盘已有 APK 属于第三轮，不能视作本轮交付。未执行 macOS 构建、GUI/实机操作、原生集成测试或性能测量，Windows 手动验收由用户完成。15 份改动 Markdown 本地链接及 `git diff --check` 通过，依赖和锁文件未变；保留既有工作区修改，未提交或推送。

## 第五轮：工具同层、紧凑资料与统一视觉

依据[第五轮方案](fifth-round-plan.md)和用户追加的四项导航图标优化。第四轮的构建与测试数字属于此前源码，本轮结果单独记录。

- 消息、下载、设置进入同一固定根标签，按需保留频道、账号、消息、下载、设置五个分支；一级切换不新增可关闭标签或返回历史。各分支保持自己的筛选、滚动、消息草稿及刷新作用域，私有内容仍随账号 epoch 重建；下载仓储继续为进程级所有者。
- 设置去除通用头像、搜索与工具按钮，分类继续保留。消息/下载不再同时高亮我的；窄屏底部继续提供四个原有主入口。首页、动态、直播、我的采用同组 Material 常态/选中图标，正式品牌图标不变。
- 热门四子标签采用与首页/直播/消息一致的共享视觉参数、图标文字和短指示线，保留现有键盘/滚轮、选期与缓存行为。
- 我的顶部恢复等级、经验/满级信息、细进度、硬币、关注/粉丝/动态；真实数据来自既有 AccountOverview。宽屏横排、窄屏分行，保留登录/退出与加载失败重试；四个内容标签继续直接展示，统计导航使用原有用户主页 section 参数。
- 共享网格窄屏列间距 20→10，推荐/热门/首页内容/历史左右留白 20→12；搜索沿用已有 12px。卡片内容、封面比例、字体及原有列数/大字体断点保持，局部可用宽度驱动布局，不按设备平台分叉。390px 内容区卡宽由 165 增至 178。

### 第五轮验证

- 共享网格与懒列表 17 项自动回归通过（`build/validation/qingwan/fifth-grid-tests.log`），覆盖窄屏间距、局部可用宽度、大字体、桌面列数以及滚动时不重建已挂载卡片。
- 工作区模型、五分支根容器、账号组合及路由 68 项通过（`fifth-workspace-tests.log`）。覆盖从任意根入口首次进入、消息收件人/草稿、下载筛选与初始化一次、设置分类、刷新隔离、账号 epoch，以及双向滚动和查询次数保留。检查中修正了额外 family provider 覆盖导致的重入加载：控制器继续由原 tab 作用域单独持有，分支只负责状态保留与活动/命令隔离，未放宽原查询次数断言。
- 外壳、导航、热门和消息定向 86 项通过，覆盖五类根入口不新增标签、设置工具行隐藏、分类重入保留、窄屏四个入口与消息/下载无错误选中态，以及原热门期数/缓存和消息业务。新旧标签条使用相同 PageTabStyle 参数，主题、滚轮与选中语义保持。
- 账号组件最终 25 项通过（`build/account-profile-summary-tests.log`），使用 `WRITE_UI_PREVIEW=true` 加载实际字体并生成宽屏浅/深色、390 窄屏和 320 双倍字体的离线 PNG；主代理已检查四种布局和收窄后的最终桌面经验条。正常字号资料区宽屏不超过 100px、窄屏不超过 140px，经验条最大 320px；长名单行省略并提供完整 Tooltip，大字体统计改为标签/数字同排以保留内容高度。经验/硬币/三统计、未知与真实 0、导航、失败重试、账号隔离及四内容标签保留回归通过。预览在 `artifacts/account-tabs-preview/`，内容区是测试占位，仅用于资料区布局评估，不是客户端运行或实机验收。
- 首次全量检查定位到资料区测试仅在导出预览时加载正式字体、以及两份首页测试写死旧边距/列间距的预期。资料测试现始终加载正式字体，PNG 开关仅控制导出；默认 25 项通过（`build/account-profile-summary-default-tests.log`）。首页回归同步新的 24px 总留白与 10px 列间距，保留卡片加载数量、16:9、滚动、元信息和缩放不重新加载断言，相关 21 项回归通过（`fifth-page-grid-tests.log`）。没有为通过检查放宽资料区高度或内容可达性要求。
- 最终 `tool/check.ps1 -SkipPub` 通过（`build/validation/qingwan/fifth-check-final.log`）：根应用 2160、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2，共 2782 项测试通过；五处格式、静态分析与打包边界脚本通过。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不能视作原生封装通过。
- Windows Release 构建通过（`build/validation/qingwan/fifth-windows-release.log`），入口 `build/windows/x64/runner/Release/bilisail.exe`，运行时保留整个 Release 目录。第三方 inappwebview 的既有 CMake CMP0175 开发警告仍存在，构建成功。
- 本轮按用户要求仅构建 Windows；未构建 Android/macOS，未运行或操作客户端，未进行实机/native 集成或性能测试。17 份改动 Markdown 本地链接及 `git diff --check` 通过，依赖及锁文件未变；保留此前工作区修改，未提交或推送。最终手动验收由用户完成。

## 第六轮：内容子标签、动态入口与播放窗口记忆

依据[第六轮方案](sixth-round-plan.md)调整，以上历史验证结果不代表本轮源码。

- 热门四子栏目改为左对齐纯文字，和番剧等内容子标签共用 `ContentSectionTabs`：44px 行高、13px 字号、玫红选中文字、浅灰圆角悬停，不带图标和下划线。保留 `RetainedTabView`、周次与排行榜缓存；窄屏选中项仅在不可见时滚入视口，普通数据重建不改变手动横向滚动位置。
- 动态恢复头像与搜索，根页面不增加历史、下载、设置工具。按后续用户要求，首次一级入口默认“动态”子标签，后续保留会话内手动分类选择与显式旧链接；侧栏、底栏和根标签统一使用完整的 RSS 动态订阅图标。
- 桌面双标签的所有媒体继续共用一个播放窗口，新增当前应用会话的正常窗口位置、尺寸记忆。记忆在原生窗口通道实例中，退出清除，无设置/数据库迁移；新窗口挂载前恢复，关闭先保存，再卸载 Flutter view 并销毁原生窗口。
- Windows 保存屏幕坐标的正常窗口矩形，最大化/最小化时读取正常还原位置；进入全屏前捕获，避免全屏边界覆盖。`WINDOWPLACEMENT` 的工作区坐标显式转换后才传给屏幕坐标 API，避免顶部/左侧任务栏造成重复位移，依据 [Microsoft WINDOWPLACEMENT 文档](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-windowplacement)。恢复检查当前显示器工作区，允许负坐标并将已移除屏幕上的窗口放回可见区域。
- macOS 使用同一原生通道中的正常 frame 跟踪器，跟踪拖动、缩放、关闭及系统全屏通知；保存 Cocoa 桌面坐标，恢复到可见屏幕范围。本轮不在 Windows 主机声称通过 macOS 编译或原生运行。
- 恢复、捕获和释放使用 view 与窗口 owner 双重身份，通道等待最多 2 秒；快速重开后，旧窗的保存/关闭事件不再影响新窗。等待恢复时连续切视频复用待创建窗口并补最新标题；全屏捕获后重查窗口存活，外部销毁后延迟释放 notifier，保留原生调用的 idle 时序与先卸载后销毁规则。

### 第六轮验证

- 动态外壳、工作区与双 view 定向 77 项通过（`build/validation/qingwan/sixth-shell-tests.log`）；覆盖两导航模式、窄屏/桌面首次视频动态、显式链接、用户选择保留、头像搜索和统一图标。
- 内容子标签与首页/热门定向 39 项通过（`build/sixth-content-tabs-tests.log`）；覆盖左对齐、选中语义、窄屏滚轮、本地宽度变化、双倍字体及原列表状态。对应定向静态分析通过。
- 窗口适配、WindowService、播放窗宿主和双 view 定向 34 项通过（`build/validation/qingwan/sixth-window-tests.log`），对应静态分析通过（`sixth-window-analyze.log`）。覆盖先恢复后挂载、连续媒体/标题更新、关闭或宿主卸载期间恢复、旧窗迟到事件、原生销毁通知栈、全屏捕获后窗口关闭，以及超时仍保留原错误并释放窗口。
- `tool/test-window-geometry.ps1` 通过：纯 C++ 几何/会话单元测试以 MSVC `/W4 /WX` 编译，验证顶部/左侧任务栏转换、负坐标、显示器移除、超大与非法边界、旧 owner 隔离和新应用实例清空。该程序不创建窗口，不算原生窗口交互或实机验收。
- 最终 `tool/check.ps1 -SkipPub` 通过（`build/validation/qingwan/sixth-check.log`）：根应用 2187、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2，共 2809 项测试通过；五处格式、静态分析和打包边界脚本通过。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不算原生封装通过。
- 最终 `flutter build windows --release --no-pub` 通过（`build/validation/qingwan/sixth-windows-release.log`）；入口 `build/windows/x64/runner/Release/bilisail.exe`，须保留整个 Release 目录。Windows 新增原生代码已随本次构建编译；第三方 inappwebview 既有 CMP0175 开发警告仍存在，不影响构建成功。
- 本轮仅构建 Windows，未启动或操作客户端，未执行 GUI/实机、原生集成和性能测试，也未构建 Android/macOS。实际窗口拖动、关闭重开、最大化/全屏与跨显示器体验由用户手动验收。18 份改动 Markdown 本地链接及 `git diff --check` 通过，依赖与锁文件未变；保留已有工作区修改，未提交或推送。

### 第六轮追加：关闭重开保持最大化

用户进一步要求同次应用运行中记住最大化状态。正常矩形与最大化标志现分开保存，关闭后重开先恢复普通位置/尺寸，再恢复最大化；手动点击还原后，下一次也按普通窗口打开。记忆继续限于原生通道实例，不跨应用启动，不写用户设置。

- Windows 最大化时使用正常还原矩形；恢复顺序为 `SetWindowPos` 普通矩形 → `ShowWindow(SW_MAXIMIZE)`。Flutter 固定 SDK 的控制器在窗口状态事件中同步采样是否最大化，最小化/全屏期间保留此前采样，避免把关闭时的最小化状态当成普通窗口。跨窗口记忆仍只由带 owner 校验的原生 GeometrySession 持有。
- macOS 在正常 frame 之外保存 Cocoa zoom 状态，先设置正常 frame 再 zoom，原有系统全屏隔离与可见屏幕校验保留；本轮 Windows 主机未编译或运行 macOS。
- 纯 C++ 几何单测通过（`build/validation/qingwan/maximized-geometry-tests.log`），新增最大化关闭/重开、还原矩形保持、主动还原、过期 owner 和非法边界不能部分覆盖状态、新应用实例重置。
- 窗口四文件定向 35 项通过（`build/validation/qingwan/maximized-window-tests.log`），新增从最大化进入最小化/全屏后捕获仍保留原标志，恢复普通窗口后正确清除标志；原关闭/重开、prepare、标题更新和 view 生命周期回归继续通过。
- 最终 `tool/check.ps1 -SkipPub` 通过（`build/validation/qingwan/maximized-check.log`）：根应用 2188、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2，共 2810 项测试通过；根与四包的格式、静态分析及打包边界检查通过。10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生封装通过。
- 最终 Windows Release 构建通过（`build/validation/qingwan/maximized-windows-release.log`），入口 `build/windows/x64/runner/Release/bilisail.exe`，运行与分发保留整个 Release 目录。既有第三方 inappwebview CMP0175 开发警告不影响构建。
- 按本次用户范围未启动客户端，未执行实机/native 集成与性能测试，未构建 Android/macOS。正常/最大化切换、关闭重开与实际还原位置由用户手动验收。18 份改动 Markdown 本地链接与 `git diff --check` 通过；无依赖/锁文件变更，保留原有修改，未提交或推送。

### 第六轮追加：排行榜分区左对齐

排行榜内部“全站”等分区标签增加左对齐容器，避免宽窗口中标签总宽度较小时被父布局居中。原有按钮样式、12px 留白、窄屏横向滚动、分区选择与缓存行为保持；这是局部排版调整，无协议或状态模型变化。

- `tool/check.ps1 -SkipPub` 通过（`build/validation/qingwan/ranking-align-check.log`）：根应用 2188、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2，共 2810 项通过，格式、静态分析及打包边界检查通过。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。
- Windows Release 构建通过（`build/validation/qingwan/ranking-align-windows-release.log`），入口 `build/windows/x64/runner/Release/bilisail.exe`，须保留整个 Release 目录。未启动客户端或做实机测试，未构建 Android/macOS，继续由用户手动确认；`git diff --check` 通过，原有未提交修改保留。
