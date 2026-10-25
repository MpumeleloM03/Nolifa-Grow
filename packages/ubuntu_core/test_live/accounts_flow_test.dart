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

  test('a whole delivery with the demo accounts', () async {
    final farmer = await signIn('fatboy');
    final buyer = await signIn('customer');
    final driver = await signIn('driver');
    final run = DateTime.now().millisecondsSinceEpoch;

    // The farm lists a product; the buyer sees it.
    final pid = 'e2e-mince-$run';
    await farmer.market.putProduct(
        Product(id: pid, name: 'Beef mince', emoji: '🥩', category: Category.meat, farm: 'Fatboy Butcheries', km: 12, price: 100, unit: 'kg', stock: 40, ownerId: farmer.id),
        farmer.id);
    final listed = await buyer.market.watchProducts(buyer.id).firstWhere((l) => l.any((p) => p.id == pid)).timeout(const Duration(seconds: 20));
    expect(listed.firstWhere((p) => p.id == pid).farm, 'Fatboy Butcheries');

    // The buyer orders 2 kg, cash on delivery.
    final o = Order(
      id: 'UD-E2E-$run',
      lines: [OrderLine('Beef mince', '🥩', 2, 100, ownerId: farmer.id, productId: pid)],
      deliveryFee: 25,
      serviceFee: 6.0,
      method: PayMethod.cash,
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
    await buyer.market.placeOrder(o, buyer.id, '4321');
    var seen = await see(farmer, o.id);
    expect(seen.paid, isTrue, reason: 'cash on delivery counts as paid');
    final shelf = (await farmer.market.watchProducts(farmer.id).first).firstWhere((p) => p.id == pid);
    expect(shelf.stock, 38, reason: 'the shelf shrank on the server');
    final told = await farmer.client.from('notifications').select('kind').eq('uid', farmer.id);
    expect(told.map((r) => r['kind']), contains('order_new'));

    // The farm packs it and a driver takes it.
    await farmer.market.putOrder(seen.copyWith(status: OrderStatus.findingDriver, commission: 0.05, rev: seen.rev + 1), farmer.id); // Grow plan: 5%
    expect((await see(driver, o.id)).status, OrderStatus.findingDriver);
    expect(await driver.market.claimJob(o.id, driver.id, 'Sipho'), isTrue);
    await driver.client.schema('delivery_api').rpc('post_location', params: {'p_lat': -29.80, 'p_lng': 31.00, 'p_heading': 45.0, 'p_speed': 25.0, 'p_accuracy': 6.0});
    final track = await buyer.client.schema('drop_api').rpc('track_order', params: {'p_id': o.id}) as Map;
    expect((track['driver'] as Map)['lat'], closeTo(-29.80, 1e-6), reason: 'the buyer follows the driver');

    // Collect, deliver with the PIN, confirm.
    final mine = await see(driver, o.id, (x) => x.driverIsMe);
    await driver.market.putOrder(mine.copyWith(status: OrderStatus.pickedUp, pickupProof: true, rev: mine.rev + 1), driver.id);
    expect((await driver.market.deliverWithPin(o.id, '0000'))['outcome'], 'wrong');
    expect((await driver.market.deliverWithPin(o.id, '4321'))['outcome'], 'delivered');
    final delivered = await see(buyer, o.id, (x) => x.status == OrderStatus.delivered);
    await buyer.market.putOrder(delivered.copyWith(released: true, rating: 5, rev: delivered.rev + 1), buyer.id);
    final done = await see(buyer, o.id, (x) => x.released);
    expect(done.released, isTrue);

    // Everybody is paid once.
    final pay = await driver.client.from('driver_payouts').select().eq('order_id', o.id);
    expect(pay.length, 1, reason: 'the driver is paid once');
    expect((pay.single['amount'] as num) >= 24, isTrue, reason: 'never under the R24 floor');
    await driver.client.schema('delivery_api').rpc('go_offline');
    for (final p in [farmer, buyer, driver]) {
      final n = await p.client.from('notifications').select('kind').eq('uid', p.id);
      expect(n, isNotEmpty, reason: 'everyone was told something along the way');
    }
  });
}
