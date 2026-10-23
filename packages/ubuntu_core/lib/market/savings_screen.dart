import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'market_models.dart';
import 'market_store.dart';
import 'market_widgets.dart';
import 'shop_screens.dart';
import 'trust_screens.dart' show ScreenFrame;

/// What a household has saved, what it paid in fees, and what it could save today.
class HouseholdSavings {
  final double groupSaved; // group buys and shared delivery, from the store's running total
  final double rescueSaved; // rescue deals bought, from the orders
  final double spent; // food bought, before fees
  final double fees; // service and delivery fees paid
  final int orders;
  final List<Product> rescueNow;
  final List<Product> groupsOpen;

  const HouseholdSavings(
      this.groupSaved, this.rescueSaved, this.spent, this.fees, this.orders, this.rescueNow, this.groupsOpen);

  double get totalSaved => r2(groupSaved + rescueSaved);
  double get net => r2(totalSaved - fees);
  double get feePercent => spent <= 0 ? 0 : r2(fees / spent * 100);

  /// Saved on one of every rescue deal listed now.
  double get rescuePotential =>
      r2(rescueNow.fold(0.0, (a, p) => a + ((p.wasPrice ?? p.price) - p.price)));
}

HouseholdSavings householdSavings(MarketState s) {
  final byId = {for (final p in s.products) p.id: p};
  var rescue = 0.0, spent = 0.0, fees = 0.0;
  final mine = s.myOrders;
  for (final o in mine) {
    spent += o.subtotal;
    fees += o.serviceFee + o.deliveryFee;
    for (final l in o.lines) {
      final was = byId[l.productId]?.wasPrice;
      if (was != null && was > l.price) rescue += (was - l.price) * l.qty;
    }
  }
  return HouseholdSavings(
    s.saved,
    r2(rescue),
    r2(spent),
    r2(fees),
    mine.length,
    [for (final p in s.products) if (p.wasPrice != null && p.available && !p.soldOut) p],
    [for (final p in s.products) if (p.groupTarget > 0 && p.available && !s.joined.contains(p.id)) p],
  );
}

/// The household's savings, in plain Rand.
class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final v = householdSavings(s);
    return ScreenFrame(title: 'My savings', children: [
      GlassCard(
        tint: AppTheme.sprout.withValues(alpha: 0.12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You have saved', style: AppTheme.caption),
          CountUp(v.totalSaved, style: AppTheme.largeTitle.copyWith(color: AppTheme.sprout)),
          const SizedBox(height: AppTheme.s2),
          Row(children: [
            Expanded(child: _Stat('Rescue deals', rand(v.rescueSaved))),
            Expanded(child: _Stat('Group buys', rand(v.groupSaved))),
            Expanded(child: _Stat('Fees paid', rand(v.fees))),
          ]),
          const SizedBox(height: AppTheme.s3),
          Text(
              v.net >= 0
                  ? 'After fees you are ${rand(v.net)} ahead.'
                  : 'Fees are ${rand(-v.net)} more than you saved so far. Rescue deals and group buys change that.',
              style: AppTheme.callout.copyWith(color: AppTheme.textPrimary)),
          if (v.orders > 0)
            Text('${v.orders} order${v.orders == 1 ? '' : 's'}, ${rand(v.spent)} of food. Fees are ${v.feePercent.toStringAsFixed(1)}% of what you spent.',
                style: AppTheme.footnote),
        ]),
      ),
      if (v.rescueNow.isNotEmpty) ...[
        Text('Rescue deals now', style: AppTheme.title3),
        Text('Good food at a lower price. Take one of each and save ${rand(v.rescuePotential)}.', style: AppTheme.footnote),
        for (final p in v.rescueNow.take(5)) _Deal(p, 'Was ${rand(p.wasPrice!)}, now ${rand(p.price)}'),
      ],
      if (v.groupsOpen.isNotEmpty) ...[
        Text('Group buys you can join', style: AppTheme.title3),
        Text('Neighbours order together and share the delivery.', style: AppTheme.footnote),
        for (final p in v.groupsOpen.take(4)) _Deal(p, '${p.groupJoined} of ${p.groupTarget} joined'),
      ],
      if (v.rescueNow.isEmpty && v.groupsOpen.isEmpty)
        GlassCard(child: Text('No deals right now. Check back, new rescue deals appear when farms have surplus.', style: AppTheme.callout)),
      Text('Savings from rescue deals are worked out from your orders. Group-buy savings use the running total on this phone.', style: AppTheme.caption),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: AppTheme.title3),
        Text(label, style: AppTheme.caption),
      ]);
}

class _Deal extends ConsumerWidget {
  final Product p;
  final String line;
  const _Deal(this.p, this.line);

  @override
  Widget build(BuildContext context, WidgetRef ref) => GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
        child: Row(children: [
          Text(p.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p.name}, ${p.farm}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary)),
              Text(line, style: AppTheme.caption),
            ]),
          ),
          IconButton(
            tooltip: 'Add to basket',
            icon: Icon(Icons.add_circle_rounded, color: AppTheme.sprout),
            onPressed: () => addToBasket(context, ref, p),
          ),
        ]),
      );
}
