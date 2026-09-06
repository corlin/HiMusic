import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:himusic/main.dart';
import 'package:himusic/playback/player_controller.dart';
import 'package:himusic/sources/local_source.dart';
import 'package:himusic/waveform/waveform_view.dart';

import 'fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS 播放 FLAC 后播放栏显示真实波形', (tester) async {
    const musicDirectory = String.fromEnvironment('HIMUSIC_TEST_MUSIC_DIR');
    final ownsDirectory = musicDirectory.isEmpty;
    final directory = ownsDirectory
        ? await Directory.systemTemp.createTemp('himusic-ui-wave-')
        : Directory(musicDirectory);
    final controller = PlayerController();
    try {
      if (ownsDirectory) {
        final fixture = flacFixtures.entries.first;
        await File('${directory.path}/${fixture.key}')
            .writeAsBytes(base64Decode(fixture.value));
      }
      await controller.connect(() => LocalSource.open(directory.path), '');

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => PlayerBar(controller: controller),
              ),
            ),
          ),
        ),
      );
      final flac = controller.entries.firstWhere(
        (entry) => entry.extension == 'flac',
      );
      await controller.playEntry(flac);

      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (controller.waveform.peaks.isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump();

      expect(
        controller.waveform.peaks,
        isNotEmpty,
        reason: controller.waveform.message,
      );
      if (!ownsDirectory) {
        expect(controller.waveform.peaks.length, greaterThan(10000));
      }
      expect(find.byType(WaveformView), findsOneWidget);
      expect(tester.getSize(find.byType(WaveformView)).height, 68);
      expect(find.text('10 秒'), findsOneWidget);
      await tester.tap(find.byKey(const Key('waveform-zoom-in')));
      await tester.pump();
      expect(find.text('5 秒'), findsOneWidget);
      expect(
        tester.widget<WaveformView>(find.byType(WaveformView)).window,
        const Duration(seconds: 5),
      );
      final before = tester
          .widget<WaveformView>(find.byType(WaveformView))
          .position;
      await tester.pump(const Duration(milliseconds: 120));
      final after = tester
          .widget<WaveformView>(find.byType(WaveformView))
          .position;
      expect(after, greaterThan(before));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.shutdown();
      if (ownsDirectory) await directory.delete(recursive: true);
    }
  });
}
