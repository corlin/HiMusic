import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/lyrics/lyrics_controller.dart';
import 'package:himusic/lyrics/lyrics_document.dart';
import 'package:himusic/lyrics/lyrics_repository.dart';
import 'package:himusic/sources/music_source.dart';

class _Source extends MusicSource {
  @override
  String get label => 'test';
  @override
  String get cacheNamespace => 'test';
  @override
  Future<void> close() async {}
  @override
  Future<List<MusicEntry>> list(String directory) async => [];
  @override
  Future<Uint8List> read(String path, int offset, int length) async =>
      Uint8List(0);
  @override
  Future<Uint8List?> readSidecar(
    MusicEntry entry,
    String extension, {
    required int maxBytes,
  }) async => null;
}

class _Loader implements LyricsLoader {
  _Loader(this.loadCallback);
  final Future<LyricsDocument?> Function(MusicEntry) loadCallback;
  @override
  Future<LyricsDocument?> load(MusicSource source, MusicEntry entry) =>
      loadCallback(entry);
}

MusicEntry _entry(String name) =>
    MusicEntry(path: name, name: name, isDirectory: false, size: 1);

const _lyrics = LyricsDocument(
  source: LyricsSource.sidecarLrc,
  lines: [
    TimedLyricLine(timestamp: Duration(seconds: 1), text: '一'),
    TimedLyricLine(timestamp: Duration(seconds: 3), text: '二'),
    TimedLyricLine(timestamp: Duration(seconds: 5), text: '三'),
  ],
);

void main() {
  test('loads ready, empty and error states and retries', () async {
    var attempt = 0;
    final controller = LyricsController(
      repository: _Loader((_) async {
        attempt++;
        if (attempt == 1) throw StateError('temporary');
        return _lyrics;
      }),
    );
    await controller.load(_Source(), _entry('song.mp3'));
    expect(controller.status, LyricsStatus.error);
    await controller.retry();
    expect(controller.status, LyricsStatus.ready);

    final empty = LyricsController(repository: _Loader((_) async => null));
    await empty.load(_Source(), _entry('none.mp3'));
    expect(empty.status, LyricsStatus.empty);
  });

  test(
    'selects active line with binary search after forward and backward seeks',
    () async {
      final controller = LyricsController(
        repository: _Loader((_) async => _lyrics),
      );
      await controller.load(_Source(), _entry('song.mp3'));
      controller.updatePosition(const Duration(milliseconds: 500));
      expect(controller.currentLineIndex, -1);
      controller.updatePosition(const Duration(seconds: 4));
      expect(controller.currentLineIndex, 1);
      controller.updatePosition(const Duration(seconds: 9));
      expect(controller.currentLineIndex, 2);
      controller.updatePosition(const Duration(seconds: 1));
      expect(controller.currentLineIndex, 0);
    },
  );

  test('discards a slow result after a newer track loads', () async {
    final first = Completer<LyricsDocument?>();
    final controller = LyricsController(
      repository: _Loader((entry) {
        if (entry.path == 'first.mp3') return first.future;
        return Future.value(_lyrics);
      }),
    );
    final firstLoad = controller.load(_Source(), _entry('first.mp3'));
    await controller.load(_Source(), _entry('second.mp3'));
    first.complete(
      const LyricsDocument(
        source: LyricsSource.embeddedPlain,
        plainText: '旧歌词',
      ),
    );
    await firstLoad;
    expect(controller.entry!.path, 'second.mp3');
    expect(controller.document, same(_lyrics));
  });

  test('clear invalidates pending work', () async {
    final pending = Completer<LyricsDocument?>();
    final controller = LyricsController(
      repository: _Loader((_) => pending.future),
    );
    final load = controller.load(_Source(), _entry('song.mp3'));
    controller.clear();
    pending.complete(_lyrics);
    await load;
    expect(controller.status, LyricsStatus.idle);
    expect(controller.document, isNull);
  });
}
