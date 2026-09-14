mport 'package:latlong2/latlong.dart';

import '../models/diagnosis_record.dart';
import '../models/disease_info.dart';
import 'region_service.dart';

/// A single point on the predictive map. May come from a real user scan
/// (`isLive == true`) or from seed/community data (`isLive == false`).
class MapPoint {
  final LatLng location;
  final String disease;
  final String region;
  final String severityColor; // green | orange | red | grey
  final DateTime date;
  final bool isLive;

  MapPoint({
    required this.location,
    required this.disease,
    required this.region,
    required this.severityColor,
    required this.date,
    required this.isLive,
  });
}

/// A region with elevated disease activity.
class Hotspot {
  final String region;
  final LatLng center;
  final int scanCount;
  final int urgentCount;
  final int moderateCount;
  final int healthyCount;
  final String dominantDisease;
  final String severityColor;

  const Hotspot({
    required this.region,
    required this.center,
    required this.scanCount,
    required this.urgentCount,
    required this.moderateCount,
    required this.healthyCount,
    required this.dominantDisease,
    required this.severityColor,
  });
}

class TrendingDisease {
  final String name;
  final int count;
  final String severityColor;

  const TrendingDisease(this.name, this.count, this.severityColor);
}

/// Predicted risk for a region based on rolling 7-day vs prior 7-day activity.
class RiskForecast {
  final String region;
  final LatLng center;
  final double riskScore; // 0..1
  final String trend; // 'rising' | 'stable' | 'declining'
  final int recentCount;
  final int previousCount;
  final double percentChange;

  const RiskForecast({
    required this.region,
    required this.center,
    required this.riskScore,
    required this.trend,
    required this.recentCount,
    required this.previousCount,
    required this.percentChange,
  });
}

class WeeklyPulse {
  final int recentTotal;
  final int previousTotal;
  final int recentUrgent;
  final int previousUrgent;
  final double percentChange;
  final String trend;

  const WeeklyPulse({
    required this.recentTotal,
    required this.previousTotal,
    required this.recentUrgent,
    required this.previousUrgent,
    required this.percentChange,
    required this.trend,
  });
}

class PredictiveInsights {
  final List<MapPoint> points;
  final List<Hotspot> hotspots;
  final List<TrendingDisease> trending;
  final List<RiskForecast> forecast;
  final WeeklyPulse pulse;
  final int liveScanCount;
  final int seedScanCount;
  final DateTime computedAt;

  const PredictiveInsights({
    required this.points,
    required this.hotspots,
    required this.trending,
    required this.forecast,
    required this.pulse,
    required this.liveScanCount,
    required this.seedScanCount,
    required this.computedAt,
  });
}

class PredictiveMappingService {
  PredictiveInsights compute({
    required List<DiagnosisRecord> history,
    List<MapPoint> seedPoints = const [],
    bool includeSeed = true,
  }) {
    final live = _buildLivePoints(history);
    final seed = includeSeed ? seedPoints : const <MapPoint>[];
    final allPoints = [...seed, ...live];

    final hotspots = _computeHotspots(history, seed);
    final trending = _trendingDiseases(history, seed);
    final forecast = _riskForecast(history, seed);
    final pulse = _weeklyPulse(history, seed);

    return PredictiveInsights(
      points: allPoints,
      hotspots: hotspots,
      trending: trending,
      forecast: forecast,
      pulse: pulse,
      liveScanCount: live.length,
      seedScanCount: seed.length,
      computedAt: DateTime.now(),
    );
  }

  List<MapPoint> _buildLivePoints(List<DiagnosisRecord> history) {
    final List<MapPoint> points = [];
    for (final record in history) {
      LatLng? loc;
      if (record.latitude != null && record.longitude != null) {
        loc = LatLng(record.latitude!, record.longitude!);
      } else if (record.region != null) {
        final r = RegionService.findByName(record.region);
        if (r != null) loc = RegionService.jitter(r.center, record.id);
      }
      if (loc == null) continue;
      final info = DiseaseDatabase.getInfo(record.label);
      points.add(MapPoint(
        location: loc,
        disease: info.plainName,
        region: record.region ?? 'Unknown',
        severityColor: info.severityColor,
        date: record.date,
        isLive: true,
      ));
    }
    return points;
  }

  List<Hotspot> _computeHotspots(
    List<DiagnosisRecord> history,
    List<MapPoint> seedPoints,
  ) {
    final Map<String, _RegionAgg> agg = {};

    void addPoint(String region, String severity, String diseaseName) {
      final r = RegionService.findByName(region);
      if (r == null) return;
      final a = agg.putIfAbsent(region, () => _RegionAgg(r.center));
      a.total++;
      switch (severity) {
        case 'red':
          a.urgent++;
          break;
        case 'orange':
          a.moderate++;
          break;
        case 'green':
          a.healthy++;
          break;
      }
      if (severity != 'green') {
        a.diseases[diseaseName] = (a.diseases[diseaseName] ?? 0) + 1;
      }
    }

    for (final rec in history) {
      if (rec.region == null) continue;
      final info = DiseaseDatabase.getInfo(rec.label);
      addPoint(rec.region!, info.severityColor, info.plainName);
    }
    for (final p in seedPoints) {
      addPoint(p.region, p.severityColor, p.disease);
    }

    final List<Hotspot> hotspots = [];
    for (final entry in agg.entries) {
      final a = entry.value;
      String dominant;
      if (a.diseases.isNotEmpty) {
        dominant = a.diseases.entries
            .reduce((x, y) => x.value > y.value ? x : y)
            .key;
      } else if (a.healthy > 0) {
        dominant = 'Healthy crops';
      } else {
        dominant = 'Mixed';
      }
      String severityColor;
      if (a.urgent >= 2) {
        severityColor = 'red';
      } else if (a.urgent + a.moderate >= 3) {
        severityColor = 'orange';
      } else if (a.total > 0 && a.healthy == a.total) {
        severityColor = 'green';
      } else if (a.urgent + a.moderate > 0) {
        severityColor = 'orange';
      } else {
        severityColor = 'green';
      }
      hotspots.add(Hotspot(
        region: entry.key,
        center: a.center,
        scanCount: a.total,
        urgentCount: a.urgent,
        moderateCount: a.moderate,
        healthyCount: a.healthy,
        dominantDisease: dominant,
        severityColor: severityColor,
      ));
    }
    hotspots.sort((a, b) {
      final ua = b.urgentCount.compareTo(a.urgentCount);
      if (ua != 0) return ua;
      final mu = (b.moderateCount + b.urgentCount)
          .compareTo(a.moderateCount + a.urgentCount);
      if (mu != 0) return mu;
      return b.scanCount.compareTo(a.scanCount);
    });
    return hotspots;
  }

  List<TrendingDisease> _trendingDiseases(
    List<DiagnosisRecord> history,
    List<MapPoint> seedPoints,
  ) {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final Map<String, int> counts = {};
    final Map<String, String> sev = {};

    for (final r in history) {
      if (!r.date.isAfter(cutoff)) continue;
      final info = DiseaseDatabase.getInfo(r.label);
      if (info.severityColor == 'green') continue;
      counts[info.plainName] = (counts[info.plainName] ?? 0) + 1;
      sev[info.plainName] = info.severityColor;
    }
    for (final p in seedPoints) {
      if (!p.date.isAfter(cutoff)) continue;
      if (p.severityColor == 'green') continue;
      counts[p.disease] = (counts[p.disease] ?? 0) + 1;
      sev[p.disease] = p.severityColor;
    }

    final list = counts.entries
        .map((e) => TrendingDisease(e.key, e.value, sev[e.key] ?? 'orange'))
        .toList();
    list.sort((a, b) => b.count.compareTo(a.count));
    return list.take(5).toList();
  }

  List<RiskForecast> _riskForecast(
    List<DiagnosisRecord> history,
    List<MapPoint> seedPoints,
  ) {
    final now = DateTime.now();
    final lastWeek = now.subtract(const Duration(days: 7));
    final twoWeeks = now.subtract(const Duration(days: 14));
    final Map<String, int> recent = {};
    final Map<String, int> previous = {};

    void bump(String region, DateTime date, String severity) {
      if (severity == 'green') return;
      if (date.isAfter(lastWeek)) {
        recent[region] = (recent[region] ?? 0) + 1;
      } else if (date.isAfter(twoWeeks)) {
        previous[region] = (previous[region] ?? 0) + 1;
      }
    }

    for (final r in history) {
      if (r.region == null) continue;
      final info = DiseaseDatabase.getInfo(r.label);
      bump(r.region!, r.date, info.severityColor);
    }
    for (final p in seedPoints) {
      bump(p.region, p.date, p.severityColor);
    }

    final allRegions = {...recent.keys, ...previous.keys};
    final List<RiskForecast> forecast = [];
    for (final region in allRegions) {
      final regionInfo = RegionService.findByName(region);
      if (regionInfo == null) continue;
      final r = recent[region] ?? 0;
      final p = previous[region] ?? 0;
      final intensity = (r / 5.0).clamp(0.0, 1.0);
      final growth = p == 0
          ? (r > 0 ? 1.0 : 0.0)
          : ((r - p) / p).clamp(-1.0, 1.0);
      final score = (0.6 * intensity + 0.4 * growth.clamp(0.0, 1.0))
          .clamp(0.0, 1.0);
      String trend;
      if (r > p) {
        trend = 'rising';
      } else if (r < p) {
        trend = 'declining';
      } else {
        trend = 'stable';
      }
      final pct = p == 0
          ? (r > 0 ? 100.0 : 0.0)
          : ((r - p) / p) * 100.0;
      forecast.add(RiskForecast(
        region: region,
        center: regionInfo.center,
        riskScore: score,
        trend: trend,
        recentCount: r,
        previousCount: p,
        percentChange: pct,
      ));
    }
    forecast.sort((a, b) => b.riskScore.compareTo(a.riskScore));
    return forecast;
  }

  WeeklyPulse _weeklyPulse(
    List<DiagnosisRecord> history,
    List<MapPoint> seedPoints,
  ) {
    final now = DateTime.now();
    final lastWeek = now.subtract(const Duration(days: 7));
    final twoWeeks = now.subtract(const Duration(days: 14));
    int recentTotal = 0, previousTotal = 0;
    int recentUrgent = 0, previousUrgent = 0;

    void bump(DateTime date, String severity) {
      if (date.isAfter(lastWeek)) {
        recentTotal++;
        if (severity == 'red') recentUrgent++;
      } else if (date.isAfter(twoWeeks)) {
        previousTotal++;
        if (severity == 'red') previousUrgent++;
      }
    }

    for (final r in history) {
      final info = DiseaseDatabase.getInfo(r.label);
      bump(r.date, info.severityColor);
    }
    for (final p in seedPoints) {
      bump(p.date, p.severityColor);
    }

    final pct = previousTotal == 0
        ? (recentTotal > 0 ? 100.0 : 0.0)
        : ((recentTotal - previousTotal) / previousTotal) * 100.0;
    final trend = recentTotal > previousTotal
        ? 'rising'
        : (recentTotal < previousTotal ? 'declining' : 'stable');

    return WeeklyPulse(
      recentTotal: recentTotal,
      previousTotal: previousTotal,
      recentUrgent: recentUrgent,
      previousUrgent: previousUrgent,
      percentChange: pct,
      trend: trend,
    );
  }
}

class _RegionAgg {
  final LatLng center;
  int total = 0;
  int urgent = 0;
  int moderate = 0;
  int healthy = 0;
  final Map<String, int> diseases = {};

  _RegionAgg(this.center);
}
