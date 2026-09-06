import 'dart:io';
import 'dart:typed_data';

import 'waveform_data.dart';

class WaveformCache {
  const WaveformCache(this.directory, {this.maxBytes = 256 * 1024 * 1024});

  final Directory directory;
  final int maxBytes;

  Future<List<WavePeak>?> load(String key) async {
    final file = File('${directory.path}/${_name(key)}.hmw');
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length < 8 ||
          bytes[0] != 0x48 ||
          bytes[1] != 0x4d ||
          bytes[2] != 0x57 ||
          bytes[3] != 0x31) {
        return null;
      }
      final data = ByteData.sublistView(bytes);
      final count = data.getUint32(4, Endian.little);
      if (count == 0 || bytes.length != 8 + count * 4) return null;
      final peaks = List<WavePeak>.generate(count, (index) {
        final offset = 8 + index * 4;
        return WavePeak(
          data.getInt16(offset, Endian.little) / 32768,
          data.getInt16(offset + 2, Endian.little) / 32768,
        );
      }, growable: false);
      await file.setLastModified(DateTime.now());
      return List.unmodifiable(peaks);
    } on FileSystemException {
      return null;
    } on RangeError {
      return null;
    }
  }

  Future<void> store(String key, List<WavePeak> peaks) async {
    if (peaks.isEmpty) return;
    await directory.create(recursive: true);
    final target = File('${directory.path}/${_name(key)}.hmw');
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final bytes = Uint8List(8 + peaks.length * 4);
    bytes.setRange(0, 4, const [0x48, 0x4d, 0x57, 0x31]);
    final data = ByteData.sublistView(bytes);
    data.setUint32(4, peaks.length, Endian.little);
    for (var index = 0; index < peaks.length; index++) {
      final offset = 8 + index * 4;
      data.setInt16(
        offset,
        (peaks[index].low.clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
      data.setInt16(
        offset + 2,
        (peaks[index].high.clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
    }
    await temporary.writeAsBytes(bytes, flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      try {
        await target.delete();
      } on FileSystemException catch (_) {}
      await temporary.rename(target.path);
    }
    await trim();
  }

  Future<void> trim() async {
    if (!await directory.exists()) return;
    final files = <({File file, FileStat stat})>[];
    var total = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.hmw')) continue;
      final stat = await entity.stat();
      total += stat.size;
      files.add((file: entity, stat: stat));
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final item in files) {
      if (total <= maxBytes) break;
      try {
        await item.file.delete();
        total -= item.stat.size;
      } on FileSystemException catch (_) {}
    }
  }

  String _name(String key) =>
      '${_fnv32(key).toRadixString(16).padLeft(8, '0')}-${_fnv32('HiMusic:$key').toRadixString(16).padLeft(8, '0')}';

  int _fnv32(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
