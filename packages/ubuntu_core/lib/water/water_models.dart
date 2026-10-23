import 'package:flutter/material.dart';

/// How full a community's water supply is, from the provider's readings.
enum WaterStatus { healthy, watch, low, critical }

extension WaterStatusX on WaterStatus {
  static WaterStatus of(double level) {
    if (level >= 60) return WaterStatus.healthy;
    if (level >= 40) return WaterStatus.watch;
    if (level >= 20) return WaterStatus.low;
    return WaterStatus.critical;
  }

  String get label => switch (this) {
        WaterStatus.healthy => 'Healthy',
        WaterStatus.watch => 'Watch',
        WaterStatus.low => 'Low',
        WaterStatus.critical => 'Critical',
      };

  Color get color => switch (this) {
        WaterStatus.healthy => const Color(0xFF52D1A4),
        WaterStatus.watch => const Color(0xFFE8C23D),
        WaterStatus.low => const Color(0xFFE8A33D),
        WaterStatus.critical => const Color(0xFFFF6B6B),
      };

  /// Communities can ask for help once supply is low or critical.
  bool get canRequestHelp => this == WaterStatus.low || this == WaterStatus.critical;
}

/// One reservoir level reading, as a percentage of capacity.
class WaterReading {
  final DateTime at;
  final double level; // 0..100
  const WaterReading(this.at, this.level);
}

/// A community supplied from one reservoir, with the provider that runs it.
class WaterZone {
  final String id;
  final String name;
  final String provider;
  final String reservoir;
  final int population;
  final int voteThreshold; // distinct people needed to send the request on
  final List<WaterReading> readings; // oldest first, evenly spaced
  final bool demo;

  /// Where real readings come from (for example the DWS weekly report). Null for
  /// readings a provider published itself.
  final String? source;

  const WaterZone({
    required this.id,
    required this.name,
    required this.provider,
    required this.reservoir,
    required this.population,
    required this.voteThreshold,
    required this.readings,
    this.demo = false,
    this.source,
  });

  double get level => readings.isEmpty ? 0 : readings.last.level;
  DateTime? get updated => readings.isEmpty ? null : readings.last.at;
  WaterStatus get status => WaterStatusX.of(level);

  WaterZone withReadings(List<WaterReading> r) => WaterZone(
        id: id,
        name: name,
        provider: provider,
        reservoir: reservoir,
        population: population,
        voteThreshold: voteThreshold,
        readings: r,
        demo: demo,
        source: source,
      );
}

/// What the radar expects over the coming days.
class WaterForecast {
  /// Expected level at the end of each of the next days, 0..100.
  final List<double> days;

  /// Days until the level reaches Low (40%), Critical (20%) or empty. Null when
  /// the supply is stable or recovering.
  final double? daysToLow;
  final double? daysToCritical;
  final double? daysToEmpty;

  /// Percentage points per day (negative means falling).
  final double changePerDay;

  /// 0 to 1: how well the model has tracked recent readings.
  final double confidence;

  /// One plain sentence on why.
  final String why;

  const WaterForecast({
    required this.days,
    required this.daysToLow,
    required this.daysToCritical,
    required this.daysToEmpty,
    required this.changePerDay,
    required this.confidence,
    required this.why,
  });

  bool get falling => changePerDay < -0.3;
}

/// Where a community's request for help has got to.
enum IncidentStage { open, requested, acknowledged, dispatched, resolved }

extension IncidentStageX on IncidentStage {
  String get label => switch (this) {
        IncidentStage.open => 'Collecting votes',
        IncidentStage.requested => 'Sent to the provider',
        IncidentStage.acknowledged => 'Provider has seen it',
        IncidentStage.dispatched => 'Trucks on the way',
        IncidentStage.resolved => 'Resolved',
      };
}

class WaterIncident {
  final String id; // "<zoneId>-<epoch>"
  final String zoneId;
  final int epoch;
  final IncidentStage stage;
  final int votes;
  final int threshold;
  final DateTime openedAt;
  final DateTime? requestedAt;
  final DateTime? acknowledgedAt;
  final DateTime? dispatchedAt;
  final DateTime? resolvedAt;
  final int trucks;
  final int etaMinutes;
  final String note;

  const WaterIncident({
    required this.id,
    required this.zoneId,
    required this.epoch,
    required this.stage,
    required this.votes,
    required this.threshold,
    required this.openedAt,
    this.requestedAt,
    this.acknowledgedAt,
    this.dispatchedAt,
    this.resolvedAt,
    this.trucks = 0,
    this.etaMinutes = 0,
    this.note = '',
  });

  bool get active => stage != IncidentStage.resolved;
  double get progress => threshold == 0 ? 0 : (votes / threshold).clamp(0, 1).toDouble();

  WaterIncident copyWith({
    IncidentStage? stage,
    int? votes,
    DateTime? requestedAt,
    DateTime? acknowledgedAt,
    DateTime? dispatchedAt,
    DateTime? resolvedAt,
    int? trucks,
    int? etaMinutes,
    String? note,
  }) =>
      WaterIncident(
        id: id,
        zoneId: zoneId,
        epoch: epoch,
        stage: stage ?? this.stage,
        votes: votes ?? this.votes,
        threshold: threshold,
        openedAt: openedAt,
        requestedAt: requestedAt ?? this.requestedAt,
        acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
        dispatchedAt: dispatchedAt ?? this.dispatchedAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        trucks: trucks ?? this.trucks,
        etaMinutes: etaMinutes ?? this.etaMinutes,
        note: note ?? this.note,
      );
}

/// What happened when someone tried to add their voice.
enum VoteResult { counted, alreadyVoted, notEligible, notVerified }

/// What a person has told the app about their own situation. Private to them.
class WaterPrefs {
  final String? zoneId;
  final int household; // people at home
  final int tankLitres; // water stored on site
  final int herd; // livestock head, for farmers

  const WaterPrefs({this.zoneId, this.household = 4, this.tankLitres = 0, this.herd = 0});

  WaterPrefs copyWith({String? zoneId, int? household, int? tankLitres, int? herd}) => WaterPrefs(
        zoneId: zoneId ?? this.zoneId,
        household: household ?? this.household,
        tankLitres: tankLitres ?? this.tankLitres,
        herd: herd ?? this.herd,
      );
}
