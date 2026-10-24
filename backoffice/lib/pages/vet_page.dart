import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, friendlyError, resilientRows;
import 'package:url_launcher/url_launcher.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
SupabaseClient get _db => SupabaseBoot.client;

final _cases = StreamProvider((ref) => resilientRows(
      open: () => _db.from('consults').stream(primaryKey: ['id']),
      fetch: () async => [for (final r in await _db.from('consults').select()) Map<String, dynamic>.from(r)],
    ));

/// What a vet sees: every case from their provinces, newest first, open ones on top.
class VetPage extends ConsumerWidget {
  const VetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_cases);
    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e, doing: 'load the cases'))),
      data: (list) {
        int rank(String s) => switch (s) { 'open' => 0, 'visit_requested' => 1, 'in_review' => 2, 'answered' => 3, 'visit_booked' => 4, _ => 5 };
        final sorted = [...list]..sort((a, b) {
            final c = rank(a['status'] as String).compareTo(rank(b['status'] as String));
            return c != 0 ? c : (b['created_at'] as String).compareTo(a['created_at'] as String);
          });
        if (sorted.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Text('No cases from your provinces yet.'));
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text('Vet cases', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          for (final c in sorted) _Case(c),
        ]);
      },
    );
  }
}

class _Case extends StatefulWidget {
  final Map<String, dynamic> c;
  const _Case(this.c);

  @override
  State<_Case> createState() => _CaseState();
}

class _CaseState extends State<_Case> {
  final _msg = TextEditingController();
  final _f = {for (final k in ['suspected', 'why', 'remedy', 'howItHelps', 'handling']) k: TextEditingController()};
  String _urgency = 'soon';
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _chat = [];

  String get _id => widget.c['id'] as String;

  @override
  void dispose() {
    _msg.dispose();
    for (final c in _f.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = await _db.from('consult_videos').select().eq('consult_id', _id).order('created_at');
      final m = await _db.from('consult_messages').select().eq('consult_id', _id).order('created_at');
      if (mounted) {
        setState(() {
          _videos = [for (final r in v) Map<String, dynamic>.from(r)];
          _chat = [for (final r in m) Map<String, dynamic>.from(r)];
        });
      }
    } catch (_) {}
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _answer() async {
    try {
      await _db.rpc('vet_answer', params: {
        'p_consult': _id,
        'p_diagnosis': {for (final e in _f.entries) e.key: e.value.text.trim(), 'urgency': _urgency},
      });
      _say('Diagnosis sent to the farmer.');
    } catch (e) {
      _say(e.toString().contains('needs what it is') ? 'Fill in what it is, why, the remedy and how it helps.' : friendlyError(e, doing: 'send the diagnosis'));
    }
  }

  Future<void> _send() async {
    final t = _msg.text.trim();
    if (t.isEmpty) return;
    try {
      await _db.rpc('send_consult_message', params: {'p_consult': _id, 'p_body': t});
      _msg.clear();
      await _load();
    } catch (e) {
      _say(friendlyError(e, doing: 'send that'));
    }
  }

  Future<void> _book() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 2)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
    if (d == null) return;
    try {
      await _db.rpc('book_vet_visit', params: {'p_consult': _id, 'p_on': d.toIso8601String().substring(0, 10), 'p_note': _msg.text.trim()});
      _say('Visit booked.');
    } catch (e) {
      _say(friendlyError(e, doing: 'book the visit'));
    }
  }

  Future<void> _play(String path) async {
    final url = await _db.storage.from('consult-videos').createSignedUrl(path, 900);
    await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final d = c['diagnosis'] as Map?;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        onExpansionChanged: (open) {
          if (open) _load();
        },
        title: Text('${c['title']}  ·  ${c['animal_label']} ${c['species']}'),
        subtitle: Text('${c['status']}  ·  ${c['province']}  ·  ${c['kind']}'),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${c['description']}'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (var i = 0; i < _videos.length; i++)
              ActionChip(avatar: const Icon(Icons.play_circle_rounded), label: Text('Video ${i + 1} (${_videos[i]['duration_s']} s)'), onPressed: () => _play(_videos[i]['path'] as String)),
            if (_videos.isEmpty) const Text('No videos loaded.'),
          ]),
          if (c['visit'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Visit: ${c['visit']}')),
          const Divider(height: 28),
          if (d != null) Text('Answered: ${d['suspected']}\nWhy: ${d['why']}\nRemedy: ${d['remedy']}\nHow it helps: ${d['howItHelps']}'),
          const Text('Your diagnosis', style: TextStyle(fontWeight: FontWeight.w700)),
          TextField(controller: _f['suspected'], decoration: const InputDecoration(labelText: 'What you think it is')),
          TextField(controller: _f['why'], maxLines: 2, decoration: const InputDecoration(labelText: 'Why you think so (what you saw in the video)')),
          TextField(controller: _f['remedy'], maxLines: 2, decoration: const InputDecoration(labelText: 'The remedy: product, dose, how long')),
          TextField(controller: _f['howItHelps'], maxLines: 2, decoration: const InputDecoration(labelText: 'How the remedy will help')),
          TextField(controller: _f['handling'], maxLines: 2, decoration: const InputDecoration(labelText: 'How to handle and care for the animal')),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Urgency  '),
            DropdownButton<String>(value: _urgency, items: [for (final u in ['monitor', 'soon', 'emergency']) DropdownMenuItem(value: u, child: Text(u))], onChanged: (v) => setState(() => _urgency = v ?? 'soon')),
            const Spacer(),
            FilledButton(onPressed: _answer, child: const Text('Send diagnosis')),
          ]),
          const Divider(height: 28),
          const Text('Chat', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final m in _chat) Text('${m['role'] == 'vet' ? 'Vet' : 'Farmer'}: ${m['body']}'),
          Row(children: [
            Expanded(child: TextField(controller: _msg, decoration: const InputDecoration(labelText: 'Message or visit note'))),
            IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded)),
            if (c['status'] == 'visit_requested' || c['status'] == 'visit_booked') OutlinedButton(onPressed: _book, child: const Text('Book visit')),
          ]),
        ],
      ),
    );
  }
}
