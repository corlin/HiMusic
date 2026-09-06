import 'package:flutter/material.dart';

import 'player_controller.dart';

class VolumeControls extends StatelessWidget {
  const VolumeControls({super.key, required this.controller});
  final PlayerController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: controller.volume == 0 ? '取消静音' : '静音',
              onPressed: controller.toggleMute,
              icon: Icon(
                controller.volume == 0 ? Icons.volume_off : Icons.volume_up,
              ),
            ),
            Expanded(
              child: Slider(
                semanticFormatterCallback: (v) => '音量 ${(v * 100).round()}%',
                value: controller.volume.clamp(0, 1),
                divisions: 100,
                onChanged: controller.setVolume,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text('${(controller.volume * 100).round()}%'),
            ),
          ],
        ),
        if (controller.volumeError != null)
          Text(
            controller.volumeError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
