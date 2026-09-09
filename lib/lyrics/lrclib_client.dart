import 'dart:convert';
import 'dart:io';

/// LRCLIB (lrclib.net) 歌词 API 客户端。
///
/// 参考 lrcget 实现：
/// - GET /api/get  精确匹配（artist + track + album + duration），直接返回歌词
/// - GET /api/search  模糊搜索，返回候选列表
class LrclibClient {
  LrclibClient({
    this.baseUrl = 'https://lrclib.net',
    this.timeout = const Duration(seconds: 10),
    String? userAgent,
  }) : userAgent = userAgent ?? 'HiMusic (https://github.com/corlin/HiMusic)';

  final String baseUrl;
  final Duration timeout;
  final String userAgent;

  /// 精确获取歌词。匹配成功返回歌词，未找到返回 null。
  Future<LrclibLyrics?> getLyrics({
    required String trackName,
    String? artistName,
    String? albumName,
    Duration? duration,
  }) async {
    final params = <String, String>{
      'track_name': trackName,
      if (artistName != null) 'artist_name': artistName,
      if (albumName != null) 'album_name': albumName,
      if (duration != null) 'duration': duration.inSeconds.toString(),
    };
    final uri = Uri.parse('$baseUrl/api/get').replace(queryParameters: params);
    final data = await _get(uri);
    if (data == null) return null;
    final lyrics = LrclibLyrics.fromJson(data);
    if (lyrics.isEmpty && !lyrics.instrumental) return null;
    return lyrics;
  }

  /// 模糊搜索歌词，返回候选列表。
  Future<List<LrclibLyrics>> searchLyrics({
    String? trackName,
    String? artistName,
    String? albumName,
    String? query,
  }) async {
    final params = <String, String>{
      if (trackName != null) 'track_name': trackName,
      if (artistName != null) 'artist_name': artistName,
      if (albumName != null) 'album_name': albumName,
      if (query != null) 'q': query,
    };
    final uri = Uri.parse('$baseUrl/api/search').replace(queryParameters: params);
    final data = await _get(uri);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(LrclibLyrics.fromJson)
        .toList();
  }

  Future<dynamic> _get(Uri uri) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = timeout;
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode != HttpStatus.ok) {
        throw LrclibException(
          statusCode: response.statusCode,
          message: 'LRCLIB 请求失败: ${response.statusCode}',
        );
      }
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } on SocketException catch (e) {
      throw LrclibException(message: '网络连接失败: $e');
    } finally {
      client.close();
    }
  }
}

class LrclibLyrics {
  const LrclibLyrics({
    this.id,
    this.name,
    this.artistName,
    this.albumName,
    this.duration,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
  });

  factory LrclibLyrics.fromJson(Map<String, dynamic> json) => LrclibLyrics(
    id: (json['id'] as num?)?.toInt(),
    name: json['name'] as String?,
    artistName: json['artistName'] as String?,
    albumName: json['albumName'] as String?,
    duration: (json['duration'] as num?)?.toDouble(),
    instrumental: json['instrumental'] as bool? ?? false,
    plainLyrics: json['plainLyrics'] as String?,
    syncedLyrics: json['syncedLyrics'] as String?,
  );

  final int? id;
  final String? name;
  final String? artistName;
  final String? albumName;
  final double? duration;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  bool get isEmpty =>
      (plainLyrics == null || plainLyrics!.trim().isEmpty) &&
      (syncedLyrics == null || syncedLyrics!.trim().isEmpty);

  bool get hasSynced => syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;

  String get displayTitle =>
      name ??
      (artistName != null ? '$artistName - ${albumName ?? ''}' : '未知歌曲');
}

class LrclibException implements Exception {
  const LrclibException({this.statusCode, required this.message});
  final int? statusCode;
  final String message;
  @override
  String toString() => message;
}
