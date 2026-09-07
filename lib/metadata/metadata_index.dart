import 'package:flutter/foundation.dart';

import '../sources/music_source.dart';
import 'track_metadata.dart';
import 'track_metadata_reader.dart';

class MetadataIndex extends ChangeNotifier {
  MetadataIndex({TrackMetadataLoader? loader, this.maxEntries = 512})
    : assert(maxEntries > 0),
      _loader = loader ?? TrackMetadataReader();

  final TrackMetadataLoader _loader;
  final int maxEntries;
  final Map<String, TrackMetadata> _cache = {};
  final Map<String, String> _pathsByKey = {};
  final Map<String, TrackMetadata> _visible = {};
  int _generation = 0;
  bool isScanning = false;
  int failedCount = 0;

  TrackMetadata? metadataFor(MusicEntry entry) => _visible[entry.path];

  Future<void> scan(MusicSource source, List<MusicEntry> entries) async {
    final generation = ++_generation;
    failedCount = 0;
    final pending = <({MusicEntry entry, String key})>[];
    for (final entry in entries.where((entry) => entry.isAudio)) {
      final key = _key(source, entry);
      final cached = _cache[key];
      if (cached == null) {
        _visible.remove(entry.path);
        pending.add((entry: entry, key: key));
      } else {
        _visible[entry.path] = cached;
      }
    }
    isScanning = pending.isNotEmpty;
    notifyListeners();

    var cursor = 0;
    Future<void> worker() async {
      while (cursor < pending.length) {
        final item = pending[cursor++];
        try {
          final metadata = await _loader.read(source, item.entry);
          if (generation != _generation) return;
          _remember(item.key, item.entry.path, metadata);
          _visible[item.entry.path] = metadata;
          notifyListeners();
        } catch (_) {
          if (generation != _generation) return;
          failedCount++;
          notifyListeners();
        }
      }
    }

    await Future.wait(
      List.generate(pending.length.clamp(0, 2), (_) => worker()),
    );
    if (generation == _generation) {
      isScanning = false;
      notifyListeners();
    }
  }

  String _key(MusicSource source, MusicEntry entry) =>
      '${source.cacheNamespace}\u0000${entry.path}\u0000${entry.size}\u0000${entry.modified?.millisecondsSinceEpoch ?? 0}';

  void _remember(String key, String path, TrackMetadata metadata) {
    _cache.remove(key);
    _cache[key] = metadata;
    _pathsByKey[key] = path;
    while (_cache.length > maxEntries) {
      final oldestKey = _cache.keys.first;
      final oldest = _cache.remove(oldestKey);
      final oldestPath = _pathsByKey.remove(oldestKey);
      if (oldestPath != null && identical(_visible[oldestPath], oldest)) {
        _visible.remove(oldestPath);
      }
    }
  }

  void cancel() {
    _generation++;
    isScanning = false;
    _visible.clear();
  }
}
