import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/sources/music_source.dart';
import 'package:himusic/sources/local_source.dart';
import 'package:himusic/sources/selected_files_source.dart';

void main() {
  test('忽略隐藏音频、非零 Apple 辅助文件和零字节文件', () {
    for (final name in ['._song.flac', '.song.mp3', 'empty.wav']) {
      final entry = MusicEntry(
        path: name,
        name: name,
        isDirectory: false,
        size: name == 'empty.wav' ? 0 : 4096,
      );
      expect(entry.isAudio, isFalse, reason: name);
    }
    expect(
      const MusicEntry(
        path: 'song.FLAC',
        name: 'song.FLAC',
        isDirectory: false,
        size: 100,
      ).isAudio,
      isTrue,
    );
  });
  test('本地目录和文件选择器统一过滤且不删除源文件', () async {
    final dir = await Directory.systemTemp.createTemp('music-filter-');
    addTearDown(() => dir.delete(recursive: true));
    final files = <XFile>[];
    for (final name in [
      '._song.flac',
      '.hidden.mp3',
      'empty.wav',
      'cover.jpg',
      'lyrics.lrc',
      'notes.txt',
      'song.flac',
    ]) {
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(name == 'empty.wav' ? [] : [1, 2, 3, 4]);
      files.add(XFile(file.path));
    }
    for (final source in [
      await LocalSource.open(dir.path),
      SelectedFilesSource(files),
    ]) {
      expect((await source.list('')).map((e) => e.name), ['song.flac']);
      await source.close();
    }
    expect(await dir.list().length, 7);
  });
}
