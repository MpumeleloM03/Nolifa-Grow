import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// What the driver has made, per delivery, and how the pay works.
class EarningsPage extends ConsumerWidget {
  const EarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final done = s.orders.where((o) => o.driverIsMe && o.status == OrderStatus.delivered).toList()
      ..sort((a, b) => b.placed.compareTo(a.placed));
    // The server's own record is the truth where there is one; the phone's
    // figure covers the phone-only mode.
    final server = ref.watch(driverPayoutsProvider).valueOrNull ?? const <DriverPayout>[];
    final byOrder = {for (final p in server) p.orderId: p};
    double payOf(Order o) => byOrder[o.id]?.amount ?? o.driverPay;
    final waiting = server.isNotEmpty
        ? server.where((p) => p.pending).fold<double>(0, (a, p) => a + p.amount)
        : done.where((o) => !o.released).fold<double>(0, (a, o) => a + o.driverPay);
    final paid = server.isNotEmpty ? server.where((p) => p.released).fold<double>(0, (a, p) => a + p.amount) : s.driverEarned;
    final km = server.fold<double>(0, (a, p) => a + p.km);
    final entries = s.ledger.where((e) => e.kind == LedgerKind.payout).take(8).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: ParallaxHeader(
            emoji: '💸',
            title: 'Earnings',
            subtitle: 'Paid when the customer confirms',
            accent: AppTheme.sprout,
            trailing: const HeaderActions(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            Reveal(
              child: GlassCard(
                tint: AppTheme.sprout.withValues(alpha: 0.12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('You have earned', style: AppTheme.caption),
                  CountUp(paid, style: AppTheme.largeTitle.copyWith(color: AppTheme.sprout)),
                  if (waiting > 0)
                    Text('${rand(waiting)} more once customers confirm', style: AppTheme.footnote),
                  const SizedBox(height: AppTheme.s3),
                  Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
                    Pill('${done.length} deliveries', color: AppTheme.livestockAccent),
                    Pill('R${DriverPay.base.round()} + R${DriverPay.perKm.toStringAsFixed(2)} a km',
                        color: AppTheme.textSecondary),
                    if (km > 0) Pill('${km.round()} km driven', color: AppTheme.textSecondary),
                  ]),
                ]),
              ),
            ),
            const SectionTitle('🧾', 'Recent deliveries'),
            if (done.isEmpty)
              GlassCard(
                child: Text('Finished deliveries show up here.', style: AppTheme.callout),
              )
            else
              for (final o in done.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.s2),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.s4, vertical: AppTheme.s3),
                    child: Row(children: [
                      Text(o.lines.first.emoji, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: AppTheme.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${o.id}  •  ${o.pickup}', style: AppTheme.headline),
                          Text(
                              '${o.released ? 'Paid' : 'Waiting for confirmation'}'
                              '${byOrder[o.id] == null ? '' : '  •  ${rand(byOrder[o.id]!.base, decimals: 0)} + ${byOrder[o.id]!.km.toStringAsFixed(1)} km${byOrder[o.id]!.minimumTopUp > 0 ? ' + minimum' : ''}'}',
                              style: AppTheme.caption),
                        ]),
                      ),
                      Text(rand(payOf(o)),
                          style: AppTheme.headline.copyWith(color: AppTheme.sprout)),
                    ]),
                  ),
                ),
            if (entries.isNotEmpty) ...[
              const SectionTitle('👛', 'Payouts'),
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.s2),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.s4, vertical: AppTheme.s3),
                    child: Row(children: [
                      Expanded(child: Text(e.title, style: AppTheme.body)),
                      Text(rand(e.amount), style: AppTheme.headline),
                    ]),
                  ),
                ),
            ],
            const SectionTitle('ℹ️', 'How you are paid'),
            GlassCard(
              child: Text(
                  'You are paid for the work, not for the size of the order: R${DriverPay.base.round()} for each delivery plus R${DriverPay.perKm.toStringAsFixed(2)} for every road kilometre, and never less than R${DriverPay.minimum.round()}. '
                  'If the customer\'s delivery fee does not cover that, Nolifa pays the difference. '
                  'The server records the amount when the customer\'s PIN is accepted, and it is released when they confirm, or automatically after 2 hours. '
                  'A full refund or a conduct complaint cancels it. Farms that deliver themselves do not use drivers.',
                  style: AppTheme.callout),
            ),
            const SizedBox(height: AppTheme.s3),
            GlassCard(
              child: Text(
                  'Fuel is not added on top. We budget R${DriverPay.fuelPerKm.toStringAsFixed(2)} a km for a small car, so the batch screen shows your pay per hour before and after fuel. If your real costs are higher, tell us in Account > Help.',
                  style: AppTheme.footnote),
            ),
            const SizedBox(height: AppTheme.s3),
            GlassButton(
              label: 'Wallet and receipts',
              icon: Icons.account_balance_wallet_rounded,
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const WalletScreen())),
            ),
          ]),
        ),
      ],
    );
  }
}
