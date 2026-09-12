import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/lyrics/embedded_lyrics_reader.dart';
import 'package:himusic/lyrics/lyrics_document.dart';
import 'package:himusic/lyrics/lyrics_repository.dart';
import 'package:himusic/sources/music_source.dart';

const _song = MusicEntry(
  path: 'song.flac',
  name: 'song.flac',
  isDirectory: false,
  size: 10,
);

class _Source extends MusicSource {
  _Source({this.sidecar});
  Uint8List? sidecar;
  int sidecarReads = 0;
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
  }) async {
    sidecarReads++;
    return sidecar;
  }
}

class _Embedded implements EmbeddedLyricsLoader {
  _Embedded(this.value, {this.fail = false});
  final EmbeddedLyricsCandidates value;
  final bool fail;
  int reads = 0;
  @override
  Future<EmbeddedLyricsCandidates> read(
    MusicSource source,
    MusicEntry entry,
  ) async {
    reads++;
    if (fail) throw const FormatException('bad tags');
    return value;
  }
}

LyricsDocument _timed(LyricsSource source) => LyricsDocument(
  source: source,
  lines: const [TimedLyricLine(timestamp: Duration(seconds: 1), text: '歌词')],
);

void main() {
  test('synchronized embedded lyrics beat sidecar', () async {
    final source = _Source(
      sidecar: Uint8List.fromList(utf8.encode('[00:01]旁挂')),
    );
    final embedded = _Embedded(
      EmbeddedLyricsCandidates(
        synchronized: _timed(LyricsSource.embeddedSynced),
      ),
    );
    final result = await LyricsRepository(embeddedReader: embedded)
        .load(source, _song);
    expect(result!.source, LyricsSource.embeddedSynced);
    expect(source.sidecarReads, 0);
  });

  test(
    'sidecar beats embedded plain and metadata failure still falls through',
    () async {
      final source = _Source(
        sidecar: Uint8List.fromList(utf8.encode('[00:01]旁挂')),
      );
      final plain = LyricsDocument(
        source: LyricsSource.embeddedPlain,
        plainText: '内嵌',
      );
      final result = await LyricsRepository(
        embeddedReader: _Embedded(EmbeddedLyricsCandidates(plain: plain)),
      ).load(source, _song);
      expect(result!.source, LyricsSource.sidecarLrc);

      final fallback =
          await LyricsRepository(
            embeddedReader: _Embedded(
              const EmbeddedLyricsCandidates(),
              fail: true,
            ),
          ).load(
            source,
            const MusicEntry(
              path: 'other.flac',
              name: 'other.flac',
              isDirectory: false,
              size: 1,
            ),
          );
      expect(fallback!.source, LyricsSource.sidecarLrc);
    },
  );

  test('returns plain or null and caches results', () async {
    final source = _Source();
    final plain = LyricsDocument(
      source: LyricsSource.embeddedPlain,
      plainText: '内嵌',
    );
    final embedded = _Embedded(EmbeddedLyricsCandidates(plain: plain));
    final repository = LyricsRepository(embeddedReader: embedded);
    expect((await repository.load(source, _song))!.plainText, '内嵌');
    await repository.load(source, _song);
    expect(embedded.reads, 1);

    expect(
      await LyricsRepository(
        embeddedReader: _Embedded(const EmbeddedLyricsCandidates()),
      ).load(source, _song),
      isNull,
    );
  });

  test('129th item evicts least recently used cache entry', () async {
    final source = _Source();
    final embedded = _Embedded(const EmbeddedLyricsCandidates());
    final repository = LyricsRepository(embeddedReader: embedded);
    for (var i = 0; i < 129; i++) {
      await repository.load(
        source,
        MusicEntry(
          path: '$i.mp3',
          name: '$i.mp3',
          isDirectory: false,
          size: i + 1,
        ),
      );
    }
    await repository.load(
      source,
      const MusicEntry(
        path: '0.mp3',
        name: '0.mp3',
        isDirectory: false,
        size: 1,
      ),
    );
    expect(embedded.reads, 130);
  });
}
