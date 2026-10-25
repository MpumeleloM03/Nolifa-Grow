import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

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

Future<void> _pump(WidgetTester tester, [int ms = 1400]) async {
  for (var t = 0; t < ms; t += 200) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  Widget child, {
  bool demo = true,
}) async {
  _ignoreFontOverflow();
  tester.view.physicalSize = const Size(1206, 12000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(overrides: [
    marketUidProvider.overrideWithValue('u-me'),
    marketNameProvider.overrideWithValue('Thandi'),
    marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
    waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: AppTheme.build(), home: Scaffold(body: child)),
  ));
  if (!demo) c.read(marketProvider.notifier).setDemoMode(false);
  await _pump(tester);
  return c;
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _pump(tester, 600);
}

void main() {
  group('Shop home', () {
    testWidgets('lists farms with their names and offerings, nearest first', (tester) async {
      final c = await _mount(tester, const ShopHomePage());
      final farms = groupFarms(c.read(marketProvider).products);
      expect(farms.length, greaterThan(3));
      expect(find.text('Farms near you'), findsOneWidget);
      // First farm card is on screen with its offerings and delivery label.
      expect(find.text(farms.first.name), findsWidgets);
      expect(find.text(farms.first.products.first.name), findsWidgets);
      expect(find.text('Fresh near you'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('quick add puts it in the cart and the badge counts', (tester) async {
      final c = await _mount(tester, const ShopHomePage());
      expect(c.read(marketProvider).cartCount, 0);
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await _pump(tester, 600);
      expect(c.read(marketProvider).cartCount, 1);
      expect(find.textContaining('Checkout'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('a basket holds one farm: adding from another asks first', (tester) async {
      final c = await _mount(tester, const ShopHomePage());
      final s = c.read(marketProvider);
      final farms = groupFarms(s.products);
      c.read(marketProvider.notifier).add(farms.first.products.first.id);
      await _pump(tester, 600);
      // Second farm's quick add.
      final other = farms[1].products.first;
      final add = find.descendant(
          of: find.byType(FarmCard).at(1), matching: find.byIcon(Icons.add_rounded));
      await tester.ensureVisible(add.first);
      await tester.tap(add.first, warnIfMissed: false);
      await _pump(tester, 600);
      expect(find.text('Start a new basket?'), findsOneWidget);
      await tester.tap(find.text('Start new'));
      await _pump(tester, 600);
      expect(c.read(marketProvider).cartFarm, other.farm);
      await _end(tester);
    });

    testWidgets('search narrows farms to a match and says so when none match', (tester) async {
      final c = await _mount(tester, const ShopHomePage());
      final total = groupFarms(c.read(marketProvider).products).length;
      await tester.enterText(find.byType(TextFormField), 'eggs');
      await _pump(tester, 600);
      expect(find.byType(FarmCard).evaluate().length, lessThan(total));
      expect(find.byType(FarmCard), findsWidgets);
      await tester.enterText(find.byType(TextFormField), 'zzzz');
      await _pump(tester, 600);
      expect(find.byType(FarmCard), findsNothing);
      expect(find.textContaining('No farms match'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('delivery address comes from settings', (tester) async {
      final c = await _mount(tester, const ShopHomePage());
      expect(find.text('Set your address'), findsOneWidget);
      final store = c.read(marketProvider.notifier);
      store.updateProfile(c.read(marketProvider).profile.copyWith(address: '5 Main Rd', suburb: 'Pinetown'));
      await _pump(tester, 400);
      expect(find.text('5 Main Rd, Pinetown'), findsOneWidget);
      await _end(tester);
    });
  });

  group('Farm page', () {
    testWidgets('shows the farm, how it delivers and everything it sells', (tester) async {
      final c = await _mount(tester, const SizedBox());
      final farm = groupFarms(c.read(marketProvider).products)
          .firstWhere((f) => f.delivery == DeliveryMode.self);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.build(), home: FarmScreen(farmId: farm.id)),
      ));
      await _pump(tester);
      expect(find.text(farm.name), findsWidgets);
      expect(find.textContaining('brings your order to your door'), findsOneWidget);
      expect(find.byType(ProductCard).evaluate().length, greaterThan(0));
      await _end(tester);
    });

    testWidgets('an unknown farm says it is not selling', (tester) async {
      await _mount(tester, const FarmScreen(farmId: 'nobody'));
      expect(find.textContaining('not selling'), findsOneWidget);
      await _end(tester);
    });
  });

  group('Business page', () {
    testWidgets('selling opens only after register, verify and plan', (tester) async {
      final c = await _mount(tester, const BusinessScreen(), demo: false);
      final store = c.read(marketProvider.notifier);
      expect(c.read(marketProvider).canSell, isFalse);
      expect(find.text('Finish the steps to start selling'), findsOneWidget);

      await tester.tap(find.text('Register'));
      await _pump(tester, 600);
      expect(c.read(marketProvider).business.registered, isTrue);

      for (final step in farmerSteps) {
        store.completeKyc(KycRole.farmer, step.id);
      }
      await _pump(tester, 400);
      expect(c.read(marketProvider).canSell, isFalse);

      store.setPlan(Plan.grow);
      await _pump(tester, 600);
      expect(c.read(marketProvider).canSell, isFalse, reason: 'land photos still missing');
      store.submitLandEvidence();
      await _pump(tester, 600);
      expect(c.read(marketProvider).canSell, isTrue);
      expect(find.text('Selling with limits'), findsOneWidget);
      store.requestInspection(InspectionRoute.coopDay);
      store.recordInspection(passed: true);
      await _pump(tester, 600);
      expect(find.text('Your store is open'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('choosing to deliver yourself changes the fee card and the profile', (tester) async {
      final c = await _mount(tester, const BusinessScreen(), demo: false);
      await tester.ensureVisible(find.textContaining('I deliver'));
      await tester.tap(find.textContaining('I deliver'));
      await _pump(tester, 600);
      expect(c.read(marketProvider).profile.delivery, DeliveryMode.self);
      expect(find.text('Your delivery fee'), findsOneWidget);
      expect(find.text('Yours'), findsOneWidget);

      await tester.ensureVisible(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await _pump(tester, 400);
      expect(c.read(marketProvider).profile.deliveryFee, 5);

      await tester.ensureVisible(find.textContaining('Nolifa Delivery').first);
      await tester.tap(find.textContaining('Nolifa Delivery').first);
      await _pump(tester, 600);
      expect(c.read(marketProvider).profile.delivery, DeliveryMode.platform);
      await _end(tester);
    });

    testWidgets('the fee card matches the plan', (tester) async {
      final c = await _mount(tester, const BusinessScreen(), demo: false);
      c.read(marketProvider.notifier).setPlan(Plan.coop);
      await _pump(tester, 600);
      await tester.ensureVisible(find.text('What it costs'));
      expect(find.text('R199'), findsOneWidget);
      expect(find.text('3%'), findsWidgets);
      await _end(tester);
    });
  });

  group('Settings and orders', () {
    testWidgets('settings saves name, phone, address and notification choices', (tester) async {
      final c = await _mount(tester, const ProfileSettingsScreen(), demo: false);
      expect(find.widgetWithText(TextFormField, 'Full name'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Thandi M');
      await tester.enterText(find.widgetWithText(TextFormField, 'Cell number'), '0831112222');
      await tester.enterText(find.widgetWithText(TextFormField, 'Delivery address'), '9 Oak Ave');
      await tester.ensureVisible(find.text('Outbreak alerts'));
      await tester.tap(find.text('Outbreak alerts'));
      await _pump(tester, 300);
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await _pump(tester, 600);
      final p = c.read(marketProvider).profile;
      expect((p.name, p.phone, p.address), ('Thandi M', '0831112222', '9 Oak Ave'));
      expect(p.notifyOutbreaks, isFalse);
      expect(find.text('Save changes'), findsNothing, reason: 'button reads Saved now');
      await _end(tester);
    });

    testWidgets('a farmer also sees the store section', (tester) async {
      await _mount(tester, const ProfileSettingsScreen(farmer: true), demo: false);
      expect(find.text('Your store'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Farm name (shown in bold)'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('orders screen is empty at first, then lists a placed order', (tester) async {
      final c = await _mount(tester, const OrdersScreen());
      c.read(marketProvider.notifier).setDemoMode(false);
      await _pump(tester, 400);
      expect(find.text('No orders yet'), findsOneWidget);
      c.read(marketProvider.notifier).setDemoMode(true);
      await _pump(tester, 400);
      final store = c.read(marketProvider.notifier);
      final before = find.byType(OrderTile).evaluate().length;
      store.add('p-water');
      final id = store.place(PayMethod.fnbPay);
      await _pump(tester, 600);
      expect(find.byType(OrderTile).evaluate().length, before + 1);
      expect(find.textContaining(id), findsWidgets);
      expect(find.text('On the way'), findsOneWidget);
      // Let the simulated driver finish so no timers outlive the test.
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await _end(tester);
    });

    testWidgets('help answers the money questions', (tester) async {
      await _mount(tester, const HelpScreen());
      expect(find.text('How does my money stay safe?'), findsOneWidget);
      expect(find.text('Who delivers?'), findsOneWidget);
      await _end(tester);
    });
  });

  group('honesty', () {
    testWidgets('the offline guide separates what works offline from what needs a connection or a person', (tester) async {
      await _mount(tester, const OfflineGuideScreen());
      expect(find.text('Works with no signal'), findsOneWidget);
      expect(find.text('Needs a connection'), findsOneWidget);
      expect(find.text('Needs another person'), findsOneWidget);
      expect(find.textContaining('Leaf scanner'), findsOneWidget);
      expect(find.textContaining('Water trucks'), findsOneWidget);
      expect(find.textContaining('two phones do not see each other'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('plans say what is free and why selling has a fee', (tester) async {
      await _mount(tester, const PlansScreen());
      expect(find.text('Free for everyone, always'), findsOneWidget);
      expect(find.text('Paid: selling on Nolifa Drop'), findsOneWidget);
      expect(find.textContaining('test with farmers'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('the trust page lists what is simulated', (tester) async {
      await _mount(tester, const TrustCenterScreen());
      expect(find.text('What is simulated in this prototype'), findsOneWidget);
      expect(find.textContaining('No real money moves'), findsWidgets);
      await _end(tester);
    });

    testWidgets('the water page says where the numbers come from and what happens if nobody responds', (tester) async {
      await _mount(tester, const WaterScreen());
      await tester.ensureVisible(find.text('Where this comes from'));
      expect(find.text('Who measures it'), findsOneWidget);
      expect(find.text('How fresh it is'), findsOneWidget);
      expect(find.text('Who responds'), findsOneWidget);
      expect(find.text('If nobody responds'), findsOneWidget);
      expect(find.textContaining('simulated and labelled as demo'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('checkout and wallet say the payment is simulated', (tester) async {
      final c = await _mount(tester, const SizedBox());
      c.read(marketProvider.notifier).add('p-water');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.build(), home: const CheckoutScreen()),
      ));
      await _pump(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await _pump(tester, 600);
      expect(find.textContaining('the payment is simulated'), findsOneWidget);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.build(), home: const WalletScreen()),
      ));
      await _pump(tester);
      expect(find.textContaining('simulated'), findsWidgets);
      await _end(tester);
    });
  });

  group('savings', () {
    testWidgets('shows what was saved, the fees paid, and deals to take', (tester) async {
      final c = await _mount(tester, const SavingsScreen());
      expect(find.text('You have saved'), findsOneWidget);
      expect(find.text('Rescue deals now'), findsOneWidget);
      expect(find.text('Group buys you can join'), findsOneWidget);
      expect(find.textContaining('After fees you are'), findsOneWidget);
      await _end(tester);
      expect(c.read(marketProvider).saved, greaterThan(0));
    });

    test('rescue savings come from the orders, fees from the service and delivery fees', () {
      final p = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('u'),
        marketNameProvider.overrideWithValue('S'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
      ]);
      addTearDown(p.dispose);
      final st = p.read(marketProvider.notifier);
      final rescue = p.read(marketProvider).products.firstWhere((x) => x.wasPrice != null && x.buyable);
      st.add(rescue.id, 2);
      st.place(PayMethod.fnbPay);
      final v = householdSavings(p.read(marketProvider));
      expect(v.orders, 1);
      expect(v.rescueSaved, r2((rescue.wasPrice! - rescue.price) * 2));
      final o = p.read(marketProvider).myOrders.first;
      expect(v.fees, r2(o.serviceFee + o.deliveryFee));
      expect(v.spent, o.subtotal);
      expect(v.net, r2(v.totalSaved - v.fees));
      expect(v.rescueNow, isNotEmpty);
    });
  });

  group('phone check', () {
    testWidgets('a wrong code is refused, the right one verifies the number', (tester) async {
      final c = await _mount(tester, const PhoneVerifyScreen(), demo: false);
      await tester.enterText(find.widgetWithText(TextFormField, 'Cell number (0821234567)'), '123');
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<GlassButton>(find.widgetWithText(GlassButton, 'Send code')).onPressed, isNull,
          reason: 'not a real number');
      await tester.enterText(find.widgetWithText(TextFormField, 'Cell number (0821234567)'), '082 123 4567');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Send code'));
      await _pump(tester, 400);
      expect(find.textContaining('no SMS is sent'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, '4-digit code'), '0000');
      await tester.tap(find.text('Verify'));
      await _pump(tester, 300);
      expect(find.text('That code does not match'), findsOneWidget);
      expect(c.read(marketProvider).profile.phoneVerified, isFalse);
      await tester.enterText(find.widgetWithText(TextFormField, '4-digit code'), PhoneVerifyScreen.demoCode);
      await tester.tap(find.text('Verify'));
      await _pump(tester, 500);
      expect(c.read(marketProvider).profile.phoneVerified, isTrue);
      expect(c.read(marketProvider).profile.phone, '0821234567');
      expect(find.textContaining('Your phone is verified'), findsOneWidget);
      await _end(tester);
    });
  });

  group('Driver job', () {
    Future<ProviderContainer> mountJob(
      WidgetTester tester, {
      required List<String> navigated,
      required bool Function() photo,
      bool withMap = false,
    }) async {
      _ignoreFontOverflow();
      tester.view.physicalSize = const Size(1206, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('u-drv'),
        marketNameProvider.overrideWithValue('Sipho'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        navigateProvider.overrideWithValue((d) async {
          navigated.add(d);
          return true;
        }),
        proofPhotoProvider.overrideWithValue(() async => photo()),
        if (withMap)
          jobMapProvider.overrideWithValue((o) => Text('map:${o.id}:${o.status.name}')),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.build(), home: const Scaffold(body: DrivePage())),
      ));
      final store = c.read(marketProvider.notifier);
      for (final step in driverSteps) {
        store.completeKyc(KycRole.driver, step.id);
      }
      store.toggleOnline();
      store.accept('UD-1033');
      await _pump(tester);
      return c;
    }

    testWidgets('after accepting, Navigate opens directions to the farm, then to the customer', (tester) async {
      final went = <String>[];
      final c = await mountJob(tester, navigated: went, photo: () => true);
      expect(find.text('Navigate to the farm'), findsOneWidget);
      await tester.tap(find.text('Navigate to the farm'));
      await _pump(tester, 400);
      expect(went, ['Dlamini Mill']);

      await tester.tap(find.textContaining('Picked up'));
      await _pump(tester, 600);
      expect(c.read(marketProvider).orderById('UD-1033')!.status, OrderStatus.pickedUp);
      expect(find.text('Navigate to the customer'), findsOneWidget);
      await tester.tap(find.text('Navigate to the customer'));
      await _pump(tester, 400);
      expect(went.last, 'Chatsworth');
      await _end(tester);
    });

    testWidgets('an accepted job shows the route map, and it follows the job from farm to customer', (tester) async {
      final c = await mountJob(tester, navigated: [], photo: () => true, withMap: true);
      expect(find.text('map:UD-1033:assigned'), findsOneWidget);
      await tester.tap(find.textContaining('Picked up'));
      await _pump(tester, 600);
      expect(c.read(marketProvider).orderById('UD-1033')!.status, OrderStatus.pickedUp);
      expect(find.text('map:UD-1033:pickedUp'), findsOneWidget);
      await tester.tap(find.textContaining('Delivered: take photo'));
      await _pump(tester, 800);
      await tester.enterText(find.byType(TextField).last, '1946');
      await tester.tap(find.text('Confirm'));
      await _pump(tester, 600);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await _end(tester);
    });

    testWidgets('three wrong PINs lock the order and open a dispute that freezes the money', (tester) async {
      final c = await mountJob(tester, navigated: [], photo: () => true);
      final store = c.read(marketProvider.notifier);
      await tester.tap(find.textContaining('Picked up'));
      await _pump(tester, 600);
      await tester.tap(find.textContaining('Delivered: take photo'));
      await _pump(tester, 800);
      for (final left in [2, 1]) {
        await tester.enterText(find.byType(TextField).last, '0000');
        await tester.tap(find.text('Confirm'));
        await _pump(tester, 400);
        expect(find.textContaining('$left ${left == 1 ? 'try' : 'tries'} left'), findsOneWidget);
        expect(c.read(marketProvider).orderById('UD-1033')!.pinAttempts, 3 - left);
      }
      await tester.enterText(find.byType(TextField).last, '0000');
      await tester.tap(find.text('Confirm'));
      await _pump(tester, 800);
      final o = c.read(marketProvider).orderById('UD-1033')!;
      expect(o.pinAttempts, 3);
      expect(o.disputed, isTrue);
      expect(o.dispute!.reason, DisputeReason.pinLocked);
      expect(o.status, OrderStatus.pickedUp, reason: 'not delivered');
      expect(o.released, isFalse, reason: 'money stays frozen');
      expect(find.textContaining('order is locked'), findsOneWidget);
      // Even the right PIN no longer works.
      expect(store.tryPin('UD-1033', '1946').locked, isTrue);
      expect(c.read(marketProvider).orderById('UD-1033')!.status, OrderStatus.pickedUp);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await _end(tester);
    });

    test('a correct PIN after one wrong try still delivers and the count stops mattering', () {
      final p = ProviderContainer(overrides: [
        marketUidProvider.overrideWithValue('u'),
        marketNameProvider.overrideWithValue('S'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
      ]);
      addTearDown(p.dispose);
      final st = p.read(marketProvider.notifier);
      for (final step in driverSteps) {
        st.completeKyc(KycRole.driver, step.id);
      }
      st.toggleOnline();
      st.accept('UD-1033');
      st.pickedUp('UD-1033');
      expect(st.tryPin('UD-1033', '9999').outcome, PinOutcome.wrong);
      expect(st.tryPin('UD-1033', '1946').delivered, isTrue);
      expect(p.read(marketProvider).orderById('UD-1033')!.status, OrderStatus.delivered);
    });

    test('places: the longest known name in an address wins, unknown places are null', () {
      expect(lookupPlace('12 Jacaranda Road, Umlazi V Section'), placeCoords['umlazi v section']);
      expect(lookupPlace('Shop 4, Pinetown'), placeCoords['pinetown']);
      expect(lookupPlace('Dlamini Mill'), placeCoords['dlamini mill']);
      expect(lookupPlace('Somewhere unknown'), isNull);
    });

    testWidgets('without a photo the job does not move on', (tester) async {
      final c = await mountJob(tester, navigated: [], photo: () => false);
      await tester.tap(find.textContaining('Picked up'));
      await _pump(tester, 600);
      expect(c.read(marketProvider).orderById('UD-1033')!.status, OrderStatus.assigned);
      expect(find.text('A photo is needed as proof first.'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('delivery takes the photo first, then asks for the PIN', (tester) async {
      final c = await mountJob(tester, navigated: [], photo: () => true);
      await tester.tap(find.textContaining('Picked up'));
      await _pump(tester, 600);
      await tester.tap(find.textContaining('Delivered: take photo'));
      await _pump(tester, 800);
      expect(find.text('Customer PIN'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '1946');
      await tester.tap(find.text('Confirm'));
      await _pump(tester, 600);
      expect(c.read(marketProvider).orderById('UD-1033')!.status, OrderStatus.delivered);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await _end(tester);
    });
  });
}
