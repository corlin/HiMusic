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

/// 每个路径对应固定元数据，便于断言排序结果。
/// x：甲 / 张三 / 专辑A / 3 分钟；y：乙 / 李四 / 专辑B / 5 分钟；z：丙 / 张三 / 专辑A / 4 分钟
TrackMetadata? _meta(MusicEntry entry) => switch (entry.path) {
  'x.flac' => const TrackMetadata(
    title: '甲',
    performers: ['张三'],
    album: '专辑A',
    duration: Duration(minutes: 3),
  ),
  'y.flac' => const TrackMetadata(
    title: '乙',
    performers: ['李四'],
    album: '专辑B',
    duration: Duration(minutes: 5),
  ),
  'z.flac' => const TrackMetadata(
    title: '丙',
    performers: ['张三'],
    album: '专辑A',
    duration: Duration(minutes: 4),
  ),
  _ => null,
};

class _Loader implements TrackMetadataLoader {
  @override
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry) async =>
      _meta(entry) ?? const TrackMetadata(title: '未知');
}

const _entries = [
  MusicEntry(path: 'x.flac', name: 'x.flac', isDirectory: false, size: 100),
  MusicEntry(path: 'y.flac', name: 'y.flac', isDirectory: false, size: 100),
  MusicEntry(path: 'z.flac', name: 'z.flac', isDirectory: false, size: 100),
];

Future<PlayerController> _build(
  WidgetTester tester,
  Size size,
) async {
  final controller =
      PlayerController(metadataIndex: MetadataIndex(loader: _Loader()))
        ..source = _Source()
        ..directory = 'music'
        ..entries = _entries;
  await controller.metadata.scan(controller.source!, controller.entries);
  tester.view.physicalSize = size;
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

double _rowTop(WidgetTester tester, String title) =>
    tester.getTopLeft(find.text(title).last).dy;

void main() {
  testWidgets('表头点击排序：升序 → 降序 → 回到自然顺序', (tester) async {
    final controller =
        await _build(tester, const Size(1200, 900));
    expect(find.text('标题'), findsOneWidget);

    // 默认自然顺序：x、y、z
    expect(_rowTop(tester, '甲') < _rowTop(tester, '乙'), isTrue);
    expect(_rowTop(tester, '乙') < _rowTop(tester, '丙'), isTrue);

    // 点击「标题」→ 按标题升序（丙 < 乙 < 甲，Unicode 码点）
    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();
    expect(_rowTop(tester, '丙') < _rowTop(tester, '乙'), isTrue);
    expect(_rowTop(tester, '乙') < _rowTop(tester, '甲'), isTrue);
    expect(tester.takeException(), isNull);

    // 再次点击 → 降序（甲 < 乙 < 丙 倒序：甲在上）
    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();
    expect(_rowTop(tester, '甲') < _rowTop(tester, '乙'), isTrue);
    expect(_rowTop(tester, '乙') < _rowTop(tester, '丙'), isTrue);

    // 第三次点击 → 回到自然顺序（x、y、z）
    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();
    expect(_rowTop(tester, '甲') < _rowTop(tester, '乙'), isTrue);
    expect(_rowTop(tester, '乙') < _rowTop(tester, '丙'), isTrue);

    await _tearDown(tester, controller);
  });

  testWidgets('按时长排序与按艺术家排序', (tester) async {
    final controller = await _build(tester, const Size(1200, 900));

    // 时长升序：3、4、5 分钟 → 甲、丙、乙
    await tester.tap(find.text('时长'));
    await tester.pumpAndSettle();
    expect(_rowTop(tester, '甲') < _rowTop(tester, '丙'), isTrue);
    expect(_rowTop(tester, '丙') < _rowTop(tester, '乙'), isTrue);

    // 艺术家升序：张三(x)、张三(z)、李四(y) → 甲、丙、乙
    await tester.tap(find.text('艺术家').last);
    await tester.pumpAndSettle();
    expect(_rowTop(tester, '甲') < _rowTop(tester, '丙'), isTrue);
    expect(_rowTop(tester, '丙') < _rowTop(tester, '乙'), isTrue);
    expect(tester.takeException(), isNull);

    await _tearDown(tester, controller);
  });

  testWidgets('专辑分区：浏览 → 点入筛选 → 清除', (tester) async {
    final controller = await _build(tester, const Size(1200, 900));

    await tester.tap(find.text('专辑').first); // 侧栏导航
    await tester.pumpAndSettle();
    expect(find.text('专辑 · 2'), findsOneWidget);
    expect(find.text('专辑A'), findsWidgets);
    expect(find.text('专辑B'), findsOneWidget);

    await tester.tap(find.text('专辑A').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('专辑：专辑A'), findsOneWidget);
    expect(find.text('2 项 · 只读访问'), findsOneWidget);

    // 清除筛选后回到全部
    await tester.tap(find.textContaining('专辑：专辑A'));
    await tester.pumpAndSettle();
    expect(find.text('3 项 · 只读访问'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _tearDown(tester, controller);
  });

  testWidgets('艺术家分区：点入筛选该艺术家的曲目', (tester) async {
    final controller = await _build(tester, const Size(1200, 900));

    await tester.tap(find.text('艺术家').first); // 侧栏导航
    await tester.pumpAndSettle();
    expect(find.text('艺术家 · 2'), findsOneWidget);

    await tester.tap(find.text('张三').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('艺术家：张三'), findsOneWidget);
    expect(find.text('2 项 · 只读访问'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _tearDown(tester, controller);
  });
}
