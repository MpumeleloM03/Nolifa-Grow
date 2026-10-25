import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        FarmerWarehouseScreen,
        LotStatus,
        Pill,
        Product,
        Reveal,
        SectionTitle,
        StockLot,
        StorageZone,
        SupabaseBoot,
        marketProvider,
        resilientRows,
        warehouseProvider;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'stock_card.dart' show lowStockAt;
import 'store_common.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;

/// How cold or warm one warehouse room is right now, from the server. A farmer
/// only gets the rooms where their own stock is kept.
class RoomClimate {
  final String hub;
  final String zone;
  final double c;
  final bool ok;
  final DateTime at;
  const RoomClimate(this.hub, this.zone, this.c, this.ok, this.at);

  factory RoomClimate.fromRow(Map<String, dynamic> r) => RoomClimate(
        r['hub'] as String,
        r['zone'] as String,
        (r['c'] as num).toDouble(),
        r['ok'] as bool,
        DateTime.fromMillisecondsSinceEpoch((r['at'] as num).toInt()),
      );
}

/// Live room temperatures. Saved for offline, so the last known reading shows
/// with its time when there is no signal.
final roomClimateProvider = StreamProvider<List<RoomClimate>>((ref) {
  if (!SupabaseBoot.ready) return Stream.value(const []);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('room_climate').stream(primaryKey: ['hub', 'zone']),
    fetch: () async => [for (final r in await db.from('room_climate').select()) Map<String, dynamic>.from(r)],
    cacheKey: '${db.auth.currentUser?.id ?? 'anon'}:room_climate',
  ).map((rows) => [for (final r in rows) RoomClimate.fromRow(r)]);
});

String _key(String name) => name.trim().toLowerCase();

String _ago(DateTime t) {
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  if (m < 24 * 60) return '${m ~/ 60} h ago';
  return '${m ~/ (24 * 60)} d ago';
}

/// The seller's stock in one place: what the shop shows buyers, what the
/// warehouse holds, and how cold the room is. It updates by itself as buyers
/// order, as the warehouse checks goods in and as the room temperature moves.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  Future<void> _setAmount(BuildContext context, WidgetRef ref, Product p) async {
    final n = await askNumber(
      context,
      title: 'How many ${p.name} do you have?',
      subtitle: 'This is what buyers in the shop see.',
      label: 'Units in stock',
      icon: Icons.inventory_2_rounded,
      initial: '${p.stock ?? ''}',
      allowZero: true,
    );
    if (n == null) return;
    ref.read(marketProvider.notifier).updateProduct(p.id, stock: n.round());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = [for (final p in ref.watch(marketProvider).products) if (p.mine) p];
    final wh = ref.watch(warehouseProvider);
    final climate = ref.watch(roomClimateProvider).valueOrNull ?? const <RoomClimate>[];
    final lots = [for (final l in wh.lots) if (l.status == LotStatus.stored && l.remaining > 0) l];
    final byProduct = <String, List<StockLot>>{};
    for (final l in lots) {
      byProduct.putIfAbsent(_key(l.productName), () => []).add(l);
    }
    final zones = {for (final l in lots) l.zone};
    final rooms = [for (final z in StorageZone.values) if (zones.contains(z)) z];
    RoomClimate? roomFor(StorageZone z) => climate.where((c) => c.zone == z.name).firstOrNull;
    final alarms = [for (final z in rooms) if (roomFor(z) != null && !roomFor(z)!.ok) z];
    final low = products.where((p) => p.stock != null && p.stock! <= lowStockAt).length;
    final kg = lots.fold<double>(0, (a, l) => a + l.remaining);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory'), backgroundColor: Colors.transparent),
      body: AppBackdrop(
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
            children: [
              Reveal(
                child: GlassCard(
                  tint: (alarms.isEmpty ? AppTheme.sprout : AppTheme.danger).withValues(alpha: 0.12),
                  child: Row(children: [
                    Expanded(child: _Stat('${products.length}', 'items in the shop', AppTheme.textPrimary)),
                    Expanded(child: _Stat('${kg.round()} kg', 'in the warehouse', AppTheme.sprout)),
                    Expanded(child: _Stat('$low', 'running low', low > 0 ? AppTheme.warn : AppTheme.textSecondary)),
                  ]),
                ),
              ),
              if (rooms.isNotEmpty) ...[
                const SectionTitle('🌡️', 'Your rooms'),
                if (alarms.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s3),
                    child: GlassCard(
                      tint: AppTheme.danger.withValues(alpha: 0.12),
                      child: Text('${alarms.map((z) => z.label).join(' and ')} ${alarms.length == 1 ? 'is' : 'are'} out of range. Warehouse staff have been told.',
                          style: AppTheme.callout.copyWith(color: AppTheme.danger, fontWeight: FontWeight.w700)),
                    ),
                  ),
                SizedBox(
                  height: 112,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: [for (final z in rooms) _RoomCard(z, roomFor(z))],
                  ),
                ),
              ],
              SectionTitle('📦', 'Stock', trailing: Pill('${products.length} listed', color: AppTheme.sprout)),
              if (products.isEmpty)
                GlassCard(child: Text('Add stock on the Sell tab and it shows up here.', style: AppTheme.callout)),
              for (var i = 0; i < products.length; i++)
                Reveal(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s3),
                    child: _ItemCard(
                      product: products[i],
                      lots: byProduct[_key(products[i].name)] ?? const [],
                      room: (byProduct[_key(products[i].name)]?.isEmpty ?? true) ? null : roomFor(byProduct[_key(products[i].name)]!.first.zone),
                      onSet: () => _setAmount(context, ref, products[i]),
                    ),
                  ),
                ),
              const SizedBox(height: AppTheme.s2),
              GhostButton(
                label: 'Warehouse: deposits and stock',
                icon: Icons.warehouse_rounded,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FarmerWarehouseScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _Stat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: AppTheme.title2.copyWith(color: color)),
        Text(label, style: AppTheme.caption, textAlign: TextAlign.center),
      ]);
}

class _RoomCard extends StatelessWidget {
  final StorageZone zone;
  final RoomClimate? now;
  const _RoomCard(this.zone, this.now);

  @override
  Widget build(BuildContext context) {
    final ok = now?.ok ?? true;
    final color = now == null ? AppTheme.textSecondary : (ok ? AppTheme.sprout : AppTheme.danger);
    return Container(
      width: 168,
      margin: const EdgeInsets.only(right: AppTheme.s3),
      child: GlassCard(
        tint: color.withValues(alpha: 0.10),
        padding: const EdgeInsets.all(AppTheme.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(zone.label, style: AppTheme.caption),
          Text(now == null ? 'No reading' : '${now!.c.toStringAsFixed(1)} °C', style: AppTheme.title2.copyWith(color: color)),
          Text(now == null ? 'Should be ${zone.band}' : '${ok ? 'In range' : 'Out of range'}  •  ${zone.band}', style: AppTheme.caption),
          if (now != null) Text(_ago(now!.at), style: AppTheme.caption),
        ]),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Product product;
  final List<StockLot> lots;
  final RoomClimate? room;
  final VoidCallback onSet;
  const _ItemCard({required this.product, required this.lots, required this.room, required this.onSet});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final shop = p.stock;
    final inWh = lots.fold<double>(0, (a, l) => a + l.remaining);
    final next = lots.isEmpty ? null : (lots.map((l) => l.useBy).toList()..sort()).first;
    final days = next == null ? null : DateTime(next.year, next.month, next.day).difference(DateTime.now()).inDays;
    final lowShop = shop != null && shop <= lowStockAt;
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      onTap: onSet,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Glyph(p.emoji, size: 26),
          const SizedBox(width: AppTheme.s3),
          Expanded(child: Text(p.name, style: AppTheme.headline)),
          if (lowShop) Pill(p.soldOut ? 'Sold out' : 'Only $shop left', color: p.soldOut ? AppTheme.danger : AppTheme.warn),
        ]),
        const SizedBox(height: AppTheme.s3),
        Row(children: [
          Expanded(child: _Cell('In the shop', shop == null ? 'No limit' : '$shop ${p.unit}', lowShop ? AppTheme.warn : AppTheme.textPrimary)),
          Expanded(child: _Cell('In the warehouse', lots.isEmpty ? 'None' : '${inWh.round()} ${p.unit}', lots.isEmpty ? AppTheme.textSecondary : AppTheme.sprout)),
          Expanded(
            child: _Cell(
                'Room',
                lots.isEmpty ? 'None' : (room == null ? lots.first.zone.label : '${room!.c.toStringAsFixed(1)} °C'),
                room == null ? AppTheme.textSecondary : (room!.ok ? AppTheme.sprout : AppTheme.danger)),
          ),
        ]),
        if (days != null) ...[
          const SizedBox(height: AppTheme.s2),
          Text(days < 0 ? 'Past its use-by date' : days == 0 ? 'Use by today' : 'Use by in $days ${days == 1 ? 'day' : 'days'}',
              style: AppTheme.caption.copyWith(color: days <= 2 ? AppTheme.warn : AppTheme.textSecondary)),
        ],
        const SizedBox(height: AppTheme.s2),
        Text('Tap to change the shop count', style: AppTheme.caption),
      ]),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Cell(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTheme.caption),
        Text(value, style: AppTheme.subhead.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]);
}
