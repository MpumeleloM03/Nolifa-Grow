import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'stock_page.dart';

/// Scan a tag with a barcode scanner (it types the code and presses Enter) or
/// type it. Shows the lot, its history, and lets staff print, move or remove.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  String? _code;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _go(String v) {
    setState(() => _code = v.trim());
    _c.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final wh = ref.watch(warehouseProvider);
    final now = ref.watch(warehouseClockProvider)();
    StockLot? lot;
    if (_code != null) {
      for (final l in wh.lots) {
        if (l.id.toLowerCase() == _code!.toLowerCase() || (l.tag ?? '').toLowerCase() == _code!.toLowerCase()) lot = l;
      }
    }
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Scan a tag', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('Click in the box and scan. A USB or Bluetooth barcode scanner types the code and presses Enter.'),
      const SizedBox(height: 12),
      TextField(
        controller: _c,
        focusNode: _focus,
        autofocus: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.qr_code_scanner_rounded), hintText: 'NLF-DBN-0001', border: OutlineInputBorder()),
        onSubmitted: _go,
      ),
      const SizedBox(height: 16),
      if (_code != null && lot == null) Text('No lot with the tag "$_code".', style: const TextStyle(color: Colors.red)),
      if (lot != null) ...[
        LotTagCard(lot, now: now, atRisk: wh.zoneAtRisk(lot.hub, lot.zone)),
        const SizedBox(height: 8),
        if (lot.tag != null)
          Wrap(spacing: 8, children: [
            FilledButton.icon(icon: const Icon(Icons.print_rounded), label: const Text('Print tag again'), onPressed: () => printTag(lot!)),
            if (lot.inStock) LotMenu(lot),
          ]),
      ],
    ]);
  }
}
