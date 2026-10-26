// Lists the Fatboy Butcheries range for the demo farmer, with stock. Run after clearing old test orders.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  final url = Platform.environment['SUPABASE_URL'] ?? '', anon = Platform.environment['SUPABASE_ANON_KEY'] ?? '';
  test('list the Fatboy range', () async {
    final c = SupabaseClient(url, anon, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
    final res = await c.auth.signInWithPassword(email: 'farmer@demo.nolifa.co.za', password: 'NolifaDemo1');
    final repo = SupabaseMarketRepository(db: c);
    for (final p in fatboyRange) {
      await repo.putProduct(p.copyWith(stock: 40, ownerId: res.user!.id), res.user!.id);
    }
    expect((await c.from('market_products').select()).length, fatboyRange.length);
  }, skip: url.isEmpty ? 'needs SUPABASE_URL' : null);
}
