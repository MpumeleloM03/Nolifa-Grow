import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import '../theme/app_theme.dart';
import 'driver_state.dart' show placeOf;
import 'job_map.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;

/// The driver's live position for one driver, from the server. Only the buyer or
/// seller of an order that is on its way (and staff) can read it.
final driverLiveProvider = StreamProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, driverId) {
  if (!SupabaseBoot.ready) return Stream.value(null);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('driver_locations').stream(primaryKey: ['driver_id']).eq('driver_id', driverId),
    fetch: () async => [for (final r in await db.from('driver_locations').select().eq('driver_id', driverId)) Map<String, dynamic>.from(r)],
  ).map((rows) => rows.isEmpty ? null : rows.first);
});

/// Follow an order on a map: the farm, the home, the driver moving between them
/// and how long they have left. Used by the buyer, and by the seller for their
/// own orders.
class OrderTrackMap extends ConsumerStatefulWidget {
  final Order order;
  const OrderTrackMap(this.order, {super.key});

  @override
  ConsumerState<OrderTrackMap> createState() => _OrderTrackMapState();
}

class _OrderTrackMapState extends ConsumerState<OrderTrackMap> {
  final _map = MapController();
  LatLng? _farm, _home;
  RouteInfo? _route;
  LatLng? _routedFrom;
  Timer? _tick;

  bool get _live => widget.order.status == OrderStatus.assigned || widget.order.status == OrderStatus.pickedUp;

  @override
  void initState() {
    super.initState();
    _places();
    // The "seconds ago" text stays honest between position updates.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _places() async {
    final farm = await placeOf(widget.order.driverPickup);
    final home = await placeOf(widget.order.dropArea);
    if (!mounted) return;
    setState(() {
      _farm = farm;
      _home = home;
    });
  }

  Future<void> _reroute(LatLng me) async {
    final from = _routedFrom;
    if (from != null && const Distance()(from, me) < 150) return;
    _routedFrom = me;
    final toFarm = widget.order.status == OrderStatus.assigned;
    final r = await driveRoute([me, if (toFarm && _farm != null) _farm!, if (_home != null) _home!]);
    if (mounted) setState(() => _route = r);
  }

  Marker _pin(LatLng p, IconData icon, Color c, {double size = 38}) => Marker(
        point: p,
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)]),
          child: Icon(icon, color: Colors.white, size: size * 0.52),
        ),
      );

  String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 10) return 'just now';
    if (s < 90) return '$s s ago';
    if (s < 3600) return '${s ~/ 60} min ago';
    return '${s ~/ 3600} h ago';
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final farm = _farm, home = _home;
    final driverId = o.driverId;
    final live = driverId != null && _live ? ref.watch(driverLiveProvider(driverId)).valueOrNull : null;
    LatLng? me;
    DateTime? seen;
    if (live != null && live['online'] != false) {
      me = LatLng((live['lat'] as num).toDouble(), (live['lng'] as num).toDouble());
      seen = DateTime.tryParse('${live['updated_at']}')?.toLocal();
      if (_home != null) Future.microtask(() => _reroute(me!));
    }
    final stale = seen != null && DateTime.now().difference(seen).inSeconds > 120;

    final String headline;
    if (!_live) {
      headline = o.status == OrderStatus.delivered ? 'Delivered' : o.status == OrderStatus.findingDriver ? 'Finding a driver' : 'Being packed';
    } else if (me == null) {
      headline = '${o.driver ?? 'Your driver'} is on the way. Waiting for their location.';
    } else if (stale) {
      headline = 'Last seen ${_ago(seen)}';
    } else {
      final mins = _route?.minutes;
      final what = o.status == OrderStatus.assigned ? 'to collect from the farm' : 'to you';
      headline = mins == null ? '${o.driver ?? 'Your driver'} is on the way $what' : '${o.driver ?? 'Your driver'} is about $mins min away $what';
    }

    final pts = [if (farm != null) farm, if (home != null) home, if (me != null) me];
    if (pts.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(color: AppTheme.glassFillStrong, borderRadius: BorderRadius.circular(AppTheme.rCard)),
        alignment: Alignment.center,
        child: CircularProgressIndicator(color: AppTheme.sprout, strokeWidth: 2),
      );
    }
    final line = _route?.line ?? [if (farm != null) farm, if (home != null) home];
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rCard),
      child: SizedBox(
        height: 240,
        child: Stack(children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCameraFit: pts.length > 1
                  ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(42), maxZoom: 15)
                  : null,
              initialCenter: pts.first,
              initialZoom: 13,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.nolifa.grow'),
              if (line.length > 1)
                PolylineLayer(polylines: [
                  Polyline(points: line, strokeWidth: 5, color: const Color(0xFF1E7A5C), borderColor: Colors.white, borderStrokeWidth: 1.5, isDotted: _route?.real == false),
                ]),
              MarkerLayer(markers: [
                if (farm != null) _pin(farm, Icons.agriculture_rounded, const Color(0xFF2D9A6B)),
                if (home != null) _pin(home, Icons.home_rounded, const Color(0xFFD94141)),
                if (me != null) _pin(me, Icons.two_wheeler_rounded, stale ? Colors.grey : const Color(0xFF2E6FDB), size: 44),
              ]),
            ],
          ),
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.74), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(me != null && !stale ? Icons.circle : Icons.circle_outlined, size: 10, color: me != null && !stale ? const Color(0xFF52D1A4) : Colors.white54),
                const SizedBox(width: 8),
                Expanded(child: Text(headline, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
              ]),
            ),
          ),
          if (seen != null && !stale)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
                child: Text('Updated ${_ago(seen)}', style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ),
            ),
        ]),
      ),
    );
  }
}
