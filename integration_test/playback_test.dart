import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:himusic/playback/audio_bridge.dart';
import 'package:himusic/playback/player_controller.dart';
import 'package:himusic/sources/music_source.dart';
import 'package:himusic/sources/local_source.dart';

import 'fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实 macOS 引擎通过范围桥接播放三种 FLAC 并拖动', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('HiMusic · FLAC playback verification')),
        ),
      ),
    );
    final directory = await Directory.systemTemp.createTemp('himusic-audio-');
    final source = await LocalSource.open(directory.path);
    final bridge = await AudioBridge.start(source);
    final player = AudioPlayer();
    try {
      await player.setVolume(
        0,
      ); // Decode with native output running, without audible test tones.
      for (final fixture in flacFixtures.entries) {
        await File('${directory.path}/${fixture.key}')
            .writeAsBytes(base64Decode(fixture.value));
      }
      for (final file in await source.list('')) {
        await player
            .setUrl(bridge.register(file).toString())
            .timeout(const Duration(seconds: 20));
        expect(player.duration?.inMilliseconds, closeTo(4000, 100));
        unawaited(player.play());
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(player.position.inMilliseconds, greaterThan(100));
        await player.pause();
        await player.seek(const Duration(seconds: 2));
        expect(player.position.inMilliseconds, closeTo(2000, 200));
        await player.stop();
      }
    } finally {
      await player.dispose();
      await bridge.close();
      await source.close();
      await directory.delete(recursive: true);
    }
  });
  testWidgets('连接失败可重试，目录重试不会恢复已暂停播放，关闭释放迟到连接', (tester) async {
    final directory = await Directory.systemTemp.createTemp('himusic-retry-');
    final fixture = flacFixtures.entries.first;
    await File('${directory.path}/${fixture.key}')
        .writeAsBytes(base64Decode(fixture.value));
    final c = PlayerController();
    final source = FailingSource(await LocalSource.open(directory.path));
    var attempts = 0;
    try {
      await c.player.setVolume(0);
      await c.connect(() async {
        attempts++;
        if (attempts == 1) {
          throw const SocketException('connection unavailable');
        }
        return source;
      }, '');
      expect(c.error, isNotNull);
      await c.retry();
      expect(attempts, 2);
      expect(c.entries.length, 1);
      await c.playEntry(c.entries.single);
      await c.toggle();
      expect(c.player.playing, false);
      source.failNextList = true;
      await c.browse('');
      expect(c.error, isNotNull);
      await c.retry();
      expect(c.error, isNull);
      expect(c.player.playing, false);
    } finally {
      await c.shutdown();
    }
    final delayed = PlayerController();
    final factory = Completer<MusicSource>();
    final lateSource = FailingSource(await LocalSource.open(directory.path));
    final connecting = delayed.connect(() => factory.future, '');
    final closing = delayed.shutdown();
    factory.complete(lateSource);
    await connecting;
    await closing;
    expect(lateSource.closed, true);
    expect(delayed.source, isNull);
    await directory.delete(recursive: true);
  });
  testWidgets('音量支持最终值与静音恢复', (tester) async {
    final c = PlayerController();
    try {
      await c.setVolume(0.37);
      expect(c.player.volume, closeTo(0.37, 0.001));
      await c.toggleMute();
      expect(c.player.volume, 0);
      await c.toggleMute();
      expect(c.player.volume, closeTo(0.37, 0.001));
      final first = c.setVolume(0.1);
      final last = c.setVolume(0.62);
      await Future.wait([first, last]);
      expect(c.player.volume, closeTo(0.62, 0.001));
      expect(c.volumeError, isNull);
    } finally {
      await c.shutdown();
    }
  });
}

class FailingSource extends MusicSource {
  FailingSource(this.inner);
  final MusicSource inner;
  bool failNextList = false;
  bool closed = false;
  @override
  String get label => inner.label;
  @override
  String get cacheNamespace => 'test:${inner.cacheNamespace}';
  @override
  Future<List<MusicEntry>> list(String path) async {
    if (failNextList) {
      failNextList = false;
      throw const SocketException('temporary failure');
    }
    return inner.list(path);
  }

  @override
  Future<Uint8List> read(String path, int offset, int length) =>
      inner.read(path, offset, length);
  @override
  Future<Uint8List?> readSidecar(
    MusicEntry entry,
    String extension, {
    required int maxBytes,
  }) =>
      inner.readSidecar(entry, extension, maxBytes: maxBytes);
  @override
  Future<void> close() async {
    closed = true;
    await inner.close();
  }
}
