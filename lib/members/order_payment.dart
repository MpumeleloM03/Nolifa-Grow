import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot;
import 'package:url_launcher/url_launcher.dart';

/// Opens the Yoco card page for an order. The server works out the amount from
/// the order itself, and only Yoco's signed message can mark the order paid.
/// Returns a plain sentence when it could not start, or null when the page is open.
///
/// A new order reaches the server a moment after it is placed, so "not your
/// order" in the first seconds is retried.
Future<String?> startOrderPayment(String orderId) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    try {
      final r = await SupabaseBoot.client.functions.invoke('yoco-checkout', body: {'orderId': orderId});
      final d = r.data;
      if (d is Map && d['url'] is String) {
        final ok = await launchUrl(Uri.parse(d['url'] as String), mode: LaunchMode.externalApplication);
        return ok ? null : 'The card page could not be opened. Try again.';
      }
      return (d is Map ? d['error']?.toString() : null) ?? 'Card payments are not available right now.';
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map ? d['error']?.toString() : null;
      if (e.status == 403 && attempt < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        continue;
      }
      return msg ?? 'Card payments are not available right now.';
    } catch (e) {
      debugPrint('payment: could not start: $e');
      return 'We could not reach the card service. Check your signal and try again.';
    }
  }
  return 'The order is still being saved. Try again in a moment.';
}
