import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr;
/// Where the driver is. Asks once; if location is off or refused, returns null
/// and the map starts from the farm instead.
Future<LatLng?> driverLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium))
        .timeout(const Duration(seconds: 6));
    return LatLng(p.latitude, p.longitude);
  } catch (e) {
    debugPrint('location: unavailable: $e');
    return null;
  }
}

/// Finds a street address on the map. Falls back to the demo place list, then
/// to the middle of Durban, so a route can always be drawn.
Future<LatLng> geocode(String text) async {
  final known = lookupPlace(text);
  try {
    final c = HttpClient()..userAgent = 'NolifaDelivery/1.0';
    final q = Uri.encodeQueryComponent('$text, KwaZulu-Natal, South Africa');
    final req = await c.getUrl(Uri.parse('https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=1'))
        .timeout(const Duration(seconds: 5));
    final res = await req.close().timeout(const Duration(seconds: 5));
    final body = await res.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List;
    if (list.isNotEmpty) {
      return LatLng(double.parse(list.first['lat'] as String), double.parse(list.first['lon'] as String));
    }
  } catch (e) {
    debugPrint('geocode: lookup failed for "$text": $e');
  }
  final k = known ?? durbanCentre;
  return LatLng(k.$1, k.$2);
}

class RouteInfo {
  final List<LatLng> line;
  final double km;
  final int minutes;
  final bool real; // false when drawn as a straight line
  const RouteInfo(this.line, this.km, this.minutes, this.real);
}

/// Driving route through the points, from the free OSRM service. If it cannot
/// be reached, a straight line and a rough time are used instead.
Future<RouteInfo> driveRoute(List<LatLng> pts) async {
  try {
    final coords = pts.map((p) => '${p.longitude},${p.latitude}').join(';');
    final c = HttpClient();
    final req = await c
        .getUrl(Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson'))
        .timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 6));
    final body = await res.transform(utf8.decoder).join();
    final r = (jsonDecode(body)['routes'] as List).first;
    final line = [for (final p in r['geometry']['coordinates'] as List) LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())];
    return RouteInfo(line, (r['distance'] as num) / 1000, ((r['duration'] as num) / 60).round(), true);
  } catch (e) {
    debugPrint('route: using a straight line: $e');
    const d = Distance();
    var m = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      m += d(pts[i], pts[i + 1]);
    }
    final km = m / 1000 * 1.3; // roads are longer than straight lines
    return RouteInfo(pts, km, (km / 40 * 60).round().clamp(1, 600), false);
  }
}

/// The map on an accepted job: the driver, the farm to collect from, and the
/// customer's address, with the driving route between them.
class JobRouteMap extends ConsumerStatefulWidget {
  final Order order;
  const JobRouteMap(this.order, {super.key});

  @override
  ConsumerState<JobRouteMap> createState() => _JobRouteMapState();
}

class _JobRouteMapState extends ConsumerState<JobRouteMap> {
  LatLng? _me, _farm, _home;
  RouteInfo? _route;
  bool _failed = false;
  StreamSubscription<Position>? _gps;
  bool _gotFix = false;

  bool get _toFarm => widget.order.status == OrderStatus.assigned;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gps?.cancel();
    super.dispose();
  }

  /// Follows the driver along the route once we have a real position.
  void _follow() {
    if (_gps != null) return;
    try {
      _gps = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 30))
          .listen((p) {
        if (mounted) setState(() => _me = LatLng(p.latitude, p.longitude));
      }, onError: (Object e) => debugPrint('location: stream stopped: $e'));
    } catch (e) {
      debugPrint('location: cannot follow: $e');
    }
  }

  @override
  void didUpdateWidget(JobRouteMap old) {
    super.didUpdateWidget(old);
    if (old.order.status != widget.order.status) _load();
  }

  Future<void> _load() async {
    final o = widget.order;
    final locate = ref.read(reportLocationProvider);
    final results = await Future.wait<Object?>([
      locate().then((p) => p == null ? null : LatLng(p.$1, p.$2)),
      geocode(o.driverPickup),
      geocode(o.dropArea),
    ]);
    if (!mounted) return;
    final farm = results[1]! as LatLng;
    final home = results[2]! as LatLng;
    // No location (denied, or a simulator): start near the farm so a route still shows.
    _gotFix = results[0] != null;
    final me = (results[0] as LatLng?) ?? LatLng(farm.latitude + 0.02, farm.longitude - 0.02);
    final pts = _toFarm ? [me, farm, home] : [me, home];
    final r = await driveRoute(pts);
    if (!mounted) return;
    setState(() {
      _me = me;
      _farm = farm;
      _home = home;
      _route = r;
      _failed = false;
    });
    if (_gotFix) _follow();
  }

  Marker _pin(LatLng p, IconData icon, Color c) => Marker(
        point: p,
        width: 38,
        height: 38,
        child: Container(
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Marker _hazardPin(RoadHazard h) => Marker(
        point: LatLng(h.lat, h.lng),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: AppTheme.sheet,
            builder: (_) => SafeArea(
              child: Padding(padding: const EdgeInsets.all(AppTheme.s4), child: HazardTile(h)),
            ),
          ),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4D6),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE8A33D), width: 2.5),
            ),
            child: Text(h.kind.emoji, style: const TextStyle(fontSize: 18)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = _route;
    if (r == null || _me == null) {
      return Container(
        color: AppTheme.glassFillStrong,
        alignment: Alignment.center,
        child: _failed
            ? Text('Could not load the map', style: AppTheme.footnote)
            : CircularProgressIndicator(color: AppTheme.sprout, strokeWidth: 2),
      );
    }
    final bounds = LatLngBounds.fromPoints([r.line.first, ...r.line, _home!, _farm!]);
    final now = ref.watch(roadClockProvider)();
    final live = ref.watch(roadProvider).live(now);
    final route = [for (final p in r.line) (p.latitude, p.longitude)];
    final ahead = hazardsAhead(route, (_me!.latitude, _me!.longitude), live);
    final onRoute = {for (final a in ahead) a.hazard.id};
    return Stack(children: [
      FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(36)),
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.nolifa.delivery',
          ),
          PolylineLayer(polylines: [
            Polyline(points: r.line, strokeWidth: 5, color: const Color(0xFF1E7A5C), borderColor: Colors.white, borderStrokeWidth: 1.5,
                isDotted: !r.real),
          ]),
          MarkerLayer(markers: [
            for (final h in live)
              if (onRoute.contains(h.id) || bounds.contains(LatLng(h.lat, h.lng))) _hazardPin(h),
            _pin(_me!, Icons.two_wheeler_rounded, const Color(0xFF2E6FDB)),
            if (_toFarm) _pin(_farm!, Icons.agriculture_rounded, const Color(0xFF2D9A6B)),
            _pin(_home!, Icons.home_rounded, const Color(0xFFD94141)),
          ]),
        ],
      ),
      Positioned(
        left: 8,
        top: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(10)),
          child: Text(
              '${r.km.toStringAsFixed(1)} km  •  about ${r.minutes} min${r.real ? '' : '  •  estimate'}${ahead.isEmpty ? '' : '  •  ${ahead.length} alert${ahead.length == 1 ? '' : 's'}'}',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
      Positioned(
        left: 8,
        bottom: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
          child: Text(_toFarm ? 'You > Farm > Customer' : 'You > Customer', style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ),
      ),
      Positioned(
        right: 8,
        bottom: 8,
        child: FloatingActionButton.small(
          heroTag: 'report-${widget.order.id}',
          backgroundColor: const Color(0xFFE8A33D),
          foregroundColor: Colors.black,
          tooltip: tr('Report a hazard'),
          onPressed: () => showRoadReportSheet(context, ref),
          child: const Icon(Icons.add_alert_rounded),
        ),
      ),
      if (ahead.isNotEmpty)
        Positioned(
          left: 8,
          right: 8,
          top: 44,
          child: _AheadBanner(ahead.first, onHere: ahead.first.metresAhead < 300),
        ),
    ]);
  }
}


/// The next warning on the route. Close to it, asks the question that keeps
/// the map honest: is it still there?
class _AheadBanner extends ConsumerWidget {
  final HazardAhead ahead;
  final bool onHere;
  const _AheadBanner(this.ahead, {required this.onHere});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ahead.hazard;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8A33D))),
      child: Row(children: [
        Text(h.kind.emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${h.kind.label} in ${ahead.distanceText}',
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: 13)),
            Text(h.kind.advice, style: const TextStyle(color: Colors.black54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (onHere) ...[
          TextButton(onPressed: () => ref.read(roadProvider.notifier).confirm(h.id), child: const Text('Still there')),
          TextButton(onPressed: () => ref.read(roadProvider.notifier).deny(h.id), child: const Text('Gone')),
        ],
      ]),
    );
  }
}
