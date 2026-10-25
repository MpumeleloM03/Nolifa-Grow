import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the card payment for an order and returns a plain sentence if it could
/// not start, or null when the card page is open. The app supplies it (it needs
/// the server and the phone's browser); null means there is no card payment, as
/// on the phone alone.
final orderPaymentProvider = Provider<Future<String?> Function(String orderId)?>((ref) => null);
