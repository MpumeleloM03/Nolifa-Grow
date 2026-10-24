import 'dart:math' as math;
import '../market/market_models.dart';

/// One job with its two ends placed on the map.
class JobPoint {
  final Order order;
  final double pLat, pLng; // where it is collected
  final double dLat, dLng; // where it goes
  const JobPoint(this.order, this.pLat, this.pLng, this.dLat, this.dLng);

  String get farm => order.driverPickup;
  int get items => order.lines.fold<int>(0, (a, l) => a + l.qty);
}

enum StopKind { pickup, drop }

class TripStop {
  final StopKind kind;
  final String label;
  final double lat, lng;
  final List<Order> orders; // one farm gives several orders, one drop gives one
  const TripStop(this.kind, this.label, this.lat, this.lng, this.orders);

  int get items => orders.fold<int>(0, (a, o) => a + o.lines.fold<int>(0, (b, l) => b + l.qty));
}

/// Jobs a driver can take together: collected from a few farms close by, then
/// delivered in one run. The payout is the sum of what each job pays.
class Batch {
  final String id;
  final List<JobPoint> jobs;
  final List<TripStop> stops;
  final double km;
  final int minutes;
  const Batch(this.id, this.jobs, this.stops, this.km, this.minutes);

  List<String> get orderIds => [for (final j in jobs) j.order.id];
  double get payout => r2(jobs.fold<double>(0, (a, j) => a + j.order.driverPay));
  int get items => jobs.fold<int>(0, (a, j) => a + j.items);
  int get farms => stops.where((s) => s.kind == StopKind.pickup).length;
  int get drops => stops.where((s) => s.kind == StopKind.drop).length;
  double get perHour => minutes == 0 ? 0 : r2(payout / (minutes / 60));
}

double kmBetween(double aLat, double aLng, double bLat, double bLng) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(bLat - aLat);
  final dLng = rad(bLng - aLng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(aLat)) * math.cos(rad(bLat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h.toDouble()));
}

/// Groups open jobs into batches. Jobs go together when they are collected
/// within [pickupKm] of each other and delivered within [dropKm] of each other.
/// A batch has at most [maxFarms] farms and [maxDrops] deliveries. Richest
/// batch first. Every job lands in exactly one batch, so no job is stranded.
List<Batch> buildBatches(
  List<JobPoint> jobs, {
  double? startLat,
  double? startLng,
  int maxFarms = 4,
  int maxDrops = 12,
  double pickupKm = 20,
  double dropKm = 30,
}) {
  final left = [...jobs]..sort((a, b) => b.order.driverPay.compareTo(a.order.driverPay));
  final out = <Batch>[];
  while (left.isNotEmpty) {
    final seed = left.removeAt(0);
    final group = [seed];
    final farms = {seed.farm};
    final near = [...left]..sort((a, b) =>
        kmBetween(seed.pLat, seed.pLng, a.pLat, a.pLng).compareTo(kmBetween(seed.pLat, seed.pLng, b.pLat, b.pLng)));
    for (final j in near) {
      if (group.length >= maxDrops) break;
      if (kmBetween(seed.pLat, seed.pLng, j.pLat, j.pLng) > pickupKm) continue;
      if (kmBetween(seed.dLat, seed.dLng, j.dLat, j.dLng) > dropKm) continue;
      if (!farms.contains(j.farm) && farms.length >= maxFarms) continue;
      farms.add(j.farm);
      group.add(j);
      left.remove(j);
    }
    out.add(_make(group, startLat ?? seed.pLat, startLng ?? seed.pLng));
  }
  out.sort((a, b) => b.payout.compareTo(a.payout));
  return out;
}

Batch _make(List<JobPoint> group, double fromLat, double fromLng) {
  // Collect from the nearest farm first, then the next nearest, and so on.
  final byFarm = <String, List<JobPoint>>{};
  for (final j in group) {
    byFarm.putIfAbsent(j.farm, () => []).add(j);
  }
  final pickups = [
    for (final e in byFarm.entries)
      TripStop(StopKind.pickup, e.key, e.value.first.pLat, e.value.first.pLng, [for (final j in e.value) j.order])
  ];
  final stops = <TripStop>[];
  var lat = fromLat, lng = fromLng;
  final pLeft = [...pickups];
  while (pLeft.isNotEmpty) {
    pLeft.sort((a, b) => kmBetween(lat, lng, a.lat, a.lng).compareTo(kmBetween(lat, lng, b.lat, b.lng)));
    final s = pLeft.removeAt(0);
    stops.add(s);
    lat = s.lat;
    lng = s.lng;
  }
  final drops = [for (final j in group) TripStop(StopKind.drop, j.order.dropArea, j.dLat, j.dLng, [j.order])];
  while (drops.isNotEmpty) {
    drops.sort((a, b) => kmBetween(lat, lng, a.lat, a.lng).compareTo(kmBetween(lat, lng, b.lat, b.lng)));
    final s = drops.removeAt(0);
    stops.add(s);
    lat = s.lat;
    lng = s.lng;
  }
  // Straight legs, stretched for the shape of real roads.
  var km = 0.0;
  var pLat = fromLat, pLng = fromLng;
  for (final s in stops) {
    km += kmBetween(pLat, pLng, s.lat, s.lng) * 1.3;
    pLat = s.lat;
    pLng = s.lng;
  }
  km = double.parse(km.toStringAsFixed(1));
  final minutes = (km / 35 * 60).round() + stops.length * 6;
  final ids = [for (final j in group) j.order.id]..sort();
  return Batch(ids.join('+'), group, stops, km, minutes);
}
