# 官网弹幕与 Flutter Windows 合成边界对照

日期：2026-10-13。用户观察官网开关弹幕时 GPU 负载几乎不变，要求对照实际实现。本轮检查官网普通弹幕的 DOM/CSS/合成层，并核对当前 Flutter 3.47.6 的固定源码；没有更改产品代码或重复宣称 GPU A/B 验收。

## 官网实际使用 GPU 加速合成

使用独立 Chromium 155 浏览器检查 [BV1C3576fErj](https://www.bilibili.com/video/BV1C3576fErj/)，以及网页自动连播中的 [BV174B7BGE1L](https://www.bilibili.com/video/BV174B7BGE1L/)。普通弹幕容器是 `.bpx-player-row-dm-wrap`，显示中的弹幕采用独立 `div`，类名包含 `.bili-danmaku-x-dm`、`.bili-danmaku-x-roll`、`.bili-danmaku-x-show`。播放器内没有 Canvas；视频是原生 `<video>`，MediaSource blob。该观察不推广到高级弹幕、特殊效果或其他播放器模式。

滚动通过线性的 CSS `roll` 动画实现，动画关键帧改变横向 transform，并带 `translateZ(0)`；文字节点包含 `will-change: transform, opacity, top, left`。实查到 DOM 动画处于 running，且变换矩阵随时间改变。字体、粗体、阴影、透明度属于节点样式，并不是每帧让 JavaScript重新画出全部文字。

CDP `LayerTree.compositingReasons` 进一步确认：实际出现 `ActiveTransformAnimation`、`Trivial3DTransform`、`WillChangeTransform`、`WillChangeOpacity` 的合成层，视频层报告 `Video`。在 `BV174B7BGE1L` 约 5.94 秒，一个显示中的文字节点约 **18×20** 逻辑像素，活动 transform 图层约 **26×25**（含效果边界），视频层约 **668×376**。这比只看到 `will-change` 提示更强：本次确实存在加速 transform 合成层。

准确表述是：**普通弹幕由 DOM 表示，文字形成可复用内容，移动由浏览器 GPU 合成器处理**。文字栅格化本身可以按浏览器路径由 CPU 或 GPU 完成；没有证据将其描述成“全部字形都由专用 GPU shader 每帧绘制”。Chrome 的绘制/栅格化和合成区别见[官方图形架构](https://www.chromium.org/developers/design-documents/gpu-accelerated-compositing-in-chrome/)。

本次为独立游客浏览器，实际源约 640×359/360，没有复制应用登录凭据；初始化中的隐藏窗口会冻结/暂停媒体，已排除那部分状态作为加速动画证据，并使用焦点模拟检查播放与节点。部分相邻 DOM 采样会碰到等待显示的节点或暂停的动画，不能将其计为活动弹幕。本次未采集与应用 1080p、同设置同数量的 30 秒 GPU A/B，也未确认网页此次实际采用 MPO。

## 应用 Windows 路径的结构性成本

当前 Flutter SDK：3.47.6，framework revision `5fc346839b5d0eef006ed8404392afb4dfae428d`。以下使用该 revision 的源码，而不是从 master 推测本地版本行为。

本机既有 Release 测试 stderr 还确认使用 `Impeller (OpenGLESSDF)`。同版 Windows compositor 有 4x MSAA backing store 创建分支，其实际选中分支与 GPU 占比尚未单独量化；不能把这个静态分支写成额外收益已验证。

1. SDK `media_kit_video 2.0.1` 的 `video_texture.dart` 最终创建 Flutter `Texture`。mpv 输出是交付给 Flutter 的 RGB 外部纹理；它没有成为独立的 Windows 原生视频平面。
2. 引擎 [`TextureLayer::Diff`](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/flow/layers/texture_layer.cc#L19) 无法确认内容是否未变，仍将旧绘制区域标为 dirty，并把整个纹理矩形加入绘制区域。即使视频只是 30fps，弹幕触发的额外 Flutter 帧也会涉及视频区域。
3. [`ContainerLayer::DiffChildren`](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/flow/layers/container_layer.cc#L67) 明确不会跳过含 TextureLayer 的保留子树。`RepaintBoundary` 能隔离 Dart 重绘，不能据此声称视频 GPU 合成被隔离。
4. Windows [`CompositorOpenGL::Present`](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/windows/compositor_opengl.cc#L167) 接受一个 backing store；关闭 scissor，对 **整个 backing store 的 width×height** 执行 framebuffer blit，再 SwapBuffers。这里的 Flutter Layer 不等于浏览器独立提交的视频平面或弹幕平面。

因此，单条小弹幕可以让整张大视频区域继续参与 Flutter 绘制/窗口呈现。每条文字本身很小、位图也已缓存，仍无法避开这个成本。这里确认的是源码路径及其与已测帧率/面积变化的一致性，尚未用 GPU pass 时间把每一步成本单独量化。

## 对现方案的判断

现有时钟、轨道、过滤、容量和文字图像缓存可以保留；问题主要是 **Windows 呈现边界**。它把视频和弹幕绑定在同一个 Flutter 最终输出中，效率与官网独立加速图层不同。之前把滚动刷新降到约 59 次/秒、固定/空弹幕按需唤醒，是有效的开销控制，但没有解除上述耦合。

先前同视频 Release 实测见[修复记录](danmaku-frame-cadence-2026-10-13.md)：全屏可见弹幕短子区间从 23.76% 降至 10.38–10.58%，但全屏纯视频的 30 秒基线约 4.56–4.60%；弹幕出现时 Flutter 总帧时序仍约 74–76 次/秒。这支持“额外窗口帧昂贵”的方向，不能将该短子区间和纯视频 30 秒均值称为新的成对 30 秒对照。

官网观察不到明显 GPU 增量是合理的：少量小图层的内容可复用，transform 合成工作很轻，浏览器还可使用损伤区域管理和平台视频呈现。Chromium Windows 的 [SwapChainPresenter](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/ui/gl/swap_chain_presenter.cc) 提供 NV12/P010、DirectComposition 与 overlay 路径；实际是否提升到硬件 MPO 仍需呈现 trace。负载百分比接近不能推断 GPU 完全没有参与；进程读数还需包含浏览器 GPU 进程及可能由 DWM 承担的工作。

## 后续优化的优先级

| 方向 | 能处理的成本 | 本次结论 |
| --- | --- | --- |
| 保留每条文字图层，只更新 transform | 文字层重新录制及密集绘制指令 | 可做受控原型，但当前视频 Texture dirty 和全视图 Present 仍在，不能保证接近官网 |
| GPU 字形图集/实例化 | 高密度文字绘制与命令数量 | 当前单条弹幕现象未证明这是主要瓶颈，需密集数据再决定 |
| Windows 独立视频与 UI/弹幕平台合成 | 弹幕动画反复带动视频及大窗口输出 | 优先进行原生验证，验证后再决定产品迁移 |

原生验证应保留共享 PlaybackSession 和弹幕时钟，比较实际 1080p 页面、弹幕实际可见数、显示帧率、 GPU 频率和至少 30 秒采样；同时验证透明度/遮挡、DPR/缩放、全屏、窗口移动/最小化、多标签、截图和生命周期。不要把 Windows 可行性写成 Android/macOS 已验收，也不直接复制官网 bundle 或引入浏览器作为播放器运行时。

只读证据保存于 `output/playwright/danmaku-reference/official-danmaku-live-composition.txt` 及相关 DOM 采样；其中只记录样式、几何、公共 BV 和图层原因，不记录登录 Cookie、签名媒体 URL 或弹幕正文。第三方 bundle 下载仅用于本地检查，没有纳入源码或产品依赖。
