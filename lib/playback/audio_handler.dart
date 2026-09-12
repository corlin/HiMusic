import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../metadata/track_metadata.dart';
import '../sources/music_source.dart';
import '../util/format.dart';
import 'player_controller.dart';

/// 构造系统媒体信息；[artPath] 为封面文件路径（无则 null）。
MediaItem buildMediaItem(
  MusicEntry entry,
  TrackMetadata? metadata, {
  String? artPath,
}) =>
    MediaItem(
      id: entry.path,
      title: metadata?.displayTitle(entry.name) ?? stripExtension(entry.name),
      artist: metadata?.artistLine,
      album: metadata?.album,
      duration: metadata?.duration,
      artUri: artPath == null ? null : Uri.file(artPath),
    );

/// 把 [PlayerController] 暴露给系统媒体控制（audio_service）。
///
/// 仅做适配转发，不持有业务逻辑；[PlayerController] 不反向依赖本类。
class HiMusicAudioHandler extends BaseAudioHandler {
  HiMusicAudioHandler(this.controller) {
    controller.addListener(_sync);
    _sync();
  }

  final PlayerController controller;

  static const String _fallbackArtAsset =
      'assets/artwork/placeholder-cover.jpg';

  final Map<String, String> _artCache = {};
  String? _fallbackArtPath;

  /// 把无封面时的内置占位封面写入临时文件（失败则保持无封面）。
  Future<void> loadFallbackArt() async {
    try {
      final data = await rootBundle.load(_fallbackArtAsset);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/himusic_placeholder_cover.jpg');
      if (!await file.exists()) {
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      _fallbackArtPath = file.path;
    } catch (_) {
      _fallbackArtPath = null;
    }
  }

  Future<String?> _artPath(MusicEntry entry) async {
    final metadata = controller.metadata.metadataFor(entry);
    if (metadata?.artwork == null) return _fallbackArtPath;
    final cached = _artCache[entry.path];
    if (cached != null) return cached;
    try {
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/himusic_art_${entry.path.hashCode & 0x7fffffff}.jpg');
      await file.writeAsBytes(metadata!.artwork!, flush: true);
      _artCache[entry.path] = file.path;
      return file.path;
    } catch (_) {
      return _fallbackArtPath;
    }
  }

  void _sync() {
    final current = controller.current;
    queue.add(
      controller.queue
          .map(_plainMediaItem)
          .toList(growable: false),
    );
    if (current == null) {
      mediaItem.add(null);
      _publishState(playing: false, index: null);
      return;
    }
    final index = controller.queue.indexOf(current);
    unawaited(_publishCurrent(current, index < 0 ? 0 : index));
  }

  /// 队列条目：只带文字信息（批量同步不做封面 IO）。
  MediaItem _plainMediaItem(MusicEntry entry) => buildMediaItem(
    entry,
    controller.metadata.metadataFor(entry),
  );

  Future<void> _publishCurrent(MusicEntry entry, int index) async {
    final artPath = await _artPath(entry);
    mediaItem.add(
      buildMediaItem(
        entry,
        controller.metadata.metadataFor(entry),
        artPath: artPath,
      ),
    );
    _publishState(playing: controller.player.playing, index: index);
  }

  void _publishState({required bool playing, required int? index}) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _processingState(),
        playing: playing,
        updatePosition: controller.player.position,
        queueIndex: index,
      ),
    );
  }

  AudioProcessingState _processingState() => switch (
    controller.player.processingState
  ) {
    ProcessingState.idle => AudioProcessingState.idle,
    ProcessingState.loading => AudioProcessingState.loading,
    ProcessingState.buffering => AudioProcessingState.buffering,
    ProcessingState.ready => AudioProcessingState.ready,
    ProcessingState.completed => AudioProcessingState.completed,
  };

  @override
  Future<void> play() => controller.play();
  @override
  Future<void> pause() => controller.pause();
  @override
  Future<void> seek(Duration position) => controller.seek(position);
  @override
  Future<void> skipToNext() => controller.skip(true);
  @override
  Future<void> skipToPrevious() => controller.skip(false);
  @override
  Future<void> stop() => controller.stopPlayback();
}
