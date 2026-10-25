import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Order, OrderStatus, friendlyError, marketProvider;
import '../theme/app_theme.dart';
import '../theme/glass.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;

/// What the QR on a parcel says. The order id is not secret and does not pay or
/// release anything: it only tells the store which order the parcel is.
String parcelCode(String orderId) => 'nolifa:order:$orderId';

/// The order id inside a scanned or typed code, or null if it is not ours.
/// Typing the last 5 characters is enough.
String? orderIdFromCode(String raw, Iterable<String> knownIds) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final id = t.startsWith('nolifa:order:') ? t.substring('nolifa:order:'.length) : t;
  for (final k in knownIds) {
    if (k == id) return k;
  }
  if (id.length >= 4) {
    final tail = id.toUpperCase();
    final hits = [for (final k in knownIds) if (k.toUpperCase().endsWith(tail)) k];
    if (hits.length == 1) return hits.first;
  }
  return null;
}

/// The parcel label: a QR the store sticks on the bag.
Future<void> showParcelLabel(BuildContext context, Order o) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.sheet,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.s6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Parcel label', style: AppTheme.title3),
            const SizedBox(height: AppTheme.s2),
            Text('Stick this on the bag. Scan it to send the order out for a driver.', style: AppTheme.footnote, textAlign: TextAlign.center),
            const SizedBox(height: AppTheme.s4),
            Container(
              padding: const EdgeInsets.all(AppTheme.s3),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.rControl)),
              child: QrImageView(data: parcelCode(o.id), size: 200, backgroundColor: Colors.white),
            ),
            const SizedBox(height: AppTheme.s3),
            Text(o.id, style: AppTheme.headline),
          ]),
        ),
      ),
    );

/// The store scans a parcel and sends the order out for a driver. A typed code
/// works too, so a dead camera or a smudged label never blocks an order.
class ScanDispatchScreen extends ConsumerStatefulWidget {
  const ScanDispatchScreen({super.key});

  @override
  ConsumerState<ScanDispatchScreen> createState() => _ScanDispatchState();
}

class _ScanDispatchState extends ConsumerState<ScanDispatchScreen> {
  final _typed = TextEditingController();
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.code39]);
  String? _message;
  Color? _messageColor;
  bool _busy = false;

  @override
  void dispose() {
    _typed.dispose();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    if (_busy) return;
    final orders = ref.read(marketProvider).farmOrders;
    final id = orderIdFromCode(raw, [for (final o in orders) o.id]);
    if (id == null) {
      _say('That code is not one of your orders.', AppTheme.danger);
      return;
    }
    final o = orders.firstWhere((x) => x.id == id);
    if (!o.paid) {
      _say('$id is not paid yet. Pack it once the card payment goes through.', AppTheme.warn);
      return;
    }
    if (o.status != OrderStatus.newOrder) {
      _say(o.status == OrderStatus.findingDriver ? '$id is already waiting for a driver.' : '$id has already been sent out.', AppTheme.warn);
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      ref.read(marketProvider.notifier).packOrder(id);
      _say('$id is ready. Drivers can see it now.', AppTheme.sprout);
      _typed.clear();
    } catch (e) {
      _say(friendlyError(e, doing: 'send that order out'), AppTheme.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String m, Color c) {
    if (mounted) setState(() {
      _message = m;
      _messageColor = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final waiting = ref.watch(marketProvider.select((s) => s.farmOrders.where((o) => o.status == OrderStatus.newOrder).length));
    return Scaffold(
      appBar: AppBar(title: const Text('Scan to send out'), backgroundColor: Colors.transparent),
      body: AppBackdrop(
        child: SafeArea(
          child: Column(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.rCard),
                child: Stack(children: [
                  MobileScanner(
                    controller: _scanner,
                    onDetect: (cap) {
                      final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                      if (v != null) _handle(v);
                    },
                    errorBuilder: (context, error) => Container(
                      color: AppTheme.glassFillStrong,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(AppTheme.s6),
                      child: Text('The camera is not available. Type the order code below.', textAlign: TextAlign.center, style: AppTheme.callout),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
                      child: Text('$waiting ${waiting == 1 ? 'order is' : 'orders are'} waiting to go out. Point the camera at the parcel label.',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.s4),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s2),
                    child: Text(_message!, style: AppTheme.callout.copyWith(color: _messageColor, fontWeight: FontWeight.w700)),
                  ),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _typed,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Or type the order code', hintText: 'Last 5 characters'),
                      onSubmitted: _handle,
                    ),
                  ),
                  const SizedBox(width: AppTheme.s3),
                  IconButton.filled(onPressed: _busy ? null : () => _handle(_typed.text), icon: const Icon(Icons.check_rounded)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
