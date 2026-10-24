import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'market_models.dart';
import 'market_store.dart';
import 'honesty.dart';
import 'market_widgets.dart';

/// Shield and close buttons shown at the top right of every hub page.
class HeaderActions extends StatelessWidget {
  final VoidCallback? onClose;
  const HeaderActions({super.key, this.onClose});

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Trust and safety',
          icon: Icon(Icons.verified_user_rounded, color: AppTheme.sprout),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const TrustCenterScreen())),
        ),
        if (onClose != null)
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClose),
      ]);
}

class ScreenFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const ScreenFrame({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AppBackdrop(
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.s2, AppTheme.s2, AppTheme.s6, 0),
                child: Row(children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20)),
                  Expanded(child: Text(title, style: AppTheme.title1)),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.s6, AppTheme.s4, AppTheme.s6, AppTheme.s10),
                  itemCount: children.length,
                  itemBuilder: (_, i) => Reveal(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.s4),
                      child: children[i],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _Block extends StatelessWidget {
  final String emoji;
  final String title;
  final List<Widget> children;
  final Color? tint;
  const _Block(
      {required this.emoji,
      required this.title,
      required this.children,
      this.tint});

  @override
  Widget build(BuildContext context) => GlassCard(
        tint: tint,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: AppTheme.s3),
            Expanded(child: Text(title, style: AppTheme.title3)),
          ]),
          const SizedBox(height: AppTheme.s3),
          ...children,
        ]),
      );
}

class _Row extends StatelessWidget {
  final String left;
  final String right;
  final bool strong;
  const _Row(this.left, this.right, {this.strong = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(left,
              style: AppTheme.footnote.copyWith(
                  color: strong ? AppTheme.sprout : AppTheme.textTertiary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(right,
              style: AppTheme.body.copyWith(
                  fontWeight: strong ? FontWeight.w600 : FontWeight.w400)),
        ]),
      );
}

class _Bullet extends StatelessWidget {
  final String text;
  final int? n;
  const _Bullet(this.text, {this.n});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (n == null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(Icons.check_circle_rounded,
                  size: 16, color: AppTheme.sprout),
            )
          else
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.sprout.withValues(alpha: 0.2)),
              child: Text('$n',
                  style: AppTheme.caption.copyWith(
                      color: AppTheme.sprout, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: AppTheme.s3),
          Expanded(child: Text(text, style: AppTheme.callout)),
        ]),
      );
}

// ============================================================ TRUST CENTER

class TrustCenterScreen extends ConsumerWidget {
  const TrustCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    final shared = ref.watch(marketSharedProvider);
    return ScreenFrame(title: 'Trust & Safety', children: [
      const PrototypeLimitsBlock(),
      GlassCard(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const OfflineGuideScreen())),
        child: Row(children: [
          const Text('📶', style: TextStyle(fontSize: 26)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('What works offline', style: AppTheme.headline),
              Text('And what needs a connection or another person', style: AppTheme.footnote),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
        ]),
      ),
      GlassCard(
        tint: AppTheme.sprout.withValues(alpha: 0.12),
        child: Row(children: [
          const Text('🛡️', style: TextStyle(fontSize: 34)),
          const SizedBox(width: AppTheme.s4),
          Expanded(
            child: Text(
                'Your money, your goods and your data are protected at every step. Here is exactly how.',
                style: AppTheme.callout.copyWith(color: AppTheme.textPrimary)),
          ),
        ]),
      ),
      const _Block(emoji: '💳', title: 'Who pays what', children: [
        _Row('Buyer pays',
            'Items + delivery + 3% service fee (min R2, max R15)'),
        _Row('Farmer pays',
            '8% commission, 5% on Grow, 3% on Co-op. Only when a sale completes'),
        _Row('Driver earns', '80% of the delivery fee'),
        _Row('Nolifa Drop keeps', 'Service fee + commission + 20% of delivery',
            strong: true),
        Divider(height: AppTheme.s6),
        _Row('Monthly farm plan (to sell)', 'Starter R49, Grow R99, Co-op R199'),
        _Row('Scanning, water radar, alerts, buying', 'Free. Only selling has a plan'),
        _Row('Hidden fees',
            'None. The split is shown before you pay and on every receipt'),
      ]),
      const _Block(emoji: '⏱️', title: 'Who is paid, and when', children: [
        _Bullet(
            'Buyer pays at checkout. Money is held by FNB in escrow, not by the farmer or driver.',
            n: 1),
        _Bullet('Driver collects at the farm and takes a pickup photo.', n: 2),
        _Bullet(
            'Delivery completes only when the buyer gives the driver their 4-digit PIN.',
            n: 3),
        _Bullet(
            'Buyer then has 2 hours to confirm or report a problem. Confirm and everyone is paid at once.',
            n: 4),
        _Bullet(
            'No action after 2 hours: the farmer and driver are paid automatically, within minutes, to FNB account or Instant Money.',
            n: 5),
        _Bullet(
            'Cash on delivery orders skip escrow, so those are limited to R500.'),
      ]),
      const _Block(emoji: '🪪', title: 'How we verify people', children: [
        _Bullet(
            'Drivers: ID checked with FNB and Home Affairs, selfie match, payout account, vehicle and safety briefing. No verification, no jobs.'),
        _Bullet(
            'Farmers and sellers: ID, GPS pin of the farm, payout account. Only verified farms can list produce.'),
        _Bullet(
            'Every driver and farm carries a rating. Repeated low ratings pause the account for review.'),
      ]),
      _Block(emoji: '🔬', title: 'How we verify outbreak reports', children: [
        const _Bullet(
            'Step 1: AI checks the photo and symptoms against known diseases.'),
        const _Bullet(
            'Step 2: nearby farms confirm. At least 2 confirmations make a report public.'),
        const _Bullet(
            'Step 3: a vet or extension officer verifies it. Only then it carries the Vet verified badge.'),
        const _Bullet(
            'Single unconfirmed reports never trigger area alerts. False reports lower the reporter\'s trust score and can limit reporting.'),
        const SizedBox(height: AppTheme.s3),
        for (final c in s.cases.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.s2),
            child: Row(children: [
              Text(c.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: AppTheme.s2),
              Expanded(child: Text(c.title, style: AppTheme.footnote)),
              Pill(c.stage.label,
                  color: c.stage == ReportStage.vetVerified
                      ? AppTheme.sprout
                      : c.stage.broadcasts
                          ? AppTheme.livestockAccent
                          : AppTheme.textTertiary),
            ]),
          ),
      ]),
      _Block(
          emoji: '⚖️',
          title: 'When delivery goes wrong',
          tint: AppTheme.warn.withValues(alpha: 0.10),
          children: [
            const _Bullet(
                'Tap "Report a problem" any time before payout. The money freezes instantly, so nobody is paid.'),
            const _Bullet(
                'A mediator reviews the GPS trail, pickup photo, PIN log and your evidence.'),
            const _Bullet(
                'Decision within 48 hours. Refunds go back to your original payment method.'),
            const SizedBox(height: AppTheme.s2),
            for (final r in DisputeReason.values.where((r) => !r.systemOnly))
              _Row('${r.emoji} ${r.label}', r.remedy),
            const SizedBox(height: AppTheme.s2),
            Text(
                'Not happy with the decision? Ask for a second review. Escalation goes to FNB customer care.',
                style: AppTheme.footnote),
          ]),
      const _Block(emoji: '🚨', title: 'Delivery safety', children: [
        _Bullet('Live GPS trail on every delivery, visible to the buyer.'),
        _Bullet(
            'Drivers have an SOS button that shares their location with our safety line.'),
        _Bullet(
            'Drivers never need to carry cash except on small cash orders.'),
        _Bullet(
            'Meet at the gate: PIN handover means nothing is left unattended.'),
      ]),
      _Block(
        emoji: '🧪',
        title: 'App mode',
        tint: (s.demoMode ? AppTheme.warn : AppTheme.sprout).withValues(alpha: 0.10),
        children: [
          if (ref.watch(marketStartsLiveProvider))
            Text('Live. Only real people, real listings and the real 2-hour protection window.', style: AppTheme.callout)
          else
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppTheme.warn,
            value: s.demoMode,
            onChanged: store.setDemoMode,
            title: Text('Demo mode', style: AppTheme.headline),
            subtitle: Text(
                s.demoMode
                    ? 'On. Seeded farms, simulated neighbours and a 12-second protection window so you can see the whole loop.'
                    : 'Off. Live mode. Only real people, real listings and the real 2-hour protection window.',
                style: AppTheme.footnote),
          ),
          const SizedBox(height: AppTheme.s2),
          Pill(shared ? 'Synced between phones' : 'Saved on this phone only',
              color: shared ? AppTheme.sprout : AppTheme.textTertiary,
              icon: shared ? Icons.cloud_done_rounded : Icons.phone_iphone_rounded),
          const SizedBox(height: AppTheme.s2),
          Text(
              shared
                  ? 'Real farms, orders and outbreak cases are shared in real time. Demo-farm orders stay on this phone.'
                  : 'Connect Firebase to share orders and listings between phones. Everything you do is still saved here.',
              style: AppTheme.footnote),
        ],
      ),
      _Block(emoji: '🔐', title: 'Your data', children: [
        const _Bullet(
            'We follow POPIA. Your records are encrypted and never sold.'),
        const _Bullet(
            'Sharing sales history with FNB for credit and insurance is optional and you can switch it off any time.'),
        const SizedBox(height: AppTheme.s2),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppTheme.sprout,
          value: s.creditConsent,
          onChanged: store.setConsent,
          title: Text('Share farm records with FNB', style: AppTheme.headline),
          subtitle: Text(
              s.creditConsent
                  ? 'On. Used for credit pre-qualification'
                  : 'Off. No credit offers',
              style: AppTheme.footnote),
        ),
      ]),
    ]);
  }
}

// ================================================================ WALLET

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    return ScreenFrame(title: 'Wallet', children: [
      const PrototypeNotice('Prototype: the balances and payouts here are simulated. No real money moves until FNB payments are connected.'),
      Row(children: [
        Expanded(child: _Stat('🔒', 'In escrow', s.escrowHeld, AppTheme.warn)),
        const SizedBox(width: AppTheme.s3),
        Expanded(
            child: _Stat('🌾', 'Farm earned', s.farmEarned, AppTheme.sprout)),
      ]),
      Row(children: [
        Expanded(
            child: _Stat('🛵', 'Driver earned', s.driverEarned,
                AppTheme.livestockAccent)),
        const SizedBox(width: AppTheme.s3),
        Expanded(child: _Stat('💰', 'Saved', s.saved, AppTheme.sprout)),
      ]),
      Text('Activity', style: AppTheme.title3),
      for (final e in s.ledger) _LedgerTile(e),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String emoji, label;
  final double value;
  final Color color;
  const _Stat(this.emoji, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$emoji $label', style: AppTheme.caption),
          const SizedBox(height: 2),
          CountUp(value,
              decimals: 0, style: AppTheme.title2.copyWith(color: color)),
        ]),
      );
}

class _LedgerTile extends StatelessWidget {
  final LedgerEntry e;
  const _LedgerTile(this.e);

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (e.kind) {
      LedgerKind.held => (Icons.lock_rounded, AppTheme.warn),
      LedgerKind.payout => (Icons.south_west_rounded, AppTheme.sprout),
      LedgerKind.fee => (Icons.receipt_long_rounded, AppTheme.textSecondary),
      LedgerKind.refund => (Icons.undo_rounded, AppTheme.sprout),
      LedgerKind.driver => (
          Icons.two_wheeler_rounded,
          AppTheme.livestockAccent
        ),
    };
    final amt = e.amount == 0
        ? 'Settled'
        : '${e.amount > 0 ? '+' : '-'}${rand(e.amount.abs(), decimals: 2)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.s2),
      child: GlassCard(
        padding: const EdgeInsets.all(AppTheme.s4),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, style: AppTheme.headline),
              Text(e.sub, style: AppTheme.footnote),
            ]),
          ),
          Text(amt,
              style: AppTheme.headline.copyWith(
                  color:
                      e.amount > 0 ? AppTheme.sprout : AppTheme.textPrimary)),
        ]),
      ),
    );
  }
}

// ================================================================ PLANS

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    return ScreenFrame(title: 'Farm plans', children: [
      const FreeVsPaidCard(),
      Text(
          'Every farm pays a small monthly platform fee that includes support, plus a commission on each sale. Move up when your sales make the lower commission worth it.',
          style: AppTheme.callout),
      for (final p in Plan.values)
        GlassCard(
          tint: s.plan == p ? AppTheme.sprout.withValues(alpha: 0.14) : null,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(p.label, style: AppTheme.title2)),
              if (s.plan == p)
                Pill('Current plan', color: AppTheme.sprout),
            ]),
            Text(p.blurb, style: AppTheme.footnote),
            const SizedBox(height: AppTheme.s3),
            Text(p.price == 0 ? 'R0 / month' : 'R${p.price} / month',
                style: AppTheme.title1.copyWith(color: AppTheme.sprout)),
            const SizedBox(height: AppTheme.s3),
            for (final perk in p.perks) _Bullet(perk),
            const SizedBox(height: AppTheme.s3),
            Text(
                'On R1 000 of sales you keep R${(1000 * (1 - p.commission) - p.price).round()}',
                style: AppTheme.footnote),
            const SizedBox(height: AppTheme.s3),
            GlassButton(
              label: s.plan == p ? 'Your plan' : (ref.watch(sellerPlanProvider) != null ? 'Ask Nolifa for ${p.label}' : 'Choose ${p.label}'),
              onPressed: s.plan == p
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      if (ref.read(sellerPlanProvider) != null) {
                        // Plans cost money, so Nolifa switches them on once payment is confirmed.
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Nolifa switches your plan on when your payment is confirmed. Contact us to change it.'),
                            behavior: SnackBarBehavior.floating));
                        return;
                      }
                      store.setPlan(p);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('You are on ${p.label} ✅'),
                          behavior: SnackBarBehavior.floating));
                    },
            ),
          ]),
        ),
      Text(
          'Grow pays for itself once you sell about R1 700 a month. Co-op beats Grow above about R5 000. Cancel any time, no lock-in.',
          style: AppTheme.footnote),
    ]);
  }
}

// ================================================================= KYC

class VerifyScreen extends ConsumerStatefulWidget {
  final KycRole role;
  const VerifyScreen({super.key, required this.role});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  String? _busy;

  Future<void> _run(KycStep step) async {
    setState(() => _busy = step.id);
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    ref.read(marketProvider.notifier).completeKyc(widget.role, step.id);
    setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(marketProvider);
    final steps = widget.role == KycRole.driver ? driverSteps : farmerSteps;
    final done = widget.role == KycRole.driver ? s.driverKyc : s.farmKyc;
    final all = done.length == steps.length;
    return ScreenFrame(
      title: widget.role == KycRole.driver
          ? 'Verify as a driver'
          : 'Verify your farm',
      children: [
        GlassCard(
          tint: all ? AppTheme.sprout.withValues(alpha: 0.14) : null,
          child: Row(children: [
            RingGauge(
              value: done.length / steps.length,
              size: 60,
              color: AppTheme.sprout,
              center: Text('${done.length}/${steps.length}',
                  style: AppTheme.headline),
            ),
            const SizedBox(width: AppTheme.s4),
            Expanded(
              child: Text(
                  all
                      ? 'You are FNB-verified. Buyers see your badge.'
                      : widget.role == KycRole.driver
                          ? 'Finish all steps to go online and accept jobs.'
                          : 'Finish all steps to list produce. Buyers trust verified farms.',
                  style:
                      AppTheme.callout.copyWith(color: AppTheme.textPrimary)),
            ),
          ]),
        ),
        for (final step in steps)
          GlassCard(
            padding: const EdgeInsets.all(AppTheme.s4),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      (done.contains(step.id) ? AppTheme.sprout : AppTheme.textPrimary)
                          .withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    done.contains(step.id) ? Icons.check_rounded : step.icon,
                    color: done.contains(step.id)
                        ? AppTheme.sprout
                        : AppTheme.textSecondary),
              ),
              const SizedBox(width: AppTheme.s3),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.title, style: AppTheme.headline),
                      Text(step.detail, style: AppTheme.footnote),
                    ]),
              ),
              if (!done.contains(step.id))
                _busy == step.id
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.sprout))
                    : GestureDetector(
                        onTap: _busy == null ? () => _run(step) : null,
                        child: Pill('Verify', color: AppTheme.sprout),
                      ),
            ]),
          ),
        Text(
            'Demo: each check is simulated. In production these call FNB identity services and Home Affairs.',
            style: AppTheme.caption),
      ],
    );
  }
}

// ============================================================= MONEY SPLIT

/// Shows exactly where each Rand goes. Used before paying and on receipts.
class MoneySplitCard extends StatelessWidget {
  final double farm;
  final double driver;
  final double platform;
  final double refund;
  final String farmNote;
  final String title;
  const MoneySplitCard({
    super.key,
    required this.farm,
    required this.driver,
    required this.platform,
    this.refund = 0,
    required this.farmNote,
    this.title = 'Where your money goes',
  });

  @override
  Widget build(BuildContext context) {
    final total =
        (farm + driver + platform + refund).clamp(0.01, double.infinity);
    Widget seg(double v, Color c) => Expanded(
          flex: ((v / total) * 1000).round().clamp(1, 1000),
          child: Container(height: 10, color: c),
        );
    Widget line(Color c, String name, String note, double v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: AppTheme.s3),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppTheme.callout
                            .copyWith(color: AppTheme.textPrimary)),
                    Text(note, style: AppTheme.caption),
                  ]),
            ),
            Text(rand(v, decimals: 2), style: AppTheme.headline),
          ]),
        );
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🧾 $title', style: AppTheme.headline),
        const SizedBox(height: AppTheme.s3),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(children: [
            seg(farm, AppTheme.sprout),
            seg(driver, AppTheme.livestockAccent),
            seg(platform, const Color(0xFF7FB7FF)),
            if (refund > 0) seg(refund, AppTheme.danger),
          ]),
        ),
        const SizedBox(height: AppTheme.s3),
        line(AppTheme.sprout, 'Farm', farmNote, farm),
        if (driver > 0)
          line(AppTheme.livestockAccent, 'Driver',
              '80% of delivery, paid on delivery', driver),
        line(const Color(0xFF7FB7FF), 'Nolifa Drop',
            driver > 0
                ? 'Service fee, commission, 20% of delivery'
                : 'Service fee and commission', platform),
        if (refund > 0)
          line(AppTheme.danger, 'Refunded to you',
              'Back to your original payment', refund),
      ]),
    );
  }
}

// ================================================================ DISPUTES

Future<void> showDisputeSheet(BuildContext context, Order order) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DisputeSheet(order: order),
  );
}

class _DisputeSheet extends ConsumerStatefulWidget {
  final Order order;
  const _DisputeSheet({required this.order});

  @override
  ConsumerState<_DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends ConsumerState<_DisputeSheet> {
  DisputeReason _reason = DisputeReason.notDelivered;
  final _note = TextEditingController();
  bool _photo = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.sheet,
          borderRadius:
              const BorderRadius.vertical(top: const Radius.circular(AppTheme.rCard)),
        ),
        padding: const EdgeInsets.all(AppTheme.s6),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('⚖️ Report a problem', style: AppTheme.title2),
                const SizedBox(height: 4),
                Text(
                    'Opening a case freezes the payment. Nobody is paid until it is resolved.',
                    style: AppTheme.footnote),
                const SizedBox(height: AppTheme.s4),
                for (final r in DisputeReason.values.where((r) => !r.systemOnly))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s2),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.s4, vertical: AppTheme.s3),
                      tint: _reason == r
                          ? AppTheme.sprout.withValues(alpha: 0.16)
                          : null,
                      onTap: () => setState(() => _reason = r),
                      child: Row(children: [
                        Text(r.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: AppTheme.s3),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.label, style: AppTheme.headline),
                                Text('Likely outcome: ${r.remedy}',
                                    style: AppTheme.caption),
                              ]),
                        ),
                        if (_reason == r)
                          Icon(Icons.check_circle_rounded,
                              color: AppTheme.sprout),
                      ]),
                    ),
                  ),
                const SizedBox(height: AppTheme.s2),
                GlassField(
                    controller: _note,
                    label: 'What happened? (optional)',
                    icon: Icons.edit_note_rounded),
                const SizedBox(height: AppTheme.s3),
                GestureDetector(
                  onTap: () => setState(() => _photo = !_photo),
                  child: Row(children: [
                    Icon(
                        _photo
                            ? Icons.check_circle_rounded
                            : Icons.add_a_photo_rounded,
                        color:
                            _photo ? AppTheme.sprout : AppTheme.textSecondary),
                    const SizedBox(width: AppTheme.s2),
                    Text(
                        _photo
                            ? 'Photo evidence attached'
                            : 'Add a photo as evidence',
                        style: AppTheme.callout),
                  ]),
                ),
                const SizedBox(height: AppTheme.s4),
                GlassButton(
                  label: 'Freeze payment and open case',
                  icon: Icons.gavel_rounded,
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    final store = ref.read(marketProvider.notifier);
                    final cur = ref.read(marketProvider).orderById(widget.order.id);
                    if (cur == null || !store.canDispute(cur)) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'This payment was already released. Contact FNB customer care for a review.'),
                          behavior: SnackBarBehavior.floating));
                      return;
                    }
                    store.openDispute(widget.order.id, _reason, _note.text.trim());
                    Navigator.pop(context);
                  },
                ),
              ]),
        ),
      ),
    );
  }
}

class DisputeTimeline extends StatelessWidget {
  final Dispute dispute;
  const DisputeTimeline({super.key, required this.dispute});

  @override
  Widget build(BuildContext context) {
    final stage = switch (dispute.stage) {
      DisputeStage.open => ('Case open', AppTheme.warn),
      DisputeStage.review => ('In review', AppTheme.warn),
      DisputeStage.resolved => ('Resolved', AppTheme.sprout),
    };
    return GlassCard(
      tint: stage.$2.withValues(alpha: 0.10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child:
                  Text('⚖️ ${dispute.reason.label}', style: AppTheme.headline)),
          Pill(stage.$1, color: stage.$2),
        ]),
        const SizedBox(height: AppTheme.s3),
        for (final e in dispute.timeline)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Icon(Icons.circle, size: 8, color: AppTheme.sprout)),
              const SizedBox(width: AppTheme.s3),
              Expanded(
                  child: Text(e.$1,
                      style: AppTheme.footnote
                          .copyWith(color: AppTheme.textPrimary))),
            ]),
          ),
        if (dispute.stage != DisputeStage.resolved) ...[
          const SizedBox(height: AppTheme.s2),
          Text('Decision within 48 hours in production.',
              style: AppTheme.caption),
        ],
      ]),
    );
  }
}

// ============================================================ OUTBREAK REPORTS

class CasePipeline extends StatelessWidget {
  final ReportCase c;
  const CasePipeline(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    const stages = [
      ReportStage.submitted,
      ReportStage.aiChecked,
      ReportStage.corroborated,
      ReportStage.vetVerified,
    ];
    final idx = stages.indexOf(c.stage);
    return Row(children: [
      for (var i = 0; i < stages.length; i++) ...[
        Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= idx ? AppTheme.sprout : Colors.transparent,
              border: Border.all(
                  color: i <= idx ? AppTheme.sprout : AppTheme.glassBorder,
                  width: 2),
            ),
            child: i <= idx
                ? Icon(Icons.check_rounded,
                    size: 12, color: AppTheme.onAccent)
                : null,
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(stages[i].label,
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(fontSize: 10)),
          ),
        ]),
        if (i < stages.length - 1)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Container(
                  height: 2,
                  color: i < idx ? AppTheme.sprout : AppTheme.glassBorder),
            ),
          ),
      ],
    ]);
  }
}

class CaseCard extends ConsumerWidget {
  final ReportCase c;
  const CaseCard(this.c, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final broadcast = c.stage.broadcasts;
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(c.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.title, style: AppTheme.headline),
              Text(
                  '${c.area}  •  AI confidence ${c.aiConfidence}%${c.mine ? '  •  yours' : ''}',
                  style: AppTheme.footnote),
            ]),
          ),
        ]),
        const SizedBox(height: AppTheme.s4),
        CasePipeline(c),
        const SizedBox(height: AppTheme.s3),
        Row(children: [
          Expanded(
            child: Text(
                broadcast
                    ? 'Public: nearby farms are being alerted.'
                    : 'Private until ${2 - c.confirmations > 0 ? '${2 - c.confirmations} more farm${2 - c.confirmations == 1 ? '' : 's'} confirm' : 'confirmed'}.',
                style: AppTheme.caption.copyWith(
                    color:
                        broadcast ? AppTheme.sprout : AppTheme.textTertiary)),
          ),
          if (!c.mine && !broadcast)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (!ref.read(marketProvider.notifier).confirmCase(c.id)) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Only verified farmers can confirm an outbreak, so reports cannot be faked.'),
                    action: SnackBarAction(
                      label: 'Verify',
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const VerifyScreen(role: KycRole.farmer))),
                    ),
                  ));
                }
              },
              child:
                  Pill('I see this too', color: AppTheme.livestockAccent),
            ),
        ]),
      ]),
    );
  }
}

Future<void> showReportSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ReportSheet(),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet();

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  static const _kinds = [
    ('🌿', 'Crop disease'),
    ('🐄', 'Livestock illness'),
    ('🐛', 'Pest infestation'),
    ('💧', 'Water contamination'),
  ];
  int _k = 0;
  final _what = TextEditingController();
  bool _photo = true;

  @override
  void dispose() {
    _what.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.sheet,
          borderRadius:
              const BorderRadius.vertical(top: const Radius.circular(AppTheme.rCard)),
        ),
        padding: const EdgeInsets.all(AppTheme.s6),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🚩 Report a case', style: AppTheme.title2),
                const SizedBox(height: 4),
                Text(
                    'Your report is AI checked now. It only alerts other farms after neighbours confirm it or a vet verifies it.',
                    style: AppTheme.footnote),
                const SizedBox(height: AppTheme.s4),
                Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
                  for (var i = 0; i < _kinds.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _k = i),
                      child: Pill('${_kinds[i].$1} ${_kinds[i].$2}',
                          color: _k == i
                              ? AppTheme.sprout
                              : AppTheme.textTertiary),
                    ),
                ]),
                const SizedBox(height: AppTheme.s3),
                GlassField(
                    controller: _what,
                    label: 'What are you seeing? (e.g. leaf rust)',
                    icon: Icons.search_rounded),
                const SizedBox(height: AppTheme.s3),
                GestureDetector(
                  onTap: () => setState(() => _photo = !_photo),
                  child: Row(children: [
                    Icon(
                        _photo
                            ? Icons.check_circle_rounded
                            : Icons.add_a_photo_rounded,
                        color:
                            _photo ? AppTheme.sprout : AppTheme.textSecondary),
                    const SizedBox(width: AppTheme.s2),
                    Text(_photo ? 'Photo and GPS attached' : 'Attach a photo',
                        style: AppTheme.callout),
                  ]),
                ),
                const SizedBox(height: AppTheme.s4),
                GlassButton(
                  label: 'Submit for checking',
                  icon: Icons.send_rounded,
                  onPressed: () {
                    final title = _what.text.trim().isEmpty
                        ? _kinds[_k].$2
                        : _what.text.trim();
                    ref
                        .read(marketProvider.notifier)
                        .submitReport(title, _kinds[_k].$1, 'Your area');
                    HapticFeedback.mediumImpact();
                    Navigator.pop(context);
                  },
                ),
              ]),
        ),
      ),
    );
  }
}
