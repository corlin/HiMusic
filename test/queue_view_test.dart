import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/metadata/metadata_index.dart';
import 'package:himusic/metadata/track_metadata.dart';
import 'package:himusic/metadata/track_metadata_reader.dart';
import 'package:himusic/playback/player_controller.dart';
import 'package:himusic/sources/music_source.dart';
import 'package:himusic/ui/library_page.dart';

class _Source extends MusicSource {
  @override
  String get label => '测试来源';
  @override
  String get cacheNamespace => 'source';
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
  }) async =>
      null;
}

class _Loader implements TrackMetadataLoader {
  @override
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry) async =>
      TrackMetadata(title: '标签 ${entry.path}');
}

const _trackA = MusicEntry(
  path: 'a.flac',
  name: 'a.flac',
  isDirectory: false,
  size: 100,
);
const _trackB = MusicEntry(
  path: 'b.flac',
  name: 'b.flac',
  isDirectory: false,
  size: 100,
);
const _all = [_trackA, _trackB];

Future<PlayerController> _build(
  WidgetTester tester, {
  List<MusicEntry> entries = _all,
  List<MusicEntry>? queue,
}) async {
  final controller =
      PlayerController(metadataIndex: MetadataIndex(loader: _Loader()))
        ..source = _Source()
        ..directory = 'music'
        ..entries = entries;
  if (queue != null) controller.queue = List.of(queue);
  await controller.metadata.scan(controller.source!, controller.entries);
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: LibraryPage(controller: controller)),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _tearDown(WidgetTester tester, PlayerController controller) async {
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
  await tester.pump();
}

Future<void> _openQueueSection(WidgetTester tester) async {
  await tester.tap(find.text('播放列表').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('队列为空时显示空态', (tester) async {
    final controller = await _build(tester, queue: const []);
    await _openQueueSection(tester);
    expect(find.text('播放队列 · 0'), findsOneWidget);
    expect(find.textContaining('当前队列为空'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _tearDown(tester, controller);
  });

  testWidgets('队列页显示条目与移除按钮，点击移除不崩溃', (tester) async {
    final controller = await _build(tester, queue: _all);
    await _openQueueSection(tester);
    expect(find.text('播放队列 · 2'), findsOneWidget);
    expect(find.text('标签 a.flac'), findsOneWidget);
    expect(find.text('标签 b.flac'), findsOneWidget);

    await tester.tap(find.byTooltip('从队列移除').first);
    await tester.pumpAndSettle();
    // 移除在重建播放器前先落地；测试环境无平台播放器，仅验证不崩溃且队列缩短。
    expect(controller.queue.length, 1);
    expect(tester.takeException(), isNull);
    await _tearDown(tester, controller);
  });

  testWidgets('宽屏目录页提供播放全部与随机播放入口', (tester) async {
    final controller = await _build(tester);
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('随机播放'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, '播放全部')).enabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await _tearDown(tester, controller);
  });

  testWidgets('目录无音频时播放入口禁用', (tester) async {
    final controller = await _build(tester, entries: const []);
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, '播放全部')).enabled,
      isFalse,
    );
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, '随机播放')).enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await _tearDown(tester, controller);
  });
}
