import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RegionInfo {
  final String key; // translation key
  final String name; // canonical English name (stored in records)
  final LatLng center;

  const RegionInfo(this.key, this.name, this.center);
}

class RegionService {
  static const String _userRegionKey = 'user_region';

  // KwaZulu-Natal regional centroids used for predictive mapping.
  static const List<RegionInfo> regions = [
    RegionInfo('greater_durban', 'Greater Durban', LatLng(-29.8587, 31.0218)),
    RegionInfo('midlands', 'KZN Midlands', LatLng(-29.6167, 30.3833)),
    RegionInfo('north_coast', 'North Coast', LatLng(-29.4, 31.2)),
    RegionInfo('south_coast', 'South Coast', LatLng(-30.2, 30.8)),
    RegionInfo('zululand', 'Zululand', LatLng(-28.75, 31.88)),
    RegionInfo('northern_kzn', 'Northern KZN', LatLng(-27.8, 32.1)),
    RegionInfo('other', 'Other', LatLng(-29.0, 31.0)),
  ];

  static RegionInfo? findByName(String? name) {
    if (name == null) return null;
    for (final r in regions) {
      if (r.name == name || r.key == name) return r;
    }
    return null;
  }

  /// Deterministic per-record jitter so a region's points spread on the map
  /// instead of stacking on the same coordinate.
  static LatLng jitter(LatLng base, String seed) {
    final r = Random(seed.hashCode);
    final dLat = (r.nextDouble() - 0.5) * 0.22;
    final dLng = (r.nextDouble() - 0.5) * 0.22;
    return LatLng(base.latitude + dLat, base.longitude + dLng);
  }

  Future<String?> getUserRegion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userRegionKey);
  }

  Future<void> setUserRegion(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userRegionKey, name);
  }

  Future<void> clearUserRegion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userRegionKey);
  }
}
