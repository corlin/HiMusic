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
