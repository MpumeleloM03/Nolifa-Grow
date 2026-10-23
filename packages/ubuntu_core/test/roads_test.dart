import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'shared_fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

final _t0 = DateTime(2026, 10, 23, 9);

RoadHazard _h(String id, HazardKind k, double lat, double lng,
        {int ageMin = 0, List<String> yes = const ['r'], List<String> no = const []}) =>
    RoadHazard(
        id: id,
        kind: k,
        lat: lat,
        lng: lng,
        reportedAt: _t0.subtract(Duration(minutes: ageMin)),
        lastSeen: _t0.subtract(Duration(minutes: ageMin)),
        reporter: 'r',
        confirms: yes,
        denies: no);

ProviderContainer _box({bool verified = true, DateTime Function()? clock}) {
  final c = ProviderContainer(overrides: [
    marketUidProvider.overrideWithValue('u-me'),
    marketNameProvider.overrideWithValue('Sipho'),
    marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
    roadRepositoryProvider.overrideWithValue(LocalRoadRepository.memory(clock: clock ?? () => _t0, seeds: false)),
    roadClockProvider.overrideWithValue(clock ?? () => _t0),
    roadCanReportProvider.overrideWithValue(verified),
  ]);
  addTearDown(c.dispose);
  return c;
}

// The test font renders every glyph a full em wide, so rows overflow here that
// fit on a phone. Ignore only those.
void _ignoreFontOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('lifetime', () {
    test('a pothole lasts days, a crash lasts hours', () {
      expect(_h('a', HazardKind.pothole, 0, 0, ageMin: 60 * 48).activeAt(_t0), isTrue);
      expect(_h('b', HazardKind.accident, 0, 0, ageMin: 60 * 3).activeAt(_t0), isFalse);
      expect(_h('c', HazardKind.accident, 0, 0, ageMin: 60).activeAt(_t0), isTrue);
    });

    test('another driver seeing it renews the clock', () {
      final old = _h('a', HazardKind.accident, 0, 0, ageMin: 100);
      final renewed = old.seenBy('v2', _t0);
      expect(renewed.expiresAt.isAfter(old.expiresAt), isTrue);
      expect(renewed.confirms, ['r', 'v2']);
    });

    test('two "gone" votes outweighing the sightings take it down', () {
      var h = _h('a', HazardKind.pothole, 0, 0);
      h = h.notThere('x');
      expect(h.activeAt(_t0), isTrue);
      h = h.notThere('y');
      expect(h.disproved, isTrue);
      expect(h.activeAt(_t0), isFalse);
    });

    test('the reporter\'s own sighting cannot be erased by saying gone', () {
      final h = _h('a', HazardKind.pothole, 0, 0).notThere('r');
      expect(h.confirms, contains('r'));
    });
  });

  group('geometry', () {
    test('a degree of latitude is about 111 km', () {
      expect(metresBetween(-30, 31, -29, 31), closeTo(111195, 300));
    });

    // A straight road going north from Umlazi, a point every ~100 m.
    final road = [for (var i = 0; i <= 100; i++) (-29.9700 + i * 0.0009, 30.8860)];

    test('only warnings on the route and ahead of the driver count, nearest first', () {
      final me = road[10];
      final onRoadFar = _h('far', HazardKind.flooding, road[60].$1, road[60].$2 + 0.0002);
      final onRoadNear = _h('near', HazardKind.pothole, road[30].$1, road[30].$2);
      final behind = _h('behind', HazardKind.police, road[3].$1, road[3].$2);
      final offRoute = _h('off', HazardKind.accident, road[40].$1, road[40].$2 + 0.01); // ~1 km sideways
      final out = hazardsAhead(road, me, [onRoadFar, offRoute, behind, onRoadNear]);
      expect([for (final a in out) a.hazard.id], ['near', 'far']);
      expect(out.first.metresAhead, closeTo(2000, 60));
      expect(out.first.distanceText, '2.0 km');
    });

    test('distance text rounds sensibly under a kilometre', () {
      expect(HazardAhead(_h('a', HazardKind.pothole, 0, 0), 430).distanceText, '450 m');
      expect(HazardAhead(_h('a', HazardKind.pothole, 0, 0), 10).distanceText, 'a moment');
    });

    test('a one-point route has nothing ahead', () {
      expect(hazardsAhead([(0, 0)], (0, 0), [_h('a', HazardKind.pothole, 0, 0)]), isEmpty);
    });
  });

  group('store', () {
    test('a verified driver reports and the warning is live', () async {
      final c = _box();
      c.read(roadProvider);
      await _settle();
      final out = await c.read(roadProvider.notifier).report(HazardKind.flooding, -29.97, 30.88, note: ' low bridge ');
      expect(out, ReportOutcome.created);
      await _settle();
      final live = c.read(roadProvider).live(_t0);
      expect(live.length, 1);
      expect(live.single.note, 'low bridge');
      expect(live.single.confirms, ['u-me']);
    });

    test('an unverified account cannot report, confirm or reject', () async {
      final c = _box(verified: false);
      c.read(roadProvider);
      await _settle();
      expect(await c.read(roadProvider.notifier).report(HazardKind.pothole, 0, 0), ReportOutcome.notAllowed);
      expect(await c.read(roadProvider.notifier).confirm('x'), isFalse);
      expect(await c.read(roadProvider.notifier).deny('x'), isFalse);
      expect(c.read(roadProvider).hazards, isEmpty);
    });

    test('the same hazard reported again nearby is one hazard with two sightings', () async {
      final c = _box();
      c.read(roadProvider);
      final s = c.read(roadProvider.notifier);
      await s.report(HazardKind.pothole, -29.9700, 30.8860);
      await _settle();
      // 60 m away, same kind.
      expect(await s.report(HazardKind.pothole, -29.97054, 30.8860), ReportOutcome.merged);
      await _settle();
      expect(c.read(roadProvider).live(_t0).length, 1);
      // A different kind at the same spot is a different warning.
      expect(await s.report(HazardKind.flooding, -29.9700, 30.8860), ReportOutcome.created);
      await _settle();
      expect(c.read(roadProvider).live(_t0).length, 2);
    });

    test('warnings age out of the live list', () async {
      final c = _box();
      c.read(roadProvider);
      await c.read(roadProvider.notifier).report(HazardKind.police, 0, 0);
      await _settle();
      expect(c.read(roadProvider).live(_t0).length, 1);
      expect(c.read(roadProvider).live(_t0.add(const Duration(hours: 2))), isEmpty);
    });

    test('real reports survive a restart, samples never reach the disk', () async {
      final kv = MemoryKv();
      final a = LocalRoadRepository(kv: kv, clock: () => _t0);
      final first = await a.watch().first;
      expect(first.every((h) => h.demo), isTrue);
      expect(first, isNotEmpty);
      await a.save(_h('mine', HazardKind.pothole, -29.9, 30.9));
      final raw = (await kv.read('road_hazards_v1'))!;
      expect(raw, contains('mine'));
      expect(raw, isNot(contains('sample-')));
      final b = LocalRoadRepository(kv: kv, clock: () => _t0);
      final again = await b.watch().first;
      expect(again.map((h) => h.id), contains('mine'));
    });
  });

  group('shared backend', () {
    test('two phones see each other\'s warnings and sightings', () async {
      final db = SharedRoadDb();
      final a = FakeSharedRoadRepository(db, clock: () => _t0);
      final b = FakeSharedRoadRepository(db, clock: () => _t0);
      expect(a.shared, isTrue);
      final seenOnB = b.watch();
      final done = expectLater(
        seenOnB,
        emitsThrough(predicate<List<RoadHazard>>((l) => l.length == 1 && l.single.confirms.length == 2)),
      );
      final h = _h('h1', HazardKind.flooding, -29.9, 30.9);
      await a.save(h);
      await b.save(h.seenBy('v2', _t0));
      await done;
    });

    test('warnings older than any kind can live are not listened to', () async {
      final db = SharedRoadDb();
      final repo = FakeSharedRoadRepository(db, clock: () => _t0);
      await repo.save(_h('old', HazardKind.pothole, 0, 0, ageMin: 60 * 80));
      await repo.save(_h('new', HazardKind.pothole, 0, 0, ageMin: 5));
      final list = await repo.watch().first;
      expect(list.map((h) => h.id), ['new']);
    });
  });

  group('screens', () {
    Future<ProviderContainer> mount(WidgetTester t, Widget page, {bool verified = true, (double, double)? where}) async {
      _ignoreFontOverflow();
      t.view.physicalSize = const Size(1206, 3000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final c = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('u-me'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        roadRepositoryProvider.overrideWithValue(LocalRoadRepository.memory(clock: () => _t0)),
        roadClockProvider.overrideWithValue(() => _t0),
        roadCanReportProvider.overrideWithValue(verified),
        reportLocationProvider.overrideWithValue(() async => where),
      ]);
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
          container: c, child: MaterialApp(theme: AppTheme.build(), home: Scaffold(body: page))));
      await t.pump(const Duration(milliseconds: 400));
      return c;
    }

    testWidgets('the alerts page lists samples, labelled, and sorts by distance', (t) async {
      await mount(t, const RoadAlertsScreen(), where: (-29.9540, 30.8870)); // Umlazi D
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Sample'), findsWidgets);
      expect(find.textContaining('Prototype: warnings stay on this phone'), findsOneWidget);
      // The pothole in Umlazi D is the closest one, so it is listed first.
      final firstTile = t.widgetList<HazardTile>(find.byType(HazardTile)).first;
      expect(firstTile.hazard.kind, HazardKind.pothole);
    });

    testWidgets('an unverified driver sees a disabled report button and no confirm buttons', (t) async {
      await mount(t, const RoadAlertsScreen(), verified: false);
      expect(find.text('Verify to report'), findsOneWidget);
      expect(find.text('Still there'), findsNothing);
    });

    testWidgets('reporting from the sheet places a warning at the driver\'s position', (t) async {
      final c = await mount(t, const RoadAlertsScreen(), where: (-29.80, 30.95));
      await t.tap(find.text('Report a hazard'));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('What is on the road?'), findsOneWidget);
      await t.tap(find.descendant(of: find.byType(GridView), matching: find.text('Pothole')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      final mine = c.read(roadProvider).hazards.where((h) => !h.demo).toList();
      expect(mine.length, 1);
      expect(mine.single.lat, -29.80);
      expect(find.textContaining('Pothole reported'), findsOneWidget);
    });

    testWidgets('with location off the driver is told, and nothing is saved', (t) async {
      final c = await mount(t, const RoadAlertsScreen());
      await t.tap(find.text('Report a hazard'));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.descendant(of: find.byType(GridView), matching: find.text('Flooding')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Turn location on'), findsOneWidget);
      expect(c.read(roadProvider).hazards.where((h) => !h.demo), isEmpty);
    });

    testWidgets('"Still there" adds the driver as a sighting', (t) async {
      final c = await mount(t, const RoadAlertsScreen());
      final tile = find.byType(HazardTile).first;
      final id = t.widget<HazardTile>(tile).hazard.id;
      await t.ensureVisible(find.descendant(of: tile, matching: find.text('Still there')));
      await t.tap(find.descendant(of: tile, matching: find.text('Still there')));
      await t.pump(const Duration(milliseconds: 400));
      expect(c.read(roadProvider).hazards.firstWhere((h) => h.id == id).confirms, contains('u-me'));
    });
  });
}
