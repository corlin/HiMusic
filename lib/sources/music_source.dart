import 'dart:typed_data';

class MusicEntry {
  const MusicEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    this.modified,
  });
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
  String get extension => name.split('.').last.toLowerCase();
  bool get isAudio =>
      !isDirectory &&
      const {'flac', 'mp3', 'm4a', 'aac', 'wav', 'alac'}.contains(extension);
  String get mimeType => switch (extension) {
    'flac' => 'audio/flac',
    'mp3' => 'audio/mpeg',
    'm4a' || 'alac' => 'audio/mp4',
    'aac' => 'audio/aac',
    'wav' => 'audio/wav',
    _ => 'application/octet-stream',
  };
}

/// Share-relative paths. Reject traversal instead of silently normalizing it.
String safePath(String path) {
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.any((p) => p == '..' || p == '.' || p.contains('\u0000'))) {
    throw const FormatException('目录路径不能包含 . 或 ..');
  }
  return parts.join('/');
}

abstract interface class MusicSource {
  String get label;
  Future<List<MusicEntry>> list(String directory);
  Future<Uint8List> read(String path, int offset, int length);
  Future<void> close();
}

List<MusicEntry> sortEntries(Iterable<MusicEntry> entries) =>
    entries.toList()..sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
