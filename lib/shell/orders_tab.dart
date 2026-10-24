import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        BusinessScreen,
        CountUp,
        DeliveryModeX,
        fatboyRange,
        MarketState,
        Order,
        OrderStatus,
        PlanX,
        PlansScreen,
        Pill,
        Reveal,
        SectionTitle,
        WalletScreen,
        marketProvider,
        marketSharedProvider;
import '../store/add_stock_sheet.dart';
import '../store/order_card.dart';
import '../store/stock_card.dart';
import '../store/store_common.dart' show firstName, money, timeAgo;
import '../store/order_rows.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// The selling side: what the farm has made, what has to go out, and what the
/// neighbours bought.
class OrdersTab extends ConsumerWidget {
  const OrdersTab({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final shared = ref.watch(marketSharedProvider);
    final stock = [
      for (final p in s.products)
        if (p.mine) p
    ];
    final orders = sortedFarmOrders(s.farmOrders);
    final toSend = orders.where((o) => o.status == OrderStatus.newOrder).length;
    final onTheWay = orders
        .where((o) =>
            o.status == OrderStatus.findingDriver ||
            o.status == OrderStatus.assigned ||
            o.status == OrderStatus.pickedUp)
        .length;
    final pending = orders
        .where((o) => !o.released && !o.disputed)
        .fold<double>(0, (a, o) => a + youReceive(o, s.plan.commission).amount);
    final rows = orderRows(orders);
    final news = _notifications(orders);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s6, AppTheme.s6, AppTheme.s2),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Orders', style: AppTheme.largeTitle),
                  Text('Sales through Nolifa Drop', style: AppTheme.callout),
                ]),
              ),
              if (s.demoMode) Pill('Demo', color: AppTheme.warn, icon: Icons.science_rounded),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s4, AppTheme.s6, 140),
          sliver: SliverList.list(children: [
            if (!shared)
              const Padding(
                padding: EdgeInsets.only(bottom: AppTheme.s3),
                child: LocalModeBadge(
                    detail: 'Saved on this phone only. Neighbours cannot see your stock yet.'),
              ),
            Reveal(child: _Earnings(s, pending, toSend, onTheWay)),
            const SizedBox(height: AppTheme.s3),
            Reveal(index: 1, child: _SellingStatus(s)),
            if (news.isNotEmpty) ...[
              const SectionTitle('🔔', 'Notifications'),
              for (var i = 0; i < news.length; i++)
                Reveal(index: i, child: news[i]),
            ],
            SectionTitle('📥', 'Orders received',
                trailing: toSend == 0 ? null : Pill('$toSend to send', color: AppTheme.warn)),
            if (rows.isEmpty)
              GlassCard(
                child: Row(children: [
                  const Text('📭', style: TextStyle(fontSize: 30)),
                  const SizedBox(width: AppTheme.s3),
                  Expanded(
                    child: Text(
                      s.canSell
                          ? (shared
                              ? 'No orders yet. Your stock is visible to neighbours nearby.'
                              : 'No orders yet. They show up here once your stock is shared with neighbours.')
                          : 'Finish setting up your store and orders will appear here.',
                      style: AppTheme.callout,
                    ),
                  ),
                ]),
              )
            else
              for (var i = 0; i < rows.length; i++)
                Reveal(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s3),
                    child: rows[i] is Order
                        ? OrderCard(rows[i] as Order,
                            key: ValueKey('order-${(rows[i] as Order).id}'),
                            planCommission: s.plan.commission)
                        : Text('${rows[i]}', style: AppTheme.subhead),
                  ),
                ),
            SectionTitle('🧺', 'My stock',
                trailing: stock.isEmpty ? null : Pill('${stock.length} listed', color: AppTheme.sprout)),
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.s3),
              child: GlassButton(
                label: 'Add stock',
                icon: Icons.add_rounded,
                onPressed: () => startAddStock(context, ref),
              ),
            ),
            if (s.canSell && stock.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.s3),
                child: GhostButton(
                  label: 'Quick start: add the Fatboy Butcheries range',
                  icon: Icons.restaurant_rounded,
                  onPressed: () {
                    final why = ref.read(marketProvider.notifier).listRange(fatboyRange);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(why ?? 'Added ${fatboyRange.length} products from the Fatboy Butcheries shop.')));
                  },
                ),
              ),
            if (stock.isEmpty)
              GlassCard(
                onTap: () => startAddStock(context, ref),
                child: Row(children: [
                  const Text('📸', style: TextStyle(fontSize: 30)),
                  const SizedBox(width: AppTheme.s3),
                  Expanded(
                    child: Text(
                      s.canSell
                          ? 'Add your first stock in a minute. Neighbours near you can buy it today.'
                          : 'You can list stock once your store is registered, verified and on a plan.',
                      style: AppTheme.callout,
                    ),
                  ),
                ]),
              )
            else
              for (var i = 0; i < stock.length; i++)
                Reveal(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s3),
                    child: StockCard(stock[i], key: ValueKey('stock-${stock[i].id}')),
                  ),
                ),
            const SectionTitle('👛', 'Money'),
            Row(children: [
              Expanded(
                child: _Link('Wallet', 'Payouts and receipts', () => _open(context, const WalletScreen())),
              ),
              const SizedBox(width: AppTheme.s3),
              Expanded(
                child: _Link('Plans', 'Lower your commission', () => _open(context, const PlansScreen())),
              ),
            ]),
          ]),
        ),
      ],
    );
  }

  /// A short feed built from orders: what just came in, what got paid.
  List<Widget> _notifications(List<Order> orders) {
    final out = <Widget>[];
    for (final o in orders.take(12)) {
      final mineLines = o.lines.where((l) => l.mine).toList();
      final n = (mineLines.isEmpty ? o.lines : mineLines).fold<int>(0, (a, l) => a + l.qty);
      final who = firstName(o.customer);
      final (icon, color, text) = o.disputed
          ? (Icons.report_gmailerrorred_rounded, AppTheme.danger, 'Case open on ${o.id} from $who')
          : o.released
              ? (Icons.payments_rounded, AppTheme.sprout,
                  '${money(o.mySalesNet)} paid out for ${o.id}')
              : switch (o.status) {
                  OrderStatus.newOrder => (
                      Icons.shopping_bag_rounded,
                      AppTheme.warn,
                      '$who ordered $n item${n == 1 ? '' : 's'}, ${money((mineLines.isEmpty ? o.lines : mineLines).fold<double>(0, (a, l) => a + l.total))}. Pack it and send it out.'
                    ),
                  OrderStatus.delivered => (
                      Icons.check_circle_rounded,
                      AppTheme.sprout,
                      '${o.id} delivered to $who. Payout follows when they confirm.'
                    ),
                  _ => (
                      Icons.local_shipping_rounded,
                      AppTheme.plantAccent,
                      '${o.id} for $who is on its way'
                    ),
                };
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.s2),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
          child: Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppTheme.s3),
            Expanded(child: Text(text, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary))),
            const SizedBox(width: AppTheme.s2),
            Text(timeAgo(o.placed), style: AppTheme.caption),
          ]),
        ),
      ));
      if (out.length == 4) break;
    }
    return out;
  }
}

class _Earnings extends StatelessWidget {
  final MarketState s;
  final double pending;
  final int toSend, onTheWay;
  const _Earnings(this.s, this.pending, this.toSend, this.onTheWay);

  @override
  Widget build(BuildContext context) => GlassCard(
        tint: AppTheme.sprout.withValues(alpha: 0.12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You have made', style: AppTheme.caption),
          CountUp(s.farmEarned, style: AppTheme.largeTitle.copyWith(color: AppTheme.sprout)),
          if (pending > 0)
            Text('plus about ${money(pending)} still to come in', style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s4),
          Row(children: [
            Expanded(child: _Count(toSend, 'to send out', toSend > 0 ? AppTheme.warn : AppTheme.textSecondary)),
            Expanded(child: _Count(onTheWay, 'on the way', AppTheme.plantAccent)),
            Expanded(child: _Count(s.farmOrders.length, 'orders in all', AppTheme.textSecondary)),
          ]),
        ]),
      );
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

/// Where the farm stands on selling: registered, verified, plan, delivery.
class _SellingStatus extends StatelessWidget {
  final MarketState s;
  const _SellingStatus(this.s);

  @override
  Widget build(BuildContext context) {
    final open = s.canSell;
    final limited = open && !s.inspectionPassed;
    return GlassCard(
      tint: (open && !limited ? AppTheme.sprout : AppTheme.warn).withValues(alpha: 0.10),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const BusinessScreen())),
      child: Row(children: [
        Text(limited ? '🟡' : (open ? '✅' : '🔒'), style: const TextStyle(fontSize: 28)),
        const SizedBox(width: AppTheme.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(limited ? 'Selling with limits' : (open ? 'Your store is open' : 'Finish setup to start selling'),
                style: AppTheme.headline),
            Text(
                limited
                    ? 'Fresh produce only, up to ${money(s.provisionalRoom)} more. Book your inspection to lift the limits. ${s.provisionalDaysLeft} days left.'
                    : open
                        ? '${s.plan.label} plan, ${(s.plan.commission * 100).round()}% commission, ${s.profile.delivery.label}'
                        : 'Register, get verified, pick a plan and show your land',
                style: AppTheme.footnote),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
      ]),
    );
  }
}

class _Link extends StatelessWidget {
  final String title, note;
  final VoidCallback onTap;
  const _Link(this.title, this.note, this.onTap);

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.s4),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTheme.headline),
          Text(note, style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s2),
          Text('Open →',
              style: AppTheme.footnote.copyWith(color: AppTheme.sprout, fontWeight: FontWeight.w600)),
        ]),
      );
}
