import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'music_source.dart';

class LocalSource implements MusicSource {
  LocalSource._(this.root);
  final String root;
  static Future<LocalSource> open(String root) async {
    try {
      return LocalSource._(await Directory(root).resolveSymbolicLinks());
    } catch (_) {
      // iOS 安全范围 URL 路径可能包含无法解析的符号链接，
      // 回退到原始路径（安全范围本身已提供沙盒保护）。
      return LocalSource._(root);
    }
  }
  @override
  String get label => p.basename(root);
  @override
  String get cacheNamespace => root;

  Future<String> _resolve(String path) async {
    final joined = p.join(root, safePath(path));
    try {
      final resolved = await File(joined).resolveSymbolicLinks();
      if (resolved != root && !p.isWithin(root, resolved)) {
        throw const FileSystemException('文件超出所选目录');
      }
      return resolved;
    } catch (_) {
      // iOS 安全范围路径回退：不做符号链接解析，直接使用拼接路径。
      return joined;
    }
  }

  @override
  Future<List<MusicEntry>> list(String directory) async {
    final path = safePath(directory);
    final result = <MusicEntry>[];
    await for (final entry in Directory(
      await _resolve(path),
    ).list(followLinks: false)) {
      if (entry is Link) continue;
      final stat = await entry.stat();
      final item = MusicEntry(
        path: [
          path,
          p.basename(entry.path),
        ].where((s) => s.isNotEmpty).join('/'),
        name: p.basename(entry.path),
        isDirectory: stat.type == FileSystemEntityType.directory,
        size: stat.size,
        modified: stat.modified,
      );
      if (item.isDirectory || item.isAudio) result.add(item);
    }
    return sortEntries(result);
  }

  @override
  Future<Uint8List> read(String path, int offset, int length) async {
    final file = await File(await _resolve(path)).open(mode: FileMode.read);
    try {
      await file.setPosition(offset);
      return await file.read(length);
    } finally {
      await file.close();
    }
  }

  @override
  Future<Uint8List?> readSidecar(
    MusicEntry entry,
    String extension, {
    required int maxBytes,
  }) async {
    final audioPath = await _resolve(entry.path);
    final wanted = '${p.basenameWithoutExtension(audioPath)}$extension';
    await for (final candidate in Directory(p.dirname(audioPath)).list()) {
      if (candidate is! File ||
          p.basename(candidate.path).toLowerCase() != wanted.toLowerCase()) {
        continue;
      }
      final size = await candidate.length();
      if (size > maxBytes) throw const FileSystemException('歌词文件过大');
      return candidate.readAsBytes();
    }
    return null;
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> writeSidecar(
    MusicEntry entry,
    String extension,
    Uint8List bytes,
  ) async {
    final audioPath = await _resolve(entry.path);
    final dir = p.dirname(audioPath);
    final base = p.basenameWithoutExtension(audioPath);
    final target = p.join(dir, '$base.$extension');
    await File(target).writeAsBytes(bytes, flush: true);
  }
}
