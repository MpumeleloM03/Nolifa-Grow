// Walks the real demo accounts (farmer, customer, driver) through a whole delivery with the
// app's own repositories against the cloud project: list stock, order, be told, pack, claim,
// track, collect, deliver with the PIN, confirm, and get paid.
//
//   SUPABASE_URL=... SUPABASE_ANON_KEY=... flutter test test_live/accounts_flow_test.dart
//
// The logins are read from ~/nolifa-accounts.local.txt. Skipped when that file or the keys are
// missing. Needs the farm approved and the driver approved (tools/e2e_cloud.py does both).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

final _url = Platform.environment['SUPABASE_URL'] ?? '';
final _anon = Platform.environment['SUPABASE_ANON_KEY'] ?? '';
final _file = File('${Platform.environment['HOME']}/nolifa-accounts.local.txt');

class Who {
  Who(this.client, this.id);
  final SupabaseClient client;
  final String id;
  SupabaseMarketRepository get market => SupabaseMarketRepository(db: client);
}

Future<Who> signIn(String key) async {
  final line = _file.readAsLinesSync().lastWhere((l) => l.startsWith('$key '));
  final parts = line.split(RegExp(r'\s+'));
  final c = SupabaseClient(_url, _anon, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
  final res = await c.auth.signInWithPassword(email: parts[1], password: parts[2]);
  return Who(c, res.user!.id);
}

Future<Order> see(Who p, String id, [bool Function(Order o)? until]) async {
  final list = await p.market
      .watchOrders(p.id)
      .firstWhere((l) => l.any((x) => x.id == id && (until == null || until(x))))
      .timeout(const Duration(seconds: 20));
  return list.firstWhere((x) => x.id == id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  final skip = (_url.isEmpty || _anon.isEmpty || !_file.existsSync()) ? 'needs SUPABASE_URL, SUPABASE_ANON_KEY and ~/nolifa-accounts.local.txt' : null;

  test('leave one order in each state for the screens to show', () async {
    final farmer = await signIn('fatboy');
    final buyer = await signIn('customer');
    final driver = await signIn('driver');
    final run = DateTime.now().millisecondsSinceEpoch;
    final pid = 'e2e-states-$run';
    await farmer.market.putProduct(
        Product(id: pid, name: 'Chicken breast', emoji: '🍗', category: Category.meat, farm: 'Fatboy Butcheries', km: 12, price: 80, unit: 'kg', stock: 60, ownerId: farmer.id),
        farmer.id);
    await buyer.market.watchProducts(buyer.id).firstWhere((l) => l.any((p) => p.id == pid)).timeout(const Duration(seconds: 20));

    Order make(String tag, PayMethod m) => Order(
          id: 'UD-$tag-$run'.substring(0, 12).toUpperCase(),
          lines: [OrderLine('Chicken breast', '🍗', 2, 80, ownerId: farmer.id, productId: pid)],
          deliveryFee: 25,
          serviceFee: 4.8,
          method: m,
          status: OrderStatus.newOrder,
          customer: 'Zanele',
          pickup: 'Fatboy Butcheries',
          dropArea: 'Umhlanga',
          pin: '4321',
          placed: DateTime.now(),
          customerId: buyer.id,
          farmerId: farmer.id,
          route: 'local',
        );

    // 1. A card order nobody has paid yet.
    await buyer.market.placeOrder(make('K', PayMethod.fnbPay), buyer.id, '4321');
    // 2. Packed, waiting for a driver.
    final b = make('P', PayMethod.cash);
    await buyer.market.placeOrder(b, buyer.id, '4321');
    var o = await see(farmer, b.id);
    await farmer.market.putOrder(o.copyWith(status: OrderStatus.findingDriver, commission: 0.05, rev: o.rev + 1), farmer.id);
    // 3. Delivered, waiting for the buyer to confirm. (The driver does one job at a time.)
    final d = make('D', PayMethod.cash);
    await buyer.market.placeOrder(d, buyer.id, '4321');
    o = await see(farmer, d.id);
    await farmer.market.putOrder(o.copyWith(status: OrderStatus.findingDriver, commission: 0.05, rev: o.rev + 1), farmer.id);
    await see(driver, d.id);
    expect(await driver.market.claimJob(d.id, driver.id, 'Sipho'), isTrue);
    var dm = await see(driver, d.id, (x) => x.driverIsMe);
    await driver.market.putOrder(dm.copyWith(status: OrderStatus.pickedUp, pickupProof: true, rev: dm.rev + 1), driver.id);
    expect((await driver.market.deliverWithPin(d.id, '4321'))['outcome'], 'delivered');
    // 4. On the road.
    final c = make('R', PayMethod.cash);
    await buyer.market.placeOrder(c, buyer.id, '4321');
    o = await see(farmer, c.id);
    await farmer.market.putOrder(o.copyWith(status: OrderStatus.findingDriver, commission: 0.05, rev: o.rev + 1), farmer.id);
    await see(driver, c.id);
    expect(await driver.market.claimJob(c.id, driver.id, 'Sipho'), isTrue);
    dm = await see(driver, c.id, (x) => x.driverIsMe);
    await driver.market.putOrder(dm.copyWith(status: OrderStatus.pickedUp, pickupProof: true, rev: dm.rev + 1), driver.id);
    await driver.client.schema('delivery_api').rpc('post_location', params: {'p_lat': -29.79, 'p_lng': 31.04, 'p_heading': 30.0, 'p_speed': 35.0, 'p_accuracy': 6.0});
  }, skip: skip);
}
