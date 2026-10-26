import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
Future<LatLng> _geocode(String text) async {
  final known = lookupPlace(text);
  try {
    final c = HttpClient()..userAgent = 'NolifaDrop/1.0';
    final q = Uri.encodeQueryComponent('$text, KwaZulu-Natal, South Africa');
    final req = await c.getUrl(Uri.parse('https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=1')).timeout(const Duration(seconds: 5));
    final res = await req.close().timeout(const Duration(seconds: 5));
    final list = jsonDecode(await res.transform(utf8.decoder).join()) as List;
    if (list.isNotEmpty) return LatLng(double.parse(list.first['lat'] as String), double.parse(list.first['lon'] as String));
  } catch (e) {
    debugPrint('tracking: geocode fell back for "$text": $e');
  }
  final k = known ?? durbanCentre;
  return LatLng(k.$1, k.$2);
}

Future<List<LatLng>> _route(List<LatLng> pts) async {
  try {
    final coords = pts.map((p) => '${p.longitude},${p.latitude}').join(';');
    final c = HttpClient();
    final req = await c.getUrl(Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson')).timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 6));
    final r = (jsonDecode(await res.transform(utf8.decoder).join())['routes'] as List).first;
    return [for (final p in r['geometry']['coordinates'] as List) LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())];
  } catch (e) {
    debugPrint('tracking: straight line: $e');
    return pts;
  }
}

/// The customer's live map: the real road route from the farm to their door,
/// with the driver's scooter driving along it as the order moves on. In the
/// prototype the movement is simulated along the real route; live GPS needs
/// the shared backend.
class TrackingMap extends StatefulWidget {
  final Order order;
  const TrackingMap(this.order, {super.key});

  @override
  State<TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends State<TrackingMap> {
  List<LatLng>? _line;
  List<double> _cum = const [];
  LatLng? _farm, _home;
  double _farmFrac = 0.3;

  double get _target => switch (widget.order.status) {
        OrderStatus.newOrder || OrderStatus.findingDriver => 0.0,
        OrderStatus.assigned => _farmFrac,
        OrderStatus.pickedUp => 0.97,
        OrderStatus.delivered => 1.0,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final o = widget.order;
    final farm = await _geocode(o.driverPickup);
    final home = await _geocode(o.dropArea);
    // The driver starts a few minutes from the farm.
    final start = LatLng(farm.latitude + 0.018, farm.longitude - 0.018);
    final line = await _route([start, farm, home]);
    if (!mounted) return;
    const d = Distance();
    final cum = <double>[0];
    for (var i = 1; i < line.length; i++) {
      cum.add(cum.last + d(line[i - 1], line[i]));
    }
    var fi = 0;
    var best = double.infinity;
    for (var i = 0; i < line.length; i++) {
      final m = d(line[i], farm);
      if (m < best) {
        best = m;
        fi = i;
      }
    }
    setState(() {
      _line = line;
      _cum = cum;
      _farm = farm;
      _home = home;
      _farmFrac = cum.last == 0 ? 0.3 : cum[fi] / cum.last;
    });
  }

  LatLng _at(double f) {
    final line = _line!;
    final total = _cum.last;
    if (total == 0) return line.first;
    final t = f.clamp(0.0, 1.0) * total;
    var i = 1;
    while (i < _cum.length - 1 && _cum[i] < t) {
      i++;
    }
    final span = _cum[i] - _cum[i - 1];
    final k = span == 0 ? 0.0 : (t - _cum[i - 1]) / span;
    return LatLng(line[i - 1].latitude + (line[i].latitude - line[i - 1].latitude) * k,
        line[i - 1].longitude + (line[i].longitude - line[i - 1].longitude) * k);
  }

  Widget _pin(String emoji, Color c) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
        child: Text(emoji, style: const TextStyle(fontSize: 18)),
      );

  @override
  Widget build(BuildContext context) {
    final line = _line;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rCard),
      child: SizedBox(
        height: 300,
        child: line == null
            ? Container(color: AppTheme.glassFillStrong, alignment: Alignment.center, child: CircularProgressIndicator(color: AppTheme.sprout, strokeWidth: 2))
            : Stack(children: [
                FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(bounds: LatLngBounds.fromPoints(line), padding: const EdgeInsets.all(40)),
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                  ),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.ubuntudrop.ubuntuDrop'),
                    PolylineLayer(polylines: [Polyline(points: line, strokeWidth: 5, color: const Color(0xFF1E7A5C), borderColor: Colors.white, borderStrokeWidth: 1.5)]),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _target),
                      duration: Duration(seconds: widget.order.status == OrderStatus.pickedUp ? 20 : 8),
                      curve: Curves.easeInOut,
                      builder: (_, f, __) {
                        final show = widget.order.status != OrderStatus.findingDriver && widget.order.status != OrderStatus.newOrder;
                        return MarkerLayer(markers: [
                          Marker(point: _farm!, width: 38, height: 38, child: _pin('🌾', const Color(0xFF2D9A6B))),
                          Marker(point: _home!, width: 38, height: 38, child: _pin('🏠', const Color(0xFFD94141))),
                          if (show) Marker(point: _at(f), width: 42, height: 42, child: _pin('🛵', const Color(0xFF2E6FDB))),
                        ]);
                      },
                    ),
                  ],
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Demo: the driver moves along the real road route', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  ),
                ),
              ]),
      ),
    );
  }
}
