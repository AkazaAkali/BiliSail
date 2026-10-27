# 宽屏侧栏样式与收起

日期：2026-10-27。

## 行为

- 设置 → 外观 → **宽屏侧栏样式**：提供“随窗口宽度”“完整侧栏”“图标文字上下”。默认自动，保留原有 600–1599 逻辑像素使用 76 宽导航轨、1600 起使用 164 宽完整侧栏的行为。手动选择在安全区可用宽度达到 600 后生效；窄屏继续使用底栏。
- 宽屏顶部左侧放置圆角描边的菜单／箭头按钮，浅色与深色均使用当前主题颜色，提供“收起侧栏／展开侧栏”提示。按钮在侧栏完全收起后仍留在原位；复用桌面标题栏或多标签栏，没有这些栏时显示 40 高工具栏，避免遮挡页面、搜索及播放操作。
- 收起／展开使用 240ms `easeInOutCubic` 宽度和透明度过渡，内容区及左留白同步调整，按钮图标轻微旋转。侧栏内部保持完整布局宽度并裁剪，避免文字在收起过程中挤压折行。快速反向点击从当前宽度继续；系统减少动画时立即到位，进入窄屏也立即让出空间。
- 收起期间侧栏停止接收指针、键盘焦点和无障碍导航；完全收起后不绘制侧栏。内容页保持同一组件树，不复制页面、播放会话或数据请求。主导航、消息／下载／设置的底部布局和短窗口滚动沿用现有实现。
- `AppSettings.sidebarStyle/sidebarCollapsed` 经设置控制器立即应用并串行保存，失败回退已保存配置并提示。`preferences.v1` 版本化快照追加两个字段，无数据库表变动；缺失／非法字段分别回退为自动、展开，保留其他合法旧设置。恢复默认同时恢复自动样式与展开状态。缩窄窗口不覆盖宽屏偏好。

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

- 安全区可用宽度达到 600 逻辑像素、当前浏览其他页面且仍有保留的播放页时，左上角侧栏开关旁显示“回到播放页”按钮。侧栏收起后仍可使用；没有播放页或当前已在播放页时隐藏。
- 单／双／多标签共用工作区选择逻辑。点击侧栏首页、动态、直播等入口后，可直接回到原播放页面，沿用页面状态和播放会话。桌面双标签模式激活已有独立播放窗口；即使路由已经选中播放页，重复点击仍可唤回该窗口。
- 多标签按最近访问顺序选择仍保留的播放页，覆盖视频、影视、直播与离线播放。关闭最近播放页后回退到上一个保留的播放页，全部关闭后隐藏入口。访问顺序按开放页面去重保存，受 16 页上限约束，不依赖会被一级导航清空或被 64 次访问截断的返回历史；后台换源不改变访问顺序。
- 宽屏应用内双标签统一使用左上角入口；窄屏继续使用原“返回播放”浮动按钮。按钮位于标题栏拖动区域之外，不占用内容页、搜索和播放控件的位置。
- [外壳回归](../../test/app/workspace_shell_test.dart)覆盖三种模式、原生标题栏／普通工具栏、侧栏首页／动态／直播返回、页面与计数状态保留、侧栏收起、599／600 断点和关闭后的回退；[独立窗口回归](../../test/app/windowed_workspace_test.dart)通过 Windows／macOS 平台配置和 fake 多 view 验证重复激活、不重复创建窗口及原页面／view 保留；[工作区回归](../../test/app/workspace_tabs_test.dart)覆盖访问顺序、返回、后台换源、关闭和历史上限。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析、平台打包边界检查、根应用 3027 项与四包 659 项测试通过；13 项根测试因 Windows 符号链接权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志 `build/return-to-playback-check.log`。
- 安全区边界修正后，五个工作区／侧栏／布局测试文件最终 224 项通过，覆盖总宽 620、左右安全区各 20 时仍使用窄屏浮动入口；日志 `build/return-to-playback-targeted.log`。最终根静态分析、两个文档共 38 个相对链接和 `git diff --check` 通过。未进行新的平台构建、原生媒体回归或实机操作验收。
