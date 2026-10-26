# 推荐页分页与反馈更新范围优化

日期：2026-10-27。承接[Android 导航对照](android-navigation-reference-comparison-2026-10-26.md)，本轮定位推荐页数据变化牵动的组件范围；实现沿用 Riverpod、保留页面和自然高度懒网格。

## 热点与结构证据

原 [FeedScreen](../../lib/features/feed/presentation/feed_screen.dart) 订阅整个频道 FeedState，网格版本同时包含视频列表和三组反馈 ID。已有缓存能隔离分页等待/失败，但成功追加列表或反馈一张卡会重建当前全部行、卡片及其图片/标题子树。

在修改前运行新增断言，两个用例均失败：

| 受控操作 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 500 条列表、430×860 视口、追加屏幕外第 501 条时现有 VideoCard 重建 | 12 | 0 |
| 第一张卡反馈、完成、撤销、完成时相邻 VideoCard 重建 | 4 | 0 |

计数来自 `debugOnRebuildDirtyWidget`，只表示组件工作量，不是帧耗时。分页重复返回已存在的视频时，仅该卡重新构建并显示新标题；其他卡继续复用。

## 实现与边界

- 页面选择订阅列表、频道、分类、分页状态和当前查询归属。反馈交给 [FeedVideoGrid](../../lib/features/feed/presentation/feed_video_grid.dart) 内各张已挂载卡片，选择订阅自己的 rejected/busy/uncertain 三个值；反馈不再重建分页视口。
- 分页仍更新行委托及条目数量。每个已挂载 tile 只复用一份对应不可变 VideoSummary 的 VideoCard，数据实例/推荐模式/反馈值改变时失效。离开 Sliver 缓存范围后随 tile 释放，未建立全列表 Widget 缓存、扩大 cacheExtent 或增加页面保留数量。
- 卡片动作读取当前 widget 的视频和回调，避免缓存旧登录状态或旧反馈上下文。Theme、文字缩放、工作区可见性、图片和鼠标预览仍通过原有继承状态更新。
- 查询归属是自动分页的必要订阅输入：切回保留频道时，即使列表快照相同，也必须等控制器完成频道选择再启用分页。全量回归发现这一边界后已补入；保留取消和迟到响应隔离。
- 自然高度、两行标题、大字布局、推荐理由、菜单、滚动位置和导航动效均沿用现有行为。本轮没有复制 PiliPlus 源码或资源、改变依赖和网络协议。

## Android Profile 对照

[基准](../../integration_test/android_recommendation_updates_test.dart) 使用真实 router/shell/FeedScreen，300 条初始视频、每次追加 20 条、480×270 固定 PNG 和内存仓储。推荐反馈也只操作 fake 仓储，无真实账号/API/CDN/账号写请求。各路径预热一次后按追加→反馈→撤销循环八轮，共 24 个样本；用 FrameTiming 记录 UI 和光栅耗时。UI buildDuration 包含构建/布局/绘制，不只是 Widget.build；rasterDuration 也不等于 GPU 硬件计时。

```powershell
.\tool\test-android-primary-switch.ps1 -DeviceId <adb-device-id> -Scenario recommendation-updates -Label feed-final
```

脚本先保留普通入口开发 Release，检查 Profile 包名、标签及与 Release 相同的签名证书，使用 `adb install -r` 和 `flutter drive --keep-app-running`。结束时覆盖恢复普通 Release 和临时 USB 常亮设置。输出位于 `build/validation/recommendation-updates-<label>.json` 及同名 APK。原 primary-switch 场景仍是默认值。

设备为小米 13（2211133C / fuxi）、Android 16，报告约 120 Hz；Flutter 3.47.6 / Dart 3.13.5，沿用默认渲染配置，设备日志确认 Impeller Vulkan。最终复测前 Thermal Status 0、电池温度 32.9°C。每个表格值为八次操作中“该次最大帧耗时”的中位数，单位 ms。

| 操作 | 基线 UI | 最终 UI | 基线光栅 | 最终光栅 |
| --- | ---: | ---: | ---: | ---: |
| 分页追加 | 6.32 | 1.01 | 15.85 | 10.38 |
| 不感兴趣 | 6.94 | 2.14 | 14.84 | 11.14 |
| 撤销反馈 | 7.25 | 2.00 | 15.28 | 11.31 |

原始数据：`recommendation-updates-feed-baseline.json`、`recommendation-updates-feed-final.json`。基线使用本轮修改前的推荐源码（`fea84e5`），最终轮补齐查询归属回归；中间轮 `recommendation-updates-feed-optimized.json` 的三类 UI 峰值中位数为 1.07 / 2.41 / 2.25 ms。最终轮全部样本中 UI/光栅最大值为 2.62 / 11.80 ms，基线为 8.16 / 17.53 ms。

这是同一设备固定内容的特定更新路径收益；不代表稳态滚动、底栏切换、冷图片加载或所有设备的 FPS 提升。光栅耗时仍超过约 8.33 ms 的 120 Hz 帧预算，未证明消除所有高刷卡顿。

## 回归与交付

新增/加强 [分页虚拟化测试](../../test/features/feed/feed_virtualization_test.dart) 和 [推荐反馈测试](../../test/features/feed/recommendation_feedback_test.dart)，覆盖追加不重建、同 ID 数据更新、相邻卡/视口不重建、登录状态更新、隐藏频道完成反馈后返回，以及既有反馈失败/结果不明、撤销和大字交互。

- `tool/check.ps1 -SkipPub` 最终完整通过：根应用 2965、bili_api 478、bili_player 83、bili_danmaku 93、bili_mux 5，共 3624 项通过；13 项 Windows 符号链接用例及 10 项未配置 BILI_MUX_LIBRARY 的原生用例跳过，不计为原生集成通过。日志：`build/recommendation-final-check.log`。
- 第一轮全量分析被同期播放文件的 lint 阻塞；同期修复后最终全量分析通过。本任务仅修改推荐页和相关验证文件，未修改播放代码。第一次完整测试发现切回频道续页问题，修复查询归属订阅后定向 23 项及最终全套均通过。
- Android arm64 mux 组件、普通入口开发 Release/Debug、三轮 Profile APK 构建及设备基准成功。普通 Debug 启动后通过 Flutter attach/DTD 热重载成功，运行时错误工具返回无错误；Debug 帧率未用于性能结论。
- 已覆盖恢复普通入口 `BiliSail 测试版` Release（`dev.bilisail.bilisail.test`），确认不含 DEBUGGABLE，启动成功；USB 常亮值恢复为原值 0。正式包及历史 `.primaryswitch` 包未安装、卸载或清除数据。
- 两个脚本的 Dart 分析/格式与 PowerShell 语法、本记录 6 个相对链接、文档索引链接及 `git diff --check` 通过。APK、数据和日志留在忽略目录，不提交二进制。

Windows/macOS 没有本轮新构建与设备性能测量；真实账号网络、不同设备和长期滚动内存验收未覆盖。完整数据、构建与设备日志位于 `build/recommendation-*.log` 和 `build/validation/recommendation-updates-*.json`。
