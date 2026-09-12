import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/metadata/metadata_index.dart';
import 'package:himusic/metadata/track_metadata.dart';
import 'package:himusic/metadata/track_metadata_reader.dart';
import 'package:himusic/sources/music_source.dart';

class _Source extends MusicSource {
  @override
  String get label => '测试来源';
  @override
  String get cacheNamespace => 'source';
  @override
  Future<void> close() async {}
  @override
  Future<List<MusicEntry>> list(String directory) async => [];
  @override
  Future<Uint8List> read(String path, int offset, int length) async =>
      Uint8List(0);
  @override
  Future<Uint8List?> readSidecar(
    MusicEntry entry,
    String extension, {
    required int maxBytes,
  }) async =>
      null;
}

class _Loader implements TrackMetadataLoader {
  final loaded = <String>[];

  @override
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry) async {
    loaded.add(entry.path);
    if (entry.path == 'broken.flac') throw const FormatException('bad tag');
    return TrackMetadata(title: '标签 ${entry.name}');
  }
}

void main() {
  test('后台索引音频文件并跳过目录和损坏标签', () async {
    final loader = _Loader();
    final index = MetadataIndex(loader: loader);
    const entries = [
      MusicEntry(path: 'folder', name: 'folder', isDirectory: true, size: 0),
      MusicEntry(path: 'a.flac', name: 'a.flac', isDirectory: false, size: 10),
      MusicEntry(
        path: 'broken.flac',
        name: 'broken.flac',
        isDirectory: false,
        size: 10,
      ),
    ];

    await index.scan(_Source(), entries);

    expect(loader.loaded, ['a.flac', 'broken.flac']);
    expect(index.metadataFor(entries[1])?.title, '标签 a.flac');
    expect(index.metadataFor(entries[2]), isNull);
    expect(index.failedCount, 1);
    expect(index.isScanning, isFalse);
  });

  test('文件未改变时复用缓存', () async {
    final loader = _Loader();
    final index = MetadataIndex(loader: loader);
    const entry = MusicEntry(
      path: 'a.flac',
      name: 'a.flac',
      isDirectory: false,
      size: 10,
    );

    await index.scan(_Source(), const [entry]);
    await index.scan(_Source(), const [entry]);

    expect(loader.loaded, ['a.flac']);
  });

  test('缓存超过容量后淘汰最早读取的歌曲', () async {
    final loader = _Loader();
    final index = MetadataIndex(loader: loader, maxEntries: 2);
    const first = MusicEntry(
      path: 'first.flac',
      name: 'first.flac',
      isDirectory: false,
      size: 10,
    );
    const second = MusicEntry(
      path: 'second.flac',
      name: 'second.flac',
      isDirectory: false,
      size: 10,
    );
    const third = MusicEntry(
      path: 'third.flac',
      name: 'third.flac',
      isDirectory: false,
      size: 10,
    );

    await index.scan(_Source(), const [first, second, third]);
    await index.scan(_Source(), const [first]);

    expect(loader.loaded.where((path) => path == 'first.flac').length, 2);
  });
}
