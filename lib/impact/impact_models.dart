import 'dart:math' as math;

/// The farmer's judgement of a diagnosis, given after they have looked at the
/// plant or animal themselves.
enum Verdict { right, wrong, unsure }

class ScanFeedback {
  final String id;
  final DateTime at;
  final String kind; // 'crop' or 'animal'
  final String label;
  final String plainName;
  final double confidence; // 0 to 100, as the scanner reported it
  final Verdict verdict;
  const ScanFeedback(this.id, this.at, this.kind, this.label, this.plainName, this.confidence, this.verdict);

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'kind': kind,
        'label': label,
        'name': plainName,
        'conf': confidence,
        'verdict': verdict.name,
      };

  factory ScanFeedback.fromJson(Map<String, dynamic> m) => ScanFeedback(
        m['id'] as String,
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        m['kind'] as String? ?? 'crop',
        m['label'] as String? ?? '',
        m['name'] as String? ?? '',
        (m['conf'] as num?)?.toDouble() ?? 0,
        Verdict.values.firstWhere((v) => v.name == m['verdict'], orElse: () => Verdict.unsure),
      );
}

/// Water the AI chose not to use, confirmed by the farmer (rain came, soil was wet).
class WaterSaving {
  final DateTime at;
  final String plot;
  final double litres;
  final String reason;
  const WaterSaving(this.at, this.plot, this.litres, this.reason);

  Map<String, dynamic> toJson() => {'at': at.millisecondsSinceEpoch, 'plot': plot, 'l': litres, 'why': reason};

  factory WaterSaving.fromJson(Map<String, dynamic> m) => WaterSaving(
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        m['plot'] as String? ?? '',
        (m['l'] as num?)?.toDouble() ?? 0,
        m['why'] as String? ?? '',
      );
}

/// What we predicted for one day, and later what actually happened.
class ForecastPair {
  final DateTime day; // midnight, local
  final DateTime madeOn;
  final double predRainMm;
  final double predMaxC;
  final double? actualRainMm;
  final double? actualMaxC;
  const ForecastPair(this.day, this.madeOn, this.predRainMm, this.predMaxC, {this.actualRainMm, this.actualMaxC});

  bool get settled => actualRainMm != null && actualMaxC != null;

  /// A rain call is "rain" at 1 mm or more, which is what a farmer would notice.
  bool? get rainCallRight => settled ? (predRainMm >= 1) == (actualRainMm! >= 1) : null;

  ForecastPair settle(double rain, double maxC) =>
      ForecastPair(day, madeOn, predRainMm, predMaxC, actualRainMm: rain, actualMaxC: maxC);

  Map<String, dynamic> toJson() => {
        'day': day.millisecondsSinceEpoch,
        'made': madeOn.millisecondsSinceEpoch,
        'pr': predRainMm,
        'pt': predMaxC,
        'ar': actualRainMm,
        'at': actualMaxC,
      };

  factory ForecastPair.fromJson(Map<String, dynamic> m) => ForecastPair(
        DateTime.fromMillisecondsSinceEpoch((m['day'] as num).toInt()),
        DateTime.fromMillisecondsSinceEpoch((m['made'] as num).toInt()),
        (m['pr'] as num).toDouble(),
        (m['pt'] as num).toDouble(),
        actualRainMm: (m['ar'] as num?)?.toDouble(),
        actualMaxC: (m['at'] as num?)?.toDouble(),
      );
}

/// A harvest the farmer logged, against the date the advisor expected.
class HarvestLog {
  final DateTime at;
  final String plot;
  final String crop;
  final DateTime expectedOn;
  final DateTime actualOn;
  const HarvestLog(this.at, this.plot, this.crop, this.expectedOn, this.actualOn);

  int get daysOff => actualOn.difference(expectedOn).inDays;

  Map<String, dynamic> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'plot': plot,
        'crop': crop,
        'exp': expectedOn.millisecondsSinceEpoch,
        'act': actualOn.millisecondsSinceEpoch,
      };

  factory HarvestLog.fromJson(Map<String, dynamic> m) => HarvestLog(
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        m['plot'] as String? ?? '',
        m['crop'] as String? ?? '',
        DateTime.fromMillisecondsSinceEpoch((m['exp'] as num).toInt()),
        DateTime.fromMillisecondsSinceEpoch((m['act'] as num).toInt()),
      );
}

/// Everything the app has measured about itself on this phone.
class ImpactData {
  final List<ScanFeedback> scans;
  final List<WaterSaving> savings;
  final List<ForecastPair> forecasts;
  final List<HarvestLog> harvests;
  const ImpactData({
    this.scans = const [],
    this.savings = const [],
    this.forecasts = const [],
    this.harvests = const [],
  });

  bool get isEmpty => scans.isEmpty && savings.isEmpty && forecasts.isEmpty && harvests.isEmpty;

  Map<String, dynamic> toJson() => {
        'scans': [for (final s in scans) s.toJson()],
        'savings': [for (final s in savings) s.toJson()],
        'forecasts': [for (final f in forecasts) f.toJson()],
        'harvests': [for (final h in harvests) h.toJson()],
      };

  factory ImpactData.fromJson(Map<String, dynamic> m) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        [for (final e in (m[k] as List? ?? const [])) f(Map<String, dynamic>.from(e as Map))];
    return ImpactData(
      scans: list('scans', ScanFeedback.fromJson),
      savings: list('savings', WaterSaving.fromJson),
      forecasts: list('forecasts', ForecastPair.fromJson),
      harvests: list('harvests', HarvestLog.fromJson),
    );
  }
}

/// 95% Wilson score interval for k successes in n trials. Unlike the plain
/// "k out of n", it stays honest when n is small.
(double, double) wilson(int k, int n, {double z = 1.96}) {
  if (n == 0) return (0, 1);
  final p = k / n;
  final z2 = z * z;
  final centre = (p + z2 / (2 * n)) / (1 + z2 / n);
  final half = z * math.sqrt(p * (1 - p) / n + z2 / (4 * n * n)) / (1 + z2 / n);
  return ((centre - half).clamp(0.0, 1.0), (centre + half).clamp(0.0, 1.0));
}

/// Fewer than this and we say the sample is too small to claim anything.
const minSampleToClaim = 30;

class Rate {
  final int hits;
  final int n;
  const Rate(this.hits, this.n);
  double? get value => n == 0 ? null : hits / n;
  (double, double) get interval => wilson(hits, n);
  bool get claimable => n >= minSampleToClaim;
}

class ImpactSummary {
  final Rate scanAccuracy;
  final Rate highConfidence; // scans the scanner was 80%+ sure of
  final Rate lowConfidence;
  final int unsure;
  final double litresSaved;
  final int savingEvents;
  final Rate rainCalls;
  final double? tempMae;
  final int forecastDays;
  final int forecastPending;
  final int harvests;
  final double? harvestMaeDays;
  final double? harvestBiasDays; // positive means later than expected
  final int harvestWithin3;

  const ImpactSummary({
    required this.scanAccuracy,
    required this.highConfidence,
    required this.lowConfidence,
    required this.unsure,
    required this.litresSaved,
    required this.savingEvents,
    required this.rainCalls,
    required this.tempMae,
    required this.forecastDays,
    required this.forecastPending,
    required this.harvests,
    required this.harvestMaeDays,
    required this.harvestBiasDays,
    required this.harvestWithin3,
  });

  factory ImpactSummary.of(ImpactData d) {
    final judged = d.scans.where((s) => s.verdict != Verdict.unsure).toList();
    Rate rate(Iterable<ScanFeedback> l) => Rate(l.where((s) => s.verdict == Verdict.right).length, l.length);
    final settled = d.forecasts.where((f) => f.settled).toList();
    final tempErr = [for (final f in settled) (f.predMaxC - f.actualMaxC!).abs()];
    final h = d.harvests;
    return ImpactSummary(
      scanAccuracy: rate(judged),
      highConfidence: rate(judged.where((s) => s.confidence >= 80)),
      lowConfidence: rate(judged.where((s) => s.confidence < 80)),
      unsure: d.scans.length - judged.length,
      litresSaved: d.savings.fold(0.0, (a, s) => a + s.litres),
      savingEvents: d.savings.length,
      rainCalls: Rate(settled.where((f) => f.rainCallRight == true).length, settled.length),
      tempMae: tempErr.isEmpty ? null : tempErr.reduce((a, b) => a + b) / tempErr.length,
      forecastDays: settled.length,
      forecastPending: d.forecasts.length - settled.length,
      harvests: h.length,
      harvestMaeDays: h.isEmpty ? null : h.map((x) => x.daysOff.abs()).reduce((a, b) => a + b) / h.length,
      harvestBiasDays: h.isEmpty ? null : h.map((x) => x.daysOff).reduce((a, b) => a + b) / h.length,
      harvestWithin3: h.where((x) => x.daysOff.abs() <= 3).length,
    );
  }
}

/// A flat CSV of every measured event, for a funder, a mentor or a spreadsheet.
String impactCsv(ImpactData d) {
  String q(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
  String day(DateTime t) => t.toIso8601String().substring(0, 10);
  final rows = <String>['type,date,item,detail_1,detail_2,detail_3'];
  for (final s in d.scans) {
    rows.add([q('scan'), day(s.at), q(s.plainName), q(s.kind), q(s.confidence.toStringAsFixed(0)), q(s.verdict.name)].join(','));
  }
  for (final s in d.savings) {
    rows.add([q('water_saved'), day(s.at), q(s.plot), q(s.litres.toStringAsFixed(0)), q(s.reason), q('')].join(','));
  }
  for (final f in d.forecasts) {
    rows.add([
      q('forecast'),
      day(f.day),
      q('rain_mm_and_max_c'),
      q('${f.predRainMm.toStringAsFixed(1)} / ${f.predMaxC.toStringAsFixed(1)}'),
      q(f.settled ? '${f.actualRainMm!.toStringAsFixed(1)} / ${f.actualMaxC!.toStringAsFixed(1)}' : 'pending'),
      q(''),
    ].join(','));
  }
  for (final h in d.harvests) {
    rows.add([q('harvest'), day(h.actualOn), q('${h.crop} ${h.plot}'), q('expected ${day(h.expectedOn)}'), q('days_off ${h.daysOff}'), q('')].join(','));
  }
  return rows.join('\n');
}
