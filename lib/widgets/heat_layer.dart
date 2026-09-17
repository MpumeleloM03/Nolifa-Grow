import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/outbreak_report.dart';

/// Density overlay for disease reports.
///
/// Each sighting is painted as a soft radial blob and the blobs are composited
/// additively, so a cluster of reports in one valley burns brighter than a
/// single isolated case. That is the signal a farmer actually needs: not where
/// one plant was sick, but where something is spreading.
class HeatLayer extends StatelessWidget {
  final List<OutbreakReport> reports;

  /// Blob radius in metres, so the heat keeps its real-world size as you zoom.
  final double radiusMeters;

  const HeatLayer({
    super.key,
    required this.reports,
    this.radiusMeters = 62000,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (reports.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _HeatPainter(reports: reports, camera: camera, radiusMeters: radiusMeters),
      ),
    );
  }
}

class _HeatPainter extends CustomPainter {
  final List<OutbreakReport> reports;
  final MapCamera camera;
  final double radiusMeters;

  _HeatPainter({
    required this.reports,
    required this.camera,
    required this.radiusMeters,
  });

  /// Metres-per-pixel at the current zoom, corrected for latitude.
  double _pixelRadius() {
    const earthCircumference = 40075016.686;
    final latRad = camera.center.latitude * math.pi / 180;
    final metersPerPixel =
        earthCircumference * math.cos(latRad) / math.pow(2, camera.zoom + 8);
    return (radiusMeters / metersPerPixel).clamp(46.0, 460.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final radius = _pixelRadius();
    final bounds = Offset.zero & size;

    // Additive compositing needs its own layer, otherwise the blend reads
    // against the map tiles instead of against the other blobs.
    canvas.saveLayer(bounds, Paint());

    for (final r in reports) {
      final p = camera.latLngToScreenPoint(r.location);
      final center = Offset(p.x, p.y);

      // Skip anything well outside the viewport.
      if (center.dx < -radius ||
          center.dy < -radius ||
          center.dx > size.width + radius ||
          center.dy > size.height + radius) {
        continue;
      }

      final weight = r.weight;
      final core = _colorFor(r.severity).withValues(alpha: 0.42 * weight);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [core, core.withValues(alpha: 0)],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    canvas.restore();
  }

  static Color _colorFor(String severity) => switch (severity) {
        'red' => const Color(0xFFFF3B30),
        'orange' => const Color(0xFFFF9F0A),
        _ => const Color(0xFF34C759),
      };

  @override
  bool shouldRepaint(_HeatPainter old) =>
      old.reports != reports ||
      old.camera.zoom != camera.zoom ||
      old.camera.center != camera.center;
}
