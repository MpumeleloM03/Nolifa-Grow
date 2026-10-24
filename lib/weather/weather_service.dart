import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../crops/crop_store.dart';
import '../impact/impact_store.dart';
import '../models/cattle.dart';
import '../services/auth_service.dart';
import '../services/cattle_service.dart';
import '../services/region_service.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show userLocationProvider, userPlaceProvider;
import 'weather_models.dart';
import 'weather_threats.dart';

/// Gets the forecast for a region. Real data comes from Open-Meteo, which needs
/// no key. With no signal the last saved forecast is used, and with none at all
/// a clearly marked demo forecast, so the feature can always be shown.
class WeatherService {
  /// The forecast for a registered region, when the phone's position is not
  /// known.
  Future<Forecast> forecastFor(String region) async {
    final centre = (RegionService.findByName(region) ?? RegionService.regions.first).center;
    return forecastAt(region, centre.latitude, centre.longitude);
  }

  /// The forecast at an exact place. With no signal the last saved real
  /// forecast is used. With neither, this throws: the app shows that the
  /// weather is unavailable and never makes one up.
  Future<Forecast> forecastAt(String label, double lat, double lon) async {
    try {
      final f = await fetch(label, lat, lon);
      await _save(f);
      return f;
    } catch (e) {
      debugPrint('weather: using the saved forecast: $e');
    }
    final saved = await _load(label);
    if (saved != null) return saved.copyWith(saved: true);
    throw StateError('No forecast available and none saved');
  }

  @visibleForTesting
  Future<Forecast> fetch(String region, double lat, double lon) async {
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,et0_fao_evapotranspiration'
        '&past_days=$pastDays&forecast_days=7&timezone=auto');
    final c = HttpClient();
    try {
      final req = await c.getUrl(uri).timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) throw HttpException('weather ${res.statusCode}');
      return parseOpenMeteo(region, await res.transform(utf8.decoder).join(), pastDays: pastDays);
    } finally {
      c.close();
    }
  }

  Future<void> _save(Forecast f) async =>
      (await SharedPreferences.getInstance()).setString('forecast_${f.region}', jsonEncode(f.toJson()));

  Future<Forecast?> _load(String region) async {
    final raw = (await SharedPreferences.getInstance()).getString('forecast_$region');
    if (raw == null) return null;
    try {
      return Forecast.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }
}

/// How many past days to ask for. They tell the irrigation AI how much water
/// the soil has already lost.
const pastDays = 5;

/// Reads Open-Meteo's daily JSON into a forecast. The first [pastDays] rows are
/// days that already happened.
Forecast parseOpenMeteo(String region, String body, {int pastDays = 0}) {
  final d = (jsonDecode(body) as Map)['daily'] as Map;
  final times = d['time'] as List;
  double num0(List l, int i) => ((l[i] as num?) ?? 0).toDouble();
  final et0 = d['et0_fao_evapotranspiration'] as List?;
  DayForecast row(int i) => DayForecast(
        DateTime.parse(times[i] as String),
        num0(d['temperature_2m_min'] as List, i),
        num0(d['temperature_2m_max'] as List, i),
        num0(d['precipitation_sum'] as List, i),
        num0(d['precipitation_probability_max'] as List, i).round(),
        num0(d['wind_speed_10m_max'] as List, i),
        et0: et0 == null || et0[i] == null ? null : (et0[i] as num).toDouble(),
      );
  final cut = pastDays.clamp(0, times.length);
  return Forecast(
    region,
    [for (var i = cut; i < times.length; i++) row(i)],
    DateTime.now(),
    past: [for (var i = 0; i < cut; i++) row(i)],
  );
}

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());

/// The forecast for the signed-in farmer's region.
final forecastProvider = FutureProvider<Forecast>((ref) async {
  final loc = await ref.watch(userLocationProvider.future);
  if (loc != null) {
    final place = await ref.watch(userPlaceProvider.future) ?? 'Near you';
    return _forecastAtPlace(ref, place, loc.$1, loc.$2);
  }
  final region = ref.watch(currentUserProvider.select((u) => u?.region)) ?? '';
  return _forecastAndLog(ref, region.isEmpty ? 'Greater Durban' : region);
});

Future<Forecast> _forecastAtPlace(Ref ref, String place, double lat, double lon) async {
  final f = await ref.watch(weatherServiceProvider).forecastAt(place, lat, lon);
  if (!f.saved) {
    final impact = ref.read(impactStoreProvider.notifier);
    impact.recordForecast(f, DateTime.now());
    impact.settleForecasts(place, DateTime.now());
  }
  return f;
}

/// Gets the forecast and lets the impact ledger keep a copy to judge later.
Future<Forecast> _forecastAndLog(Ref ref, String region) async {
  final f = await ref.watch(weatherServiceProvider).forecastFor(region);
  if (!f.demo && !f.saved) {
    final impact = ref.read(impactStoreProvider.notifier);
    impact.recordForecast(f, DateTime.now());
    impact.settleForecasts(region, DateTime.now());
  }
  return f;
}

/// Threats to this farm in the next week, from the forecast and the crops grown.
final weatherThreatsProvider = Provider<List<WeatherThreat>>((ref) {
  final f = ref.watch(forecastProvider).valueOrNull;
  if (f == null) return const [];
  final region = (ref.watch(currentUserProvider.select((u) => u?.region)) ?? '').toLowerCase();
  final animals = ref.watch(herdProvider).valueOrNull?.where((c) => c.status == CattleStatus.active).length ?? 0;
  const coast = ['durban', 'coast', 'umhlanga', 'ballito', 'richards bay'];
  final humid = region.isEmpty || coast.any(region.contains);
  return assessWeather(f, ref.watch(cropStoreProvider), DateTime.now(), animals: animals, humidCoast: humid);
});
