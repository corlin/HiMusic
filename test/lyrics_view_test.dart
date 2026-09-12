import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/lyrics/lyrics_controller.dart';
import 'package:himusic/lyrics/lyrics_document.dart';
import 'package:himusic/lyrics/lyrics_repository.dart';
import 'package:himusic/lyrics/lyrics_view.dart';
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
  _Loader(this.document);
  final LyricsDocument? document;
  @override
  Future<LyricsDocument?> load(MusicSource source, MusicEntry entry) async =>
      document;
}

const _entry = MusicEntry(
  path: 'song.mp3',
  name: 'song.mp3',
  isDirectory: false,
  size: 1,
);

Future<void> _show(
  WidgetTester tester,
  LyricsController controller, {
  ValueChanged<TimedLyricLine>? onSeek,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          height: 420,
          child: LyricsView(controller: controller, onSeek: onSeek ?? (_) {}),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows active synchronized line and taps to seek', (
    tester,
  ) async {
    const document = LyricsDocument(
      source: LyricsSource.sidecarLrc,
      lines: [
        TimedLyricLine(timestamp: Duration(seconds: 1), text: '第一句'),
        TimedLyricLine(timestamp: Duration(seconds: 3), text: '第二句'),
      ],
    );
    final controller = LyricsController(repository: _Loader(document));
    await controller.load(_Source(), _entry);
    TimedLyricLine? sought;
    await _show(tester, controller, onSeek: (line) => sought = line);
    controller.updatePosition(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('当前歌词：第二句'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lyric-line-0')));
    expect(sought!.text, '第一句');
  });

  testWidgets('shows plain and no-lyrics states', (tester) async {
    final plain = LyricsController(
      repository: _Loader(
        const LyricsDocument(
          source: LyricsSource.embeddedPlain,
          plainText: '整段歌词',
        ),
      ),
    );
    await plain.load(_Source(), _entry);
    await _show(tester, plain);
    expect(find.text('整段歌词'), findsOneWidget);

    final empty = LyricsController(repository: _Loader(null));
    await empty.load(_Source(), _entry);
    await _show(tester, empty);
    expect(find.text('这首歌没有本地歌词'), findsOneWidget);
  });

  testWidgets('manual scrolling offers and then clears follow control', (
    tester,
  ) async {
    final lines = List.generate(
      20,
      (i) => TimedLyricLine(
        timestamp: Duration(seconds: i),
        text: '第$i句',
      ),
    );
    final controller = LyricsController(
      repository: _Loader(
        LyricsDocument(source: LyricsSource.sidecarLrc, lines: lines),
      ),
    );
    await controller.load(_Source(), _entry);
    await _show(tester, controller);
    await tester.drag(
      find.byKey(const Key('timed-lyrics-list')),
      const Offset(0, -120),
    );
    await tester.pump();
    expect(find.text('回到当前歌词'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('回到当前歌词'), findsNothing);
  });
}
