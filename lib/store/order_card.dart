import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show Order, OrderStatus, Pill, askCustomerPin, marketProvider;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'store_common.dart';

/// The status badge for an order, in the words a farmer would use.
({String label, Color color}) orderBadge(Order o) {
  if (o.released) {
    // A full refund pays the farm nothing, so "Paid out" would mislead.
    return o.farmFactor == 0
        ? (label: 'Refunded', color: AppTheme.danger)
        : (label: 'Paid out', color: AppTheme.sprout);
  }
  if (o.disputed) return (label: 'Case open', color: AppTheme.danger);
  if (o.selfDelivery) {
    if (o.status == OrderStatus.assigned) {
      return (label: 'Ready to deliver', color: AppTheme.plantAccent);
    }
    if (o.status == OrderStatus.pickedUp) {
      return (label: 'Out for delivery', color: AppTheme.plantAccent);
    }
  }
  return switch (o.status) {
    OrderStatus.newOrder => (label: 'New', color: AppTheme.warn),
    OrderStatus.findingDriver => (
        label: 'Waiting for a driver',
        color: AppTheme.livestockAccent
      ),
    OrderStatus.assigned => (
        label: 'Driver on the way',
        color: AppTheme.plantAccent
      ),
    OrderStatus.pickedUp => (label: 'On its way', color: AppTheme.plantAccent),
    OrderStatus.delivered => (label: 'Delivered', color: AppTheme.sprout),
  };
}

/// What reaches the farmer for this order, and whether the figure is final.
///
/// A new order has no commission locked in yet, so it uses the farmer's
/// current plan. Once packed, the order carries the rate it was packed at.
({double amount, bool settled}) youReceive(Order o, double planCommission) {
  if (o.released) return (amount: o.mySalesNet, settled: true);
  final rate = o.status == OrderStatus.newOrder ? planCommission : o.commission;
  return (amount: o.mySalesGross * (1 - rate), settled: false);
}

/// Where the order goes, or null when the buyer gave no real area. Orders
/// placed in the app carry the buyer's placeholder "Your street".
String? dropAreaFor(Order o) =>
    o.dropArea.isEmpty || o.dropArea == 'Your street' ? null : o.dropArea;

/// One order the farmer received: who bought, what, what it pays, and where it is.
class OrderCard extends ConsumerWidget {
  final Order order;
  final double planCommission;
  const OrderCard(this.order, {super.key, required this.planCommission});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = order;
    final badge = orderBadge(o);
    final pay = youReceive(o, planCommission);
    final mine = o.lines.where((l) => l.mine);
    // Show only this farmer's lines when an order mixes several farms.
    final lines = mine.isEmpty ? o.lines : mine.toList();

    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      tint: o.status == OrderStatus.newOrder
          ? AppTheme.warn.withValues(alpha: 0.10)
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${o.id}  •  ${timeAgo(o.placed)}',
                style: AppTheme.caption),
          ),
          Pill(badge.label, color: badge.color),
        ]),
        const SizedBox(height: AppTheme.s3),
        Row(children: [
          Icon(Icons.person_rounded,
              size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: AppTheme.s2),
          Expanded(
            child: Text(
              '${firstName(o.customer)}  •  ${dropAreaFor(o) ?? 'Area not given'}',
              style: AppTheme.headline,
            ),
          ),
        ]),
        const SizedBox(height: AppTheme.s2),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.s1),
            child: Row(children: [
              Text(l.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: AppTheme.s2),
              Expanded(
                  child: Text('${l.qty} × ${l.name}', style: AppTheme.callout)),
              Text(money(l.total), style: AppTheme.subhead),
            ]),
          ),
        const Divider(height: AppTheme.s5),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sale', style: AppTheme.caption),
              Text(money(o.mySalesGross), style: AppTheme.title3),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(pay.settled ? 'You receive' : 'You receive about',
                style: AppTheme.caption),
            Text(
              money(pay.amount),
              style: AppTheme.title3.copyWith(color: AppTheme.sprout),
            ),
          ]),
        ]),
        if (o.driver != null && !o.selfDelivery) ...[
          const SizedBox(height: AppTheme.s2),
          Row(children: [
            Icon(Icons.two_wheeler_rounded,
                size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: AppTheme.s2),
            Expanded(
                child: Text('Driver: ${o.driver}', style: AppTheme.footnote)),
          ]),
        ],
        if (o.selfDelivery && o.farmIsMe && o.status != OrderStatus.delivered) ...[
          const SizedBox(height: AppTheme.s2),
          Row(children: [
            const Text('🚜', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: AppTheme.s2),
            Expanded(child: Text('You deliver this one yourself', style: AppTheme.footnote)),
          ]),
        ],
        if (o.status == OrderStatus.newOrder) ...[
          const SizedBox(height: AppTheme.s3),
          GlassButton(
            label: o.selfDelivery ? 'Packed, I am delivering' : 'Packed, request driver',
            icon: o.selfDelivery ? Icons.agriculture_rounded : Icons.local_shipping_rounded,
            onPressed: () {
              HapticFeedback.mediumImpact();
              ref.read(marketProvider.notifier).packOrder(o.id);
            },
          ),
        ],
        if (o.route == 'hub' && o.farmIsMe && o.status == OrderStatus.findingDriver && o.hubStage != null && o.hubStage != 'released') ...[
          const SizedBox(height: AppTheme.s3),
          GlassCard(
            tint: AppTheme.warn.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(AppTheme.s4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  o.hubStage == 'toHub'
                      ? 'Take this to the ${o.hub ?? 'hub'}'
                      : o.hubStage == 'droppedOff'
                          ? 'At the hub, waiting to be checked in'
                          : 'Checked in at the hub',
                  style: AppTheme.headline),
              const SizedBox(height: 2),
              Text(
                  o.hubStage == 'toHub'
                      ? 'This buyer is ${o.distanceKm.round()} km away, so a hub driver brings it the last stretch. Write this code on the packing slip: ${o.hubCode}'
                      : 'Hub code ${o.hubCode}. A last-mile driver collects it once the hub releases it.',
                  style: AppTheme.footnote),
              if (o.hubStage == 'toHub') ...[
                const SizedBox(height: AppTheme.s3),
                GlassButton(
                  label: 'I dropped it at the hub',
                  icon: Icons.inventory_2_rounded,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ref.read(marketProvider.notifier).dropAtHub(o.id);
                  },
                ),
              ],
            ]),
          ),
        ],
        if (o.selfDelivery && o.farmIsMe && o.driverIsMe && o.status == OrderStatus.assigned) ...[
          const SizedBox(height: AppTheme.s3),
          GlassButton(
            label: 'Out for delivery',
            icon: Icons.local_shipping_rounded,
            onPressed: () {
              HapticFeedback.mediumImpact();
              ref.read(marketProvider.notifier).pickedUp(o.id);
            },
          ),
        ],
        if (o.selfDelivery && o.farmIsMe && o.driverIsMe && o.status == OrderStatus.pickedUp) ...[
          const SizedBox(height: AppTheme.s3),
          GlassButton(
            label: 'Delivered, enter customer PIN',
            icon: Icons.pin_rounded,
            onPressed: () {
              HapticFeedback.heavyImpact();
              askCustomerPin(context, ref.read(marketProvider.notifier), o);
            },
          ),
        ],
      ]),
    );
  }
}
