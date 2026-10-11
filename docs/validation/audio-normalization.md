# 播放器音量均衡

日期：2026-10-11。

## 行为与范围

播放器设置的“播放”页提供“标准／高动态／关闭”。默认关闭，保持旧版本的播放音量；选择持久化到全局设置，并立即应用到已打开的普通视频与影视。均衡增益独立于用户音量，不修改音量滑块、倍速、位置和暂停状态，也不重新打开媒体。

标准使用接口给出的 `normal_target_i`，高动态使用 `high_dynamic_target_i`；后者通常更安静，为动态峰值留出空间。这是按整段响度计算的固定增益，不是实时自动增益、压缩器或均衡器。缺少合法元数据、测量响度低于 `undersized_target_i`，以及静音预览、直播、离线源，都使用 0 dB 附加增益。

## 协议与来源

| profile | 端点 | 请求与响应 |
| --- | --- | --- |
| 普通视频播放 | `GET https://api.bilibili.com/x/player/wbi/playurl` | Web Cookie／WBI，增加 `voice_balance=1`；静音预览不增加此参数 |
| 影视播放 | `GET https://api.bilibili.com/pgc/player/web/playurl` | 沿用 Web 会话及原有权益／试看校验，增加 `voice_balance=1` |

两者均为无分页 JSON 只读请求，复用已有取消、超时、有限重试与账号隔离。即使设置为关闭，也获取可选响度元数据，以便切换时直接生效。只解析已有播放响应的 `volume`，不增加独立请求，不更改选流或观看权限。

`volume.measured_i` 为测量响度；`volume.multi_scene_args` 内的 `normal_target_i`、`high_dynamic_target_i`、`undersized_target_i` 分别映射标准目标、高动态目标与过低响度阈值。合法值须为有限数、位于 `[-70, 0)`，且阈值不大于高动态目标、高动态目标不大于标准目标；缺字段、`.001` 哨兵或其他非法值整体视为无元数据，不影响媒体本身可播。

```text
gainDb = targetI - measuredI
amplitude = 10 ^ (gainDb / 20)
```

额外增益限制为 `[-60, 30]` dB；异常数据回退到 0 dB。参考来源为本次在线检查的 [Bilibili 官方播放器脚本](https://s1.hdslb.com/bfs/static/player/main/core.ba67b466.js) 的 `voice_balance`、`normal_target_i`、`high_dynamic_target_i` 及 GainNode 调整链路。仅借鉴接口字段和计算行为，没有复制该脚本、资源或引入其运行时依赖。

## 实现边界

- `bili_api` 提供可选 `ApiAudioLoudness`，共用 DASH 映射转为纯 Dart `AudioLoudness`；普通视频与影视使用同一链路。
- `PlaybackSession` 根据当前源与设置计算增益；`bili_player` 仅接收通用 dB 值，不感知 Bilibili 字段或全局设置。
- 初次打开通过 `OpenOptions.audioGainDb` 在播放前应用；打开期间设置变化会在源就绪后补用最新设置。后续切换通过有界命令队列合并待执行值，源代次与账号 epoch 隔离旧操作。
- 设置保存到 `preferences.v1.audioNormalization`；快照 schema 由 17 升到 18，SQLite 数据库 schema 不变。缺失或未知值回退关闭。
- 当前 Windows 捆绑 mpv 缺少 FFmpeg `volume` 滤镜及新版本 `volume-gain` 属性，因此使用已有 `replaygain=no` 与独立的 `replaygain-fallback` 增益。每次设置后读回校验，避免 media_kit 静默忽略原生属性失败。
- 播放中切换在约 90 ms 内以有限步数平滑到目标，幅度域采用 15 ms 时间常数；初次打开直接设置。单次操作最多 2 秒，源替换／释放／新操作会使旧操作失效，无常驻计时器。错误使用已有播放错误通道。不新增依赖或原生二进制。

## 验证

- 协议测试覆盖 UGC／PGC 参数与元数据、预览排除、无效元数据降级。
- 领域与会话测试覆盖三模式、阈值与目标计算、设置持久化、两类点播、切换清晰度／新源、打开中改设置、快速切换合并、旧账号操作隔离。
- 小屏设置测试在 400 × 800 布局选择三模式，保存后保留用户音量。
- 原生增益单测覆盖平滑、属性读回、静默写失败、取消、超时后禁止继续写入及非法增益。
- Windows 本机 `integration_test/windows_audio_normalization_test.dart` 两例通过：真实 mpv 解码本地 DASH 音视频分轨，通过普通视频／影视会话验证三模式增益，保留音量、倍速、暂停、位置，换清晰度继承，新源无元数据恢复 0 dB。该测试已加入 `tool/test-windows-media.ps1`。
- `tool/check.ps1 -SkipPub` 通过格式、静态检查和回归测试：根应用 1821、API 包 390、播放器包 41、弹幕包 86、封装包 2；封装包 7 项依赖 `BILI_MUX_LIBRARY` 的原生测试按既有规则跳过。
- Windows Release 构建通过，产物位于 `build/windows-audio-release/runner/Release/`。常规 `flutter build windows --release --no-pub` 的输出被已运行实例锁定，因此沿用 Flutter 生成的配置，用独立 CMake 构建目录和显式项目内 `CMAKE_INSTALL_PREFIX` 完成编译／文件收集；依赖复用现有已校验缓存，未改动正在运行的实例。该 Release 产物未另外启动做听感验收。

在线匿名只读探针 `dart run tool/audio_normalization_smoke.dart`：UGC `BV11hpL62Ezv` 返回测量 `-16.7`、标准目标 `-14`、高动态目标 `-24`、过低阈值 `-28`，对应标准 `+2.7 dB`、高动态 `-7.3 dB`。PGC `ep733316` 返回有效视频／音频分轨，但没有 `volume`；另外抽查两集及新版 v2 接口也未得到该字段。影视链路支持接口提供的响度数据，但不能保证每一剧集都有，缺失时保持原声。

Android／macOS 原生播放尚未验证；Windows 自动化验证不等同于三端实机验收。极端素材的峰值裁切、主观听感与不同音频设备仍未完成系统测量。
