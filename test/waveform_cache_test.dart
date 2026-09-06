import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/waveform/waveform_cache.dart';
import 'package:himusic/waveform/waveform_data.dart';

void main() {
  test('persistent peak cache round-trips and evicts oldest entries', () async {
    final root = await Directory.systemTemp.createTemp('himusic-wave-cache-');
    final cache = WaveformCache(root, maxBytes: 45);
    try {
      const peaks = [WavePeak(-.5, .25), WavePeak(-1, 1)];
      await cache.store('first', peaks);
      final loaded = await cache.load('first');
      expect(loaded, hasLength(2));
      expect(loaded!.first.low, closeTo(-.5, .0001));
      expect(loaded.last.high, closeTo(1, .0001));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cache.store('second', List.filled(8, const WavePeak(-1, 1)));
      expect(await cache.load('first'), isNull);
      expect(await cache.load('second'), isNotEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
