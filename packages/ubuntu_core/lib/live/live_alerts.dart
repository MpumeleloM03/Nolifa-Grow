import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_models.dart';
import '../market/market_store.dart';
import '../roads/road_models.dart';
import '../roads/road_store.dart';
import 'location.dart';

/// One day of real weather at a place.
class WxDay {
  final DateTime date;
  final double minC;
  final double maxC;
  final double rainMm;
  final double windKmh;
  const WxDay(this.date, this.minC, this.maxC, this.rainMm, this.windKmh);
}

/// Where the weather comes from. Open-Meteo, no key. Tests replace it.
abstract class LiveWeather {
  Future<List<WxDay>> forecast(double lat, double lng);
}

class OpenMeteoLive implements LiveWeather {
  @override
  Future<List<WxDay>> forecast(double lat, double lng) async {
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max&forecast_days=3&timezone=auto');
    final c = HttpClient();
    try {
      final req = await c.getUrl(uri).timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) throw HttpException('weather ${res.statusCode}');
      final d = (jsonDecode(await res.transform(utf8.decoder).join()) as Map)['daily'] as Map;
      final t = d['time'] as List;
      double v(String k, int i) => (((d[k] as List)[i]) as num? ?? 0).toDouble();
      return [
        for (var i = 0; i < t.length; i++)
          WxDay(DateTime.parse(t[i] as String), v('temperature_2m_min', i), v('temperature_2m_max', i),
              v('precipitation_sum', i), v('wind_speed_10m_max', i))
      ];
    } finally {
      c.close();
    }
  }
}

final liveWeatherProvider = Provider<LiveWeather>((ref) => OpenMeteoLive());

String _dayWord(DateTime d, DateTime now) {
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  return diff <= 0 ? 'today' : diff == 1 ? 'tomorrow' : 'in $diff days';
}

/// Turns real forecast days into warnings. Thresholds: frost at 2 C or less
/// (hard frost at 0), heat at 35 C, heavy rain at 30 mm in a day, wind at 50
/// km/h. Nothing is shown when the weather is ordinary.
List<MarketAlert> weatherAlertsFor(List<WxDay> days, String area, DateTime now) {
  final out = <MarketAlert>[];
  for (final d in days) {
    final when = _dayWord(d.date, now);
    if (d.minC <= 2) {
      final hard = d.minC <= 0;
      out.add(MarketAlert(
        id: 'wx-frost-${d.date.day}',
        emoji: '❄️',
        kind: AlertKind.weather,
        title: hard ? 'Hard frost $when' : 'Frost risk $when',
        body: 'Lowest ${d.minC.toStringAsFixed(1)} C. Cover tender plants before sunset and bring animals in.',
        area: area,
        severity: hard ? 2 : 1,
        cta: 'See the forecast',
        farmSide: true,
        trust: 'Open-Meteo forecast',
      ));
    }
    if (d.maxC >= 35) {
      out.add(MarketAlert(
        id: 'wx-heat-${d.date.day}',
        emoji: '🔥',
        kind: AlertKind.weather,
        title: 'Very hot $when',
        body: 'Up to ${d.maxC.toStringAsFixed(0)} C. Water animals more, keep stock in shade and water crops early.',
        area: area,
        severity: 1,
        cta: 'See the forecast',
        farmSide: true,
        trust: 'Open-Meteo forecast',
      ));
    }
    if (d.rainMm >= 30) {
      out.add(MarketAlert(
        id: 'wx-rain-${d.date.day}',
        emoji: '🌧️',
        kind: AlertKind.weather,
        title: 'Heavy rain $when',
        body: '${d.rainMm.round()} mm expected. Low roads and rivers may flood, so deliveries can be late.',
        area: area,
        severity: d.rainMm >= 60 ? 2 : 1,
        cta: 'See the forecast',
        trust: 'Open-Meteo forecast',
      ));
    }
    if (d.windKmh >= 50) {
      out.add(MarketAlert(
        id: 'wx-wind-${d.date.day}',
        emoji: '💨',
        kind: AlertKind.weather,
        title: 'Strong wind $when',
        body: 'Gusts to ${d.windKmh.round()} km/h. Secure shade cloth, tunnels and loose items.',
        area: area,
        severity: 1,
        cta: 'See the forecast',
        trust: 'Open-Meteo forecast',
      ));
    }
  }
  return out;
}

/// Real weather warnings for where the user actually is.
final weatherAlertsProvider = FutureProvider<List<MarketAlert>>((ref) async {
  final loc = await ref.watch(userLocationProvider.future);
  if (loc == null) return const [];
  try {
    final days = await ref.watch(liveWeatherProvider).forecast(loc.$1, loc.$2);
    final place = await ref.watch(userPlaceProvider.future) ?? 'Near you';
    return weatherAlertsFor(days, place, DateTime.now());
  } catch (e) {
    debugPrint('alerts: no weather: $e');
    return const [];
  }
});

/// Warnings that drivers reported within 15 km of the user and are still live.
final roadAlertsProvider = Provider<List<MarketAlert>>((ref) {
  final loc = ref.watch(userLocationProvider).valueOrNull;
  if (loc == null) return const [];
  final now = ref.watch(roadClockProvider)();
  final near = ref.watch(roadProvider).near(loc.$1, loc.$2, 15000, now);
  return [
    for (final h in near.take(5))
      MarketAlert(
        id: 'road-${h.id}',
        emoji: h.kind.emoji,
        kind: AlertKind.road,
        title: '${h.kind.label} reported ${h.ageText(now)}',
        body: '${h.kind.advice}. ${(metresBetween(loc.$1, loc.$2, h.lat, h.lng) / 1000).toStringAsFixed(1)} km from you, '
            'seen by ${h.confirms.length} ${h.confirms.length == 1 ? 'driver' : 'drivers'}.',
        area: 'Near you',
        severity: h.kind == HazardKind.accident || h.kind == HazardKind.blocked || h.kind == HazardKind.flooding ? 2 : 1,
        cta: 'See road alerts',
        trust: 'Reported by drivers',
      )
  ];
});

/// Outbreak cases that neighbours confirmed. Only real, non-demo cases count.
final caseAlertsProvider = Provider<List<MarketAlert>>((ref) {
  final s = ref.watch(marketProvider);
  if (s.demoMode) return const [];
  return [
    for (final c in s.cases)
      if (c.stage == ReportStage.corroborated || c.stage == ReportStage.vetVerified)
        MarketAlert(
          id: 'case-${c.id}',
          emoji: c.emoji,
          kind: AlertKind.outbreak,
          title: c.title,
          body: '${c.confirmations} farms confirmed this. Check your own animals and crops.',
          area: c.area,
          severity: c.stage == ReportStage.vetVerified ? 2 : 1,
          cta: 'Scan now',
          farmSide: true,
          trust: c.stage == ReportStage.vetVerified ? 'Vet verified' : 'Confirmed by neighbours',
        )
  ];
});
