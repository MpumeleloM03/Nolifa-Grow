import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cattle.dart';
import '../../services/auth_service.dart';
import '../../services/cattle_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import 'add_cattle_screen.dart';

class HerdScreen extends ConsumerStatefulWidget {
  const HerdScreen({super.key});

  @override
  ConsumerState<HerdScreen> createState() => _HerdScreenState();
}

class _HerdScreenState extends ConsumerState<HerdScreen> {
  String _query = '';

  Future<void> _import() async {
    final controller = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.forest,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rCard)),
        title: Text('Import herd', style: AppTheme.title3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste the CSV your tag supplier exported. Column names from Allflex, '
              'Datamars and Shearwell are recognised automatically.',
              style: AppTheme.footnote,
            ),
            const SizedBox(height: AppTheme.s4),
            TextField(
              controller: controller,
              maxLines: 6,
              style: AppTheme.footnote.copyWith(
                  color: AppTheme.textPrimary, fontFamily: 'Menlo'),
              decoration: InputDecoration(
                hintText: 'tag_number,breed,sex\nZA0012,Nguni,cow',
                hintStyle: AppTheme.caption,
                filled: true,
                fillColor: AppTheme.glassFill,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rChip)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: AppTheme.subhead)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Import',
                style: AppTheme.headline.copyWith(color: AppTheme.sprout)),
          ),
        ],
      ),
    );

    if (go != true || controller.text.trim().isEmpty) return;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;

    final result =
        await ref.read(cattleServiceProvider).importCsv(uid, controller.text);
    if (!mounted) return;

    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: result.added > 0 ? AppTheme.leaf : AppTheme.danger,
        content: Text(result.added > 0
            ? 'Imported ${result.added} animals${result.skipped > 0 ? ", skipped ${result.skipped}" : ""}'
            : result.problems.isNotEmpty
                ? result.problems.first
                : 'Nothing imported'),
      ),
    );
  }

  Future<void> _export(List<Cattle> herd) async {
    final csv = ref.read(cattleServiceProvider).exportCsv(herd);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.leaf,
        content: Text('${herd.length} animals copied as CSV'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final herd = ref.watch(herdProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.livestockAccent,
        foregroundColor: const Color(0xFF07150F),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddCattleScreen()),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add animal'),
      ),
      body: AppBackdrop(
        tint: AppTheme.livestockAccent,
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(child: Text('Herd register', style: AppTheme.title2)),
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined, size: 22),
                    tooltip: 'Import CSV',
                    onPressed: _import,
                  ),
                  herd.maybeWhen(
                    data: (list) => IconButton(
                      icon: const Icon(Icons.file_upload_outlined, size: 22),
                      tooltip: 'Export CSV',
                      onPressed: list.isEmpty ? null : () => _export(list),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(width: AppTheme.s2),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s3),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                  style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search tag, name or breed',
                    hintStyle: AppTheme.subhead,
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 20, color: AppTheme.textTertiary),
                    filled: true,
                    fillColor: AppTheme.glassFill,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rControl),
                      borderSide: const BorderSide(color: AppTheme.glassBorder),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: herd.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.livestockAccent)),
                  error: (e, _) => _Message(
                      icon: Icons.cloud_off_rounded,
                      title: 'Cannot load your herd',
                      body: '$e'),
                  data: (list) {
                    final shown = list.where((c) {
                      if (_query.isEmpty) return true;
                      return c.tagNumber.toLowerCase().contains(_query) ||
                          c.name.toLowerCase().contains(_query) ||
                          c.breed.toLowerCase().contains(_query);
                    }).toList();

                    if (list.isEmpty) {
                      return const _Message(
                        icon: Icons.pets_rounded,
                        title: 'No animals yet',
                        body:
                            'Add your first animal, or import the CSV from your tag supplier.',
                      );
                    }
                    if (shown.isEmpty) {
                      return const _Message(
                        icon: Icons.search_off_rounded,
                        title: 'No match',
                        body: 'Nothing in your herd matches that search.',
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          AppTheme.s4, 0, AppTheme.s4, 100),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s3),
                        child: _CattleRow(animal: shown[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CattleRow extends StatelessWidget {
  final Cattle animal;
  const _CattleRow({required this.animal});

  @override
  Widget build(BuildContext context) {
    final age = animal.ageMonths;
    final details = [
      if (animal.breed.isNotEmpty) animal.breed,
      animal.sex,
      if (age != null) age >= 24 ? '${(age / 12).floor()} yrs' : '$age mo',
    ].join(' · ');

    return GlassCard(
      radius: AppTheme.rControl,
      padding: const EdgeInsets.all(AppTheme.s4),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AddCattleScreen(existing: animal)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.livestockAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppTheme.rChip),
            ),
            child: Icon(
              animal.tagStandard == TagStandard.iso11784
                  ? Icons.nfc_rounded
                  : Icons.sell_outlined,
              size: 19,
              color: AppTheme.livestockAccent,
            ),
          ),
          const SizedBox(width: AppTheme.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  animal.name.isEmpty ? animal.tagNumber : animal.name,
                  style: AppTheme.headline,
                ),
                const SizedBox(height: 2),
                Text(
                  animal.name.isEmpty ? details : '${animal.tagNumber} · $details',
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          if (animal.status != CattleStatus.active)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.s2, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.glassFill,
                borderRadius: BorderRadius.circular(AppTheme.s2),
              ),
              child: Text(animal.status.label, style: AppTheme.caption),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppTheme.textTertiary),
            const SizedBox(height: AppTheme.s4),
            Text(title, style: AppTheme.title3, textAlign: TextAlign.center),
            const SizedBox(height: AppTheme.s2),
            Text(body, style: AppTheme.footnote, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
