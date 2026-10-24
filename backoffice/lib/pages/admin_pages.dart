import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, friendlyError, resilientRows;
import 'package:url_launcher/url_launcher.dart';

SupabaseClient get _db => SupabaseBoot.client;

Future<void> _open(String bucket, String path) async {
  final url = await _db.storage.from(bucket).createSignedUrl(path, 600);
  await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
}

void _say(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<void> _run(BuildContext c, Future<void> Function() f, String done, String doing) async {
  try {
    await f();
    if (c.mounted) _say(c, done);
  } catch (e) {
    if (c.mounted) _say(c, friendlyError(e, doing: doing));
  }
}

Stream<List<Map<String, dynamic>>> _live(String table, String key) => resilientRows(
      open: () => _db.from(table).stream(primaryKey: [key]),
      fetch: () async => [for (final r in await _db.from(table).select()) Map<String, dynamic>.from(r)],
    );

final _applications = StreamProvider((ref) => _live('farm_applications', 'uid'));
final _driverApps = StreamProvider((ref) => _live('driver_applications', 'uid'));
final _farmProfiles = StreamProvider((ref) => _live('farm_profiles', 'uid'));
final _plans = StreamProvider((ref) => _live('seller_plans', 'uid'));
final _memberships = StreamProvider((ref) => _live('memberships', 'uid'));
final _boreholes = StreamProvider((ref) => _live('borehole_requests', 'id'));
final _reserves = StreamProvider((ref) => _live('water_reserves', 'id'));

Widget _empty(String t) => Padding(padding: const EdgeInsets.all(24), child: Text(t));
Widget _pad(List<Widget> c) => ListView(padding: const EdgeInsets.all(20), children: c);

/// Farm applications waiting for a decision.
class ApplicationsPage extends ConsumerWidget {
  const ApplicationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(_applications);
    return apps.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _empty(friendlyError(e, doing: 'load applications')),
      data: (rows) {
        final list = [for (final r in rows) if (r['status'] != 'draft') r]
          ..sort((a, b) => ((a['status'] == 'submitted') ? 0 : 1).compareTo((b['status'] == 'submitted') ? 0 : 1));
        if (list.isEmpty) return _empty('No applications yet.');
        return _pad([
          Text('Farm applications', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          for (final r in list) _AppCard(r),
        ]);
      },
    );
  }
}

class _AppCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _AppCard(this.row);

  @override
  Widget build(BuildContext context) {
    final d = Map<String, dynamic>.from(row['data'] as Map);
    final p = Map<String, dynamic>.from((d['practices'] as Map?) ?? {});
    final status = row['status'] as String;
    String v(Object? x) => (x == null || '$x'.isEmpty) ? 'not given' : '$x';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text('${v(d['farmName'])}  ·  ${v(d['fullName'])}'),
        subtitle: Text('$status  ·  ${v(d['province'])}  ·  ${v(d['sizeHa'])} ha'),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ID number ${v(d['idNumber'])}  ·  phone ${v(d['phone'])}'),
          Text('Business ${v(d['kind'])} ${v(d['businessName'])}  ·  CIPC ${v(d['regNumber'])}'),
          Text('Land ${v(d['tenure'])}  ·  near ${v(d['town'])}  ·  GPS ${v(d['lat'])}, ${v(d['lng'])}'),
          Text('Farms ${v(d['farmKind'])}  ·  sells ${((d['products'] as List?) ?? const []).join(', ')}'),
          if (p.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('How they farm', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final e in p.entries) Text('${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}'),
          ],
          const SizedBox(height: 8),
          _Files(row['uid'] as String),
          if (status == 'submitted') ...[
            const SizedBox(height: 12),
            _Decide(row['uid'] as String),
          ] else if ((row['review_note'] ?? '').toString().isNotEmpty)
            Text('Note: ${row['review_note']}'),
        ],
      ),
    );
  }
}

class _Files extends StatelessWidget {
  final String uid;
  const _Files(this.uid);

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _db.from('application_files').select().eq('uid', uid),
        builder: (_, snap) {
          final files = [for (final f in (snap.data ?? const [])) Map<String, dynamic>.from(f as Map)];
          if (files.isEmpty) return const Text('No photos.');
          return Wrap(spacing: 8, children: [
            for (final f in files)
              ActionChip(
                avatar: const Icon(Icons.image_rounded, size: 16),
                label: Text('${f['kind']}'),
                onPressed: () => _open('verification', f['path'] as String),
              ),
          ]);
        },
      );
}

class _Decide extends StatefulWidget {
  final String uid;
  const _Decide(this.uid);

  @override
  State<_Decide> createState() => _DecideState();
}

class _DecideState extends State<_Decide> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _go(String decision) => _run(
        context,
        () => _db.rpc('review_application', params: {'p_uid': widget.uid, 'p_decision': decision, 'p_note': _note.text.trim()}),
        'Saved: $decision.',
        'save that decision',
      );

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Open the ID photo and the selfie. Do the faces match, and does the number on the ID match the form?'),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note to the farmer (needed unless approving)')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: () => _go('approved'), child: const Text('Approve')),
          OutlinedButton(onPressed: () => _go('needs_info'), child: const Text('Ask for more')),
          OutlinedButton(onPressed: () => _go('rejected'), child: const Text('Reject')),
        ]),
      ]);
}

/// Members waiting for a first payment to be confirmed.
class MembershipsPage extends ConsumerWidget {
  const MembershipsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_memberships).valueOrNull ?? const [];
    final ref0 = TextEditingController();
    return _pad([
      Text('Memberships', style: Theme.of(context).textTheme.headlineSmall),
      const Text('Turn a membership on only after the first payment has cleared in the bank. The 24 month term starts the day you do.'),
      const SizedBox(height: 12),
      if (rows.isEmpty) const Text('No one has signed up yet.'),
      for (final r in rows)
        Card(
          child: ListTile(
            title: Text('${r['tier'] == 'max' ? 'Max' : 'Member'}  ·  R${r['monthly_price']} a month  ·  ${r['status']}'),
            subtitle: Text('${r['uid']}\nAccepted ${r['accepted_terms_at']}${r['term_ends_at'] != null ? '\nTerm ends ${r['term_ends_at']}' : ''}'),
            isThreeLine: true,
            trailing: r['status'] == 'awaiting_payment'
                ? FilledButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Payment received?'),
                          content: TextField(controller: ref0, decoration: const InputDecoration(labelText: 'Bank reference')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Turn on')),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        await _run(context, () => _db.rpc('activate_membership', params: {'p_uid': r['uid'], 'p_ref': ref0.text.trim()}), 'Membership is on.', 'turn it on');
                      }
                    },
                    child: const Text('Payment received'),
                  )
                : null,
          ),
        ),
    ]);
  }
}

/// Borehole requests and the water Nolifa keeps in reserve.
class BoreholesPage extends ConsumerWidget {
  const BoreholesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reqs = ref.watch(_boreholes).valueOrNull ?? const [];
    final res = ref.watch(_reserves).valueOrNull ?? const [];
    final price = TextEditingController();
    return _pad([
      Text('Boreholes', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      if (reqs.isEmpty) const Text('No requests yet.'),
      for (final r in reqs)
        Card(
          child: ListTile(
            title: Text('${r['purpose']}  ·  ${r['status']}  ·  ${r['tier']} (${r['discount_pct']}% off)'),
            subtitle: Text('${r['address']}  ${r['contact_phone']}\n${r['lat']}, ${r['lng']}  ${r['notes']}${r['standard_quote'] != null ? '\nStandard R${r['standard_quote']}, member price R${r['final_quote']}' : ''}'),
            isThreeLine: true,
            trailing: Wrap(spacing: 8, children: [
              if (r['status'] == 'requested' || r['status'] == 'quoted')
                OutlinedButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Standard price of the drill (rand)'),
                        content: TextField(controller: price, keyboardType: TextInputType.number),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send quote')),
                        ],
                      ),
                    );
                    final n = int.tryParse(price.text.trim());
                    if (ok == true && n != null && n > 0 && context.mounted) {
                      await _run(context, () => _db.rpc('quote_borehole', params: {'p_id': r['id'], 'p_standard': n}), 'Quote sent.', 'send the quote');
                    }
                  },
                  child: const Text('Quote'),
                ),
              if (r['status'] == 'accepted' || r['status'] == 'scheduled')
                FilledButton(
                  onPressed: () => _run(context, () => _db.rpc('mark_borehole_drilled', params: {'p_id': r['id']}), 'Marked drilled. A reserve was created.', 'mark it drilled'),
                  child: const Text('Mark drilled'),
                ),
            ]),
          ),
        ),
      const SizedBox(height: 20),
      Text('Water reserves', style: Theme.of(context).textTheme.titleLarge),
      const Text('Each Nolifa borehole keeps 50 000 litres for communities in need.'),
      for (final r in res)
        Card(
          child: ListTile(
            title: Text('${r['litres_collected']} of ${r['litres_reserved']} litres collected'),
            subtitle: Text('${r['address']}  ${r['contact_phone']}  (${r['lat']}, ${r['lng']})'),
            trailing: OutlinedButton(
              onPressed: () async {
                final l = TextEditingController();
                final n = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Log a collection'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(controller: l, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Litres')),
                      TextField(controller: n, decoration: const InputDecoration(labelText: 'Which community or school')),
                    ]),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
                    ],
                  ),
                );
                final litres = int.tryParse(l.text.trim());
                if (ok == true && litres != null && litres > 0 && context.mounted) {
                  await _run(context, () => _db.rpc('log_collection', params: {'p_reserve': r['id'], 'p_litres': litres, 'p_note': n.text.trim()}), 'Logged.', 'log that');
                }
              },
              child: const Text('Log collection'),
            ),
          ),
        ),
    ]);
  }
}

String prettyJson(Object o) => const JsonEncoder.withIndent('  ').convert(o);


/// Drivers waiting for approval. Nobody can take a job until one of these is approved.
class DriverApplicationsPage extends ConsumerWidget {
  const DriverApplicationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_driverApps).valueOrNull ?? const [];
    final list = [for (final r in rows) if (r['status'] != 'draft') r]
      ..sort((a, b) => ((a['status'] == 'submitted') ? 0 : 1).compareTo((b['status'] == 'submitted') ? 0 : 1));
    return _pad([
      Text('Driver applications', style: Theme.of(context).textTheme.headlineSmall),
      const Text('Open the ID photo and the selfie, then the licence and the vehicle. Approve only if the faces match and the licence is valid for that vehicle.'),
      const SizedBox(height: 12),
      if (list.isEmpty) const Text('No driver applications yet.'),
      for (final r in list)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text('${(r['data'] as Map)['fullName'] ?? 'No name'}  ·  ${(r['data'] as Map)['vehicle'] ?? ''} ${(r['data'] as Map)['plate'] ?? ''}'),
            subtitle: Text('${r['status']}  ·  licence ${(r['data'] as Map)['licenceCode'] ?? ''}'),
            childrenPadding: const EdgeInsets.all(16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID number ${(r['data'] as Map)['idNumber']}  ·  phone ${(r['data'] as Map)['phone']}'),
              const SizedBox(height: 8),
              _Files(r['uid'] as String),
              if (r['status'] == 'submitted') ...[const SizedBox(height: 12), _DecideDriver(r['uid'] as String)]
              else if ((r['review_note'] ?? '').toString().isNotEmpty) Text('Note: ${r['review_note']}'),
            ],
          ),
        ),
    ]);
  }
}

class _DecideDriver extends StatefulWidget {
  final String uid;
  const _DecideDriver(this.uid);

  @override
  State<_DecideDriver> createState() => _DecideDriverState();
}

class _DecideDriverState extends State<_DecideDriver> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _go(String d) => _run(
        context,
        () => _db.rpc('review_driver_application', params: {'p_uid': widget.uid, 'p_decision': d, 'p_note': _note.text.trim()}),
        'Saved: $d.',
        'save that decision',
      );

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note to the driver (needed unless approving)')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: () => _go('approved'), child: const Text('Approve')),
          OutlinedButton(onPressed: () => _go('needs_info'), child: const Text('Ask for more')),
          OutlinedButton(onPressed: () => _go('rejected'), child: const Text('Reject')),
        ]),
      ]);
}

/// The plan each farm pays for. The commission on its sales comes from here,
/// so change it only once the payment has cleared.
class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farms = ref.watch(_farmProfiles).valueOrNull ?? const [];
    final plans = {for (final p in (ref.watch(_plans).valueOrNull ?? const [])) p['uid'] as String: p['plan'] as String};
    return _pad([
      Text('Farm plans', style: Theme.of(context).textTheme.headlineSmall),
      const Text('Starter 8 percent commission, Grow 5 percent, Co-op 3 percent. A farm is on Starter until you change it here.'),
      const SizedBox(height: 12),
      if (farms.isEmpty) const Text('No approved farms yet.'),
      for (final f in farms)
        Card(
          child: ListTile(
            title: Text('${(f['data'] as Map)['farmName']}'),
            subtitle: Text('${f['uid']}'),
            trailing: DropdownButton<String>(
              value: plans[f['uid']] ?? 'starter',
              items: [for (final p in const ['starter', 'grow', 'coop']) DropdownMenuItem(value: p, child: Text(p))],
              onChanged: (v) {
                if (v == null) return;
                _run(context, () => _db.rpc('set_seller_plan', params: {'p_uid': f['uid'], 'p_plan': v}), 'Plan set to $v.', 'change the plan');
              },
            ),
          ),
        ),
    ]);
  }
}
