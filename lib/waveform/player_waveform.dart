import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';

import '../playback/player_controller.dart';
import 'waveform_data.dart';
import 'waveform_view.dart';

class PlayerWaveform extends StatefulWidget {
  const PlayerWaveform({super.key, required this.controller});
  final PlayerController controller;

  @override
  State<PlayerWaveform> createState() => _PlayerWaveformState();
}

class _PlayerWaveformState extends State<PlayerWaveform> {
  static const windows = [5, 10, 30, 60, 120, 0];
  int zoomIndex = 1;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.waveform,
    builder: (context, _) {
      final wave = widget.controller.waveform;
      if (wave.peaks.isEmpty) {
        return SizedBox(
          height: 126,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (wave.progress != null)
                SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(value: wave.progress),
                ),
              const SizedBox(height: 6),
              Text(
                wave.message ?? '准备高解析音频波形…',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              _CompactSeekBar(controller: widget.controller),
            ],
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, size: 16, color: Colors.white60),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '动态波形',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
              IconButton(
                key: const Key('waveform-zoom-out'),
                tooltip: '缩小波形',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: zoomIndex < windows.length - 1
                    ? () => setState(() => zoomIndex++)
                    : null,
                icon: const Icon(Icons.remove, size: 18),
              ),
              Text(
                windows[zoomIndex] == 0 ? '整曲' : '${windows[zoomIndex]} 秒',
                key: const Key('waveform-window-label'),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                key: const Key('waveform-zoom-in'),
                tooltip: '放大波形',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: zoomIndex > 0
                    ? () => setState(() => zoomIndex--)
                    : null,
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
          StreamBuilder<Duration?>(
            stream: widget.controller.player.durationStream,
            initialData: widget.controller.player.duration,
            builder: (context, duration) => _SmoothWaveform(
              controller: widget.controller,
              peaks: wave.peaks,
              duration: duration.data ?? Duration.zero,
              window: windows[zoomIndex] == 0
                  ? duration.data ?? Duration.zero
                  : Duration(seconds: windows[zoomIndex]),
            ),
          ),
        ],
      );
    },
  );
}

class _CompactSeekBar extends StatefulWidget {
  const _CompactSeekBar({required this.controller});
  final PlayerController controller;

  @override
  State<_CompactSeekBar> createState() => _CompactSeekBarState();
}

class _CompactSeekBarState extends State<_CompactSeekBar> {
  double? pending;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration?>(
    stream: widget.controller.player.durationStream,
    initialData: widget.controller.player.duration,
    builder: (context, duration) => StreamBuilder<Duration>(
      stream: widget.controller.player.positionStream,
      initialData: widget.controller.player.position,
      builder: (context, position) {
        final total = duration.data ?? Duration.zero;
        final maximum = max(1, total.inMilliseconds).toDouble();
        final value = pending ?? position.data?.inMilliseconds.toDouble() ?? 0;
        return Slider(
          value: value.clamp(0, maximum),
          max: maximum,
          onChanged: widget.controller.busy || total <= Duration.zero
              ? null
              : (next) => setState(() => pending = next),
          onChangeEnd: (next) async {
            await widget.controller.seek(Duration(milliseconds: next.round()));
            if (mounted) setState(() => pending = null);
          },
        );
      },
    ),
  );
}

class _SmoothWaveform extends StatefulWidget {
  const _SmoothWaveform({
    required this.controller,
    required this.peaks,
    required this.duration,
    required this.window,
  });

  final PlayerController controller;
  final List<WavePeak> peaks;
  final Duration duration;
  final Duration window;

  @override
  State<_SmoothWaveform> createState() => _SmoothWaveformState();
}

class _SmoothWaveformState extends State<_SmoothWaveform>
    with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  late final StreamSubscription<PlayerState> playerStateSubscription;
  Duration position = Duration.zero;

  @override
  void initState() {
    super.initState();
    position = widget.controller.player.position;
    ticker = createTicker((_) {
      if (mounted) setState(() => position = widget.controller.player.position);
    });
    playerStateSubscription = widget.controller.player.playerStateStream.listen(
      (state) {
        if (!mounted) return;
        setState(() => position = widget.controller.player.position);
        if (state.playing && state.processingState == ProcessingState.ready) {
          if (!ticker.isActive) ticker.start();
        } else {
          ticker.stop();
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant _SmoothWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.peaks, widget.peaks)) {
      position = widget.controller.player.position;
    }
  }

  @override
  void dispose() {
    ticker.dispose();
    playerStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      WaveformView(
        peaks: widget.peaks,
        position: position,
        duration: widget.duration,
        window: widget.window,
        enabled: !widget.controller.busy,
        onSeek: widget.controller.seek,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_time(position), style: const TextStyle(fontSize: 11)),
          Text(_time(widget.duration), style: const TextStyle(fontSize: 11)),
        ],
      ),
    ],
  );

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
