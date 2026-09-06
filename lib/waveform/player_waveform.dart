import 'package:flutter/material.dart';

import '../playback/player_controller.dart';
import 'waveform_view.dart';

class PlayerWaveform extends StatelessWidget {
  const PlayerWaveform({super.key, required this.controller});
  final PlayerController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.waveform,
    builder: (context, _) {
      final wave = controller.waveform;
      if (wave.peaks.isEmpty) {
        return SizedBox(
          height: 64,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (wave.progress != null)
                  SizedBox(
                    width: 140,
                    child: LinearProgressIndicator(value: wave.progress),
                  ),
                Text(
                  wave.message ?? '准备音频波形…',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
        );
      }
      return StreamBuilder<Duration?>(
        stream: controller.player.durationStream,
        initialData: controller.player.duration,
        builder: (context, duration) => StreamBuilder<Duration>(
          stream: controller.player.positionStream,
          initialData: controller.player.position,
          builder: (context, position) => WaveformView(
            peaks: wave.peaks,
            position: position.data ?? Duration.zero,
            duration: duration.data ?? Duration.zero,
            enabled: !controller.busy,
            onSeek: controller.seek,
          ),
        ),
      );
    },
  );
}
