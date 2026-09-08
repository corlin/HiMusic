import 'package:flutter/foundation.dart';

import '../sources/music_source.dart';
import 'lyrics_document.dart';
import 'lyrics_repository.dart';

enum LyricsStatus { idle, loading, ready, empty, error }

class LyricsController extends ChangeNotifier {
  LyricsController({LyricsLoader? repository})
    : _repository = repository ?? LyricsRepository();

  final LyricsLoader _repository;
  int _generation = 0;
  MusicSource? _source;
  MusicEntry? entry;
  LyricsDocument? document;
  LyricsStatus status = LyricsStatus.idle;
  int currentLineIndex = -1;

  Future<void> load(MusicSource source, MusicEntry entry) async {
    final generation = ++_generation;
    _source = source;
    this.entry = entry;
    document = null;
    currentLineIndex = -1;
    status = LyricsStatus.loading;
    notifyListeners();
    try {
      final result = await _repository.load(source, entry);
      if (generation != _generation) return;
      document = result;
      status = result == null ? LyricsStatus.empty : LyricsStatus.ready;
    } catch (_) {
      if (generation != _generation) return;
      status = LyricsStatus.error;
    }
    notifyListeners();
  }

  Future<void> retry() async {
    final source = _source;
    final current = entry;
    if (source != null && current != null) await load(source, current);
  }

  void updatePosition(Duration position) {
    final lines = document?.lines;
    if (lines == null || lines.isEmpty) return;
    var low = 0;
    var high = lines.length - 1;
    var found = -1;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      if (lines[middle].timestamp <= position) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    if (found != currentLineIndex) {
      currentLineIndex = found;
      notifyListeners();
    }
  }

  void clear() {
    _generation++;
    _source = null;
    entry = null;
    document = null;
    currentLineIndex = -1;
    status = LyricsStatus.idle;
    notifyListeners();
  }
}
