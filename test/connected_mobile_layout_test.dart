import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/metadata/metadata_index.dart';
import 'package:himusic/metadata/track_metadata.dart';
import 'package:himusic/metadata/track_metadata_reader.dart';
import 'package:himusic/ui/library_page.dart';
import 'package:himusic/playback/player_controller.dart';
import 'package:himusic/sources/music_source.dart';

class _Source extends MusicSource {
  @override
  String get label => '192.168.5.1 / disk';
  @override
  String get cacheNamespace => label;
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

class _MetadataLoader implements TrackMetadataLoader {
  @override
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry) async =>
      TrackMetadata(
        title: '标签曲名 ${entry.path}',
        performers: const ['歌手甲'],
        album: '测试专辑',
        composers: const ['作曲甲'],
        arrangers: const ['编曲甲'],
      );
}

class _PlayingController extends PlayerController {
  _PlayingController()
    : super(metadataIndex: MetadataIndex(loader: _MetadataLoader()));

  @override
  MusicEntry? get current => const MusicEntry(
    path: 'playing.flac',
    name: '横屏正在播放的长曲目名称.flac',
    isDirectory: false,
    size: 22000000,
  );
}

class _IPhoneNonlinearTextScaler extends TextScaler {
  const _IPhoneNonlinearTextScaler();

  @override
  double scale(double fontSize) => fontSize >= 30 ? fontSize : fontSize * 1.5;

  @override
  double get textScaleFactor => 1.5;
}

void main() {
  testWidgets('未连接时不显示写死的示例路由器名称', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController();
    await tester.pumpWidget(
      MaterialApp(home: LibraryPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('BE7200 MAX'), findsNothing);
    expect(find.text('连接 SMB 共享硬盘'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump();
  });

  for (final width in [360.0, 412.0, 800.0]) {
    testWidgets('已连接音乐库在 $width 宽度下无溢出且标题可读', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller =
          PlayerController(
              metadataIndex: MetadataIndex(loader: _MetadataLoader()),
            )
            ..source = _Source()
            ..directory = 'music'
            ..entries = List.generate(
              6,
              (i) => MusicEntry(
                path: '$i.flac',
                name: '皇帝与公主长曲目名称$i.flac',
                isDirectory: false,
                size: 22000000,
              ),
            );
      await controller.metadata.scan(controller.source!, controller.entries);
      await tester.pumpWidget(
        MaterialApp(home: LibraryPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width < 700) {
        expect(find.text('位置'), findsNothing);
        final title = find.text('标签曲名 0.flac').last;
        expect(
          tester.renderObject<RenderBox>(title).constraints.maxWidth,
          greaterThan(180),
        );
      }
      if (width >= 700) {
        expect(find.text('当前目录'), findsWidgets);
      }
      expect(find.text('标签曲名 0.flac'), findsWidgets);
      expect(find.textContaining('歌手甲'), findsWidgets);
      if (width == 800) {
        await tester.tap(find.byTooltip('查看歌曲信息').first);
        await tester.pumpAndSettle();
        expect(find.text('演唱'), findsOneWidget);
        expect(find.text('作曲'), findsOneWidget);
        expect(find.text('编曲'), findsOneWidget);
        expect(find.text('测试专辑'), findsWidgets);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pumpAndSettle();
      expect(find.textContaining('没有匹配的音乐或文件夹'), findsOneWidget);
      expect(find.text('找到 0 项 / 共 6 项 · 只读访问'), findsOneWidget);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.text('6 项 · 只读访问'), findsOneWidget);
      expect(find.byTooltip('清除搜索'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pump();
    });
  }

  testWidgets('iPhone Duo 横屏非线性文字缩放时专辑封面架不溢出', (tester) async {
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller =
        PlayerController(
            metadataIndex: MetadataIndex(loader: _MetadataLoader()),
          )
          ..source = _Source()
          ..directory = 'music'
          ..entries = List.generate(
            6,
            (i) => MusicEntry(
              path: '$i.flac',
              name: '横屏长曲目名称$i.flac',
              isDirectory: false,
              size: 22000000,
            ),
          );
    await controller.metadata.scan(controller.source!, controller.entries);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: const _IPhoneNonlinearTextScaler()),
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

  testWidgets('iPhone Duo 横屏播放栏保持紧凑并可打开歌词', (tester) async {
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _PlayingController()..source = _Source();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: const _IPhoneNonlinearTextScaler()),
          child: Scaffold(
            body: Column(
              children: [
                const Spacer(),
                PlayerBar(controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PlayerBar)).height, lessThan(150));
    await tester.tap(find.byTooltip('歌词'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('正在播放'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump();
  });
}
