import 'package:flutter/foundation.dart';

import '../metadata/track_metadata.dart';
import '../sources/music_source.dart';
import 'lrclib_client.dart';
import 'lyrics_document.dart';
import 'lyrics_repository.dart';

enum LyricsStatus { idle, loading, ready, empty, error, fetching }

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
  List<LrclibLyrics>? pendingChoices;

  Future<void> load(MusicSource source, MusicEntry entry) async {
    final generation = ++_generation;
    _source = source;
    this.entry = entry;
    document = null;
    pendingChoices = null;
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

  /// 联网获取歌词。精确匹配成功直接显示，多个候选时设置 [pendingChoices]。
  Future<void> fetchOnline(TrackMetadata metadata) async {
    final source = _source;
    final current = entry;
    if (source == null || current == null) return;
    final repo = _repository;
    if (repo is! LyricsRepository) return;

    final generation = ++_generation;
    status = LyricsStatus.fetching;
    pendingChoices = null;
    notifyListeners();

    try {
      final result = await repo.fetchOnline(source, current, metadata);
      if (generation != _generation) return;
      switch (result) {
        case LrclibDirect(:final document):
          this.document = document;
          status = LyricsStatus.ready;
        case LrclibChoices(:final choices):
          pendingChoices = choices;
          status = LyricsStatus.empty;
        case LrclibNotFound():
          status = LyricsStatus.empty;
      }
    } catch (_) {
      if (generation != _generation) return;
      status = LyricsStatus.error;
    }
    notifyListeners();
  }

  /// 用户从搜索候选中选择一个，应用并显示。
  Future<void> applyChoice(LrclibLyrics choice) async {
    final source = _source;
    final current = entry;
    if (source == null || current == null) return;
    final repo = _repository;
    if (repo is! LyricsRepository) return;

    final generation = ++_generation;
    status = LyricsStatus.fetching;
    notifyListeners();

    try {
      final doc = await repo.applyChoice(source, current, choice);
      if (generation != _generation) return;
      if (doc != null) {
        document = doc;
        status = LyricsStatus.ready;
      } else {
        status = LyricsStatus.empty;
      }
    } catch (_) {
      if (generation != _generation) return;
      status = LyricsStatus.error;
    }
    pendingChoices = null;
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
