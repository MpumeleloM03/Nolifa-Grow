import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import '../labels.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String d(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}';
String q(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

Future<void> printTag(StockLot l) => Printing.layoutPdf(name: 'Tag ${l.tag}', format: labelFormat, onLayout: (_) => lotTagPdf(l));

/// Every lot in the warehouse with its tag, room, bay, quantity and use-by date.
/// Actions: print its tag, move it to another bay, remove some of it with a reason.
class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  String _filter = '';
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final wh = ref.watch(warehouseProvider);
    final now = ref.watch(warehouseClockProvider)();
    final lots = [
      for (final l in wh.lots)
        if ((_all || l.inStock) &&
            (_filter.isEmpty ||
                '${l.tag} ${l.productName} ${l.farmName} ${l.bay}'.toLowerCase().contains(_filter.toLowerCase())))
          l
    ]..sort((a, b) => a.useBy.compareTo(b.useBy));
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Stock', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tag, product, farm or bay'), onChanged: (v) => setState(() => _filter = v))),
        const SizedBox(width: 12),
        FilterChip(label: const Text('Include sent out and written off'), selected: _all, onSelected: (v) => setState(() => _all = v)),
      ]),
      const SizedBox(height: 12),
      if (lots.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Text('Nothing to show.'))
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Tag')),
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Farm')),
              DataColumn(label: Text('Room')),
              DataColumn(label: Text('Bay')),
              DataColumn(label: Text('Left'), numeric: true),
              DataColumn(label: Text('Use by')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final l in lots)
                DataRow(cells: [
                  DataCell(Text(l.tag ?? 'none', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700))),
                  DataCell(Text(l.productName)),
                  DataCell(Text(l.farmName)),
                  DataCell(Text(l.zone.label)),
                  DataCell(Text(l.bay ?? '-')),
                  DataCell(Text('${q(l.remaining)} ${l.unit}')),
                  DataCell(Text(d(l.useBy), style: TextStyle(color: l.inStock && l.daysLeft(now) <= 2 ? Colors.red : null))),
                  DataCell(Text(wh.zoneAtRisk(l.hub, l.zone) && l.inStock ? 'Room out of range' : l.status.label)),
                  DataCell(l.tag == null
                      ? const SizedBox()
                      : Row(children: [
                          IconButton(tooltip: 'Print tag', icon: const Icon(Icons.print_rounded), onPressed: () => printTag(l)),
                          if (l.inStock) LotMenu(l),
                        ])),
                ]),
            ],
          ),
        ),
    ]);
  }
}

/// Move and remove, for one lot.
class LotMenu extends ConsumerWidget {
  final StockLot lot;
  const LotMenu(this.lot, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        onSelected: (v) async {
          final w = ref.read(warehouseProvider.notifier);
          final c = TextEditingController();
          final c2 = TextEditingController();
          if (v == 'move') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Move ${lot.tag}'),
                content: TextField(controller: c, decoration: const InputDecoration(labelText: 'New bay, for example C2-05')),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Move'))],
              ),
            );
            if (ok == true) await w.moveLot(lot.id, c.text);
          } else {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Remove from ${lot.tag}'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'How much (${lot.unit})')),
                  TextField(controller: c2, decoration: const InputDecoration(labelText: 'Reason (damaged, spoiled, lost)')),
                ]),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove'))],
              ),
            );
            final n = double.tryParse(c.text.replaceAll(',', '.'));
            if (ok == true && n != null) await w.writeOffQty(lot.id, n, c2.text);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'move', child: Text('Move to another bay')),
          PopupMenuItem(value: 'remove', child: Text('Remove some, with a reason')),
        ],
      );
}
