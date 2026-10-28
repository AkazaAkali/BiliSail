# 手机物理旋转与全屏

关联：[#22](https://github.com/CKopoer/BiliSail/issues/22)。本改动仅处理播放页方向行为，不调整全站留白或导航布局。

## 行为与范围

- 手机横向视频：系统允许界面转横、设备物理横持时进入全屏；物理转竖退出全屏，回到原播放页。共用原有 PlaybackSession、全屏路由和唯一视频 surface，不重开媒体，不重置详情/评论状态。
- 真正竖视频点击全屏保持竖向、隐藏详情，不经过横向过渡，也不使用横视频的横持进入/转竖退出逻辑。普通视频页在手机竖向时按真实视频比例增加内嵌高度，上限为可用高度65%，仅尺寸变化重建布局；横向源、桌面/平板及PGC/直播布局保持。源内自带黑边不裁切；以播放器报告的真实视频尺寸判断。
- 竖持点击全屏仍使用已有视频比例方向锁（横视频转横，竖视频保持竖屏）。竖持手动进入后，初始物理 portrait 不是“转竖”：须先横持再转竖，避免刚进入立即退出。
- 横持时手动退出恢复竖向详情；临时竖屏限制在设备回竖时释放，不提供“保持横屏详情直到再次转动”的模式。离开页面、后台、传感器失败与异步取消也释放该临时限制。
- 只在活动前台播放页、横向视频且手机全窗口内自动切换；未知视频尺寸、竖视频、平板、折叠屏铰链/展开大屏、Android 分屏/PiP、后台、隐藏标签及桌面不自动进入。既有手动全屏功能保留。
- Android 读取系统自动旋转开关，不修改系统设置。iOS 没有公开方向锁查询，故两端自动进入都额外要求未全屏界面已横向；界面方向只是进入许可，不能作为物理转动证据。

## 实现选择

`SystemChrome.setPreferredOrientations` 会把窗口锁横，`didChangeMetrics` 无法再证明用户物理转竖。因此新增应用自有小型 EventChannel `bilisail/device_orientation`，不引入传感器依赖、不新增权限：Android 使用 `OrientationEventListener`（轴附近稳定区和未知姿态），iOS 使用 `UIDevice.orientationDidChangeNotification`。事件包含物理姿态、系统自动旋转许可及设备/窗口资格。

Flutter 由可注入的 `deviceRotationProvider` 共用广播流；仅可见前台播放页订阅。纯 Dart `FullscreenRotation` 保存物理方向历史。平台命令沿用既有 owner 串行队列，迟到平台回复再次检查页面和姿态，防止退出、隐藏或重新进入时遗留方向锁。手动退出允许 `WindowService.setFullScreen(false, orientation: portrait)`，后续 null 请求释放本服务安装的限制。

## 验证

2026-10-28，dot Linux 云构建机，Flutter 3.47.6 / Dart 3.13.5：

- `flutter test --no-pub test/features/playback/fullscreen_rotation_test.dart test/features/playback/playback_panel_test.dart`：294项通过；随后新增的竖视频传感器序列用例单独通过，合计295项。
- `flutter test --no-pub test/core/platform/window_service_test.dart`：17项通过，4项Windows专属跳过；覆盖横全屏→竖屏退出→释放限制→重复释放不再改方向。
- `flutter test --no-pub test/features/video/inline_video_height_test.dart test/features/video/video_screen_test.dart`：54项通过；最后简化维度订阅后新portrait用例再次通过。
- 新增/修改Dart文件格式检查、定向静态分析与 `git diff --check` 通过。
- `tool/check.ps1 -SkipPub` 已完成全仓格式、静态分析、平台边界脚本及根应用3252项测试（5项平台专属跳过）、bili_api 495项、bili_player 83项、bili_danmaku 116项。旧检查进程在最后mux阶段被环境安全策略拦截遥测请求，不能宣称整脚本通过；随后在官方禁遥测配置下直接重跑mux：5项通过，10项原生用例因未配Linux原生库跳过。检查启动后的最后新增/精简改动另有上述定向复验。
- 提交此草案时，本分支Android独立构建尚未完成；包含本功能、观看历史搜索和间距调整的集成测试包另行构建，不把集成构建冒充本分支独立构建或实机验收。

Android/iOS 真机尚未验证；iOS构建未运行（Linux无Xcode）。自动化测试不等于传感器、系统方向锁、系统手势、视频纹理旋转和软键盘的实机验收。

设备验收应覆盖：Android/iPhone 自动旋转开关；竖→横→竖连续多轮；竖持手动全屏；横持退出后回竖；转动时打开弹层/输入法；后台前后及导航切页；竖视频；平板/折叠/分屏；播放位置、暂停意图、评论滚动位置与单路音频。
