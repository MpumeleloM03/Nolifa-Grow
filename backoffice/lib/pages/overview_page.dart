import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import '../app.dart';

const hubName = 'Durban hub';

class Tile extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  final Color? color;
  const Tile(this.label, this.value, {super.key, this.note, this.color});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
            if (note != null) Text(note!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
      );
}

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wh = ref.watch(warehouseProvider);
    final now = ref.watch(warehouseClockProvider)();
    final orders = ref.watch(hubOrdersProvider).valueOrNull ?? const <Order>[];
    final toPick = orders.where((o) => o.hubStage == 'received' && o.status == OrderStatus.findingDriver).length;
    final dropped = orders.where((o) => o.hubStage == 'droppedOff').length;
    final kg = wh.stored.fold<double>(0, (a, l) => a + l.remaining);
    final soon = wh.stored.where((l) => l.daysLeft(now) <= 2).toList()..sort((a, b) => a.useBy.compareTo(b.useBy));
    final certified = wh.certifiedRooms(hubName, now);

    final warnings = <String>[
      for (final z in StorageZone.values)
        if (wh.zoneAtRisk(hubName, z)) '${z.label} is out of range (${wh.latest(hubName, z)!.c.toStringAsFixed(1)} C, must be ${z.band}).',
      for (final z in {for (final l in wh.stored) l.zone})
        if (!certified.contains(z)) '${z.label} holds goods but has no valid certificate.',
      if (soon.isNotEmpty) '${soon.length} ${soon.length == 1 ? 'lot is' : 'lots are'} within 2 days of use-by.',
    ];

    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Overview', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      if (warnings.isNotEmpty)
        Card(
          color: const Color(0xFFFFEBEB),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Needs attention', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final w in warnings) Padding(padding: const EdgeInsets.only(top: 4), child: Text(w)),
            ]),
          ),
        ),
      const SizedBox(height: 12),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
        childAspectRatio: 2.2,
        children: [
          Tile('Deposits waiting', '${wh.expected.length}', note: 'announced by farms'),
          Tile('In storage', '${wh.stored.length} lots', note: '${kg.toStringAsFixed(1)} kg'),
          Tile('Orders to pick', '$toPick', note: 'cut, weigh, release'),
          Tile('Farm drop-offs to check in', '$dropped'),
        ],
      ),
      const SizedBox(height: 12),
      Text('Rooms', style: Theme.of(context).textTheme.titleLarge),
      for (final z in StorageZone.values)
        ListTile(
          leading: Icon(wh.zoneAtRisk(hubName, z) ? Icons.warning_rounded : Icons.thermostat_rounded,
              color: wh.zoneAtRisk(hubName, z) ? Colors.red : Colors.teal),
          title: Text('${z.label}  (${z.band})'),
          subtitle: Text(wh.latest(hubName, z) == null
              ? 'No reading yet'
              : 'Last reading ${wh.latest(hubName, z)!.c.toStringAsFixed(1)} C, ${wh.latest(hubName, z)!.manual ? 'typed in' : 'sensor'}'),
          trailing: Chip(
            label: Text(certified.contains(z) ? 'Certified' : 'Not certified'),
            backgroundColor: certified.contains(z) ? const Color(0xFFD7F5E8) : const Color(0xFFFFE3C2),
          ),
        ),
    ]);
  }
}
