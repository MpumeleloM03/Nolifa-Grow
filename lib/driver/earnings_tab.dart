import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show CountUp, DriverPayout, Reveal, WalletScreen, driverPayoutsProvider, marketProvider, rand;
import '../theme/app_theme.dart';
import '../theme/glass.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;

/// The driver's money: what they have earned, what is still waiting for the
/// customer's PIN, and each payout the server recorded.
class EarningsTab extends ConsumerWidget {
  const EarningsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final payouts = ref.watch(driverPayoutsProvider).valueOrNull ?? const <DriverPayout>[];
    final done = s.orders.where((o) => o.driverIsMe && o.released).length;
    final active = s.myJobs.length;
    final pending = payouts.where((p) => p.pending).fold<double>(0, (a, p) => a + p.amount);
    final earned = payouts.isEmpty
        ? s.driverEarned
        : payouts.where((p) => p.released).fold<double>(0, (a, p) => a + p.amount);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s6, AppTheme.s6, AppTheme.s2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Earnings', style: AppTheme.largeTitle),
              Text('Paid when the customer gives you their PIN', style: AppTheme.callout),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s4, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            Reveal(
              child: GlassCard(
                tint: AppTheme.sprout.withValues(alpha: 0.12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('You have earned', style: AppTheme.caption),
                  CountUp(earned, prefix: 'R', style: AppTheme.largeTitle.copyWith(color: AppTheme.sprout)),
                  if (pending > 0)
                    Text('plus ${rand(pending, decimals: 2)} waiting for a PIN', style: AppTheme.footnote),
                  const SizedBox(height: AppTheme.s4),
                  Row(children: [
                    Expanded(child: _Count(done, 'deliveries done', AppTheme.textPrimary)),
                    Expanded(child: _Count(active, 'on the go now', AppTheme.plantAccent)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: AppTheme.s3),
            Reveal(
              index: 1,
              child: GlassCard(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, color: AppTheme.sprout),
                  const SizedBox(width: AppTheme.s3),
                  Expanded(
                    child: Text(
                      'R12 a delivery plus R2.50 a km, never under R24. A farm that delivers itself keeps its own fee.',
                      style: AppTheme.footnote,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: AppTheme.s5),
            Text('Payouts', style: AppTheme.headline),
            const SizedBox(height: AppTheme.s2),
            if (payouts.isEmpty)
              Text('Your payouts show here after each delivery.', style: AppTheme.footnote)
            else
              for (var i = 0; i < payouts.length && i < 30; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.s2),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
                    child: Row(children: [
                      Icon(
                        payouts[i].released ? Icons.check_circle_rounded : Icons.schedule_rounded,
                        color: payouts[i].released ? AppTheme.sprout : AppTheme.warn,
                      ),
                      const SizedBox(width: AppTheme.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Order ${payouts[i].orderId}', style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary)),
                          Text(
                            '${payouts[i].km.toStringAsFixed(1)} km · ${payouts[i].released ? 'paid' : (payouts[i].pending ? 'waiting for PIN' : 'cancelled')}',
                            style: AppTheme.caption,
                          ),
                        ]),
                      ),
                      Text(rand(payouts[i].amount, decimals: 2), style: AppTheme.headline),
                    ]),
                  ),
                ),
            const SizedBox(height: AppTheme.s3),
            GlassButton(
              label: 'Wallet and payout account',
              icon: Icons.account_balance_wallet_rounded,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
            ),
          ]),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  final int n;
  final String label;
  final Color color;
  const _Count(this.n, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n', style: AppTheme.title1.copyWith(color: color)),
        Text(label, style: AppTheme.caption),
      ]);
}
