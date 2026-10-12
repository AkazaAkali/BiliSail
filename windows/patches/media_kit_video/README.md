# media_kit_video 2.0.1 Windows 渲染与释放补丁

来源：[media-kit/media-kit](https://github.com/media-kit/media-kit)，已锁定的 Pub 包 `media_kit_video 2.0.1`。仅在构建目录复制其 Windows 源文件并修正渲染和释放生命周期；不修改 Pub 缓存，不替换 Dart、Android/macOS 实现或 libmpv/ANGLE 二进制。上游代码为 MIT，许可保存在 [LICENSE](LICENSE)，源文件版权头保留。

`apply.cmake` 在 Windows 插件目标创建后校验五个上游源文件的 SHA-256，将副本作为该目标的编译输入。依赖升级或源文件变化时配置失败，必须重新审查补丁，不能静默跳过。普通 `flutter build windows` 与 MSIX 打包共用此入口。

修正包括：方法通道等待原生 Dispose 完成；停止渲染通知并排空在途任务；等待当前和旧纹理的注销回调；在有效 GL 上下文中同步释放 mpv 渲染上下文，然后销毁 ANGLE。没有纹理时不等待不存在的回调。重复到达、尚未执行的渲染通知只排一个任务；执行期间的新通知会在队列尾部再排一次，避免长时间占住共用渲染线程。暂停、SetSize 与视口变化仍强制重绘。

尺寸方法改用 Dart 原生适配器通过 SetSize 发送的显示尺寸，避免在共用渲染线程同步调用 mpv 核心 API。另由当前挂载的 VideoSurface 按布局与设备像素比发送视口上限，原生端按源显示比例限制中间输出纹理，不改变源分辨率或解码设置。新视口所有者立即解除旧上限；放大立即更新，缩小延迟 300 ms，原生单调 revision 防止异步通道请求逆序覆盖。首帧／暂停时的尺寸更新立即触发检查和绘制，主视频与预览继续使用 GPU 渲染。纹理复制和 GL 同步仍维持上游行为。

四个 `.inc` 是编译到上游类中的替换方法，原生单测直接编译相关方法体。它们不是构建产物。测试不依赖播放器、显卡或 Flutter 进程：`pwsh -File tool/test-windows-video-dispose.ps1`。布局所有权、设备像素比及缩小定时行为由 `packages/bili_player/test/video_viewport_test.dart` 验证。

故障证据、设计及验收范围见 [验证记录](../../../docs/validation/windows-preview-dispose.md)。

悬停卡顿原因、保留 GPU 的方案与 Profile 对照见 [预览出帧争用](../../../docs/validation/video-preview-contention.md)。`BILISAIL_VIDEO_RENDER_TRACE=1` 仅供该探针构建记录耗时；常规构建不加入逐帧诊断代码。

本次视口尺寸和 Windows GPU Engine 的受控 Profile 对照见 [渲染性能验证](../../../docs/validation/windows-video-render-performance-2026-10-11.md)。性能结论以实际设备和素材为限，不能把输出像素面积下降直接等同于 GPU 忙碌率下降。

`pwsh -NoProfile -File tool/test-windows-video-render.ps1 -Label run-720 -Height 720 -GenerateFixture` 可在仓库根目录生成或复用同参数的 50 秒测试片并执行 Profile 探针；结果写入 `build/validation/windows-video-render-run-720.json`、同名日志、`.fixture.json` 素材 SHA-256 元数据与 `windows-gpu-engine-run-720.jsonl`。传入 `-MediaDir` 可复用指定素材，`-ExePath` 可运行已保存的旧版 Profile 可执行目录做交替对照。脚本在 Flutter 构建后还原普通 CMake 配置。独立分轨检查使用 `tool/validation/windows_dash_render_probe.dart`，不会混入单文件 A/B 指标。
