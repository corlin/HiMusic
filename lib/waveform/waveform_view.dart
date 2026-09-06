import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'waveform_data.dart';

class WaveformView extends StatefulWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.enabled = true,
  });
  final List<WavePeak> peaks;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final bool enabled;
  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  double? dragging;
  bool focused = false;
  double get fraction => widget.duration.inMilliseconds <= 0
      ? 0
      : (widget.position.inMilliseconds / widget.duration.inMilliseconds).clamp(
          0,
          1,
        );
  void seek(double value) {
    if (widget.enabled && widget.duration > Duration.zero) {
      widget.onSeek(
        Duration(
          milliseconds: (value.clamp(0, 1) * widget.duration.inMilliseconds)
              .round(),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.peaks, widget.peaks)) dragging = null;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '音频波形，左右方向键调整五秒',
    value: '已播放 ${(fraction * 100).round()}%',
    increasedValue:
        '已播放 ${((fraction + 5000 / max(1, widget.duration.inMilliseconds)).clamp(0, 1) * 100).round()}%',
    decreasedValue:
        '已播放 ${((fraction - 5000 / max(1, widget.duration.inMilliseconds)).clamp(0, 1) * 100).round()}%',
    onIncrease: widget.enabled
        ? () => seek(fraction + 5000 / max(1, widget.duration.inMilliseconds))
        : null,
    onDecrease: widget.enabled
        ? () => seek(fraction - 5000 / max(1, widget.duration.inMilliseconds))
        : null,
    child: Focus(
      onFocusChange: (value) => setState(() => focused = value),
      onKeyEvent: (_, event) {
        if (!widget.enabled || event is KeyUpEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          seek(
            fraction +
                (event.logicalKey == LogicalKeyboardKey.arrowRight
                        ? 5000
                        : -5000) /
                    max(1, widget.duration.inMilliseconds),
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.enabled
              ? (event) => seek(event.localPosition.dx / constraints.maxWidth)
              : null,
          onHorizontalDragUpdate: widget.enabled
              ? (event) => setState(
                  () =>
                      dragging = (event.localPosition.dx / constraints.maxWidth)
                          .clamp(0, 1),
                )
              : null,
          onHorizontalDragEnd: widget.enabled
              ? (_) {
                  if (dragging != null) seek(dragging!);
                  setState(() => dragging = null);
                }
              : null,
          onHorizontalDragCancel: () => setState(() => dragging = null),
          child: RepaintBoundary(
            child: CustomPaint(
              size: const Size(double.infinity, 64),
              painter: WaveformPainter(
                peaks: widget.peaks,
                progress: dragging ?? fraction,
                played: Theme.of(context).colorScheme.primary,
                remaining: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.22),
                focused: focused,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.played,
    required this.remaining,
    this.focused = false,
  });
  final List<WavePeak> peaks;
  final double progress;
  final Color played;
  final Color remaining;
  final bool focused;
  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || size.width < 1) return;
    final center = size.height / 2;
    final scale = center - 6;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    final bars = min(peaks.length, max(1, size.width ~/ 4));
    for (var i = 0; i < bars; i++) {
      var low = 0.0;
      var high = 0.0;
      for (
        var j = i * peaks.length ~/ bars;
        j < (i + 1) * peaks.length ~/ bars;
        j++
      ) {
        low = min(low, peaks[j].low);
        high = max(high, peaks[j].high);
      }
      final x = (i + 0.5) * size.width / bars;
      paint.color = x <= progress * size.width ? played : remaining;
      canvas.drawLine(
        Offset(x, center - high * scale),
        Offset(x, center - low * scale),
        paint,
      );
    }
    paint
      ..color = played
      ..strokeWidth = 1;
    final cursor = (progress * size.width).clamp(0.5, size.width - 0.5);
    canvas.drawLine(Offset(cursor, 3), Offset(cursor, size.height - 3), paint);
    if (focused) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter old) =>
      !identical(peaks, old.peaks) ||
      progress != old.progress ||
      played != old.played ||
      remaining != old.remaining ||
      focused != old.focused;
}
