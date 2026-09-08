import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/main.dart';
import 'package:himusic/playback/player_controller.dart';
import 'package:himusic/sources/local_source.dart';
import 'package:himusic/sources/music_source.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture selected product-design state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1024));
    final directory = await Directory.systemTemp.createTemp('himusic-design-');
    final controller = PlayerController();
    try {
      const designAudio = String.fromEnvironment('HIMUSIC_DESIGN_AUDIO');
      final fixtureBytes = base64Decode(flacFixtures.values.first);
      final mainBytes = designAudio.isEmpty
          ? fixtureBytes
          : await File(designAudio).readAsBytes();
      await File('${directory.path}/01 山丘 (Live).flac').writeAsBytes(mainBytes);
      for (final name in const [
        'Sonder.flac',
        '小幸运.flac',
        'River Flows In You.flac',
        'New Morning.flac',
        '再见青春.flac',
      ]) {
        await File('${directory.path}/$name').writeAsBytes(fixtureBytes);
      }
      final local = await LocalSource.open(directory.path);
      await controller.connect(() async => _DesignSource(local), '');
      await tester.pumpWidget(
        HiMusicApp(home: LibraryPage(controller: controller)),
      );
      await controller.playEntry(controller.entries.first);
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while ((controller.waveform.peaks.isEmpty ||
              controller.metadata.isScanning) &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 300));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('library-capture-boundary')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File(
        '${Directory.systemTemp.path}/himusic-implementation-option-1.png',
      );
      await output.writeAsBytes(data!.buffer.asUint8List());
      debugPrint('DESIGN_CAPTURE=${output.path}');
      expect(output.lengthSync(), greaterThan(10000));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.shutdown();
      await directory.delete(recursive: true);
      await tester.binding.setSurfaceSize(null);
    }
  });
}

class _DesignSource implements MusicSource {
  const _DesignSource(this.local);
  final LocalSource local;

  @override
  String get label => 'BE7200 MAX / USB Music';

  @override
  String get cacheNamespace => 'design:${local.cacheNamespace}';

  @override
  Future<List<MusicEntry>> list(String directory) => local.list(directory);

  @override
  Future<Uint8List> read(String path, int offset, int length) =>
      local.read(path, offset, length);

  @override
  Future<Uint8List?> readSidecar(
    MusicEntry entry,
    String extension, {
    required int maxBytes,
  }) =>
      local.readSidecar(entry, extension, maxBytes: maxBytes);

  @override
  Future<void> close() => local.close();
}
