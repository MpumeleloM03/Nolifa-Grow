import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import '../app.dart';
import '../labels.dart';
import 'package:printing/printing.dart';

/// Deposits the farms announced, to check in at the door. A check-in weighs
/// the goods, takes the temperature, gives the lot a tag and a bay, and offers
/// the tag to print straight away.
class ReceivingPage extends ConsumerWidget {
  const ReceivingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wh = ref.watch(warehouseProvider);
    final orders = ref.watch(hubOrdersProvider).valueOrNull ?? const <Order>[];
    final dropped = orders.where((o) => o.hubStage == 'droppedOff').toList();
    final fresh = wh.stored.where((l) => l.receivedAt != null && DateTime.now().difference(l.receivedAt!).inHours < 24).toList();
    return ListView(children: [
      const Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 0), child: Text('Receiving', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
      SizedBox(height: 520, child: const ReceivingPanel()),
      if (fresh.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 4), child: Text('Checked in today: print the tags', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        for (final l in fresh)
          ListTile(
            leading: const Icon(Icons.sell_rounded),
            title: Text('${l.tag}  ${l.productName}'),
            subtitle: Text('${l.farmName}, ${l.zone.label}, bay ${l.bay}'),
            trailing: FilledButton.icon(
              icon: const Icon(Icons.print_rounded),
              label: const Text('Print tag'),
              onPressed: () => Printing.layoutPdf(name: 'Tag ${l.tag}', format: labelFormat, onLayout: (_) => lotTagPdf(l)),
            ),
          ),
      ],
      if (dropped.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 4), child: Text('Farm drop-offs for single orders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        for (final o in dropped) _DropOff(o),
      ],
    ]);
  }
}

class _DropOff extends StatefulWidget {
  final Order o;
  const _DropOff(this.o);

  @override
  State<_DropOff> createState() => _DropOffState();
}

class _DropOffState extends State<_DropOff> {
  final _code = TextEditingController();
  String? _err;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text('${widget.o.id}  from ${widget.o.pickup}'),
        subtitle: Text('To ${widget.o.dropArea}. Type the code from the packing slip.${_err == null ? '' : '\n$_err'}'),
        trailing: SizedBox(
          width: 220,
          child: Row(children: [
            Expanded(child: TextField(controller: _code, maxLength: 4, decoration: const InputDecoration(counterText: '', hintText: 'Code'))),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                if (_code.text.trim() != widget.o.hubCode) return setState(() => _err = 'That code does not match.');
                await setHubStage(widget.o, 'received');
              },
              child: const Text('Check in'),
            ),
          ]),
        ),
      );
}
