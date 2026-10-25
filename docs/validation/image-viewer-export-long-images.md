# 图片查看器保存、复制与长图

日期：2026-10-25。

## 行为与平台

评论、首页／空间动态继续共用 [ImageViewer](../../lib/shared/ui/image_viewer.dart)。工具栏增加“保存图片”“复制图片”，仅在受支持平台显示，原图未就绪和导出进行中禁用。操作由[图片控制器](../../lib/features/image_viewer/application/image_viewer_controller.dart)捕获点击时的原图；不重新请求 CDN。切图、账号变化和关闭后，迟到的完成反馈不能覆盖新状态。明确点击后的系统写入不因切图而回滚；失败允许显式重试，30 秒超时提示先检查目录／粘贴结果，不自动重放。

[平台适配器](../../lib/core/platform/image_export_service.dart)只向原生端传递文件字节、依据实际文件签名确定的扩展名和 MIME，不传远端 URL、查询参数或账号凭据。没有新增第三方依赖。保存不转码，生成唯一文件名，保留原始格式与动图数据。

| 平台 | 保存位置 | 图片剪贴板 |
| --- | --- | --- |
| Windows | `SHGetKnownFolderPath(FOLDERID_Pictures)` 返回的系统图片目录下 `BiliSail/`，兼容目录重定向 | WIC 解码第一帧为原尺寸 BGRA DIBV5；PNG 同时放入原始 PNG 数据，供不同接收程序使用 |
| macOS | `FileManager.picturesDirectory` 下 `BiliSail/` | `NSImage` 写入系统 `NSPasteboard`；最终粘贴取决于接收程序支持的图片格式 |
| Android 10+ | `MediaStore.Images`、`Pictures/BiliSail/`，完成写入后清除 `IS_PENDING`，供相册发现 | 私有缓存中的原文件经只读、URI 授权的 ContentProvider 提供给系统剪贴板，不复制 URL 文本 |
| Android 7–9 | 系统 `Pictures/BiliSail/`，用户授予旧存储权限后写入并触发媒体扫描 | 同上，复制不要求公共存储权限 |

Android 剪贴板保留最近四份文件，最多 128 MiB，关闭查看器不删除当前剪贴板文件；后续复制淘汰旧文件。Provider 只接受固定 UUID 文件名、图片扩展名和只读打开，不暴露其他缓存。macOS 的 Debug/Profile 和 Release 均增加图片目录读写 entitlement；[发布检查](../../tool/macos-release-validation.ps1)同步要求该权限，继续拒绝其他额外／重复／禁用权限。

## 长图根因与新边界

旧[原图仓储](../../lib/features/image_viewer/data/network_original_image_repository.dart)在读取编码图片尺寸后，主动拒绝任一边超过 **16,384 px** 或总像素超过 **32 × 1024 × 1024** 的文件。该判断发生在原图下载成功后、Flutter 像素解码前，是客户端限制。没有具体失败 URL，不能断言每一次长图失败都由此造成，CDN 非 200、超时、损坏或不支持的格式仍分别可能失败；本轮没有新增 API，也未用真实图片 URL 做在线核对。

现将编码原图和显示预览分别限额：

- 编码文件仍最多 **32 MiB**、下载 deadline **30 秒**；长宽分别最多 **262,144 px**，总像素最多 **64 × 1024 × 1024**（约 6711 万），限制极端解码输入。
- 原图尺寸和字节保持完整。Flutter 主预览最长边最多 **8192 px**、解码最多 **16 × 1024 × 1024** 像素；背景同时限制在 **256 × 256** 包围框内，避免仅指定宽度使长图背景仍生成超高纹理。按 [Flutter ResizeImage](https://api.flutter.dev/flutter/painting/ResizeImage-class.html) 的尺寸解码机制降低预览内存与纹理尺寸，不承诺无限尺寸或原分辨率长图文字清晰度。
- 缩放布局仍使用原图长宽，最低缩放改为 `0.0001`，适应窗口能容纳极长图；大图显示“缩小预览”说明。底部工具栏按实际高度参与布局，窄窗口换行不会覆盖预览视口。
- 保存使用编码原文件；图片剪贴板使用原文件／原尺寸第一帧，接收程序仍可能自行转换。Windows WIC 不支持的编解码格式会明确复制失败，不报虚假成功。
- 公共传输层新增有类型的体积超限错误，原图查看器将 Content-Length 与分块累计超限归为大小限制，而非笼统的下载失败。取消、HTTPS／公开主机校验、无凭据传输和代次隔离沿用原实现。

## 验证

- [原图仓储测试](../../test/features/image_viewer/original_image_repository_test.dart)：生成 24,000 px 长图／宽图，验证仓储接受、原字节保留与有界尺寸实际解码；覆盖体积、尺寸、像素上限及取消。原有 16,384 px 判定会拒绝这些长图。
- [导出控制器测试](../../test/features/image_viewer/image_viewer_controller_test.dart)覆盖未加载、重复点击、当前原图、失败重试、切图／账号／关闭后的迟到完成；[平台通道测试](../../test/core/platform/image_export_service_test.dart)覆盖签名格式、原字节、平台能力和错误传播；[宽窄屏组件测试](../../test/features/image_viewer/image_viewer_test.dart)验证两个按钮、保存路径／复制反馈与不额外下载。
- 双窗口原图／路由和公开图片传输回归一并执行，定向合计 29 项通过。
- [Windows 原生回归](../../tool/test-windows-image-export.ps1)在独立窗口站、独立桌面使用真实剪贴板，不打开或覆盖交互用户剪贴板。验证 WIC 原图转 DIBV5、PNG 原字节、损坏文件失败保留前次剪贴板、24,000 px 长图复制不缩小／裁切、系统图片目录保存与原字节一致，并删除本次生成的测试文件。
- Windows 原生资产按 `tool/build-download-mux.ps1 -Target windows-x64` 准备；Windows Release 构建通过。Android `:app:compileDebugKotlin -x compileFlutterBuildDebug` 通过，只证明原生源码／manifest 相关依赖可编译，未构建 APK 或设备安装。
- 本机未发现 DTD／调试应用，热重载调用因无活动连接未执行。macOS 无本机工具链；Android／macOS 真实相册保存、权限交互和跨应用粘贴，以及 Windows 实际接收程序粘贴仍需设备验收。本轮未测性能。

`tool/check.ps1 -SkipPub` 最终完整通过：根应用 2,237、`bili_api` 446、`bili_player` 81、`bili_danmaku` 93、`bili_mux` 2 项，共 **2,859 项**；五处格式、静态分析及打包边界检查通过。mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不能视作原生封装回归通过。此前的检查先因本次新增 Pictures entitlement 尚未同步发布白名单而失败（已修复），随后因同期新增的 `test/shared/ui/app_dialog_test.dart` lint 失败；最终检查时同期 lint 已消除，本任务未修改该文件。

日志位于本机忽略目录 `build/validation/image-export-{check,windows-build,android-compile}.log`。计数包含工作区同期修改，不代表全部由本任务新增。`git diff --check` 通过，用户和其他任务的修改保留；本任务未提交或推送。
