# HiMusic

家庭共享硬盘音乐播放器。当前为 V0 原型：Flutter 多端工程、只读 SMB 2/3 连接、本地目录、范围读取音频桥接、播放队列与电视布局入口。

## 启动

本机已将 Flutter 3.47.2 安装在 `.tooling/flutter`（不提交到仓库）。

```sh
.tooling/flutter/bin/flutter pub get
.tooling/flutter/bin/flutter run -d macos
```

其他开发机安装同版本 Flutter 后，使用标准 `flutter` 命令。Windows 构建需要 Windows 工具链；Android / iOS 分别需要对应 SDK。

选择“连接 SMB 共享硬盘”，填写路由器 IP、共享名称、可选音乐目录及账号密码。密码仅保留在当前进程内；退出后重新输入。原型不提供源文件写操作。

macOS / Windows 可选择本地音乐目录。手机本地目录导入、后台媒体服务和连接持久化尚未实现。电视可通过右上角电视按钮切换大字号布局；真实遥控器仍需验收。

## Android / Google TV 开发包

本机产物：`artifacts/HiMusic-0.1.2-android-debug.apk`（Android 7.0+，调试签名）。真实电视尚未安装验收。

```sh
./scripts/flutter.sh build apk --debug
```

脚本为当前工作区选择私有 Flutter、Android SDK 和 Gradle 缓存，避免用户全局 Gradle 镜像配置干扰。

## 验证

```sh
.tooling/flutter/bin/flutter analyze
.tooling/flutter/bin/flutter test
.tooling/flutter/bin/flutter test integration_test/playback_test.dart -d macos
```

集成测试使用自生成 4 秒正弦波 FLAC，以静音音量运行原生解码、读取播放位置并执行跳转。测试不代表真实路由器、电视扬声器输出规格或无缝播放验收。

## 当前边界

- 目录播放器，尚无标签索引、SQLite 音乐库、收藏与歌单持久化。
- 共享源文件，各设备队列独立；没有家庭账号及跨设备同步。
- FLAC 原文件传输，不提供服务端转码，不声称 bit-perfect。
- SMB 错误可重试；连接兼容性、双设备并发和休眠恢复待实机验证。
- 应用暂未签名发布，不提供商店安装包。

产品要求见 [SPEC.md](SPEC.md)，实现和验收记录见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。


## 音量与音频输出（0.1.1）

顶部声音按钮和播放栏提供 0–100% 应用音量、静音与恢复。选择“音频输出设备”：macOS 可在列表中选择系统默认输出（影响其他应用），Android 使用系统选择器或声音设置，iOS 使用系统路由按钮，Windows 打开声音设置。这不是跨设备播放接力或遥控电视功能。

## 音频波形（0.1.2）

播放栏展示整首音频的真实振幅轮廓，已播放部分高亮。点击或拖动波形可定位，聚焦后左右方向键调整五秒。Android / Google TV、iOS、macOS 使用原生解码生成波形；Windows 暂显示不支持，原有进度条仍可用。

首次分析需要将当前曲目分块复制到临时目录；播放缓冲时暂停复制。单曲超过 256 MiB 时跳过分析，最多缓存八首已分析曲目的峰值（当前来源、当前进程）。临时音频在分析完成或失败后删除，音频播放仍从原来源流式读取。快速切歌会丢弃旧结果；已启动的原生分析无法中途取消，新曲目的分析需等待它完成。分析失败不影响音乐播放。
