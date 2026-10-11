# 稍后再看队列播放

日期：2026-10-07，删除入口更新于 2026-10-11。视觉依据为用户提供的官方客户端截图和已安装 Windows 客户端的只读观察；Flutter 组件、图标与排版独立实现，未复制参考仓库代码或资源。沿用项目现有 Web 会话 `/x/v2/history/toview` 读取；当前 `HomeClient` 一次读取 `data.list` 并返回 `hasMore: false`，“未看完”在该结果上过滤。播放页删除复用已有 `/x/v2/history/toview/del`，无新增端点。

## 入口与队列

稍后再看两个子标签的卡片保留标题菜单“删除”，封面悬停时不显示“添加稍后再看”；其他页面仍显示该入口。点击卡片时捕获该子标签当前可播放条目的有序快照，跳过缺失合法 BVID 的失效条目。单个快照最多 1000 项，超过预算的条目仍可普通打开，但不进入队列；当前接口无分页，快照来源是本次完整读取结果。队列只在进程内保存，路由携带带随机实例前缀的不透明 ID，不写入持久存储。快照预算为 16 个，超出时优先淘汰空闲快照；打开的播放标签持有快照直到退出或改为普通视频。账号 scope 或会话 epoch 变化立即拒绝旧队列，账号状态变化还清理内存快照。

队列按列表原顺序。2026-10-11 起自然结束推进受设置中的“连续播放”控制，默认关闭，见 [连续播放与下一集](continuous-playback.md)。开启时先播放当前视频下一 P，最后一 P 才进入队列下一条；上一/下一 P 控件或快捷键跨当前视频边界时跳到相邻队列视频。合集仍在简介中供用户显式浏览，不改变稍后再看顺序。点击队列条目沿用当前暂停/播放意图；自然结束推进时从下一项零点继续播放。最后一条结束后停在结束状态，不循环。普通推荐、合集或独立视频链接不继承队列。

队列展开时右侧约 380 逻辑像素侧栏由约 48 像素常驻标题和独立滚动列表占据；收起时标题仍在简介/评论上方。条目显示封面、时长、标题、UP、播放数、弹幕数，当前条目按主题色强调；切换视频后列表将当前项滚到可见。侧栏宽度和项目字体缩放决定封面及行高，窄窗和大字号保留文字空间。条目点击、边界跳转与自动推进更新现有播放标签，播放器对象由该标签的 `PlaybackSession` 持有；页面等待新详情时保留旧播放器 owner，源解析仍由原有 source generation 取消旧结果。多标签允许并发时，隐藏的队列标签继续推进且不抢当前标签焦点；单标签互斥仍由 `PlaybackManager` 决定。

## 折叠状态与动效（2026-10-11）

原先展开队列会移除简介／评论子树，导致 UP 主信息的自动释放 Provider 销毁；再次收起队列时重发请求，粉丝数和关注状态短暂回到加载值。现在 [队列面板](../../lib/features/video/presentation/watch_later_queue_panel.dart) 在首次收起时才挂载详情，此后用 Offstage 保留详情、UP 主状态、已访问的评论页及滚动位置。隐藏详情通过 WorkspaceActivity、TickerMode、指针／焦点／语义隔离停用交互与悬停预览；账号变更仍由原有控制器和队列 scope／epoch 边界处理，关闭页面照常释放。

标题始终位于同一位置，箭头旋转与内容淡入淡出、约 4% 高度位移持续 180 毫秒。动画只更新侧栏绘制，固定列表视口不随动画改变尺寸，播放器位于动画外；使用 RepaintBoundary 隔离绘制。队列仍按视口懒创建，退出动画结束后卸载列表卡片并释放图片需求。系统关闭动效时直接切换，快速连续点击可从当前进度反向过渡。

队列播放数和弹幕数使用与 [公共视频卡片](shared-video-cards.md)、[直播卡片](live-card-count.md) 相同的 `compactCountLabel`：原始数字和十进制文本按万／亿缩略，空白文本回退领域模型数值，保留已有缩略文字；真实 0 和缺失计数分别显示 0 和横杠。不改变接口及领域模型。

回归覆盖宽／窄屏反复折叠后 UP 主仅读取一次、Provider 和简介滚动状态保留、关闭时取消、动画期间播放器不逐帧重建、快速反向切换、关闭动效、1000 项队列的懒创建及计数边界。此为 widget／结构验证，未据此推导真实设备帧耗时。

本轮 `tool/check.ps1 -EnforceLockfile` 在原有固定依赖上完整通过：根应用 1853 项、bili_api 390 项、bili_player 41 项、bili_danmaku 86 项、bili_mux 2 项，共 2372 项；各项目格式检查与静态分析通过。bili_mux 的 7 项原生测试因未设置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/watch-later-sidebar-pinned-check.log`。未修改原生播放，真实账号界面及 Windows／Android／macOS 实机帧耗时未验证。

本轮重新生成并检查 `build/watch-later-page-preview/light-folded.png`、`dark-expanded.png`、`narrow-large.png`，确认折叠标题、暗色列表、360 像素两倍字号布局无溢出；使用脱敏手写数据和封面占位图。

## 验证边界

2026-10-11 播放页队列的非当前播放条目右下角显示垃圾桶图标和“删除”按钮；当前播放项不显示。快照保留原始条目 ID 和字符串 `aid`，按钮通过已有 `WatchLaterRemovalController` 显式删除，不触发视频切换。请求期间禁用按钮并显示等待状态，确认成功后同步移除播放队列及“全部／未看完”列表中的条目，计数、上一／下一视频和连续播放使用同一份过滤结果；原快照保持不可变。其他页面移除当前视频时，播放页暂时保留当前源作为导航锚点，切换后将其过滤，不中断播放。

失败保留条目并提示原因；结果不明时提示刷新核对，不自动重放写请求。沿用共用卡片添加／删除互斥端口，避免同时添加与删除同一视频。账号 scope、会话 epoch 或队列变化隔离迟到提示；账号会话失效时由已有 provider 清理取消请求。自动测试覆盖成功、失败、结果不明及同账号 epoch 改变、原始 `aid` 精度、两个首页子列表同步、按钮不导航、播放器实例保留，以及亮／暗主题和窄窗两倍字号布局。真实账号删除及 Android/macOS 设备交互未验证。

本次 `tool/check.ps1 -SkipPub` 通过：根应用 1841 项、bili_api 390 项、bili_player 41 项、bili_danmaku 86 项、bili_mux 2 项，共 2360 项；各项目格式检查与静态分析通过。bili_mux 的 7 项原生测试因未设置 `BILI_MUX_LIBRARY` 跳过。本次日志为 `build/watch-later-removal-check.log`；按钮预览位于 `build/watch-later-queue-preview/dark-expanded.png` 和 `narrow-large.png`，已检查位置、主题和大字号布局。

定向测试覆盖队列顺序、账号/epoch 隔离、旧 ID 防碰撞、快照上限与活动标签保留、自然结束分 P/下条单次推进、尾部停止、显式切换保留暂停、折叠/滚动/条目点击、封面入口范围，以及主题和窄窗大字号无布局溢出。整页视觉预览位于 `build/watch-later-page-preview/`，覆盖亮/暗主题、展开/收起和 360 像素两倍字号；使用手写脱敏数据、封面占位图和项目字体，不代表真实账号内容。Android/macOS 和真实账号写操作未在此项执行。

账号状态变化使路由重新读取 registry 并移除旧列表；待消费的播放意图也记录账号/epoch，停止会话时清除。两个首页子标签的入口回归确认点击后保留完整有序列表、跳过失效 BVID 且沿用原计数字段；后台导航回归确认推进不改变当前活动标签或增加浏览历史。

`tool/check.ps1 -SkipPub` 完整通过：根应用 881 项、bili_api 269 项、bili_player 22 项、bili_danmaku 32 项，共 1204 项；根与各包格式检查、静态分析均通过。日志为 `build/watch-later-queue-check.log`。

## Windows 原生验收

使用本地 12 秒 DASH 音视频分轨夹具及原生 `MediaKitEngine`，`integration_test/windows_watch_later_queue_test.dart` 通过：暂停状态点击队列保留暂停，展开/收起不改变 source generation，隐藏页面后 A1→A2→B 自动继续播放，尾部停止，以及末尾显式重播回到零点且不重建源。新详情读取人为延迟 150 毫秒，验证加载间隙仍保留同一播放会话。

验收中发现原生 EOF 之后的 `playing=false` / `buffering=false` 事件会覆盖结束状态，导致队列漏掉结束信号。`MediaKitEngine` 现保持结束状态直到显式 seek/play 或换源；末尾等待及显式重播断言覆盖此行为。

`tool/test-windows-media.ps1` 本地回归通过：原有播放测试 8 项，诊断测试 1 项，包含分轨解码、seek、切换清晰度/分 P、暂停意图、进度恢复、全屏和脱敏 HTTP 失败诊断。未启用在线 smoke。真实账号的完整队列播放、Android/macOS 构建与设备体验尚未验证。

`flutter build windows --release --no-pub` 成功，产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志为 `build/watch-later-queue-windows-build.log`。既有 WebView 插件 CMake 开发警告不阻断构建。没有替换用户运行中的已安装客户端。
