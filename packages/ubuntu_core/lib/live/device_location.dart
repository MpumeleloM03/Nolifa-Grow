import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';

/// Where the phone is right now, asking for permission once. Returns null when
/// location is off or refused, so callers say so instead of guessing.
Future<(double, double)?> deviceLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 10) return (last.latitude, last.longitude);
    final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium))
        .timeout(const Duration(seconds: 8));
    return (p.latitude, p.longitude);
  } catch (e) {
    debugPrint('location: unavailable: $e');
    return null;
  }
}
