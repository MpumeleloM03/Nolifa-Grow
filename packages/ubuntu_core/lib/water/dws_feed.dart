import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../roads/road_models.dart' show metresBetween;
import 'water_models.dart';

/// One dam from the Department of Water and Sanitation's weekly report.
class DamLevel {
  final String name;
  final String river;
  final double fsc; // full storage capacity, million cubic metres
  final double thisWeek; // percent full
  final double lastWeek;
  final double lastYear;
  const DamLevel(this.name, this.river, this.fsc, this.thisWeek, this.lastWeek, this.lastYear);

  Map<String, dynamic> toJson() =>
      {'n': name, 'r': river, 'f': fsc, 't': thisWeek, 'l': lastWeek, 'y': lastYear};

  factory DamLevel.fromJson(Map<String, dynamic> m) => DamLevel(m['n'] as String, m['r'] as String,
      (m['f'] as num).toDouble(), (m['t'] as num).toDouble(), (m['l'] as num).toDouble(), (m['y'] as num).toDouble());
}

class DwsReport {
  final DateTime date; // the week the readings are for
  final List<DamLevel> dams;
  const DwsReport(this.date, this.dams);

  Map<String, dynamic> toJson() => {'d': date.millisecondsSinceEpoch, 'dams': [for (final d in dams) d.toJson()]};

  factory DwsReport.fromJson(Map<String, dynamic> m) => DwsReport(
      DateTime.fromMillisecondsSinceEpoch((m['d'] as num).toInt()),
      [for (final d in (m['dams'] as List)) DamLevel.fromJson(Map<String, dynamic>.from(d as Map))]);
}

/// Reads the KwaZulu-Natal "State of Dams" page from dws.gov.za. Rows hold the
/// dam, river, full capacity and the level this week, last week and last year.
DwsReport parseDwsProvince(String html) {
  final title = RegExp(r'State of Dams on (\d{4})-(\d{2})-(\d{2})').firstMatch(html);
  if (title == null) throw const FormatException('not a State of Dams page');
  final date = DateTime(int.parse(title.group(1)!), int.parse(title.group(2)!), int.parse(title.group(3)!));
  final dams = <DamLevel>[];
  for (final row in RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true).allMatches(html)) {
    final cells = [
      for (final c in RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true).allMatches(row.group(1)!))
        c.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim()
    ].where((c) => c.isNotEmpty).toList();
    // Dam, River, Photo, Indicators, FSC, This Week, Last Week, Last Year
    if (cells.length < 8 || !cells.contains('Photo')) continue;
    final nums = [for (final c in cells.skip(cells.indexOf('Indicators') + 1).take(4)) double.tryParse(c.replaceAll('#', ''))];
    if (nums.length < 4 || nums.any((n) => n == null)) continue;
    dams.add(DamLevel(cells[0], cells[1], nums[0]!, nums[1]!, nums[2]!, nums[3]!));
  }
  if (dams.isEmpty) throw const FormatException('no dams found');
  return DwsReport(date, dams);
}

/// Which dams feed which part of KwaZulu-Natal. These are bulk supply dams: a
/// healthy dam does not mean every tap is running, which is why local reports
/// and community votes still matter.
class SupplySystem {
  final String id;
  final String name;
  final String provider;
  final List<String> dams;
  const SupplySystem(this.id, this.name, this.provider, this.dams);
}

const supplySystems = <String, SupplySystem>{
  'Greater Durban': SupplySystem('dws-durban', 'Greater Durban', 'eThekwini Water and Sanitation, supplied by the Umgeni system',
      ['Inanda Dam', 'Nagle Dam', 'Midmar Dam', 'Albert Falls Dam']),
  'KZN Midlands': SupplySystem('dws-midlands', 'KZN Midlands', 'Msunduzi and uMgungundlovu, supplied by the Upper Umgeni and Mooi systems',
      ['Midmar Dam', 'Albert Falls Dam', 'Spring Grove Dam', 'Mearns Dam']),
  'North Coast': SupplySystem('dws-northcoast', 'North Coast', 'iLembe, supplied by the Mdloti system', ['Hazelmere Dam']),
  'Zululand': SupplySystem('dws-zululand', 'Zululand', 'King Cetshwayo and Zululand districts, supplied by the Mhlathuze, Hluhluwe and Pongola systems',
      ['Goedertrouw Dam', 'Hluhluwe Dam', 'Pongolapoort Dam', 'Klipfontein Dam']),
  'Northern KZN': SupplySystem('dws-northern', 'Northern KZN', 'Newcastle and Uthukela, supplied by the Ngagane and Tugela systems',
      ['Ntshingwayo Dam', 'Zaaihoek Dam', 'Spioenkop Dam', 'Wagendrift Dam', 'Woodstock Dam']),
};

/// The middle of the area each supply system serves.
const systemCentres = <String, (double, double)>{
  'Greater Durban': (-29.86, 30.98),
  'KZN Midlands': (-29.55, 30.25),
  'North Coast': (-29.40, 31.15),
  'Zululand': (-28.75, 31.90),
  'Northern KZN': (-27.80, 30.00),
};

/// The supply system whose area a position is in, or null when it is further
/// than 120 km from every one (the real dam data only covers KwaZulu-Natal).
SupplySystem? nearestSystem(double lat, double lng) {
  String? best;
  var bd = double.infinity;
  for (final e in systemCentres.entries) {
    final d = metresBetween(lat, lng, e.value.$1, e.value.$2);
    if (d < bd) {
      bd = d;
      best = e.key;
    }
  }
  return best == null || bd > 120000 ? null : supplySystems[best];
}

/// Capacity-weighted level of a system's dams: the share of its total storage
/// that is full.
double systemLevel(SupplySystem s, List<DamLevel> dams, double Function(DamLevel) pick) {
  final mine = [for (final d in dams) if (s.dams.contains(d.name)) d];
  if (mine.isEmpty) return double.nan;
  final cap = mine.fold<double>(0, (a, d) => a + d.fsc);
  return mine.fold<double>(0, (a, d) => a + pick(d) * d.fsc) / cap;
}

/// Rain around a place, from Open-Meteo: what fell in the past week and what is
/// forecast for the next.
class RainOutlook {
  final double pastMm;
  final double nextMm;
  final double hotDays; // days at or above 30 C in the next week
  const RainOutlook(this.pastMm, this.nextMm, this.hotDays);
}

/// The forecast for a system from two weekly readings and the rain outlook.
/// Weekly data is thin, so confidence is low and the sentence says what it used.
WaterForecast forecastFromWeekly({
  required double thisWeek,
  required double lastWeek,
  required DateTime reportDate,
  RainOutlook? rain,
  int horizonDays = 7,
}) {
  var perDay = (thisWeek - lastWeek) / 7;
  final notes = <String>[];
  if (rain != null) {
    if (rain.nextMm >= 50) {
      perDay = perDay < 0.2 ? 0.2 : perDay;
      notes.add('heavy rain expected (${rain.nextMm.round()} mm)');
    } else if (rain.nextMm >= 25) {
      if (perDay < 0) perDay *= 0.5;
      notes.add('rain expected (${rain.nextMm.round()} mm)');
    } else if (rain.nextMm < 3 && rain.hotDays >= 3) {
      if (perDay < 0) perDay *= 1.3;
      notes.add('hot and dry week ahead');
    }
  }
  final days = [for (var d = 1; d <= horizonDays; d++) (thisWeek + perDay * d).clamp(0.0, 100.0)];
  double? until(double target) {
    if (thisWeek <= target) return 0;
    if (perDay >= -0.05) return null;
    return (thisWeek - target) / -perDay;
  }

  final stamp = '${reportDate.day}/${reportDate.month}';
  final trend = perDay < -0.05
      ? 'falling about ${(-perDay).toStringAsFixed(2)} points a day'
      : perDay > 0.05
          ? 'recovering about ${perDay.toStringAsFixed(2)} points a day'
          : 'steady';
  return WaterForecast(
    days: days,
    daysToLow: until(40),
    daysToCritical: until(20),
    daysToEmpty: until(0),
    changePerDay: perDay,
    confidence: 0.35,
    why: 'Dams were ${lastWeek.toStringAsFixed(1)}% full last week and ${thisWeek.toStringAsFixed(1)}% on $stamp (DWS), $trend'
        '${notes.isEmpty ? '' : ', with ${notes.join(' and ')}'}. Weekly readings only, so treat this as a guide.',
  );
}

/// A real reservoir reading and forecast for one region.
class FeedZone {
  final WaterZone zone;
  final WaterForecast forecast;
  const FeedZone(this.zone, this.forecast);
}

/// Where real water levels come from. Tests replace it.
abstract class WaterFeed {
  Future<List<FeedZone>> load();
}

class DwsWaterFeed implements WaterFeed {
  static const _url = 'https://www.dws.gov.za/Hydrology/Weekly/ProvinceWeek.aspx?region=KN';
  static const _cacheKey = 'dws_kn_report';

  @override
  Future<List<FeedZone>> load() async {
    final report = await _report();
    if (report == null) return const [];
    final out = <FeedZone>[];
    for (final e in supplySystems.entries) {
      final s = e.value;
      final now = systemLevel(s, report.dams, (d) => d.thisWeek);
      if (now.isNaN) continue;
      final before = systemLevel(s, report.dams, (d) => d.lastWeek);
      final rain = await _rain(e.key);
      final zone = WaterZone(
        id: s.id,
        name: s.name,
        provider: s.provider,
        reservoir: s.dams.join(', '),
        population: 0,
        voteThreshold: 50,
        readings: [
          WaterReading(report.date.subtract(const Duration(days: 7)), before.clamp(0, 100).toDouble()),
          WaterReading(report.date, now.clamp(0, 100).toDouble()),
        ],
        source: 'DWS weekly State of Dams, ${report.date.year}-${report.date.month.toString().padLeft(2, '0')}-${report.date.day.toString().padLeft(2, '0')}',
      );
      out.add(FeedZone(zone, forecastFromWeekly(thisWeek: now, lastWeek: before, reportDate: report.date, rain: rain)));
    }
    return out;
  }

  Future<DwsReport?> _report() async {
    try {
      final c = HttpClient()..userAgent = 'Nolifa/1.0 (community water radar)';
      final req = await c.getUrl(Uri.parse(_url)).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw HttpException('DWS ${res.statusCode}');
      final report = parseDwsProvince(await res.transform(utf8.decoder).join());
      (await SharedPreferences.getInstance()).setString(_cacheKey, jsonEncode(report.toJson()));
      return report;
    } catch (e) {
      debugPrint('water feed: using the last saved DWS report: $e');
      final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
      if (raw == null) return null;
      try {
        return DwsReport.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        return null;
      }
    }
  }

  static const _centres = systemCentres;

  Future<RainOutlook?> _rain(String region) async {
    final c = _centres[region];
    if (c == null) return null;
    try {
      final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${c.$1}&longitude=${c.$2}'
          '&daily=precipitation_sum,temperature_2m_max&past_days=7&forecast_days=7&timezone=auto');
      final cl = HttpClient();
      final req = await cl.getUrl(uri).timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final d = (jsonDecode(await res.transform(utf8.decoder).join()) as Map)['daily'] as Map;
      final rain = [for (final x in d['precipitation_sum'] as List) ((x as num?) ?? 0).toDouble()];
      final tmax = [for (final x in d['temperature_2m_max'] as List) ((x as num?) ?? 0).toDouble()];
      double sum(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);
      return RainOutlook(sum(rain.take(7)), sum(rain.skip(7)), tmax.skip(7).where((t) => t >= 30).length.toDouble());
    } catch (e) {
      debugPrint('water feed: no rain outlook: $e');
      return null;
    }
  }
}

/// The feed live mode uses. Demo mode never reads it.
final waterFeedProvider = Provider<WaterFeed?>((ref) => DwsWaterFeed());
