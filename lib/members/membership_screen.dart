import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show friendlyError;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'members_service.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
String rand(int n) => 'R${n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')}';

/// The Nolifa membership: Member at R3 000 a month, Max at R7 000. Both run for
/// at least 24 months, and that is said before anyone can join.
class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key});

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  Tier _pick = Tier.member;
  bool _agree = false;
  bool _busy = false;
  bool _test = false;
  String? _error;

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await startCardPayment();
      _test = c.test;
      final ok = await launchUrl(Uri.parse(c.url), mode: LaunchMode.externalApplication);
      if (!ok) _error = 'We could not open the payment page. Try again.';
    } catch (e) {
      _error = e is StateError ? e.message : friendlyError(e, doing: 'start the payment');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await joinMembership(_pick);
      HapticFeedback.mediumImpact();
    } catch (e) {
      _error = friendlyError(e, doing: 'sign you up');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(membershipProvider).valueOrNull;
    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.livestockAccent,
        child: SafeArea(
          child: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: const GlassBar(),
              leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
              title: const Text('Nolifa membership'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
              sliver: SliverList.list(children: [
                if (m != null && m.active) ..._current(m) else if (m != null && m.awaitingPayment) ..._waiting(m) else ..._offer(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _current(Membership m) => [
        Text('You are a ${m.tier.label} member', style: AppTheme.title1),
        const SizedBox(height: AppTheme.s2),
        Text(
            'Started ${_d(m.startedAt)}. Your 24 month term runs to ${_d(m.termEndsAt)}. ${m.tier.videosPerMonth} vet videos a month${m.tier.vetVisits ? ', on-site vet visits in partner areas' : ''}, and a discount on a Nolifa borehole.',
            style: AppTheme.callout),
      ];

  List<Widget> _waiting(Membership m) => [
        Text('One step left: pay the first month', style: AppTheme.title1),
        const SizedBox(height: AppTheme.s2),
        Text(
            'You asked to join as a ${m.tier.label} member at ${rand(m.tier.monthly)} a month. Pay the first month by card. Your plan switches on the moment the payment is confirmed, and the 24 months start that day.',
            style: AppTheme.callout),
        const SizedBox(height: AppTheme.s3),
        if (_test)
          GlassCard(
            tint: AppTheme.warn.withValues(alpha: 0.14),
            child: Text('TEST MODE. No real money is taken. On the payment page use the test card details from the Yoco test card list.', style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppTheme.s2), child: Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger))),
        const SizedBox(height: AppTheme.s3),
        GlassButton(label: _busy ? 'Opening payment' : 'Pay ${rand(m.tier.monthly)} by card', icon: Icons.credit_card_rounded, onPressed: _busy ? null : _pay),
        const SizedBox(height: AppTheme.s2),
        Text('After paying, come back to this screen. It updates by itself.', style: AppTheme.caption),
      ];

  List<Widget> _offer() => [
        Text('Look after your herd with a vet', style: AppTheme.title1),
        const SizedBox(height: AppTheme.s1),
        Text('Send your vet a video, get a written diagnosis and a plan, and chat to them in the app.', style: AppTheme.callout),
        const SizedBox(height: AppTheme.s4),
        for (final t in Tier.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.s3),
            child: GlassCard(
              onTap: () => setState(() => _pick = t),
              tint: _pick == t ? AppTheme.sprout.withValues(alpha: 0.14) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_pick == t ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: AppTheme.sprout),
                  const SizedBox(width: AppTheme.s3),
                  Text(t.label, style: AppTheme.title2),
                  const Spacer(),
                  Text('${rand(t.monthly)} a month', style: AppTheme.headline),
                ]),
                const SizedBox(height: AppTheme.s3),
                _perk('Up to ${t.videosPerMonth} videos a month, each up to 2 minutes'),
                _perk('A vet reviews them and writes what it is, why, the remedy and how it helps'),
                _perk('Chat with the vet inside the app'),
                _perk('Discount on a Nolifa trusted borehole driller'),
                if (t.vetVisits) _perk('Ask the vet to come to your farm for tests (partner areas, KwaZulu-Natal now)'),
              ]),
            ),
          ),
        GlassCard(
          tint: AppTheme.warn.withValues(alpha: 0.10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Read this before you join', style: AppTheme.headline),
            const SizedBox(height: AppTheme.s2),
            Text(
                'Membership is a minimum of 24 months. ${_pick.label} is ${rand(_pick.monthly)} a month, so ${rand(_pick.commitment)} over the term. It starts when Nolifa confirms your first payment. Vet videos reset each calendar month and do not roll over. On-site visits are only where we have a partner vet.',
                style: AppTheme.footnote),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agree,
              onChanged: (v) => setState(() => _agree = v ?? false),
              title: Text('I understand this is a 24 month commitment of ${rand(_pick.commitment)}.', style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
            ),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppTheme.s2),
          Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
        ],
        const SizedBox(height: AppTheme.s3),
        GlassButton(label: _busy ? 'Signing you up' : 'Join as ${_pick.label}', icon: Icons.verified_rounded, onPressed: (_agree && !_busy) ? _join : null),
      ];

  Widget _perk(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.check_rounded, size: 18, color: AppTheme.ok),
          const SizedBox(width: AppTheme.s2),
          Expanded(child: Text(t, style: AppTheme.footnote)),
        ]),
      );

  static String _d(DateTime? d) => d == null ? 'soon' : '${d.day}/${d.month}/${d.year}';
}
