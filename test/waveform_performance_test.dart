import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/waveform/waveform_data.dart';
import 'package:himusic/waveform/waveform_view.dart';

void main() {
  test('viewport cost is bounded by width for maximum in-memory waveform', () {
    final peaks = List.generate(
      180000,
      (index) => WavePeak(-((index % 97) / 97), (index % 89) / 89),
      growable: false,
    );
    final build = Stopwatch()..start();
    final pyramid = WaveformPyramid(peaks);
    build.stop();
    final query = Stopwatch()..start();
    var checksum = 0.0;
    for (var frame = 0; frame < 600; frame++) {
      final start = frame * 251 % 160000;
      final slice = pyramid.query(start, start + 20000, targetPoints: 960);
      expect(slice.peaks.length, lessThanOrEqualTo(960));
      checksum += slice.peaks[frame % slice.peaks.length].high;
    }
    query.stop();
    expect(checksum, greaterThan(0));
    // Generous guards catch accidental O(songLength) work without depending on
    // a particular developer machine's exact frame timing.
    expect(build.elapsedMilliseconds, lessThan(1500));
    expect(query.elapsedMilliseconds, lessThan(500));
    final renderCache = WaveformRenderCache(pyramid);
    final first = renderCache.path(
      'tile',
      start: 1000,
      end: 21000,
      width: 1440,
      height: 88,
      targetPoints: 720,
    );
    final second = renderCache.path(
      'tile',
      start: 1000,
      end: 21000,
      width: 1440,
      height: 88,
      targetPoints: 720,
    );
    expect(identical(first, second), isTrue);
    expect(renderCache.pathBuildCount, 1);
  });
}
