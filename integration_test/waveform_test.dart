import 'dart:io';
import 'dart:convert';

import 'fixtures.dart';

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:himusic/sources/local_source.dart';
import 'package:himusic/waveform/waveform_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native extraction distinguishes silence from actual PCM sound', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'himusic-wave-test-',
    );
    final wave = WaveformController(temporaryDirectory: () async => directory);
    try {
      const rate = 44100;
      final bytes = Uint8List(44 + rate * 4 * 2);
      final data = ByteData.sublistView(bytes);
      void tag(int offset, String text) =>
          bytes.setRange(offset, offset + text.length, text.codeUnits);
      tag(0, 'RIFF');
      data.setUint32(4, bytes.length - 8, Endian.little);
      tag(8, 'WAVE');
      tag(12, 'fmt ');
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(22, 1, Endian.little);
      data.setUint32(24, rate, Endian.little);
      data.setUint32(28, rate * 2, Endian.little);
      data.setUint16(32, 2, Endian.little);
      data.setUint16(34, 16, Endian.little);
      tag(36, 'data');
      data.setUint32(40, bytes.length - 44, Endian.little);
      for (var i = rate; i < rate * 2; i++) {
        data.setInt16(
          44 + i * 2,
          (sin(i * 2 * pi * 440 / rate) * 20000).round(),
          Endian.little,
        );
      }
      await File('${directory.path}/dynamics.wav').writeAsBytes(bytes);
      final source = await LocalSource.open(directory.path);
      wave.show(source, (await source.list('')).single);
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (wave.peaks.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(wave.peaks, isNotEmpty, reason: wave.message);
      final n = wave.peaks.length;
      expect(wave.peaks[n ~/ 8].high, lessThan(.01));
      expect(wave.peaks[n * 3 ~/ 8].high, greaterThan(.8));
      expect(wave.peaks[n * 7 ~/ 8].high, lessThan(.01));
      for (final fixture in flacFixtures.entries) {
        final audio = await File('${directory.path}/${fixture.key}')
            .writeAsBytes(base64Decode(fixture.value));
        final peaks = await extractWaveform(
          audio,
          File('${directory.path}/${fixture.key}.wave'),
        ).timeout(const Duration(seconds: 30));
        expect(peaks, isNotEmpty, reason: fixture.key);
        expect(
          peaks[peaks.length ~/ 2].high,
          greaterThan(.8),
          reason: fixture.key,
        );
      }
    } finally {
      await wave.close();
      await directory.delete(recursive: true);
    }
  });
}
