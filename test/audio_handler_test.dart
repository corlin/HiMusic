import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/metadata/metadata_index.dart';
import 'package:himusic/metadata/track_metadata.dart';
import 'package:himusic/metadata/track_metadata_reader.dart';
import 'package:himusic/playback/audio_handler.dart';
import 'package:himusic/playback/player_controller.dart';
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
  @override
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry) async {
    if (entry.path == 'cover.flac') {
      return TrackMetadata(
        title: '带封面',
        performers: const ['歌手甲'],
        album: '专辑甲',
        duration: const Duration(minutes: 2),
        artwork: Uint8List.fromList(const [1, 2, 3, 4]),
      );
    }
    return TrackMetadata(title: '普通 ${entry.path}');
  }
}

const _entries = [
  MusicEntry(path: 'a.flac', name: 'a.flac', isDirectory: false, size: 100),
  MusicEntry(
    path: 'cover.flac',
    name: 'cover.flac',
    isDirectory: false,
    size: 100,
  ),
];

Future<PlayerController> _build() async {
  final controller =
      PlayerController(metadataIndex: MetadataIndex(loader: _Loader()))
        ..source = _Source()
        ..directory = 'music'
        ..entries = _entries
        ..queue = _entries;
  await controller.metadata.scan(controller.source!, controller.entries);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无封面条目：媒体信息用文件名兜底，无封面', () {
    const entry = MusicEntry(
      path: 'x.flac',
      name: 'x.flac',
      isDirectory: false,
      size: 1,
    );
    final item = buildMediaItem(entry, null);
    expect(item.title, 'x');
    expect(item.artist, isNull);
    expect(item.album, isNull);
    expect(item.artUri, isNull);
  });

  test('有元数据条目：标题/艺术家/专辑/时长映射', () {
    const entry = MusicEntry(
      path: 'y.flac',
      name: 'y.flac',
      isDirectory: false,
      size: 1,
    );
    final item = buildMediaItem(
      entry,
      const TrackMetadata(
        title: '歌曲乙',
        performers: ['歌手乙'],
        album: '专辑乙',
        duration: Duration(minutes: 4),
      ),
    );
    expect(item.title, '歌曲乙');
    expect(item.artist, '歌手乙');
    expect(item.album, '专辑乙');
    expect(item.duration, const Duration(minutes: 4));
    expect(item.artUri, isNull);
  });

  test('提供封面路径时 artUri 指向本地文件', () {
    const entry = MusicEntry(
      path: 'z.flac',
      name: 'z.flac',
      isDirectory: false,
      size: 1,
    );
    final item = buildMediaItem(
      entry,
      const TrackMetadata(title: '带封面'),
      artPath: '/tmp/cover.jpg',
    );
    expect(item.artUri, isNotNull);
    expect(item.artUri!.scheme, 'file');
    expect(item.artUri!.path, '/tmp/cover.jpg');
  });

  test('handler 同步队列文字信息与初始播放状态', () async {
    final controller = await _build();
    final handler = HiMusicAudioHandler(controller);
    await null;
    expect(handler.queue.value.length, 2);
    expect(handler.queue.value[0].title, '普通 a.flac');
    expect(handler.queue.value[1].title, '带封面');
    expect(handler.queue.value[1].artist, '歌手甲');
    expect(handler.queue.value[1].album, '专辑甲');
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.idle);
    expect(handler.playbackState.value.controls.length, 3);
    expect(handler.mediaItem.value, isNull);
    controller.dispose();
  });

  test('队列变化后 handler 重新同步', () async {
    final controller = await _build();
    final handler = HiMusicAudioHandler(controller);
    controller.queue = _entries.take(1).toList();
    controller.notifyListeners();
    await null;
    expect(handler.queue.value.length, 1);
    expect(handler.queue.value[0].title, '普通 a.flac');
    controller.dispose();
  });
}
