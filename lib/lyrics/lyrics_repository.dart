import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../metadata/track_metadata.dart';
import '../sources/music_source.dart';
import 'embedded_lyrics_reader.dart';
import 'lrc_parser.dart';
import 'lrclib_client.dart';
import 'lyrics_document.dart';

/// 联网获取歌词的结果。
sealed class LrclibFetchResult {}

/// 精确匹配成功，直接返回歌词文档。
class LrclibDirect extends LrclibFetchResult {
  LrclibDirect(this.document);
  final LyricsDocument document;
}

/// 精确匹配失败，返回多个候选供用户选择。
class LrclibChoices extends LrclibFetchResult {
  LrclibChoices(this.choices);
  final List<LrclibLyrics> choices;
}

/// 未找到歌词。
class LrclibNotFound extends LrclibFetchResult {}

abstract interface class LyricsLoader {
  Future<LyricsDocument?> load(MusicSource source, MusicEntry entry);
}

class LyricsRepository implements LyricsLoader {
  LyricsRepository({
    EmbeddedLyricsLoader? embeddedReader,
    LrcParser? parser,
    LrclibClient? lrclib,
    this.maxEntries = 128,
  }) : _embeddedReader = embeddedReader ?? EmbeddedLyricsReader(),
       _parser = parser ?? LrcParser(),
       _lrclib = lrclib ?? LrclibClient();

  static const maxSidecarBytes = 2 * 1024 * 1024;
  final EmbeddedLyricsLoader _embeddedReader;
  final LrcParser _parser;
  final LrclibClient _lrclib;
  final int maxEntries;
  final LinkedHashMap<String, LyricsDocument?> _cache = LinkedHashMap();

  @override
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

  /// 联网获取歌词。
  ///
  /// 1. 先用 [metadata] 精确匹配 LRCLIB `/api/get`
  /// 2. 精确匹配失败时，用关键词搜索 `/api/search`
  /// 3. 搜索结果唯一时直接采用，多个时返回候选列表
  Future<LrclibFetchResult> fetchOnline(
    MusicSource source,
    MusicEntry entry,
    TrackMetadata metadata,
  ) async {
    final title = metadata.title ?? entry.name;
    final artist = metadata.performers.isNotEmpty ? metadata.performers.first : null;
    final album = metadata.album;
    final duration = metadata.duration;

    // 1. 精确匹配
    try {
      final direct = await _lrclib.getLyrics(
        trackName: title,
        artistName: artist,
        albumName: album,
        duration: duration,
      );
      if (direct != null) {
        final doc = await _saveAndParse(source, entry, direct);
        if (doc != null) return LrclibDirect(doc);
      }
    } catch (_) {
      // 精确匹配失败，继续搜索
    }

    // 2. 模糊搜索
    try {
      final query = [title, artist].where((s) => s != null && s.isNotEmpty).join(' ');
      final results = await _lrclib.searchLyrics(
        trackName: title,
        artistName: artist,
        albumName: album,
        query: query,
      );
      if (results.isEmpty) return LrclibNotFound();
      if (results.length == 1) {
        final doc = await _saveAndParse(source, entry, results.first);
        if (doc != null) return LrclibDirect(doc);
      }
      return LrclibChoices(results);
    } catch (_) {
      return LrclibNotFound();
    }
  }

  /// 用户从搜索结果中选择一个候选，保存并解析。
  Future<LyricsDocument?> applyChoice(
    MusicSource source,
    MusicEntry entry,
    LrclibLyrics choice,
  ) =>
      _saveAndParse(source, entry, choice);

  /// 将 LRCLIB 歌词写入 sidecar 文件并解析为 LyricsDocument。
  Future<LyricsDocument?> _saveAndParse(
    MusicSource source,
    MusicEntry entry,
    LrclibLyrics lyrics,
  ) async {
    final content = lyrics.syncedLyrics ?? lyrics.plainLyrics;
    if (content == null || content.trim().isEmpty) return null;

    // 写入 sidecar .lrc 文件
    try {
      await source.writeSidecar(
        entry,
        'lrc',
        Uint8List.fromList(utf8.encode(content)),
      );
    } catch (_) {
      // 写入失败不影响内存中的歌词显示
    }

    // 解析为 LyricsDocument
    try {
      final doc = _parser.parse(Uint8List.fromList(utf8.encode(content)));
      _cache[_key(source, entry)] = doc;
      return doc;
    } catch (_) {
      return null;
    }
  }
}
