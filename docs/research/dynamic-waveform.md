# HiMusic 动态高解析波形研究与实现建议

日期：2026-09-06

## 结论

HiMusic 应把当前“整首歌固定压缩为少量柱形”的模型升级为两层波形：一个始终显示整曲的概览层，以及一个可缩放、可平移并跟随播放头的细节层。底层数据采用每个时间窗的 `min/max` 峰值对，并建立 2 倍递降的多分辨率金字塔。渲染时只读取当前视口对应层的峰值，绘制成本因此只与屏幕宽度有关，与歌曲时长和 FLAC 采样率无关。

这符合 BBC `audiowaveform`、`waveform-data.js`、Peaks.js、wavesurfer.js 和 Audacity 的共同设计。BBC 的生成器先合并声道，再对每组 N 个输入样本输出一对最小值/最大值；其 `waveform-data.js` 可以从基础波形向更粗粒度重采样，但明确不允许从粗数据反推更细的数据。[audiowaveform README](https://github.com/bbc/audiowaveform/blob/master/README.md) [waveform-data.js API](https://github.com/bbc/waveform-data.js/blob/master/doc/API.md)

“动态波形”在这里指时间轴随真实播放位置平滑推进、可以缩放和平移的确定性音频包络。实时 FFT 频谱是另一种可视化，需要播放器暴露解码后的实时 PCM；不应通过随机柱形或动画伪装成音频数据。`just_audio` 的维护者也将“预先提取整曲波形”和“播放器实时音频缓冲可视化”明确区分为两条数据通路。[just_audio issue #97](https://github.com/ryanheise/just_audio/issues/97)

## 理论基础

### 为什么使用 min/max，而不是抽样或平均值

若一个像素对应 N 个音频样本，随机抽取一个样本会漏掉短促的鼓点和削波；平均值还会让正负样本互相抵消。每个窗记录：

```text
peak[i] = (min(samples[a:b]), max(samples[a:b]))
```

便可保留该窗的上下极值。BBC `audiowaveform` 正是按这种方式生成波形点；Peaks.js 将每个像素的 `min` 和 `max` 沿相反方向连接成闭合形状。[audiowaveform manual](https://github.com/bbc/audiowaveform/blob/master/doc/audiowaveform.1) [Peaks.js WaveformShape source](https://github.com/bbc/peaks.js/blob/master/src/waveform-shape.js)

这种表示还能无损地向下合并极值：

```text
parent.min = min(left.min, right.min)
parent.max = max(left.max, right.max)
```

因此可以从最高解析层线性生成 1/2、1/4、1/8……解析度的层级，而无需再次解码 FLAC。这里的“无损”仅指每个合并窗的极值不丢失，并不表示可以还原 PCM。

Audacity 使用类似的分层摘要思路：根据每屏像素对应的样本数，在原始样本、每 256 样本的 min/max/RMS 摘要和每 64K 样本的摘要之间选择，并把波形数据与位图分别缓存。[Audacity WaveDataCache.h](https://github.com/audacity/audacity/blob/master/au3/libraries/au3-wave-track-paint/waveform/WaveDataCache.h) [Audacity WaveDataCache.cpp](https://github.com/audacity/audacity/blob/master/au3/libraries/au3-wave-track-paint/waveform/WaveDataCache.cpp)

### 分辨率与视觉振幅

建议基础层采用 **512 peak pairs/second**，然后逐级减半。该值意味着一个基础窗约 1.95 ms：44.1 kHz FLAC 每窗约 86 个样本，192 kHz FLAC 每窗约 375 个样本。五分钟单声道包络采用两个 `int16` 值时，基础层约 600 KiB；包含所有二倍金字塔层仍低于基础层的两倍。长曲目可将基础点数限制在 2,000,000，避免有声书或整场演出产生过大的缓存。

峰值数据应保留相对于数字满幅 `[-1, 1]` 的线性值，不能在落盘时把每首歌的最大峰统一拉到 1。这样不会把安静录音伪装成响亮录音。为让安静段在小高度控件中仍可见，可只在绘制阶段提供视觉增益，例如 `sign(x) * pow(abs(x), 0.65)`，或提供线性/dB 两种显示模式；缓存本身保持原值。Audacity 也将显示范围、dB 模式和 RMS 显示作为绘制参数处理，而非破坏源波形数据。[Audacity WaveformView.cpp](https://github.com/audacity/audacity/blob/master/au3/src/tracks/playabletrack/wavetrack/ui/WaveformView.cpp)

## 多分辨率数据设计

### 推荐数据结构

每首曲目的缓存包含：

- 格式 magic、版本、采样率、声道模式、基础 points/second、时长；
- 源标识：SMB 路径、文件大小、修改时间；修改时间不可靠时再加入首尾各 64 KiB 的快速指纹；
- 各层的 points/second、点数、文件偏移和校验值；
- 每点两个 little-endian `int16`：`min`、`max`。

默认将所有声道合成一个包络，方法是取同一窗内所有声道的最小和最大值。后续可增加双声道模式，但家庭播放器的首要目标是清晰、流畅的单条时间轴。

基础层为 `512 pps`，其余层为 `256, 128, 64, ...`，直到最粗层不超过约 2,048 点。视口选择“每个逻辑像素约 1–2 个峰值点”的最接近层；若仍有多点落在同一像素，再用 min/max 合并。绝不能只取其中一个点。

Peaks.js 的缩放单位是 samples-per-pixel，并缓存已经重采样的缩放级别；创建新级别时，它从最接近的更细缓存层重采样。缩放时若播放头可见，会保持播放头在窗口中的像素位置，否则保持窗口中心对应的时间不动。[Peaks.js zoom view source](https://github.com/bbc/peaks.js/blob/master/src/waveform-zoomview.js) [Peaks.js API](https://github.com/bbc/peaks.js/blob/master/doc/API.md)

### 与当前 just_waveform 的关系

`just_waveform` 已支持以 pixels-per-second 或 samples-per-pixel 指定提取解析度，目标平台为 Android、iOS 和 macOS。[just_waveform README](https://github.com/ryanheise/just_waveform) [WaveformZoom API](https://pub.dev/documentation/just_waveform/latest/just_waveform/WaveformZoom-class.html) [just_waveform pubspec](https://github.com/ryanheise/just_waveform/blob/master/pubspec.yaml)

HiMusic 可以继续用它完成首版高解析提取，但需改变后处理：

1. 以 `WaveformZoom.pixelsPerSecond(512)` 提取，保留全部原始 min/max 点；
2. 不再在解析阶段固定压成 256 个 bins；
3. 在后台 isolate 中构建二倍金字塔并原子写入持久缓存；
4. UI 按视口按需读取所需层，不把所有层转成大量 Dart 对象常驻内存。

`just_waveform` 当前只声明 Android、iOS、macOS，因此 Windows 仍需独立原生解码后端或另选跨平台解码器，不能把本次三平台验证外推到 Windows。[just_waveform pubspec](https://github.com/ryanheise/just_waveform/blob/master/pubspec.yaml)

## 动态交互模型

建议播放器同时提供以下两个视图：

1. **概览波形**：整首歌固定在控件宽度内，显示已播放区域、播放头和细节视口的半透明窗口。点击或拖动可快速 seek。
2. **细节波形**：默认显示播放头附近 30 秒；提供 10、30、60、120 秒和“整曲”档位，也支持触控板/双指缩放。播放时波形在固定播放头下平滑移动。

跟随规则应可预测：播放时默认保持播放头在控件宽度约 35%–50% 处；用户手动平移后暂时退出跟随，并显示“回到播放位置”；再次播放、点击该按钮或数秒无操作后恢复跟随。Peaks.js 的 zoom view 同样具有独立 overview/zoomview、起始时间、缩放、滚动和自动跟随播放头的概念。[Peaks.js README](https://github.com/bbc/peaks.js/blob/master/README.md) [Peaks.js API](https://github.com/bbc/peaks.js/blob/master/doc/API.md)

播放头的视觉更新应跟随屏幕帧，而非只依赖播放器低频 position 事件。播放器事件用于定期校准基准位置；两次事件之间用单调时钟和播放速率插值。Flutter `Ticker` 在启用时每帧调用回调，且在界面不可见时可被 `TickerMode` 静音，适合只在播放期间驱动进度层。[Flutter Ticker](https://api.flutter.dev/flutter/scheduler/Ticker-class.html)

wavesurfer.js 也使用单一 `requestAnimationFrame` 循环，在播放期间每帧读取真实播放时间并更新进度；暂停后停止循环。[wavesurfer.js FrameScheduler](https://github.com/katspaugh/wavesurfer.js/blob/main/src/frame-scheduler.ts) [wavesurfer.js playback tick](https://github.com/katspaugh/wavesurfer.js/blob/main/src/wavesurfer.ts)

## Flutter 渲染架构

推荐拆成三个独立层：

```text
WaveformViewport
├── StaticWaveTiles       峰值形状，仅在曲目/缩放/视口跨 tile 时更新
├── PlayedColorOverlay    复用同一形状，以裁剪区域表现已播放颜色
└── PlayheadAndGestures   每帧更新的细线、时间和拖动反馈
```

具体约束如下：

- 每个 tile 建议宽 512–1,024 个逻辑像素，缓存为 `ui.Picture`；键包含曲目标识、层级、tile 序号、控件高度、主题和 devicePixelRatio。
- 一帧只组合当前视口及左右预取各一个 tile；缩放或滚动跨界时异步准备下一 tile。
- 播放时复用静态 tile，只移动/裁剪合成层并重绘播放头；不要每帧重建 Widget、Path 或峰值 List。
- 用一个连续闭合 Path 描绘上边的 max 和反向的 min，避免每个峰创建独立对象；柱形风格可作为用户选项。
- 波形层和播放头层分别放在 `RepaintBoundary`。Flutter 官方说明，重绘边界会为子树建立单独 display list，父子在不同时间重绘时可以复用既有记录。[Flutter RenderRepaintBoundary](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary-class.html)
- 拖动期间先更新预览位置，限频向播放器发 seek；松手后发送最终精确 seek。这样 SMB 跳读不会随每个 pointer event 重启。

wavesurfer.js 对长波形采用多个 canvas，只切出可见数据，滚动时惰性绘制需要的 canvas，并在累计过多时清理旧 canvas；进度颜色则复用已画波形，通过合成遮罩着色。这些做法可直接映射为 Flutter tile 和裁剪层。[wavesurfer.js renderer](https://github.com/katspaugh/wavesurfer.js/blob/main/src/renderer.ts)

## SMB、缓存与任务调度

路由器 SMB 是本项目最慢且最不稳定的环节。一次波形生成应只顺序读取文件一遍，并且不能与播放争夺带宽：

- 播放开始后先保证播放器缓冲稳定，再以低优先级启动波形提取；
- 同时最多一个解码任务，切歌时立即取消尚未开始的任务；原生插件无法中断时丢弃过期结果；
- 先读取持久峰值缓存，命中时不再访问整首 FLAC；
- 缓存写入临时文件并在完成校验后 rename，应用被关闭时不会留下“看似成功”的半文件；
- 采用磁盘 LRU，例如总量 256 MiB，并保留当前播放曲目；
- 大文件不应因为 256 MiB 门槛永久失去波形。更合理的限制是峰值点数/缓存大小，并在解码输入侧流式读取；在完成这项能力前，可保留现有限制并明确提示。

wavesurfer.js 官方文档明确指出，浏览器完整解码大音频可能因内存失败，并推荐为大文件提供预解码 peaks；有 peaks 和 duration 时也可配合流式播放。[wavesurfer.js documentation](https://wavesurfer.xyz/docs/)

## 建议的实施顺序

### P0：高解析数据与可见窗口

- 将提取解析度改为 512 pps；解析器保留完整 min/max，不再固定 256 bins。
- 构建 2 倍金字塔并持久缓存。
- 实现整曲概览 + 30 秒细节视口，以及 10/30/60/120 秒/整曲缩放。
- 只绘制可见峰值，手势 seek 使用精确的 `time = viewportStart + x / width * viewportDuration`。

### P1：平滑播放与渲染隔离

- 用 Ticker 只驱动播放头/平移合成层，并用播放器位置流校准漂移。
- 引入 tile picture cache，静态波形与动态覆盖层分离。
- 完成用户平移暂停跟随、返回播放位置和缩放锚点规则。

### P2：渐进生成与平台覆盖

- 原生解码器分块输出 peaks，使未缓存曲目在解码过程中逐段出现波形。
- 去除按音频文件大小跳过的限制，改为峰值缓存预算。
- 为 Windows 加入等价解码后端，并用同一二进制峰值格式保证跨平台缓存一致。
- 若需要“随音乐跳动”的频谱，再单独设计实时 PCM/FFT 通路；它不属于时间轴波形的替代品。

## 验收与性能门槛

功能验收应覆盖真实本地 FLAC 和真实 SMB FLAC，而不只用固定数组：

- 44.1/16、96/24、192/24 FLAC 的时长、峰值位置和 seek 对齐；
- 包含短脉冲、静音、削波、左右声道不同内容的合成夹具，确认任何缩放层都不会漏掉极值；
- 缩放前后播放头锚点时间误差小于一个屏幕像素对应的时长；
- 缓存命中时不重新读取完整音频，源文件修改后缓存失效；
- 快速切歌、关闭窗口和 SMB 断线不会展示上一首歌的结果或遗留半缓存。

性能验收建议在 macOS Retina、普通 Android 手机和目标 Android TV 上分别测量：

- 播放状态下绘制复杂度为 `O(viewportWidth)`，与整曲点数无关；
- 60 Hz 设备的 UI frame build+raster P95 小于 16.7 ms；若设备支持 120 Hz，则目标小于 8.3 ms；
- 稳态播放期间不持续分配与屏宽成比例的 List/Path，不触发整页 rebuild；
- 已缓存曲目波形首屏目标 150 ms 内出现；
- 当前曲目峰值和 tile 的常驻内存设置明确上限，并通过 profile build 的时间线和内存快照验证，而非从单元测试推断。

## 许可边界

上述项目适合作为架构和行为参考，但不应直接复制强 copyleft 项目的实现代码。Audacity 为 GPL 系列许可；BBC `audiowaveform`/`waveform-data.js` 的许可也需在复用代码前逐项核对。HiMusic 可以独立实现通用的 min/max 金字塔算法，或继续调用 MIT 许可的 `just_waveform` 提取接口，并在引入任何源代码前完成依赖许可审查。[Audacity license](https://github.com/audacity/audacity/blob/master/LICENSE.txt) [just_waveform license](https://github.com/ryanheise/just_waveform/blob/master/LICENSE)
