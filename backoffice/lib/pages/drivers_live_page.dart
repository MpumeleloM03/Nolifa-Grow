import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, friendlyError, resilientRows;
import 'package:url_launcher/url_launcher.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
SupabaseClient get _db => SupabaseBoot.client;

final _positions = StreamProvider((ref) => resilientRows(
      open: () => _db.from('driver_locations').stream(primaryKey: ['driver_id']),
      fetch: () async => [for (final r in await _db.from('driver_locations').select()) Map<String, dynamic>.from(r)],
    ));

// Names come from the driver application, which only admins can read.
final _names = FutureProvider<Map<String, String>>((ref) async {
  try {
    final rows = await _db.from('driver_applications').select('uid, data');
    return {
      for (final r in rows)
        r['uid'] as String: ((r['data'] as Map?)?['fullName'] ?? (r['data'] as Map?)?['name'] ?? '').toString(),
    };
  } catch (_) {
    return {};
  }
});

/// Where every driver is, straight from the phones. A driver who stopped
/// sending for 3 minutes is shown as out of contact, not as online.
class DriversLivePage extends ConsumerWidget {
  const DriversLivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_positions);
    final names = ref.watch(_names).valueOrNull ?? const <String, String>{};
    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e, doing: 'load driver positions'))),
      data: (list) {
        final now = DateTime.now().toUtc();
        final sorted = [...list]..sort((a, b) => (b['updated_at'] as String).compareTo(a['updated_at'] as String));
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text('Drivers live', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('Positions come from the Nolifa phones while a driver is online. Nothing is shown for a driver who is offline.'),
          const SizedBox(height: 12),
          if (sorted.isEmpty) const Text('No driver is sharing a position right now.'),
          for (final d in sorted) _row(context, d, names, now),
        ]);
      },
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> d, Map<String, String> names, DateTime now) {
    final seen = DateTime.tryParse(d['updated_at'] as String)?.toUtc() ?? now;
    final age = now.difference(seen);
    final online = d['online'] == true;
    final fresh = age.inMinutes < 3;
    final state = !online ? 'offline' : fresh ? 'online' : 'out of contact';
    final lat = (d['lat'] as num).toDouble(), lng = (d['lng'] as num).toDouble();
    final who = names[d['driver_id']]?.trim();
    return Card(
      child: ListTile(
        leading: Icon(Icons.two_wheeler_rounded, color: online && fresh ? Colors.green : Colors.grey),
        title: Text(who == null || who.isEmpty ? 'Driver ${(d['driver_id'] as String).substring(0, 8)}' : who),
        subtitle: Text('$state  ·  seen ${age.inSeconds < 60 ? '${age.inSeconds}s' : '${age.inMinutes} min'} ago'
            '${d['speed_kmh'] == null ? '' : '  ·  ${(d['speed_kmh'] as num).round()} km/h'}'
            '  ·  ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'),
        trailing: IconButton(
          tooltip: 'Open in Maps',
          icon: const Icon(Icons.map_rounded),
          onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'), mode: LaunchMode.externalApplication),
        ),
      ),
    );
  }
}
