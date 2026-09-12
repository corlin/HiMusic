import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

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
      !name.startsWith('.') &&
      size > 0 &&
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

abstract class MusicSource {
  String get label;
  String get cacheNamespace;
  Future<List<MusicEntry>> list(String directory);
  Future<Uint8List> read(String path, int offset, int length);
  Future<Uint8List?> readSidecar(
    MusicEntry entry,
    String extension, {
    required int maxBytes,
  });

  /// 写入与 [entry] 同名的 sidecar 文件。
  ///
  /// [extension] 不含点，例如 `lrc`。
  /// 默认不支持写入的源会抛出 [UnsupportedError]。
  Future<void> writeSidecar(MusicEntry entry, String extension, Uint8List bytes) {
    throw UnsupportedError('当前音源不支持写入歌词文件');
  }

  Future<void> close();
}

List<MusicEntry> sortEntries(Iterable<MusicEntry> entries) =>
    entries.toList()..sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

/// 音频文件对应的 sidecar 期望文件名（不区分大小写比较）。
///
/// [audioName] 可为完整路径；[extension] 可带或不带点，例如 `lrc` / `.lrc`。
String sidecarNameFor(String audioName, String extension) {
  final base = p.basenameWithoutExtension(audioName);
  final dot = extension.startsWith('.') ? '' : '.';
  return '$base$dot$extension';
}

/// [candidateName] 是否为音频 [audioName] 的同名 [extension] sidecar 文件。
bool isSidecarName(String candidateName, String audioName, String extension) =>
    candidateName.toLowerCase() ==
    sidecarNameFor(audioName, extension).toLowerCase();

/// 在音频所在目录写入同名 [extension] 的 sidecar 文件。
Future<void> writeSidecarFile(
  String audioPath,
  String extension,
  Uint8List bytes,
) async {
  final target = p.join(
    p.dirname(audioPath),
    sidecarNameFor(p.basename(audioPath), extension),
  );
  await File(target).writeAsBytes(bytes, flush: true);
}
