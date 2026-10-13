# 正式页面、首页视频与真实弹幕的 GPU 复测

日期：2026-10-13。用户补充条件：从首页选择视频、1080p、复用 Release 登录信息，每个场景测量 30 秒。本轮按这些条件使用 **Windows Release**，共用正式 BiliApp、首页 VideoCard、VideoScreen、PlaybackPanel、PlaybackSession、ApiPlaybackRepository 和 DanmakuOverlay。

本文件记录修复前的正式页面基线。后续透明度对照排除了主要的整层透明度猜测，60Hz 按需绘制已实现，结果见[弹幕高刷合成修复](danmaku-frame-cadence-2026-10-13.md)。

## 与合成测试不同的条件

- 第一轮点击正式首页第一条时长至少 120 秒的推荐卡片，选中 [BV1C3576fErj](https://www.bilibili.com/video/BV1C3576fErj/)，第二轮复测相同视频和片段，避免推荐内容变化。CID `38238750699`。
- 使用 Release 应用同一系统安全存储中的登录态，在内存副本中恢复；实际已登录。请求 1080p `qn=80`，服务端实际档位也为 80；DASH 音视频分轨，H.264 `avc1.640033` / AAC `mp4a.40.2`，实际解码尺寸为 **1920×1076**，没有强制改变源编码尺寸。原生硬解实值均为 `d3d11va`。
- 复制当前应用保存的播放/弹幕设置：HarmonyOS Sans、加粗、字号缩放 **0.85**、阴影、透明度 **0.8**、区域 **40%**、速度 1、每秒上限 20、重复合并开启、同屏限制 0、无关键词过滤，字幕关闭、点击控件模式。本轮没有改成合成测试的系统字体、不加粗、25px 和 75% 区域。
- 通过正式页面和正式全屏控制进入两种布局。窗口为 1280×720、DPR 1；VideoSurface 容器约 884×669，原生输出 **896×503**。全屏容器 1920×1080，原生输出 **1920×1076**。容器尺寸与按片源比例生成的输出纹理尺寸分别记录，不将二者混为一个数值。
- 获取对应视频的服务器弹幕，通过生产时间窗、权重/类型筛选、每秒上限、重复合并和防碰撞轨道。该段自然弹幕很稀疏：段 1 共 17 条，30–60 秒有 4 条滚动弹幕，生产筛选/合并后同屏最多 **1 条**，30 秒可见均值约 0.27。没有额外注入文字、统一时间分布或持续补齐密度。
- 环境仍为 RTX 4070 Ti SUPER、驱动 `32.0.16.1742`、180Hz。正常客户端保留侧栏、简介/评论区域、真实图片、播放进度和控件生命周期；不再用只含 VideoSurface 的固定尺寸 Stack。

为保持复测片段一致，内存配置关闭自动续播/下一集，并将音量设为 0，音频仍实际解码。进度存储和云端历史上报端口使用空实现，其余播放、网络、弹幕和 UI 路径继续共用生产实现；原有数据库、凭据与偏好不修改。这是测量入口与完整使用流程之间保留的边界。

## 完整 30 秒采样

每个场景先 seek 到约 22 秒，预热 8 秒，再测约 30–60 秒的相同内容。测量时钟独立于采样文件写入，不把预热纳入 30 秒，也不因逐次写文件延长每秒采样间隔。

两轮分别运行窗口内弹幕关闭/开启、全屏弹幕关闭/开启，共 **8 个场景**。每个场景记录 30 条播放与 Flutter 帧时序样本，实测时间 **30.000–30.002 秒**。

GPU 改用连续 PDH 查询，每秒采集同一 PID、同一适配器 LUID `0x00000000_0x0000c3a9` 的 GPU Engine，避免上一轮每次重新建立查询。实际间隔均值约 1.014–1.017 秒；每阶段获得 **28–29 个完整 GPU 间隔**，不完整的边界间隔不混入均值。因此 30 秒播放采样与完整 PDH 间隔数量分别报告，不能写成必然有 30 个完整一秒 GPU 点。

## 两轮结果

| 场景 | 第 1 轮 3D 均值 | 第 2 轮 3D 均值 | 30 秒 Dart 帧时序上报/秒 | 实际可见弹幕 |
| --- | ---: | ---: | ---: | --- |
| 窗口内，关闭弹幕 | 1.28% | **1.43%** | 约 29.9 | 0 |
| 窗口内，开启真实弹幕 | 3.06% | **3.10%** | 约 69.6–69.7 | 最多 1，均值 0.27 |
| 全屏，关闭弹幕 | 4.43% | **4.46%** | 约 29.9 | 0 |
| 全屏，开启真实弹幕 | 9.88% | **10.06%** | 约 69.6–70.7 | 最多 1，均值 0.27 |

第一轮窗口内关闭弹幕时曾从 P0/P5 回到 P8，核心时钟均值 480MHz、中位数 210MHz；不能将该一格当作严格同频对照。其余阶段、包括第二轮全部四个场景，均为 **210MHz / P8**。主要比较以第二轮为准，全屏两轮结果接近。

30 秒开启弹幕的均值包含自然空档。进一步只选择相邻可见状态均大于 0 的完整 GPU 间隔，排除弹幕入场/退出的过渡间隔：

| 有弹幕可见的子区间 | 第 1 轮 3D 均值 | 第 2 轮 3D 均值 | 同屏数量 | Dart 帧时序上报/秒 |
| --- | ---: | ---: | ---: | ---: |
| 窗口内 | 7.49%（7 点） | 7.40%（6 点） | 1 | 约 180 |
| 全屏 | **23.41%（7 点）** | **23.76%（7 点）** | 1 | 约 180 |

子区间只有约 6–7 个完整 GPU 点，**不是另一次持续 30 秒有弹幕压测**。它说明普通 30 秒均值会掩盖短时负载；不能用 23–24% 冒充整个 30 秒或所有视频的平均占用。弹幕不再可见后，全屏子区间回到约 4.45–4.69%，窗口内回到约 1.41–1.42%。

全部场景没有 buffering/seeking、Flutter 错误或播放器/解码器掉帧，采样最大绝对 A/V 偏差不超过 0.93ms。raster P95 约 1.13–1.43ms；没有在该素材上复现持续卡顿。文字图像缓存命中约 **99.93%**、峰值约 **0.24 MiB**，直接绘制回退 **0**。

## 对优化优先级的修正

本例只有一条自然滚动弹幕，就能在全屏可见子区间升至约 23–24%。当前应优先检查 **滚动弹幕触发约 180Hz 的 Flutter 绘制/窗口合成，以及全屏弹幕透明层的面积成本**。窗口内到全屏的增量不能只按“多了多少条文字”解释，扩大文字缓存也没有本轮证据。

- 修复前 [DanmakuOverlay](../../packages/bili_danmaku/lib/src/danmaku_overlay.dart) 的活动滚动弹幕持续请求 Ticker；真实空档停止 Ticker 已生效。应在真实页面验证有界调度，保留时间驱动的位置、暂停/seek/倍速语义，再比较高刷平滑度与 GPU，而不是直接套用合成测试的固定降幅。
- [PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart) 仍通过整层 `Opacity(0.8)` 包装弹幕；可验证减少合成范围或在文字图像绘制时应用 alpha，同时验证阴影、描边和重叠区域像素。当前观察是受控切换和源码证据，尚未逐个 GPU pass 计时，不能宣称某一个 `saveLayer` 独占全部额外负载。
- 本片段没有固定顶部/底部弹幕可见，不能用本轮替代固定弹幕事件驱动候选的真实素材验证。前序合成数据保留为结构探针，不再作为这类实际页面的负载预测。

原生硬解仍为 `d3d11va`，不能把约 180 次/秒 Dart 绘制写成 180 次 GPU 回读或原生纹理复制。本轮没有同片段网页对照，也没有验证其他 GPU、DPR、HDR、长播放及所有弹幕密度。

## 复现与产物

工具：[实际页面 Release 探针](../../tool/validation/windows_real_video_gpu_probe.dart)、[运行脚本](../../tool/test-windows-real-video-gpu.ps1)、[GPU 采集](../../tool/validation/windows_gpu_engine_probe.ps1)。本基线测量时正式播放器调度尚未修改，无新增依赖。

```powershell
flutter build windows --release --no-pub -t tool/validation/windows_real_video_gpu_probe.dart
# 将整个 Release bundle 复制到独立目录，后续恢复产品入口不会覆盖它。
pwsh -NoProfile -File tool/test-windows-real-video-gpu.ps1 `
  -Label real-home-verify -Bvid home -Quality 80 -StartSeconds 30 `
  -ExePath C:\Users\14562\code\bili-lite\build\validation\windows-home-video-gpu-bundle\bilisail.exe
# 第一轮记录实际首页选中的 BV，后续传该 BV 复测同一视频。
```

有效标签为 `real-home-1`、`real-home-2`。`build/validation/windows-real-playback-<label>.jsonl` 包含配置摘要、精确阶段边界、位置、尺寸、缓存与帧时序；`windows-gpu-engine-<label>.jsonl` 为进程 GPU 数据；`windows-real-clocks-<label>.csv` 为 NVIDIA 时钟与整卡功耗；`windows-real-fixture-<label>.json` 为运行参数及 EXE/libmpv 哈希。没有保存 Cookie、用户 MID、签名媒体 URL、完整偏好或弹幕正文。

汇总为忽略目录 `artifacts/windows-gpu-native/real-video-comparison.json`，脚本为 `summarize-real-video.py`。此前 `real-mv-a`、`real-mv-1` 是全屏控件自动定位未完成的探索记录，未纳入本报告；正式探针通过播放器的语义点击显示控件，再调用实际全屏按钮，等待真实窗口状态改变。

探针格式、静态分析与 Windows Release 构建通过；同一首页视频的两轮复测进程均正常退出。`tool/check.ps1 -SkipPub` 通过：根应用 1932、API 426、播放器 54、弹幕 90、合流包 2，共 **2504** 项，另 10 项合流原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。格式和静态分析通过。随后 `flutter build windows --release --no-pub -t lib/main.dart` 成功，正常 Release 入口已恢复；日志分别为 `real-video-check.log` 和 `real-video-main-build.log`。
