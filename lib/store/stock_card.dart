import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show Pill, Product, marketProvider;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'store_common.dart';

/// At or below this many units a listing is flagged as running low. Matches
/// the "Only N left" badge buyers see in the shop.
const lowStockAt = 5;

/// The badge for a listing. Sold out beats paused, which beats running low.
({String label, Color color, IconData icon}) stockBadge(Product p) {
  if (p.soldOut) {
    return (
      label: 'Sold out',
      color: AppTheme.danger,
      icon: Icons.remove_shopping_cart_rounded
    );
  }
  if (!p.available) {
    return (
      label: 'Paused',
      color: AppTheme.textSecondary,
      icon: Icons.pause_circle_rounded
    );
  }
  final left = p.stock;
  if (left != null && left <= lowStockAt) {
    return (
      label: 'Only $left left',
      color: AppTheme.warn,
      icon: Icons.warning_amber_rounded
    );
  }
  return (
    label: 'In stock',
    color: AppTheme.sprout,
    icon: Icons.check_circle_rounded
  );
}

/// One of the farmer's own listings, with the controls to restock it, change
/// its price, or pause selling without deleting it.
class StockCard extends ConsumerWidget {
  final Product product;
  const StockCard(this.product, {super.key});

  Future<void> _setAmount(BuildContext context, WidgetRef ref) async {
    final n = await askNumber(
      context,
      title: 'How many ${product.name} do you have?',
      subtitle: 'Sets the count to the number you type.',
      label: 'Units in stock',
      icon: Icons.inventory_2_rounded,
      initial: '${product.stock ?? ''}',
      allowZero: true,
    );
    if (n == null) return;
    ref
        .read(marketProvider.notifier)
        .updateProduct(product.id, stock: n.round());
  }

  Future<void> _setPrice(BuildContext context, WidgetRef ref) async {
    final n = await askNumber(
      context,
      title: 'New price for ${product.name}',
      subtitle: 'A lower price shows the old one crossed out.',
      label: 'Price in Rand (per ${product.unit})',
      icon: Icons.payments_rounded,
      initial: product.price == product.price.roundToDouble()
          ? '${product.price.round()}'
          : '${product.price}',
      decimal: true,
    );
    if (n == null) return;
    ref.read(marketProvider.notifier).updateProduct(product.id, price: n);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product;
    final store = ref.read(marketProvider.notifier);
    final badge = stockBadge(p);
    final left = p.stock;

    void restock(int by) {
      HapticFeedback.selectionClick();
      store.updateProduct(p.id,
          stock: ((left ?? 0) + by).clamp(0, maxStoreNumber));
    }

    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: AppTheme.headline),
              Text.rich(
                TextSpan(style: AppTheme.footnote, children: [
                  TextSpan(text: '${money(p.price)} per ${p.unit}'),
                  if (p.wasPrice != null)
                    TextSpan(
                      text: '  ${money(p.wasPrice!)}',
                      style: TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          const SizedBox(width: AppTheme.s2),
          Pill(badge.label, color: badge.color, icon: badge.icon),
        ]),
        const SizedBox(height: AppTheme.s3),
        Text(
          left == null ? 'Stock not counted yet' : '${groupDigits(left)} left',
          style: AppTheme.title3,
        ),
        const SizedBox(height: AppTheme.s3),
        Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
          ChoiceChipButton(label: '+10', onTap: () => restock(10)),
          ChoiceChipButton(label: '+50', onTap: () => restock(50)),
          ChoiceChipButton(
            label: 'Set amount',
            icon: Icons.edit_rounded,
            onTap: () => _setAmount(context, ref),
          ),
          ChoiceChipButton(
            label: 'Change price',
            icon: Icons.sell_rounded,
            onTap: () => _setPrice(context, ref),
          ),
        ]),
        const SizedBox(height: AppTheme.s2),
        Row(children: [
          Expanded(
            child: Text(
              !p.available
                  ? 'Paused, buyers cannot see it'
                  : p.soldOut
                      ? 'Out of stock. Restock to sell again'
                      : 'Selling now',
              style: AppTheme.subhead,
            ),
          ),
          Switch(
            value: p.available,
            activeThumbColor: AppTheme.sprout,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              store.updateProduct(p.id, available: v);
            },
          ),
        ]),
      ]),
    );
  }
}
