import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'music_source.dart';

class LocalSource implements MusicSource {
  LocalSource._(this.root);
  final String root;
  static Future<LocalSource> open(String root) async =>
      LocalSource._(await Directory(root).resolveSymbolicLinks());
  @override
  String get label => p.basename(root);

  Future<String> _resolve(String path) async {
    final joined = p.join(root, safePath(path));
    final resolved = await File(joined).resolveSymbolicLinks();
    if (resolved != root && !p.isWithin(root, resolved)) {
      throw const FileSystemException('文件超出所选目录');
    }
    return resolved;
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
  Future<void> close() async {}
}
