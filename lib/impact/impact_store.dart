import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecurePrefs;
import '../services/auth_service.dart';
import '../services/region_service.dart';
import '../weather/weather_models.dart';
import 'impact_models.dart';

/// What actually happened on past days. Open-Meteo serves the last week of
/// observed values from the same endpoint as the forecast.
abstract class ActualWeather {
  Future<Map<DateTime, (double rainMm, double maxC)>> lastDays(String region);
}

class OpenMeteoActuals implements ActualWeather {
  @override
  Future<Map<DateTime, (double, double)>> lastDays(String region) async {
    final c = (RegionService.findByName(region) ?? RegionService.regions.first).center;
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${c.latitude}&longitude=${c.longitude}'
        '&daily=temperature_2m_max,precipitation_sum&past_days=7&forecast_days=1&timezone=auto');
    final http = HttpClient();
    try {
      final req = await http.getUrl(uri).timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) throw HttpException('actuals ${res.statusCode}');
      return parseActuals(await res.transform(utf8.decoder).join());
    } finally {
      http.close();
    }
  }
}

Map<DateTime, (double, double)> parseActuals(String body) {
  final d = (jsonDecode(body) as Map)['daily'] as Map;
  final times = d['time'] as List;
  final rain = d['precipitation_sum'] as List;
  final max = d['temperature_2m_max'] as List;
  final out = <DateTime, (double, double)>{};
  for (var i = 0; i < times.length; i++) {
    if (rain[i] == null || max[i] == null) continue;
    final t = DateTime.parse(times[i] as String);
    out[DateTime(t.year, t.month, t.day)] = ((rain[i] as num).toDouble(), (max[i] as num).toDouble());
  }
  return out;
}

final actualWeatherProvider = Provider<ActualWeather>((ref) => OpenMeteoActuals());

/// The evidence ledger. It is kept sealed on the phone, one per account, and
/// only ever records things that happened: a farmer's verdict, a forecast and
/// what the weather then did, a logged harvest, water actually saved.
class ImpactStore extends Notifier<ImpactData> {
  String get _key => 'impact_${ref.read(currentUserProvider)?.uid ?? 'guest'}';
  Future<void> _ready = Future.value();

  @override
  ImpactData build() {
    ref.watch(currentUserProvider.select((u) => u?.uid));
    _ready = _load();
    return const ImpactData();
  }

  Future<void> _load() async {
    final raw = await SecurePrefs.getString(_key);
    if (raw == null) return;
    try {
      final saved = ImpactData.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      final ids = {for (final s in state.scans) s.id};
      state = ImpactData(
        scans: [...state.scans, for (final s in saved.scans) if (!ids.contains(s.id)) s],
        savings: [...state.savings, ...saved.savings],
        forecasts: _mergeForecasts(state.forecasts, saved.forecasts),
        harvests: [...state.harvests, ...saved.harvests],
      );
    } catch (_) {
      // An unreadable ledger starts again rather than crashing the page.
    }
  }

  List<ForecastPair> _mergeForecasts(List<ForecastPair> fresh, List<ForecastPair> old) {
    final days = {for (final f in fresh) f.day};
    return [...fresh, for (final f in old) if (!days.contains(f.day)) f];
  }

  Future<void> _save() async {
    final key = _key;
    final payload = jsonEncode(state.toJson());
    await _ready;
    await SecurePrefs.setString(key, payload);
  }

  void _set(ImpactData next) {
    state = next;
    _save();
  }

  /// Records or replaces the farmer's verdict on one scan.
  void rateScan(ScanFeedback f) => _set(ImpactData(
        scans: [f, for (final s in state.scans) if (s.id != f.id) s].take(500).toList(),
        savings: state.savings,
        forecasts: state.forecasts,
        harvests: state.harvests,
      ));

  ScanFeedback? verdictFor(String id) {
    for (final s in state.scans) {
      if (s.id == id) return s;
    }
    return null;
  }

  void addSaving(WaterSaving s) => _set(ImpactData(
        scans: state.scans,
        savings: [s, ...state.savings].take(500).toList(),
        forecasts: state.forecasts,
        harvests: state.harvests,
      ));

  void logHarvest(HarvestLog h) => _set(ImpactData(
        scans: state.scans,
        savings: state.savings,
        forecasts: state.forecasts,
        harvests: [h, ...state.harvests].take(200).toList(),
      ));

  /// Stores tomorrow onwards from a real forecast. A later forecast for the same
  /// day replaces the earlier one until the day arrives, so what is judged is
  /// the last forecast made before the day: a one-day-ahead call.
  void recordForecast(Forecast f, DateTime now) {
    if (f.demo || f.saved) return;
    final today = DateTime(now.year, now.month, now.day);
    final byDay = {for (final p in state.forecasts) p.day: p};
    for (final d in f.days) {
      final day = DateTime(d.date.year, d.date.month, d.date.day);
      if (!day.isAfter(today)) continue;
      final old = byDay[day];
      if (old != null && old.settled) continue;
      byDay[day] = ForecastPair(day, now, d.rainMm, d.maxC);
    }
    final kept = byDay.values.toList()..sort((a, b) => b.day.compareTo(a.day));
    _set(ImpactData(scans: state.scans, savings: state.savings, forecasts: kept.take(120).toList(), harvests: state.harvests));
  }

  /// Fills in what the weather actually did for forecasts whose day has passed.
  /// Quietly does nothing when offline.
  Future<int> settleForecasts(String region, DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final due = state.forecasts.where((f) => !f.settled && f.day.isBefore(today)).toList();
    if (due.isEmpty) return 0;
    Map<DateTime, (double, double)> actual;
    try {
      actual = await ref.read(actualWeatherProvider).lastDays(region);
    } catch (e) {
      debugPrint('impact: could not fetch observed weather: $e');
      return 0;
    }
    var n = 0;
    final next = [
      for (final f in state.forecasts)
        if (!f.settled && actual.containsKey(f.day) && f.day.isBefore(today))
          () {
            n++;
            final a = actual[f.day]!;
            return f.settle(a.$1, a.$2);
          }()
        else
          f
    ];
    if (n > 0) {
      _set(ImpactData(scans: state.scans, savings: state.savings, forecasts: next, harvests: state.harvests));
    }
    return n;
  }
}

final impactStoreProvider = NotifierProvider<ImpactStore, ImpactData>(ImpactStore.new);

/// Turns the labelled sample set on the Impact page on and off. It is never
/// saved and never mixed into the real ledger.
final impactSampleProvider = StateProvider<bool>((ref) => false);

/// A sample ledger for presentations, clearly marked on screen.
ImpactData sampleImpact(DateTime now) {
  final scans = <ScanFeedback>[];
  // 62 judged scans: 51 right overall, confident calls more often right.
  for (var i = 0; i < 62; i++) {
    final high = i % 5 != 0;
    final right = high ? i % 8 != 1 : i % 3 == 0;
    scans.add(ScanFeedback('s$i', now.subtract(Duration(days: i)), i % 4 == 0 ? 'animal' : 'crop', 'x', 'Sample', high ? 88 : 61,
        right ? Verdict.right : Verdict.wrong));
  }
  final today = DateTime(now.year, now.month, now.day);
  return ImpactData(
    scans: scans,
    savings: [
      for (var i = 0; i < 9; i++) WaterSaving(now.subtract(Duration(days: i * 3)), 'Tomato plot', 420.0 + i * 35, 'Rain forecast, run skipped'),
    ],
    forecasts: [
      for (var i = 1; i <= 21; i++)
        ForecastPair(today.subtract(Duration(days: i)), today.subtract(Duration(days: i + 1)), i % 4 == 0 ? 6 : 0.2, 24.0 + i % 5,
            actualRainMm: i % 6 == 0 ? 5.5 : (i % 4 == 0 ? 3 : 0), actualMaxC: 24.0 + i % 5 + (i % 3 == 0 ? 2 : -1)),
    ],
    harvests: [
      HarvestLog(now, 'Tomato plot', 'Tomato', today.subtract(const Duration(days: 12)), today.subtract(const Duration(days: 9))),
      HarvestLog(now, 'Spinach bed', 'Spinach', today.subtract(const Duration(days: 30)), today.subtract(const Duration(days: 31))),
    ],
  );
}
