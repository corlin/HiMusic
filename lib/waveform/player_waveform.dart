import 'dart:async';

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
  static const windows = [5, 15, 30, 60];
  int zoomIndex = 1;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.waveform,
    builder: (context, _) {
      final wave = widget.controller.waveform;
      if (wave.peaks.isEmpty) {
        return SizedBox(
          height: 126,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
              ],
            ),
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
                '${windows[zoomIndex]} 秒',
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
              window: Duration(seconds: windows[zoomIndex]),
            ),
          ),
        ],
      );
    },
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
