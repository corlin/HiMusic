import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/sources/local_source.dart';
import 'package:himusic/waveform/waveform_controller.dart';
import 'package:himusic/waveform/waveform_data.dart';

void main() {
  test('close does not wait for uncancellable native analysis', () async {
    final root = await Directory.systemTemp.createTemp('wave-close-test-');
    final started = Completer<void>();
    final result = Completer<List<WavePeak>>();
    final controller = WaveformController(
      supported: true,
      temporaryDirectory: () async => root,
      extract: (_, _) {
        started.complete();
        return result.future;
      },
    );
    await File('${root.path}/a.flac').writeAsBytes([1]);
    final source = await LocalSource.open(root.path);
    controller.show(source, (await source.list('')).single);
    await started.future.timeout(const Duration(seconds: 5));
    await controller.close().timeout(const Duration(seconds: 1));
    result.complete(const [WavePeak(-1, 1)]);
    for (
      var i = 0;
      i < 50 && await root.list().any((e) => e is Directory);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.peaks, isEmpty);
    expect(await root.list().any((e) => e is Directory), isFalse);
    await root.delete(recursive: true);
  });
  test(
    'switching tracks discards stale extraction and removes temporary audio',
    () async {
      final root = await Directory.systemTemp.createTemp('wave-test-');
      final firstStarted = Completer<void>();
      final firstResult = Completer<List<WavePeak>>();
      var calls = 0;
      final controller = WaveformController(
        supported: true,
        temporaryDirectory: () async => root,
        extract: (audio, output) async {
          calls++;
          if (calls == 1) {
            firstStarted.complete();
            return firstResult.future;
          }
          return const [WavePeak(-.5, .5)];
        },
      );
      try {
        await File('${root.path}/a.flac').writeAsBytes([1]);
        await File('${root.path}/b.flac').writeAsBytes([2]);
        final source = await LocalSource.open(root.path);
        final entries = await source.list('');
        controller.show(source, entries.first);
        await firstStarted.future.timeout(const Duration(seconds: 5));
        controller.show(source, entries.last);
        firstResult.complete(const [WavePeak(-1, 1)]);
        final ready = Completer<void>();
        controller.addListener(() {
          if (controller.peaks.isNotEmpty && !ready.isCompleted) {
            ready.complete();
          }
        });
        await ready.future.timeout(const Duration(seconds: 5));
        expect(controller.peaks.single.high, .5);
        await controller.close();
        for (
          var i = 0;
          i < 50 && await root.list().any((e) => e is Directory);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(
          await root.list().where((e) => e is Directory).toList(),
          isEmpty,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
