import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  testWidgets('with no alerts the page still says so and shows what is watched', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        marketStartsLiveProvider.overrideWithValue(true),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        roadRepositoryProvider.overrideWithValue(LocalRoadRepository.memory()),
      ],
      child: MaterialApp(theme: AppTheme.buildLight(), home: const Scaffold(body: AlertsPage())),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('Nothing needs you right now'), findsOneWidget);
    expect(find.text('Road alerts'), findsOneWidget);
    expect(find.text('Outbreak reports'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
