import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_models.dart' show MarketAlert, AlertKind;
import '../market/market_store.dart';
import '../live/live_alerts.dart';
import '../live/location.dart';
import 'dws_feed.dart';
import 'water_forecast.dart';
import 'water_models.dart';
import 'water_repository.dart';

/// The shared water data. Each app overrides this with Firestore once Firebase
/// is connected; until then it is kept on the device.
final waterRepositoryProvider = Provider<WaterRepository>((ref) => LocalWaterRepository());

/// True when the signed-in person works for the water provider (the `utility`
/// permission). Apps override this from the sign-in token. In demo mode the
/// provider desk is open to everyone.
/// When true, only verified members (a verified farm, or a verified phone number)
/// can vote on a water request. This stops one person voting from many accounts.
final requireVerifiedVotesProvider = Provider<bool>((ref) => true);

final waterUtilityProvider = Provider<bool>((ref) => false);

class WaterState {
  final List<WaterZone> zones;
  final List<WaterIncident> incidents;
  final Map<String, WaterForecast> forecasts;
  final WaterPrefs prefs;
  final Set<String> myVotes; // incident ids this person voted in
  final bool demo;
  final bool dryRunning;
  final bool autopilot; // demo only: a pretend provider answers by itself

  /// The supply system nearest the user's real position, and whether they are
  /// outside the area the real dam data covers (KwaZulu-Natal for now).
  final String? locationZoneId;
  final bool outsideCoverage;

  const WaterState({
    this.zones = const [],
    this.incidents = const [],
    this.forecasts = const {},
    this.prefs = const WaterPrefs(),
    this.myVotes = const {},
    this.demo = true,
    this.dryRunning = false,
    this.autopilot = true,
    this.locationZoneId,
    this.outsideCoverage = false,
  });

  WaterState copyWith({
    List<WaterZone>? zones,
    List<WaterIncident>? incidents,
    Map<String, WaterForecast>? forecasts,
    WaterPrefs? prefs,
    Set<String>? myVotes,
    bool? demo,
    bool? dryRunning,
    bool? autopilot,
    String? locationZoneId,
    bool? outsideCoverage,
  }) =>
      WaterState(
        zones: zones ?? this.zones,
        incidents: incidents ?? this.incidents,
        forecasts: forecasts ?? this.forecasts,
        prefs: prefs ?? this.prefs,
        myVotes: myVotes ?? this.myVotes,
        demo: demo ?? this.demo,
        dryRunning: dryRunning ?? this.dryRunning,
        autopilot: autopilot ?? this.autopilot,
        locationZoneId: locationZoneId ?? this.locationZoneId,
        outsideCoverage: outsideCoverage ?? this.outsideCoverage,
      );

  /// The community this person belongs to: their choice, else the first one.
  WaterZone? get myZone {
    if (zones.isEmpty) return null;
    final id = prefs.zoneId;
    for (final z in zones) {
      if (z.id == id) return z;
    }
    // Then the supply system nearest where they really are.
    for (final z in zones) {
      if (!demo && z.id == locationZoneId) return z;
    }
    // Until they choose: the demo's home community, else the one in most need.
    for (final z in zones) {
      if (demo && z.id == 'umlazi') return z;
    }
    return ([...zones]..sort((a, b) => a.level.compareTo(b.level))).first;
  }

  WaterForecast? forecastOf(String zoneId) => forecasts[zoneId];
  WaterIncident? incidentOf(String zoneId) => activeIncidentFor(incidents, zoneId);
  bool votedIn(WaterIncident? i) => i != null && myVotes.contains(i.id);

  /// Incidents that have reached the provider and need an answer.
  List<WaterIncident> get providerQueue => [
        for (final i in incidents)
          if (i.stage == IncidentStage.requested || i.stage == IncidentStage.acknowledged) i
      ]..sort((a, b) => (a.requestedAt ?? a.openedAt).compareTo(b.requestedAt ?? b.openedAt));

  /// Incidents trucks are already heading to.
  List<WaterIncident> get inTransit =>
      [for (final i in incidents) if (i.stage == IncidentStage.dispatched) i];
}

const _simNames = ['Thandi', 'Sipho', 'Nomsa', 'Bheki', 'Zanele', 'Lwazi', 'Palesa', 'Musa'];

/// Hours between readings in the demo.
const _stepHours = 6;

List<WaterZone> demoWaterZones(DateTime now) {
  List<WaterReading> series(double start, double perDay, {double wobble = 0.5, int seed = 0}) {
    const n = 28; // seven days, four readings a day
    final perStep = perDay / (24 / _stepHours);
    return [
      for (var i = 0; i < n; i++)
        WaterReading(
          now.subtract(Duration(hours: _stepHours * (n - 1 - i))),
          (start + perStep * i + wobble * math.sin((i + seed) * 1.7)).clamp(0.0, 100.0),
        )
    ];
  }

  WaterZone z(String id, String name, String res, int pop, List<WaterReading> r) => WaterZone(
        id: id,
        name: name,
        provider: 'eThekwini Water (demo)',
        reservoir: res,
        population: pop,
        voteThreshold: 5,
        readings: r,
        demo: true,
      );

  return [
    z('umlazi', 'Umlazi', 'Umlazi Reservoir', 85000, series(52, -2.8, seed: 1)),
    z('kwamashu', 'KwaMashu', 'KwaMashu Reservoir', 64000, series(35, -2.2, seed: 2)),
    z('inanda', 'Inanda', 'Inanda Reservoir', 41000, series(60, -1.3, seed: 3)),
    z('pinetown', 'Pinetown', 'Pinetown Reservoir', 52000, series(70, -0.4, seed: 4)),
    z('chatsworth', 'Chatsworth', 'Chatsworth Reservoir', 58000, series(74, 0.0, seed: 5)),
  ];
}

class WaterStore extends Notifier<WaterState> {
  final _timers = <Timer>[];
  final _subs = <StreamSubscription<dynamic>>[];
  final _simmed = <String>{};
  late WaterRepository _live;
  late WaterRepository _active;
  LocalWaterRepository? _demoRepo;
  late String _uid;
  bool _disposed = false;
  bool _utility = false;
  bool _demo = true;
  int _epoch = 0; // bumps whenever the repository in use changes
  List<FeedZone> _feed = const []; // real reservoir levels, live mode only

  @override
  WaterState build() {
    _uid = ref.watch(marketUidProvider);
    _live = ref.watch(waterRepositoryProvider);
    _utility = ref.watch(waterUtilityProvider);
    _demo = ref.watch(marketProvider.select((s) => s.demoMode));
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      for (final t in _timers) {
        t.cancel();
      }
      _timers.clear();
      _simmed.clear();
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
    });
    ref.listen(userLocationProvider, (_, next) => _placeUser(next.valueOrNull), fireImmediately: true);
    Future.microtask(_attach);
    return WaterState(demo: _demo);
  }

  /// Picks the supply system nearest the phone's real position.
  void _placeUser((double, double)? loc) {
    if (loc == null) return;
    final sys = nearestSystem(loc.$1, loc.$2);
    state = state.copyWith(locationZoneId: sys?.id, outsideCoverage: sys == null);
  }

  /// Can this person act for the water provider?
  bool get isProvider => _demo || _utility;

  Future<void> _attach() async {
    if (_disposed) return;
    final epoch = ++_epoch;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    if (_demo) {
      _demoRepo ??= LocalWaterRepository.memory()..demoZones = true;
      await _seedDemo(_demoRepo!);
      _active = _demoRepo!;
    } else {
      _active = _live;
    }
    if (_disposed || epoch != _epoch) return;
    state = state.copyWith(demo: _demo, myVotes: const {});
    if (!_demo) _loadFeed(epoch);
    _subs
      ..add(_active.watchZones().listen((z) => _onZones(epoch, z), onError: _logErr))
      ..add(_active.watchIncidents().listen((i) => _onIncidents(epoch, i), onError: _logErr));
    // Personal details load in the background; the radar must not wait for them.
    _live.loadPrefs(_uid).then((prefs) {
      if (prefs != null && !_disposed && epoch == _epoch) state = state.copyWith(prefs: prefs);
    }).catchError((Object e) => debugPrint('water: could not load prefs: $e'));
  }

  void _logErr(Object e) => debugPrint('water sync error: $e');

  void _guard(Future<void> f) => f.catchError((Object e) => _logErr(e));

  Future<void> _seedDemo(LocalWaterRepository repo) async {
    final first = await repo.watchZones().first;
    if (first.isNotEmpty) return;
    for (final z in demoWaterZones(DateTime.now())) {
      await repo.upsertZone(z);
    }
  }

  List<WaterZone> _repoZones = const [];

  /// Real levels from the Department of Water and Sanitation, added next to any
  /// communities a provider published. Never used in demo mode.
  Future<void> _loadFeed(int epoch) async {
    final feed = ref.read(waterFeedProvider);
    if (feed == null) return;
    try {
      final zones = await feed.load();
      if (_disposed || epoch != _epoch) return;
      _feed = zones;
      _onZones(epoch, _repoZones);
    } catch (e) {
      _logErr(e);
    }
  }

  void _onZones(int epoch, List<WaterZone> zones) {
    if (_disposed || epoch != _epoch) return;
    _repoZones = zones;
    final real = [for (final f in _feed) if (!zones.any((z) => z.id == f.zone.id)) f];
    final sorted = [...zones, for (final f in real) f.zone]..sort((a, b) => a.name.compareTo(b.name));
    // The cloud copy of a dam zone is the shared one (votes and the provider
    // work on it), but the phone's own rain-adjusted forecast is richer than
    // two weekly points, so it keeps the feed's forecast for the same id.
    FeedZone? feedOf(String id) => _feed.where((f) => f.zone.id == id).firstOrNull;
    state = state.copyWith(zones: sorted, forecasts: {
      for (final z in sorted) z.id: feedOf(z.id)?.forecast ?? forecastWater(z.readings)
    });
  }

  Future<void> _onIncidents(int epoch, List<WaterIncident> incidents) async {
    if (_disposed || epoch != _epoch) return;
    state = state.copyWith(incidents: incidents);
    // Work out which active incidents this person already voted in.
    final voted = {...state.myVotes};
    for (final i in incidents.where((i) => i.active)) {
      if (voted.contains(i.id)) continue;
      try {
        if (await _active.hasVoted(i.id, _uid)) voted.add(i.id);
      } catch (e) {
        _logErr(e);
      }
    }
    if (_disposed || epoch != _epoch) return;
    if (voted.length != state.myVotes.length) state = state.copyWith(myVotes: voted);
    if (_demo) _runDemoDirector(incidents);
  }

  // ------------------------------------------------------------ people

  void selectZone(String id) {
    state = state.copyWith(prefs: state.prefs.copyWith(zoneId: id));
    _savePrefs();
  }

  void setHousehold(int n) {
    state = state.copyWith(prefs: state.prefs.copyWith(household: n.clamp(1, 30)));
    _savePrefs();
  }

  void setTank(int litres) {
    state = state.copyWith(prefs: state.prefs.copyWith(tankLitres: litres.clamp(0, 100000)));
    _savePrefs();
  }

  void setHerd(int head) {
    state = state.copyWith(prefs: state.prefs.copyWith(herd: head.clamp(0, 5000)));
    _savePrefs();
  }

  void _savePrefs() => _guard(_live.savePrefs(_uid, state.prefs));

  /// Adds this person's voice to their community's request for water.
  Future<VoteResult> vote({bool dryTaps = false}) async {
    final zone = state.myZone;
    if (zone == null) return VoteResult.notEligible;
    if (ref.read(requireVerifiedVotesProvider) && !ref.read(marketProvider).isVerifiedMember) {
      return VoteResult.notVerified;
    }
    final result = await _active.vote(zone, _uid, dryTaps: dryTaps);
    if (result == VoteResult.counted || result == VoteResult.alreadyVoted) {
      final i = activeIncidentFor(
          await _active.watchIncidents().first, zone.id);
      if (i != null && !_disposed) {
        state = state.copyWith(myVotes: {...state.myVotes, i.id});
      }
    }
    return result;
  }

  // ---------------------------------------------------- water provider

  // A refused write (a stale utility claim, an invalid payload) reaches the
  // caller, so the desk never reports trucks sent that the community cannot
  // see. Callers with nowhere to show an error wrap the call in [_guard].

  /// The provider has seen the request. Throws when the write is refused.
  Future<void> acknowledge(String incidentId) => _active.acknowledge(incidentId);

  /// Sends trucks to a community. Throws when the write is refused.
  Future<void> dispatch(String incidentId, {required int trucks, required int etaMinutes, String note = ''}) =>
      _active.dispatch(incidentId, trucks: trucks, etaMinutes: etaMinutes, note: note);

  /// Marks the trucks delivered. Throws when the write is refused.
  Future<void> resolve(String incidentId) => _active.resolve(incidentId);

  /// Publishes a reservoir reading. Throws when the write is refused.
  Future<void> publishReading(String zoneId, double level) => _active.publishReading(zoneId, level);

  /// Adds or replaces a community. A failure reaches the caller, so the form
  /// that adds a community can tell the provider it did not save.
  Future<void> upsertZone(WaterZone zone) => _active.upsertZone(zone);

  // -------------------------------------------------------------- demo

  /// Demo: the reservoir keeps falling, so the alerts, the vote and the
  /// provider response all play out in under a minute.
  void runDrySpell({String zoneId = 'umlazi'}) {
    if (!_demo || state.dryRunning) return;
    state = state.copyWith(dryRunning: true);
    _timers.add(Timer.periodic(const Duration(seconds: 2), (t) {
      final z = state.zones.where((z) => z.id == zoneId);
      if (_disposed || z.isEmpty || z.first.level <= 14) {
        t.cancel();
        if (!_disposed) state = state.copyWith(dryRunning: false);
        return;
      }
      _guard(publishReading(zoneId, z.first.level - 4));
    }));
  }

  void setAutopilot(bool on) => state = state.copyWith(autopilot: on);

  /// Demo: neighbours add their voices, and a pretend provider answers.
  void _runDemoDirector(List<WaterIncident> incidents) {
    for (final i in incidents) {
      if (i.stage == IncidentStage.open && _simmed.add('votes-${i.id}')) {
        var n = 0;
        _timers.add(Timer.periodic(const Duration(milliseconds: 1500), (t) async {
          final cur = activeIncidentFor(await _active.watchIncidents().first, i.zoneId);
          if (_disposed || cur == null || cur.id != i.id || cur.stage != IncidentStage.open) {
            t.cancel();
            return;
          }
          final zone = state.zones.firstWhere((z) => z.id == i.zoneId);
          await _active.vote(zone, 'sim-${_simNames[n % _simNames.length]}-$n');
          n++;
        }));
      }
      if (!state.autopilot) continue;
      if (i.stage == IncidentStage.requested && _simmed.add('ack-${i.id}')) {
        _timers.add(Timer(const Duration(seconds: 5), () {
          if (!_disposed && state.autopilot) _guard(acknowledge(i.id));
        }));
      }
      if ((i.stage == IncidentStage.requested || i.stage == IncidentStage.acknowledged) &&
          _simmed.add('dispatch-${i.id}')) {
        _timers.add(Timer(const Duration(seconds: 11), () {
          if (_disposed || !state.autopilot) return;
          final cur = activeIncidentFor(state.incidents, i.zoneId);
          if (cur != null && cur.id == i.id &&
              (cur.stage == IncidentStage.requested || cur.stage == IncidentStage.acknowledged)) {
            _guard(dispatch(i.id, trucks: 3, etaMinutes: 90, note: 'Tankers to the community tanks'));
          }
        }));
      }
    }
  }

  /// Demo: back to where it started.
  Future<void> resetDemo() async {
    if (!_demo) return;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _simmed.clear();
    _demoRepo = null;
    state = state.copyWith(dryRunning: false, myVotes: const {}, incidents: const []);
    await _attach();
  }
}

final waterProvider = NotifierProvider<WaterStore, WaterState>(WaterStore.new);

/// Water alerts for this person's own community, in the same shape as the other
/// alerts so every screen can show them.
final waterAlertsProvider = Provider<List<MarketAlert>>((ref) {
  final s = ref.watch(waterProvider);
  final zone = s.myZone;
  if (zone == null) return const [];
  final f = s.forecastOf(zone.id);
  final lvl = zone.level.round();
  final soon = f?.daysToCritical;
  final status = zone.status;
  if (!status.canRequestHelp && !(soon != null && soon < 5)) return const [];
  final incident = s.incidentOf(zone.id);
  final severity = status == WaterStatus.critical ? 2 : 1;
  final String title;
  final String body;
  if (incident != null && incident.stage == IncidentStage.dispatched) {
    title = '${incident.trucks} water trucks heading to ${zone.name}';
    body = 'Expected in about ${incident.etaMinutes} minutes. Have containers ready.';
  } else if (status.canRequestHelp) {
    title = '${zone.name} water is ${status.label.toLowerCase()} ($lvl%)';
    body = soon != null && soon > 0
        ? 'About ${soon.toStringAsFixed(1)} days until critical. Stock up and ask the provider for help.'
        : 'Supply is critical. Stock up now and ask the provider for trucks.';
  } else {
    title = 'Water radar: ${zone.name} may run low';
    body = 'Reservoir at $lvl% and falling. About ${soon!.toStringAsFixed(1)} days until critical.';
  }
  return [
    MarketAlert(
      id: 'w-${zone.id}',
      emoji: '💧',
      kind: AlertKind.water,
      title: title,
      body: body,
      area: zone.name,
      severity: severity,
      cta: 'Check water supply',
      trust: zone.demo ? 'Provider feed (demo)' : zone.provider,
    )
  ];
});

/// Every alert for this person: their water situation first, then the rest.
final allAlertsProvider = Provider<List<MarketAlert>>((ref) {
  final demo = ref.watch(marketProvider.select((s) => s.demoMode));
  final water = ref.watch(waterAlertsProvider);
  if (demo) return [...water, ...ref.watch(marketProvider.select((s) => s.alerts))];
  // Live: only what real sources say about where this person is.
  final all = [
    ...water,
    ...(ref.watch(weatherAlertsProvider).valueOrNull ?? const <MarketAlert>[]),
    ...ref.watch(roadAlertsProvider),
    ...ref.watch(caseAlertsProvider),
  ];
  return all..sort((a, b) => b.severity.compareTo(a.severity));
});
