import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the phone is right now as (latitude, longitude), or null when
/// location is off, refused or unavailable. Each app overrides this with the
/// phone's GPS. Everything that says "near you" reads it, so nothing is
/// guessed from a saved region.
final userLocationProvider = FutureProvider<(double, double)?>((ref) async => null);

/// A readable name for a place ("Umlazi, Durban"), from OpenStreetMap's
/// reverse geocoder. Null when it cannot be reached.
Future<String?> reverseGeocode(double lat, double lng) async {
  try {
    final c = HttpClient()..userAgent = 'Nolifa/1.0';
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=jsonv2&zoom=14&addressdetails=1');
    final req = await c.getUrl(uri).timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return null;
    final a = (jsonDecode(await res.transform(utf8.decoder).join())['address'] as Map?) ?? const {};
    final parts = [
      a['suburb'] ?? a['neighbourhood'] ?? a['village'] ?? a['hamlet'],
      a['city'] ?? a['town'] ?? a['municipality'] ?? a['county'],
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  } catch (e) {
    debugPrint('location: could not name the place: $e');
    return null;
  }
}

/// The place name for where the user is. Null while loading or unknown.
final userPlaceProvider = FutureProvider<String?>((ref) async {
  final loc = await ref.watch(userLocationProvider.future);
  if (loc == null) return null;
  return reverseGeocode(loc.$1, loc.$2);
});
