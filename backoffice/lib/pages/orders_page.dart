import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import '../app.dart';
import '../labels.dart';
import 'stock_page.dart';

/// What has already been cut for an order, saved so a refresh or a second
/// person at another screen cannot cut the same line twice.
class CutLine {
  final String product;
  final double kg;
  final List<String> tags;
  final DateTime? useBy;
  const CutLine(this.product, this.kg, this.tags, this.useBy);
}

final cutsProvider = StreamProvider.family<Map<String, CutLine>, String>((ref, orderId) =>
    SupabaseBoot.client.from('warehouse_picks').stream(primaryKey: ['id']).eq('id', orderId).map((rows) {
      final m = (rows.isEmpty ? null : (rows.first['data'] as Map?)?['lines'] as Map?) ?? const {};
      return {
        for (final e in m.entries)
          e.key as String: CutLine(
            (e.value['product'] as String?) ?? '',
            ((e.value['kg'] as num?) ?? 0).toDouble(),
            [for (final t in (e.value['tags'] as List? ?? const [])) t as String],
            e.value['useBy'] == null ? null : DateTime.fromMillisecondsSinceEpoch((e.value['useBy'] as num).toInt()),
          )
      };
    }));

class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(hubOrdersProvider);
    return orders.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e, doing: 'load orders'))),
      data: (all) {
        final toPick = all.where((o) => o.hubStage == 'received' && o.status == OrderStatus.findingDriver).toList();
        final done = all.where((o) => o.hubStage == 'released' || o.status != OrderStatus.findingDriver).take(8).toList();
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text('Pick and cut', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          const Text('Paid orders waiting at the hub. Cut each line from the oldest stock, weigh it, then print the label and release the order to a driver.'),
          const SizedBox(height: 12),
          if (toPick.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No orders are waiting to be picked.'))),
          for (final o in toPick) PickCard(o),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Recently sent', style: Theme.of(context).textTheme.titleMedium),
            for (final o in done) ListTile(dense: true, title: Text('${o.id}  ${o.pickup}'), subtitle: Text('To ${o.dropArea}'), trailing: Text(o.status == OrderStatus.delivered ? 'Delivered' : o.status == OrderStatus.findingDriver ? 'Waiting for a driver' : 'With a driver')),
          ],
        ]);
      },
    );
  }
}

class PickCard extends ConsumerWidget {
  final Order o;
  const PickCard(this.o, {super.key});

  Future<void> _cut(BuildContext context, WidgetRef ref, int i) async {
    final line = o.lines[i];
    final w = ref.read(warehouseProvider.notifier);
    final lots = w.lotsFor(o.pickup, line.name);
    final c = TextEditingController(text: '${line.qty}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cut ${line.name} for ${o.id}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ordered ${line.qty} kg. Oldest stock is used first:'),
          for (final l in lots.take(3)) Text('${l.tag}  bay ${l.bay}  ${q(l.remaining)} kg left  use by ${d(l.useBy)}', style: const TextStyle(fontSize: 12)),
          if (lots.isEmpty) const Text('Nothing in storage for this product.', style: TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight cut (kg)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: lots.isEmpty ? null : () => Navigator.pop(ctx, true), child: const Text('Cut'))],
      ),
    );
    final kg = double.tryParse(c.text.replaceAll(',', '.'));
    if (ok != true || kg == null || kg <= 0) return;
    // Within 10 percent of what was ordered. Anything else needs a second look.
    if ((kg - line.qty).abs() > line.qty * 0.10 && context.mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Weight is far from the order'),
          content: Text('Ordered ${line.qty} kg but you cut ${q(kg)} kg. Continue?'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, continue'))],
        ),
      );
      if (go != true) return;
    }
    final picks = await w.dispatch(o.pickup, line.name, kg, o.id);
    if (picks == null) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough in a room that is in range. Nothing was taken.')));
      return;
    }
    await SupabaseBoot.client.rpc('save_pick', params: {
      'p_order': o.id,
      'p_index': '$i',
      'p_line': {
        'product': line.name,
        'kg': kg,
        'tags': [for (final p in picks) p.tag],
        'useBy': lots.isEmpty ? null : lots.first.useBy.millisecondsSinceEpoch,
      },
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuts = ref.watch(cutsProvider(o.id)).valueOrNull ?? const <String, CutLine>{};
    final wh = ref.watch(warehouseProvider);
    final allCut = !o.fromStock || List.generate(o.lines.length, (i) => cuts.containsKey('$i')).every((x) => x);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${o.id}  -  ${o.pickup}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            Chip(label: Text(o.fromStock ? 'From warehouse stock' : 'Farm drop-off')),
          ]),
          Text('Deliver to ${o.dropArea} (${o.customer})'),
          const Divider(),
          for (var i = 0; i < o.lines.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(cuts.containsKey('$i') || !o.fromStock ? Icons.check_circle_rounded : Icons.circle_outlined, color: cuts.containsKey('$i') || !o.fromStock ? Colors.teal : null),
              title: Text('${o.lines[i].qty} kg  ${o.lines[i].name}'),
              subtitle: Text(!o.fromStock
                  ? 'Arrived from the farm already packed'
                  : cuts.containsKey('$i')
                      ? 'Cut ${q(cuts['$i']!.kg)} kg from ${cuts['$i']!.tags.join(', ')}'
                      : '${q(wh.available(o.pickup, o.lines[i].name))} kg of ${o.lines[i].name} in storage'),
              trailing: o.fromStock && !cuts.containsKey('$i') ? FilledButton.icon(icon: const Icon(Icons.content_cut_rounded), label: const Text('Cut and weigh'), onPressed: () => _cut(context, ref, i)) : null,
            ),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.print_rounded),
              label: const Text('Print dispatch label'),
              onPressed: !allCut
                  ? null
                  : () => Printing.layoutPdf(
                        name: 'Order ${o.id}',
                        format: labelFormat,
                        onLayout: (_) => dispatchLabelPdf(
                          orderId: o.id,
                          customer: o.customer,
                          dropArea: o.dropArea,
                          hub: o.hub ?? 'Durban hub',
                          packedAt: DateTime.now(),
                          items: [
                            for (var i = 0; i < o.lines.length; i++)
                              (
                                product: o.lines[i].name,
                                kg: cuts['$i']?.kg ?? o.lines[i].qty.toDouble(),
                                tags: cuts['$i']?.tags ?? const <String>[],
                                useBy: cuts['$i']?.useBy,
                              ),
                          ],
                        ),
                      ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.local_shipping_rounded),
              label: const Text('Packed: release to a driver'),
              onPressed: allCut ? () => setHubStage(o, 'released') : null,
            ),
          ]),
        ]),
      ),
    );
  }
}
