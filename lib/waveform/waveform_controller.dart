import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';

import '../sources/music_source.dart';
import 'waveform_data.dart';

typedef WaveExtractor = Future<List<WavePeak>> Function(
  File audio,
  File output,
);

Future<List<WavePeak>> extractWaveform(File audio, File output) async {
  await for (final progress in JustWaveform.extract(
    audioInFile: audio,
    waveOutFile: output,
    zoom: const WaveformZoom.pixelsPerSecond(20),
  )) {
    if (progress.progress >= 1) {
      return parseWaveform(await output.readAsBytes());
    }
  }
  throw const FormatException('No waveform data');
}

class WaveformController extends ChangeNotifier {
  WaveformController({
    WaveExtractor? extract,
    bool? supported,
    Future<Directory> Function()? temporaryDirectory,
    bool Function()? playbackReady,
  }) : _extract = extract ?? extractWaveform,
       _supported =
           supported ??
           (Platform.isAndroid || Platform.isIOS || Platform.isMacOS),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _playbackReady = playbackReady ?? (() => true);
  static const maxFileSize = 256 * 1024 * 1024;
  final WaveExtractor _extract;
  final bool _supported;
  final Future<Directory> Function() _temporaryDirectory;
  final bool Function() _playbackReady;
  List<WavePeak> peaks = [];
  String? message;
  double? progress;
  int _generation = 0;
  bool _closed = false;
  ({MusicSource source, MusicEntry entry, int generation})? _pending;
  Future<void>? _worker;
  Future<dynamic>? _read;
  MusicSource? _source;
  String? _key;
  final Map<String, List<WavePeak>> _cache = {};

  void _emit() {
    if (!_closed) notifyListeners();
  }

  bool _active(int generation) => !_closed && generation == _generation;

  void show(MusicSource source, MusicEntry entry) {
    if (_closed) return;
    final key =
        '${entry.path}\u0000${entry.size}\u0000${entry.modified?.microsecondsSinceEpoch}';
    if (identical(source, _source) && key == _key) return;
    if (!identical(source, _source)) _cache.clear();
    _source = source;
    _key = key;
    _generation++;
    _pending = null;
    peaks = [];
    progress = null;
    if (!_supported) {
      message = '此平台暂不支持波形';
      _emit();
      return;
    }
    if (entry.size <= 0 || entry.size > maxFileSize) {
      message = '文件较大，已跳过波形分析';
      _emit();
      return;
    }
    final cached = entry.modified == null ? null : _cache[key];
    if (cached != null) {
      peaks = cached;
      message = null;
      _emit();
      return;
    }
    message = '准备音频波形…';
    progress = 0;
    _pending = (source: source, entry: entry, generation: _generation);
    _emit();
    _worker ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null && !_closed) {
        final job = _pending!;
        _pending = null;
        Directory? work;
        try {
          final root = await _temporaryDirectory();
          if (!_active(job.generation)) continue;
          await root.create(recursive: true);
          if (!_active(job.generation)) continue;
          work = await root.createTemp('himusic-wave-');
          final audio = File('${work.path}/audio.${job.entry.extension}');
          final handle = await audio.open(mode: FileMode.write);
          try {
            for (
              var offset = 0;
              offset < job.entry.size && _active(job.generation);
            ) {
              while (!_playbackReady() && _active(job.generation)) {
                await Future<void>.delayed(const Duration(milliseconds: 200));
              }
              if (!_active(job.generation)) break;
              final size = min(128 * 1024, job.entry.size - offset);
              final read = job.source
                  .read(job.entry.path, offset, size)
                  .timeout(const Duration(seconds: 25));
              _read = read;
              final bytes = await read;
              if (!_active(job.generation)) break;
              if (bytes.isEmpty || bytes.length > size) {
                throw const FileSystemException('Incomplete audio');
              }
              await handle.writeFrom(bytes);
              offset += bytes.length;
              progress = offset / job.entry.size;
              message = '准备波形 ${(progress! * 100).round()}%';
              _emit();
              // Yield between bounded reads so the playback stream gets service.
              await Future<void>.delayed(const Duration(milliseconds: 8));
            }
          } finally {
            await handle.close();
          }
          if (!_active(job.generation)) continue;
          message = '分析音频波形…';
          progress = null;
          _emit();
          // Native extraction has no cancellation API. Keep only one decode in
          // flight and discard stale results before processing the latest track.
          final result = await _extract(audio, File('${work.path}/audio.wave'));
          if (!_active(job.generation)) continue;
          peaks = result;
          message = null;
          if (job.entry.modified != null) {
            if (_cache.length >= 8) _cache.remove(_cache.keys.first);
            _cache[_key!] = result;
          }
          _emit();
        } catch (_) {
          if (_active(job.generation)) {
            message = '暂时无法生成波形，音乐仍可正常播放';
            progress = null;
            _emit();
          }
        } finally {
          if (work != null) {
            try {
              await work.delete(recursive: true);
            } catch (_) {}
          }
        }
      }
    } finally {
      _worker = null;
    }
  }

  /// Stop further reads before the owner closes/replaces an SMB connection.
  Future<void> reset() async {
    _generation++;
    _pending = null;
    _source = null;
    _key = null;
    _cache.clear();
    peaks = [];
    message = null;
    progress = null;
    _emit();
    try {
      await _read;
    } catch (_) {}
  }

  Future<void> close() async {
    _closed = true;
    await reset();
    // Native extraction owns its temporary files until it finishes.
    // It must not hold up playback or source teardown.
    super.dispose();
  }
}
