import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../supabase/supabase_boot.dart';

/// What the server says a driver is owed for one delivery. The server writes it
/// when the customer's PIN is accepted; the driver can read it and nothing more.
class DriverPayout {
  final String orderId;
  final double amount;
  final double base;
  final double distancePay;
  final double minimumTopUp;
  final double topUp; // what Nolifa adds above 80% of the buyer's fee
  final double km;
  final String state; // pending, released or cancelled
  final DateTime createdAt;

  const DriverPayout({
    required this.orderId,
    required this.amount,
    required this.base,
    required this.distancePay,
    required this.minimumTopUp,
    required this.topUp,
    required this.km,
    required this.state,
    required this.createdAt,
  });

  bool get pending => state == 'pending';
  bool get released => state == 'released';

  factory DriverPayout.fromRow(Map<String, dynamic> m) => DriverPayout(
        orderId: m['order_id'] as String,
        amount: (m['amount'] as num).toDouble(),
        base: (m['base'] as num).toDouble(),
        distancePay: (m['distance_pay'] as num).toDouble(),
        minimumTopUp: (m['minimum_top_up'] as num).toDouble(),
        topUp: (m['topup'] as num).toDouble(),
        km: (m['km'] as num).toDouble(),
        state: m['state'] as String,
        createdAt: DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
      );
}

/// The driver's own payouts, newest first. Empty on the phone alone, where the
/// running totals in the wallet are all there is.
final driverPayoutsProvider = StreamProvider<List<DriverPayout>>((ref) {
  if (!ref.watch(supabaseReadyProvider)) return Stream.value(const []);
  return liveTable(SupabaseBoot.client, 'driver_payouts', key: 'order_id').map(
      (rows) => [for (final r in rows) DriverPayout.fromRow(r)]..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});
