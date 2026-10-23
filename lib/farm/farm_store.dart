import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecurePrefs;
import '../crops/crop_store.dart';
import '../impact/impact_models.dart';
import '../impact/impact_store.dart';
import '../services/auth_service.dart';
import '../services/region_service.dart';
import '../weather/weather_service.dart';
import 'farm_models.dart';
import 'irrigation_ai.dart';

/// Opens a farm's water valve. The default talks to a smart valve or relay over
/// the farm's network; tests replace it.
abstract class ValveController {
  /// Opens the valve for [minutes]. Returns null on success, otherwise why not.
  Future<String?> open(IrrigationSystem system, int minutes);
}

/// Sends one web request. A link with `{minutes}` or `{seconds}` in it is called
/// with a GET (this is how a Shelly relay takes a timer). Any other link gets a
/// POST with a small JSON body.
class HttpValveController implements ValveController {
  @override
  Future<String?> open(IrrigationSystem system, int minutes) async {
    final url = system.valveUrl;
    if (url == null || url.trim().isEmpty) return 'No valve link is set for ${system.name}.';
    final filled = url.replaceAll('{minutes}', '$minutes').replaceAll('{seconds}', '${minutes * 60}');
    final uri = Uri.tryParse(filled);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return 'The valve link is not a web address.';
    final client = HttpClient();
    try {
      final isGet = filled != url;
      final req = await (isGet ? client.getUrl(uri) : client.postUrl(uri)).timeout(const Duration(seconds: 6));
      if (!isGet) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'action': 'open', 'minutes': minutes, 'zone': system.id}));
      }
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>();
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      return 'The valve answered with error ${res.statusCode}.';
    } catch (e) {
      debugPrint('valve: could not reach ${system.name}: $e');
      return 'Could not reach the valve. Is it on the same Wi-Fi?';
    } finally {
      client.close();
    }
  }
}

final valveControllerProvider = Provider<ValveController>((ref) => HttpValveController());

/// The farm's setup, soil checks and watering log, kept sealed on the phone.
class FarmStore extends Notifier<FarmProfile> {
  String get _key => 'farm_profile_${ref.read(currentUserProvider)?.uid ?? 'guest'}';
  Future<void> _ready = Future.value();
  int _seq = 0;

  @override
  FarmProfile build() {
    ref.watch(currentUserProvider.select((u) => u?.uid));
    _ready = _load();
    return const FarmProfile();
  }

  Future<void> _load() async {
    final raw = await SecurePrefs.getString(_key);
    if (raw == null) return;
    try {
      final saved = FarmProfile.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      // Anything changed while this was loading wins over the saved copy.
      if (state.hectares == 0 && state.systems.isEmpty && state.sources.isEmpty) state = saved;
    } catch (_) {
      // An unreadable save starts again rather than crashing the page.
    }
  }

  Future<void> _save() async {
    final key = _key;
    final payload = jsonEncode(state.toJson());
    await _ready;
    await SecurePrefs.setString(key, payload);
  }

  void _set(FarmProfile next) {
    state = next;
    _save();
  }

  String _id(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  void setBasics({double? hectares, SoilType? soil}) =>
      _set(state.copyWith(hectares: hectares, soil: soil));

  WaterSource addSource(WaterSourceKind kind, String name, {double capacityL = 0, double levelL = 0}) {
    final s = WaterSource(
      id: _id('src'),
      name: name.trim().isEmpty ? kind.label : name.trim(),
      kind: kind,
      capacityL: capacityL,
      levelL: levelL.clamp(0, capacityL > 0 ? capacityL : levelL),
      levelAt: kind == WaterSourceKind.tank ? DateTime.now() : null,
    );
    _set(state.copyWith(sources: [...state.sources, s]));
    return s;
  }

  void updateSource(WaterSource s) =>
      _set(state.copyWith(sources: [for (final x in state.sources) if (x.id == s.id) s else x]));

  void removeSource(String id) => _set(state.copyWith(
        sources: [for (final s in state.sources) if (s.id != id) s],
        systems: [
          for (final s in state.systems)
            if (s.sourceId == id) IrrigationSystem(id: s.id, name: s.name, kind: s.kind, flowLph: s.flowLph, valveUrl: s.valveUrl) else s
        ],
      ));

  IrrigationSystem addSystem(IrrigationKind kind, String name, double flowLph, {String? sourceId, String? valveUrl}) {
    final s = IrrigationSystem(
      id: _id('sys'),
      name: name.trim().isEmpty ? kind.label : name.trim(),
      kind: kind,
      flowLph: flowLph,
      sourceId: sourceId,
      valveUrl: valveUrl == null || valveUrl.trim().isEmpty ? null : valveUrl.trim(),
    );
    _set(state.copyWith(systems: [...state.systems, s]));
    return s;
  }

  void updateSystem(IrrigationSystem s) =>
      _set(state.copyWith(systems: [for (final x in state.systems) if (x.id == s.id) s else x]));

  void removeSystem(String id) => _set(state.copyWith(
        systems: [for (final s in state.systems) if (s.id != id) s],
        plotSystem: {for (final e in state.plotSystem.entries) if (e.value != id) e.key: e.value},
      ));

  void assign(String plotId, String? systemId) {
    final next = {...state.plotSystem};
    if (systemId == null) {
      next.remove(plotId);
    } else {
      next[plotId] = systemId;
    }
    _set(state.copyWith(plotSystem: next));
  }

  void soilCheck(String plotId, SoilFeel feel, {DateTime? at}) =>
      _set(state.copyWith(soilChecks: [SoilCheck(plotId, at ?? DateTime.now(), feel), ...state.soilChecks].take(200).toList()));

  /// Sets what is in a tank right now.
  void setTankLevel(String sourceId, double litres) {
    for (final s in state.sources) {
      if (s.id == sourceId && s.isTank) {
        updateSource(s.copyWith(levelL: litres.clamp(0, s.capacityL > 0 ? s.capacityL : litres), levelAt: DateTime.now()));
      }
    }
  }

  /// Records a watering and takes the water out of the tank it came from.
  void logRun(String plotId, double litres, {bool byValve = false, bool followedPlan = true, DateTime? at}) {
    final when = at ?? DateTime.now();
    var sources = state.sources;
    final sys = state.systemFor(plotId);
    if (sys?.sourceId != null) {
      sources = [
        for (final s in sources)
          if (s.id == sys!.sourceId && s.isTank) s.copyWith(levelL: (s.levelL - litres).clamp(0, double.infinity)) else s
      ];
    }
    _set(state.copyWith(
      sources: sources,
      runs: [IrrigationRun(plotId, when, litres, byValve: byValve, followedPlan: followedPlan), ...state.runs].take(300).toList(),
    ));
  }

  /// The farmer confirms they did not water on a day it rained. The litres a
  /// daily calendar would still have pumped that the rain covers count as saved.
  /// A dry day the soil simply held enough is only a delay, not a saving, so it
  /// counts for nothing.
  bool holdOff(String plotId, String plotName, PlotDay day) {
    final key = '$plotId|${dayKey(day.date)}';
    if (state.heldOff.contains(key) || day.action == DayAction.water || day.rainWorkLitres < 1) return false;
    _set(state.copyWith(heldOff: {...state.heldOff, key}));
    ref.read(impactStoreProvider.notifier).addSaving(
        WaterSaving(DateTime.now(), plotName, day.rainWorkLitres, 'Rain did the work, run skipped'));
    return true;
  }

  void setAutopilot(bool on) => _set(state.copyWith(autopilot: on));


  /// Opens the valve for a run the plan calls for. Returns null when it worked,
  /// otherwise the reason it did not.
  Future<String?> runNow(PlotPlan plan) async {
    final sys = plan.system;
    final today = plan.today;
    if (sys == null) return 'Pick an irrigation system for this plot first.';
    if (today.action != DayAction.water || today.minutes <= 0) return 'The plan does not call for water today.';
    final err = await ref.read(valveControllerProvider).open(sys, today.minutes);
    if (err != null) return err;
    logRun(plan.plot.id, today.litres, byValve: true);
    return null;
  }
}

final farmStoreProvider = NotifierProvider<FarmStore, FarmProfile>(FarmStore.new);

/// The latitude of the farmer's region, for estimating evaporation when the
/// weather source does not give it.
final farmLatitudeProvider = Provider<double>((ref) {
  final region = ref.watch(currentUserProvider.select((u) => u?.region)) ?? '';
  return (RegionService.findByName(region) ?? RegionService.regions.first).center.latitude;
});

/// Today's irrigation plan for every plot, or null while the weather loads.
final irrigationProvider = Provider<FarmIrrigation?>((ref) {
  final fc = ref.watch(forecastProvider).valueOrNull;
  if (fc == null) return null;
  final plots = ref.watch(cropStoreProvider);
  if (plots.isEmpty) return null;
  return planFarm(
    plots: plots,
    farm: ref.watch(farmStoreProvider),
    forecast: fc,
    now: DateTime.now(),
    latitude: ref.watch(farmLatitudeProvider),
  );
});

typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Starts the runs the plan calls for, if the farmer turned autopilot on. It
/// only works while the app is open, in the morning, and only for plots whose
/// system has a valve link. It never runs the same plot twice in a day.
///
/// Pass `ref.read` from a widget, or `container.read` in a test.
Future<List<String>> autopilotTick(Reader read, {DateTime? now}) async {
  final t = now ?? DateTime.now();
  final farm = read(farmStoreProvider);
  final plan = read(irrigationProvider);
  if (!farm.autopilot || plan == null) return const [];
  if (t.hour < 5 || t.hour >= 11) return const []; // water early, never in the heat of the day
  final started = <String>[];
  for (final p in plan.wateringToday) {
    final sys = p.system;
    if (sys == null || sys.valveUrl == null) continue;
    final already = farm.runs.any((r) => r.plotId == p.plot.id && dayKey(r.at) == dayKey(t));
    if (already) continue;
    final err = await read(farmStoreProvider.notifier).runNow(p);
    if (err == null) started.add(p.plot.name);
  }
  return started;
}
