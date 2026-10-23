import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// A hexagon on the map, named by its axial column and row.
class HexId {
  final int q;
  final int r;
  const HexId(this.q, this.r);

  @override
  bool operator ==(Object o) => o is HexId && o.q == q && o.r == r;
  @override
  int get hashCode => Object.hash(q, r);
  @override
  String toString() => 'Hex($q,$r)';

  /// The six hexagons touching this one.
  List<HexId> get neighbours => [
        HexId(q + 1, r), HexId(q - 1, r), HexId(q, r + 1),
        HexId(q, r - 1), HexId(q + 1, r - 1), HexId(q - 1, r + 1),
      ];
}

/// Pointy-top hexagons tiled over KwaZulu-Natal. Latitude and longitude are
/// squashed to roughly equal distances first, so the cells look regular on the
/// map instead of stretched.
class HexGrid {
  /// Distance from a hexagon's centre to a corner, in degrees of latitude.
  /// 0.05 is about 5.5 km, so a cell is roughly 10 km across.
  final double size;
  final double _squash;

  HexGrid({this.size = 0.05, double referenceLat = -29.0})
      : _squash = math.cos(referenceLat * math.pi / 180);

  (double, double) _project(LatLng p) => (p.longitude * _squash, p.latitude);
  LatLng _unproject(double x, double y) => LatLng(y, x / _squash);

  HexId cellOf(LatLng p) {
    final (x, y) = _project(p);
    final q = (math.sqrt(3) / 3 * x - y / 3) / size;
    final r = (2 / 3 * y) / size;
    return _round(q, r);
  }

  // Cube rounding: snap fractional axial coordinates to the nearest hexagon.
  HexId _round(double q, double r) {
    final s = -q - r;
    var rq = q.roundToDouble();
    var rr = r.roundToDouble();
    final rs = s.roundToDouble();
    final dq = (rq - q).abs(), dr = (rr - r).abs(), ds = (rs - s).abs();
    if (dq > dr && dq > ds) {
      rq = -rr - rs;
    } else if (dr > ds) {
      rr = -rq - rs;
    }
    return HexId(rq.toInt(), rr.toInt());
  }

  LatLng centerOf(HexId h) =>
      _unproject(size * math.sqrt(3) * (h.q + h.r / 2), size * 1.5 * h.r);

  List<LatLng> cornersOf(HexId h) {
    final cx = size * math.sqrt(3) * (h.q + h.r / 2);
    final cy = size * 1.5 * h.r;
    return [
      for (var i = 0; i < 6; i++)
        _unproject(cx + size * math.cos(math.pi / 180 * (60 * i - 30)),
            cy + size * math.sin(math.pi / 180 * (60 * i - 30)))
    ];
  }
}
