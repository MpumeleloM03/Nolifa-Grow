import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/market/drive_page.dart';
import 'package:ubuntu_core/market/market_hub.dart';
import 'package:ubuntu_core/market/radar_page.dart';
import 'package:ubuntu_core/market/market_models.dart';
import 'package:ubuntu_core/market/market_repository.dart';
import 'package:ubuntu_core/market/market_store.dart';
import 'package:ubuntu_core/water/water_repository.dart';
import 'package:ubuntu_core/water/water_store.dart';
import 'package:ubuntu_core/theme/app_theme.dart';

// The test font (Ahem) renders every glyph a full em wide, so text rows
// overflow here that fit fine on a device. Ignore only those.
void ignoreFontOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

Future<void> scrollTo(WidgetTester tester, String text) async {
  for (var i = 0; i < 40 && find.text(text).evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 700));
  }
  await tester.ensureVisible(find.text(text).first);
  await tester.pump(const Duration(milliseconds: 500));
}

/// Mounts the hub with a container the test can poke directly.
Future<ProviderContainer> mount(WidgetTester tester, {List<HubTab>? tabs, MarketRepository? repo}) async {
  ignoreFontOverflow();
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    marketUidProvider.overrideWithValue('u-me'),
    marketNameProvider.overrideWithValue('Test Farmer'),
    marketRepositoryProvider.overrideWithValue(repo ?? LocalMarketRepository.memory()),
    waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.build(), home: MarketHub(tabs: tabs)),
  ));
  await tester.pump(const Duration(seconds: 1));
  return container;
}

/// Places a basket and returns the order id.
String order(ProviderContainer c, {PayMethod method = PayMethod.fnbPay}) {
  final store = c.read(marketProvider.notifier);
  store.add('p-water');
  store.add('p-candle');
  return store.place(method);
}

Future<void> settle(WidgetTester tester, [int seconds = 40]) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  group('fees', () {
    test('service fee is 3% with a R2 floor and R15 cap', () {
      expect(Fees.buyer(0), 0);
      expect(Fees.buyer(20), 2); // 3% = 0.60, floor R2
      expect(Fees.buyer(100), 3);
      expect(Fees.buyer(1000), 15); // 3% = 30, cap R15
    });

    test('plans trade a monthly fee for a lower commission', () {
      expect(Plan.starter.commission, 0.08);
      expect(Plan.grow.commission, 0.05);
      expect(Plan.coop.commission, 0.03);
      expect(Plan.starter.price, 49);
      expect(Plan.grow.price, 99);
    });
  });

  testWidgets('order total and the money split add up exactly', (tester) async {
    final c = await mount(tester);
    final id = order(c);
    final o = c.read(marketProvider).orderById(id)!;
    // R45 water + R29 candles = R74. Delivery R25. Service fee 3% = R2.22.
    expect(o.subtotal, 74);
    expect(o.serviceFee, 2.22);
    expect(o.total, 101.22);
    expect(r2(o.farmNet + o.driverPay + o.platformTake), o.total);
    expect(o.driverPay, 20); // 80% of the R25 delivery fee
    await settle(tester);
  });

  testWidgets('pay, deliver with PIN, confirm: everyone is paid once', (tester) async {
    final c = await mount(tester);
    final store = c.read(marketProvider.notifier);
    final id = order(c);
    expect(c.read(marketProvider).escrowHeld, 101.22);

    await tester.pump(const Duration(seconds: 6));
    expect(c.read(marketProvider).orderById(id)!.status, OrderStatus.assigned);
    await tester.pump(const Duration(seconds: 6));
    expect(c.read(marketProvider).orderById(id)!.pickupProof, isTrue);
    await tester.pump(const Duration(seconds: 10));
    final delivered = c.read(marketProvider).orderById(id)!;
    expect(delivered.status, OrderStatus.delivered);
    // Delivered but still protected: nobody has been paid yet.
    expect(delivered.released, isFalse);
    expect(c.read(marketProvider).escrowHeld, 101.22);

    store.confirmReceived(id, 5);
    final done = c.read(marketProvider).orderById(id)!;
    expect(done.released, isTrue);
    expect(done.rating, 5);
    expect(c.read(marketProvider).escrowHeld, 0);
    await settle(tester);
  });

  testWidgets('no action after delivery: funds auto-release after the window', (tester) async {
    final c = await mount(tester);
    final id = order(c);
    await tester.pump(const Duration(seconds: 21));
    expect(c.read(marketProvider).orderById(id)!.status, OrderStatus.delivered);
    expect(c.read(marketProvider).orderById(id)!.released, isFalse);
    await tester.pump(protectionWindow + const Duration(seconds: 1));
    expect(c.read(marketProvider).orderById(id)!.released, isTrue);
    await settle(tester);
  });

  testWidgets('delivery needs the right PIN', (tester) async {
    final c = await mount(tester);
    final store = c.read(marketProvider.notifier);
    store.completeKyc(KycRole.driver, 'selfie');
    store.completeKyc(KycRole.driver, 'payout');
    store.completeKyc(KycRole.driver, 'vehicle');
    store.toggleOnline();
    store.accept('UD-1033');
    store.pickedUp('UD-1033');

    expect(store.deliverWithPin('UD-1033', '0000'), isFalse);
    expect(c.read(marketProvider).orderById('UD-1033')!.status, OrderStatus.pickedUp);
    expect(store.deliverWithPin('UD-1033', '1946'), isTrue);
    expect(c.read(marketProvider).orderById('UD-1033')!.status, OrderStatus.delivered);
    await settle(tester);
    // Driver is paid 80% of R30 once the window closes.
    expect(c.read(marketProvider).driverEarned, 310 + 24);
  });

  testWidgets('unverified drivers cannot go online until all checks pass', (tester) async {
    final c = await mount(tester);
    final store = c.read(marketProvider.notifier);
    store.toggleOnline();
    expect(c.read(marketProvider).driverOnline, isFalse);
    for (final step in driverSteps) {
      store.completeKyc(KycRole.driver, step.id);
    }
    expect(c.read(marketProvider).driverVerified, isTrue);
    store.toggleOnline();
    expect(c.read(marketProvider).driverOnline, isTrue);
  });

  testWidgets('dispute freezes payment, then refunds in full if never delivered', (tester) async {
    final c = await mount(tester);
    final store = c.read(marketProvider.notifier);
    final farmBefore = c.read(marketProvider).farmEarned;
    final id = order(c);
    await tester.pump(const Duration(seconds: 12)); // picked up
    expect(c.read(marketProvider).orderById(id)!.status, OrderStatus.pickedUp);

    store.openDispute(id, DisputeReason.notDelivered, 'Nothing came');
    var o = c.read(marketProvider).orderById(id)!;
    expect(o.disputed, isTrue);
    expect(o.released, isFalse);
    expect(c.read(marketProvider).escrowHeld, o.total);

    await tester.pump(const Duration(seconds: 6));
    expect(c.read(marketProvider).orderById(id)!.dispute!.stage, DisputeStage.review);
    await tester.pump(const Duration(seconds: 8));
    o = c.read(marketProvider).orderById(id)!;
    expect(o.dispute!.stage, DisputeStage.resolved);
    expect(o.outcome, Outcome.fullRefund);
    expect(o.refund, o.total);
    expect(o.driverPay, 0);
    expect(o.platformTake, 0);
    expect(c.read(marketProvider).farmEarned, farmBefore);
    expect(c.read(marketProvider).ledger.first.kind, LedgerKind.refund);
    await settle(tester);
    // A late "delivered" must not pay out a case that was already settled.
    expect(c.read(marketProvider).escrowHeld, 0);
  });

  testWidgets('damaged goods refund half the items', (tester) async {
    final c = await mount(tester);
    final store = c.read(marketProvider.notifier);
    final id = order(c);
    await tester.pump(const Duration(seconds: 21));
    store.openDispute(id, DisputeReason.damaged, '');
    await tester.pump(const Duration(seconds: 14));
    final o = c.read(marketProvider).orderById(id)!;
    expect(o.outcome, Outcome.partialRefund);
    expect(o.refund, 37);
    await settle(tester);
  });

  testWidgets('only the buyer can dispute, and only once, before payout', (tester) async {
    final c = await mount(tester);
    final store = c.read(marketProvider.notifier);
    expect(store.canDispute(c.read(marketProvider).orderById('UD-1033')!), isFalse);
    final id = order(c);
    expect(store.canDispute(c.read(marketProvider).orderById(id)!), isFalse); // not picked up yet
    await tester.pump(const Duration(seconds: 12));
    store.openDispute(id, DisputeReason.late, '');
    store.openDispute(id, DisputeReason.damaged, ''); // ignored
    expect(c.read(marketProvider).orderById(id)!.dispute!.reason, DisputeReason.late);
    await settle(tester);
  });

  testWidgets('outbreak reports only go public once neighbours confirm', (tester) async {
    final c = await mount(tester);
    final store = c.read(marketProvider.notifier);
    final id = store.submitReport('Leaf rust', '🍂', 'Your area');
    ReportCase get() => c.read(marketProvider).cases.firstWhere((x) => x.id == id);
    expect(get().stage, ReportStage.aiChecked);
    expect(get().stage.broadcasts, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(get().confirmations, 1);
    expect(get().stage.broadcasts, isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(get().stage, ReportStage.corroborated);
    expect(get().stage.broadcasts, isTrue);
    await tester.pump(const Duration(seconds: 9));
    expect(get().stage, ReportStage.vetVerified);
  });

  testWidgets('upgrading the plan lowers commission on the next sale', (tester) async {
    final c = await mount(tester);
    final store = c.read(marketProvider.notifier);
    store.setPlan(Plan.grow);
    expect(c.read(marketProvider).plan, Plan.grow);
    store.packOrder('UD-1032');
    expect(c.read(marketProvider).orderById('UD-1032')!.commission, 0.05);
    // R114 sale, 5% commission.
    expect(c.read(marketProvider).orderById('UD-1032')!.mySalesNet, 108.3);
    expect(c.read(marketProvider).ledger.first.title, 'Grow plan');
    await settle(tester);
  });

  testWidgets('shop to checkout to tracking, driver tab and trust screens render', (tester) async {
    final c = await mount(tester);
    expect(find.text('Farms near you'), findsOneWidget);
    expect(find.text('Fresh near you'), findsOneWidget);

    // The top banner is now the live water alert; open checkout from the basket.
    c.read(marketProvider.notifier)
      ..add('p-water')
      ..add('p-candle');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.textContaining('Checkout').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Checkout'), findsOneWidget);
    await scrollTo(tester, 'Service fee (3%)');
    expect(find.text('Service fee (3%)'), findsOneWidget);
    await scrollTo(tester, '🧾 Where your money goes');
    expect(find.text('🧾 Where your money goes'), findsOneWidget);
    await tester.tap(find.textContaining('Pay R'));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(c.read(marketProvider).myOrders, isNotEmpty);
    await settle(tester, 30);
    while (find.byIcon(Icons.arrow_back_ios_new_rounded).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).first);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.tap(find.byIcon(Icons.menu_rounded).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('My orders'), findsOneWidget);
    await tester.tap(find.text('Trust and safety'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Trust & Safety'), findsOneWidget);
    expect(find.text('What is simulated in this prototype'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Who pays what'), findsOneWidget);
    while (find.byIcon(Icons.arrow_back_ios_new_rounded).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).first);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.tap(find.text('Alerts'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Umlazi'), findsWidgets);
    await settle(tester);
  });

  testWidgets('radar shows risk per supplier and reroute works from the screen', (tester) async {
    final c = await mount(tester, tabs: [
      HubTab('📡', Icons.radar_rounded, 'Radar', (cl) => RadarPage(onClose: cl)),
    ]);
    await tester.tap(find.text('Radar'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Supply Radar'), findsWidgets);
    expect(find.text('Mkhize Beef'), findsOneWidget);
    expect(find.text('High risk'), findsWidgets);
    expect(find.textContaining('vet verified in Pinetown'), findsOneWidget);
    expect(c.read(marketProvider).highRiskCount, 1);

    final y = tester.getCenter(find.text('Reroute volume').first).dy;
    if (y > 700) {
      await tester.drag(find.byType(CustomScrollView).first, Offset(0, 600 - y));
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.tap(find.text('Reroute volume').first);
    await tester.pump(const Duration(seconds: 1));
    expect(c.read(marketProvider).rerouted, {'s-1'});
    expect(find.text('Rerouted'), findsOneWidget);
    await settle(tester, 5);
  });

  testWidgets('driver page asks for verification first', (tester) async {
    await mount(tester, tabs: [
      HubTab('🛵', Icons.two_wheeler_rounded, 'Drive', (cl) => DrivePage(onClose: cl)),
    ]);
    expect(find.textContaining('Get verified'), findsOneWidget);
    await settle(tester, 5);
  });

  testWidgets('app mode switch in Trust & Safety turns demo off and on', (tester) async {
    final c = await mount(tester);
    await tester.tap(find.byIcon(Icons.menu_rounded).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Trust and safety'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await scrollTo(tester, 'Demo mode');
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(seconds: 1));
    expect(c.read(marketProvider).demoMode, isFalse);
    expect(find.textContaining('Live mode'), findsWidgets);
    expect(find.text('Saved on this phone only'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(seconds: 1));
    expect(c.read(marketProvider).demoMode, isTrue);
    await settle(tester, 5);
  });
}
