import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  Future<void> open(WidgetTester t, List<Override> o, KycRole role) async {
    t.view.physicalSize = const Size(1206, 2622);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        marketStartsLiveProvider.overrideWithValue(true),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        ...o,
      ],
      child: MaterialApp(home: VerifyScreen(role: role)),
    ));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('a driver goes to the real application when the app has one', (t) async {
    await open(t, [driverApplicationScreenProvider.overrideWithValue(() => const Text('REAL DRIVER FORM'))], KycRole.driver);
    expect(find.text('REAL DRIVER FORM'), findsOneWidget);
    expect(find.textContaining('FNB'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('a farm goes to the real application when the app has one', (t) async {
    await open(t, [farmApplicationScreenProvider.overrideWithValue(() => const Text('REAL FARM FORM'))], KycRole.farmer);
    expect(find.text('REAL FARM FORM'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('phone-only mode still shows the steps, labelled as a demo and without false FNB claims', (t) async {
    await open(t, const [], KycRole.driver);
    expect(find.text('Verify as a driver'), findsOneWidget);
    expect(find.textContaining('Home Affairs'), findsNothing);
    expect(find.textContaining('simulated'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
