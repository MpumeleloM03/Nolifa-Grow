import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'farm_art.dart';
import 'farm_brand.dart';
import 'farm_models.dart';
import 'farm_screen.dart';
import 'market_models.dart';
import 'market_store.dart';
import 'market_widgets.dart';
import 'shop_screens.dart';

import '../tr_text.dart' show Text;
/// The shopping bag with a count. Opens the basket.
class CartButton extends ConsumerWidget {
  const CartButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(marketProvider.select((s) => s.cartCount));
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.glassFillStrong,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          Icon(Icons.shopping_bag_rounded, size: 22, color: AppTheme.textPrimary),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(count),
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppTheme.sprout, borderRadius: BorderRadius.circular(9)),
                  child: Text('$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.onAccent)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

const _heroColors = <List<Color>>[
  [Color(0xFF2D6A4F), Color(0xFF14352A)],
  [Color(0xFF8A5A2B), Color(0xFF2B1D10)],
  [Color(0xFF2E6F8E), Color(0xFF10293A)],
  [Color(0xFF7A3E5C), Color(0xFF2B1220)],
  [Color(0xFF6B7F2A), Color(0xFF1F2810)],
  [Color(0xFF8E3B2E), Color(0xFF2B1410)],
];

List<Color> farmColors(String name) {
  final brand = farmBrands[name]?.color;
  if (brand != null) return [brand, Color.lerp(brand, Colors.black, 0.82)!];
  return _heroColors[name.codeUnits.fold<int>(0, (a, b) => a + b) % _heroColors.length];
}

/// A farm the way a food app shows a restaurant: a picture-style banner, the
/// name in bold, how far and how fast, how it delivers, then what it sells.
class FarmCard extends ConsumerWidget {
  final Farm farm;
  const FarmCard({super.key, required this.farm});

  void _open(BuildContext context) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => FarmScreen(farmId: farm.id)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(farmBrandProvider);
    final colors = farmColors(farm.name);
    final self = farm.delivery == DeliveryMode.self;
    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: () => _open(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Banner
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
          child: Container(
            height: 124,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
            ),
            child: Stack(children: [
              if (farmBanner(farm.name) != null) ...[
                Positioned.fill(child: Image(image: farmBanner(farm.name)!, fit: BoxFit.cover)),
                const Positioned.fill(child: PhotoScrim()),
              ] else ...[
                Positioned.fill(
                  child: EmojiPattern([for (final p in farm.products) p.emoji], size: 34, opacity: 0.30),
                ),
                Positioned(
                  right: -8,
                  bottom: -14,
                  child: Row(children: [
                    for (final p in farm.products.take(3).toList().reversed)
                      Transform.translate(
                        offset: const Offset(-18, 0),
                        child: Glyph(p.emoji, size: 64),
                      ),
                  ]),
                ),
              ],
              Positioned(
                left: AppTheme.s4,
                bottom: AppTheme.s3,
                child: FarmLogo(
                    name: farm.name,
                    emoji: farm.products.first.emoji,
                    size: 58),
              ),
              Positioned(
                left: AppTheme.s4,
                top: AppTheme.s3,
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  Pill(self ? 'Farm delivers' : 'Nolifa Delivery',
                      color: self ? AppTheme.livestockAccent : AppTheme.sprout),
                  if (farm.hasRescue) Pill('Rescue deals', color: AppTheme.warn),
                  if (farm.mine) const Pill('Your store', color: Colors.white),
                ]),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s3, AppTheme.s4, AppTheme.s2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(farm.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.title3.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (farm.verified)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.verified_rounded, size: 18, color: AppTheme.sprout),
                ),
              _Rating(farm),
            ]),
            const SizedBox(height: 2),
            Text(
                '${farm.km.toStringAsFixed(1)} km  •  ${farm.etaMinutes}-${farm.etaMinutes + 10} min  •  ${farm.deliveryLabel}',
                style: AppTheme.footnote),
            const SizedBox(height: 2),
            Text(farm.tagline, style: AppTheme.caption),
          ]),
        ),
        // What they sell
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s4),
            itemCount: farm.products.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppTheme.s2),
            itemBuilder: (_, i) => _Offer(farm.products[i]),
          ),
        ),
      ]),
    );
  }
}

class _Rating extends StatelessWidget {
  final Farm farm;
  const _Rating(this.farm);

  @override
  Widget build(BuildContext context) {
    final r = farm.rating;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.glassFillStrong,
        borderRadius: BorderRadius.circular(AppTheme.rChip),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(r == null ? Icons.fiber_new_rounded : Icons.star_rounded,
            size: 15, color: AppTheme.livestockAccent),
        const SizedBox(width: 3),
        Text(r == null ? 'New' : '${r.toStringAsFixed(1)} (${farm.reviews})',
            style: AppTheme.footnote.copyWith(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// One offering on a farm card: emoji, name, price, and a quick add.
class _Offer extends ConsumerWidget {
  final Product product;
  const _Offer(this.product);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product;
    final inBasket = ref.watch(marketProvider.select((s) => s.cart[p.id] ?? 0));
    return Container(
      width: 112,
      padding: const EdgeInsets.all(AppTheme.s2),
      decoration: BoxDecoration(
        color: AppTheme.glassFillStrong,
        borderRadius: BorderRadius.circular(AppTheme.rControl),
        border: Border.all(color: AppTheme.glassBorderSoft),
      ),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Glyph(p.emoji, size: 26),
          const SizedBox(height: 2),
          Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
          const Spacer(),
          Row(children: [
            Text(rand(p.price), style: AppTheme.headline.copyWith(color: AppTheme.sprout)),
            if (p.wasPrice != null) ...[
              const SizedBox(width: 4),
              Text(rand(p.wasPrice!),
                  style: AppTheme.caption.copyWith(decoration: TextDecoration.lineThrough)),
            ],
          ]),
        ]),
        Positioned(
          right: 0,
          top: 0,
          child: p.soldOut
              ? Pill('Sold out', color: AppTheme.danger)
              : GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    addToBasket(context, ref, p);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: AppTheme.sprout, borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: inBasket > 0
                        ? Text('$inBasket',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: AppTheme.onAccent))
                        : Icon(Icons.add_rounded, size: 18, color: AppTheme.onAccent),
                  ),
                ),
        ),
      ]),
    );
  }
}
