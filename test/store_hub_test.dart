import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nolifa_grow/models/app_user.dart';
import 'package:latlong2/latlong.dart';
import 'package:nolifa_grow/models/cattle.dart';
import 'package:nolifa_grow/models/outbreak_report.dart';
import 'package:nolifa_grow/screens/map_screen.dart';
import 'package:nolifa_grow/screens/livestock/livestock_home_screen.dart';
import 'package:nolifa_grow/community/community_alerts_screen.dart';
import 'package:nolifa_grow/shell/alarm.dart';
import 'package:nolifa_grow/weather/weather_models.dart';
import 'package:nolifa_grow/weather/weather_service.dart';
import 'package:nolifa_grow/shell/alerts_tab.dart';
import 'package:nolifa_grow/shell/grow_shell.dart';
import 'package:nolifa_grow/shell/orders_tab.dart';
import 'package:nolifa_grow/shell/welcome_back.dart';
import 'package:nolifa_grow/services/auth_service.dart';
import 'package:nolifa_grow/services/cattle_service.dart';
import 'package:nolifa_grow/store/add_stock_sheet.dart';
import 'package:nolifa_grow/store/farm_water_section.dart';
import 'package:nolifa_grow/store/market_overrides.dart';
import 'package:nolifa_grow/store/order_card.dart';
import 'package:nolifa_grow/store/order_rows.dart';
import 'package:nolifa_grow/store/stock_card.dart';
import 'package:nolifa_grow/store/store_common.dart';
import 'package:nolifa_grow/water/supplier_screen.dart';
import 'package:nolifa_grow/water/supplier_store.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

// The test font renders every glyph a full em wide, so rows overflow here that
// fit fine on a phone. Ignore only those.
void ignoreFontOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

const _me = 'farmer-1';

class _DemoWeather extends WeatherService {
  @override
  Future<Forecast> forecastFor(String region) async => demoForecast(region, DateTime.now());
}

class _FakeNotices implements NoticeSender {
  final sent = <(String, String)>[];
  @override
  Future<void> show({required String title, required String body}) async => sent.add((title, body));
}

/// Lets sheets and reveals finish without waiting on the alert pulse, which
/// never stops animating.
Future<void> pumpFor(WidgetTester tester, [int ms = 1200]) async {
  for (var t = 0; t < ms; t += 200) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

class Rig {
  final ProviderContainer container;
  final LocalMarketRepository repo;
  final VoidCallback _dispose;
  Rig(this.container, this.repo, this._dispose);

  /// Unmounts the page and disposes the store so its simulation timers stop
  /// before the test ends.
  Future<void> shutDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    _dispose();
  }

  MarketState get state => container.read(marketProvider);
  MarketStore get store => container.read(marketProvider.notifier);
  List<Product> get mine => state.products.where((p) => p.mine).toList();
}

/// Mounts [child] with the shared providers pointed at memory storage. The
/// view is tall so every lazy section builds without scrolling.
///
/// Live mode (the default here) starts from an empty farm. Pass [demo] to keep
/// the seeded demo orders, cases and balances.
Future<Rig> mount(
  WidgetTester tester, {
  Widget child = const Scaffold(body: OrdersTab()),
  bool demo = false,
  bool verified = true,
  List<Cattle>? herd,
  AppUser? user,
  bool waterPrompt = false,
  NoticeSender? notices,
}) async {
  ignoreFontOverflow();
  tester.view.physicalSize = const Size(1206, 12000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = LocalMarketRepository.memory();
  final container = ProviderContainer(overrides: [
    marketUidProvider.overrideWithValue(_me),
    marketNameProvider.overrideWithValue('Farmer'),
    marketRepositoryProvider.overrideWithValue(repo),
    waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
    lowWaterPromptShownProvider.overrideWith((ref) => !waterPrompt),
    weatherServiceProvider.overrideWithValue(_DemoWeather()),
    if (notices != null) notifierProvider.overrideWithValue(notices),
    if (herd != null) herdProvider.overrideWith((ref) => Stream.value(herd)),
    if (user != null) currentUserProvider.overrideWithValue(user),
  ]);
  var disposed = false;
  addTearDown(() {
    if (!disposed) container.dispose();
  });
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.build(), home: child),
  ));
  await pumpFor(tester);
  final rig = Rig(container, repo, () {
    disposed = true;
    container.dispose();
  });
  if (!demo) rig.store.setDemoMode(false);
  if (verified) {
    for (final step in farmerSteps) {
      rig.store.completeKyc(KycRole.farmer, step.id);
    }
    rig.store.registerBusiness();
    rig.store.setPlan(Plan.starter);
    rig.store.submitLandEvidence();
    rig.store.requestInspection(InspectionRoute.surveyor);
    rig.store.recordInspection(passed: true);
  }
  await pumpFor(tester, 400);
  return rig;
}

Product spinach({int? stock = 20, bool available = true, double price = 12}) =>
    Product(
      id: 'sp',
      name: 'Spinach bunch',
      emoji: '🥬',
      category: Category.veg,
      farm: "Farmer's farm",
      km: 0.5,
      price: price,
      unit: 'bunch',
      stock: stock,
      available: available,
    );

Order neighbourOrder({
  String id = 'UD-T0001',
  OrderStatus status = OrderStatus.newOrder,
  int qty = 4,
  String customer = 'Thandi Nkosi',
  String dropArea = 'Umlazi V Section',
  Duration age = const Duration(minutes: 6),
  String? driver,
  bool released = false,
  double commission = 0.08,
  bool selfDelivery = false,
  String? pinHash,
}) =>
    Order(
      id: id,
      lines: [
        OrderLine('Spinach bunch', '🥬', qty, 12,
            mine: true, ownerId: _me, productId: 'sp'),
      ],
      deliveryFee: 25,
      serviceFee: 2,
      commission: commission,
      method: PayMethod.fnbPay,
      status: status,
      customer: customer,
      pickup: "Farmer's farm",
      dropArea: dropArea,
      placed: DateTime.now().subtract(age),
      customerId: 'neighbour-1',
      farmerId: _me,
      driver: driver,
      driverId: driver == null ? null : 'driver-1',
      released: released,
      selfDelivery: selfDelivery,
      pinHash: pinHash,
    );

/// Delivers an order to the farmer the way Firestore would: through the repo.
Future<void> receive(WidgetTester tester, Rig rig, Order o) async {
  await rig.repo.putOrder(o, 'neighbour-1');
  await pumpFor(tester, 600);
}

Finder card(String key) => find.byKey(ValueKey(key));

void main() {
  // Widget tests cannot reach the Keychain, so use a fixed test key.
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  group('pure helpers', () {
    test('first names, digits and numbers read the South African way', () {
      expect(firstName('Thandi Nkosi'), 'Thandi');
      expect(firstName('  '), 'A neighbour');
      expect(groupDigits(12500), '12 500');
      expect(groupDigits(999), '999');
      expect(money(12), 'R12');
      expect(money(28.5), 'R28.50');
      expect(parseNumber('12,50'), 12.5);
      expect(parseNumber('abc'), isNull);
    });

    test('time ago rounds down to the unit a person would say', () {
      final now = DateTime(2026, 10, 21, 12);
      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now),
          'Just now');
      expect(timeAgo(now.subtract(const Duration(minutes: 6)), now: now),
          '6 min ago');
      expect(
          timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
      expect(
          timeAgo(now.subtract(const Duration(days: 2)), now: now), '2 d ago');
    });

    test('stock badges: sold out beats paused beats running low', () {
      expect(stockBadge(spinach(stock: 0)).label, 'Sold out');
      expect(stockBadge(spinach(stock: 0, available: false)).label, 'Sold out');
      expect(stockBadge(spinach(available: false)).label, 'Paused');
      expect(stockBadge(spinach(stock: 3)).label, 'Only 3 left');
      expect(stockBadge(spinach(stock: lowStockAt + 1)).label, 'In stock');
      expect(stockBadge(spinach(stock: null)).label, 'In stock');
    });

    test('order status badges use the words a farmer would', () {
      String label(Order o) => orderBadge(o).label;
      expect(label(neighbourOrder()), 'New');
      expect(label(neighbourOrder(status: OrderStatus.findingDriver)),
          'Waiting for a driver');
      expect(label(neighbourOrder(status: OrderStatus.assigned)),
          'Driver on the way');
      expect(label(neighbourOrder(status: OrderStatus.pickedUp)), 'On its way');
      expect(label(neighbourOrder(status: OrderStatus.delivered)), 'Delivered');
      expect(
          label(neighbourOrder(status: OrderStatus.delivered, released: true)),
          'Paid out');
    });

    test('a disputed order shows as a case, a refunded one is not "paid out"',
        () {
      final disputed = neighbourOrder(status: OrderStatus.delivered).copyWith(
        dispute: const Dispute(
            reason: DisputeReason.damaged,
            note: '',
            stage: DisputeStage.review,
            timeline: []),
      );
      expect(orderBadge(disputed).label, 'Case open');
      final refunded =
          neighbourOrder(status: OrderStatus.delivered, released: true)
              .copyWith(
        dispute: const Dispute(
            reason: DisputeReason.notDelivered,
            note: '',
            stage: DisputeStage.resolved,
            outcome: Outcome.fullRefund,
            timeline: []),
      );
      expect(orderBadge(refunded).label, 'Refunded');
    });

    test('what the farmer receives follows the commission that applies', () {
      // 4 x R12 = R48 of the farmer's own produce.
      final fresh = youReceive(neighbourOrder(), 0.05);
      expect(
          fresh.amount, closeTo(45.6, 0.001)); // a new order uses today's plan
      expect(fresh.settled, isFalse);

      final packed =
          youReceive(neighbourOrder(status: OrderStatus.findingDriver), 0.03);
      expect(packed.amount,
          closeTo(44.16, 0.001)); // packed at 8%, plan change ignored

      final paid = youReceive(
          neighbourOrder(
              status: OrderStatus.delivered, released: true, commission: 0.05),
          0.08);
      expect(paid.amount, 45.6);
      expect(paid.settled, isTrue);
    });

    test('new orders sort to the top, newest first, with group labels', () {
      final old = neighbourOrder(id: 'old', age: const Duration(hours: 5));
      final newer =
          neighbourOrder(id: 'newer', age: const Duration(minutes: 5));
      final done = neighbourOrder(
          id: 'done',
          status: OrderStatus.delivered,
          age: const Duration(minutes: 1));
      final rows = orderRows(sortedFarmOrders([old, done, newer]));
      expect(rows.map((r) => r is Order ? r.id : r).toList(),
          ['New orders', 'newer', 'old', 'Earlier orders', 'done']);
      // One group needs no labels.
      expect(orderRows([done]).whereType<String>(), isEmpty);
    });

    test('herd water: 50 litres a head, and days of cover from the tank', () {
      expect(herdLitresPerDay(12), 600);
      expect(herdTankDays(head: 0, tankLitres: 5000), isNull);
      expect(herdTankDays(head: 10, tankLitres: 2000), 4);
    });
  });

  group('Orders tab', () {
    testWidgets(
        'an empty store invites the first listing and says orders are on this phone',
        (tester) async {
      await mount(tester);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.textContaining('Add your first stock'), findsOneWidget);
      expect(find.textContaining('No orders yet'), findsOneWidget);
      // Memory storage is not shared, so the page must not imply neighbours can see it.
      expect(find.textContaining('Saved on this phone only'), findsOneWidget);
      expect(find.textContaining('once your stock is shared'), findsOneWidget);
      expect(find.text('Orders received'), findsOneWidget);
      expect(find.text('Your store is open'), findsOneWidget);
    });

    testWidgets(
        'adding stock through the sheet lists an own product with the right quantity',
        (tester) async {
      final rig = await mount(tester);
      expect(rig.mine, isEmpty);

      await tester.tap(find.widgetWithText(GlassButton, 'Add stock'));
      await pumpFor(tester, 600);
      expect(find.text('🌱 Add stock'), findsOneWidget);

      await tester.tap(find.text('🌽'));
      await tester.enterText(
          find.widgetWithText(
              TextFormField, 'What are you selling? (e.g. Carrots 5kg)'),
          'Mielies 10 cobs');
      await tester.tap(find.text('Grain'));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Price in Rand'), '25,50');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'How many'), '40');
      await tester.tap(find.text('bag'));
      await tester.pump();
      await tester.tap(find.text('List it'));
      await pumpFor(tester, 800);

      final p = rig.mine.single;
      expect(p.name, 'Mielies 10 cobs');
      expect(p.emoji, '🌽');
      expect(p.category, Category.grain);
      expect(p.price, 25.5);
      expect(p.stock, 40);
      expect(p.unit, 'bag');
      expect(p.ownerId, _me);
      expect(p.farm, "Farmer's Farm");
      expect(p.rescue, isFalse);
      expect(p.available, isTrue);

      // The sheet closed, the card shows it and the farmer got a confirmation.
      expect(find.text('🌱 Add stock'), findsNothing);
      expect(find.text('Mielies 10 cobs'), findsOneWidget);
      expect(find.text('40 left'), findsOneWidget);
      expect(find.textContaining('is listed. 40 in stock'), findsOneWidget);
      // And it reached storage, which is what Nolifa Drop reads from.
      expect((await rig.repo.watchProducts(_me).first).single.stock, 40);
    });

    testWidgets(
        'the sheet refuses an empty name, a zero price and a zero quantity',
        (tester) async {
      final rig = await mount(tester);
      await tester.tap(find.widgetWithText(GlassButton, 'Add stock'));
      await pumpFor(tester, 600);
      await tester.tap(find.text('List it'));
      await pumpFor(tester, 400);
      expect(find.text('Give it a name, like Carrots 5kg'), findsOneWidget);
      expect(find.text('Enter a price in Rand'), findsOneWidget);
      expect(find.text('Enter how many you have'), findsOneWidget);
      expect(rig.mine, isEmpty);
      expect(find.text('🌱 Add stock'), findsOneWidget);
    });

    testWidgets(
        'a rescue listing takes 25% off and keeps the usual price struck through',
        (tester) async {
      final rig = await mount(tester);
      await tester.tap(find.widgetWithText(GlassButton, 'Add stock'));
      await pumpFor(tester, 600);
      await tester.enterText(
          find.widgetWithText(
              TextFormField, 'What are you selling? (e.g. Carrots 5kg)'),
          'Tomatoes 2kg');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Price in Rand'), '40');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'How many'), '12');
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.textContaining('Neighbours pay R30 (25% off R40)'),
          findsOneWidget);
      await tester.tap(find.text('List it'));
      await pumpFor(tester, 800);

      final p = rig.mine.single;
      expect(p.rescue, isTrue);
      expect(p.price, 40 * (1 - rescueDiscount));
      expect(p.wasPrice, 40);
      expect(find.textContaining('R30 per kg  R40'),
          findsOneWidget); // usual price struck through
    });

    testWidgets(
        'a farm that is not set up yet is sent to the Business page before adding stock',
        (tester) async {
      final rig = await mount(tester, verified: false);
      expect(rig.state.canSell, isFalse);
      expect(find.text('Finish setup to start selling'), findsOneWidget);

      await tester.tap(find.widgetWithText(GlassButton, 'Add stock'));
      await pumpFor(tester, 800);
      expect(find.byType(BusinessScreen), findsOneWidget);
      expect(find.text('🌱 Add stock'), findsNothing);
    });

    testWidgets('registering, verifying and paying for a plan opens the store',
        (tester) async {
      final rig = await mount(tester, verified: false);
      expect(rig.state.canSell, isFalse);
      rig.store.registerBusiness(kind: 'cooperative');
      expect(rig.state.canSell, isFalse, reason: 'still unverified and no plan');
      for (final step in farmerSteps) {
        rig.store.completeKyc(KycRole.farmer, step.id);
      }
      expect(rig.state.canSell, isFalse, reason: 'no plan yet');
      rig.store.setPlan(Plan.grow);
      expect(rig.state.canSell, isFalse, reason: 'land photos missing');
      rig.store.submitLandEvidence();
      expect(rig.state.canSell, isTrue);
      await pumpFor(tester, 600);
      expect(find.text('Selling with limits'), findsOneWidget);
    });

    testWidgets('restock buttons and a typed amount update the count',
        (tester) async {
      final rig = await mount(tester);
      rig.store.list(spinach(stock: 5));
      await pumpFor(tester, 600);
      final spinachCard = card('stock-sp');
      expect(find.descendant(of: spinachCard, matching: find.text('5 left')),
          findsOneWidget);
      expect(
          find.descendant(of: spinachCard, matching: find.text('Only 5 left')),
          findsOneWidget);

      await tester
          .tap(find.descendant(of: spinachCard, matching: find.text('+10')));
      await pumpFor(tester, 400);
      expect(rig.mine.single.stock, 15);

      await tester
          .tap(find.descendant(of: spinachCard, matching: find.text('+50')));
      await pumpFor(tester, 400);
      expect(rig.mine.single.stock, 65);
      expect(find.descendant(of: spinachCard, matching: find.text('In stock')),
          findsOneWidget);

      await tester.tap(
          find.descendant(of: spinachCard, matching: find.text('Set amount')));
      await pumpFor(tester, 600);
      await tester.enterText(find.byType(TextFormField), '3');
      await tester.tap(find.text('Save'));
      await pumpFor(tester, 600);
      expect(rig.mine.single.stock, 3);
      expect(
          find.descendant(of: spinachCard, matching: find.text('Only 3 left')),
          findsOneWidget);
    });

    testWidgets(
        'typing zero marks the listing sold out, and a bad amount is refused',
        (tester) async {
      final rig = await mount(tester);
      rig.store.list(spinach(stock: 8));
      await pumpFor(tester, 600);
      final spinachCard = card('stock-sp');

      await tester.tap(
          find.descendant(of: spinachCard, matching: find.text('Set amount')));
      await pumpFor(tester, 600);
      await tester.enterText(find.byType(TextFormField), '2.5');
      await tester.tap(find.text('Save'));
      await pumpFor(tester, 300);
      expect(find.text('Whole numbers only'), findsOneWidget);
      expect(rig.mine.single.stock, 8);

      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Save'));
      await pumpFor(tester, 600);
      expect(rig.mine.single.stock, 0);
      expect(find.descendant(of: spinachCard, matching: find.text('Sold out')),
          findsOneWidget);
      expect(find.textContaining('Restock to sell again'), findsOneWidget);
    });

    testWidgets(
        'changing the price saves it and shows a cut as a strike-through',
        (tester) async {
      final rig = await mount(tester);
      rig.store.list(spinach());
      await pumpFor(tester, 600);
      final spinachCard = card('stock-sp');

      await tester.tap(find.descendant(
          of: spinachCard, matching: find.text('Change price')));
      await pumpFor(tester, 600);
      await tester.enterText(find.byType(TextFormField), '9,50');
      await tester.tap(find.text('Save'));
      await pumpFor(tester, 600);
      expect(rig.mine.single.price, 9.5);
      expect(rig.mine.single.wasPrice, 12);
      expect(find.textContaining('R9.50 per bunch'), findsOneWidget);

      await tester.tap(find.descendant(
          of: spinachCard, matching: find.text('Change price')));
      await pumpFor(tester, 600);
      await tester.enterText(find.byType(TextFormField), '15');
      await tester.tap(find.text('Save'));
      await pumpFor(tester, 600);
      expect(rig.mine.single.price, 15);
      expect(rig.mine.single.wasPrice, isNull);
    });

    testWidgets(
        'the switch pauses and resumes selling without losing the stock',
        (tester) async {
      final rig = await mount(tester);
      rig.store.list(spinach());
      await pumpFor(tester, 600);
      final toggle =
          find.descendant(of: card('stock-sp'), matching: find.byType(Switch));

      await tester.tap(toggle);
      await pumpFor(tester, 400);
      expect(rig.mine.single.available, isFalse);
      expect(rig.mine.single.stock, 20);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.textContaining('buyers cannot see it'), findsOneWidget);

      await tester.tap(toggle);
      await pumpFor(tester, 400);
      expect(rig.mine.single.available, isTrue);
      expect(find.text('Paused'), findsNothing);
      expect(find.text('Selling now'), findsOneWidget);
    });

    testWidgets('sold-out stock says so', (tester) async {
      final rig = await mount(tester);
      rig.store.list(spinach(stock: 0));
      await pumpFor(tester, 600);
      expect(find.text('Sold out'), findsOneWidget);
      expect(find.text('0 left'), findsOneWidget);
    });

    testWidgets(
        'an order from a neighbour shows who, what and what you get, and packing works',
        (tester) async {
      final rig = await mount(tester);
      rig.store.list(spinach(stock: 20));
      await pumpFor(tester, 600);
      await receive(tester, rig, neighbourOrder());

      final order = card('order-UD-T0001');
      expect(order, findsOneWidget);
      // WHO: first name and area only.
      expect(
          find.descendant(of: order, matching: find.textContaining('Thandi')),
          findsOneWidget);
      expect(find.descendant(of: order, matching: find.textContaining('Nkosi')),
          findsNothing);
      expect(
          find.descendant(
              of: order, matching: find.textContaining('Umlazi V Section')),
          findsOneWidget);
      // WHAT: every line, with quantity.
      expect(
          find.descendant(of: order, matching: find.text('4 × Spinach bunch')),
          findsOneWidget);
      // MONEY: the sale and the share after the 8% free-plan commission.
      expect(
          find.descendant(of: order, matching: find.text('R48')), findsWidgets);
      expect(
          find.descendant(of: order, matching: find.text('You receive about')),
          findsOneWidget);
      expect(find.descendant(of: order, matching: find.text('R44.16')),
          findsOneWidget);
      // STATUS and the header count.
      expect(find.descendant(of: order, matching: find.text('New')),
          findsOneWidget);
      expect(find.text('1 to send'), findsOneWidget);
      // The shelf shrank by what was ordered.
      expect(rig.mine.single.stock, 16);
      expect(find.text('16 left'), findsOneWidget);

      final pack = find.descendant(
          of: order, matching: find.text('Packed, request driver'));
      expect(pack, findsOneWidget);
      await tester.tap(pack);
      await pumpFor(tester, 600);

      expect(
          rig.state.orderById('UD-T0001')!.status, OrderStatus.findingDriver);
      expect(
          find.descendant(
              of: order, matching: find.text('Waiting for a driver')),
          findsOneWidget);
      expect(find.text('Packed, request driver'), findsNothing);
      expect(find.text('1 to send'), findsNothing);
      // The change went to storage, where drivers find open jobs.
      final stored = (await rig.repo.watchOrders('neighbour-1').first).single;
      expect(stored.status, OrderStatus.findingDriver);
    });

    testWidgets(
        'a farm that delivers itself packs, goes out for delivery, and finishes with the buyer PIN',
        (tester) async {
      final rig = await mount(tester);
      rig.store.list(spinach(stock: 20));
      await pumpFor(tester, 600);
      await receive(tester, rig,
          neighbourOrder(selfDelivery: true, pinHash: hashPin('UD-T0001', '4242')));

      final order = card('order-UD-T0001');
      expect(find.descendant(of: order, matching: find.text('You deliver this one yourself')),
          findsOneWidget);
      // No driver queue for a self-delivery order.
      await tester.tap(find.descendant(of: order, matching: find.text('Packed, I am delivering')));
      await pumpFor(tester, 600);
      expect(rig.state.orderById('UD-T0001')!.status, OrderStatus.assigned);
      expect(find.descendant(of: order, matching: find.text('Ready to deliver')), findsOneWidget);

      await tester.tap(find.descendant(of: order, matching: find.text('Out for delivery')).last);
      await pumpFor(tester, 600);
      expect(rig.state.orderById('UD-T0001')!.status, OrderStatus.pickedUp);

      await tester.tap(find.text('Delivered, enter customer PIN'));
      await pumpFor(tester, 600);
      await tester.enterText(find.byType(TextField).last, '1111');
      await tester.tap(find.text('Confirm'));
      await pumpFor(tester, 400);
      expect(find.textContaining('That PIN does not match'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '4242');
      await tester.tap(find.text('Confirm'));
      await pumpFor(tester, 600);
      expect(rig.state.orderById('UD-T0001')!.status, OrderStatus.delivered);
      await rig.shutDown(tester);
    });

    testWidgets(
        'new orders sit above earlier ones, and an assigned driver is named',
        (tester) async {
      final rig = await mount(tester);
      rig.store.list(spinach(stock: 50));
      await pumpFor(tester, 600);
      await receive(
          tester,
          rig,
          neighbourOrder(
              id: 'UD-EARLY',
              status: OrderStatus.assigned,
              age: const Duration(minutes: 2),
              driver: 'Sipho M.',
              customer: 'Mama Joy Spaza',
              dropArea: 'Kwa-Mashu'));
      await receive(tester, rig,
          neighbourOrder(id: 'UD-FRESH', age: const Duration(minutes: 30)));

      expect(find.text('New orders'), findsOneWidget);
      expect(find.text('Earlier orders'), findsOneWidget);
      final fresh = tester.getTopLeft(card('order-UD-FRESH')).dy;
      final early = tester.getTopLeft(card('order-UD-EARLY')).dy;
      expect(fresh, lessThan(early),
          reason: 'a new order outranks a more recent older one');

      final earlyCard = card('order-UD-EARLY');
      expect(
          find.descendant(
              of: earlyCard, matching: find.text('Driver on the way')),
          findsOneWidget);
      expect(
          find.descendant(
              of: earlyCard, matching: find.text('Driver: Sipho M.')),
          findsOneWidget);
      expect(
          find.descendant(of: earlyCard, matching: find.textContaining('Mama')),
          findsOneWidget);
      // Only new orders can be packed.
      expect(
          find.descendant(
              of: earlyCard, matching: find.text('Packed, request driver')),
          findsNothing);
    });

    testWidgets('a paid-out order shows the final amount after commission',
        (tester) async {
      final rig = await mount(tester);
      rig.store.list(spinach(stock: 50));
      await pumpFor(tester, 600);
      await receive(
          tester,
          rig,
          neighbourOrder(
              id: 'UD-PAID',
              status: OrderStatus.delivered,
              released: true,
              commission: 0.05,
              age: const Duration(days: 2)));

      final paid = card('order-UD-PAID');
      expect(find.descendant(of: paid, matching: find.text('Paid out')),
          findsOneWidget);
      expect(find.descendant(of: paid, matching: find.text('You receive')),
          findsOneWidget);
      expect(find.descendant(of: paid, matching: find.text('R45.60')),
          findsOneWidget);
      expect(
          find.descendant(of: paid, matching: find.textContaining('2 d ago')),
          findsOneWidget);
    });

    testWidgets(
        'summary shows earnings, orders to send, plan, and the wallet and plan links',
        (tester) async {
      await mount(tester, demo: true);
      expect(find.text('You have made'), findsOneWidget);
      expect(find.text('R1 240'),
          findsOneWidget); // demo farm earnings after the count-up
      expect(find.text('to send out'), findsOneWidget);
      expect(find.textContaining('8% commission'), findsOneWidget);
      expect(find.text('Your store is open'), findsOneWidget);

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await tester.ensureVisible(find.text('Wallet'));
      await tester.tap(find.text('Wallet'));
      await pumpFor(tester, 800);
      expect(find.byType(WalletScreen), findsOneWidget);
      nav.pop();
      await pumpFor(tester, 800);

      await tester.ensureVisible(find.text('Plans'));
      await tester.tap(find.text('Plans'));
      await pumpFor(tester, 800);
      expect(find.byType(PlansScreen), findsOneWidget);
    });

    testWidgets('notifications tell the farmer what came in', (tester) async {
      await mount(tester, demo: true);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.textContaining('Thandi ordered 7 items'), findsOneWidget);
    });

    testWidgets(
        'the demo orders show who ordered and what, before any are packed',
        (tester) async {
      final rig = await mount(tester, demo: true);
      final order = card('order-UD-1031');
      expect(
          find.descendant(of: order, matching: find.textContaining('Thandi')),
          findsOneWidget);
      expect(
          find.descendant(
              of: order, matching: find.textContaining('Umlazi V Section')),
          findsOneWidget);
      expect(
          find.descendant(of: order, matching: find.text('6 × Spinach bunch')),
          findsOneWidget);
      expect(
          find.descendant(
              of: order, matching: find.text('1 × Free-range eggs x30')),
          findsOneWidget);
      // R72 + R84 of produce, less the 8% free-plan commission.
      expect(find.descendant(of: order, matching: find.text('R156')),
          findsWidgets);
      expect(find.descendant(of: order, matching: find.text('R143.52')),
          findsOneWidget);
      expect(find.text('2 to send'), findsOneWidget);
      expect(find.text('New orders'), findsNothing,
          reason: 'one group needs no labels');

      await tester.tap(find.descendant(
          of: order, matching: find.text('Packed, request driver')));
      await pumpFor(tester, 600);
      expect(rig.state.orderById('UD-1031')!.status, OrderStatus.findingDriver);
      expect(find.text('1 to send'), findsOneWidget);
      await rig.shutDown(tester);
    });
  });

  group('Alerts tab', () {
    const alerts = Scaffold(body: AlertsTab());

    Future<void> openAlarm(WidgetTester tester) async {
      await tester.tap(find.byType(AlarmButton));
      await pumpFor(tester, 1000);
    }

    testWidgets('Alerts runs: map, Report, water graph, Water radar, then Community alerts', (tester) async {
      await mount(tester, demo: true, child: alerts);
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.byType(AlarmButton), findsOneWidget);
      expect(tester.getTopLeft(find.byType(AlarmButton)).dx < 40, isTrue);
      expect(find.byType(MapScreen), findsOneWidget);
      double y(Finder f) => tester.getTopLeft(f).dy;
      final report = y(find.text('Report an outbreak'));
      final graph = y(find.byType(WaterRadarChart));
      final radar = y(find.widgetWithText(GlassButton, 'Water radar'));
      final community = y(find.textContaining('Community alerts').first);
      expect(report < graph, isTrue, reason: 'graph is just below Report');
      expect(graph < radar, isTrue, reason: 'Water radar button is below the graph');
      expect(radar < community, isTrue, reason: 'Community alerts is below Water radar');
      // The community lists and the chat are not on this page any more.
      expect(find.text('Neighbour reports'), findsNothing);
      expect(find.text('Elsewhere in KwaZulu-Natal'), findsNothing);
      expect(find.text('Share proof with your area'), findsNothing);
      expect(find.text('Frost risk tonight'), findsNothing);
    });

    testWidgets('Community alerts holds neighbour reports, the area lists and the chat', (tester) async {
      await mount(tester, demo: true, child: alerts);
      await tester.ensureVisible(find.textContaining('Community alerts').first);
      await tester.tap(find.textContaining('Community alerts').first);
      await pumpFor(tester, 1200);
      expect(find.byType(CommunityAlertsScreen), findsOneWidget);
      expect(find.text('Neighbour reports'), findsOneWidget);
      expect(find.text('Fall armyworm on maize'), findsWidgets);
      expect(find.text('Elsewhere in KwaZulu-Natal'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('Share proof with your area'), findsOneWidget);
    });

    testWidgets('the alarm lists water first, then farm alerts, and leaves out the rest',
        (tester) async {
      await mount(tester, demo: true, child: alerts);
      await openAlarm(tester);
      expect(find.byType(AlarmScreen), findsOneWidget);
      expect(find.text('Water'), findsOneWidget);
      expect(find.text('Vote and add to the community voice'), findsOneWidget);
      expect(find.text('Weather'), findsOneWidget, reason: 'the demo forecast has a frost, heat and rain');
      expect(find.text('Fall armyworm spotted 12 km away'), findsOneWidget);
      expect(find.text('Foot-and-mouth movement restriction'), findsOneWidget);
      expect(find.text('Frost risk tonight'), findsOneWidget);
      expect(find.text('Load shedding stage 4 tonight'), findsNothing);
      final water = tester.getTopLeft(find.text('Water')).dy;
      final farm = tester.getTopLeft(find.text('On your farm')).dy;
      expect(water < farm, isTrue, reason: 'water has the most emphasis');
    });

    testWidgets('the alarm opens the water page to vote', (tester) async {
      await mount(tester, demo: true, child: alerts);
      await openAlarm(tester);
      await tester.tap(find.text('Vote and add to the community voice'));
      await pumpFor(tester, 1200);
      expect(find.byType(WaterScreen), findsOneWidget);
    });

    testWidgets('the frost alert opens the add-stock sheet with the discount already on',
        (tester) async {
      await mount(tester, demo: true, child: alerts);
      await openAlarm(tester);
      await tester.ensureVisible(find.text('Frost risk tonight'));
      await tester.tap(find.text('Frost risk tonight'));
      await pumpFor(tester, 800);
      expect(find.text('🌱 Add stock'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('the foot-and-mouth alert opens the herd screen', (tester) async {
      await mount(tester, demo: true, herd: const [], child: alerts);
      await openAlarm(tester);
      await tester.ensureVisible(find.text('Foot-and-mouth movement restriction'));
      await tester.tap(find.text('Foot-and-mouth movement restriction'));
      await pumpFor(tester, 800);
      expect(find.byType(LivestockHomeScreen), findsOneWidget);
    });

    test('area outbreaks merge demo and live reports, drop healthy scans, urgent first', () {
      final live = [
        OutbreakReport(
            id: 'r1',
            disease: 'Late_Blight',
            severity: 'red',
            kind: OutbreakKind.plant,
            location: const LatLng(-29.6, 30.4),
            region: 'KZN Midlands',
            reportedAt: DateTime.now()),
        OutbreakReport(
            id: 'r2',
            disease: 'Healthy',
            severity: 'green',
            kind: OutbreakKind.plant,
            location: const LatLng(-29.6, 30.4),
            region: 'KZN Midlands',
            reportedAt: DateTime.now()),
      ];
      final list = buildAreaOutbreaks(live);
      expect(list.any((o) => o.disease.toLowerCase() == 'healthy'), isFalse);
      final blight = list.firstWhere(
          (o) => o.disease == 'Late Blight' && o.region == 'KZN Midlands');
      expect(blight.reports, 3, reason: 'two demo sightings plus one live report');
      expect(blight.severity, 'red');
      expect(list.first.severity, 'red');
    });

    testWidgets('reporting an outbreak lands on the map feed and opens a neighbour case',
        (tester) async {
      final rig = await mount(tester,
          demo: false,
          child: alerts,
          user: const AppUser(
              uid: _me, name: 'Sipho', email: '', region: 'North Coast', farmType: 'both'));
      await tester.tap(find.text('Report an outbreak'));
      await pumpFor(tester, 800);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await pumpFor(tester, 600);
      await tester.tap(find.text('Rust').last);
      await pumpFor(tester, 600);
      await tester.tap(find.text('Send report'));
      await pumpFor(tester, 800);
      expect(rig.state.cases.any((c) => c.title == 'Rust' && c.mine), isTrue);
    });
  });

  group('Grow shell', () {
    const farmer = AppUser(
        uid: _me, name: 'Sipho Dlamini', email: 's@x.co', region: 'North Coast', farmType: 'both');

    testWidgets('opens on the scanners, before orders and settings', (tester) async {
      await mount(tester, child: const GrowShell(), user: farmer);
      expect(find.text('Sawubona, Sipho'), findsOneWidget);
      expect(find.text('Scan a crop'), findsOneWidget);
      expect(find.text('Check a sick animal'), findsOneWidget);
      for (final t in ['Home', 'Orders', 'Alerts', 'Settings']) {
        expect(find.text(t), findsWidgets);
      }
      final scan = tester.getTopLeft(find.text('Scan a crop')).dy;
      final herd = tester.getTopLeft(find.text('Your herd')).dy;
      expect(scan < herd, isTrue, reason: 'scanning comes first');
    });

    testWidgets('tabs switch to orders, alerts and settings', (tester) async {
      await mount(tester, child: const GrowShell(), user: farmer, demo: true);
      await tester.tap(find.text('Orders').last);
      await pumpFor(tester, 800);
      expect(find.text('You have made'), findsOneWidget);
      await tester.tap(find.text('Alerts').last);
      await pumpFor(tester, 800);
      expect(find.text('Report an outbreak'), findsOneWidget);
      await tester.tap(find.text('Settings').last);
      await pumpFor(tester, 800);
      expect(find.text('Personal details'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('the Orders tab badge counts orders to send out', (tester) async {
      await mount(tester, child: const GrowShell(), user: farmer, demo: true);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('settings saves personal and store details', (tester) async {
      final rig = await mount(tester, child: const GrowShell(), user: farmer);
      await tester.tap(find.text('Settings').last);
      await pumpFor(tester, 800);
      await tester.enterText(find.widgetWithText(TextFormField, 'Cell number'), '0821234567');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Farm name (shown in bold)'), 'Dlamini Acres');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await pumpFor(tester, 800);
      expect(rig.state.profile.phone, '0821234567');
      expect(rig.state.profile.farmName, 'Dlamini Acres');
    });

    testWidgets('the Water radar tile opens the radar with the farm herd section',
        (tester) async {
      await mount(tester, child: const GrowShell(), user: farmer, herd: [
        for (var i = 0; i < 8; i++)
          Cattle(id: 'c$i', tagNumber: 'T$i', tagStandard: TagStandard.visual)
      ]);
      await tester.ensureVisible(find.text('Water radar'));
      await tester.tap(find.text('Water radar'));
      await pumpFor(tester, 1500);
      expect(find.byType(WaterScreen), findsOneWidget);
      expect(find.byType(FarmWaterSection), findsOneWidget);
      expect(find.text('Your herd'), findsOneWidget);
      expect(find.textContaining('Your herd needs about 400 litres a day'),
          findsOneWidget);
    });
  });

  group('wiring into the shared package', () {
    const thandi = AppUser(
        uid: 'u-42',
        name: 'Thandi Nkosi',
        email: 't@example.com',
        region: 'KwaZulu-Natal',
        farmType: 'both');

    ProviderContainer wired([AppUser? user]) {
      final c = ProviderContainer(overrides: [
        ...marketOverrides(),
        currentUserProvider.overrideWithValue(user),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('the signed-in farmer is the same person in Nolifa Drop', () {
      final c = wired(thandi);
      expect(c.read(marketUidProvider), 'u-42');
      expect(c.read(marketNameProvider), 'Thandi');
    });

    test('signed out, or with no name, falls back to the guest defaults', () {
      expect(wired().read(marketUidProvider), 'guest');
      expect(wired().read(marketNameProvider), 'Neighbour');
      const nameless = AppUser(
          uid: 'u-1', name: '  ', email: '', region: '', farmType: 'both');
      expect(wired(nameless).read(marketNameProvider), 'Neighbour');
    });

    test('without Firebase the market and water data stay on the device', () {
      final c = wired(thandi);
      expect(c.read(marketRepositoryProvider), isA<LocalMarketRepository>());
      expect(c.read(waterRepositoryProvider), isA<LocalWaterRepository>());
    });
  });

  group('welcome back notification', () {
    const farmer = AppUser(uid: _me, name: 'Sipho Dlamini', email: 's@x.co', region: 'North Coast', farmType: 'both');

    testWidgets('opening the shell notifies "Welcome back, Sipho" with orders to send', (tester) async {
      final fake = _FakeNotices();
      final rig = await mount(tester, child: const GrowShell(), user: farmer, demo: true, notices: fake);
      await pumpFor(tester, 2000);
      expect(fake.sent, hasLength(1));
      expect(fake.sent.single.$1, 'Welcome back, Sipho');
      expect(fake.sent.single.$2, contains('2 orders to send out'));
      await tester.tap(find.text('Orders').last);
      await pumpFor(tester, 2000);
      expect(fake.sent, hasLength(1), reason: 'once per launch');
      await rig.shutDown(tester);
    });

    test('the farmer update leads with orders, then water, then outbreaks', () {
      expect(farmerUpdate(1, 'Umlazi water is low (33%)', 2),
          '1 order to send out. Umlazi water is low (33%). 2 urgent outbreaks near you.');
      expect(farmerUpdate(0, null, 0), 'Everything looks calm on the farm.');
    });
  });

  group('Water provider and low-water pop-up', () {
    const farmer = AppUser(uid: _me, name: 'Sipho Dlamini', email: 's@x.co', region: 'North Coast', farmType: 'both');

    testWidgets('opening the app with low water shows a pop-up that leads to the vote page', (tester) async {
      await mount(tester, child: const GrowShell(), user: farmer, demo: true, waterPrompt: true);
      await pumpFor(tester, 1500);
      expect(find.textContaining('water is low'), findsWidgets);
      await tester.tap(find.text('Vote for help'));
      await pumpFor(tester, 1500);
      expect(find.byType(WaterScreen), findsOneWidget);
      await tester.scrollUntilVisible(find.byType(FarmWaterSection), 600,
          scrollable: find.descendant(of: find.byType(WaterScreen), matching: find.byType(Scrollable)).first);
      expect(find.byType(FarmWaterSection), findsOneWidget);
      await pumpFor(tester, 2000);
    });

    testWidgets('a farm registers as a supplier and offers help to a community that asked', (tester) async {
      final rig = await mount(tester, child: const WaterSupplierScreen(), user: farmer, demo: true);
      expect(find.text('Communities asking for water'), findsNothing, reason: 'not a supplier yet');
      await tester.tap(find.byType(Switch).first);
      await pumpFor(tester, 800);
      expect(rig.container.read(supplierProvider).supplier.enabled, isTrue);
      expect(find.text('Communities asking for water'), findsOneWidget);
      await rig.shutDown(tester);
    });
  });

  group('supplier wiring', () {
    test('registering as a water supplier makes the farm allowed to answer requests', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(overrides: [
        ...marketOverrides(),
        currentUserProvider.overrideWithValue(const AppUser(uid: 'f9', name: 'X', email: '', region: '', farmType: 'both')),
      ]);
      addTearDown(c.dispose);
      expect(c.read(waterUtilityProvider), isFalse);
      c.read(supplierProvider.notifier).update(const WaterSupplier(enabled: true));
      expect(c.read(waterUtilityProvider), isTrue);
      c.read(supplierProvider.notifier).update(const WaterSupplier(enabled: false));
      expect(c.read(waterUtilityProvider), isFalse);
    });
  });

  group('Water radar for farmers', () {
    Cattle cow(String tag, {CattleStatus status = CattleStatus.active}) =>
        Cattle(
            id: tag,
            tagNumber: tag,
            tagStandard: TagStandard.visual,
            status: status);

    Future<Rig> mountSection(WidgetTester tester, List<Cattle> herd) => mount(
          tester,
          herd: herd,
          child: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: FarmWaterSection(),
            ),
          ),
        );

    testWidgets(
        'counts the active animals in the herd register and tells the planner',
        (tester) async {
      final rig = await mountSection(tester, [
        cow('A1'),
        cow('A2'),
        cow('A3'),
        cow('S1', status: CattleStatus.sold),
        cow('D1', status: CattleStatus.deceased),
      ]);
      expect(find.text('3 head'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
      expect(find.textContaining('Your herd needs about 150 litres a day'),
          findsOneWidget);
      expect(find.textContaining('Counted from your herd register.'), findsOneWidget);
      expect(rig.container.read(waterProvider).prefs.herd, 3);
      // The register decides, so there is no stepper to disagree with it.
      expect(find.text('+10'), findsNothing);
    });

    testWidgets('without a register it offers a stepper that feeds the planner',
        (tester) async {
      final rig = await mountSection(tester, const []);
      expect(find.textContaining('No animals counted yet'), findsOneWidget);

      await tester.tap(find.text('+10'));
      await pumpFor(tester, 400);
      await tester.tap(find.text('+10'));
      await pumpFor(tester, 400);
      await tester.tap(find.text('-1'));
      await pumpFor(tester, 1200);
      expect(rig.container.read(waterProvider).prefs.herd, 19);
      expect(find.text('19 head'), findsOneWidget);
      expect(find.textContaining('about 950 litres a day'), findsOneWidget);

      await tester.tap(find.text('-10'));
      await tester.tap(find.text('-10'));
      await pumpFor(tester, 400);
      expect(rig.container.read(waterProvider).prefs.herd, 0,
          reason: 'never below zero');
    });

    testWidgets('shows how long the stored tank lasts the herd',
        (tester) async {
      final rig =
          await mountSection(tester, [for (var i = 0; i < 10; i++) cow('T$i')]);
      expect(find.textContaining('No tank saved yet'), findsOneWidget);

      rig.container.read(waterProvider.notifier).setTank(2000);
      await pumpFor(tester, 600);
      expect(find.text('Tank on site: 2 000 L'), findsOneWidget);
      expect(find.text('4.0 days for the herd'), findsOneWidget);

      rig.container.read(waterProvider.notifier).setTank(600);
      await pumpFor(tester, 600);
      expect(find.text('1.2 days for the herd'), findsOneWidget);
    });
  });
}
