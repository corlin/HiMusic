# V0 开发记录

本次开发范围：可运行的目录播放器原型，包含只读 SMB / 本地文件来源、范围读取桥接、FLAC 播放及电视方向键操作入口。

不将 V1 的完整标签扫描、SQLite 音乐库、跨设备同步或 V0 全部实机验收算作本次已完成。

## 技术决策

- Flutter SDK 放在 `.tooling/flutter`，不提交 SDK。
- 候选 `dart_smb2 0.1.2`：Dart 包 BSD-3-Clause，底层 libsmb2 另有许可证义务；发布前应保留完整第三方声明并核验原生构建来源。通过 worker pool 执行 SMB 2/3 读取，不提供写操作。
- 将读取统一为只读、按偏移取字节的来源接口；设备内 HTTP 服务仅绑定 IPv4 loopback，通过随机会话令牌注册歌曲，限制并发与块大小。
- 使用真实本地文件验证 HTTP Range 行为，不以模拟 SMB 结果证明路由器兼容性。
- 播放采用 just_audio；Windows 使用 media_kit 后端。移动端后台完整集成留在后续验收批次。
- 首批不持久化密码，仅保留在当前连接内存中；保存连接功能须使用系统安全存储后再开放。

## 验证边界

HTTP 范围读取协议、只读目录边界、流式读取取消和界面交互为本地验证重点。
真实路由器认证、并发和电视解码需要用户设备；缺少连接信息时继续独立实现，不伪造成功状态。

## 本批实现与验证（2026-09-05）

已实现：具名 SMB 配置、只读目录浏览、本地目录、循环/上下曲/暂停、目录音频队列、拖动结束定位、失败操作重试与回环范围服务。原型密码仅在内存使用，暂未提供保存连接。

- Flutter 3.47.2 / Dart 3.13.2；macOS 27.0 / Xcode 26.6。
- 静态分析通过；7 项单元/界面测试通过。
- macOS 原生集成：3 种合成 FLAC（16/44.1、24/96、24/192）可加载、播放推进及定位；测试静音，不验证扬声器实际输出规格。
- 原生回归：连接失败重试、暂停后目录失败重试、关闭期间迟到连接清理通过。
- 本机 Impacket 0.13.1 SMB2 服务（仅监听 127.0.0.1:1445，仅共享测试样本）实测认证、列目录、读取 FLAC 文件头、通过桥接解码 24/96 和定位通过。此结果不代表中兴路由器兼容性。
- 代码复核发现并修正了错误重试目标、意外恢复播放、拖动最终位置丢失、迟到连接释放和重试 URL 累积问题。
- Android SDK 与 NDK 安装到 `.tooling/android-sdk`；使用 `scripts/flutter.sh` 隔离环境。全局 Gradle 镜像脚本与 Flutter 新版仓库约束冲突，项目独立 `GRADLE_USER_HOME` 避开该冲突，不修改用户全局配置。

## 复现 SMB 集成测试

测试工具不作为产品依赖：

```sh
uv venv --python /usr/bin/python3 .tooling/smb-test-venv
uv pip install --python .tooling/smb-test-venv/bin/python impacket==0.13.1
.tooling/smb-test-venv/bin/python scripts/smb_fixture_server.py
# 另一终端；测试完成后停止上述服务器
./scripts/flutter.sh test integration_test/smb_test.dart -d macos
```

脚本中的账号密码仅是公开的本机测试凭据，不连接或修改用户路由器。

## 仍未验收

实际 BE7200 MAX 连接、两台设备并发、Android TV 解码与遥控器、休眠/硬盘唤醒、持续播放和无缝音频；iOS / Windows 运行；手机后台服务、本地文件授权、标签库和持久化均需后续批次。


## 产物确认（2026-09-06）

- Android Debug APK 构建成功，`apksigner verify` 通过；minSdk 24 / targetSdk 36，包含 arm64-v8a、armeabi-v7a、x86_64 与 Leanback 启动入口。
- 构建存在 SDK XML 版本警告，未阻止 APK 构建；仍需实际电视安装和播放验收。
- 正常应用入口 macOS 原生测试通过：首屏显示、键盘打开连接表单、切换电视布局，无框架异常。
- 初次窗口查看命中了集成测试遗留进程的黑色窗口；清理该进程后使用正常入口原生测试验证。不可把测试结束后的窗口当作正常运行结果。
- 本机产物位于 `artifacts/`，不提交大型二进制文件。Android 为开发调试签名包，macOS 为本机构建，不是商店签名/公证发布版。
- macOS Release 构建成功（构建目录约 46 MB），复制为 `artifacts/HiMusic.app` 并打包 ZIP；通过实际窗口截图确认正常首屏显示。
- 产物校验和写入 `artifacts/SHA256SUMS.txt`。

## 0.1.1 音量与本机输出（2026-09-06）

- 增加顶部声音入口、播放栏音量滑块、百分比与静音/恢复；音量调整不受播放操作 busy 状态丢弃，串行合并最新目标。
- macOS 通过 CoreAudio 读取实际输出设备，选择后核验系统默认输出；界面明确标注影响其他应用。
- Android API 34+ 尝试系统输出选择器，较旧系统或未能显示时进入声音设置；iOS 注册 AVRoutePickerView；Windows 打开声音设置。
- 本次设备选择为本机音频路由，不是家庭远程设备配对或播放接力。
- 静态分析与 7 项既有测试通过；macOS 原生音量/静音/最终值验证通过；实际输出设备枚举及重选当前设备通过（未主动切到其他设备）。
- 代码复核未发现新增实质问题。真实 Android/iOS 路由切换、外接蓝牙/HDMI 热插拔及 Windows 入口仍待对应设备验收。

- 0.1.1+2 Android Debug APK 签名校验通过，macOS Release 构建通过，iOS 模拟器构建通过（不代表真机路由选择验收）。
- 新版产物：`artifacts/HiMusic-0.1.1-android-debug.apk`、`artifacts/HiMusic-0.1.1-macos.zip`。

## 0.1.2 音频波形（2026-09-06）

- 播放栏增加真实音频峰值轮廓、已播放高亮、点击/拖动定位与左右键五秒跳转。
- 使用 just_waveform 原生提取；显式按 20 字节头部解析 8/16-bit 波形文件，避免插件 Dart 解析器的偏移问题。
- 来源分块读取，每块最多 128 KiB；播放缓冲时让出读取。单曲临时副本上限 256 MiB，峰值内存缓存上限八首，切换来源清空缓存。
- 切歌通过代次丢弃过期结果；原生解码串行，无法中途取消。关闭先释放播放器，原生分析自行完成临时文件清理。文件读取等待有 25 秒上限，底层 SMB 连接由来源关闭流程释放。
- 静态分析通过；12 项单元/组件测试通过，包括真实样本偏移、静音、峰值聚合、点击定位、切歌结果隔离、关闭不等待解码与临时文件清理。
- macOS 原生测试通过：生成 PCM 音频的静音/有声区间与波形一致；16/44.1、24/96、24/192 FLAC 均成功提取。既有三项原生播放/跳转/重试/音量回归通过。
- Windows 暂不支持波形；真实路由器读取性能、Android TV 遥控器与 iOS 真机波形尚待验收。
- Android Debug APK（签名校验通过）、macOS Release 和 iOS 模拟器编译通过。0.1.2 产物与 SHA-256 位于 `artifacts/`；不代表对应移动设备真机验收。

## 0.1.3 macOS 波形修复（2026-09-06）

- 修复 macOS 沙盒返回的缓存目录尚不存在时，`createTemp` 抛出 `PathNotFoundException`，导致所有 FLAC 只显示波形失败的问题。
- 新增缓存根目录缺失回归测试，以及播放器联动的 macOS 波形界面测试。
- 使用 `/Users/corlin/Desktop/music` 中的真实 FLAC，经测试容器授权副本验证：原生峰值提取成功，播放栏显示 64 px 波形。
- 13 项单元/组件测试、macOS 波形界面测试及三类 FLAC 播放回归通过；macOS Release 与 Android Debug 构建通过。
- 修复版产物为 `HiMusic-0.1.3-macos.zip` 与 `HiMusic-0.1.3-android-debug.apk`。

## 0.2.0 动态高解析波形（2026-09-06）

- 参考 BBC audiowaveform / Peaks.js、wavesurfer.js、Audacity 与 Flutter 渲染边界，研究记录见 `docs/research/dynamic-waveform.md`。
- 基础解析度由 20 pps 且固定压缩 256 点，提升为 512 pps、最多 180,000 点；约覆盖普通六分钟歌曲的完整基础解析度。
- 新增 2 倍 min/max 峰值金字塔。最大内存波形的视口查询每帧最多访问一屏目标点数，不扫描整曲；查询返回只读视图，避免每帧复制峰值列表。
- 新增自动跟随的细节波形、整曲概览、视口框、时间网格、渐变真实振幅、已播放着色与 5/10/30/60/120 秒及整曲缩放。
- 使用 Ticker 在播放器 ready 且 playing 时逐帧读取校准位置；暂停、缓冲或结束时停止，避免无效刷新。
- 新增版本化峰值磁盘缓存，使用临时文件加 rename 原子提交，按来源、路径、大小与修改时间失效，总量限制 256 MiB 并按最近使用淘汰。
- 16 项单元/组件测试通过；三种 FLAC 原生播放/提取、真实 FLAC 首次生成与缓存命中、5 秒缩放和逐帧位置推进通过。
- macOS Release 实际窗口检查通过：细节波形、概览视口、时间、音量和播放控制在默认窗口内完整显示；删除重复进度条并将输出设备入口并入控制行。
- 复核后为不可用、分析中和失败状态恢复独立 seek 滑块；动态细节波形按半个视口分片缓存 Path，逐帧仅平移、裁剪和绘制缓存路径。

## 0.3.0 资料库界面（2026-09-06）

- 桌面宽屏新增固定资料库侧栏、搜索、最近专辑陈列、曲目表与常驻底部播放器，窄窗口自动切换紧凑布局。
- 本地目录、SMB、目录导航、播放、跳转、音量和输出设备继续使用真实控制器；搜索会即时筛选当前目录，电视模式会增大曲目行高和主要字号。
- 六张资料库封面与独立的正在播放封面均为项目内置位图资源，避免网络依赖和占位图。
- 波形播放器增加紧凑显示模式，将细节与概览压缩到 68 px，同时保留双层波形、视口框、时间刻度、点击和拖动跳转。
- 设计验收以 1440×1024 的选定视觉稿和同尺寸 macOS 实现截图并排对照，结果记录于 `design-qa.md`。

## 0.4.0 本地歌词（2026-09-08）

- 支持音频内嵌同步歌词、同名 `.lrc` 和内嵌纯文本歌词，按此顺序选用；不访问在线歌词服务。
- LRC 支持 UTF-8、UTF-8 BOM、GB18030、分钟秒时间戳、多时间标签和毫秒偏移。单个旁挂文件限制 2 MiB，解析缓存最多保留 128 首。
- 本地目录与 SMB 只查找歌曲所在目录的同名歌词；iOS/Android 文件选择器只允许读取用户同时选中的歌词文件。歌词文件不会出现在曲目列表中。
- 播放进度驱动当前歌词高亮；点击歌词可定位。手动滚动时暂停自动跟随，四秒后恢复，也可立即点“回到当前歌词”。
- 小屏“正在播放”页可切换封面与歌词，宽度达到 980 px 时并排显示。
- `flutter analyze` 无问题，完整测试 54 项通过。macOS、签名 iOS 和 Android Release 构建成功，产物分别为 `build/macos/Build/Products/Release/himusic.app`、`build/ios/iphoneos/Runner.app`、`build/app/outputs/flutter-apk/app-release.apk`。
- 最新 iOS Release 已安装并启动于 `corlin17mx`（iPhone 17 Pro Max），进程与非白屏截图已核验，截图保存在未提交的 `build/verification/corlin17mx-lyrics-build.png`。
- 实机当时停留在已有 SMB 输入弹窗，尚未完成设备端选择音频与 LRC 后的滚动/点击验收；真实 SMB 同名歌词读取也仍需共享盘样本。

## 0.5.0 元数据曲目表（2026-09-11）

- 元数据解析链路（`MetadataIndex` 代次扫描/取消/LRU、`TrackMetadata` 字段、LRCLIB 用元数据参数匹配）在 0.4.0 已完成；本版落地 UI：宽屏曲目表新增**艺术家、专辑、时长**三列，窄屏保持紧凑副标题。
- 表头点击排序：标题/艺术家/专辑/时长/格式，升序 → 降序 → 回到自然顺序循环；目录条目固定置顶、元数据缺失排后、排序稳定。排序逻辑收敛到纯函数 `lib/util/track_sort.dart`，与 UI 解耦。
- 侧栏"专辑""艺术家"分区落地：按当前目录音频聚合（未知专辑/未知艺术家归组），点入后回到曲目表并带筛选 chip，可一键清除；目录变化自动清筛选。侧栏"播放列表"仍为占位（0.6.0 队列功能落地）。
- 顺手修复既有宽屏隐患：侧栏品牌行在窄容器下文本无法收缩（测试字体下溢出 4.8 px），品牌行文本改为可收缩省略，TopBar 宽版品牌改用 Expanded 承接。
- `flutter analyze` 无问题（排除未跟踪的联网调试测试）；完整测试 67 项通过（原 54 + 排序 9 + 分区/表头组件 4）；macOS Debug 构建与启动冒烟通过。
- 0.5.0 规划文档：`docs/superpowers/specs/2026-09-11-metadata-queue-background-design.md` 与 `docs/superpowers/plans/2026-09-11-metadata-queue-background.md`（含 0.6.0 队列/播放模式与 0.7.0 后台播放的多端全做决策）。

## 0.6.0 播放队列与播放模式（2026-09-11）

- **随机播放**：走 just_audio 原生 shuffle（`shuffleModeEnabled`，Dart 侧 shuffleOrder 语义，一轮内不重复）；macOS/iOS/Android/TV 用 just_audio 默认后端语义可靠，Windows 的 media_kit 后端将 shuffle 委托原生（行为差异已知，未承诺特殊处理）。`PlayerController.toggleShuffle()` 乐观更新状态、不中断当前曲目；`shuffleModeEnabledStream` 与外部变化双向同步。
- **队列管理与入口**：`playEntry` 重构为共享的 `_startQueue`（按目录构建队列+随机/顺序起播），新增 `playAll({shuffle})`（目录"播放全部/随机播放"入口，宽屏标题行，无音频时禁用）、`playAt(index)`（队列页点击跳转）、`removeFromQueue(index)`（移除后按 `lib/util/queue_math.dart` 的 `mapIndexAfterRemoval` 映射播放位置；移除当前曲目顺延播原下一首，列表清空则停止；保留当前曲目位置与进度）。
- **侧栏"播放列表"落地为队列页**：高亮播放中曲目、点击跳转、逐条移除、空队列空态引导；替换原占位 snackbar。
- **播放模式 UI**：底部播放栏在循环按钮旁新增随机开关（高亮/置灰随 `shuffleEnabled`，tooltip 双态文案）。
- 测试：新增 `test/queue_math_test.dart`（移除索引映射 5 项）与 `test/queue_view_test.dart`（空态/条目渲染/移除不崩溃/播放入口启用禁用 4 项），全量 76 项通过；`flutter analyze` 无问题（排除未跟踪联网调试文件）；macOS Debug 构建与启动冒烟通过。
- 随机切换、队列跳转/移除的播放器级行为（依赖真实音频平台）待 P0 真机验收：iOS corlin17mx 与 Android TV MiTV。
- 版本 0.6.0+1。
