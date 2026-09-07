import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/sources/selected_files_source.dart';

void main() {
  test('多选同名文件隔离映射、范围读取且不暴露其他文件', () async {
    final dir = await Directory.systemTemp.createTemp('selected-audio-');
    try {
      await Directory('${dir.path}/a').create();
      await Directory('${dir.path}/b').create();
      final first = File('${dir.path}/a/song.flac');
      final second = File('${dir.path}/b/song.flac');
      await first.writeAsBytes([1, 2, 3, 4]);
      await second.writeAsBytes([5, 6, 7, 8]);
      final source = SelectedFilesSource([
        XFile(first.path, name: 'song.flac'),
        XFile(second.path, name: 'song.flac'),
      ]);
      final entries = await source.list('');
      expect(entries.length, 2);
      expect(entries.map((e) => e.path).toSet().length, 2);
      expect(await source.read('0', 1, 2), [2, 3]);
      expect(await source.read('1', 1, 2), [6, 7]);
      await expectLater(
        source.read('../first', 0, 1),
        throwsA(isA<FileSystemException>()),
      );
      await source.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
