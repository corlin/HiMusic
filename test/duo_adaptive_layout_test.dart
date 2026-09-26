import 'dart:typed_data';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/lyrics/lyrics_controller.dart';
import 'package:himusic/lyrics/lyrics_document.dart';
import 'package:himusic/lyrics/lyrics_repository.dart';
import 'package:himusic/metadata/metadata_index.dart';
import 'package:himusic/metadata/track_metadata.dart';
import 'package:himusic/metadata/track_metadata_reader.dart';
import 'package:himusic/playback/player_controller.dart';
import 'package:himusic/sources/music_source.dart';
import 'package:himusic/ui/library_page.dart';
import 'package:himusic/ui/now_playing_page.dart';

const _song = MusicEntry(
  path: 'music/song.flac',
  name: '长歌曲名称.flac',
  isDirectory: false,
  size: 100,
);

class _Source extends MusicSource {
  @override
  String get label => '本地音乐';
  @override
  String get cacheNamespace => 'duo-layout-test';
  @override
  Future<void> close() async {}
  @override
  Future<List<MusicEntry>> list(String directory) async => [_song];
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

class _Metadata implements TrackMetadataLoader {
  @override
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry) async =>
      TrackMetadata(
        title: '示例曲目',
        performers: const ['歌手甲'],
        album: entry.path.contains('other') ? '第二张' : '示例专辑',
      );
}

class _Lyrics implements LyricsLoader {
  @override
  Future<LyricsDocument?> load(MusicSource source, MusicEntry entry) async =>
      const LyricsDocument(
        source: LyricsSource.sidecarLrc,
        lines: [TimedLyricLine(timestamp: Duration(seconds: 1), text: '第一句歌词')],
      );
}

class _PlayingController extends PlayerController {
  _PlayingController()
    : super(
        metadataIndex: MetadataIndex(loader: _Metadata()),
        lyricsController: LyricsController(repository: _Lyrics()),
      );

  @override
  MusicEntry? get current => _song;
}

Future<void> _size(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  final duoSizes =
      <({String name, Size size, EdgeInsets padding, double scale})>[
        (
          name: 'outer portrait',
          size: const Size(466, 678),
          padding: const EdgeInsets.only(top: 20, bottom: 34),
          scale: 1,
        ),
        (
          name: 'outer landscape',
          size: const Size(678, 466),
          padding: const EdgeInsets.only(left: 30, right: 30, bottom: 21),
          scale: 1,
        ),
        (
          name: 'inner portrait',
          size: const Size(669, 951),
          padding: const EdgeInsets.only(top: 20, bottom: 30),
          scale: 1,
        ),
        (
          name: 'inner landscape',
          size: const Size(951, 669),
          padding: const EdgeInsets.only(left: 30, right: 30, bottom: 21),
          scale: 1,
        ),
        (
          name: 'split left',
          size: const Size(326, 951),
          padding: const EdgeInsets.only(top: 20, right: 8, bottom: 30),
          scale: 1,
        ),
        (
          name: 'split right',
          size: const Size(343, 951),
          padding: const EdgeInsets.only(top: 20, left: 8, bottom: 30),
          scale: 1,
        ),
        (
          name: 'tabletop upper half',
          size: const Size(951, 320),
          padding: const EdgeInsets.only(left: 30, right: 30, top: 20),
          scale: 1,
        ),
        (
          name: 'tabletop lower half',
          size: const Size(951, 329),
          padding: const EdgeInsets.only(left: 30, right: 30, bottom: 21),
          scale: 1,
        ),
        (
          name: 'outer landscape large text',
          size: const Size(678, 466),
          padding: const EdgeInsets.only(left: 30, right: 30, bottom: 21),
          scale: 1.8,
        ),
        (
          name: 'inner landscape large text',
          size: const Size(951, 669),
          padding: const EdgeInsets.only(left: 30, right: 30, bottom: 21),
          scale: 1.8,
        ),
        (
          name: 'split large text',
          size: const Size(326, 951),
          padding: const EdgeInsets.only(top: 20, right: 8, bottom: 30),
          scale: 1.8,
        ),
      ];

  for (final config in duoSizes) {
    testWidgets('Duo ${config.name} connected library fits with player', (
      tester,
    ) async {
      await _size(tester, config.size);
      final controller = _PlayingController()
        ..source = _Source()
        ..directory = 'music'
        ..entries = [_song];
      await controller.metadata.scan(controller.source!, controller.entries);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              padding: config.padding,
              textScaler: TextScaler.linear(config.scale),
            ),
            child: LibraryPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PlayerBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pump();
    });

    testWidgets('Duo ${config.name} now playing fits', (tester) async {
      await _size(tester, config.size);
      final controller = _PlayingController()..source = _Source();
      await controller.metadata.scan(controller.source!, [_song]);
      await controller.lyrics.load(controller.source!, _song);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              padding: config.padding,
              textScaler: TextScaler.linear(config.scale),
            ),
            child: NowPlayingPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('now-playing-transport-dock')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pump();
    });
  }

  testWidgets('Duo compact landscape welcome keeps both choices visible', (
    tester,
  ) async {
    await _size(tester, const Size(678, 360));
    final controller = PlayerController();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(padding: const EdgeInsets.only(bottom: 30)),
          child: LibraryPage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final smb = find.text('连接 SMB 共享硬盘');
    final local = find.text('选择本地音乐');
    expect(smb, findsOneWidget);
    expect(local, findsOneWidget);
    expect(tester.getRect(smb).bottom, lessThan(330));
    expect(tester.getRect(local).bottom, lessThan(330));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump();
  });

  testWidgets('Duo portrait shelf selects the lower track deck', (
    tester,
  ) async {
    await _size(tester, const Size(669, 951));
    const other = MusicEntry(
      path: 'music/other.flac',
      name: '另一首.flac',
      isDirectory: false,
      size: 100,
    );
    final controller =
        PlayerController(metadataIndex: MetadataIndex(loader: _Metadata()))
          ..source = _Source()
          ..directory = 'music'
          ..entries = [_song, other];
    await controller.metadata.scan(controller.source!, controller.entries);
    await tester.pumpWidget(
      MaterialApp(home: LibraryPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('duo-track-deck')), findsOneWidget);
    expect(find.text('2 首'), findsOneWidget);
    await tester.tap(find.byKey(const Key('album-tile-music/song.flac')));
    await tester.pumpAndSettle();
    expect(find.text('专辑：示例专辑'), findsOneWidget);
    expect(find.text('1 首'), findsOneWidget);
    await tester.tap(find.byKey(const Key('album-tile-music/song.flac')));
    await tester.pumpAndSettle();
    expect(find.text('专辑：示例专辑'), findsNothing);
    expect(find.text('2 首'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump();
  });

  testWidgets('Duo compact landscape library with player stays within height', (
    tester,
  ) async {
    await _size(tester, const Size(678, 360));
    final controller = _PlayingController()
      ..source = _Source()
      ..directory = 'music'
      ..entries = [_song];
    await controller.metadata.scan(controller.source!, controller.entries);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(padding: const EdgeInsets.only(bottom: 30)),
          child: LibraryPage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump();
  });

  testWidgets(
    'Duo outer and split widths keep every library section reachable',
    (tester) async {
      await _size(tester, const Size(466, 678));
      final controller =
          PlayerController(metadataIndex: MetadataIndex(loader: _Metadata()))
            ..source = _Source()
            ..directory = 'music'
            ..entries = [_song];
      await controller.metadata.scan(controller.source!, controller.entries);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData.fromView(tester.view)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: LibraryPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compact-library-sections')), findsOneWidget);
      expect(find.byKey(const Key('library-navigation-rail')), findsNothing);
      await tester.tap(find.text('专辑').first);
      await tester.pumpAndSettle();
      expect(find.text('专辑 · 1'), findsOneWidget);

      tester.view.physicalSize = const Size(669, 951);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-navigation-rail')), findsOneWidget);
      expect(find.byKey(const Key('compact-library-sections')), findsNothing);
      await tester.tap(find.byTooltip('艺术家'));
      await tester.pumpAndSettle();
      expect(find.text('艺术家 · 1'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              padding: const EdgeInsets.only(right: 100, bottom: 30),
              textScaler: const TextScaler.linear(1.8),
            ),
            child: LibraryPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-navigation-rail')), findsNothing);
      expect(find.byKey(const Key('compact-library-sections')), findsOneWidget);
      tester.view.physicalSize = const Size(951, 669);
      await tester.pumpWidget(
        MaterialApp(home: LibraryPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-navigation-rail')), findsOneWidget);
      tester.view.physicalSize = const Size(678, 466);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-navigation-rail')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pump();
    },
  );

  for (final config in [
    (const Size(466, 678), <DisplayFeature>[], false, false),
    (
      const Size(669, 951),
      <DisplayFeature>[
        const DisplayFeature(
          bounds: Rect.fromLTWH(326, 0, 17, 951),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ],
      false,
      true,
    ),
    (
      const Size(669, 951),
      <DisplayFeature>[
        const DisplayFeature(
          bounds: Rect.fromLTWH(334.5, 0, 0, 951),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ],
      false,
      true,
    ),
    (
      const Size(951, 669),
      <DisplayFeature>[
        const DisplayFeature(
          bounds: Rect.fromLTWH(0, 320, 951, 20),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ],
      false,
      false,
    ),
    (const Size(669, 951), <DisplayFeature>[], true, false),
  ]) {
    testWidgets('Duo now playing adapts at ${config.$1}', (tester) async {
      await _size(tester, config.$1);
      final controller = _PlayingController()..source = _Source();
      await controller.metadata.scan(controller.source!, [_song]);
      await controller.lyrics.load(controller.source!, _song);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              displayFeatures: config.$2,
              textScaler: const TextScaler.linear(1.8),
            ),
            child: NowPlayingPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('now-playing-dual-pane')),
        config.$3 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('now-playing-book-pose')),
        config.$4 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('now-playing-transport-dock')),
        findsOneWidget,
      );
      if (config.$3 || config.$4) {
        expect(find.text('第一句歌词'), findsOneWidget);
      }
      if (config.$4) {
        final hinge = config.$2.first.bounds;
        expect(
          tester
              .getRect(find.byKey(const Key('now-playing-transport-dock')))
              .right,
          lessThan(hinge.left),
        );
        expect(
          tester.getRect(find.byKey(const Key('book-lyrics-page'))).left,
          greaterThan(hinge.right),
        );
        expect(find.text('唱片页'), findsOneWidget);
        expect(find.text('歌词页'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pump();
    });
  }
}
