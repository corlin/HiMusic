import 'dart:collection';

import '../sources/music_source.dart';
import 'embedded_lyrics_reader.dart';
import 'lrc_parser.dart';
import 'lyrics_document.dart';

class LyricsRepository {
  LyricsRepository({
    EmbeddedLyricsLoader? embeddedReader,
    LrcParser? parser,
    this.maxEntries = 128,
  }) : _embeddedReader = embeddedReader ?? EmbeddedLyricsReader(),
       _parser = parser ?? LrcParser();

  static const maxSidecarBytes = 2 * 1024 * 1024;
  final EmbeddedLyricsLoader _embeddedReader;
  final LrcParser _parser;
  final int maxEntries;
  final LinkedHashMap<String, LyricsDocument?> _cache = LinkedHashMap();

  Future<LyricsDocument?> load(MusicSource source, MusicEntry entry) async {
    final key = _key(source, entry);
    if (_cache.containsKey(key)) {
      final cached = _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }

    EmbeddedLyricsCandidates embedded = const EmbeddedLyricsCandidates();
    try {
      embedded = await _embeddedReader.read(source, entry);
    } catch (_) {
      // A damaged metadata tag must not prevent a valid sidecar from loading.
    }
    LyricsDocument? result = embedded.synchronized;
    if (result == null) {
      try {
        final bytes = await source.readSidecar(
          entry,
          '.lrc',
          maxBytes: maxSidecarBytes,
        );
        if (bytes != null) result = _parser.parse(bytes);
      } catch (_) {
        // Fall through to plain embedded lyrics.
      }
    }
    result ??= embedded.plain;
    _cache[key] = result;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  String _key(MusicSource source, MusicEntry entry) =>
      '${source.cacheNamespace}|${entry.path}|${entry.size}|'
      '${entry.modified?.millisecondsSinceEpoch ?? ''}';
}
