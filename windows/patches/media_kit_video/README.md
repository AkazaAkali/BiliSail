# media_kit_video 2.0.1 Windows 渲染与释放补丁

来源：[media-kit/media-kit](https://github.com/media-kit/media-kit)，已锁定的 Pub 包 `media_kit_video 2.0.1`。仅在构建目录复制其 Windows 源文件并修正渲染、交付和释放生命周期；不修改 Pub 缓存或 Android/macOS 实现。上游代码为 MIT，许可保存在 [LICENSE](LICENSE)，源文件版权头保留。Windows libmpv 二进制另通过[固定原生资产](../../native/mpv/SOURCE.md)更新，ANGLE 资产保持原版本。

`apply.cmake` 在 Windows 插件目标创建后校验七个上游源文件的 SHA-256，将副本作为该目标的编译输入。依赖升级或源文件变化时配置失败，必须重新审查补丁，不能静默跳过。普通 `flutter build windows` 与 MSIX 打包共用此入口。

修正包括：方法通道等待原生 Dispose 完成；停止渲染通知并排空在途任务；等待当前和旧纹理的注销回调；在有效 GL 上下文中同步释放 mpv 渲染上下文，然后销毁 ANGLE。没有纹理时不等待不存在的回调。重复到达、尚未执行的渲染通知只排一个任务；执行期间的新通知会在队列尾部再排一次，避免长时间占住共用渲染线程。暂停、SetSize 与视口变化仍强制重绘。

尺寸方法改用 Dart 原生适配器通过 SetSize 发送的显示尺寸，避免在共用渲染线程同步调用 mpv 核心 API。另由当前挂载的 VideoSurface 按布局与设备像素比发送视口上限，原生端按源显示比例限制中间输出纹理，不改变源分辨率或解码设置。新视口所有者立即解除旧上限；放大立即更新，缩小延迟 300 ms，原生单调 revision 防止异步通道请求逆序覆盖。首帧／暂停时的尺寸更新立即触发检查和绘制，主视频与预览继续使用 GPU 渲染。纹理交付和同步采用下述 GPU 队列补丁。

新增 `angle_gpu_queue.inc`：先初始化 ANGLE display，借用其 D3D11 device/即时上下文并启用线程保护，将 GL 绘制和复制放在同一 GPU 命令队列，使用 `glFlush` 提交而非逐帧 `glFinish` 等待。消费者明确使用同一个 D3D11 device 时可直接导出渲染纹理；不同或未知设备继续使用独立复制纹理，同一 draw revision 只复制一次。不能仅因两个设备属于同一显卡就共享可写纹理。缺少 ANGLE device 查询时保留原同步回退。不调用 `eglTerminate` 破坏其他组件仍在使用的默认 display，surface/context 继续显式释放。

五个 `.inc` 是编译到上游类中的替换方法，不是构建产物。生命周期/队列测试仍不依赖播放器、显卡或 Flutter 进程：`pwsh -File tool/test-windows-video-dispose.ps1`。真实 D3D11 纹理像素、同设备共享、未知消费者复制、resize 与共享 display 寿命由 `pwsh -File tool/test-windows-gpu-queue.ps1` 验证；此测试需要 Windows GPU，CPU 回读仅在测试 staging texture 中使用。布局所有权、设备像素比及缩小定时行为由 `packages/bili_player/test/video_viewport_test.dart` 验证。

故障证据、设计及验收范围见 [验证记录](../../../docs/validation/windows-preview-dispose.md)。

悬停卡顿原因、保留 GPU 的方案与 Profile 对照见 [预览出帧争用](../../../docs/validation/video-preview-contention.md)。`BILISAIL_VIDEO_RENDER_TRACE=1` 仅供该探针构建记录耗时；常规构建不加入逐帧诊断代码。

本次视口尺寸和 Windows GPU Engine 的受控 Profile 对照见 [渲染性能验证](../../../docs/validation/windows-video-render-performance-2026-10-11.md)。性能结论以实际设备和素材为限，不能把输出像素面积下降直接等同于 GPU 忙碌率下降。

`pwsh -NoProfile -File tool/test-windows-video-render.ps1 -Label run-720 -Height 720 -GenerateFixture` 可在仓库根目录生成或复用同参数的 50 秒测试片并执行 Profile 探针；结果写入 `build/validation/windows-video-render-run-720.json`、同名日志、`.fixture.json` 素材 SHA-256 元数据与 `windows-gpu-engine-run-720.jsonl`。传入 `-MediaDir` 可复用指定素材，`-ExePath` 可运行已保存的旧版 Profile 可执行目录做交替对照。脚本在 Flutter 构建后还原普通 CMake 配置。独立分轨检查使用 `tool/validation/windows_dash_render_probe.dart`，不会混入单文件 A/B 指标。
