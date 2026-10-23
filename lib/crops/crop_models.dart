import 'dart:math' as math;

/// What the app knows about growing one crop in South African conditions:
/// days from planting to harvest, how long it can stay in the field, how much
/// water it drinks per day, and its growth stages as fractions of the cycle.
class CropSpec {
  final String name;
  final String emoji;
  final int daysToHarvest;
  final int harvestWindowDays;

  /// Litres per square metre per day at peak (1 mm of water is 1 L per m²).
  final double peakMm;
  final List<(String, double)> stages; // name and the cycle fraction it ends at
  const CropSpec(this.name, this.emoji, this.daysToHarvest, this.harvestWindowDays,
      this.peakMm, this.stages);

  /// Water use rises through the season and dips as the crop matures.
  double mmAt(double progress) {
    if (progress < 0.15) return peakMm * 0.45;
    if (progress < 0.45) return peakMm * 0.8;
    if (progress < 0.85) return peakMm;
    return peakMm * 0.7;
  }
}

const _fruiting = [('Seedling', 0.15), ('Growing leaves', 0.45), ('Flowering', 0.65), ('Fruit filling', 1.0)];
const _leafy = [('Seedling', 0.2), ('Leaf growth', 0.75), ('Full size', 1.0)];
const _root = [('Seedling', 0.15), ('Tops growing', 0.5), ('Roots swelling', 1.0)];
const _grain = [('Seedling', 0.15), ('Growing', 0.5), ('Tasselling', 0.65), ('Grain filling', 1.0)];

const cropSpecs = <CropSpec>[
  CropSpec('Maize', '🌽', 120, 21, 5.5, _grain),
  CropSpec('Tomato', '🍅', 85, 35, 5.0, _fruiting),
  CropSpec('Spinach', '🥬', 45, 21, 4.0, _leafy),
  CropSpec('Cabbage', '🥗', 80, 21, 4.5, _leafy),
  CropSpec('Carrot', '🥕', 90, 28, 4.0, _root),
  CropSpec('Onion', '🧅', 120, 28, 4.0, _root),
  CropSpec('Potato', '🥔', 100, 21, 4.5, _root),
  CropSpec('Butternut', '🎃', 100, 35, 5.0, _fruiting),
  CropSpec('Beans', '🫘', 65, 14, 4.0, _fruiting),
  CropSpec('Peppers', '🫑', 90, 35, 4.5, _fruiting),
  CropSpec('Sweet potato', '🍠', 120, 28, 4.0, _root),
];

CropSpec specFor(String name) =>
    cropSpecs.firstWhere((c) => c.name == name, orElse: () => cropSpecs.first);

/// A watering setup on one plot. The app cannot switch a sprinkler on by
/// itself; this is the schedule the farmer runs, and the numbers the AI uses.
class SprinklerPlan {
  final bool enabled;
  final double litresPerMinute;
  final int minutesPerRun;
  final List<int> startHours; // 24h clock, e.g. [6, 17]
  const SprinklerPlan({
    this.enabled = false,
    this.litresPerMinute = 10,
    this.minutesPerRun = 20,
    this.startHours = const [6],
  });

  double get litresPerDay => enabled ? litresPerMinute * minutesPerRun * startHours.length : 0;

  /// The next start time after [now].
  DateTime? nextRun(DateTime now) {
    if (!enabled || startHours.isEmpty) return null;
    final sorted = [...startHours]..sort();
    for (final h in sorted) {
      final t = DateTime(now.year, now.month, now.day, h);
      if (t.isAfter(now)) return t;
    }
    return DateTime(now.year, now.month, now.day + 1, sorted.first);
  }

  SprinklerPlan copyWith({bool? enabled, double? litresPerMinute, int? minutesPerRun, List<int>? startHours}) =>
      SprinklerPlan(
        enabled: enabled ?? this.enabled,
        litresPerMinute: litresPerMinute ?? this.litresPerMinute,
        minutesPerRun: minutesPerRun ?? this.minutesPerRun,
        startHours: startHours ?? this.startHours,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'lpm': litresPerMinute,
        'minutes': minutesPerRun,
        'hours': startHours,
      };

  factory SprinklerPlan.fromJson(Map<String, dynamic> m) => SprinklerPlan(
        enabled: m['enabled'] as bool? ?? false,
        litresPerMinute: (m['lpm'] as num?)?.toDouble() ?? 10,
        minutesPerRun: (m['minutes'] as num?)?.toInt() ?? 20,
        startHours: [for (final h in (m['hours'] as List? ?? const [6])) (h as num).toInt()],
      );
}

/// One health scan of a plot. [severity] is 'green', 'orange' or 'red'.
class HealthCheck {
  final DateTime at;
  final String label;
  final String severity;
  const HealthCheck(this.at, this.label, this.severity);

  Map<String, dynamic> toJson() =>
      {'at': at.millisecondsSinceEpoch, 'label': label, 'severity': severity};

  factory HealthCheck.fromJson(Map<String, dynamic> m) => HealthCheck(
      DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
      m['label'] as String? ?? 'Unknown',
      m['severity'] as String? ?? 'green');
}

class CropPlot {
  final String id;
  final String crop;
  final String name;
  final DateTime plantedOn;
  final double areaM2;
  final SprinklerPlan sprinkler;
  final List<HealthCheck> checks; // newest first

  /// The harvest date the app gave when the crop was added. It is never updated,
  /// so it can be judged against the real harvest later.
  final DateTime? predictedOn;

  const CropPlot({
    required this.id,
    required this.crop,
    required this.name,
    required this.plantedOn,
    required this.areaM2,
    this.sprinkler = const SprinklerPlan(),
    this.checks = const [],
    this.predictedOn,
  });

  CropSpec get spec => specFor(crop);

  CropPlot copyWith({String? name, double? areaM2, DateTime? plantedOn, SprinklerPlan? sprinkler, List<HealthCheck>? checks}) =>
      CropPlot(
        id: id,
        crop: crop,
        name: name ?? this.name,
        plantedOn: plantedOn ?? this.plantedOn,
        areaM2: areaM2 ?? this.areaM2,
        sprinkler: sprinkler ?? this.sprinkler,
        checks: checks ?? this.checks,
        predictedOn: predictedOn,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'crop': crop,
        'name': name,
        'plantedOn': plantedOn.millisecondsSinceEpoch,
        'area': areaM2,
        'sprinkler': sprinkler.toJson(),
        'checks': [for (final c in checks) c.toJson()],
        if (predictedOn != null) 'predictedOn': predictedOn!.millisecondsSinceEpoch,
      };

  factory CropPlot.fromJson(Map<String, dynamic> m) => CropPlot(
        id: m['id'] as String,
        crop: m['crop'] as String,
        name: m['name'] as String? ?? '',
        plantedOn: DateTime.fromMillisecondsSinceEpoch((m['plantedOn'] as num).toInt()),
        areaM2: (m['area'] as num?)?.toDouble() ?? 100,
        sprinkler: m['sprinkler'] == null
            ? const SprinklerPlan()
            : SprinklerPlan.fromJson(Map<String, dynamic>.from(m['sprinkler'] as Map)),
        checks: [
          for (final c in (m['checks'] as List? ?? const []))
            HealthCheck.fromJson(Map<String, dynamic>.from(c as Map))
        ],
        predictedOn:
            m['predictedOn'] == null ? null : DateTime.fromMillisecondsSinceEpoch((m['predictedOn'] as num).toInt()),
      );
}

/// What the advisor concludes about a plot today.
class CropOutlook {
  final int daysGrowing;
  final double progress; // 0 to 1 of the cycle, adjusted for health and water
  final String stage;
  final int stageIndex;
  final int stageCount;
  final int daysToHarvest; // 0 when ready
  final int daysToHarvestHigh; // the late end of the range
  final DateTime harvestOn;
  final bool ready;
  final bool overdue;
  final int? healthScore; // null until scanned
  final double rate; // growth speed, 1.0 is on calendar
  final double? waterRatio; // supplied over needed, null without a sprinkler
  final double waterNeedLitresPerDay;
  final String confidence; // 'Low', 'Medium', 'High'
  final List<String> advice;
  const CropOutlook({
    required this.daysGrowing,
    required this.progress,
    required this.stage,
    required this.stageIndex,
    required this.stageCount,
    required this.daysToHarvest,
    required this.daysToHarvestHigh,
    required this.harvestOn,
    required this.ready,
    required this.overdue,
    required this.healthScore,
    required this.rate,
    required this.waterRatio,
    required this.waterNeedLitresPerDay,
    required this.confidence,
    required this.advice,
  });
}

/// The plant-health model. It is an agronomic estimate, not a trained neural
/// network: it starts from the crop calendar, then slows or speeds the clock
/// using what the farmer's own scans and watering say about this plot, and
/// widens its range when it has little evidence. It says so in the app.
class CropAdvisor {
  static double _severityFactor(String s) => switch (s) { 'red' => 0.68, 'orange' => 0.86, _ => 1.0 };

  /// Scans lose weight over two weeks, so old trouble stops counting.
  static double _recent(HealthCheck c, DateTime now) =>
      (1 - now.difference(c.at).inHours / (24 * 14)).clamp(0.0, 1.0);

  static int? healthScore(CropPlot p, DateTime now) {
    if (p.checks.isEmpty) return null;
    final c = p.checks.first;
    final penalty = switch (c.severity) { 'red' => 55, 'orange' => 28, _ => 0 };
    final fade = _recent(c, now); // trouble fades if nothing new is seen
    final days = now.difference(c.at).inDays;
    return (100 - penalty * (0.4 + 0.6 * fade) - math.min(days, 14) * 0.5).round().clamp(0, 100);
  }

  static CropOutlook assess(CropPlot p, DateTime now) {
    final spec = p.spec;
    final days = math.max(0, now.difference(p.plantedOn).inDays);

    // Health: blend recent scans, newest counting most.
    var healthF = 1.0;
    if (p.checks.isNotEmpty) {
      var w = 0.0, v = 0.0;
      for (var i = 0; i < math.min(3, p.checks.length); i++) {
        final c = p.checks[i];
        final weight = (3 - i) * _recent(c, now);
        w += weight;
        v += weight * _severityFactor(c.severity);
      }
      healthF = w == 0 ? 1.0 : v / w;
    }

    // Water: what the sprinkler supplies against what the crop needs today.
    final cycleProgress = (days / spec.daysToHarvest).clamp(0.0, 1.0);
    final need = p.areaM2 * spec.mmAt(cycleProgress);
    double? ratio;
    var waterF = 0.94; // rain-fed with no plan: a small, honest penalty
    if (p.sprinkler.enabled) {
      ratio = need == 0 ? 1 : p.sprinkler.litresPerDay / need;
      waterF = ratio < 0.6 ? 0.8 : ratio < 0.9 ? 0.93 : ratio <= 1.5 ? 1.0 : 0.95;
    }

    final rate = (healthF * waterF).clamp(0.5, 1.0);
    final effDays = days * rate;
    final progress = (effDays / spec.daysToHarvest).clamp(0.0, 1.0);
    final remaining = math.max(0.0, spec.daysToHarvest - effDays);
    final toHarvest = rate == 0 ? 0 : (remaining / rate).ceil();
    final evidence = p.checks.length + (p.sprinkler.enabled ? 1 : 0);
    final spread = evidence >= 3 ? 0.06 : evidence >= 1 ? 0.12 : 0.2;
    final high = (toHarvest * (1 + spread)).ceil() + (toHarvest > 0 ? 1 : 0);
    final ready = remaining <= 0;
    final overdue = ready && effDays > spec.daysToHarvest + spec.harvestWindowDays;

    var stageIndex = 0;
    for (var i = 0; i < spec.stages.length; i++) {
      if (progress >= spec.stages[i].$2 && i < spec.stages.length - 1) stageIndex = i + 1;
    }
    final stage = ready ? 'Ready to harvest' : spec.stages[stageIndex].$1;

    final advice = <String>[];
    final score = healthScore(p, now);
    final last = p.checks.isEmpty ? null : p.checks.first;
    if (last == null) {
      advice.add('Scan a leaf to start tracking the health of this plot. Until you do, the estimate comes from the crop calendar alone.');
    } else if (now.difference(last.at).inDays >= 7) {
      advice.add('Last scan was ${now.difference(last.at).inDays} days ago. Scan again this week.');
    }
    if (last != null && last.severity == 'red') {
      advice.add('${last.label} was urgent. Treat it now, then scan again in 3 days. It is slowing growth.');
    } else if (last != null && last.severity == 'orange') {
      advice.add('${last.label} needs attention soon. Follow the treatment steps and re-scan in a week.');
    }
    if (ratio != null) {
      if (ratio < 0.6) {
        advice.add('The sprinkler gives about ${(ratio * 100).round()}% of what this crop needs. Run it longer or add a second run.');
      } else if (ratio < 0.9) {
        advice.add('Watering is a little short at ${(ratio * 100).round()}% of need. Add a few minutes.');
      } else if (ratio > 1.5) {
        advice.add('Watering is ${(ratio * 100).round()}% of need. Too much invites root rot. Cut the run time.');
      }
    } else {
      advice.add('No sprinkler plan. The estimate assumes rain. Set one up to keep growth on track.');
    }
    if (ready && !overdue) {
      advice.add('Harvest within ${spec.harvestWindowDays} days for the best quality.');
    } else if (overdue) {
      advice.add('Past the best harvest window. Harvest now to avoid losses.');
    } else if (toHarvest <= 10) {
      advice.add('Harvest is close. Line up buyers on Nolifa Drop and pack material.');
    }

    return CropOutlook(
      daysGrowing: days,
      progress: progress,
      stage: stage,
      stageIndex: stageIndex,
      stageCount: spec.stages.length,
      daysToHarvest: toHarvest,
      daysToHarvestHigh: high,
      harvestOn: now.add(Duration(days: toHarvest)),
      ready: ready,
      overdue: overdue,
      healthScore: score,
      rate: rate,
      waterRatio: ratio,
      waterNeedLitresPerDay: need,
      confidence: evidence >= 3 ? 'High' : evidence >= 1 ? 'Medium' : 'Low',
      advice: advice,
    );
  }

  /// The sprinkler plan that meets today's need: total minutes split across
  /// morning and evening, which wastes less water than midday.
  static SprinklerPlan suggest(CropPlot p, DateTime now, {double litresPerMinute = 10}) {
    final days = math.max(0, now.difference(p.plantedOn).inDays);
    final need = p.areaM2 * p.spec.mmAt((days / p.spec.daysToHarvest).clamp(0.0, 1.0));
    final minutes = (need / litresPerMinute).ceil().clamp(5, 240);
    final runs = minutes > 45 ? 2 : 1;
    return SprinklerPlan(
      enabled: true,
      litresPerMinute: litresPerMinute,
      minutesPerRun: (minutes / runs).ceil(),
      startHours: runs == 2 ? const [6, 17] : const [6],
    );
  }
}
