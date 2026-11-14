import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

/// Wavy timeline (Settings → Appearance → Wavy timeline).
///
/// A drop-in for the straight progress bar the dock normally uses, with the same
/// contract: the played span is solid, buffered sits faintly behind it, a
/// thumb marks the position, and tap/drag both seek. The only difference is
/// that the track is a slow sine instead of a straight line — same 2.6px
/// stroke weight, so the timeline keeps its weight in the dock.
///
/// Static by design: the wave is a shape, not an animation, so it costs no
/// frames and has nothing to unwind under reduce motion.
class WaveTimeline extends StatelessWidget {
  const WaveTimeline({
    super.key,
    required this.progress,
    required this.buffered,
    required this.total,
    required this.showThumb,
    required this.onSeek,
    required this.baseColor,
    required this.bufferedColor,
    required this.progressColor,
    required this.thumbColor,
    required this.thumbGlowColor,
    this.verticalOffset = 0,
  });

  final Duration progress;
  final Duration buffered;
  final Duration total;

  /// False until the player knows a length: no thumb on a bar with nothing
  /// to scrub.
  final bool showThumb;
  final ValueChanged<Duration>? onSeek;
  final Color baseColor;
  final Color bufferedColor;
  final Color progressColor;
  final Color thumbColor;
  final Color thumbGlowColor;

  /// Small per-use vertical adjustment for tight progress tracks.
  final double verticalOffset;

  double _ratio(Duration d) {
    final ms = total.inMilliseconds;
    if (ms <= 0) return 0;
    return (d.inMilliseconds / ms).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seekAt(double dx) {
          if (onSeek == null || total.inMilliseconds <= 0 || width <= 0) {
            return;
          }
          final ratio = (dx / width).clamp(0.0, 1.0);
          onSeek!(Duration(
            milliseconds: (ratio * total.inMilliseconds).round(),
          ));
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seekAt(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
            child: SizedBox(
              height: 12,
              width: width,
              child: CustomPaint(
                painter: _WaveTimelinePainter(
                  progress: _ratio(progress),
                  buffered: _ratio(buffered),
                  showThumb: showThumb,
                  baseColor: baseColor,
                  bufferedColor: bufferedColor,
                  progressColor: progressColor,
                  thumbColor: thumbColor,
                  thumbGlowColor: thumbGlowColor,
                  verticalOffset: verticalOffset,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveTimelinePainter extends CustomPainter {
  const _WaveTimelinePainter({
    required this.progress,
    required this.buffered,
    required this.showThumb,
    required this.baseColor,
    required this.bufferedColor,
    required this.progressColor,
    required this.thumbColor,
    required this.thumbGlowColor,
    required this.verticalOffset,
  });

  final double progress;
  final double buffered;
  final bool showThumb;
  final Color baseColor;
  final Color bufferedColor;
  final Color progressColor;
  final Color thumbColor;
  final Color thumbGlowColor;
  final double verticalOffset;

  static const _amplitude = 2.2;
  static const _wavelength = 26.0;
  static const _stroke = 2.6;
  static const _thumbRadius = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final mid = size.height / 2 + verticalOffset;
    final path = _wavePath(size.width, mid);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawPath(path, paint..color = baseColor);

    final bufferedWidth = size.width * buffered;
    if (bufferedWidth > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, bufferedWidth, size.height));
      canvas.drawPath(path, paint..color = bufferedColor);
      canvas.restore();
    }

    final progressWidth = size.width * progress;
    if (progressWidth > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, progressWidth, size.height));
      canvas.drawPath(path, paint..color = progressColor);
      canvas.restore();
    }

    if (!showThumb) return;
    final thumbY = mid +
        math.sin(progressWidth / _wavelength * 2 * math.pi) * _amplitude;
    final thumb = Offset(
      progressWidth.clamp(_thumbRadius, size.width - _thumbRadius),
      thumbY,
    );
    canvas.drawCircle(thumb, 8, Paint()..color = thumbGlowColor);
    canvas.drawCircle(thumb, _thumbRadius, Paint()..color = thumbColor);
  }

  Path _wavePath(double width, double mid) {
    final path = Path()..moveTo(0, mid);
    for (double x = 1; x <= width; x += 1) {
      path.lineTo(
        x,
        mid + math.sin(x / _wavelength * 2 * math.pi) * _amplitude,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _WaveTimelinePainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.showThumb != showThumb ||
      old.baseColor != baseColor ||
      old.bufferedColor != bufferedColor ||
      old.progressColor != progressColor ||
      old.thumbColor != thumbColor ||
      old.thumbGlowColor != thumbGlowColor ||
      old.verticalOffset != verticalOffset;
}
