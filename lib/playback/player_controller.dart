import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../lyrics/lyrics_controller.dart';
import '../lyrics/lyrics_document.dart';
import '../metadata/metadata_index.dart';
import '../sources/music_source.dart';
import '../sources/smb_source.dart';
import '../util/queue_math.dart';
import 'audio_bridge.dart';
import '../waveform/waveform_controller.dart';

class PlayerController extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();
  final MetadataIndex metadata;
  final LyricsController lyrics;
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
  bool shuffleEnabled = false;
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

  PlayerController({
    MetadataIndex? metadataIndex,
    LyricsController? lyricsController,
  }) : metadata = metadataIndex ?? MetadataIndex(),
       lyrics = lyricsController ?? LyricsController() {
    metadata.addListener(_changed);
    lyrics.addListener(_changed);
    _subscriptions.add(player.volumeStream.listen((_) => _changed()));
    _subscriptions.add(player.playerStateStream.listen((_) => _changed()));
    _subscriptions.add(
      player.shuffleModeEnabledStream.listen((value) {
        if (value != shuffleEnabled) {
          shuffleEnabled = value;
          _changed();
        }
      }),
    );
    _subscriptions.add(
      player.currentIndexStream.listen((_) {
        _syncWaveform();
        _syncLyrics();
        _changed();
      }),
    );
    _subscriptions.add(player.positionStream.listen(lyrics.updatePosition));
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

  void _syncLyrics() {
    final entry = current;
    final origin = source;
    if (entry == null || origin == null) {
      lyrics.clear();
    } else {
      lyrics.load(origin, entry);
    }
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
          lyrics.clear();
          metadata.cancel();
          await source?.close();
          source = next;
          committed = true;
          directory = path;
          entries = files;
          queue = [];
          _audioSources = [];
          unawaited(metadata.scan(next, files));
        } finally {
          if (!committed) await next.close();
        }
      });

  Future<void> browse(String path) => run(() async {
    final files = await source!.list(safePath(path));
    directory = safePath(path);
    entries = files;
    unawaited(metadata.scan(source!, files));
  });
  Future<void> up() => browse(
    directory.contains('/')
        ? directory.substring(0, directory.lastIndexOf('/'))
        : '',
  );

  Future<void> playEntry(MusicEntry entry) => _playQueue(
    initialIndex: queue.indexOf(entry),
    shuffle: shuffleEnabled,
  );

  /// 播放当前目录全部音频；[shuffle] 为 true 时开启随机并随机起播。
  Future<void> playAll({bool shuffle = false}) => run(() async {
    final audio = entries.where((e) => e.isAudio).toList();
    if (audio.isEmpty) return;
    await _startQueue(
      audio,
      initialIndex: shuffle ? Random().nextInt(audio.length) : 0,
      shuffle: shuffle,
    );
  });

  Future<void> _playQueue({
    required int initialIndex,
    required bool shuffle,
  }) => run(() async {
    await _startQueue(
      entries.where((e) => e.isAudio).toList(),
      initialIndex: initialIndex,
      shuffle: shuffle,
    );
  });

  Future<void> _startQueue(
    List<MusicEntry> audio, {
    required int initialIndex,
    required bool shuffle,
  }) async {
    await player.stop();
    await _bridge?.close();
    _bridge = await AudioBridge.start(source!);
    queue = audio;
    _audioSources = queue
        .map((e) => AudioSource.uri(_bridge!.register(e)))
        .toList();
    final start = audio.isEmpty
        ? 0
        : initialIndex.clamp(0, _audioSources.length - 1);
    await player.setAudioSources(_audioSources, initialIndex: start);
    shuffleEnabled = shuffle;
    await player.setShuffleModeEnabled(shuffle);
    _syncWaveform();
    _syncLyrics();
    unawaited(_play());
  }

  /// 跳到队列指定位置并开始播放。
  Future<void> playAt(int index) => run(() async {
    if (index < 0 || index >= queue.length) return;
    await player.seek(Duration.zero, index: index);
    _syncWaveform();
    _syncLyrics();
    unawaited(_play());
  });

  /// 从队列移除一条；若移除的是当前曲目，则顺延播放原下一首。
  Future<void> removeFromQueue(int index) => run(() async {
    if (index < 0 || index >= queue.length) return;
    final currentIndex = player.currentIndex;
    final wasPlaying = player.playing;
    final position = player.position;
    final keepPosition = currentIndex != null && currentIndex < index;
    queue.removeAt(index);
    _audioSources.removeAt(index);
    if (_audioSources.isEmpty) {
      await player.stop();
      return;
    }
    final newCurrent = mapIndexAfterRemoval(index, currentIndex);
    await player.setAudioSources(
      _audioSources,
      initialIndex: newCurrent ?? 0,
      initialPosition: keepPosition ? position : Duration.zero,
    );
    if (wasPlaying && newCurrent != null) unawaited(_play());
  });

  /// 切换随机播放：仅改变播放模式，不中断当前曲目。
  Future<void> toggleShuffle() => run(() async {
    final next = !shuffleEnabled;
    shuffleEnabled = next;
    _changed();
    try {
      await player.setShuffleModeEnabled(next);
    } catch (_) {
      // 个别后端不支持时保持状态，播放器按当前顺序播放。
    }
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
  Future<void> seekToLyric(TimedLyricLine line) => seek(line.timestamp);
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
    lyrics.removeListener(_changed);
    lyrics.dispose();
    metadata.cancel();
    metadata.removeListener(_changed);
    metadata.dispose();
    await _bridge?.close();
    await source?.close();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
