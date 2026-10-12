# Windows 播放器 GPU 优化结果

日期：2026-10-13。基于[前序定位](windows-player-gpu-analysis-2026-10-12.md)，本轮修改 Windows 原生视频输出和共享点播弹幕调度，完成同机前后 GPU 对照、工程测试、真实 GPU 像素检查和 Windows Release 构建。

## 实施与实际生效路径

### 硬解帧保留在 GPU

旧 `libmpv v0.36.0-403-g652a1dd907` 检查 `EGL_EXT_device_query` 时只读取 display extension string。ANGLE 把该扩展列在 client string，导致 D3D11/EGL interop 被拒绝，自动模式选择 `d3d11va-copy`。本轮检查了旧版本源码和启动日志，并对照 [mpv 修复 1d15686](https://github.com/mpv-player/mpv/commit/1d15686142fd5d53c954aab7526cedab05ef9dc3)。

Windows x64 使用[固定 LGPL 原生资产](../../windows/native/mpv/SOURCE.md)，实际版本 `v0.41.0-1150-g88eb9f2e7`，配置确认 `gpl=false`、`libmpv=true`、`egl-angle=enabled`。归档及 DLL 均校验 SHA-256，headers/import library/打包 DLL 一起切换。保持 SDK 的自动解码配置；本机实际为 `d3d11va`，没有改成低清晰度片源或软件解码。

覆盖入口为 [mpv.cmake](../../windows/native/mpv.cmake)，只作用于 Windows x64，Pub 缓存及 Android/macOS 库不修改。源码、构建来源与许可原文随 bundle 保留在 `data/licenses/mpv`。

### GPU 命令有序提交与纹理交付

[ANGLE 补丁](../../windows/patches/media_kit_video/angle_gpu_queue.inc) 在初始化 display 后取得 ANGLE 的 D3D11 device/即时上下文，启用多线程保护。mpv GL 绘制与 GPU 复制因此使用同一生产端命令队列；`glFlush` 提交工作，代替每帧 `glFinish` 等待 GPU 完成。它不是简单删除旧 barrier 后继续跨设备操作。

只有确认消费者使用**同一个 D3D11 device 对象**时，才直接返回渲染纹理的 shared handle；不同或未知设备使用原独立交付纹理。同一 draw revision 不重复提交 `CopyResource`。缺少 ANGLE device 查询时保留旧同步回退。

**本机 Flutter 播放的日志实际为 `GPU delivery: copied`，仍有一次保护性 GPU 复制；不能宣称整条播放链已零拷贝。** 已消除的是硬解帧 GPU→RAM→GPU 往返，以及此设备支持路径上的每帧 `glFinish`。独立同设备直接交付路径由真实 GPU 测试验证，未把它冒充本机 Flutter 已采用的路径。

默认 EGL display 可能与其他组件共用，单个播放器销毁时不再调用 `eglTerminate`。继续显式释放自身 surface/context，并保留既有停止更新、渲染队列排空、旧纹理注销等待与有效 GL context 下释放 mpv 的顺序。补丁仍由 CMake 校验上游七个源文件的哈希并复制到构建树，见[补丁说明](../../windows/patches/media_kit_video/README.md)。

### 空弹幕停止绘制，未来弹幕按时唤醒

[DanmakuController](../../packages/bili_danmaku/lib/src/danmaku_controller.dart) 的 `needsFrame` 现在要求存在活动弹幕或到期 admission，空／只有未来事件的窗口不会保持 Ticker。播放时钟确认仍更新控制器；[DanmakuOverlay](../../packages/bili_danmaku/lib/src/danmaku_overlay.dart) 只通过自己的 repaint notifier 绘制，时钟变化不强制重画空层。

未来事件在原有最大 700ms 插值窗口内由一个单次 Timer 唤醒，避免等到下一次位置确认才出现；没有未来事件就没有 Timer。新位置、倍速、暂停、缓冲、seek、换控制器和 dispose 会重新锚定或取消。保留最后一条弹幕移除后的清屏绘制与暂停 seek 的有界 admission。直播空层原本已按 pending/visible 数量停转，本轮保留其独立时钟。

## GPU 前后对照

环境为 Windows、RTX 4070 Ti SUPER、驱动 `32.0.16.1742`、1920×1080/180Hz、DPR 1、Flutter 3.47.6。主片复用同一个本地 1920×1080 H.264/yuv420p、60fps、AAC 文件，SHA-256 `afdbabbfb17447cc6345e331d7b9fa1faac59f5a055c528a3791ab873710154a`。两个版本都输出 960×540，音频继续解码、音量 0；无网络、字幕或业务控件。原生 mpv 自动档的实际值另行记录。

共用 [Profile 播放探针](../../tool/validation/windows_gpu_playback_probe.dart)：纯视频预热 3 秒、稳定 40 秒；seek 回到开头，挂载空弹幕并预热 3 秒、稳定 40 秒；最后暂停。旧版 AOT bundle 在修改前保存，包含旧库和旧弹幕逻辑；新版保存最终实现。

GPU 使用 Windows PDH `GPU Engine`，只采对应进程和 NVIDIA LUID `0x00000000_0x0000c4f8`。排除阶段最初约 2 秒，只纳入完整稳态一秒区间。每个阶段有 27–30 个有效 GPU 点；同时记录 NVIDIA clocks/P-state/整卡功耗。分列 3D 和 VideoDecode，不相加成总 GPU。

| 稳态场景 | 优化前两轮 3D 均值 | 优化后两轮 3D 均值 | 优化前／后空层 Dart 帧调度 |
| --- | --- | --- | --- |
| 纯视频 | 14.12%、14.44% | **1.58%、1.64%** | 均约 0 次/秒 |
| 挂载空弹幕层 | 17.16%、16.41% | **1.55%、1.81%** | 约 181 次/秒 → **0** |

这台设备本轮纯视频 3D 均值下降约 89%；这不是所有设备或真实内容的固定降幅。Dart 上报帧调度为 0 不代表 native 视频没有呈现，视频确认位置持续推进、输出纹理有效，素材仍为 60fps。

| 核对项 | 优化前两轮 | 优化后两轮 |
| --- | --- | --- |
| 实际硬解器 | `d3d11va-copy` | `d3d11va` |
| 纯视频核心时钟均值 | 214MHz、220MHz | 210MHz、215MHz |
| 纯视频核心时钟中位数 / P-state | 210MHz / P8 | 210MHz / P8 |
| 纯视频 VideoDecode 均值 | 15.05%、14.70% | 10.60%、12.21% |
| 纯视频整卡功耗均值 | 14.96W、14.49W | 13.13W、15.63W |
| 纯视频采样最大绝对 A/V 偏差 | 1.41ms、2.21ms | 1.28ms、0.70ms |
| 播放器／解码器掉帧 | 全部 0 | 全部 0 |

纯视频频率接近，3D 的明显降低没有靠全程提高 GPU 频率取得。功耗是整卡指标，本轮两组范围重叠，**不宣称已经证明固定功耗降低**。空弹幕新版本第一轮曾短时进入 P0/P5，时钟均值 430MHz、第二轮约 230MHz，中位数均为 210MHz；同样不能用单段百分比换算能耗。

四个正式结果标签为 `before-a`、`before-b`、`final-a`、`final-b`。较早的配置探索与和原生回归同时运行的采样不混入最终对照。

## 验证

- 提交前重跑 `tool/check.ps1 -EnforceLockfile` 通过：根应用 1932、API 426、播放器 54、弹幕 90、合流包 2，共 **2504** 项；合流包另 10 项依赖 `BILI_MUX_LIBRARY` 的测试按配置跳过。格式与静态分析通过，五份锁文件没有变化，日志 `artifacts/windows-gpu-native/pre-release-check.log`。
- [新增弹幕回归](../../packages/bili_danmaku/test/danmaku_idle_test.dart) 验证空／未来窗口无连续帧、确认样本之间的到期唤醒、暂停取消及恢复、最后可见帧清理；暂停 seek admission、倍速、DPR/文字图像回归一并通过。
- `tool/test-windows-video-dispose.ps1` 的 9 项原生生命周期、队列、尺寸测试通过。原有 owner/revision/销毁屏障继续覆盖。
- [真实 GPU 队列测试](../../tool/test-windows-gpu-queue.ps1) 通过：100 个交替颜色帧逐像素核对、同设备直接共享、未知消费者复制、尺寸变化、销毁生产者后共享 display 的消费者仍可使用。CPU staging 回读只用于这个测试，日志 `gpu-queue-test-final.log`。
- `tool/test-windows-media.ps1` 通过 18 项 Windows 原生回归，覆盖分轨/请求策略、播放与界面、HTTP 错误、启动/取消、预览、音量均衡、5 分钟向前预读；日志 `windows-media.log`。
- `tool/test-windows-codecs.ps1` 的 H.264/HEVC/AV1 × 自动/软件六种组合通过，自动实值均 `d3d11va`，软件实值均 `no`，音视频解码和进度有效，暂停/seek/stop 通过；日志 `codecs.log`。
- 正式入口 `flutter build windows --release --no-pub -t lib/main.dart` 通过，日志 `release-build.log`。Release DLL 重新核对为固定 SHA-256，`data/licenses/mpv` 同时包含来源和 LGPL 原文。该本机构建不代替安装包安装与三端实机验收。

## 复测与交付边界

使用 [test-windows-gpu-playback.ps1](../../tool/test-windows-gpu-playback.ps1)，传入完整 probe bundle、同一素材路径和新 label。例如：

```powershell
pwsh -NoProfile -File tool/test-windows-gpu-playback.ps1 `
  -Label verify-new `
  -ExePath C:\Users\14562\code\bili-lite\build\validation\windows-gpu-final-bundle\bilisail.exe `
  -MediaPath C:\Users\14562\code\bili-lite\build\validation\windows-render-1080-media\main.mp4
```

原始位置/解码器/掉帧在 `build/validation/windows-gpu-playback-<label>.jsonl`；引擎计数在 `windows-gpu-engine-<label>.jsonl`；频率和功耗在 `windows-gpu-clocks-<label>.csv`；fixture/DLL 哈希在 `.fixture.json`。独立汇总为忽略目录中的 `artifacts/windows-gpu-native/comparison.json`。旧、新 bundle 分别保存于 `build/validation/windows-gpu-before-bundle` 和 `windows-gpu-final-bundle`。

验证的是本机 Windows、本地 SDR 素材和 Profile；实际内容、不同显卡/DPR、HDR/广色域、长播放、Windows 10 旧驱动及 Android/macOS 实机未由这些结果代替。新库仍保留 automatic 的能力回退，未承诺所有设备都能使用非 copy-back。当前 Flutter 保护性 GPU 复制保留，未改动 Flutter engine 或引入私有 ABI。
