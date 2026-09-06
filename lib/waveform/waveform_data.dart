import 'dart:math';
import 'dart:typed_data';

class WavePeak {
  const WavePeak(this.low, this.high);
  final double low;
  final double high;
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
  var absoluteMax = 0;
  final extrema = <(int, int)>[];
  for (var bin = 0; bin < count; bin++) {
    var low = 0;
    var high = 0;
    for (var i = bin * length ~/ count; i < (bin + 1) * length ~/ count; i++) {
      low = min(low, sample(i * 2));
      high = max(high, sample(i * 2 + 1));
    }
    absoluteMax = max(absoluteMax, max(low.abs(), high.abs()));
    extrema.add((low, high));
  }
  final divisor = max(1, absoluteMax).toDouble();
  return List.unmodifiable(
    extrema.map((e) => WavePeak(e.$1 / divisor, e.$2 / divisor)),
  );
}
