import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'market_models.dart';
import 'market_store.dart';
import 'drive_page.dart' show trackMapProvider;
import 'honesty.dart';
import 'market_widgets.dart';
import 'trust_screens.dart';

// ---------------------------------------------------------------- SHOP PIECES

/// Adds a product to the basket. A basket holds one farm at a time, so if it
/// holds another farm's produce, ask before starting a new one.
Future<void> addToBasket(BuildContext context, WidgetRef ref, Product p, [int n = 1]) async {
  final store = ref.read(marketProvider.notifier);
  if (store.add(p.id, n)) return;
  if (!p.buyable) return;
  final current = ref.read(marketProvider).cartFarm;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.sheet,
      title: Text('Start a new basket?', style: AppTheme.title3),
      content: Text(
          'Your basket has items from $current. One farm delivers one basket, so adding from ${p.farm} starts a new one.',
          style: AppTheme.callout),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep my basket', style: TextStyle(color: AppTheme.textSecondary))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Start new', style: TextStyle(color: AppTheme.sprout))),
      ],
    ),
  );
  if (ok == true) store.startNewBasket(p.id, n);
}

class CategoryChip extends StatelessWidget {
  final String label, emoji;
  final bool on;
  final VoidCallback onTap;
  const CategoryChip(this.label, this.emoji, this.on, this.onTap);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: AppTheme.s2),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppTheme.sprout : AppTheme.glassFill,
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: on ? AppTheme.sprout : AppTheme.glassBorder),
            ),
            child: Text('$emoji  $label',
                style: AppTheme.subhead.copyWith(
                    color: on ? AppTheme.onAccent : AppTheme.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );
}

class ResilienceCard extends StatelessWidget {
  final int score;
  const ResilienceCard({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? AppTheme.ok
        : score >= 60
            ? AppTheme.warn
            : AppTheme.danger;
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Row(children: [
        RingGauge(
          value: score / 100,
          size: 62,
          color: color,
          center: Text('$score', style: AppTheme.headline),
        ),
        const SizedBox(width: AppTheme.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Household readiness 🛡️', style: AppTheme.headline),
            Text(
                score >= 80
                    ? 'Well stocked for an outage. Water and essentials are covered.'
                    : 'Add water and essentials so you are ready if supply fails.',
                style: AppTheme.caption),
          ]),
        ),
      ]),
    );
  }
}

class SavedCard extends StatelessWidget {
  final double saved;
  const SavedCard({required this.saved});

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('💰 Saved', style: AppTheme.caption),
          const SizedBox(height: 2),
          CountUp(saved,
              style: AppTheme.title2.copyWith(color: AppTheme.sprout)),
          Text('group buys + rescue', style: AppTheme.caption),
        ]),
      );
}

class ProductCard extends ConsumerWidget {
  final Product product;
  const ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    final p = product;
    final qty = s.cart[p.id] ?? 0;
    final joined = s.joined.contains(p.id);

    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(children: [
        Row(children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.glassFillStrong,
              borderRadius: BorderRadius.circular(AppTheme.rControl),
            ),
            child: Text(p.emoji, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(width: AppTheme.s4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: AppTheme.headline),
              const SizedBox(height: 2),
              Text(p.km > 0 ? '${p.farm}  •  ${p.km.toStringAsFixed(1)} km' : p.farm,
                  style: AppTheme.footnote),
              const SizedBox(height: AppTheme.s2),
              Row(children: [
                Text(rand(p.price), style: AppTheme.title3.copyWith(color: AppTheme.sprout)),
                if (p.wasPrice != null) ...[
                  const SizedBox(width: 6),
                  Text(rand(p.wasPrice!),
                      style: AppTheme.footnote.copyWith(
                          decoration: TextDecoration.lineThrough)),
                ],
                const SizedBox(width: 6),
                Text('/ ${p.unit}', style: AppTheme.caption),
                const Spacer(),
                if (p.rescue) Pill('♻️ Rescue', color: AppTheme.warn),
                if (p.stock != null && p.stock! <= 5 && !p.soldOut) ...[
                  const SizedBox(width: 6),
                  Pill('Only ${p.stock} left', color: AppTheme.livestockAccent),
                ],
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: AppTheme.s3),
        Row(children: [
          if (p.groupTarget > 0)
            Expanded(
              child: GestureDetector(
                onTap: joined
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        store.joinGroup(p.id);
                      },
                child: Row(children: [
                  RingGauge(
                    value: p.groupJoined / p.groupTarget,
                    size: 34,
                    color: joined ? AppTheme.sprout : AppTheme.livestockAccent,
                    center: const Text('👥', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: AppTheme.s2),
                  Expanded(
                    child: Text(
                      joined
                          ? 'You joined. ${p.groupJoined}/${p.groupTarget} neighbours, delivery halved'
                          : 'Join group buy  ${p.groupJoined}/${p.groupTarget}',
                      style: AppTheme.caption.copyWith(
                          color: joined ? AppTheme.sprout : AppTheme.textSecondary),
                    ),
                  ),
                ]),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: AppTheme.s3),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: p.soldOut
                ? Pill('Sold out', color: AppTheme.danger)
                : qty == 0
                ? GestureDetector(
                    key: const ValueKey('add'),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      addToBasket(context, ref, p);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.sprout,
                        borderRadius: BorderRadius.circular(AppTheme.rControl),
                      ),
                      child: Row(children: [
                        Icon(Icons.add_rounded, size: 18, color: AppTheme.onAccent),
                        const SizedBox(width: 4),
                        Text('Add',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: AppTheme.onAccent)),
                      ]),
                    ),
                  )
                : _Stepper(
                    key: const ValueKey('step'),
                    qty: qty,
                    onMinus: () => store.remove(p.id),
                    onPlus: () => addToBasket(context, ref, p)),
          ),
        ]),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus, onPlus;
  const _Stepper({super.key, required this.qty, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.glassFillStrong,
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: AppTheme.sprout.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onMinus,
              icon: const Icon(Icons.remove_rounded, size: 18)),
          Text('$qty', style: AppTheme.headline),
          IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onPlus,
              icon: const Icon(Icons.add_rounded, size: 18)),
        ]),
      );
}

class CartBar extends StatelessWidget {
  final int count;
  final double total;
  const CartBar({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.translate(
          offset: Offset(0, 40 * (1 - v)), child: Opacity(opacity: v.clamp(0, 1), child: child)),
      child: GlassButton(
        label: '$count item${count == 1 ? '' : 's'}  •  ${rand(total)}  •  Checkout',
        icon: Icons.shopping_bag_rounded,
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const CheckoutScreen())),
      ),
    );
  }
}

class OrderTile extends StatelessWidget {
  final Order order;
  const OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final (label, color) = statusLabel(order);
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => TrackingScreen(orderId: order.id))),
      child: Row(children: [
        Text(order.lines.first.emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: AppTheme.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${order.id}  •  ${rand(order.total)}', style: AppTheme.headline),
            Text('${order.lines.length} item${order.lines.length == 1 ? '' : 's'} from ${order.pickup}${order.route == 'hub' ? ' via ${order.hub}' : ''}',
                style: AppTheme.footnote),
          ]),
        ),
        Pill(label, color: color),
        Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
      ]),
    );
  }
}

(String, Color) statusLabel(Order o) => o.disputed
    ? ('Case open', AppTheme.warn)
    : switch (o.status) {
      OrderStatus.newOrder => ('New', AppTheme.warn),
      OrderStatus.findingDriver => ('Finding driver', AppTheme.warn),
      OrderStatus.assigned => ('Driver on the way', AppTheme.sprout),
      OrderStatus.pickedUp => ('On its way', AppTheme.sprout),
      OrderStatus.delivered => (o.released ? 'Paid out' : 'Delivered', AppTheme.ok),
    };

// ------------------------------------------------------------ CHECKOUT

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  PayMethod _method = PayMethod.fnbPay;
  bool _paying = false;

  Future<void> _pay() async {
    setState(() => _paying = true);
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    final id = ref.read(marketProvider.notifier).place(_method);
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => TrackingScreen(orderId: id, fresh: true)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    final fee = s.deliveryFee;
    final total = s.cartTotal;
    final cashTooBig = _method == PayMethod.cash && total > 500;
    final commission = s.cartCommission;
    final ebucks = (s.cartSubtotal * 0.05).round();

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.s2, AppTheme.s2, AppTheme.s6, 0),
              child: Row(children: [
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20)),
                Text('Checkout', style: AppTheme.title1),
              ]),
            ),
            Expanded(
              child: s.cart.isEmpty
                  ? Center(
                      child: Text('Your basket is empty 🧺', style: AppTheme.callout))
                  : ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(AppTheme.s6),
                      children: [
                        if (s.cartFarm != null)
                          Reveal(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: AppTheme.s3),
                              child: GlassCard(
                                padding: const EdgeInsets.all(AppTheme.s4),
                                child: Row(children: [
                                  Text(s.cartSelfDelivery ? '🚜' : '🛵',
                                      style: const TextStyle(fontSize: 30)),
                                  const SizedBox(width: AppTheme.s3),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('From ${s.cartFarm}', style: AppTheme.headline),
                                          Text(
                                              s.deliveryPlan?.summary ??
                                                  (s.cartSelfDelivery
                                                      ? 'The farm brings it to you'
                                                      : 'A Nolifa Delivery neighbour brings it to you'),
                                              style: AppTheme.footnote),
                                          if (s.deliveryPlan != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: AppTheme.s2),
                                              child: Wrap(spacing: 6, runSpacing: 6, children: [
                                                Pill(s.deliveryPlan!.route.label, color: AppTheme.sprout),
                                                Pill('Arrives: ${s.deliveryPlan!.eta}', color: AppTheme.textSecondary),
                                                if (s.deliveryPlan!.saving >= 5 && !s.deliveryPlan!.estimated)
                                                  Pill('You save ${rand(s.deliveryPlan!.saving, decimals: 0)} on delivery', color: AppTheme.warn),
                                              ]),
                                            ),
                                        ]),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        for (final e in s.cart.entries.toList().asMap().entries)
                          Reveal(
                            index: e.key,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: AppTheme.s3),
                              child: GlassCard(
                                padding: const EdgeInsets.all(AppTheme.s4),
                                child: Row(children: [
                                  Text(store.product(e.value.key).emoji,
                                      style: const TextStyle(fontSize: 30)),
                                  const SizedBox(width: AppTheme.s3),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(store.product(e.value.key).name,
                                              style: AppTheme.headline),
                                          Text(
                                              '${rand(store.product(e.value.key).price)} each',
                                              style: AppTheme.footnote),
                                        ]),
                                  ),
                                  _Stepper(
                                      qty: e.value.value,
                                      onMinus: () => store.remove(e.value.key),
                                      onPlus: () => store.add(e.value.key)),
                                ]),
                              ),
                            ),
                          ),
                        const SectionTitle('💳', 'Pay with'),
                        for (final m in PayMethod.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppTheme.s2),
                            child: GlassCard(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.s4, vertical: AppTheme.s3),
                              tint: _method == m
                                  ? AppTheme.sprout.withValues(alpha: 0.16)
                                  : null,
                              onTap: () => setState(() => _method = m),
                              child: Row(children: [
                                Icon(m.icon,
                                    color: _method == m
                                        ? AppTheme.sprout
                                        : AppTheme.textSecondary),
                                const SizedBox(width: AppTheme.s3),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m.label, style: AppTheme.headline),
                                        Text(m.note, style: AppTheme.caption),
                                      ]),
                                ),
                                if (_method == m)
                                  Icon(Icons.check_circle_rounded,
                                      color: AppTheme.sprout),
                              ]),
                            ),
                          ),
                        const SizedBox(height: AppTheme.s3),
                        GlassCard(
                          tint: AppTheme.sprout.withValues(alpha: 0.10),
                          child: Row(children: [
                            const Text('🔒', style: TextStyle(fontSize: 26)),
                            const SizedBox(width: AppTheme.s3),
                            Expanded(
                              child: Text(
                                  'Your money is held safely by FNB until you confirm delivery. Farmers and drivers are paid only then.',
                                  style: AppTheme.footnote),
                            ),
                          ]),
                        ),
                        const SizedBox(height: AppTheme.s4),
                        if (cashTooBig)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppTheme.s3),
                            child: Pill('Cash on delivery is limited to R500. Pick another method.',
                                color: AppTheme.warn, icon: Icons.info_outline_rounded),
                          ),
                        GestureDetector(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const TrustCenterScreen())),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: AppTheme.s4),
                            child: Text('How buyer protection works →',
                                style: AppTheme.footnote.copyWith(
                                    color: AppTheme.sprout, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        _line('Items', rand(s.cartSubtotal, decimals: 2)),
                        _line(s.cartSelfDelivery ? 'Delivery by the farm' : 'Delivery by neighbour', rand(fee, decimals: 2),
                            note: fee < 25 ? 'group buy −50%' : null),
                        _line('Service fee (3%)', rand(s.serviceFee, decimals: 2)),
                        if (_method == PayMethod.ebucks || _method == PayMethod.fnbPay)
                          _line('You earn', '+$ebucks eBucks', good: true),
                        const Divider(height: AppTheme.s6),
                        _line('Total', rand(total, decimals: 2), big: true),
                        const SizedBox(height: AppTheme.s4),
                        MoneySplitCard(
                          farm: r2(s.cartSubtotal * (1 - commission) + (s.cartSelfDelivery ? fee : 0)),
                          driver: s.cartSelfDelivery ? 0 : r2(fee * Fees.driverShare),
                          platform: r2(s.serviceFee +
                              s.cartSubtotal * commission +
                              (s.cartSelfDelivery ? 0 : fee * (1 - Fees.driverShare))),
                          farmNote: 'Sale less ${(commission * 100).round()}% commission, paid after delivery',
                        ),
                      ],
                    ),
            ),
            if (s.cart.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTheme.s6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const PrototypeNotice('Prototype: the payment is simulated. No real money moves, but the escrow and PIN rules are real.'),
                  const SizedBox(height: AppTheme.s3),
                  GlassButton(
                    label: _paying ? 'Securing payment…' : 'Pay ${rand(total, decimals: 2)}',
                    icon: Icons.lock_rounded,
                    busy: _paying,
                    onPressed: cashTooBig ? null : _pay,
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _line(String a, String b, {bool big = false, bool good = false, String? note}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(a, style: big ? AppTheme.title3 : AppTheme.callout),
          if (note != null) ...[
            const SizedBox(width: 8),
            Pill(note, color: AppTheme.sprout),
          ],
          const Spacer(),
          Text(b,
              style: (big ? AppTheme.title3 : AppTheme.body)
                  .copyWith(color: good ? AppTheme.sprout : null)),
        ]),
      );
}

// ------------------------------------------------------------ TRACKING

class TrackingScreen extends ConsumerWidget {
  final String orderId;
  final bool fresh;
  const TrackingScreen({super.key, required this.orderId, this.fresh = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final o = s.orderById(orderId);
    if (o == null) return const Scaffold();
    final (label, color) = statusLabel(o);
    final steps = [
      ('Order placed', OrderStatus.findingDriver),
      ('Driver assigned', OrderStatus.assigned),
      ('Picked up at the farm', OrderStatus.pickedUp),
      ('Delivered', OrderStatus.delivered),
    ];
    final idx = OrderStatus.values.indexOf(o.status).clamp(1, 4) - 1;
    final ebucks = (o.subtotal * 0.05).round();

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppTheme.s2, AppTheme.s2, AppTheme.s2, AppTheme.s8),
            children: [
              Row(children: [
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20)),
                Expanded(child: Text(o.id, style: AppTheme.title1)),
                Pill(label, color: color),
                const SizedBox(width: AppTheme.s4),
              ]),
              Padding(
                padding: const EdgeInsets.all(AppTheme.s4),
                child: Column(children: [
                  Reveal(child: ref.watch(trackMapProvider)?.call(o) ?? _RouteMap(status: o.status)),
                  const SizedBox(height: AppTheme.s4),
                  Reveal(
                    index: 1,
                    child: GlassCard(
                      child: Row(children: [
                        const CircleAvatar(
                            radius: 24,
                            backgroundColor: Color(0x33FFFFFF),
                            child: Text('🛵', style: TextStyle(fontSize: 24))),
                        const SizedBox(width: AppTheme.s4),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.driver ?? 'Finding a neighbour…',
                                    style: AppTheme.headline),
                                Row(children: [
                                  Icon(Icons.verified_rounded,
                                      size: 14, color: AppTheme.sprout),
                                  const SizedBox(width: 4),
                                  Text(
                                      o.driver == null
                                          ? 'Nearest FNB-verified drivers notified'
                                          : 'FNB-verified  •  4.9 ★',
                                      style: AppTheme.caption),
                                ]),
                              ]),
                        ),
                        Icon(Icons.call_rounded, color: AppTheme.sprout),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppTheme.s4),
                  Reveal(
                    index: 2,
                    child: GlassCard(
                      child: Column(children: [
                        for (var i = 0; i < steps.length; i++)
                          _Step(
                              text: steps[i].$1,
                              done: i <= idx && o.status != OrderStatus.findingDriver || (i == 0),
                              active: i == idx,
                              last: i == steps.length - 1),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppTheme.s4),
                  Reveal(
                    index: 3,
                    child: GlassCard(
                      tint: AppTheme.sprout.withValues(alpha: 0.10),
                      child: Row(children: [
                        Text(o.released ? '✅' : '🔒', style: const TextStyle(fontSize: 26)),
                        const SizedBox(width: AppTheme.s3),
                        Expanded(
                          child: Text(
                              o.released
                                  ? (o.refund > 0
                                      ? 'Case resolved. ${rand(o.refund, decimals: 2)} refunded to you.'
                                      : 'Confirmed. ${rand(o.total, decimals: 2)} released to the farmer and driver. You earned $ebucks eBucks 🎉')
                                  : o.disputed
                                      ? '${rand(o.total, decimals: 2)} frozen in escrow while we review your case.'
                                      : '${rand(o.total, decimals: 2)} held in FNB escrow until you confirm delivery.',
                              style: AppTheme.footnote),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppTheme.s4),
                  if (o.customerIsMe) ...protectionCards(context, ref, o),
                  for (final l in o.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Text('${l.emoji}  ${l.qty} × ${l.name}', style: AppTheme.callout),
                        const Spacer(),
                        Text(rand(l.total), style: AppTheme.callout),
                      ]),
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String text;
  final bool done, active, last;
  const _Step({required this.text, required this.done, required this.active, required this.last});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppTheme.sprout : Colors.transparent,
                border: Border.all(
                    color: done ? AppTheme.sprout : AppTheme.glassBorder, width: 2),
              ),
              child: done
                  ? Icon(Icons.check_rounded, size: 14, color: AppTheme.onAccent)
                  : null,
            ),
            if (!last)
              Expanded(
                  child: Container(
                      width: 2,
                      color: done ? AppTheme.sprout : AppTheme.glassBorder)),
          ]),
          const SizedBox(width: AppTheme.s3),
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.s4),
            child: Text(text,
                style: AppTheme.body.copyWith(
                    color: done ? AppTheme.textPrimary : AppTheme.textTertiary,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
          ),
        ]),
      );
}

class _RouteMap extends StatelessWidget {
  final OrderStatus status;
  const _RouteMap({required this.status});

  @override
  Widget build(BuildContext context) {
    final target = switch (status) {
      OrderStatus.newOrder || OrderStatus.findingDriver => 0.0,
      OrderStatus.assigned => 0.32,
      OrderStatus.pickedUp => 0.96,
      OrderStatus.delivered => 1.0,
    };
    final secs = switch (status) {
      OrderStatus.assigned => 4,
      OrderStatus.pickedUp => 8,
      _ => 1,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rCard),
      child: Container(
        height: 230,
        decoration: BoxDecoration(
          color: AppTheme.isLight ? const Color(0xFFE6EFEA) : const Color(0xFF0E2A20),
          border: Border.all(color: AppTheme.glassBorder),
          borderRadius: BorderRadius.circular(AppTheme.rCard),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target),
          duration: Duration(seconds: secs),
          curve: Curves.easeInOut,
          builder: (_, v, __) =>
              CustomPaint(painter: _MapPainter(v, searching: status == OrderStatus.findingDriver), size: Size.infinite),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final double t;
  final bool searching;
  _MapPainter(this.t, {required this.searching});

  Path _route(Size s) => Path()
    ..moveTo(s.width * 0.08, s.height * 0.88)
    ..cubicTo(s.width * 0.3, s.height * 0.95, s.width * 0.28, s.height * 0.35,
        s.width * 0.5, s.height * 0.45)
    ..cubicTo(s.width * 0.72, s.height * 0.55, s.width * 0.68, s.height * 0.1,
        s.width * 0.9, s.height * 0.18);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppTheme.textPrimary.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = _route(size);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = AppTheme.textPrimary.withValues(alpha: 0.10));
    final metrics = path.computeMetrics().toList();
    final PathMetric m = metrics.first;
    canvas.drawPath(
        m.extractPath(0, m.length * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = AppTheme.sprout);

    void emoji(String e, Offset p, double sz) {
      final tp = TextPainter(
          text: TextSpan(text: e, style: TextStyle(fontSize: sz)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    final farm = m.getTangentForOffset(m.length * 0.32)!.position;
    final home = m.getTangentForOffset(m.length)!.position;
    emoji('🌾', farm, 28);
    emoji('🏠', home, 28);
    final d = m.getTangentForOffset(m.length * t)!.position;
    if (searching) {
      canvas.drawCircle(d, 26,
          Paint()..color = AppTheme.warn.withValues(alpha: 0.22));
    }
    canvas.drawCircle(d, 20, Paint()..color = AppTheme.sprout.withValues(alpha: 0.25));
    emoji('🛵', d, 26);
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.t != t || old.searching != searching;
}


// ------------------------------------------------------ BUYER PROTECTION

/// Everything that keeps a buyer safe on one order: the PIN, proof of pickup,
/// the confirm-or-report window, the dispute timeline and the receipt.
List<Widget> protectionCards(BuildContext context, WidgetRef ref, Order o) {
  final store = ref.read(marketProvider.notifier);
  final live = o.status == OrderStatus.assigned || o.status == OrderStatus.pickedUp;
  return [
    if (live && !o.released && o.dispute == null && o.pin != null)
      Reveal(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.s4),
          child: GlassCard(
            tint: AppTheme.livestockAccent.withValues(alpha: 0.12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🔑 Your delivery PIN', style: AppTheme.headline),
              const SizedBox(height: AppTheme.s3),
              Row(children: [
                for (final d in o.pin!.split(''))
                  Container(
                    width: 48,
                    height: 56,
                    margin: const EdgeInsets.only(right: AppTheme.s2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.glassFillStrong,
                      borderRadius: BorderRadius.circular(AppTheme.rControl),
                      border: Border.all(color: AppTheme.livestockAccent.withValues(alpha: 0.5)),
                    ),
                    child: Text(d, style: AppTheme.title1),
                  ),
              ]),
              const SizedBox(height: AppTheme.s3),
              Text('Only give this to the driver once you are holding your items. The order cannot complete without it.',
                  style: AppTheme.footnote),
            ]),
          ),
        ),
      ),
    Reveal(
      index: 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.s4),
        child: Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
          Pill(o.pickupProof ? '📸 Pickup photo taken' : '📸 Pickup photo pending',
              color: o.pickupProof ? AppTheme.sprout : AppTheme.textTertiary),
          Pill('📍 GPS trail recorded', color: AppTheme.sprout),
          Pill(o.status == OrderStatus.delivered ? '🔑 PIN used' : '🔑 PIN pending',
              color: o.status == OrderStatus.delivered ? AppTheme.sprout : AppTheme.textTertiary),
        ]),
      ),
    ),
    if (o.status == OrderStatus.delivered && !o.released && o.dispute == null)
      Reveal(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.s4),
          child: _ConfirmCard(order: o),
        ),
      ),
    if (store.canDispute(o) && o.status == OrderStatus.pickedUp)
      Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.s4),
        child: GhostButton(
          label: 'Report a problem',
          icon: Icons.flag_rounded,
          onPressed: () => showDisputeSheet(context, o),
        ),
      ),
    if (o.dispute != null)
      Reveal(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.s4),
          child: DisputeTimeline(dispute: o.dispute!),
        ),
      ),
    if (!o.disputed)
      Reveal(
        index: 2,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.s4),
          child: MoneySplitCard(
            title: o.released ? 'Receipt' : 'Where your money goes',
            farm: r2(o.farmNet + o.selfDeliveryPay),
            driver: o.driverPay,
            platform: o.platformTake,
            refund: o.refund,
            farmNote: 'Sale less ${(o.commission * 100).round()}% commission',
          ),
        ),
      ),
  ];
}

class _ConfirmCard extends ConsumerStatefulWidget {
  final Order order;
  const _ConfirmCard({required this.order});

  @override
  ConsumerState<_ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends ConsumerState<_ConfirmCard> {
  int _stars = 5;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: AppTheme.sprout.withValues(alpha: 0.12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📦 Did everything arrive OK?', style: AppTheme.headline),
        const SizedBox(height: 4),
        Text('Confirm to pay the farmer and driver now. Do nothing and they are paid automatically after 2 hours (12 seconds in this demo).',
            style: AppTheme.footnote),
        const SizedBox(height: AppTheme.s3),
        Row(children: [
          for (var i = 1; i <= 5; i++)
            GestureDetector(
              onTap: () => setState(() => _stars = i),
              child: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 34, color: AppTheme.livestockAccent),
            ),
        ]),
        const SizedBox(height: AppTheme.s3),
        GlassButton(
          label: 'Confirm and pay out',
          icon: Icons.check_circle_rounded,
          onPressed: () {
            HapticFeedback.mediumImpact();
            ref.read(marketProvider.notifier).confirmReceived(widget.order.id, _stars);
          },
        ),
        const SizedBox(height: AppTheme.s2),
        GhostButton(
          label: 'Report a problem',
          icon: Icons.flag_rounded,
          onPressed: () => showDisputeSheet(context, widget.order),
        ),
      ]),
    );
  }
}
