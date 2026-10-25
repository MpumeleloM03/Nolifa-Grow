import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_models.dart';
import '../market/market_store.dart';
import '../market/market_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../warehouse/warehouse_screens.dart';
import '../warehouse/warehouse_store.dart';

import '../tr_text.dart' show Text;
import '../tr.dart' show tr, trn;
/// True when the signed-in person works at a hub (the `hub` permission). Apps
/// override this from the sign-in token. In demo mode the desk is open to
/// everyone so it can be shown.
final hubStaffProvider = Provider<bool>((ref) => false);

final canRunHubProvider =
    Provider<bool>((ref) => ref.watch(hubStaffProvider) || ref.watch(marketProvider.select((s) => s.demoMode)));

/// A card for the Jobs page that opens the hub desk.
class HubDeskCard extends ConsumerWidget {
  const HubDeskCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canRunHubProvider)) return const SizedBox.shrink();
    final n = ref.watch(marketProvider.select((s) => s.hubOrders.length));
    return GlassCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HubDeskScreen())),
      child: Row(children: [
        const Glyph('🏭', size: 28),
        const SizedBox(width: AppTheme.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hub desk', style: AppTheme.headline),
            Text(n == 0 ? 'Nothing at the hub' : '$n ${n == 1 ? 'order' : 'orders'} passing through', style: AppTheme.footnote),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
      ]),
    );
  }
}

/// Where hub staff check farm orders in, sort them and release them to the
/// last-mile drivers. An order only becomes a driver job once it is released.
class HubDeskScreen extends ConsumerWidget {
  const HubDeskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(marketProvider);
    final demo = s.demoMode;
    final list = s.hubOrders;
    final names = {for (final o in list) o.hub ?? 'Hub'}.toList()..sort();

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: const GlassBar(),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Hub desk'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverList.list(children: [
                  Text('Check in, sort, release', style: AppTheme.title1),
                  const SizedBox(height: AppTheme.s1),
                  Text(
                      'A farm drops its order here and shows the 4-digit code on the packing slip. Type it to check the order in. '
                      'Once it is sorted, release it and the nearest last-mile drivers can take it.',
                      style: AppTheme.callout),
                  if (demo)
                    Padding(
                      padding: const EdgeInsets.only(top: AppTheme.s3),
                      child: GlassCard(
                        tint: AppTheme.warn.withValues(alpha: 0.12),
                        child: Text(
                            'Demo: the farms and the hub are pretend and move orders along by themselves after a short wait. You can act first. The code is shown on each order so you can try it.',
                            style: AppTheme.footnote),
                      ),
                    ),
                  const SizedBox(height: AppTheme.s4),
                  GlassCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WarehouseDeskScreen())),
                    child: Row(children: [
                      const Glyph('🧊', size: 28),
                      const SizedBox(width: AppTheme.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Warehouse: receiving, stock, rooms', style: AppTheme.headline),
                          Text('Check farm deposits in, see tagged stock and the cold room temperatures.', style: AppTheme.footnote),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
                    ]),
                  ),
                  const SizedBox(height: AppTheme.s4),
                  if (list.isEmpty)
                    GlassCard(child: Text('No orders are passing through a hub right now.', style: AppTheme.callout))
                  else
                    for (final name in names) ...[
                      SectionTitle('🏭', name),
                      for (final o in list.where((o) => (o.hub ?? 'Hub') == name))
                        Padding(padding: const EdgeInsets.only(bottom: AppTheme.s3), child: _HubOrder(o, showCode: demo)),
                    ],
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubOrder extends ConsumerStatefulWidget {
  final Order o;
  final bool showCode;
  const _HubOrder(this.o, {required this.showCode});

  @override
  ConsumerState<_HubOrder> createState() => _HubOrderState();
}

class _HubOrderState extends ConsumerState<_HubOrder> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _receive() {
    final ok = ref.read(marketProvider.notifier).hubReceive(widget.o.id, _code.text);
    HapticFeedback.mediumImpact();
    setState(() => _error = ok ? null : 'That code does not match this order.');
  }

  @override
  Widget build(BuildContext context) {
    final o = ref.watch(marketProvider.select((s) => s.orderById(widget.o.id))) ?? widget.o;
    final store = ref.read(marketProvider.notifier);
    final items = o.lines.fold<int>(0, (a, l) => a + l.qty);
    final (stageText, color) = switch (o.hubStage) {
      'toHub' => ('On its way from the farm', AppTheme.textSecondary),
      'droppedOff' => ('Dropped off, waiting to be checked in', AppTheme.warn),
      'received' => (o.fromStock ? 'In storage, ready to pick' : 'Checked in, ready to sort', AppTheme.sprout),
      _ => ('', AppTheme.textSecondary),
    };
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${o.id}  -  $items ${items == 1 ? 'item' : 'items'}', style: AppTheme.headline),
        const SizedBox(height: 4),
        Pill(stageText, color: color),
        const SizedBox(height: 4),
        const SizedBox(height: 2),
        Text('${o.pickup}  →  ${o.dropArea}', style: AppTheme.footnote),
        if (widget.showCode) Text('Demo code: ${o.hubCode}', style: AppTheme.caption),
        if (o.hubStage == 'droppedOff') ...[
          const SizedBox(height: AppTheme.s3),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 4,
                style: AppTheme.body,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: tr('Code from the slip'),
                  hintStyle: AppTheme.subhead,
                  errorText: trn(_error),
                  filled: true,
                  fillColor: AppTheme.glassFill,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.rChip)),
                ),
                onSubmitted: (_) => _receive(),
              ),
            ),
            const SizedBox(width: AppTheme.s2),
            GlassButton(label: 'Check in', expand: false, icon: Icons.inventory_2_rounded, onPressed: _receive),
          ]),
        ],
        if (o.hubStage == 'received') ...[
          const SizedBox(height: AppTheme.s3),
          GlassButton(
            label: o.fromStock ? 'Pick from storage and release' : 'Release to drivers',
            icon: Icons.local_shipping_rounded,
            accent: AppTheme.livestockAccent,
            onPressed: () async {
              HapticFeedback.mediumImpact();
              if (o.fromStock) {
                final wh = ref.read(warehouseProvider.notifier);
                final picks = <String>[];
                for (final l in o.lines) {
                  final p = await wh.dispatch(o.pickup, l.name, l.qty.toDouble(), o.id);
                  if (p == null) {
                    setState(() => _error = 'Not enough ${l.name} in a room that is in range. Ask the farm to deposit more.');
                    return;
                  }
                  picks.addAll([for (final x in p) '${l.name}: ${x.qty.round()} from ${x.tag}']);
                }
                if (!context.mounted) return;
                setState(() => _error = null);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Picked  ${picks.join('  |  ')}')));
              }
              store.hubRelease(o.id);
            },
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger))),
        ],
      ]),
    );
  }
}
