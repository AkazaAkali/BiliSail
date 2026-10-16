# PiliPlus 参考与 media-kit fork 移植

日期：2026-10-16。按用户要求只读参考本地 PiliPlus，修改用户的 `CKopoer/media-kit` fork 与本项目。

## 来源与采用范围

| 来源 | 精确提交 | 用途与许可 |
| --- | --- | --- |
| [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus/commit/936072449e82e3d90c28c728c0087bf5136fa441) | `936072449e82e3d90c28c728c0087bf5136fa441` | 核对 lock、播放器配置及弹幕职责；GPLv3，仅参考行为，未复制应用代码 |
| [核心 fork](https://github.com/My-Responsitories/media-kit/commit/73771ec38176be2d984a3049c28177bce23b54a0) | `73771ec38176be2d984a3049c28177bce23b54a0` | 原生选项、实例锁、hooks、FFI、Android 资产；MIT，保留版权头 |
| [视频输出 fork](https://github.com/bggRGjQaUbCoE/media-kit/commit/fd8421d21eade4d6d12de137fa7df902fec20292) | `fd8421d21eade4d6d12de137fa7df902fec20292` | Android SurfaceTexture 与 load/unload；MIT，保留版权头 |
| [canvas_danmaku](https://github.com/bggRGjQaUbCoE/canvas_danmaku/tree/275046d8647a6a26cba1d0dadb9e28688cb3dbf1) | `275046d8647a6a26cba1d0dadb9e28688cb3dbf1` | 入场时检查轨道、按项缓存；MIT (2024 Predidit)，未复制源码或引入依赖 |
| 用户 fork 官方基线 | `c533e446755f51cf53c7e57aea873f2aa5355f81` | 保留官方当前结构及 Web/asset/content URI、热重启修复，兼容移植功能 |

PiliPlus 声明的 `media_kit 1.1.11` / `media_kit_video 1.2.5` 被 Git overrides 覆盖，实际为上述定制提交。不能只比较 pub 版本号。核心 50 个文件及视频 33 个路径的逐项采用、等效实现与排除理由见用户 fork 的 [PILIPLUS_PORT.md](https://github.com/CKopoer/media-kit/blob/63b7ea7dd95fc348cecf250df5f54ff87d69d8a9/docs/PILIPLUS_PORT.md)；二进制源码、ABI、许可和校验见 [NATIVE_LIBRARIES.md](https://github.com/CKopoer/media-kit/blob/63b7ea7dd95fc348cecf250df5f54ff87d69d8a9/libs/android/media_kit_libs_android_video/NATIVE_LIBRARIES.md)。

核心兼容移植包括预初始化 options、独立逐媒体 nativeOptions、同步/异步 hooks、每播放器实例锁、FFI ABI/leaf 查询与命令/截图数组分配。视频层另移植可空配置清回 null、动态字幕 padding 两项修复；保留原有公共模型、Web、平台能力、控件与 Windows 原生补丁，不以删除能力替代优化。

## Android Surface 与解码

旧 SDK 的 SurfaceProducer wid 变化会触发 `vo=null → wid/vo → player.seek(currentPosition)`。此前同设备追踪与缓存对照将回退定位到 VO refresh seek 和同缓存区间 seek 的交叉。本次消除该隐式 seek 触发链，仍须在新构建上实机回归才能确认修复。

新流程恢复并加强了 PiliPlus 分支保留的 `SurfaceTextureEntry` 流程（Java 方案在共同祖先已存在，非该 fork 新增 Java 改动），在 `on_load` 屏障内创建新 Surface；`on_unload` 先同步设置 `vo=null`、`wid=0`，再释放 Java Surface/JNI 引用。尺寸更新受源代次与锁约束，不附带 seek，不再用固定延迟猜测释放时机。平台调用有 deadline，释放幂等；保持 Flutter 自身帧监听。创建/尺寸/附着失败传播到本源输出 readiness；释放失败也须清除 Dart controller 所有权，避免 native 地址重用命中失效对象。detach 本身失败时保留仍可能被 VO 引用的原生资源，不能声称此异常路径立即回收。

Android 自动解码采用 PiliPlus 的 `mediacodec,auto-safe` 偏好顺序，load 时提前附着 Surface，仍使用 GPU 视频输出。软件解码保持 `hwdec=no`，等待有效视频参数后附着。Android 设置 `force-window=no`，避免媒体间 idle 1×1 窗口参数干扰。实际硬解、copy 或软件回退必须以设备的 `hwdec-current` 为准，配置本身不证明零复制。

Android 库固定为 `20260906` default 资产（mpv 0.41.0 / FFmpeg 9.0.1，API 24，arm64-v8a/armeabi-v7a/x86_64），Gradle 对下载和缓存均校验完整 SHA-256。本项目原本最低 API 即为 24，发行目标继续为 arm64。Windows libmpv 和七文件校验的渲染/释放补丁继续使用，其他平台原生 wrapper 沿用官方锁定版本。

应用的 Android 视频 open 额外等待本源输出信号，等待仍受源代次、原生错误和整个 open deadline 限制；音频源不等待 Surface。输出信号仍采用视频参数/尺寸提交兜底，不能据此证明首帧像素已显示。

## 弹幕

沿用已有 DPR 文本图像缓存。点播和直播只在有候选入场时构建轨道占用索引，只在活动成员改变时同步图像保护集；动画仍逐帧更新位置。Ticker、碰撞算法、两套时钟、倍速/暂停/缓冲/seek、容量预算、Android 默认值和保存偏好保持原样。

确定性测试的 241 次 `frame()` 中，两项工作各执行一次，旧结构每次调用都会执行；这是重复工作减少的证据，不代表真实 FPS/GPU 收益。回归还覆盖过期、过滤刷新、seek、视口裁剪与图像释放。

## 依赖与验证

用户 fork 分支为 `codex/piliplus-android-surface`，已推送两次提交：`bcd8d4cb`（核心/Surface/原生资产）、`63b7ea7d`（视频配置修复与完整审计）。本项目根应用及 bili_player 的声明和两个锁文件统一固定完整提交 `63b7ea7dd95fc348cecf250df5f54ff87d69d8a9`，不跟随移动分支，也不依赖相邻目录或本机 Pub 缓存修改。

| 包 | 当前解析 |
| --- | --- |
| media_kit | `1.2.6`，用户 fork 固定 Git 提交 |
| media_kit_video | `2.0.1`，同一 Git 提交 |
| media_kit_libs_video | `1.0.8`，同一 Git 提交 |
| media_kit_libs_android_video | `1.3.8`，同一 Git 提交，原生资产为 20260906 |
| Windows / macOS / iOS / Linux 原生 wrapper | 官方 `1.0.11` / `1.1.4` / `1.1.4` / `1.2.1`，保留原锁定资产 |

Pub 不会采纳传递依赖包的 overrides，因此根应用和 bili_player 均显式覆盖 core/Android 的 hosted 声明；更新 fork 时须同时更新七处 ref，并刷新根应用与 bili_player 两份锁文件。

- `tool/check.ps1 -SkipPub`：根应用 1940、API 426、播放器 72、弹幕 93、mux 2 项通过，合计 2533；mux 的 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。
- fork 核心新增测试 9 项（含真实 Windows libmpv），视频包 21 项（17 生命周期 + 4 widget），分析/格式检查通过。
- Windows 原生释放/渲染队列/尺寸 9 项与真实 GPU 的 100 帧同设备共享、复制回退、resize、共享 display 生命周期回归通过。
- Android arm64 Release 预览签名包构建通过；从 APK 核实仅 arm64-v8a，API 24/target 36、versionName 1.0.6/versionCode 10600，实际库为 `mpv v0.41.0-dirty` / FFmpeg `n9.0.1`。
- 最终 Git 快照下完整检查再次通过；`flutter build windows --release` 通过，保留的 Windows DLL SHA-256 为 `222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`。Android 最终快照 Release 重构建通过（58.2 MiB、预览签名）；APK 内 libmpv SHA-256 为 `e03d7145209d82791048674bd07cd95ce88115dd7cb77524b63bdf0ddf44ae98`。

本地日志位于忽略目录 `artifacts/media-kit-fork-2026-10-16/`，包括全工程检查、原生回归、构建与 APK 元数据。构建日志中的 CupertinoIcons 字体提示及上游 Java 8 编译级别警告未影响 APK 构建，不作为本次性能结论。

待设备连接后的验收：同一问题视频 3 倍速完整播放，读取实际 hwdec-current 并追踪视频 PTS/avsync；另测暂停打开、续播、前后台、全屏、切源/清晰度、显式 seek、软件解码、DASH 分轨与直播。Windows 已构建并跑原生/core 回归，本轮未运行完整 GUI 播放验收或性能对比。

手机当前未连接，用户要求先完成代码和构建。本轮不声称 Android 真机三倍速、前后台、切源/清晰度、软硬解回退及长期稳定性通过；macOS 构建与设备也未验证。
