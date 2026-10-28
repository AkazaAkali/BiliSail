# 窄屏底栏切换复查（2026-10-28）

范围：首页、我的（稍后再看）、动态（视频动态）、设置之间往返。用户反馈 Windows 窄窗口和 Android 都有卡顿。本轮在共用 Flutter 路径修改，用实际路由的离线组件回归和 Windows 原生 Profile 验证；当前没有连接 Android 设备。

## 热点与处理

- 当前列表仍按视口懒创建。预热后反复切换，推荐、视频动态和稍后再看没有新增仓储读取；未发现每次重建全部 300 条卡片的情况。
- `RetainedTabView` 原来在祖先 `WorkspaceActivity` 改变时重建分页子树，内容工厂也订阅同一个活动状态。离开设置页仍重新创建隐藏表单的开关、文字等控件。现在按分页器配置、滚动行为和 PageStorage 身份复用子树，将活动状态订阅放到独立门控组件。普通父组件更新仍重新传入配置，包括同一个方法回调读取到新的 State 字段；后代的 Provider、主题、字号和活动状态订阅照常更新。
- 设置页只按已访问分类保留表单 Widget，最多为固定分类枚举数量。分类内部 Consumer 持有设置订阅，实际保存、失败回退、恢复默认及账号更新不靠重新创建表单触发。没有预加载其他分类或扩大工作区页面上限。
- 原先滑入效果仅在 Android/iOS 窄屏启用。现在跟随实际底栏布局，Windows 窄窗口和手动固定底栏也使用同一个 220ms、4% 横向位移、easeOutCubic 的不透明过渡。侧栏、详情进入/返回、首次显示不增加一级过渡；系统减少动画、动画中切到侧栏、快速切页仍沿用原有取消与归位逻辑。底栏固定，内容不重复挂载，动画帧不重建业务页。

## 验证方法

- [分页活动回归](../../test/shared/ui/retained_tab_activity_test.dart)：单纯隐藏/返回时内容工厂由初始共 3 次降为 1 次；草稿、Element、活动通知和焦点隔离保持。父 State 配置变化、字号变化、分类选择继续刷新内容。
- [设置回归](../../test/features/settings/settings_swipe_test.dart)：返回时复用 ChoiceChip，实际点击仍能保存并更新选中状态，切分类再返回仍保留设置。
- [真实外壳回归](../../test/app/primary_switch_layout_test.dart)：将设置纳入已有的三列表往返和 320/599/600/960/390 宽度检查；保留 ScrollPosition、视口约束和请求计数。
- [路由](../../test/app/workspace_router_test.dart)、[导航布局](../../test/app/navigation_bar_mode_test.dart)与[动效](../../test/shared/ui/primary_navigation_transition_test.dart)回归覆盖 Windows/Android/macOS、单/双/多标签、底栏/侧栏/安全区边界、快速重选、减少动画和逐帧内容复用。
- [Android Profile 基准](../../integration_test/android_primary_switch_test.dart)也加入设置，预热后循环 8 轮共 32 次。后续设备复测继续使用 `tool/test-android-primary-switch.ps1` 和独立测试包身份，结束恢复普通 Release。此次没有执行 Android 安装、设备采样或真实账号联网。

## 受控重建计数

使用 `PrimarySwitchFixture` 的真实路由、390×844 视口、每类 300 条内存数据（视频动态沿用 200 条保留上限），四页预热后按我的→视频动态→设置→首页往返两轮。`debugOnRebuildDirtyWidget` 记录整个切换期间的组件构建，两轮计数一致。

| 目标 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 我的／稍后再看 | 1511 | 1516 |
| 视频动态 | 1347 | 1318 |
| 设置 | 1641 | 1211 |
| 首页（从设置返回） | 1932 | 1489 |

设置分类内容工厂原先在进入、离开时各调用一次，现在预热往返中均为 0。其余消费者仍按需更新。新增活动门控本身也参与构建，因此不能宣称每条路径工作量都下降。原始探针和计数位于本机忽略目录 `artifacts/navigation-switch-20261028/` 的 `probe_test.dart`、`structure-before.json` 和 `structure-after.json`。

## Windows Profile 对照

Flutter 3.47.6，Windows 原生 Profile，Impeller OpenGLES，390×844 逻辑视口，显示刷新率 60Hz。为前后对比共用路径，fixture 固定 Android 主题与单标签模式（两版均启用原有 220ms 过渡），使用 480×270 内存 PNG，没有真实账号、API/CDN、磁盘图片读取或原生播放器。预热后每个目标采样 8 次，共 32 次；前后采样期间均未并行运行测试。初轮与组件测试重叠的基线被独立运行旧二进制的结果替换；一次隐藏窗口直接启动未完成采样，未纳入结果。

下表为每次切换区间内最大帧耗时的中位数。`FrameTiming.buildDuration` 包含 UI 帧流水线，不等于单独的 Widget.build。

| 目标 | UI 前→后（ms） | Raster 前→后（ms） |
| --- | ---: | ---: |
| 我的／稍后再看 | 3.38 → 4.05 | 5.12 → 4.89 |
| 视频动态 | 2.78 → 3.33 | 5.66 → 6.65 |
| 设置 | 3.34 → 2.59 | 1.76 → 1.93 |
| 首页（从设置返回） | 3.91 → 3.93 | 6.71 → 7.75 |

两版各列表均只读取一次。前后 UI 最大值为 4.83 / 5.16ms，Raster 最大值为 8.42 / 9.05ms，均未达到 60Hz 的 16.67ms 预算。本轮证实设置切换的额外构建减少，**没有证实所有入口整体帧耗时下降，也没有在这套受控数据中复现用户的明显停顿**。真实账号、首次图片恢复和 Android 120Hz 的预算不同，不能据此宣称两端主观卡顿全部消除。

原始数据：`artifacts/navigation-switch-20261028/profile-before.json`、`profile-after.json`；探针：同目录 `profile.dart`；运行日志：`build/navigation-switch-baseline-isolated.log`、`navigation-switch-profile-after.log`。桌面主题和实际底栏模式的启停由路由组件测试覆盖，此固定 Android 主题的 Windows 渲染对照不等同于 Android 实机。

## 最终检查

- `tool/check.ps1 -SkipPub` 完整通过：格式、静态分析、打包边界和 3911 个离线测试（根应用 3212、bili_api 495、bili_player 83、bili_danmaku 116、bili_mux 5）。根应用 13 个 Windows 符号链接用例因权限跳过，10 个 mux 原生用例因没有配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。日志：`build/navigation-switch-check.log`。
- Windows mux 组件准备和 Profile 构建通过，固定数据前后采样完成。第三方插件的既有 CMake CMP0175 提示未改变构建结果。本轮不涉及原生播放器逻辑，不将组件打包算成媒体播放回归。
- 文档相对链接和 `git diff --check` 通过。新增组件回归先复现活动变化导致额外构建，再验证修复；设置操作用例修正了 `ensureVisible` 后缺少 pump 导致的屏外点击，随后整组及全量测试通过。
- Android/iOS/macOS 未新构建或设备测试，未测真实账号内容、冷网络与长期多页浏览。实际切换手感仍需用户在运行构建中确认。

- Windows Debug 固定数据页面构建、启动和 DTD 热重载成功，运行时错误查询为空；检查结束后关闭诊断应用。Debug 仅用于运行检查，帧耗时结论只来自 Profile。
