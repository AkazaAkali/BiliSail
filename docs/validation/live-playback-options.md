# 直播清晰度与线路选择

日期：2026-10-11。本轮补齐直播播放器的清晰度、自动档和主备线路入口，复用同一 `PlaybackSession` 与原生播放器。

## 界面与行为

- 普通宽屏和全屏的清晰度按钮打开两层菜单：第一层顶部显示当前线路，其下为允许的清晰度与“自动”；点击顶部进入主线、备线列表，再次点击顶部返回。当前项以粉色显示。
- 窄窗口在“更多播放选项”内提供清晰度、自动档与直播线路。即使仅有一个清晰度，也保留直播配置入口。
- 清晰度名称优先读取 `g_qn_desc[].media_base_desc.detail_desc.desc`，没有时回退到 `desc`。可选项取实际选中协议／格式／编码的 `accept_qn`，不把其他编码或流的清晰度合并进当前菜单。
- “自动”发送 `qn=0`，由服务端决定本次打开的清晰度；当前实际清晰度仍记录为 `current_qn`。本轮不实现官网浏览器播放器的动态自适应码率或 P2P 策略。
- 切清晰度保留当前线路序号；切线路重新读取当前清晰度的短期播放地址。保留音量与用户的播放／暂停意图，直播始终从直播边缘打开，不 seek、不读取或保存点播续播进度。
- 切房间重置主线，隐藏／返回同一播放 owner 保留配置。账号 epoch、源 generation、取消与关闭状态共同隔离迟到解析；打开中的菜单也不能将旧选择应用到新源。
- 线路消失或原生打开失败时，回退至实际可用线路并更新选中状态、提示原因；同次解析最多尝试两次原生打开。服务端返回低于请求的清晰度时展示实际档位，并在手动重开时提示。

## 协议与“线路”的含义

沿用 Web profile 的 HTTPS GET `api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo`，Cookie 可选、无 App token 或账户写操作。参数为 `room_id`、`qn`、`protocol=0,1`、`format=0,1,2`、`codec=0,1`、`platform=web`。本轮增加 TS 格式查询与 `qn=0`；继续选择已有后端支持的 AVC/H.264，优先 HLS、其次 HTTP-FLV。

先选择 `stream[].protocol_name → format[].format_name → codec[].codec_name` 对应的流，再将该流的 `url_info` 按响应顺序作为主线、备线1、备线2……。播放地址仍由 `host + base_url + extra` 构成，不重写签名、域名或查询参数。线路与点播 `MediaCdnPreference` 独立，不经过点播 CDN 排序，也不将不同协议／编码混成备线。签名地址只在当前播放会话内存中使用，诊断只输出流类型、清晰度和数量。

取消、账号隔离、25 秒请求 deadline 与有界只读重试继续使用现有 `ApiRequests`／`BiliApiClient`；原生请求使用直播 Referer/UA，系统 TLS 验证保持原行为。

## 参考来源

仅核对协议和行为，自行编写 Dart／Flutter；未复制参考仓库源码、schema、样式、图片或官网 JavaScript，未添加依赖。

- [biliuwp PlayerAPI.LivePlayUrl](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/PlayerAPI.cs)：Web v2 播放接口与 `qn`。
- [biliuwp LiveRoomViewModel.GetSpecialPlayUrls](../../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Live/LiveRoomViewModel.cs)：先按 `http_hls`／`http_stream` 分流，取 AVC 的 `accept_qn` 与 `url_info`；[LiveDetailPage](../../../biliuwp-lite/src/BiliLite.UWP/Pages/LiveDetailPage.xaml.cs) 将用户选择交给 `SelectedRouteLine`。
- [bili-kernel PlayerClient](../../../bili-kernel/src/Services/Services.Media/Core/PlayerClient.cs)、[LiveAdapter](../../../bili-kernel/src/Services/Services.Media/Core/Adapters/LiveAdapter.cs)：协议／格式／编码的分层，以及流内可用清晰度和完整地址。
- 实际查看[官网直播间](https://live.bilibili.com/blanc/6650029)的两层菜单、粉色当前项与自动档，并观察切换 720P 发出的 `qn=250` 请求。官网请求包括 `format=0,1,2`、`codec=0,1,2`、`ptype=8`，并使用 WBI 签名。本项目沿用 biliuwp 与现有客户端已在线验证的未签名 Web 读取，不将官网的 DRM／HDR／P2P 参数直接加入请求。
- 读取官网当时发布的 [Room Player JavaScript](https://s1.hdslb.com/bfs/blive-engineer/live-web-player/room-player.prod.min.js)，播放器版本 `3.11.9-5177126f`：`getLineCandidates` 固定提供四个编号，`setCurLine` 按实际候选地址数量取模；因此四个菜单编号不保证四个独立地址。本项目按实际返回的线路数量展示，与 biliuwp 的映射一致。

## 验证边界

- `tool/check.ps1 -SkipPub` 通过：根应用 1869、bili_api 390、bili_player 51、bili_danmaku 86、bili_mux 2，共 2398 项测试通过；格式与静态分析全部通过。bili_mux 的 7 项原生合并测试因未设置 `BILI_MUX_LIBRARY` 跳过；安装包／签名／版本脚本检查通过，未生成安装包。文档相对链接与 `git diff --check` 通过。
- 协议测试覆盖 `qn=0`、流级 `accept_qn`、完整清晰度名称与主备地址顺序；Repository 测试覆盖 AVC HLS 选择、其他编码／格式清晰度隔离、直播请求头和 CDN 偏好独立性。
- 会话测试覆盖清晰度与线路换源、暂停／音量保留、自动档、线路缺失与原生失败回退、无 seek／点播进度写入，以及切房间／账号 epoch／关闭期间的迟到响应。
- Widget 测试覆盖宽窄窗口、普通／全屏、两层菜单、自动档和动态控制栏在菜单打开期间保持可操作。
- 游客在线读取房间 `6650029`，`qn=0/250/400/10000` 均成功，响应流级清晰度为 `[10000,400,250]`、每个组合两条地址；实际 `current_qn` 均为 250，验证了游客高档位请求的服务端回退与完整名称“720P 超清”。此结果不代表登录后高档位播放验收。
- 本轮按用户要求仅运行检查，不构建或执行原生实机验证；Windows／Android／macOS 的实际切换出帧、音频连续性与直播延迟，留待用户手动构建验收。
