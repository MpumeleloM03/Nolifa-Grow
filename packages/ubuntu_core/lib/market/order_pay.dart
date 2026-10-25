import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'market_models.dart' show Plan;

/// Opens the card payment that switches a farm to [plan]. The plan is on by
/// itself as soon as the payment goes through. Same contract as [orderPaymentProvider].
/// Opens the card payment for an order and returns a plain sentence if it could
/// not start, or null when the card page is open. The app supplies it (it needs
/// the server and the phone's browser); null means there is no card payment, as
/// on the phone alone.
final planPaymentProvider = Provider<Future<String?> Function(Plan plan)?>((ref) => null);

final orderPaymentProvider = Provider<Future<String?> Function(String orderId)?>((ref) => null);
