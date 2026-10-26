import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import '../services/job_map.dart';
import 'driver_state.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
const _ink = Color(0xFF0B0B0C);
const _green = Color(0xFF1E7A5C);

/// One step of the run, in order. Every farm is collected from before the first
/// delivery, and each delivery needs its customer's PIN.
class _Step {
  final StopKind kind;
  final String label;
  final LatLng at;
  final List<Order> orders;
  const _Step(this.kind, this.label, this.at, this.orders);
}

final _stepsProvider = FutureProvider.family<List<_Step>, List<Order>>((ref, jobs) async {
  final me = ref.watch(driverPositionProvider).valueOrNull;
  final byFarm = <String, List<Order>>{};
  for (final o in jobs) {
    if (o.status == OrderStatus.assigned) byFarm.putIfAbsent(o.driverPickup, () => []).add(o);
  }
  final steps = <_Step>[];
  var here = me ?? const LatLng(-29.8587, 31.0218);
  final pickups = <_Step>[];
  for (final e in byFarm.entries) {
    pickups.add(_Step(StopKind.pickup, e.key, await placeOf(e.key), e.value));
  }
  double d(LatLng a, LatLng b) => kmBetween(a.latitude, a.longitude, b.latitude, b.longitude);
  while (pickups.isNotEmpty) {
    pickups.sort((a, b) => d(here, a.at).compareTo(d(here, b.at)));
    final s = pickups.removeAt(0);
    steps.add(s);
    here = s.at;
  }
  final drops = <_Step>[];
  for (final o in jobs) {
    drops.add(_Step(StopKind.drop, o.dropArea, await placeOf(o.dropArea), [o]));
  }
  while (drops.isNotEmpty) {
    drops.sort((a, b) => d(here, a.at).compareTo(d(here, b.at)));
    final s = drops.removeAt(0);
    steps.add(s);
    here = s.at;
  }
  return steps;
});

/// The run in progress: a map of what is left, then the stops in order.
class TripScreen extends ConsumerStatefulWidget {
  final List<Order> jobs;
  const TripScreen({super.key, required this.jobs});

  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  RouteInfo? _route;
  String _routeKey = '';
  bool _busy = false;

  Future<void> _plan(List<_Step> remaining, LatLng? me) async {
    final key = remaining.map((s) => '${s.kind.name}${s.label}${s.orders.length}').join('|');
    if (key == _routeKey || remaining.isEmpty) return;
    _routeKey = key;
    final pts = [if (me != null) me, for (final s in remaining) s.at];
    if (pts.length < 2) return;
    final r = await driveRoute(pts);
    if (mounted && _routeKey == key) setState(() => _route = r);
  }

  Future<void> _collect(_Step s) async {
    setState(() => _busy = true);
    HapticFeedback.heavyImpact();
    final shot = await ref.read(proofPhotoProvider)();
    if (shot) {
      final store = ref.read(marketProvider.notifier);
      for (final o in s.orders) {
        store.pickedUp(o.id);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _navigate(_Step s) async {
    HapticFeedback.selectionClick();
    final ok = await ref.read(navigateProvider)(s.label);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open maps. Head to ${s.label}.'), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(marketProvider.select((s) => s.myJobs));
    final stepsAsync = ref.watch(_stepsProvider(widget.jobs));
    final me = ref.watch(driverPositionProvider).valueOrNull;
    final store = ref.read(marketProvider.notifier);
    final all = stepsAsync.valueOrNull ?? const <_Step>[];

    // What is left: farms with goods still to collect, and deliveries not made.
    final remaining = <_Step>[];
    for (final s in all) {
      final live = [for (final o in s.orders) jobs.where((j) => j.id == o.id).firstOrNull].whereType<Order>().toList();
      if (live.isEmpty) continue;
      if (s.kind == StopKind.pickup) {
        final pending = live.where((o) => o.status == OrderStatus.assigned).toList();
        if (pending.isNotEmpty) remaining.add(_Step(s.kind, s.label, s.at, pending));
      } else {
        remaining.add(_Step(s.kind, s.label, s.at, live));
      }
    }
    _plan(remaining, me);

    final pay = jobs.fold<double>(0, (a, o) => a + o.driverPay);
    final next = remaining.firstOrNull;
    final collecting = remaining.any((s) => s.kind == StopKind.pickup);

    return Stack(children: [
      FlutterMap(
        options: MapOptions(
          initialCenter: me ?? (remaining.isNotEmpty ? remaining.first.at : const LatLng(-29.8587, 31.0218)),
          initialZoom: 11,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.nolifa.delivery'),
          if (_route != null) PolylineLayer(polylines: [Polyline(points: _route!.line, strokeWidth: 5, color: _ink, borderColor: Colors.white, borderStrokeWidth: 1.5)]),
          MarkerLayer(markers: [
            if (me != null)
              Marker(point: me, width: 26, height: 26, child: Container(decoration: BoxDecoration(color: const Color(0xFF2E6FDB), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)))),
            for (var i = 0; i < remaining.length; i++)
              Marker(
                point: remaining[i].at,
                width: 34,
                height: 34,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: remaining[i].kind == StopKind.pickup ? _green : const Color(0xFFD94141), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        ],
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(30)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(rand(pay, decimals: 0), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text('${remaining.length} stops left${_route == null ? '' : '  ·  ${_route!.km.toStringAsFixed(0)} km'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ),
      ),
      DraggableScrollableSheet(
        initialChildSize: 0.46,
        minChildSize: 0.2,
        maxChildSize: 0.9,
        snap: true,
        builder: (context, scroll) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black26)],
          ),
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 10, 20, 120), children: [
            Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 12),
            if (stepsAsync.isLoading && all.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (next != null) ...[
              Text(next.kind == StopKind.pickup ? 'Collect at ${next.label}' : 'Deliver to ${next.label}', style: AppTheme.title2),
              Text(
                  next.kind == StopKind.pickup
                      ? '${next.orders.fold<int>(0, (a, o) => a + o.lines.fold<int>(0, (b, l) => b + l.qty))} items from ${next.orders.length} ${next.orders.length == 1 ? 'order' : 'orders'}. Take a photo of the goods.'
                      : 'Ask the customer for their 4-digit PIN. ${collecting ? 'Collect everything first.' : ''}',
                  style: AppTheme.callout),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _navigate(next), icon: const Icon(Icons.navigation_rounded), label: const Text('Navigate'))),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _ink, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: (_busy || (next.kind == StopKind.drop && collecting))
                        ? null
                        : () => next.kind == StopKind.pickup ? _collect(next) : askCustomerPin(context, store, next.orders.first),
                    child: Text(next.kind == StopKind.pickup ? 'I collected it' : 'Enter PIN and deliver', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
            ] else if (!stepsAsync.isLoading)
              Text('All delivered. Payment releases when each customer confirms or after the protection window.', style: AppTheme.callout),
            if (remaining.length > 1) ...[
              Text('Then', style: AppTheme.footnote),
              for (var i = 1; i < remaining.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 13, backgroundColor: remaining[i].kind == StopKind.pickup ? _green : const Color(0xFFD94141), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12))),
                  title: Text('${remaining[i].kind == StopKind.pickup ? 'Collect' : 'Deliver'}  ${remaining[i].label}'),
                  trailing: IconButton(icon: const Icon(Icons.navigation_outlined), onPressed: () => _navigate(remaining[i])),
                ),
            ],
          ]),
        ),
      ),
    ]);
  }
}
