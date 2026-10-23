import 'package:flutter/material.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show rand;
import '../theme/app_theme.dart';
import '../theme/glass.dart';

/// Accent for everything water. The design tokens have no blue yet.
const Color waterBlue = Color(0xFF5AB8F0);

/// Groups digits in threes with a space, the South African way: 12 500.
String groupDigits(num n) => n
    .round()
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

/// Whole Rand when there are no cents, two decimals otherwise.
String money(double v) => rand(v, decimals: v == v.roundToDouble() ? 0 : 2);

/// First word of a name. Orders show buyers by first name only, so a farmer
/// sees who to expect without the app handing out full names.
String firstName(String full) {
  final first = full.trim().split(RegExp(r'\s+')).first;
  return first.isEmpty ? 'A neighbour' : first;
}

/// "Just now", "6 min ago", "3 h ago", "2 d ago".
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// Parses a number a farmer typed. Accepts a comma as the decimal mark, since
/// that is how many South African phones are set up.
double? parseNumber(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', '.'));
  // "NaN" and "Infinity" parse as numbers but are not amounts.
  return v != null && v.isFinite ? v : null;
}

/// Largest price or stock count Nolifa Drop accepts. Matches firestore.rules.
const maxStoreNumber = 100000;

/// Longest product name Nolifa Drop accepts. Matches firestore.rules.
const maxProductName = 80;

/// What buyers see as the farm's name on a listing.
String farmLabel(String ownerName) =>
    ownerName == 'Neighbour' ? 'Local farm' : "$ownerName's farm";

/// Same dark panel the shared report sheet uses.
Color get _sheetFill => AppTheme.sheet;

/// Bottom-sheet chrome shared by the store's sheets: dark panel, rounded top,
/// scrolls when the keyboard takes the space.
class SheetFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const SheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: _sheetFill,
          borderRadius:
              const BorderRadius.vertical(top: const Radius.circular(AppTheme.rCard)),
        ),
        padding: const EdgeInsets.all(AppTheme.s6),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.title2),
                if (subtitle != null) ...[
                  const SizedBox(height: AppTheme.s1),
                  Text(subtitle!, style: AppTheme.footnote),
                ],
                const SizedBox(height: AppTheme.s4),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small tappable chip with a comfortable touch target. Used for the choices
/// and quick actions inside the store.
class ChoiceChipButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const ChoiceChipButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.sprout : AppTheme.textSecondary;
    final radius = BorderRadius.circular(AppTheme.rChip);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s3),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: selected
                ? AppTheme.sprout.withValues(alpha: 0.16)
                : AppTheme.glassFill,
            border: Border.all(
                color: selected ? AppTheme.sprout : AppTheme.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: AppTheme.s1),
              ],
              Text(label, style: AppTheme.subhead.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for one number in a small sheet. Returns null if the farmer backs out.
Future<double?> askNumber(
  BuildContext context, {
  required String title,
  required String label,
  required IconData icon,
  String? subtitle,
  String initial = '',
  bool decimal = false,
  bool allowZero = false,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NumberSheet(
      title: title,
      subtitle: subtitle,
      label: label,
      icon: icon,
      initial: initial,
      decimal: decimal,
      allowZero: allowZero,
    ),
  );
}

class _NumberSheet extends StatefulWidget {
  final String title, label, initial;
  final String? subtitle;
  final IconData icon;
  final bool decimal, allowZero;

  const _NumberSheet({
    required this.title,
    required this.label,
    required this.icon,
    required this.initial,
    required this.decimal,
    required this.allowZero,
    this.subtitle,
  });

  @override
  State<_NumberSheet> createState() => _NumberSheetState();
}

class _NumberSheetState extends State<_NumberSheet> {
  late final _text = TextEditingController(text: widget.initial);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? _check(String? raw) {
    final v = parseNumber(raw ?? '');
    if (v == null) return 'Type a number';
    if (v < 0 || (v == 0 && !widget.allowZero)) return 'Must be more than zero';
    if (v > maxStoreNumber)
      return 'Keep it under ${groupDigits(maxStoreNumber)}';
    if (!widget.decimal && v != v.roundToDouble()) return 'Whole numbers only';
    return null;
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, parseNumber(_text.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: widget.title,
      subtitle: widget.subtitle,
      children: [
        Form(
          key: _form,
          child: GlassField(
            controller: _text,
            label: widget.label,
            icon: widget.icon,
            keyboardType:
                TextInputType.numberWithOptions(decimal: widget.decimal),
            validator: _check,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: AppTheme.s4),
        GlassButton(
            label: 'Save', icon: Icons.check_rounded, onPressed: _submit),
      ],
    );
  }
}
