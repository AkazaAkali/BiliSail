# Android 窄屏底栏切换性能复查

日期：2026-10-26。对象为推荐、动态中的视频动态、我的中的稍后再看。使用当前真实路由、外壳与页面，区分结构回归、设备帧耗时和在线加载；本记录不把 debug 工作次数换算成帧率。

同日后续完成[Android 原生与 PiliPlus 对照](android-navigation-reference-comparison-2026-10-26.md)，增加按实际悬停订阅和去除重复封面裁剪；用户唤醒设备后重试，新的 Profile/Debug 运行及热重载已成功。下文 3495 项检查及安装受限为第一轮记录，后续结果见对照记录。

## 定位与修复

### 隐藏页面受到其他入口的高度变化

窄屏外壳的推荐头部为搜索 52 + 频道 58，动态为频道 58，我的为 0；这些头部在保留页面容器外。公共 `Expanded` 的剩余高度随之变化。Flutter 的 [Offstage](https://api.flutter.dev/flutter/widgets/Offstage-class.html) 仍会布局孩子，因此隐藏列表也收到新约束。问题来源是约束传播范围，并非 `Expanded` 本身慢，亦无证据认定 Flutter 布局框架存在不可避免的性能缺陷。

[RetainedPageLayout](../../lib/shared/ui/retained_page_layout.dart)置于根分支与首页频道组的 `Offstage` 内，隐藏时向孩子传递最后可见的约束，显示和返回预览时采用当前约束。脏的 Provider/账号内容仍可以布局更新；不把隐藏子树冻结为旧账号快照。边界不复制页面、不扩大页面数量，也不设置固定屏幕尺寸。窗口、键盘或横竖屏变化后，显示页面必须按当时的约束布局。

原始 390×844 外壳测试中，推荐到视频动态使一个保留列表从 390×682 变为 390×734；修复后的热切换保持各列表原有高度、`ScrollPosition` 身份及偏移。额外的分支 `RepaintBoundary` 未呈现稳定收益，最终没有加入；不创建整页截图缓存。

### 嵌套 family 覆盖导致额外首屏读取

完整路由基准还发现：预热后的 24 次切换让视频动态首屏读取从 1 增加到 17，稍后再看保持 1。仅测试裸 `FeedScreen` 无法覆盖这个问题。

`homeControllerProvider` 同时在工作区和账号内容列表被覆盖，但原来未声明作用域。当前锁定 Riverpod 3.4.3 的 `ProviderPointerManager.from` 对未声明 scoped dependencies 的 family 可以沿用同一 family directory；嵌套覆盖会改变后续查询的目标容器。观察器确认：视频动态 Widget 仍在首页容器，后续读取却在稍后再看的容器创建查询，随后因无监听而销毁；再次读取又初始化。

[HomeController](../../lib/features/feed/application/home_controller.dart)以 `dependencies: const []` 明确声明可被作用域覆盖，使嵌套容器分开持有 family directory。修复后同一基准不新增推荐、视频动态和稍后再看的读取；保持账号 epoch、关闭取消和查询容量上限。没有改动 Pub 缓存或升级 Riverpod。

### 活动状态与页面构建分开

[路由](../../lib/app/router.dart)使用独立的小组件更新页面快捷键注册，避免上层 `Builder` 因 `WorkspaceActivity` 通知重新调用内容工厂。[账号页](../../lib/features/auth/presentation/account_screen.dart)将活动、焦点、Ticker 门控与稳定内容 Widget 分开；实际构建配置变更仍更新内容，不保留旧登录回调。

### 图片的无效可见性工作

[AppNetworkImage](../../lib/shared/ui/app_network_image.dart)不再因 URL、解码尺寸及显示尺寸均未改变的 Widget 更新扫描滚动祖先并安排几何检查。滚动祖先状态按 Element 生命周期保留，重新挂载时清理；位置对象更换仍通过依赖通知更新监听。视口链保留结构，像素坐标每批重新读取。隐藏图片移除待检查项，并停止新几何检查；恢复、滚动、布局及窗口尺寸变化仍触发检查。已解码流在图片配置未改变的 TickerMode 切换中只更新监听，不重复解析源。

保留嵌套视口裁剪、滚动离屏释放、重挂载恢复、请求取消、队列重试、账号缓存隔离和动画图片的暂停语义。没有通过无限保留解码图片换取切换速度。

## 可复现验证

[组件回归](../../test/app/primary_switch_layout_test.dart)使用真实 `createBiliRouter`、窄屏外壳、FeedScreen 和 AccountScreen，覆盖三类列表的预热切换、尺寸与滚动位置保留、零额外读取，以及 320/599/600/960/390 宽度变化后的可见布局。另有[约束边界回归](../../test/shared/ui/retained_page_layout_test.dart)与[图片回归](../../test/shared/ui/app_network_image_visibility_test.dart)。

[设备基准](../../integration_test/android_primary_switch_test.dart)使用每类 300 条 fake 数据、480×270 PNG 封面、内存图片传输，无真实账号、API、CDN或账号写操作。推荐保留 300 条，视频动态按原规则最多保留 200 条；卡片按视口懒创建。预热三页后按视频动态→稍后再看→推荐循环八轮，采集 24 次切换的 `FrameTiming.buildDuration` 和 `rasterDuration`。这里的 buildDuration 是 UI 帧流水线耗时，包含构建、布局、绘制，不等于单独 Widget.build 的耗时。

Windows 连接 Android 后执行：

```powershell
.\tool\test-android-primary-switch.ps1 -DeviceId <adb-device-id>
```

本记录早期测量使用 `.primaryswitch` 独立包名。2026-10-26 后续按用户要求统一为 `.test`（BiliSail 测试版），普通开发 Release 与性能 fixture 共用身份；先校验 APK，再用 `adb install -r`，失败即停止。驱动带 `--keep-app-running` 防止默认卸载，结束后恢复普通 Release；规则见 [开发测试别名](ci-cd.md#android-本地开发测试别名2026-10-26)。输出 `build/validation/primary-switch-<label>.json` 和同名 APK。正常启动、冷热网络、真实账号列表与不同 GPU/设备仍需另测，不能把这套固定图片基准推广为全部 Android 设备的体验保证。

## 设备结果与边界

设备为小米 13（2211133C / fuxi）、Android 16，1080×2400、density 440；运行时报告约 120 Hz。Profile 使用当前 Flutter 3.47.6 / Dart 3.13.5。以下每个值是该入口八次切换中“每次最大 UI 帧耗时”的中位数，单位 ms；最终列来自补核图片配置边界后的最终 arm64 APK。

| 目标入口 | 修复前 | 最终代码 |
| --- | ---: | ---: |
| 推荐 | 21.78 | 16.24 |
| 视频动态 | 14.97 | 12.33 |
| 稍后再看 | 24.64 | 15.20 |
| 全部 24 次切换 | 20.89 | 13.32 |

视频动态读取在修复后各轮基准中均保持 1 次，其他列表也无新增读取。完整原始数据为 `build/validation/primary-switch-baseline.json` 和 `primary-switch-final.json`，最终包为 `primary-switch-final.apk`，日志为 `build/primary-switch-device-final.log`。此前两次复测另存 `primary-switch-verified-run1.json`、`primary-switch-verified.json`；24 次切换的 UI 峰值中位数分别为 15.24 / 10.40 ms，存在运行间波动。受控基准显示部分 UI 恢复工作减少，不能给出稳定的整体 FPS 提升比例。

光栅线程没有稳定改善：24 次切换的光栅峰值中位数，基线为 17.85 ms，最终轮为 21.28 ms，其他复测为 18.31–22.33 ms。最终轮 UI/光栅最高耗时为 32.01 / 38.38 ms；另一轮 UI 还记录到 49.70 ms，不能宣称最坏帧已收敛。最终轮采集到 487 帧，其他两轮 487/491 帧，基线 628 帧，不能直接按超过预算的帧数做同比。设备第二轮前电池温度 32.6°C、Thermal Status 0；这不能排除调度、刷新节奏、GPU 缓存或其他运行时差异。120 Hz 的单线程预算约 8.33 ms，当前仍有超预算尖峰，不能宣称已消除高刷卡顿，亦不能把剩余光栅尖峰直接归因于布局框架。

补测 `flutter drive --enable-impeller` 后，原生日志确认默认构建（PID 11324）及显式开启（PID 12211）均为 `android_context_vk_impeller.cc` 的 Impeller Vulkan。这并非两种后端对照。显式开启轮仍有 35.86 / 35.74 ms 的 UI/光栅峰值，未找到能通过这个开关解决尖峰的证据；未改动默认渲染后端。日志为 `build/primary-switch-device-impeller.log`，数据为 `build/validation/primary-switch-impeller.json`。

基准使用固定内存图片，未覆盖真实账号网络、CDN、首次图片下载和复杂动态正文。原生 mux arm64 组件重建成功，未改动播放器/弹幕实现；不将组件打包或单台设备运行推导为跨设备播放性能验收。

## 自动检查与交付状态

- `tool/check.ps1 -SkipPub` 完整通过：根应用 2854、bili_api 460、bili_player 83、bili_danmaku 93、bili_mux 5，共 3495 项通过。根应用 13 项符号链接用例因 Windows 权限限制跳过；mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。日志：`build/primary-switch-complete-check.log`。
- 最后补核图片位置对象更换和已缓存流显示尺寸更新后，29 项图片/真实外壳定向测试及图片源码静态分析通过，日志：`build/primary-switch-image-final.log`。另一次完整路由、账号、保留根页、图片与尺寸回归共 135 项通过，日志：`build/primary-switch-final-regression.log`。
- 新复测脚本 PowerShell 语法、专项文档 9 个相对链接与 `git diff --check` 通过。首轮总检查曾被同期播放器文件格式/lint 阻塞；该文件由同期工作更新后，最终全量检查通过，本任务没有修改该文件。
- Android Profile 构建和设备基准通过；正常入口的 Android Debug APK 构建成功，设备安装返回 `INSTALL_FAILED_USER_RESTRICTED`，未重复绕过限制。DTD 未发现可连接应用，热重载尝试未能完成。未进行 Windows/macOS 新构建、真实账号联网和长期性能验收。
- 修改随本轮开发测试包配置一并提交，未推送；未修改相邻参考仓库或依赖版本。

保留现有 220 ms 不透明平移动效和减少动画适配，不增加整页透明度或尺寸补间。首次网络加载可以用保持最终卡片尺寸的轻量占位表达等待；已访问列表继续显示原内容。动画无法让同一 UI 线程上的长任务消失，不能承诺用更长动画掩盖所有掉帧。

本轮第一次设备启动前未核对签名，Flutter drive 自动卸载了设备原正式包；原本地数据可能丢失。后续验证改为独立包名，并成功重新安装本机已有的正式 APK（1.2.1，versionCode 12100）；这是现有正式构建，不含本轮代码修改，也不是原安装数据的快照。重新安装不能恢复已清除的原应用数据。
