import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../sources/music_source.dart';
import '../sources/smb_source.dart';
import 'audio_bridge.dart';

class PlayerController extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();
  MusicSource? source;
  AudioBridge? _bridge;
  String directory = '';
  List<MusicEntry> entries = [];
  List<MusicEntry> queue = [];
  String? error;
  bool busy = false;
  bool _disposed = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PlayerController() {
    _subscriptions.add(player.playerStateStream.listen((_) => _changed()));
    _subscriptions.add(player.currentIndexStream.listen((_) => _changed()));
    _subscriptions.add(
      player.errorStream.listen((_) {
        error = '播放中断，请检查网络或文件格式，然后按重试。';
        _changed();
      }),
    );
  }
  MusicEntry? get current {
    final index = player.currentIndex;
    return index != null && index < queue.length ? queue[index] : null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    _changed();
    try {
      await action();
    } catch (e) {
      error = sourceError(e);
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> connect(Future<MusicSource> Function() factory, String root) =>
      run(() async {
        final next = await factory();
        late List<MusicEntry> files;
        try {
          files = await next.list(safePath(root));
        } catch (_) {
          await next.close();
          rethrow;
        }
        await player.stop();
        await _bridge?.close();
        _bridge = null;
        await source?.close();
        source = next;
        directory = safePath(root);
        entries = files;
        queue = [];
      });

  Future<void> browse(String path) => run(() async {
    final files = await source!.list(safePath(path));
    directory = safePath(path);
    entries = files;
  });
  Future<void> up() => browse(
    directory.contains('/')
        ? directory.substring(0, directory.lastIndexOf('/'))
        : '',
  );

  Future<void> playEntry(MusicEntry entry) => run(() async {
    await player.stop();
    await _bridge?.close();
    _bridge = await AudioBridge.start(source!);
    queue = entries.where((e) => e.isAudio).toList();
    await player.setAudioSources(
      queue.map((e) => AudioSource.uri(_bridge!.register(e))).toList(),
      initialIndex: queue.indexOf(entry),
    );
    unawaited(_play());
  });
  Future<void> _play() async {
    try {
      await player.play();
    } catch (_) {
      error = '无法播放，请检查网络或音频格式，然后重试。';
      _changed();
    }
  }

  Future<void> toggle() => run(() async {
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero, index: 0);
      }
      unawaited(_play());
    }
  });
  Future<void> retry() => run(() async {
    if (queue.isEmpty) {
      if (source != null) entries = await source!.list(directory);
      return;
    }
    final index = player.currentIndex ?? 0;
    final position = player.position;
    await player.stop();
    await player.setAudioSources(
      queue.map((e) => AudioSource.uri(_bridge!.register(e))).toList(),
      initialIndex: index,
      initialPosition: position,
    );
    unawaited(_play());
  });
  Future<void> skip(bool next) => run(() async {
    if (next && player.hasNext) await player.seekToNext();
    if (!next && player.hasPrevious) await player.seekToPrevious();
  });
  Future<void> seek(Duration position) => run(() => player.seek(position));
  Future<void> cycleLoop() => run(
    () => player.setLoopMode(switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    }),
  );

  Future<void> shutdown() async {
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
    await _bridge?.close();
    await source?.close();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
