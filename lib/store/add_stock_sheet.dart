import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        BusinessScreen,
        Category,
        CategoryX,
        Product,
        marketNameProvider,
        marketProvider,
        marketSharedProvider,
        r2;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'store_common.dart';

/// How much a rescue listing takes off the usual price.
const rescueDiscount = 0.25;

const _emojis = [
  '🥕',
  '🥬',
  '🍅',
  '🌽',
  '🍊',
  '🍌',
  '🥚',
  '🥛',
  '🫘',
  '🥔',
  '🍎',
  '🧅',
  '🥦',
  '🍯',
  '🥭',
  '🍉',
  '🥩',
  '🍗',
  '🌭'
];
const _units = ['kg', 'bunch', 'bag', 'pack', 'tray', 'dozen', 'litre', 'each'];

/// Opens the add-stock sheet, or sends a farmer who has not finished
/// registering, verifying and choosing a plan to the Business page first.
void startAddStock(BuildContext context, WidgetRef ref, {bool rescue = false}) {
  // Buyers only see farms that are registered, verified and on a plan.
  if (!ref.read(marketProvider).canSell) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const BusinessScreen()));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AddStockSheet(rescue: rescue),
  );
}

/// Form that puts new stock on the farmer's Nolifa Drop shelf.
class AddStockSheet extends ConsumerStatefulWidget {
  /// Starts with "Sell fast at a discount" on, for example after a frost alert.
  final bool rescue;
  const AddStockSheet({super.key, this.rescue = false});

  @override
  ConsumerState<AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends ConsumerState<AddStockSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController();
  String _emoji = _emojis.first;
  Category _cat = Category.veg;
  String _unit = 'kg';
  late bool _rescue = widget.rescue;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  static final _tooBig = 'Keep it under ${groupDigits(maxStoreNumber)}';

  String? _checkName(String? v) {
    final n = (v ?? '').trim();
    if (n.isEmpty) return 'Give it a name, like Carrots 5kg';
    return n.length > maxProductName
        ? 'Keep the name under $maxProductName letters'
        : null;
  }

  String? _checkPrice(String? v) {
    final n = parseNumber(v ?? '');
    if (n == null || n <= 0) return 'Enter a price in Rand';
    return n > maxStoreNumber ? _tooBig : null;
  }

  String? _checkQty(String? v) {
    final n = parseNumber(v ?? '');
    if (n == null || n < 1 || n != n.roundToDouble()) {
      return 'Enter how many you have';
    }
    return n > maxStoreNumber ? _tooBig : null;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final usual = parseNumber(_price.text)!;
    final qty = parseNumber(_qty.text)!.round();
    final listed = _rescue ? r2(usual * (1 - rescueDiscount)) : usual;
    final name = _name.text.trim();
    final block = ref.read(marketProvider.notifier).list(Product(
          id: 'mine-${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          emoji: _emoji,
          category: _cat,
          farm: farmLabel(ref.read(marketNameProvider)),
          km: 0, // no farm location yet, so the shop shows no distance
          price: listed,
          wasPrice: _rescue ? usual : null,
          unit: _unit,
          stock: qty,
          mine: true,
          rescue: _rescue,
        ));
    if (block != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(block), behavior: SnackBarBehavior.floating));
      return;
    }
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(
          '$_emoji $name is listed. $qty in stock at ${money(listed)} per $_unit'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: '🌱 Add stock',
      subtitle: ref.watch(marketSharedProvider)
          ? 'Neighbours nearby see it as soon as you save.'
          : 'Saved on this phone. Neighbours see it once your store is shared.',
      children: [
        Form(
          key: _form,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _emojis.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppTheme.s2),
                itemBuilder: (_, i) {
                  final e = _emojis[i];
                  final on = _emoji == e;
                  return GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on
                            ? AppTheme.sprout.withValues(alpha: 0.25)
                            : AppTheme.glassFill,
                        borderRadius: BorderRadius.circular(AppTheme.rControl),
                        border: Border.all(
                            color: on ? AppTheme.sprout : AppTheme.glassBorder),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppTheme.s3),
            GlassField(
              controller: _name,
              label: 'What are you selling? (e.g. Carrots 5kg)',
              icon: Icons.eco_rounded,
              validator: _checkName,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppTheme.s3),
            Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
              for (final c in Category.values)
                ChoiceChipButton(
                  label: c.label,
                  selected: _cat == c,
                  onTap: () => setState(() => _cat = c),
                ),
            ]),
            const SizedBox(height: AppTheme.s3),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: GlassField(
                  controller: _price,
                  label: _rescue ? 'Usual price (R)' : 'Price in Rand',
                  icon: Icons.payments_rounded,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _checkPrice,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: AppTheme.s3),
              Expanded(
                child: GlassField(
                  controller: _qty,
                  label: 'How many',
                  icon: Icons.inventory_2_rounded,
                  keyboardType: TextInputType.number,
                  validator: _checkQty,
                ),
              ),
            ]),
            const SizedBox(height: AppTheme.s3),
            Text('Sold per', style: AppTheme.caption),
            const SizedBox(height: AppTheme.s2),
            Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
              for (final u in _units)
                ChoiceChipButton(
                  label: u,
                  selected: _unit == u,
                  onTap: () => setState(() => _unit = u),
                ),
            ]),
            const SizedBox(height: AppTheme.s2),
            // Rebuilds as the price is typed, so the farmer sees what buyers pay.
            ListenableBuilder(
              listenable: _price,
              builder: (_, __) {
                final usual = parseNumber(_price.text);
                // The sheet paints its own background, which would hide the tile's ink.
                return Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppTheme.warn,
                    value: _rescue,
                    onChanged: (v) => setState(() => _rescue = v),
                    title: Text('♻️ Sell fast at a discount',
                        style: AppTheme.headline),
                    subtitle: Text(
                      _rescue && usual != null && usual > 0
                          ? 'Neighbours pay ${money(r2(usual * (1 - rescueDiscount)))} (${(rescueDiscount * 100).round()}% off ${money(usual)}).'
                          : 'Frost or a glut coming? Take ${(rescueDiscount * 100).round()}% off so it goes today.',
                      style: AppTheme.footnote,
                    ),
                  ),
                );
              },
            ),
          ]),
        ),
        const SizedBox(height: AppTheme.s3),
        GlassButton(
            label: 'List it', icon: Icons.check_rounded, onPressed: _save),
      ],
    );
  }
}
