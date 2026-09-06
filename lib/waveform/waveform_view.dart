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
    required this.window,
    required this.onSeek,
    this.enabled = true,
  });

  final List<WavePeak> peaks;
  final Duration position;
  final Duration duration;
  final Duration window;
  final ValueChanged<Duration> onSeek;
  final bool enabled;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  static const overviewTop = 96.0;
  static const totalHeight = 126.0;

  late WaveformPyramid pyramid;
  Duration? dragging;
  bool focused = false;

  @override
  void initState() {
    super.initState();
    pyramid = WaveformPyramid(widget.peaks);
  }

  @override
  void didUpdateWidget(covariant WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.peaks, widget.peaks)) {
      pyramid = WaveformPyramid(widget.peaks);
      dragging = null;
    }
  }

  double get fraction => widget.duration.inMicroseconds <= 0
      ? 0
      : (widget.position.inMicroseconds / widget.duration.inMicroseconds).clamp(
          0,
          1,
        );

  Duration get visibleWindow =>
      widget.duration <= widget.window ? widget.duration : widget.window;

  Duration get visibleStart {
    final duration = widget.duration.inMicroseconds;
    final window = visibleWindow.inMicroseconds;
    if (duration <= window || window <= 0) return Duration.zero;
    final center = (dragging ?? widget.position).inMicroseconds;
    return Duration(
      microseconds: (center - window ~/ 2).clamp(0, duration - window),
    );
  }

  Duration positionAt(Offset point, double width) {
    if (widget.duration <= Duration.zero || width <= 0) return Duration.zero;
    final x = (point.dx / width).clamp(0.0, 1.0);
    if (point.dy >= overviewTop) return widget.duration * x;
    return visibleStart + visibleWindow * x;
  }

  void seek(Duration value) {
    if (!widget.enabled || widget.duration <= Duration.zero) return;
    widget.onSeek(
      Duration(
        microseconds: value.inMicroseconds.clamp(
          0,
          widget.duration.inMicroseconds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '动态音频波形，细节视图 ${visibleWindow.inSeconds} 秒，底部为整曲概览',
    value: '已播放 ${(fraction * 100).round()}%',
    increasedValue:
        '已播放 ${((fraction + 5000 / max(1, widget.duration.inMilliseconds)).clamp(0, 1) * 100).round()}%',
    decreasedValue:
        '已播放 ${((fraction - 5000 / max(1, widget.duration.inMilliseconds)).clamp(0, 1) * 100).round()}%',
    onIncrease: widget.enabled
        ? () => seek(widget.position + const Duration(seconds: 5))
        : null,
    onDecrease: widget.enabled
        ? () => seek(widget.position - const Duration(seconds: 5))
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
            widget.position +
                (event.logicalKey == LogicalKeyboardKey.arrowRight
                    ? const Duration(seconds: 5)
                    : const Duration(seconds: -5)),
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.enabled
              ? (event) =>
                    seek(positionAt(event.localPosition, constraints.maxWidth))
              : null,
          onHorizontalDragUpdate: widget.enabled
              ? (event) => setState(
                  () => dragging = positionAt(
                    event.localPosition,
                    constraints.maxWidth,
                  ),
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
              size: const Size(double.infinity, totalHeight),
              painter: DynamicWaveformPainter(
                pyramid: pyramid,
                position: dragging ?? widget.position,
                duration: widget.duration,
                visibleStart: visibleStart,
                visibleWindow: visibleWindow,
                played: Theme.of(context).colorScheme.primary,
                remaining: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.25),
                focused: focused,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class DynamicWaveformPainter extends CustomPainter {
  const DynamicWaveformPainter({
    required this.pyramid,
    required this.position,
    required this.duration,
    required this.visibleStart,
    required this.visibleWindow,
    required this.played,
    required this.remaining,
    required this.focused,
  });

  final WaveformPyramid pyramid;
  final Duration position;
  final Duration duration;
  final Duration visibleStart;
  final Duration visibleWindow;
  final Color played;
  final Color remaining;
  final bool focused;

  double fraction(Duration value) => duration.inMicroseconds <= 0
      ? 0
      : (value.inMicroseconds / duration.inMicroseconds).clamp(0, 1);

  @override
  void paint(Canvas canvas, Size size) {
    if (pyramid.length == 0 || size.width < 1 || duration <= Duration.zero) {
      return;
    }
    final detail = Rect.fromLTWH(0, 0, size.width, 88);
    final overview = Rect.fromLTWH(0, 96, size.width, 30);
    _drawGrid(canvas, detail);
    final detailStart = (fraction(visibleStart) * pyramid.length).floor();
    final detailEnd = (fraction(visibleStart + visibleWindow) * pyramid.length)
        .ceil();
    final detailSlice = pyramid.query(
      detailStart,
      detailEnd,
      targetPoints: max(1, (size.width / 2).round()),
    );
    final detailPlayhead = visibleWindow.inMicroseconds <= 0
        ? 0.0
        : ((position - visibleStart).inMicroseconds /
                  visibleWindow.inMicroseconds)
              .clamp(0.0, 1.0);
    _drawEnvelope(canvas, detail, detailSlice.peaks, detailPlayhead);

    final overviewSlice = pyramid.query(
      0,
      pyramid.length,
      targetPoints: max(1, (size.width / 3).round()),
    );
    _drawEnvelope(canvas, overview, overviewSlice.peaks, fraction(position));
    final viewport = Rect.fromLTRB(
      overview.left + fraction(visibleStart) * overview.width,
      overview.top,
      overview.left + fraction(visibleStart + visibleWindow) * overview.width,
      overview.bottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(viewport, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = played.withValues(alpha: 0.8),
    );
    if (focused) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = played,
      );
    }
  }

  void _drawGrid(Canvas canvas, Rect rect) {
    final seconds = max(1, visibleWindow.inSeconds);
    final interval = seconds <= 8
        ? 1
        : seconds <= 20
        ? 2
        : seconds <= 40
        ? 5
        : 10;
    final first = (visibleStart.inMilliseconds / 1000 / interval).ceil();
    final last =
        ((visibleStart + visibleWindow).inMilliseconds / 1000 / interval)
            .floor();
    final paint = Paint()
      ..strokeWidth = 1
      ..color = remaining.withValues(alpha: 0.28);
    for (var tick = first; tick <= last; tick++) {
      final time = Duration(seconds: tick * interval);
      final x =
          rect.left +
          (time - visibleStart).inMicroseconds /
              max(1, visibleWindow.inMicroseconds) *
              rect.width;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      paint,
    );
  }

  void _drawEnvelope(
    Canvas canvas,
    Rect rect,
    List<WavePeak> peaks,
    double playedFraction,
  ) {
    if (peaks.isEmpty) return;
    final envelope = Path();
    final amplitude = rect.height / 2 - 3;
    for (var index = 0; index < peaks.length; index++) {
      final x = peaks.length == 1
          ? rect.center.dx
          : rect.left + index * rect.width / (peaks.length - 1);
      final y = rect.center.dy - _display(peaks[index].high) * amplitude;
      index == 0 ? envelope.moveTo(x, y) : envelope.lineTo(x, y);
    }
    for (var index = peaks.length - 1; index >= 0; index--) {
      final x = peaks.length == 1
          ? rect.center.dx
          : rect.left + index * rect.width / (peaks.length - 1);
      envelope.lineTo(
        x,
        rect.center.dy - _display(peaks[index].low) * amplitude,
      );
    }
    envelope.close();
    canvas.drawPath(
      envelope,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [remaining.withValues(alpha: 0.75), remaining],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        rect.left,
        rect.top,
        rect.left + playedFraction * rect.width,
        rect.bottom,
      ),
    );
    canvas.drawPath(
      envelope,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [played.withValues(alpha: 0.72), played],
        ).createShader(rect),
    );
    canvas.restore();
    final playheadX = (rect.left + playedFraction * rect.width).clamp(
      rect.left,
      rect.right,
    );
    canvas.drawLine(
      Offset(playheadX, rect.top + 1),
      Offset(playheadX, rect.bottom - 1),
      Paint()
        ..strokeWidth = rect.height > 40 ? 2 : 1
        ..color = played,
    );
  }

  double _display(double value) =>
      value.sign * pow(value.abs(), 0.65).toDouble();

  @override
  bool shouldRepaint(covariant DynamicWaveformPainter old) =>
      !identical(pyramid, old.pyramid) ||
      position != old.position ||
      duration != old.duration ||
      visibleStart != old.visibleStart ||
      visibleWindow != old.visibleWindow ||
      played != old.played ||
      remaining != old.remaining ||
      focused != old.focused;
}
