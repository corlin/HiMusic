# 音频测试样本

所有样本为本项目生成的 440 Hz、4 秒双声道正弦波，不含任何音乐录音。

生成命令（FFmpeg 8.0.1）：

```sh
ffmpeg -f lavfi -i 'sine=frequency=440:duration=4:sample_rate=44100' -ac 2 -sample_fmt s16 -c:a flac tone-16-44100.flac
ffmpeg -f lavfi -i 'sine=frequency=440:duration=4:sample_rate=96000' -ac 2 -sample_fmt s32 -c:a flac tone-24-96000.flac
ffmpeg -f lavfi -i 'sine=frequency=440:duration=4:sample_rate=192000' -ac 2 -sample_fmt s32 -c:a flac tone-24-192000.flac
```

FFmpeg 的 s32 输入在此 FLAC 编码器中输出 24-bit 文件。`integration_test/fixtures.dart` 为这些文件的 base64 副本，仅随测试编译，不进入正常应用。
