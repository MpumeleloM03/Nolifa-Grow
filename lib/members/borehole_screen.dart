import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, deviceLocation, friendlyError;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'members_service.dart';
import 'membership_screen.dart' show rand;

/// Ask a Nolifa trusted borehole driller to come. The price is the standard
/// price of the drill. Members get a discount. Every Nolifa borehole keeps
/// 50 000 litres in reserve for Nolifa to collect for communities in need.
class BoreholeScreen extends ConsumerStatefulWidget {
  const BoreholeScreen({super.key});

  @override
  ConsumerState<BoreholeScreen> createState() => _BoreholeState();
}

class _BoreholeState extends ConsumerState<BoreholeScreen> {
  String _purpose = 'farm';
  double? _lat, _lng;
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  bool _agree = false;
  bool _busy = false;
  String? _error;
  int _memberPct = 10, _maxPct = 15, _reserve = 50000;

  @override
  void initState() {
    super.initState();
    _config();
  }

  Future<void> _config() async {
    try {
      final r = await SupabaseBoot.client.from('borehole_config').select().eq('id', 1).maybeSingle();
      if (r != null && mounted) {
        setState(() {
          _memberPct = (r['member_discount_pct'] as num).toInt();
          _maxPct = (r['max_discount_pct'] as num).toInt();
          _reserve = (r['reserve_litres'] as num).toInt();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final p = await deviceLocation();
    if (!mounted) return;
    setState(() {
      if (p == null) {
        _error = 'We could not find your position. Turn on location, or stand where the borehole should go.';
      } else {
        _lat = p.$1;
        _lng = p.$2;
        _error = null;
      }
    });
  }

  Future<void> _send() async {
    if (_lat == null) {
      setState(() => _error = 'Tap "Use my position" at the spot you want the borehole.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseBoot.client.rpc('request_borehole', params: {
        'p_purpose': _purpose,
        'p_lat': _lat,
        'p_lng': _lng,
        'p_address': _address.text.trim(),
        'p_phone': _phone.text.trim(),
        'p_notes': _notes.text.trim(),
        'p_agree_reserve': _agree,
      });
      HapticFeedback.mediumImpact();
      ref.invalidate(boreholeRequestsProvider);
      _notes.clear();
      _address.clear();
    } catch (e) {
      _error = friendlyError(e, doing: 'send your request');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _accept(String id) async {
    try {
      await SupabaseBoot.client.rpc('accept_borehole_quote', params: {'p_id': id});
      ref.invalidate(boreholeRequestsProvider);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, doing: 'accept the quote'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(membershipProvider).valueOrNull;
    final mine = ref.watch(boreholeRequestsProvider).valueOrNull ?? const [];
    final pct = tier?.active == true ? (tier!.tier.vetVisits ? _maxPct : _memberPct) : 0;
    const blue = Color(0xFF5AB8F0);
    return Scaffold(
      body: AppBackdrop(
        tint: blue,
        child: SafeArea(
          child: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: const GlassBar(),
              leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
              title: const Text('Nolifa borehole'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
              sliver: SliverList.list(children: [
                Text('A trusted driller, on call', style: AppTheme.title1),
                const SizedBox(height: AppTheme.s1),
                Text('Ask Nolifa\'s trusted borehole driller to come to your farm or your community. You get a written quote at the standard price of the drill before anything starts.',
                    style: AppTheme.callout),
                const SizedBox(height: AppTheme.s3),
                GlassCard(
                  tint: (pct > 0 ? AppTheme.ok : AppTheme.warn).withValues(alpha: 0.10),
                  child: Text(
                      pct > 0
                          ? 'As a ${tier!.tier.label} member you get $pct% off the standard price of the drill.'
                          : 'Members get a discount on the drill: $_memberPct% for Member and $_maxPct% for Max. Not a member yet? The quote is at the standard price.',
                      style: AppTheme.callout),
                ),
                const SizedBox(height: AppTheme.s3),
                GlassCard(
                  tint: blue.withValues(alpha: 0.10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('The 50 000 litre promise', style: AppTheme.headline),
                    const SizedBox(height: AppTheme.s1),
                    Text(
                        'Every borehole Nolifa drills keeps ${_reserve.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} litres in reserve. Nolifa may collect that water at any time for communities in need. Everything else the borehole gives is yours.',
                        style: AppTheme.footnote),
                  ]),
                ),
                const SizedBox(height: AppTheme.s4),
                Wrap(spacing: AppTheme.s2, children: [
                  ChoiceChip(label: const Text('For my farm'), selected: _purpose == 'farm', onSelected: (_) => setState(() => _purpose = 'farm')),
                  ChoiceChip(label: const Text('For a community'), selected: _purpose == 'community', onSelected: (_) => setState(() => _purpose = 'community')),
                ]),
                const SizedBox(height: AppTheme.s3),
                GlassCard(
                  padding: const EdgeInsets.all(AppTheme.s4),
                  child: Row(children: [
                    Icon(_lat != null ? Icons.check_circle_rounded : Icons.pin_drop_rounded, color: _lat != null ? AppTheme.ok : AppTheme.textTertiary),
                    const SizedBox(width: AppTheme.s3),
                    Expanded(child: Text(_lat != null ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}' : 'Where should it go?', style: AppTheme.headline)),
                    GhostButton(label: 'Use my position', onPressed: _locate),
                  ]),
                ),
                const SizedBox(height: AppTheme.s3),
                GlassField(controller: _address, label: 'Directions or address', icon: Icons.signpost_rounded),
                const SizedBox(height: AppTheme.s3),
                GlassField(controller: _phone, label: 'Phone for the driller', icon: Icons.phone_rounded, keyboardType: TextInputType.phone),
                const SizedBox(height: AppTheme.s3),
                GlassField(controller: _notes, label: 'Anything the driller should know', icon: Icons.notes_rounded),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _agree,
                  onChanged: (v) => setState(() => _agree = v ?? false),
                  title: Text('I agree to keep the water reserve for Nolifa.', style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
                ),
                if (_error != null) Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
                const SizedBox(height: AppTheme.s2),
                GlassButton(label: _busy ? 'Sending' : 'Ask for a quote', icon: Icons.water_rounded, onPressed: _busy ? null : _send),
                if (mine.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.s5),
                  Text('Your requests', style: AppTheme.title3),
                  const SizedBox(height: AppTheme.s2),
                  for (final r in mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.s2),
                      child: GlassCard(
                        padding: const EdgeInsets.all(AppTheme.s4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['purpose'] == 'farm' ? 'Farm' : 'Community'} borehole  ·  ${_status(r['status'] as String)}', style: AppTheme.headline),
                          if (r['final_quote'] != null)
                            Text(
                                'Standard ${rand((r['standard_quote'] as num).toInt())}${(r['discount_pct'] as num) > 0 ? ', your price ${rand((r['final_quote'] as num).toInt())} (${r['discount_pct']}% off)' : ''}',
                                style: AppTheme.callout),
                          if (r['status'] == 'quoted')
                            Padding(padding: const EdgeInsets.only(top: AppTheme.s2), child: GhostButton(label: 'Accept this quote', icon: Icons.check_rounded, onPressed: () => _accept(r['id'] as String))),
                        ]),
                      ),
                    ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  String _status(String s) => switch (s) {
        'requested' => 'waiting for a quote',
        'quoted' => 'quote ready',
        'accepted' => 'accepted',
        'scheduled' => 'drilling booked',
        'drilled' => 'drilled',
        _ => 'cancelled',
      };
}
