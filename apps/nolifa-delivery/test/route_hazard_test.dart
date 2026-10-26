import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_delivery/services/job_map.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'support.dart';

final _now = DateTime(2026, 10, 23, 9);

Order _job(OrderStatus s) => Order(
      id: 'o1',
      lines: const [OrderLine('Spinach', '🥬', 3, 20)],
      deliveryFee: 25,
      method: PayMethod.cash,
      status: s,
      customer: 'Thandi',
      pickup: 'Mkhize Family Farm',
      dropArea: 'Pinetown',
      placed: _now,
      driverIsMe: true,
    );

RoadHazard _hazard(String id, HazardKind k, String place, {int ageMin = 10}) {
  final p = placeCoords[place]!;
  final t = _now.subtract(Duration(minutes: ageMin));
  return RoadHazard(
      id: id, kind: k, lat: p.$1, lng: p.$2, reportedAt: t, lastSeen: t, reporter: 'other', confirms: const ['other']);
}

void main() {
  Future<ProviderContainer> mount(WidgetTester t, List<RoadHazard> hazards, {bool verified = true}) async {
    ignoreFontOverflow();
    // Tests get a 400 for every web request, so the map tiles cannot load. Ignore only that.
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('tile.openstreetmap.org')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    t.view.physicalSize = const Size(1206, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final repo = LocalRoadRepository.memory(clock: () => _now, seeds: false);
    for (final h in hazards) {
      await repo.save(h);
    }
    final c = ProviderContainer(overrides: [
      marketUidProvider.overrideWithValue('u-me'),
      marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
      roadRepositoryProvider.overrideWithValue(repo),
      roadClockProvider.overrideWithValue(() => _now),
      roadCanReportProvider.overrideWithValue(verified),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(body: SizedBox(height: 600, child: JobRouteMap(_job(OrderStatus.assigned)))),
      ),
    ));
    // Let the location, geocode and route lookups fail over to their fallbacks.
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }
    return c;
  }

  testWidgets('a warning on the route shows as a banner with its distance', (t) async {
    await mount(t, [_hazard('h1', HazardKind.flooding, 'mkhize family farm')]);
    expect(find.textContaining('Flooding in'), findsOneWidget);
    expect(find.text('🌊'), findsWidgets);
    expect(find.textContaining('1 alert'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });

  testWidgets('a warning far from the route stays off the banner', (t) async {
    await mount(t, [_hazard('h2', HazardKind.accident, 'pietermaritzburg')]);
    expect(find.textContaining('Accident in'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });

  testWidgets('the report button opens the hazard picker', (t) async {
    await mount(t, const []);
    await t.tap(find.byIcon(Icons.add_alert_rounded));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('What is on the road?'), findsOneWidget);
    expect(find.text('Pothole'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });
}
