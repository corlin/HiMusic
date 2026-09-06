import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/waveform/waveform_data.dart';
import 'package:himusic/waveform/waveform_view.dart';

void main() {
  for (final bits in [8, 16]) {
    test('$bits-bit real sample offsets, silence and peak aggregation', () {
      final bytes = Uint8List(20 + 8 * bits ~/ 8);
      final data = ByteData.sublistView(bytes);
      for (final field in [
        (0, 1),
        (4, bits == 8 ? 1 : 0),
        (8, 44100),
        (12, 2205),
        (16, 4),
      ]) {
        data.setUint32(field.$1, field.$2, Endian.little);
      }
      final samples = [0, 0, 0, 0, -100, 80, -40, 100];
      for (var i = 0; i < samples.length; i++) {
        if (bits == 8) {
          data.setInt8(20 + i, samples[i]);
        } else {
          data.setInt16(20 + i * 2, samples[i], Endian.little);
        }
      }
      final peaks = parseWaveform(bytes, bins: 2);
      expect(peaks.first.low, 0);
      expect(peaks.first.high, 0);
      final divisor = bits == 8 ? 128 : 32768;
      expect(peaks.last.low, closeTo(-100 / divisor, .000001));
      expect(peaks.last.high, closeTo(100 / divisor, .000001));
      expect(
        () => parseWaveform(bytes.sublist(0, bytes.length - 1)),
        throwsFormatException,
      );
    });
  }
  testWidgets('waveform tap seeks to actual track time', (tester) async {
    Duration? target;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: WaveformView(
                peaks: List.filled(12000, const WavePeak(-1, 1)),
                position: const Duration(seconds: 50),
                duration: const Duration(seconds: 100),
                window: const Duration(seconds: 20),
                onSeek: (value) => target = value,
              ),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(WaveformView));
    await tester.tapAt(Offset(rect.left + rect.width * .75, rect.top + 30));
    expect(target, const Duration(seconds: 55));
    await tester.tapAt(Offset(rect.left + rect.width * .75, rect.bottom - 8));
    expect(target, const Duration(seconds: 75));
  });

  test('multi-resolution query stays bounded and preserves extrema', () {
    final peaks = List.generate(
      1 << 18,
      (index) =>
          index == 131072 ? const WavePeak(-1, 1) : const WavePeak(-.1, .1),
    );
    final pyramid = WaveformPyramid(peaks);
    final slice = pyramid.query(0, peaks.length, targetPoints: 900);
    expect(slice.peaks.length, lessThanOrEqualTo(1800));
    expect(slice.sourceSamplesVisited, lessThanOrEqualTo(1800));
    expect(slice.peaks.any((peak) => peak.high == 1), isTrue);
  });
}
