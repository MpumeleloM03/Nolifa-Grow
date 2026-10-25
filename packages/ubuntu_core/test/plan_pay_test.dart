import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  testWidgets('on the shared backend a plan button takes you to the card page, with the price on it', (t) async {
    final asked = <Plan>[];
    t.view.physicalSize = const Size(1206, 12000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    final c = ProviderContainer(overrides: [
      marketUidProvider.overrideWithValue('u-me'),
      marketNameProvider.overrideWithValue('Thandi'),
      marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
      waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
      sellerPlanProvider.overrideWithValue(Plan.starter),
      planPaymentProvider.overrideWithValue((plan) async {
        asked.add(plan);
        return null;
      }),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.build(), home: const Scaffold(body: PlansScreen())),
    ));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Pay R99 and switch to Grow'), findsOneWidget);
    expect(find.text('Pay R199 and switch to Co-op'), findsOneWidget);
    await t.tap(find.text('Pay R99 and switch to Grow'));
    await t.pump(const Duration(milliseconds: 300));
    expect(asked, [Plan.grow]);
    expect(find.textContaining('switches on by itself'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
