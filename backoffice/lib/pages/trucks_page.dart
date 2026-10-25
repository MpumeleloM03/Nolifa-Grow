import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, friendlyError, resilientRows;

import 'package:ubuntu_core/tr_text.dart' show Text;
SupabaseClient get _db => SupabaseBoot.client;

final _trucks = StreamProvider((ref) => resilientRows(
      open: () => _db.from('truck_hire').stream(primaryKey: ['id']),
      fetch: () async => [for (final r in await _db.from('truck_hire').select()) Map<String, dynamic>.from(r)],
    ));

/// Truck requests from farms: staff quote a price, the farm accepts in the app,
/// and staff mark the job done after the run.
class TrucksPage extends ConsumerWidget {
  const TrucksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_trucks);
    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e, doing: 'load truck requests'))),
      data: (list) {
        int rank(String s) => switch (s) { 'requested' => 0, 'quoted' => 1, 'booked' => 2, 'done' => 3, _ => 4 };
        final sorted = [...list]..sort((a, b) {
            final c = rank(a['status'] as String).compareTo(rank(b['status'] as String));
            return c != 0 ? c : (a['needed_on'] as String).compareTo(b['needed_on'] as String);
          });
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text('Truck hire', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('Farms ask for a bakkie or a refrigerated truck. The price in the app is only an estimate until you quote.'),
          const SizedBox(height: 12),
          if (sorted.isEmpty) const Text('No truck requests yet.'),
          for (final t in sorted) _TruckCard(t),
        ]);
      },
    );
  }
}

class _TruckCard extends StatefulWidget {
  final Map<String, dynamic> t;
  const _TruckCard(this.t);

  @override
  State<_TruckCard> createState() => _TruckCardState();
}

class _TruckCardState extends State<_TruckCard> {
  late final _quote = TextEditingController(text: _num(widget.t['quote'] ?? widget.t['estimate']));
  bool _busy = false;

  static String _num(Object? v) => v == null ? '' : (double.tryParse('$v') ?? 0).round().toString();

  @override
  void dispose() {
    _quote.dispose();
    super.dispose();
  }

  Future<void> _call(String fn, Map<String, dynamic> params) async {
    setState(() => _busy = true);
    try {
      await _db.rpc(fn, params: params);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, doing: 'update the request'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final status = t['status'] as String;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${t['farm_name']}  ·  ${t['kind']}${t['cold_chain'] == true ? ' (cold)' : ''}', style: Theme.of(context).textTheme.titleMedium)),
            Chip(label: Text(status)),
          ]),
          Text('${t['from_place']} to ${t['to_place']}  ·  ${t['km']} km  ·  ${t['load_kg']} kg'),
          Text('Needed ${t['needed_on']}  ·  estimate R${_num(t['estimate'])}${t['quote'] == null ? '' : '  ·  quoted R${_num(t['quote'])}'}'),
          if ((t['notes'] as String).isNotEmpty) Text('Note: ${t['notes']}'),
          const SizedBox(height: 8),
          if (status == 'requested' || status == 'quoted')
            Row(children: [
              SizedBox(
                width: 140,
                child: TextField(controller: _quote, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: 'R ', labelText: 'Quote')),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy ? null : () => _call('quote_truck', {'p_id': t['id'], 'p_quote': double.tryParse(_quote.text.trim()) ?? 0}),
                child: Text(status == 'quoted' ? 'Change quote' : 'Send quote'),
              ),
            ]),
          if (status == 'booked')
            FilledButton(onPressed: _busy ? null : () => _call('finish_truck', {'p_id': t['id']}), child: const Text('Mark done')),
        ]),
      ),
    );
  }
}
