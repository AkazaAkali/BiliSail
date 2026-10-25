# 窄屏一级导航动效与切换开销

日期：2026-10-25。此记录针对 Android 底栏的首页、动态、我的、设置切换；此前首页频道分组和其他导航修改保留在当前工作区。

## 实现

- [外壳](../../lib/app/shell.dart)将一级入口标题、工具栏和内容作为同一动效区域，底栏保持固定。[PrimaryNavigationTransition](../../lib/shared/ui/primary_navigation_transition.dart)在目标入口变化时执行 220ms easeOutCubic 动画：内容由相应方向的 4% 宽度偏移归位，透明度从 0.65 恢复至 1。390 逻辑像素宽度下，位移约 16px；根据入口顺序与文字方向确定左右方向。
- 沿用窄屏移动导航能力判断，Android/iOS 小于 600 逻辑像素时启用；桌面和宽屏不增加此切换动效。首次显示、搜索/播放/用户详情的进入和返回、同一入口中的频道/分类切换均不触发一级动效。页内横滑继续使用各自分页组件。
- 快速连点以最后目标为准，进入详情、切到宽屏或开启系统“减少动画”时立即停止并归位；底栏选中动画也遵守减少动画设置。重复点击当前底栏项不再发起路由导航。
- 动效围绕同一保留树执行，不通过切换动画 key 重挂载页面，也不同时绘制两份业务页面。SlideTransition/FadeTransition 仅更新绘制和合成，内容增加 RepaintBoundary，逐帧不调用页面构建器。

## 性能逻辑检查与修改

[WorkspaceRootPage](../../lib/app/workspace_root_page.dart)此前每次构建都会为所有已访问分支创建新 Builder，进而重新调用各分支的构建器。现在按需保留分支 Builder，只将新路由和回调配置交给选中分支；其他隐藏分支复用原 Widget。缓存以既有五个固定根分支为界，没有增加预加载或无界页面缓存。

首页与动态仍由同一个 FeedScreen 及其控制器保留已加载频道，独立一级频道组和页内滑动沿用当前工作区实现。我的保留选中内容标签和各自列表，设置保留分类和滚动位置。检查确认分页通过 WorkspaceActivity 隔离，已有内容由控制器缓存恢复，一级导航不主动刷新列表。进入可见状态时仍允许既有首屏补页规则检查，不能将这一行为误称为永远零请求。

隐藏根分支保持 WorkspaceActivity、焦点隔离和账号作用域，继续接收 Riverpod 更新。没有在整个根分支外禁用 TickerMode，避免 Riverpod 暂停监听而延迟账号清理。Offstage 的隐藏布局语义保持；本轮减少的是无关导航引起的构建和动效期间的重建，没有宣称隐藏页零布局或实际帧率提升。

## 验证

- [动效组件测试](../../test/shared/ui/primary_navigation_transition_test.dart)：方向、动画中途重选、状态保留、逐帧不重建内容、详情跳转取消、减少动画和运行中关闭动效。
- [根分支测试](../../test/app/workspace_root_page_test.dart)：从五种入口分别开始，验证懒创建、双向状态与 PageStorage 保留，隐藏分支构建器不因其他入口切换被调用，隐藏 Riverpod 消费者仍接收更新。
- [真实路由回归](../../test/app/workspace_router_test.dart)和[外壳回归](../../test/app/shell_layout_test.dart)：Android/Windows/macOS、390/1280 宽度和双/多标签的入口动效开关、一级切换和页内分组隔离、重复选择当前入口，以及已有账号 epoch、焦点和状态保留行为。

- 最终 `tool/check.ps1 -SkipPub` 通过：根应用 2319、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 2951 项测试通过；五处格式和静态分析、Android 版本/签名及 Windows/macOS 打包边界检查通过。10 项 mux 原生用例因没有配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。日志：`build/primary-navigation-check-final.log`。
- 12 组真实路由动效及分页边界定向回归通过，覆盖 Android/Windows/macOS、390/1280 宽度与双/多标签；日志：`build/primary-navigation-motion-routing-final.log`。
- `tool/build-download-mux.ps1 -Target android-arm64` 通过。Android Release APK 构建在 `:app:preReleaseBuild` 被仓库的签名检查阻止，当前进程未配置 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`；没有更改签名保护或生成替代 Release 签名。日志：`build/primary-navigation-android-mux.log`、`build/primary-navigation-android-build.log`。
- `flutter build apk --profile --target-platform android-arm64 --no-pub` 通过，产物 `build/app/outputs/flutter-apk/app-profile.apk`（约 102.9MB），日志 `build/primary-navigation-android-profile.log`。这是默认调试签名的 Profile 测试包，不能覆盖使用正式发布签名安装的版本。构建存在第三方 Java 8/弃用 API 提示；Release 尝试还输出既有 CupertinoIcons 字体缺失提示，本轮未改动相关资源。

本地没有连接的 Android 设备或可热重载的 Flutter 调试应用，实际触感、Android Profile/Release 帧时长与 GPU 合成开销尚未实测；组件工作次数不能换算成帧率收益。未构建 Windows/macOS；按用户要求与首页子标签滑动隔离修复整体提交，未推送。
