import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'job_map.dart';
import 'driver_state.dart';
import 'trip_screen.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
const _ink = Color(0xFF0B0B0C);
const _green = Color(0xFF1E7A5C);

String _hm(int minutes) => minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';

/// The driver's home: a full map, a switch to go online, and bulk batches of
/// jobs from several farms that pay once for the whole run. Pick one and go.
class DriverHome extends ConsumerStatefulWidget {
  const DriverHome({super.key});

  @override
  ConsumerState<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends ConsumerState<DriverHome> {
  final _map = MapController();
  String? _picked;
  RouteInfo? _route;
  bool _taking = false;
  String? _msg;

  Batch? _batch(List<Batch> all) => all.where((b) => b.id == _picked).firstOrNull;

  Future<void> _pick(Batch b) async {
    HapticFeedback.selectionClick();
    setState(() {
      _picked = b.id;
      _route = null;
      _msg = null;
    });
    final me = ref.read(driverPositionProvider).valueOrNull;
    final pts = [if (me != null) me, for (final s in b.stops) LatLng(s.lat, s.lng)];
    if (pts.length < 2) return;
    final r = await driveRoute(pts);
    if (!mounted || _picked != b.id) return;
    setState(() => _route = r);
    try {
      _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(r.line), padding: const EdgeInsets.fromLTRB(40, 120, 40, 360)));
    } catch (_) {}
  }

  Future<void> _take(Batch b) async {
    setState(() {
      _taking = true;
      _msg = null;
    });
    HapticFeedback.heavyImpact();
    final ok = await ref.read(marketProvider.notifier).acceptBatch(b.orderIds);
    if (!mounted) return;
    setState(() {
      _taking = false;
      _picked = null;
      _route = null;
      if (!ok) _msg = 'Another driver took one of those jobs a moment ago. Pick another batch.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    if (s.myJobs.isNotEmpty) return TripScreen(jobs: s.myJobs);
    final batches = ref.watch(batchesProvider);
    final me = ref.watch(driverPositionProvider).valueOrNull;
    final picked = _batch(batches);
    final loading = ref.watch(jobPointsProvider).isLoading && batches.isEmpty;
    final centre = me ?? const LatLng(-29.8587, 31.0218);

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(initialCenter: centre, initialZoom: 11, interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.nolifa.delivery'),
          if (_route != null)
            PolylineLayer(polylines: [Polyline(points: _route!.line, strokeWidth: 5, color: _ink, borderColor: Colors.white, borderStrokeWidth: 1.5)]),
          MarkerLayer(markers: [
            if (me != null)
              Marker(
                point: me,
                width: 26,
                height: 26,
                child: Container(decoration: BoxDecoration(color: const Color(0xFF2E6FDB), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))),
              ),
            if (s.driverOnline && picked == null)
              for (final b in batches)
                Marker(
                  point: LatLng(b.stops.first.lat, b.stops.first.lng),
                  width: 92,
                  height: 36,
                  child: GestureDetector(
                    onTap: () => _pick(b),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white, width: 2)),
                      child: Text(rand(b.payout, decimals: 0), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
            if (picked != null)
              for (var i = 0; i < picked.stops.length; i++)
                Marker(
                  point: LatLng(picked.stops[i].lat, picked.stops[i].lng),
                  width: 34,
                  height: 34,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: picked.stops[i].kind == StopKind.pickup ? _green : const Color(0xFFD94141),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
          ]),
        ],
      ),
      // Top bar: earned today, like the pill on a ride app.
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _round(Icons.sos_rounded, () => _sos(context), Colors.red),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)]),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CountUp(s.driverEarned, decimals: 0, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                const Text('earned', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            const Spacer(),
            _round(Icons.my_location_rounded, () {
              if (me != null) _map.move(me, 13);
            }, _ink),
          ]),
        ),
      ),
      DraggableScrollableSheet(
        initialChildSize: picked != null ? 0.36 : 0.44,
        minChildSize: 0.18,
        maxChildSize: 0.88,
        snap: true,
        builder: (context, scroll) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black26)],
          ),
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 10, 20, 120), children: [
            Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 14),
            if (picked != null)
              _Detail(
                batch: picked,
                route: _route,
                taking: _taking,
                onBack: () => setState(() {
                  _picked = null;
                  _route = null;
                }),
                onTake: () => _take(picked),
              )
            else ...[
              _OnlineBar(
                online: s.driverOnline,
                verified: s.driverVerified,
                onToggle: () {
                  HapticFeedback.mediumImpact();
                  if (!s.driverVerified && !s.driverOnline) {
                    final apply = ref.read(driverApplicationScreenProvider);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => apply != null ? apply() : const VerifyScreen(role: KycRole.driver)));
                    return;
                  }
                  store.toggleOnline();
                },
              ),
              if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: TextStyle(color: AppTheme.danger))),
              const SizedBox(height: 14),
              const RoadAlertsCard(),
              const SizedBox(height: 8),
              const HubDeskCard(),
              if (s.driverOnline) ...[
                const SizedBox(height: 14),
                Row(children: [
                  Text('Batches near you', style: AppTheme.title3),
                  const Spacer(),
                  if (batches.isNotEmpty) Pill('${batches.length}', color: _green),
                ]),
                const SizedBox(height: 4),
                Text('Several farms, one run, one payout. Tap a batch to see the route.', style: AppTheme.footnote),
                const SizedBox(height: 10),
                if (loading)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                else if (batches.isEmpty)
                  Text('No jobs right now. Stay online. New ones appear as people order.', style: AppTheme.callout)
                else
                  for (final b in batches) _BatchCard(b, onTap: () => _pick(b)),
              ],
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _round(IconData i, VoidCallback f, Color c) => Material(
        color: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: f, child: Padding(padding: const EdgeInsets.all(11), child: Icon(i, color: c))),
      );

  void _sos(BuildContext context) {
    HapticFeedback.heavyImpact();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Safety line'),
        content: const Text('Your live location and job details are shared with the Nolifa safety team. In an emergency call 10111 or 112.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}

class _OnlineBar extends StatelessWidget {
  final bool online, verified;
  final VoidCallback onToggle;
  const _OnlineBar({required this.online, required this.verified, required this.onToggle});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(online ? 'You are online' : 'You are offline', style: AppTheme.title2),
            Text(!verified ? 'Finish verification to start' : (online ? 'Looking for batches' : 'Go online to see batches'), style: AppTheme.footnote),
          ]),
        ),
        GestureDetector(
          onTap: onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            decoration: BoxDecoration(color: online ? const Color(0xFFD94141) : _ink, borderRadius: BorderRadius.circular(34)),
            child: Text(online ? 'Stop' : 'Go', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ),
      ]);
}

class _BatchCard extends StatelessWidget {
  final Batch b;
  final VoidCallback onTap;
  const _BatchCard(this.b, {required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rand(b.payout, decimals: 0), style: AppTheme.largeTitle.copyWith(fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('${b.farms} ${b.farms == 1 ? 'farm' : 'farms'}  ·  ${b.drops} ${b.drops == 1 ? 'drop' : 'drops'}  ·  ${b.items} items', style: AppTheme.callout),
                  Text('${b.km.toStringAsFixed(0)} km  ·  about ${_hm(b.minutes)}  ·  ${rand(b.perHour, decimals: 0)} an hour', style: AppTheme.footnote),
                  Text('${rand(b.netPerHour, decimals: 0)} an hour after fuel (${rand(b.fuel, decimals: 0)})', style: AppTheme.caption),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
            ]),
          ),
        ),
      );
}

class _Detail extends StatelessWidget {
  final Batch batch;
  final RouteInfo? route;
  final bool taking;
  final VoidCallback onBack, onTake;
  const _Detail({required this.batch, required this.route, required this.taking, required this.onBack, required this.onTake});

  @override
  Widget build(BuildContext context) {
    final km = route?.km ?? batch.km;
    final min = route?.minutes ?? batch.minutes;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
        const Spacer(),
        Text(rand(batch.payout, decimals: 0), style: AppTheme.largeTitle.copyWith(fontSize: 38, fontWeight: FontWeight.w900)),
        const Spacer(),
        const SizedBox(width: 48),
      ]),
      Center(child: Text('${batch.farms} farms · ${batch.drops} drops · ${batch.items} items · ${km.toStringAsFixed(0)} km · ${_hm(min)}${route?.real == false ? ' (estimate)' : ''}', style: AppTheme.callout)),
      Center(child: Text('About ${rand(batch.netPerHour, decimals: 0)} an hour after ${rand(batch.fuel, decimals: 0)} of fuel', style: AppTheme.footnote)),
      const SizedBox(height: 14),
      for (var i = 0; i < batch.stops.length; i++)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, backgroundColor: batch.stops[i].kind == StopKind.pickup ? _green : const Color(0xFFD94141), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12))),
          title: Text(batch.stops[i].kind == StopKind.pickup ? 'Collect at ${batch.stops[i].label}' : 'Deliver to ${batch.stops[i].label}'),
          subtitle: Text('${batch.stops[i].items} items${batch.stops[i].orders.length > 1 ? ' · ${batch.stops[i].orders.length} orders' : ''}'),
        ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _ink, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: taking ? null : onTake,
          child: Text(taking ? 'Taking it' : 'Take this batch', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: 6),
      Text('You are paid for every job in it once each is delivered with the customer PIN.', style: AppTheme.caption),
    ]);
  }
}
