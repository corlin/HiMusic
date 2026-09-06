import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../sources/music_source.dart';
import '../sources/smb_source.dart';
import 'audio_bridge.dart';
import '../waveform/waveform_controller.dart';

class PlayerController extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();
  late final WaveformController waveform = WaveformController(
    playbackReady: () =>
        player.processingState != ProcessingState.loading &&
        player.processingState != ProcessingState.buffering,
  );
  void _syncWaveform() {
    final entry = current;
    final origin = source;
    if (entry != null && origin != null) waveform.show(origin, entry);
  }

  MusicSource? source;
  AudioBridge? _bridge;
  String directory = '';
  List<MusicEntry> entries = [];
  List<MusicEntry> queue = [];
  String? error;
  bool busy = false;
  bool _disposed = false;
  bool _wantsPlayback = false;
  double? _pendingVolume;
  double _lastAudibleVolume = 1;
  Future<void>? _volumeWork;
  String? volumeError;
  double get volume => _pendingVolume ?? player.volume;
  Future<void> Function()? _retryAction;
  Completer<void>? _operation;
  Future<void>? _shutdownFuture;
  List<AudioSource> _audioSources = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PlayerController() {
    _subscriptions.add(player.volumeStream.listen((_) => _changed()));
    _subscriptions.add(player.playerStateStream.listen((_) => _changed()));
    _subscriptions.add(
      player.currentIndexStream.listen((_) {
        _syncWaveform();
        _changed();
      }),
    );
    _subscriptions.add(
      player.errorStream.listen((_) {
        error = '播放中断，请检查网络或文件格式，然后按重试。';
        _retryAction = _reloadPlayback;
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
    if (busy || _disposed) return;
    _operation = Completer<void>();
    busy = true;
    error = null;
    _retryAction = null;
    _changed();
    try {
      await action();
    } catch (e) {
      error = sourceError(e);
      _retryAction = action;
    } finally {
      _operation?.complete();
      busy = false;
      _changed();
    }
  }

  Future<void> connect(Future<MusicSource> Function() factory, String root) =>
      run(() async {
        final next = await factory();
        var committed = false;
        try {
          final path = safePath(root);
          final files = await next.list(path);
          if (_disposed) return;
          _wantsPlayback = false;
          await player.stop();
          await _bridge?.close();
          _bridge = null;
          await waveform.reset();
          await source?.close();
          source = next;
          committed = true;
          directory = path;
          entries = files;
          queue = [];
          _audioSources = [];
        } finally {
          if (!committed) await next.close();
        }
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
    _audioSources = queue
        .map((e) => AudioSource.uri(_bridge!.register(e)))
        .toList();
    await player.setAudioSources(
      _audioSources,
      initialIndex: queue.indexOf(entry),
    );
    _syncWaveform();
    unawaited(_play());
  });
  Future<void> _play() async {
    if (_disposed) return;
    _wantsPlayback = true;
    try {
      await player.play();
    } catch (_) {
      error = '无法播放，请检查网络或音频格式，然后重试。';
      _retryAction = _reloadPlayback;
      _changed();
    }
  }

  Future<void> toggle() => run(() async {
    if (player.playing) {
      _wantsPlayback = false;
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero, index: 0);
      }
      unawaited(_play());
    }
  });
  Future<void> retry() async {
    final action = _retryAction;
    if (action != null) await run(action);
  }

  Future<void> _reloadPlayback() async {
    if (_audioSources.isEmpty) return;
    final resume = _wantsPlayback;
    final index = player.currentIndex ?? 0;
    final position = player.position;
    await player.stop();
    await player.setAudioSources(
      _audioSources,
      initialIndex: index,
      initialPosition: position,
    );
    if (resume) unawaited(_play());
  }

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

  Future<void> setVolume(double value) {
    if (_disposed || !value.isFinite) return Future.value();
    _pendingVolume = value.clamp(0.0, 1.0);
    if (_pendingVolume! > 0) _lastAudibleVolume = _pendingVolume!;
    volumeError = null;
    _changed();
    return _volumeWork ??= _drainVolume();
  }

  Future<void> _drainVolume() async {
    try {
      while (_pendingVolume != null) {
        final target = _pendingVolume!;
        await player.setVolume(target);
        if (_pendingVolume == target) _pendingVolume = null;
      }
    } catch (_) {
      _pendingVolume = null;
      volumeError = '音量调整失败，请重试。';
    } finally {
      _volumeWork = null;
      _changed();
    }
  }

  Future<void> toggleMute() => setVolume(volume > 0 ? 0 : _lastAudibleVolume);

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _disposed = true;
    _retryAction = null;
    if (busy) await _operation?.future;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _volumeWork;
    await player.dispose();
    await waveform.close();
    await _bridge?.close();
    await source?.close();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
