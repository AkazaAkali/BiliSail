# 宽屏侧栏样式与收起

日期：2026-10-27。

## 行为

- 设置 → 外观 → **导航栏模式**：提供“自动”“底栏”“侧边栏”，默认自动。自动模式按安全区内可用宽度切换：小于 600 逻辑像素使用底栏，达到 600 使用侧栏；手动模式固定使用所选位置，不随窗口宽度切换。
- **侧栏样式**提供“随窗口宽度”“完整侧栏”“图标文字上下”，在侧栏布局时生效。默认仍在 1600 起展开为 164 宽完整侧栏，其余使用 76 宽导航轨；手动固定侧边栏时窄窗口也可使用这两种样式。切换底栏不覆盖样式或收起状态。
- 宽屏顶部左侧放置圆角描边的菜单／箭头按钮，浅色与深色均使用当前主题颜色，提供“收起侧栏／展开侧栏”提示。按钮在侧栏完全收起后仍留在原位；复用桌面标题栏或多标签栏，没有这些栏时显示 40 高工具栏，避免遮挡页面、搜索及播放操作。
- 收起／展开使用 240ms `easeInOutCubic` 宽度和透明度过渡，内容区及左留白同步调整，按钮图标轻微旋转。侧栏内部保持完整布局宽度并裁剪，避免文字在收起过程中挤压折行。快速反向点击从当前宽度继续；系统减少动画时立即到位，进入窄屏也立即让出空间。
- 收起期间侧栏停止接收指针、键盘焦点和无障碍导航；完全收起后不绘制侧栏。内容页保持同一组件树，不复制页面、播放会话或数据请求。主导航、消息／下载／设置的底部布局和短窗口滚动沿用现有实现。
- `AppSettings.sidebarStyle/sidebarCollapsed` 经设置控制器立即应用并串行保存，失败回退已保存配置并提示。`preferences.v1` 版本化快照追加两个字段，无数据库表变动；缺失／非法字段分别回退为自动、展开，保留其他合法旧设置。恢复默认同时恢复自动样式与展开状态。缩窄窗口不覆盖宽屏偏好。
- `AppSettings.navigationBarMode` 沿用同一保存／回退流程，快照版本从 27 增至 28，数据库版本保持 3。旧快照缺失或非法模式回退自动，恢复默认也回到自动；有效设置继续保留。直播归组和首页频道仍按页面宽度判断，窄屏固定侧栏不重复显示独立直播入口。Android 预测式返回动画和“返回播放／回到播放页”入口随实际底栏／侧栏布局选择。

## 导航栏模式验证（2026-10-27）

- [模式与路由组件回归](../../test/app/navigation_bar_mode_test.dart)覆盖 320／599／600／1280／1600 宽度、三种导航栏模式与侧栏样式组合、组件身份和输入草稿保留、收起偏好保留、三种页面导航模式下即时保存／重新加载／失败回退，以及 Android 返回动画和安全区下返回播放入口。
- [设置持久化回归](../../test/features/settings/navigation_bar_mode_test.dart)覆盖默认自动、复制／归一化、旧快照和非法字段回退、全部模式往返及恢复默认；原设置页回归增加了控件滚入视口的操作，适配新增选项后的页面高度。
- 受影响的 11 个 Dart 文件格式检查和静态分析通过，模式／侧栏／布局／预测返回／设置回归共 258 项通过，日志 `build/navigation-bar-mode-regression-final.log`。四包测试共 659 项通过；10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，日志 `build/navigation-bar-mode-package-tests.log`。
- 共享工作区的 `tool/check.ps1 -SkipPub` 在同期推荐设置代码格式检查处停止；另行执行根测试为 3137 项通过、13 项符号链接权限相关跳过、1 项设置分类连续滑动失败。失败来自同期新增推荐分类后仍断言原分类顺序，未修改该任务的分类逻辑；日志 `build/navigation-bar-mode-check.log`、`build/navigation-bar-mode-root-tests.log`。本次全量检查不记为通过。
- 以已提交源码加本任务差异导出独立源码快照，离线解析依赖后复测新增模式和设置滑动，共 17 项通过，包含共享工作区失败的连续滑动用例；日志 `build/navigation-bar-mode-snapshot-tests.log`。提交仅包含本任务差异，保留同期其他工作区修改。
- 本轮未进行平台构建、设备操作或性能测量；组件回归不代表实际设备手感验收。

## 验证

- [侧栏组件与真实路由回归](../../test/app/sidebar_test.dart)：浅／深主题、放大文字、599／600／1280／1600 宽度、两种排列方向、连续反向、完全收起后入口、宽窄往返、草稿和组件身份保留、减少动画中途启用；单／双／多标签设置即时应用、保存／失败回退及重新加载。
- [设置仓储](../../test/features/settings/sqlite_settings_repository_test.dart)：旧快照、非法字段、全部样式与两种收起状态往返；[设置页面](../../test/features/settings/settings_screen_test.dart)验证恢复默认；[外壳布局](../../test/app/shell_layout_test.dart)继续覆盖底栏、短窗口工具入口和内容保留。

- 本次 11 个 Dart 文件的格式检查与定向静态分析通过；三个文档共 55 个相对链接及 `git diff --check` 通过。使用真实 shell、主题和字体生成浅／深色的完整、紧凑、收起共六张组件渲染图，内容使用本地占位数据，未请求账号或网络；图像位于本地 `build/sidebar-*.png`。
- `flutter test --no-pub --concurrency=1 test/app/sidebar_test.dart test/app/shell_layout_test.dart test/app/workspace_shell_test.dart test/features/settings test/features/video/video_comments_controller_test.dart`：369 项通过，日志 `build/sidebar-regression-final.log`。包含侧栏全部路径、设置回归及同期评论输入失败项的复测。
- `tool/check.ps1 -SkipPub -Stage PackageTests`：bili_api 478、bili_player 83、bili_danmaku 93、bili_mux 5，共 659 项通过。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成验证；日志 `build/sidebar-package-check.log`。
- 已运行 `tool/check.ps1 -SkipPub`：格式、分析及平台打包边界检查在该次运行通过；根应用 2992 项通过、13 项跳过，6 项同期新增评论 Enter 测试失败，后在上述 369 项回归中全部复测通过。未将这次全量脚本报告为通过，日志 `build/sidebar-check-final.log`。
- 后续全量 Lint 阶段遇到同期新增的 `test/shared/ui/retained_scroll_activity_test.dart`、`test/shared/ui/video_card_content_reuse_test.dart` 格式问题；最新全量分析另在后者第 46 行报告 `curly_braces_in_flow_control_structures`。保留这些独立任务文件，未为凑全量检查修改它们；日志 `build/sidebar-lint-final.log`、`build/sidebar-analyze-final.log`。

本机 DTD 未发现运行中的 Flutter 调试实例，热重载无可用连接。未进行新的平台构建、Windows／Android／macOS 实机操作、屏幕阅读器或 Profile／Release 动效帧耗时验收；组件渲染和行为测试不能替代这些验收。

## 宽屏返回播放页（2026-10-27）

- 安全区可用宽度达到 600 逻辑像素、当前浏览其他页面时，左上角侧栏开关旁显示“回到播放页”按钮。启用时配色与侧栏开关一致，没有保留播放页时仍显示为灰色禁用状态，不可点击；侧栏收起后仍保留，当前已在播放页时隐藏。
- 单／双／多标签共用工作区选择逻辑。点击侧栏首页、动态、直播等入口后，可直接回到原播放页面，沿用页面状态和播放会话。桌面双标签模式激活已有独立播放窗口；即使路由已经选中播放页，重复点击仍可唤回该窗口。
- 多标签按最近访问顺序选择仍保留的播放页，覆盖视频、影视、直播与离线播放。关闭最近播放页后回退到上一个保留的播放页，全部关闭后入口变为灰色禁用状态。访问顺序按开放页面去重保存，受 16 页上限约束，不依赖会被一级导航清空或被 64 次访问截断的返回历史；后台换源不改变访问顺序。
- 宽屏应用内双标签统一使用左上角入口；窄屏继续使用原“返回播放”浮动按钮。按钮位于标题栏拖动区域之外，不占用内容页、搜索和播放控件的位置。
- [外壳回归](../../test/app/workspace_shell_test.dart)覆盖三种模式、原生标题栏／普通工具栏、侧栏首页／动态／直播返回、页面与计数状态保留、侧栏收起、599／600 断点和关闭后的回退；[独立窗口回归](../../test/app/windowed_workspace_test.dart)通过 Windows／macOS 平台配置和 fake 多 view 验证重复激活、不重复创建窗口及原页面／view 保留；[工作区回归](../../test/app/workspace_tabs_test.dart)覆盖访问顺序、返回、后台换源、关闭和历史上限。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析、平台打包边界检查、根应用 3027 项与四包 659 项测试通过；13 项根测试因 Windows 符号链接权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志 `build/return-to-playback-check.log`。
- 安全区边界修正后，五个工作区／侧栏／布局测试文件最终 224 项通过，覆盖总宽 620、左右安全区各 20 时仍使用窄屏浮动入口；日志 `build/return-to-playback-targeted.log`。最终根静态分析、两个文档共 38 个相对链接和 `git diff --check` 通过。未进行新的平台构建、原生媒体回归或实机操作验收。
- 后续统一按钮配色与灰色禁用态：外壳／独立窗口／侧栏／布局共 181 项定向测试及三个修改文件的静态分析通过，覆盖初始无播放页不可点击、打开后启用、全部关闭后禁用。日志为 `build/return-to-playback-disabled-targeted.log`、`build/return-to-playback-disabled-analysis.log`。本次 `tool/check.ps1 -SkipPub` 在根格式阶段被同期 `lib/features/feed/data/app_recommendation_identity_store.dart` 的格式问题阻塞，未改动该文件，不能将本次全量检查报告为通过；日志 `build/return-to-playback-disabled-check.log`。
