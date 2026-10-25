import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../live/device_location.dart';
import '../market/market_store.dart';
import '../supabase/supabase_boot.dart';

/// Shares the driver's position with the server while they are online or on a
/// job, so the buyer and the seller can follow the order and staff can see where
/// every driver is. Only an approved driver can post (the server checks), and
/// only the people on an order in progress can read it.
class DriverTracker {
  DriverTracker._();
  static final instance = DriverTracker._();

  StreamSubscription<Position>? _sub;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  Position? _last;

  bool get running => _sub != null;
  Position? get lastPosition => _last;

  Future<void> start() async {
    if (_sub != null || !SupabaseBoot.ready) return;
    // Asking once up front shows the permission prompt before the first trip.
    if (await deviceLocation() == null) return;
    try {
      _sub = positionFeed(distanceMetres: 10).listen(_send, onError: (Object e) => debugPrint('tracking: feed stopped: $e'));
    } catch (e) {
      debugPrint('tracking: could not start: $e');
    }
  }

  Future<void> _send(Position p) async {
    _last = p;
    final now = DateTime.now();
    if (now.difference(_lastSent).inSeconds < 4) return;
    _lastSent = now;
    try {
      await SupabaseBoot.client.schema('delivery_api').rpc('post_location', params: {
        'p_lat': p.latitude,
        'p_lng': p.longitude,
        'p_heading': p.heading.isNaN || p.heading < 0 ? null : p.heading,
        'p_speed': p.speed.isNaN || p.speed < 0 ? null : p.speed * 3.6,
        'p_accuracy': p.accuracy,
      });
    } catch (e) {
      // A dropped signal must not stop the trip; the next fix tries again.
      debugPrint('tracking: could not post a position: $e');
    }
  }

  Future<void> stop() async {
    final s = _sub;
    if (s == null) return;
    _sub = null;
    await s.cancel();
    if (!SupabaseBoot.ready) return;
    try {
      await SupabaseBoot.client.schema('delivery_api').rpc('go_offline');
    } catch (e) {
      debugPrint('tracking: could not say offline: $e');
    }
  }
}

/// Wrap the driver's screens in this. It starts tracking when the driver goes
/// online or takes a job and stops when they finish.
class DriverTrackingHost extends ConsumerStatefulWidget {
  final Widget child;
  const DriverTrackingHost({super.key, required this.child});

  @override
  ConsumerState<DriverTrackingHost> createState() => _DriverTrackingHostState();
}

class _DriverTrackingHostState extends ConsumerState<DriverTrackingHost> {
  @override
  void dispose() {
    DriverTracker.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(marketProvider.select((s) => s.driverOnline || s.myJobs.isNotEmpty));
    final tracker = DriverTracker.instance;
    if (active && !tracker.running) {
      Future.microtask(tracker.start);
    } else if (!active && tracker.running) {
      Future.microtask(tracker.stop);
    }
    return widget.child;
  }
}
