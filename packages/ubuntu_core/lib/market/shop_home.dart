import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../water/water_store.dart';
import 'alert_actions.dart';
import 'farm_art.dart';
import 'farm_models.dart';
import 'farm_screen.dart';
import 'farm_widgets.dart';
import 'market_models.dart';
import 'market_store.dart';
import 'market_widgets.dart';
import 'shop_screens.dart';

import '../tr_text.dart' show Text;
/// Nolifa Drop's front door, laid out like a food app: where you are, a search,
/// a few promotions, then farms (the "restaurants") with their offerings.
class ShopHomePage extends ConsumerStatefulWidget {
  /// Opens the menu (orders, wallet, settings, help). Hidden when null.
  final VoidCallback? onMenu;
  final VoidCallback? onClose;
  const ShopHomePage({super.key, this.onMenu, this.onClose});

  @override
  ConsumerState<ShopHomePage> createState() => _ShopHomePageState();
}

class _ShopHomePageState extends ConsumerState<ShopHomePage> {
  final _search = TextEditingController();
  Category? _cat;
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(marketProvider);
    final farms = groupFarms(s.products, query: _q, category: _cat);
    final active = s.myOrders.where((o) => o.status != OrderStatus.delivered).toList();
    final alerts = ref.watch(allAlertsProvider);
    final address = s.profile.address.isEmpty
        ? 'Set your address'
        : [s.profile.address, if (s.profile.suburb.isNotEmpty) s.profile.suburb].join(', ');

    return Stack(children: [
      CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s2, AppTheme.s4, 0),
              child: Row(children: [
                if (widget.onMenu != null)
                  _RoundIcon(Icons.menu_rounded, 'Menu', widget.onMenu!),
                const SizedBox(width: AppTheme.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Deliver to', style: AppTheme.caption),
                    Text(address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.headline),
                  ]),
                ),
                const CartButton(),
                if (widget.onClose != null)
                  IconButton(
                      icon: const Icon(Icons.close_rounded), onPressed: widget.onClose),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s4, AppTheme.s6, 0),
              child: GlassField(
                controller: _search,
                label: 'Search farms, veg, eggs, water',
                icon: Icons.search_rounded,
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppTheme.s4),
              child: SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.s6),
                  children: [
                    CategoryChip('All', '✨', _cat == null, () => setState(() => _cat = null)),
                    for (final c in Category.values)
                      CategoryChip(c.label, c.emoji, _cat == c, () => setState(() => _cat = c)),
                  ],
                ),
              ),
            ),
          ),
          if (_q.isEmpty && _cat == null) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: AppTheme.s4),
                child: _Promos(farms: groupFarms(s.products)),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s4, AppTheme.s6, 0),
                child: ResilienceCard(score: s.resilience),
              ),
            ),
            if (alerts.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s4, AppTheme.s6, 0),
                  child: AlertBanner(
                    alert: alerts.first,
                    onTap: () => handleAlert(context, ref, alerts.first),
                  ),
                ),
              ),
            if (active.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, 0),
                  child: Column(children: [
                    const Align(alignment: Alignment.centerLeft, child: SectionTitle('📦', 'On its way')),
                    for (final o in active.take(2))
                      Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.s2),
                          child: OrderTile(order: o)),
                  ]),
                ),
              ),
          ],
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.s6),
            sliver: SliverToBoxAdapter(
              child: SectionTitle(
                  '🌾', _q.isEmpty && _cat == null ? 'Farms near you' : '${farms.length} found'),
            ),
          ),
          if (farms.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.s8),
                child: Center(
                    child: Text('No farms match. Try another word.', style: AppTheme.callout)),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  AppTheme.s6, 0, AppTheme.s6, s.cartCount > 0 ? 160 : 120),
              sliver: SliverList.builder(
                itemCount: farms.length,
                itemBuilder: (_, i) => Reveal(
                  key: ValueKey(farms[i].id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s4),
                    child: FarmCard(farm: farms[i]),
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
          bottom: 92,
          child: CartBar(count: s.cartCount, total: s.cartSubtotal),
        ),
    ]);
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _RoundIcon(this.icon, this.tip, this.onTap);

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tip,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.glassFillStrong,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Icon(icon, size: 22, color: AppTheme.textPrimary),
          ),
        ),
      );
}

/// The carousel: "Fresh near you" first, then rescue deals and outage kit.
class _Promos extends StatefulWidget {
  final List<Farm> farms;
  const _Promos({required this.farms});

  @override
  State<_Promos> createState() => _PromosState();
}

class _PromosState extends State<_Promos> {
  final _c = PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final farms = widget.farms;
    if (farms.isEmpty) return const SizedBox.shrink();
    final nearest = farms.first;
    final rescue = farms.where((f) => f.hasRescue).firstOrNull;
    final outage = farms.where((f) => f.products.any((p) => p.category == Category.water)).firstOrNull;
    final slides = <_Slide>[
      _Slide('🌿', 'Fresh near you', '${nearest.name} is ${nearest.km.toStringAsFixed(1)} km away',
          farmColors(nearest.name), nearest, [for (final f in farms.take(4)) ...f.products.take(2).map((p) => p.emoji)], 'fresh'),
      if (rescue != null)
        _Slide('♻️', 'Rescue deals', 'Good food at up to half price, from ${rescue.name}',
            const [Color(0xFF8A5A2B), Color(0xFF2B1D10)], rescue, ['♻️', ...rescue.products.where((p) => p.rescue).map((p) => p.emoji), '🏷️'], 'rescue'),
      if (outage != null)
        _Slide('💧', 'Ready for outages', 'Water, gas and power from ${outage.name}',
            const [Color(0xFF2E6F8E), Color(0xFF10293A)], outage, const ['💧', '🕯️', '🔋', '🔥', '🚰'], 'outage'),
    ];
    return Column(children: [
      SizedBox(
        height: 150,
        child: PageView.builder(
          controller: _c,
          physics: const BouncingScrollPhysics(),
          itemCount: slides.length,
          onPageChanged: (n) => setState(() => _page = n),
          itemBuilder: (_, i) => AnimatedBuilder(
            animation: _c,
            builder: (_, child) {
              final p = _c.hasClients && _c.position.haveDimensions ? (_c.page ?? 0) : 0.0;
              final d = (p - i).abs().clamp(0.0, 1.0);
              return Transform.scale(scale: 1 - 0.05 * d, child: child);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: slides[i].build(context),
            ),
          ),
        ),
      ),
      const SizedBox(height: AppTheme.s2),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < slides.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _page ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _page ? AppTheme.sprout : AppTheme.glassBorder,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]),
    ]);
  }
}

class _Slide {
  final String emoji, title, line;
  final List<Color> colors;
  final Farm farm;
  final List<String> pattern;
  final String photo;
  const _Slide(this.emoji, this.title, this.line, this.colors, this.farm, this.pattern, this.photo);

  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => FarmScreen(farmId: farm.id))),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rCard),
            gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Stack(children: [
            // A seller with its own photo shows it, not a stock vegetable picture.
            Positioned.fill(
              child: Image(
                image: farm.brand != null && farmBanner(farm.name) != null ? farmBanner(farm.name)! : promoPhoto(photo),
                fit: BoxFit.cover,
                alignment: const Alignment(0.35, -0.2),
              ),
            ),
            const Positioned.fill(child: PhotoScrim()),
            Padding(
              padding: const EdgeInsets.all(AppTheme.s4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppTheme.title2.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                SizedBox(width: 190, child: Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.footnote.copyWith(color: Colors.white70))),
                const Spacer(),
                const Pill('Order now', color: Colors.white, icon: Icons.arrow_forward_rounded),
              ]),
            ),
          ]),
        ),
      );
}
