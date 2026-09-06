import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

class WavePeak {
  const WavePeak(this.low, this.high);
  final double low;
  final double high;
}

class WaveformSlice {
  const WaveformSlice(this.peaks);
  final List<WavePeak> peaks;
}

/// Pre-computed min/max levels. Each level combines two points from the
/// previous one, so viewport queries stay proportional to screen width.
class WaveformPyramid {
  WaveformPyramid(List<WavePeak> peaks) : length = peaks.length {
    var level = List<WavePeak>.unmodifiable(peaks);
    _levels.add(level);
    while (level.length > 1) {
      final next = <WavePeak>[];
      for (var index = 0; index < level.length; index += 2) {
        final right = min(index + 1, level.length - 1);
        next.add(
          WavePeak(
            min(level[index].low, level[right].low),
            max(level[index].high, level[right].high),
          ),
        );
      }
      level = List<WavePeak>.unmodifiable(next);
      _levels.add(level);
    }
  }

  final int length;
  final List<List<WavePeak>> _levels = [];

  WaveformSlice query(int start, int end, {required int targetPoints}) {
    if (length == 0 || targetPoints < 1) {
      return const WaveformSlice([]);
    }
    final safeStart = start.clamp(0, length - 1);
    final safeEnd = end.clamp(safeStart + 1, length);
    final span = safeEnd - safeStart;
    var levelIndex = 0;
    while (levelIndex + 1 < _levels.length &&
        (span / (1 << levelIndex)).ceil() > targetPoints) {
      levelIndex++;
    }
    final group = 1 << levelIndex;
    final level = _levels[levelIndex];
    final first = safeStart ~/ group;
    final last = min(level.length, (safeEnd / group).ceil());
    final result = _WavePeakView(level, first, last);
    return WaveformSlice(result);
  }
}

class _WavePeakView extends ListBase<WavePeak> {
  _WavePeakView(this.source, this.start, this.end);
  final List<WavePeak> source;
  final int start;
  final int end;

  @override
  int get length => end - start;

  @override
  set length(int value) => throw UnsupportedError('Read-only waveform view');

  @override
  WavePeak operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return source[start + index];
  }

  @override
  void operator []=(int index, WavePeak value) =>
      throw UnsupportedError('Read-only waveform view');
}

/// Reads the v1 audiowaveform binary format produced by the native extractor.
/// Byte offsets are explicit; never treat the 20-byte header as audio samples.
List<WavePeak> parseWaveform(Uint8List bytes, {int bins = 256}) {
  if (bytes.length < 20 || bins < 1) {
    throw const FormatException('Invalid waveform');
  }
  final data = ByteData.sublistView(bytes);
  final version = data.getUint32(0, Endian.little);
  final flags = data.getUint32(4, Endian.little);
  final rate = data.getUint32(8, Endian.little);
  final scale = data.getUint32(12, Endian.little);
  final length = data.getUint32(16, Endian.little);
  final width = flags == 0 ? 2 : 1;
  if (version != 1 ||
      flags > 1 ||
      rate == 0 ||
      scale == 0 ||
      length == 0 ||
      20 + length * 2 * width > bytes.length) {
    throw const FormatException('Invalid waveform header');
  }
  int sample(int index) => width == 1
      ? data.getInt8(20 + index)
      : data.getInt16(20 + index * 2, Endian.little);
  final count = min(bins, length);
  final extrema = <(int, int)>[];
  for (var bin = 0; bin < count; bin++) {
    var low = 0;
    var high = 0;
    for (var i = bin * length ~/ count; i < (bin + 1) * length ~/ count; i++) {
      low = min(low, sample(i * 2));
      high = max(high, sample(i * 2 + 1));
    }
    extrema.add((low, high));
  }
  final divisor = flags == 0 ? 32768.0 : 128.0;
  return List.unmodifiable(
    extrema.map((e) => WavePeak(e.$1 / divisor, e.$2 / divisor)),
  );
}
