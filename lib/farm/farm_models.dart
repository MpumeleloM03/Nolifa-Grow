/// The ground the farm is on. It decides how much water the soil can hold.
enum SoilType {
  sand('Sandy', 'Drains fast, holds little. Water often, in small amounts.', 60),
  loam('Loam', 'The balanced middle. Holds water and drains well.', 120),
  clay('Clay', 'Holds a lot but soaks slowly. Water less often, and slowly.', 160);

  final String label;
  final String note;

  /// Millimetres of water the soil can hold for plants, per metre of root depth.
  final double mmPerMetre;
  const SoilType(this.label, this.note, this.mmPerMetre);

  static SoilType parse(String? raw) => SoilType.values.firstWhere((s) => s.name == raw, orElse: () => SoilType.loam);
}

enum WaterSourceKind {
  tank('Rain tank', '🛢️'),
  borehole('Borehole', '⛏️'),
  municipal('Municipal tap', '🚰'),
  river('River or dam', '🏞️');

  final String label;
  final String emoji;
  const WaterSourceKind(this.label, this.emoji);

  static WaterSourceKind parse(String? raw) =>
      WaterSourceKind.values.firstWhere((s) => s.name == raw, orElse: () => WaterSourceKind.tank);
}

/// Where the farm's water comes from. A tank has a size and a level; the other
/// kinds are limited by how much they give per day.
class WaterSource {
  final String id;
  final String name;
  final WaterSourceKind kind;
  final double capacityL; // tank size, or the most you may take in a day
  final double levelL; // tank content now. Unused for other kinds
  final DateTime? levelAt;

  const WaterSource({
    required this.id,
    required this.name,
    required this.kind,
    this.capacityL = 0,
    this.levelL = 0,
    this.levelAt,
  });

  bool get isTank => kind == WaterSourceKind.tank;

  WaterSource copyWith({String? name, double? capacityL, double? levelL, DateTime? levelAt}) => WaterSource(
        id: id,
        name: name ?? this.name,
        kind: kind,
        capacityL: capacityL ?? this.capacityL,
        levelL: levelL ?? this.levelL,
        levelAt: levelAt ?? this.levelAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'cap': capacityL,
        'level': levelL,
        'levelAt': levelAt?.millisecondsSinceEpoch,
      };

  factory WaterSource.fromJson(Map<String, dynamic> m) => WaterSource(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        kind: WaterSourceKind.parse(m['kind'] as String?),
        capacityL: (m['cap'] as num?)?.toDouble() ?? 0,
        levelL: (m['level'] as num?)?.toDouble() ?? 0,
        levelAt: m['levelAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch((m['levelAt'] as num).toInt()),
      );
}

/// How water gets to the plants. The efficiency is the share of what leaves the
/// pipe that the plants can actually use; the rest is lost to wind, run-off or
/// evaporation.
enum IrrigationKind {
  drip('Drip lines', '💧', 0.90),
  sprinkler('Sprinklers', '🌦️', 0.75),
  pivot('Centre pivot', '⭕', 0.85),
  flood('Flood or furrow', '🌊', 0.55),
  hand('Hose or watering can', '🚿', 0.60);

  final String label;
  final String emoji;
  final double efficiency;
  const IrrigationKind(this.label, this.emoji, this.efficiency);

  static IrrigationKind parse(String? raw) =>
      IrrigationKind.values.firstWhere((s) => s.name == raw, orElse: () => IrrigationKind.sprinkler);
}

class IrrigationSystem {
  final String id;
  final String name;
  final IrrigationKind kind;

  /// Litres per hour that come out when one plot is being watered.
  final double flowLph;
  final String? sourceId;

  /// A web address that opens the valve when sent a command, for a smart valve
  /// or relay. Null if the farmer waters by hand.
  final String? valveUrl;

  const IrrigationSystem({
    required this.id,
    required this.name,
    required this.kind,
    required this.flowLph,
    this.sourceId,
    this.valveUrl,
  });

  double get efficiency => kind.efficiency;

  IrrigationSystem copyWith({String? name, double? flowLph, String? sourceId, String? valveUrl, bool clearValve = false}) =>
      IrrigationSystem(
        id: id,
        name: name ?? this.name,
        kind: kind,
        flowLph: flowLph ?? this.flowLph,
        sourceId: sourceId ?? this.sourceId,
        valveUrl: clearValve ? null : (valveUrl ?? this.valveUrl),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'flow': flowLph,
        'source': sourceId,
        'valve': valveUrl,
      };

  factory IrrigationSystem.fromJson(Map<String, dynamic> m) => IrrigationSystem(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        kind: IrrigationKind.parse(m['kind'] as String?),
        flowLph: (m['flow'] as num?)?.toDouble() ?? 1000,
        sourceId: m['source'] as String?,
        valveUrl: m['valve'] as String?,
      );
}

/// How the farmer found the soil when they last felt it.
enum SoilFeel {
  dry('Dry', 'Crumbly, plants look tired'),
  ok('Fine', 'Damp when you dig a hand deep'),
  wet('Wet', 'Soggy or just rained');

  final String label;
  final String hint;
  const SoilFeel(this.label, this.hint);

  static SoilFeel parse(String? raw) => SoilFeel.values.firstWhere((s) => s.name == raw, orElse: () => SoilFeel.ok);
}

class SoilCheck {
  final String plotId;
  final DateTime at;
  final SoilFeel feel;
  const SoilCheck(this.plotId, this.at, this.feel);

  Map<String, dynamic> toJson() => {'plot': plotId, 'at': at.millisecondsSinceEpoch, 'feel': feel.name};

  factory SoilCheck.fromJson(Map<String, dynamic> m) => SoilCheck(
        m['plot'] as String,
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        SoilFeel.parse(m['feel'] as String?),
      );
}

/// A watering the farmer did, by hand or through a valve.
class IrrigationRun {
  final String plotId;
  final DateTime at;
  final double litres;
  final bool byValve;
  final bool followedPlan;
  const IrrigationRun(this.plotId, this.at, this.litres, {this.byValve = false, this.followedPlan = true});

  Map<String, dynamic> toJson() => {
        'plot': plotId,
        'at': at.millisecondsSinceEpoch,
        'l': litres,
        'valve': byValve,
        'plan': followedPlan,
      };

  factory IrrigationRun.fromJson(Map<String, dynamic> m) => IrrigationRun(
        m['plot'] as String,
        DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        (m['l'] as num?)?.toDouble() ?? 0,
        byValve: m['valve'] as bool? ?? false,
        followedPlan: m['plan'] as bool? ?? true,
      );
}

/// Everything about the farm itself that the irrigation AI needs.
class FarmProfile {
  final double hectares;
  final SoilType soil;
  final List<WaterSource> sources;
  final List<IrrigationSystem> systems;

  /// Which system waters which plot.
  final Map<String, String> plotSystem;
  final List<SoilCheck> soilChecks;
  final List<IrrigationRun> runs;

  /// Plan days the farmer confirmed they held off watering. Keys are
  /// `plotId|yyyy-mm-dd`.
  final Set<String> heldOff;

  /// Whether the AI sends valve commands by itself when a run is due.
  final bool autopilot;

  const FarmProfile({
    this.hectares = 0,
    this.soil = SoilType.loam,
    this.sources = const [],
    this.systems = const [],
    this.plotSystem = const {},
    this.soilChecks = const [],
    this.runs = const [],
    this.heldOff = const {},
    this.autopilot = false,
  });

  bool get isSetUp => hectares > 0 && systems.isNotEmpty;

  IrrigationSystem? systemFor(String plotId) {
    final id = plotSystem[plotId];
    for (final s in systems) {
      if (s.id == id) return s;
    }
    return null;
  }

  WaterSource? sourceOf(IrrigationSystem s) {
    for (final w in sources) {
      if (w.id == s.sourceId) return w;
    }
    return null;
  }

  FarmProfile copyWith({
    double? hectares,
    SoilType? soil,
    List<WaterSource>? sources,
    List<IrrigationSystem>? systems,
    Map<String, String>? plotSystem,
    List<SoilCheck>? soilChecks,
    List<IrrigationRun>? runs,
    Set<String>? heldOff,
    bool? autopilot,
  }) =>
      FarmProfile(
        hectares: hectares ?? this.hectares,
        soil: soil ?? this.soil,
        sources: sources ?? this.sources,
        systems: systems ?? this.systems,
        plotSystem: plotSystem ?? this.plotSystem,
        soilChecks: soilChecks ?? this.soilChecks,
        runs: runs ?? this.runs,
        heldOff: heldOff ?? this.heldOff,
        autopilot: autopilot ?? this.autopilot,
      );

  Map<String, dynamic> toJson() => {
        'ha': hectares,
        'soil': soil.name,
        'sources': [for (final s in sources) s.toJson()],
        'systems': [for (final s in systems) s.toJson()],
        'plotSystem': plotSystem,
        'checks': [for (final c in soilChecks) c.toJson()],
        'runs': [for (final r in runs) r.toJson()],
        'held': heldOff.toList(),
        'auto': autopilot,
      };

  factory FarmProfile.fromJson(Map<String, dynamic> m) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        [for (final e in (m[k] as List? ?? const [])) f(Map<String, dynamic>.from(e as Map))];
    return FarmProfile(
      hectares: (m['ha'] as num?)?.toDouble() ?? 0,
      soil: SoilType.parse(m['soil'] as String?),
      sources: list('sources', WaterSource.fromJson),
      systems: list('systems', IrrigationSystem.fromJson),
      plotSystem: {for (final e in ((m['plotSystem'] as Map?) ?? const {}).entries) e.key as String: e.value as String},
      soilChecks: list('checks', SoilCheck.fromJson),
      runs: list('runs', IrrigationRun.fromJson),
      heldOff: {for (final h in (m['held'] as List? ?? const [])) h as String},
      autopilot: m['auto'] as bool? ?? false,
    );
  }
}

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
