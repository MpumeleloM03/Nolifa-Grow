import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cattle.dart';
import '../../services/auth_service.dart';
import '../../services/cattle_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';

class AddCattleScreen extends ConsumerStatefulWidget {
  final Cattle? existing;
  const AddCattleScreen({super.key, this.existing});

  @override
  ConsumerState<AddCattleScreen> createState() => _AddCattleScreenState();
}

class _AddCattleScreenState extends ConsumerState<AddCattleScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tag;
  late final TextEditingController _name;
  late final TextEditingController _breed;
  late final TextEditingController _notes;

  late TagStandard _standard;
  late String _sex;
  late CattleStatus _status;
  DateTime? _birth;
  bool _busy = false;

  static const _sexes = ['cow', 'bull', 'heifer', 'steer', 'calf'];

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _tag = TextEditingController(text: e?.tagNumber ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _breed = TextEditingController(text: e?.breed ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _standard = e?.tagStandard ?? TagStandard.visual;
    _sex = e?.sex ?? 'cow';
    _status = e?.status ?? CattleStatus.active;
    _birth = e?.birthDate;
  }

  @override
  void dispose() {
    _tag.dispose();
    _name.dispose();
    _breed.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(authServiceProvider).current?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    final service = ref.read(cattleServiceProvider);
    final animal = Cattle(
      id: widget.existing?.id ?? '',
      tagNumber: _tag.text.trim(),
      tagStandard: _standard,
      name: _name.text.trim(),
      breed: _breed.text.trim(),
      sex: _sex,
      birthDate: _birth,
      status: _status,
      notes: _notes.text.trim(),
    );

    try {
      if (_editing) {
        await service.update(uid, animal);
      } else {
        await service.add(uid, animal);
      }
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.danger,
          content: Text('Could not save: $e'),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final uid = ref.read(authServiceProvider).current?.uid;
    if (uid == null || widget.existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.forest,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rCard)),
        title: Text('Remove animal?', style: AppTheme.title3),
        content: Text(
          'This deletes ${widget.existing!.tagNumber} from your herd register. '
          'It cannot be undone.',
          style: AppTheme.subhead,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: AppTheme.subhead)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove',
                style: AppTheme.headline.copyWith(color: AppTheme.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(cattleServiceProvider).remove(uid, widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.livestockAccent,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: const GlassBar(),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(_editing ? 'Edit animal' : 'Add animal'),
                actions: [
                  if (_editing)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 22, color: AppTheme.danger),
                      onPressed: _delete,
                    ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                sliver: SliverToBoxAdapter(
                  child: Form(
                    key: _formKey,
                    child: GlassCard(
                      padding: const EdgeInsets.all(AppTheme.s6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GlassField(
                            controller: _tag,
                            label: 'Tag number',
                            icon: Icons.sell_outlined,
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Every animal needs a tag number'
                                : null,
                          ),
                          const SizedBox(height: AppTheme.s5),
                          Text('Tag type', style: AppTheme.headline),
                          const SizedBox(height: AppTheme.s3),
                          ...TagStandard.values.map((t) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: AppTheme.s2),
                                child: _RadioRow(
                                  title: t.label,
                                  subtitle: t.description,
                                  selected: _standard == t,
                                  onTap: () => setState(() => _standard = t),
                                ),
                              )),
                          const SizedBox(height: AppTheme.s5),
                          GlassField(
                            controller: _name,
                            label: 'Name (optional)',
                            icon: Icons.badge_outlined,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: AppTheme.s4),
                          GlassField(
                            controller: _breed,
                            label: 'Breed (optional)',
                            icon: Icons.category_outlined,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: AppTheme.s5),
                          Text('Class', style: AppTheme.headline),
                          const SizedBox(height: AppTheme.s3),
                          Wrap(
                            spacing: AppTheme.s2,
                            runSpacing: AppTheme.s2,
                            children: _sexes
                                .map((s) => _Pill(
                                      label: s,
                                      selected: _sex == s,
                                      onTap: () => setState(() => _sex = s),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: AppTheme.s5),
                          _DateRow(
                            date: _birth,
                            onPick: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _birth ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                                builder: (ctx, child) => Theme(
                                  data: Theme.of(ctx).copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: AppTheme.livestockAccent,
                                      surface: AppTheme.forest,
                                    ),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setState(() => _birth = picked);
                              }
                            },
                            onClear: () => setState(() => _birth = null),
                          ),
                          const SizedBox(height: AppTheme.s5),
                          Text('Status', style: AppTheme.headline),
                          const SizedBox(height: AppTheme.s3),
                          Wrap(
                            spacing: AppTheme.s2,
                            children: CattleStatus.values
                                .map((s) => _Pill(
                                      label: s.label,
                                      selected: _status == s,
                                      onTap: () => setState(() => _status = s),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: AppTheme.s5),
                          GlassField(
                            controller: _notes,
                            label: 'Notes (optional)',
                            icon: Icons.notes_rounded,
                          ),
                          const SizedBox(height: AppTheme.s6),
                          GlassButton(
                            label: _editing ? 'Save changes' : 'Add to herd',
                            icon: Icons.check_rounded,
                            accent: AppTheme.livestockAccent,
                            busy: _busy,
                            onPressed: _save,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RadioRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(AppTheme.s3),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.livestockAccent.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.rChip),
          border: Border.all(
            color: selected
                ? AppTheme.livestockAccent
                : AppTheme.glassBorderSoft,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 19,
              color: selected
                  ? AppTheme.livestockAccent
                  : AppTheme.textTertiary,
            ),
            const SizedBox(width: AppTheme.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTheme.subhead
                          .copyWith(color: AppTheme.textPrimary)),
                  Text(subtitle, style: AppTheme.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.s4, vertical: AppTheme.s2),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.livestockAccent.withValues(alpha: 0.2)
              : AppTheme.glassFill,
          borderRadius: BorderRadius.circular(AppTheme.rChip),
          border: Border.all(
            color: selected
                ? AppTheme.livestockAccent
                : AppTheme.glassBorderSoft,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.footnote.copyWith(
            color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DateRow(
      {required this.date, required this.onPick, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.s4),
        decoration: BoxDecoration(
          color: AppTheme.glassFill,
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.cake_outlined,
                size: 20, color: AppTheme.textTertiary),
            const SizedBox(width: AppTheme.s3),
            Expanded(
              child: Text(
                date == null
                    ? 'Date of birth (optional)'
                    : '${date!.day}/${date!.month}/${date!.year}',
                style: date == null
                    ? AppTheme.subhead
                    : AppTheme.subhead.copyWith(color: AppTheme.textPrimary),
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded,
                    size: 18, color: AppTheme.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}
