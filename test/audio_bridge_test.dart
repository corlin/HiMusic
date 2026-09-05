import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/playback/audio_bridge.dart';
import 'package:himusic/sources/local_source.dart';

void main() {
  late Directory directory;
  late LocalSource source;
  late AudioBridge bridge;
  late HttpClient client;
  late Uri url;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('himusic-test-');
    await File('${directory.path}/音乐.flac')
        .writeAsBytes(List.generate(300000, (i) => i % 251));
    source = await LocalSource.open(directory.path);
    bridge = await AudioBridge.start(source);
    url = bridge.register((await source.list('')).single);
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await bridge.close();
    await source.close();
    await directory.delete(recursive: true);
  });

  test('范围读取直接返回指定位置的字节与总长度', () async {
    final request = await client.getUrl(url);
    request.headers.set('Range', 'bytes=250-254');
    final response = await request.close();
    expect(response.statusCode, 206);
    expect(response.headers.value('content-range'), 'bytes 250-254/300000');
    expect(await response.expand((e) => e).toList(), [250, 0, 1, 2, 3]);
  });
  test('尾部范围、超出长度与非法多范围按协议处理', () async {
    final request = await client.getUrl(url);
    request.headers.set('Range', 'bytes=-3');
    final response = await request.close();
    expect(
      response.headers.value('content-range'),
      'bytes 299997-299999/300000',
    );
    expect(await response.expand((e) => e).toList(), [52, 53, 54]);
    for (final range in ['bytes=300000-', 'bytes=0-1,4-5', 'bytes=-0']) {
      final request = await client.getUrl(url);
      request.headers.set('Range', range);
      final response = await request.close();
      expect(response.statusCode, 416);
      expect(response.headers.value('content-range'), 'bytes */300000');
      await response.drain<void>();
    }
  });
  test('HEAD 无音频体，完整播放跨多个读取块', () async {
    final head = await (await client.openUrl('HEAD', url)).close();
    expect(head.contentLength, 300000);
    expect(await head.expand((e) => e).toList(), isEmpty);
    final response = await (await client.getUrl(url)).close();
    final bytes = await response.expand((e) => e).toList();
    expect(bytes.length, 300000);
    expect(bytes.sublist(131070, 131075), [48, 49, 50, 51, 52]);
  });
  test('未注册路径不可访问，写方法被拒绝', () async {
    final missing = await (await client.getUrl(url.resolve('/private.flac')))
        .close();
    expect(missing.statusCode, 404);
    await missing.drain<void>();
    final write = await (await client.postUrl(url)).close();
    expect(write.statusCode, 405);
    await write.drain<void>();
  });
  test('本地目录不可通过路径穿越或符号链接读取外部文件', () async {
    await expectLater(source.read('../outside', 0, 1), throwsFormatException);
    final outside = await Directory.systemTemp.createTemp('himusic-outside-');
    try {
      await File('${outside.path}/secret').writeAsString('secret');
      await Link('${directory.path}/escape.flac')
          .create('${outside.path}/secret');
      expect((await source.list('')).length, 1);
      await expectLater(
        source.read('escape.flac', 0, 6),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await outside.delete(recursive: true);
    }
  });
}
