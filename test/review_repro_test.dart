// Regression tests for bugs an independent review found in the Nolifa store
// hub: demo labelling, invented live alerts, the packed-order simulation, the
// buyer's "Your street" placeholder, the water planner overwriting saved
// details, and numbers the Firestore rules would reject.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/models/cattle.dart';
import 'package:nolifa_grow/services/cattle_service.dart';
import 'package:nolifa_grow/store/farm_water_section.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'store_hub_test.dart'
    show ignoreFontOverflow, mount, pumpFor, spinach, card;

/// A water repository whose saved details take 2 s to load, like a network read.
class SlowPrefs extends LocalWaterRepository {
  SlowPrefs() : super.memory();
  final saved = <WaterPrefs>[];

  @override
  Future<WaterPrefs?> loadPrefs(String uid) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return const WaterPrefs(
        zoneId: 'umlazi', household: 6, tankLitres: 5000, herd: 12);
  }

  @override
  Future<void> savePrefs(String uid, WaterPrefs p) async => saved.add(p);
}

void main() {
  // Widget tests cannot reach the Keychain, so use a fixed test key.
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  testWidgets(
      'a real order shows the farmer where it goes, not the buyer\'s "Your street"',
      (tester) async {
    final rig = await mount(tester);
    rig.store.list(spinach(stock: 20));
    await pumpFor(tester, 600);
    // Any real order is created by MarketStore.place, which hard-codes the
    // drop area as 'Your street'. That is the buyer's wording, not an address.
    rig.store.add('sp', 2);
    final id = rig.store.place(PayMethod.fnbPay);
    await pumpFor(tester, 800);
    final texts = tester
        .widgetList<Text>(
            find.descendant(of: card('order-$id'), matching: find.byType(Text)))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .toList();
    expect(texts.any((t) => t.contains('Your street')), isFalse,
        reason: 'card shows: $texts');
  });

  testWidgets('packing a demo order gets a driver within 30 seconds',
      (tester) async {
    final rig = await mount(tester, demo: true);
    await tester.tap(find.descendant(
        of: card('order-UD-1031'),
        matching: find.text('Packed, request driver')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final o = rig.state.orderById('UD-1031')!;
    expect(o.driver, isNotNull,
        reason: 'still "${o.status.name}" with no driver after 30 s');
    await rig.shutDown(tester);
  });

  testWidgets('demo mode is labelled on the store page', (tester) async {
    await mount(tester, demo: true);
    // Earnings of R1 240, two orders and four outbreak cases are all seed data.
    expect(find.textContaining(RegExp('demo', caseSensitive: false)),
        findsWidgets);
  });

  testWidgets('live mode does not show the invented farm alerts',
      (tester) async {
    await mount(tester); // live mode: no demo data
    expect(find.text('Foot-and-mouth movement restriction'), findsNothing,
        reason: 'a made-up "State vet notice" is shown to every live farmer');
    expect(find.text('Fall armyworm spotted 12 km away'), findsNothing);
  });

  testWidgets(
      'opening the water radar does not overwrite saved household and tank details',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    ignoreFontOverflow();
    final water = SlowPrefs();
    final c = ProviderContainer(overrides: [
      marketUidProvider.overrideWithValue('farmer-1'),
      marketNameProvider.overrideWithValue('Farmer'),
      marketRepositoryProvider
          .overrideWithValue(LocalMarketRepository.memory()),
      waterRepositoryProvider.overrideWithValue(water),
      // The register already holds the same 12 animals the saved details say.
      herdProvider.overrideWith((ref) => Stream.value([
            for (var i = 0; i < 12; i++)
              Cattle(
                  id: 'c$i', tagNumber: 'T$i', tagStandard: TagStandard.visual)
          ])),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.build(),
          home: const Scaffold(
              body: SingleChildScrollView(child: FarmWaterSection()))),
    ));
    await pumpFor(tester, 3500);
    // Whatever was stored last is what the next app start loads.
    for (final w in water.saved) {
      expect(w.tankLitres, 5000,
          reason:
              'wrote zone=${w.zoneId} household=${w.household} tank=${w.tankLitres}: defaults saved before the real details loaded');
    }
  });

  testWidgets('"Infinity" in the quantity box is refused, not thrown',
      (tester) async {
    final rig = await mount(tester);
    await tester.tap(find.widgetWithText(GlassButton, 'Add stock'));
    await pumpFor(tester, 600);
    await tester.enterText(
        find.widgetWithText(
            TextFormField, 'What are you selling? (e.g. Carrots 5kg)'),
        'Eggs');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Price in Rand'), '10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'How many'), 'Infinity');
    await tester.tap(find.text('List it'));
    await pumpFor(tester, 600);
    expect(tester.takeException(), isNull);
    expect(rig.mine, isEmpty);
    expect(find.text('Enter how many you have'), findsOneWidget);
  });

  testWidgets('a price above the Firestore limit is refused', (tester) async {
    final rig = await mount(tester);
    await tester.tap(find.widgetWithText(GlassButton, 'Add stock'));
    await pumpFor(tester, 600);
    await tester.enterText(
        find.widgetWithText(
            TextFormField, 'What are you selling? (e.g. Carrots 5kg)'),
        'Eggs');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Price in Rand'), '150000');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'How many'), '10');
    await tester.tap(find.text('List it'));
    await pumpFor(tester, 600);
    expect(rig.mine, isEmpty);
    expect(find.text('Keep it under 100 000'), findsOneWidget);
  });
}
