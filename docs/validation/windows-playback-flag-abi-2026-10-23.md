# Windows 首帧停滞与 libmpv FLAG ABI 修复

日期：2026-10-23，2026-10-24 完成相似问题检查与诊断清理。Win10 / Intel HD 620 / MSIX 用户反馈：新视频可以显示首帧、拖动定位，但声音与时间不推进；软件解码无效，长时间等待后偶尔恢复。修复包回传后，用户确认已经可以正常播放。

## 定位证据

回传日志 `playback-1792768789400028-15740.log` 的主会话为 `engineId=4, generation=2`：北京时间 23:19:54.015，播放命令在 1 ms 内返回完成。随后至 23:20:47.299 的 54 个样本均为应用期望播放、原生 `pause=true`、`paused-for-cache=false`，位置与音频 PTS 为 0，原生查询只耗时 0–1 ms。音视频解码及视频输出均已建立。视频缓冲位置最终为 257333 ms，总时长 257501 ms；此处不能推导外部音轨已全部缓存。

media-kit 的 `_setPropertyFlag` 以 `calloc<Bool>(1)` 分配 1 字节，却声明 `MPV_FORMAT_FLAG`。[libmpv client.h](https://github.com/mpv-player/mpv/blob/88eb9f2e73945d8bc9c133a2f67babaa9af34680/include/mpv/client.h#L660-L676) 要求 C `int`，在本项目目标 ABI 上为 4 字节，合法值为 0/1。原生读取会超出分配范围，相邻字节非零时，低字节写入 false 仍可能读作 true，且命令返回成功。

用同一份 libmpv 受控验证：`[0,1,0,0]` 写入成功后读回 `pause=1`，`[0,0,0,0]` 读回 `pause=0`。确定性回归使用实际分配了 4 字节的测试 allocator 模拟非零尾部，避免测试本身越界；旧实现失败，修正后通过。没有采集目标设备的堆字节，但故障日志、机制复现及用户修复包反馈相互吻合。

## 修复、来源与相似问题检查

- 用户 fork 固定到 [24f5c7cb6b78f68fa7c23c73ffe7294f0bd962ab](https://github.com/CKopoer/media-kit/commit/24f5c7cb6b78f68fa7c23c73ffe7294f0bd962ab)：FLAG 写入与 pause、core-idle、paused-for-cache、eof-reached 读取统一使用 Int32；写入 0/1，异步完成或异常后释放。根应用和 bili_player 的七处 ref、两份锁文件同步。
- `git blame 63b7ea7` 将错误分配定位到 media-kit 的 [3da3f3ddfa0730c3cd5a990c93a4fd47fe94533c](https://github.com/CKopoer/media-kit/commit/3da3f3ddfa0730c3cd5a990c93a4fd47fe94533c)（2024 年）。本项目 `4f740a4`（2026-10-16）已引用含此缺陷的 `63b7ea7d`。最近 `27fb48a` 的播放/输出/合成重构没有修改此分配或 FLAG 类型；没有证据证明重构是本次故障的引入点。
- 检查 core/video Dart FFI 的 Bool、Int8 和 FLAG 使用，以及相邻 Double、Int64、字符串二级指针、命令数组终止项与异步参数释放；修复后的依赖未发现其他同类宽度错误。节点 FLAG 使用生成绑定中的 C int 字段。
- 核对重构的输出代次、视口请求版本、播放器绑定/释放与首次输出等待，以及应用的 NativeLoadObserver 事件字段宽度和 weak client 释放顺序；未发现另一处 FLAG ABI 缺陷。原生回归发现的 seek 完成时序问题见下节，此检查不代表所有播放路径和设备均无问题。
- 删除本次临时 native probe、逐秒采样、命令追踪、诊断日志扩容、诊断专用测试与打包脚本，并移除 bili_player 为探针添加的直接 ffi 依赖。原有常规脱敏日志保留；fork 中防止 FLAG 缺陷复发的回归测试保留。不修改 Pub 缓存、相邻仓库或解码/音频后端。

## 相似的命令完成时序问题

清理后首次 Windows 回归中，拖动后立即切换视频再返回的用例预期恢复到 1700 ms，实际为 2666 ms；单独重跑通过。进一步添加直接验证 `seek` 完成状态的用例，旧实现直接暴露 `seek(4700 ms)` 已返回、快照仍为 0 ms，见 `build/playback-fix-seek-before.log`。

`MediaKitEngine.seek` 把底层命令应答当成位置已更新，立即清除 seeking 并暴露旧位置；调用方随后保存进度、重建弹幕或捕获页面检查点，会使用旧值。`git blame` 显示该逻辑来自 `78920c6b`（2026-10-07），也早于 `27fb48a`。这是独立于 FLAG 宽度的旧时序缺陷。

修复复用现有 native readiness 等待，要求位置落到目标附近后再完成，保留实际后端位置，不将请求位置冒充确认位置；等待有 12 秒上限、源代次和播放器身份校验，换源/停止及时取消，旧 seek 不得覆盖新源快照。目标超过已知时长时按时长确认。原生回归覆盖 DASH 分轨、纯视频、纯音频，暂停与 3 倍速下前后跳转，以及 seek 后立即停止。

## 桌面默认设置

Windows/macOS/Linux 的新配置改为弹幕字号比例 0.80、视频控件“动态”；Android 保留 0.60 和“点击”，其他平台保持原默认。平台差异在 `lib/app/platform_defaults.dart` 集中定义，由组合根注入设置仓储。只作用于空配置、缺失或无效字段，已保存的有效字号和控件模式不覆盖；无需数据库迁移。测试覆盖新配置、旧配置缺字段/非法值以及显式旧值保存重载。

## 验证

- fork 的 12 项定向测试与三文件静态分析通过，包含非零尾部、异步失败释放及连续 25 次暂停/播放原生读回一致。日志：`build/media-kit-flag-before.log`、`build/media-kit-flag-after.log`、`build/media-kit-flag-analysis.log`。
- 用户已确认修复诊断包 `artifacts/windows-startup-flagfix-20261023.zip`（MSIX 1.1.0.1024）在目标 Win10 / HD 620 上恢复播放。这是目标设备的用户反馈，不将本地自动化等同于实机验收。
- 清理后 `tool/check.ps1 -EnforceLockfile` 通过；增加 seek 修复后再执行 `tool/check.ps1 -SkipPub` 通过。格式、静态分析、打包边界和根应用/四包测试均通过，共 2585 项（1986 / 426 / 78 / 93 / 2）。mux 的另 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。日志：`build/playback-fix-cleanup-check.log`、`build/playback-fix-final-check.log`。
- 新增 seek 回归先失败后通过，`native_video_readiness_test` 的 5 项通过，日志：`build/playback-fix-seek-before.log`、`build/playback-fix-seek-after-final.log`。
- 最终 `tool/test-windows-media.ps1` 的 7 组全部通过：主播放 8、脱敏诊断 1、启动边界 5、视频/seek readiness 5、预览缓冲 1、音量归一化 2、五分钟缓冲窗口 1。runner 共报告 23 项，其中主播放的 1 项公网用例因未启用 `-Online` 直接返回；实际执行 22 项受控原生用例。之前失败的切换/恢复进度用例已通过。日志：`build/playback-fix-final-windows-media.log`。
- 普通 Windows Release 构建通过，未启用临时诊断开关，入口为 `build/windows/x64/runner/Release/bilisail.exe`。使用本轮已准备的 Windows mux 原生资产；构建日志：`build/playback-fix-final-release.log`。新增加的 seek 修复完成本机原生回归，未额外分发安装包或重复另一台设备的安装验收。
- 无活动 DTD/app 连接，热重载未执行成功；原生验证来自重新编译的测试进程。
- Android/macOS 实机、性能与完整在线内容回归未在本轮验证。
