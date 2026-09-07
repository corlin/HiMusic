import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'music_source.dart';

/// Only exposes files explicitly granted by the system picker, never siblings.
class SelectedFilesSource implements MusicSource {
  SelectedFilesSource(List<XFile> files) : _files = List.unmodifiable(files);
  final List<XFile> _files;
  @override
  String get label => '本地音乐';
  @override
  String get cacheNamespace => _files.map((f) => f.path).join('\u0000');
  @override
  Future<List<MusicEntry>> list(String directory) async {
    if (directory.isNotEmpty) throw const FileSystemException('未知目录');
    final entries = <MusicEntry>[];
    for (var i = 0; i < _files.length; i++) {
      final file = _files[i];
      final entry = MusicEntry(
        path: '$i',
        name: file.name,
        isDirectory: false,
        size: await file.length(),
        modified: await file.lastModified(),
      );
      if (entry.isAudio) entries.add(entry);
    }
    return sortEntries(entries);
  }

  @override
  Future<Uint8List> read(String path, int offset, int length) async {
    final index = int.tryParse(path);
    if (index == null ||
        index < 0 ||
        index >= _files.length ||
        offset < 0 ||
        length < 0) {
      throw const FileSystemException('无效文件范围');
    }
    final result = BytesBuilder(copy: false);
    await for (final chunk in _files[index].openRead(offset, offset + length)) {
      result.add(chunk);
    }
    return result.takeBytes();
  }

  @override
  Future<void> close() async {}
}
