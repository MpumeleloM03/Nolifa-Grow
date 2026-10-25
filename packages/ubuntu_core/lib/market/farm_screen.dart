import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'farm_art.dart';
import 'farm_models.dart';
import 'farm_widgets.dart';
import 'market_models.dart';
import 'market_store.dart';
import 'market_widgets.dart';
import 'shop_screens.dart';

import '../tr_text.dart' show Text;
/// One farm's page: who they are, how they deliver, and everything they sell.
class FarmScreen extends ConsumerStatefulWidget {
  final String farmId;
  const FarmScreen({super.key, required this.farmId});

  @override
  ConsumerState<FarmScreen> createState() => _FarmScreenState();
}

class _FarmScreenState extends ConsumerState<FarmScreen> {
  Category? _cat;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(marketProvider);
    final farm = s.farms.where((f) => f.id == widget.farmId).firstOrNull;
    if (farm == null) {
      return Scaffold(
        body: AppBackdrop(
          child: SafeArea(
            child: Center(child: Text('This farm is not selling right now.', style: AppTheme.callout)),
          ),
        ),
      );
    }
    final cats = {for (final p in farm.products) p.category}.toList();
    final items = farm.products.where((p) => _cat == null || p.category == _cat).toList();
    final self = farm.delivery == DeliveryMode.self;

    return Scaffold(
      body: AppBackdrop(
        tint: farmColors(farm.name).first,
        child: Stack(children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverPersistentHeader(
                  pinned: true,
                  delegate: ParallaxHeader(
                    emoji: farm.emoji,
                    title: farm.name,
                    subtitle: farm.tagline,
                    accent: AppTheme.sprout,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      const CartButton(),
                      IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context)),
                    ]),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, 0),
                sliver: SliverList.list(children: [
                  // A farm with its own photo and logo gets them front and centre.
                  if (farmBanner(farm.name) != null) ...[
                    Reveal(child: _FarmHero(farm)),
                    const SizedBox(height: AppTheme.s4),
                  ],
                  Reveal(
                    child: GlassCard(
                      padding: const EdgeInsets.all(AppTheme.s4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
                          Pill(farm.rating == null
                              ? 'New on Nolifa Drop'
                              : '★ ${farm.rating!.toStringAsFixed(1)} (${farm.reviews})',
                              color: AppTheme.livestockAccent),
                          Pill('${farm.km.toStringAsFixed(1)} km', color: AppTheme.textSecondary),
                          Pill('${farm.etaMinutes}-${farm.etaMinutes + 10} min',
                              color: AppTheme.textSecondary),
                          if (farm.verified)
                            Pill('Verified', color: AppTheme.sprout, icon: Icons.verified_rounded),
                        ]),
                        const SizedBox(height: AppTheme.s3),
                        Row(children: [
                          Text(self ? '🚜' : '🛵', style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: AppTheme.s3),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(farm.deliveryLabel, style: AppTheme.headline),
                              Text(
                                  self
                                      ? '${farm.name} brings your order to your door. You still pay through escrow and confirm with your PIN.'
                                      : 'A verified neighbour collects it from the farm and brings it to you.',
                                  style: AppTheme.footnote),
                            ]),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                  if (cats.length > 1) ...[
                    const SizedBox(height: AppTheme.s4),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          CategoryChip('All', '✨', _cat == null, () => setState(() => _cat = null)),
                          for (final c in cats)
                            CategoryChip(c.label, c.emoji, _cat == c, () => setState(() => _cat = c)),
                        ],
                      ),
                    ),
                  ],
                  const SectionTitle('🧺', 'What they sell'),
                ]),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, 0, AppTheme.s6, 140),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => Reveal(
                    key: ValueKey(items[i].id),
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.s3),
                      child: ProductCard(product: items[i]),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (s.cartCount > 0)
            Positioned(
              left: AppTheme.s6,
              right: AppTheme.s6,
              bottom: AppTheme.s6,
              child: CartBar(count: s.cartCount, total: s.cartSubtotal),
            ),
        ]),
      ),
    );
  }
}

class _FarmHero extends StatelessWidget {
  final Farm farm;
  const _FarmHero(this.farm);

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        child: SizedBox(
          height: 210,
          child: Stack(children: [
            Positioned.fill(
              child: Image(image: farmBanner(farm.name)!, fit: BoxFit.cover, alignment: const Alignment(0.35, -0.3)),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xD9000000)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppTheme.s4,
              right: AppTheme.s4,
              bottom: AppTheme.s4,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                FarmLogo(name: farm.name, emoji: farm.emoji, size: 68),
                const SizedBox(width: AppTheme.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(farm.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.title2.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    if (farm.brand != null)
                      Text('${farm.brand!.place}, KwaZulu-Natal',
                          style: AppTheme.footnote.copyWith(color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      );
}
