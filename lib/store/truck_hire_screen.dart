import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show GlassButton, GhostButton, Pill, Reveal, SectionTitle, SupabaseBoot, friendlyError, marketProvider, resilientRows;
import '../driver/job_map.dart' show driveRoute, geocode;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'store_common.dart' show money;

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr;

class TruckRequest {
  final String id, kind, from, to, status;
  final int loadKg;
  final bool cold;
  final double km, estimate;
  final double? quote;
  final DateTime neededOn;
  const TruckRequest(this.id, this.kind, this.from, this.to, this.status, this.loadKg, this.cold, this.km, this.estimate, this.quote, this.neededOn);

  factory TruckRequest.fromRow(Map<String, dynamic> r) => TruckRequest(
        r['id'] as String,
        r['kind'] as String,
        r['from_place'] as String,
        r['to_place'] as String,
        r['status'] as String,
        (r['load_kg'] as num).toInt(),
        r['cold_chain'] == true,
        (r['km'] as num).toDouble(),
        (r['estimate'] as num).toDouble(),
        (r['quote'] as num?)?.toDouble(),
        DateTime.parse(r['needed_on'] as String),
      );
}

/// The seller's own truck requests, live: a quote from staff shows up here the
/// moment it is sent.
final myTrucksProvider = StreamProvider<List<TruckRequest>>((ref) {
  if (!SupabaseBoot.ready) return Stream.value(const []);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('truck_hire').stream(primaryKey: ['id']),
    fetch: () async => [for (final r in await db.from('truck_hire').select()) Map<String, dynamic>.from(r)],
    cacheKey: '${db.auth.currentUser?.id ?? 'anon'}:truck_hire',
  ).map((rows) => ([for (final r in rows) TruckRequest.fromRow(r)]..sort((a, b) => b.neededOn.compareTo(a.neededOn))));
});

/// What a trip is likely to cost, before staff confirm. The same sum as the
/// server's, so the number on screen is the number it stores.
double truckEstimate(String kind, double km, bool cold) {
  final base = switch (kind) { 'refrigerated' => 900 + 22 * km, 'flatbed' => 600 + 15 * km, _ => 350 + 9.5 * km };
  final withCold = cold && kind != 'refrigerated' ? base * 1.15 : base;
  return withCold.roundToDouble();
}

const _kinds = <(String, String, String)>[
  ('bakkie', 'Bakkie', 'Up to about 1 ton. Cooler boxes for short trips.'),
  ('refrigerated', 'Refrigerated truck', 'Keeps meat and dairy cold on the road.'),
  ('flatbed', 'Flatbed', 'Bags, crates and equipment. Not for cold goods.'),
];

class TruckHireScreen extends ConsumerWidget {
  const TruckHireScreen({super.key});

  Future<void> _act(BuildContext context, Future<void> Function() f, String done) async {
    try {
      await f();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, doing: 'do that'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trucks = ref.watch(myTrucksProvider).valueOrNull ?? const <TruckRequest>[];
    final db = SupabaseBoot.ready ? SupabaseBoot.client.schema('grow_api') : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Truck hire'), backgroundColor: Colors.transparent),
      body: AppBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
            children: [
              Text('Move your goods in bulk', style: AppTheme.title2),
              const SizedBox(height: 4),
              Text('Need more than a delivery driver can carry? Ask for a bakkie or a refrigerated truck to take stock from your farm to the warehouse. You see a price straight away, Nolifa confirms it, and you accept.', style: AppTheme.callout),
              const SizedBox(height: AppTheme.s4),
              GlassButton(
                label: 'Ask for a truck',
                icon: Icons.local_shipping_rounded,
                onPressed: db == null
                    ? null
                    : () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: AppTheme.sheet,
                          builder: (_) => const _RequestSheet(),
                        ),
              ),
              if (db == null)
                Padding(padding: const EdgeInsets.only(top: AppTheme.s2), child: Text('Truck hire needs the shared database.', style: AppTheme.footnote)),
              const SectionTitle('🚚', 'Your requests'),
              if (trucks.isEmpty) GlassCard(child: Text('No requests yet.', style: AppTheme.callout)),
              for (var i = 0; i < trucks.length; i++)
                Reveal(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s3),
                    child: _TruckCard(
                      trucks[i],
                      onAccept: db == null ? null : () => _act(context, () => db.rpc('accept_truck', params: {'p_id': trucks[i].id}), 'Truck booked.'),
                      onCancel: db == null ? null : () => _act(context, () => db.rpc('cancel_truck', params: {'p_id': trucks[i].id}), 'Request cancelled.'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TruckCard extends StatelessWidget {
  final TruckRequest t;
  final VoidCallback? onAccept, onCancel;
  const _TruckCard(this.t, {this.onAccept, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (t.status) {
      'requested' => ('Waiting for a quote', AppTheme.warn),
      'quoted' => ('Quote ready', AppTheme.sprout),
      'booked' => ('Booked', AppTheme.sprout),
      'done' => ('Done', AppTheme.textSecondary),
      _ => ('Cancelled', AppTheme.textSecondary),
    };
    final name = _kinds.firstWhere((k) => k.$1 == t.kind, orElse: () => _kinds.first).$2;
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('$name  •  ${t.loadKg} kg${t.cold ? '  •  cold' : ''}', style: AppTheme.headline)),
          Pill(label, color: color),
        ]),
        const SizedBox(height: 2),
        Text('${t.from} to ${t.to}  •  ${t.km.toStringAsFixed(0)} km', style: AppTheme.footnote),
        Text('Needed ${t.neededOn.day}/${t.neededOn.month}/${t.neededOn.year}', style: AppTheme.footnote),
        const SizedBox(height: AppTheme.s2),
        Row(children: [
          Text(t.quote != null ? 'Quote ${money(t.quote!)}' : 'About ${money(t.estimate)}', style: AppTheme.title3.copyWith(color: t.quote != null ? AppTheme.sprout : AppTheme.textPrimary)),
        ]),
        if (t.status == 'quoted' && onAccept != null) ...[
          const SizedBox(height: AppTheme.s3),
          GlassButton(label: 'Accept the quote', icon: Icons.check_circle_rounded, onPressed: onAccept),
        ],
        if ((t.status == 'requested' || t.status == 'quoted' || t.status == 'booked') && onCancel != null) ...[
          const SizedBox(height: AppTheme.s2),
          GhostButton(label: 'Cancel', icon: Icons.close_rounded, onPressed: onCancel),
        ],
      ]),
    );
  }
}

class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet();

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  String _kind = 'bakkie';
  bool _cold = false;
  final _load = TextEditingController(text: '300');
  late final _from = TextEditingController(text: ref.read(marketProvider).profile.suburb);
  final _to = TextEditingController(text: 'Durban hub');
  final _notes = TextEditingController();
  DateTime _day = DateTime.now().add(const Duration(days: 2));
  double? _km;
  bool _measuring = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _load.dispose();
    _from.dispose();
    _to.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    if (_from.text.trim().length < 2 || _to.text.trim().length < 2) {
      setState(() => _error = 'Say where it starts and where it goes.');
      return;
    }
    setState(() {
      _measuring = true;
      _error = null;
    });
    final a = await geocode(_from.text.trim());
    final b = await geocode(_to.text.trim());
    final r = await driveRoute([a, b]);
    if (!mounted) return;
    setState(() {
      _km = double.parse(r.km.toStringAsFixed(1)).clamp(1.0, 1500.0);
      _measuring = false;
    });
  }

  Future<void> _send() async {
    final kg = int.tryParse(_load.text.trim());
    if (kg == null || kg < 1) {
      setState(() => _error = 'How many kg are you sending?');
      return;
    }
    if (_km == null) await _measure();
    if (_km == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseBoot.client.schema('grow_api').rpc('request_truck', params: {
        'p_kind': _kind,
        'p_load_kg': kg,
        'p_cold': _cold,
        'p_from': _from.text.trim(),
        'p_to': _to.text.trim(),
        'p_km': _km,
        'p_needed_on': '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}',
        'p_notes': _notes.text.trim(),
      });
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      final m = '$e';
      setState(() => _error = m.contains('P0001') || m.contains('42501') ? RegExp(r'message: ([^,]+)').firstMatch(m)?.group(1) ?? friendlyError(e, doing: 'ask for a truck') : friendlyError(e, doing: 'ask for a truck'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final est = _km == null ? null : truckEstimate(_kind, _km!, _cold);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppTheme.s5, AppTheme.s4, AppTheme.s5, MediaQuery.of(context).viewInsets.bottom + AppTheme.s5),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ask for a truck', style: AppTheme.title3),
          const SizedBox(height: AppTheme.s3),
          for (final k in _kinds)
            RadioListTile<String>(
              value: k.$1,
              groupValue: _kind,
              onChanged: (v) => setState(() {
                _kind = v!;
                if (_kind == 'flatbed') _cold = false;
                if (_kind == 'refrigerated') _cold = true;
              }),
              title: Text(k.$2),
              subtitle: Text(k.$3),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          SwitchListTile(
            value: _cold,
            onChanged: _kind == 'flatbed' || _kind == 'refrigerated' ? null : (v) => setState(() => _cold = v),
            title: const Text('Keep it cold'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          TextField(controller: _load, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Load in kg'))),
          const SizedBox(height: AppTheme.s2),
          TextField(controller: _from, decoration: InputDecoration(labelText: tr('Collect from (farm or town)')), onChanged: (_) => _km = null),
          const SizedBox(height: AppTheme.s2),
          TextField(controller: _to, decoration: InputDecoration(labelText: tr('Take to')), onChanged: (_) => _km = null),
          const SizedBox(height: AppTheme.s2),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Needed on ${_day.day}/${_day.month}/${_day.year}'),
            trailing: const Icon(Icons.calendar_month_rounded),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180)));
              if (d != null) setState(() => _day = d);
            },
          ),
          TextField(controller: _notes, maxLength: 400, decoration: InputDecoration(labelText: tr('Anything the driver should know'))),
          Row(children: [
            Expanded(
              child: Text(_km == null ? 'The distance is worked out when you ask.' : '${_km!.toStringAsFixed(0)} km, about ${money(est!)}', style: AppTheme.callout),
            ),
            TextButton(onPressed: _measuring ? null : _measure, child: Text(_measuring ? 'Measuring' : 'Check price')),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: AppTheme.s2), child: Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger))),
          GlassButton(label: 'Send the request', icon: Icons.send_rounded, busy: _busy, onPressed: _send),
        ]),
      ),
    );
  }
}
