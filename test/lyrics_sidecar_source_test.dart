import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/sources/local_source.dart';
import 'package:himusic/sources/selected_files_source.dart';

void main() {
  test('本地来源只读取同名且不区分大小写的 LRC', () async {
    final root = await Directory.systemTemp.createTemp('himusic-lrc-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/Song.flac').writeAsBytes([1]);
    await File('${root.path}/song.LRC').writeAsString('[00:01]第一句');
    await File('${root.path}/other.lrc').writeAsString('错误');
    final source = await LocalSource.open(root.path);
    final song = (await source.list('')).single;
    final bytes = await source.readSidecar(song, '.lrc', maxBytes: 1024);
    expect(utf8.decode(bytes!), contains('第一句'));
  });

  test('已选文件来源保留歌词授权但列表只公开音乐', () async {
    final root = await Directory.systemTemp.createTemp('himusic-picked-lrc-');
    addTearDown(() => root.delete(recursive: true));
    final audio = File('${root.path}/夜航.flac')..writeAsBytesSync([1]);
    final lyric = File('${root.path}/夜航.lrc')..writeAsStringSync('[00:01]起航');
    final source = SelectedFilesSource([XFile(audio.path), XFile(lyric.path)]);
    final entries = await source.list('');
    expect(entries.map((entry) => entry.name), ['夜航.flac']);
    expect(
      utf8.decode((await source.readSidecar(entries.single, '.lrc', maxBytes: 1024))!),
      contains('起航'),
    );
  });

  test('歌词超过读取上限时拒绝', () async {
    final root = await Directory.systemTemp.createTemp('himusic-large-lrc-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/song.flac').writeAsBytes([1]);
    await File('${root.path}/song.lrc').writeAsBytes(List.filled(8, 1));
    final source = await LocalSource.open(root.path);
    final song = (await source.list('')).single;
    expect(
      () => source.readSidecar(song, '.lrc', maxBytes: 4),
      throwsA(isA<FileSystemException>()),
    );
  });
}
