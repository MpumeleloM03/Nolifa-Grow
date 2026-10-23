import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'overview_page.dart';
import 'stock_page.dart' show d;

/// Which rooms a certifier has passed, until when, and a form for a certifier
/// to record a new inspection. A room cannot take goods without a valid one.
class CertsPage extends ConsumerStatefulWidget {
  const CertsPage({super.key});

  @override
  ConsumerState<CertsPage> createState() => _CertsPageState();
}

class _CertsPageState extends ConsumerState<CertsPage> {
  final _name = TextEditingController();
  final _org = TextEditingController();
  final _no = TextEditingController();
  final _notes = TextEditingController();
  final _rooms = <StorageZone>{};
  final _checks = <String>{};
  String? _msg;

  @override
  Widget build(BuildContext context) {
    final wh = ref.watch(warehouseProvider);
    final now = ref.watch(warehouseClockProvider)();
    final can = ref.watch(certifierProvider);
    final certs = [...wh.certs]..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Certificates', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      const Text('A certifier inspects the warehouse and records which rooms are fit to store food. Goods cannot be checked into a room without a valid certificate.'),
      const SizedBox(height: 12),
      for (final z in StorageZone.values)
        Builder(builder: (context) {
          final c = wh.certFor(hubName, z, now);
          final soon = c != null && c.expiresAt.difference(now).inDays < 30;
          return ListTile(
            leading: Icon(c == null ? Icons.cancel_rounded : Icons.verified_rounded, color: c == null ? Colors.red : (soon ? Colors.orange : Colors.teal)),
            title: Text(z.label),
            subtitle: Text(c == null ? 'No valid certificate. Not usable.' : 'Certificate ${c.certNumber}, valid until ${d(c.expiresAt)}${soon ? ' (renew soon)' : ''}'),
          );
        }),
      const Divider(),
      if (can) ...[
        Text('Record an inspection', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name')),
        TextField(controller: _org, decoration: const InputDecoration(labelText: 'Organisation')),
        TextField(controller: _no, decoration: const InputDecoration(labelText: 'Certificate number')),
        const SizedBox(height: 8),
        const Text('Rooms passed'),
        Wrap(spacing: 8, children: [
          for (final z in StorageZone.values)
            FilterChip(label: Text(z.label), selected: _rooms.contains(z), onSelected: (v) => setState(() => v ? _rooms.add(z) : _rooms.remove(z))),
        ]),
        const SizedBox(height: 8),
        const Text('Every check must pass for the rooms named'),
        for (final c in certChecks) CheckboxListTile(dense: true, value: _checks.contains(c), title: Text(c), onChanged: (v) => setState(() => v == true ? _checks.add(c) : _checks.remove(c))),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            final cert = await ref.read(warehouseProvider.notifier).certify(
                  hub: hubName,
                  certifierName: _name.text,
                  organisation: _org.text,
                  certNumber: _no.text,
                  rooms: _rooms.toList(),
                  checksPassed: _checks.toList(),
                  notes: _notes.text,
                );
            setState(() => _msg = cert == null ? 'Fill in your name, the number, pick a room and tick every check.' : 'Recorded. Valid until ${d(cert.expiresAt)}.');
          },
          child: const Text('Record certificate (valid 12 months)'),
        ),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!)),
        const Divider(height: 32),
      ],
      Text('History', style: Theme.of(context).textTheme.titleLarge),
      if (certs.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No inspections recorded yet.')),
      for (final c in certs)
        ListTile(
          title: Text('${c.certNumber}  -  ${c.rooms.map((r) => r.label).join(', ')}'),
          subtitle: Text('${c.certifierName}, ${c.organisation}. ${d(c.issuedAt)} to ${d(c.expiresAt)}'),
        ),
    ]);
  }
}
