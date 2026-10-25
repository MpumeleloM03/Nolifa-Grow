import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, friendlyError;
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;

/// The signed-in driver's application row, or null on the phone alone.
final driverApplicationProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.uid));
  if (!SupabaseBoot.ready) return null;
  final uid = SupabaseBoot.client.auth.currentUser?.id;
  if (uid == null) return null;
  final row = await SupabaseBoot.client.from('driver_applications').select().eq('uid', uid).maybeSingle();
  return row == null ? null : Map<String, dynamic>.from(row);
});

/// True once Nolifa staff have approved this driver. The server decides; the
/// app only reads the answer, so a driver cannot approve themselves.
final approvedDriverProvider = FutureProvider<bool>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.uid));
  if (!SupabaseBoot.ready) return false;
  try {
    return await SupabaseBoot.client.rpc('is_approved_driver') == true;
  } catch (_) {
    return false;
  }
});

/// What Nolifa needs before someone can take delivery jobs: who they are, what
/// they drive, and four photos. Staff review it in the back office.
class DriverApplicationScreen extends ConsumerStatefulWidget {
  const DriverApplicationScreen({super.key});

  @override
  ConsumerState<DriverApplicationScreen> createState() => _DriverApplicationState();
}

class _DriverApplicationState extends ConsumerState<DriverApplicationScreen> {
  static const _vehicles = ['Bicycle', 'Motorbike', 'Car', 'Bakkie'];
  static const _licences = ['None (bicycle)', 'A (motorbike)', 'B (car)', 'EB', 'C1'];
  static const _photos = [
    ('driver_id_front', 'Front of your ID'),
    ('driver_selfie_with_id', 'Selfie holding your ID'),
    ('driver_licence', 'Driving licence (or ID again for a bicycle)'),
    ('driver_vehicle', 'Your vehicle with its plate'),
  ];

  final _name = TextEditingController();
  final _id = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  String? _vehicle;
  String? _licence;
  bool _consent = false;
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  String? _note;
  Set<String> _uploaded = {};

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _phone.dispose();
    _plate.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic>? app) {
    if (_loaded) return;
    _loaded = true;
    final d = (app?['data'] as Map?)?.cast<String, dynamic>() ?? {};
    _name.text = '${d['fullName'] ?? ref.read(currentUserProvider)?.name ?? ''}';
    _id.text = '${d['idNumber'] ?? ''}';
    _phone.text = '${d['phone'] ?? ''}';
    _plate.text = '${d['plate'] ?? ''}';
    _vehicle = d['vehicle'] as String?;
    _licence = d['licenceCode'] as String?;
    _consent = d['consent'] == true;
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      final uid = SupabaseBoot.client.auth.currentUser!.id;
      final rows = await SupabaseBoot.client.from('application_files').select('kind').eq('uid', uid);
      if (mounted) setState(() => _uploaded = {for (final r in rows) '${r['kind']}'});
    } catch (_) {}
  }

  Map<String, dynamic> get _data => {
        'fullName': _name.text.trim(),
        'idNumber': _id.text.trim(),
        'phone': _phone.text.trim(),
        'vehicle': _vehicle ?? '',
        'plate': _plate.text.trim(),
        'licenceCode': _licence ?? '',
        'consent': _consent,
      };

  Future<bool> _save() async {
    try {
      await SupabaseBoot.client.rpc('save_driver_application', params: {'p_data': _data});
      return true;
    } catch (e) {
      setState(() => _error = friendlyError(e, doing: 'save your application'));
      return false;
    }
  }

  Future<void> _photo(String kind) async {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 75, maxWidth: 1600);
    if (shot == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = SupabaseBoot.client;
      final uid = db.auth.currentUser!.id;
      final path = '$uid/$kind-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await db.storage
          .from('verification')
          .upload(path, File(shot.path), fileOptions: const FileOptions(contentType: 'image/jpeg'));
      await db.rpc('add_application_file', params: {'p_kind': kind, 'p_path': path});
      await _loadFiles();
    } catch (e) {
      _error = friendlyError(e, doing: 'upload that photo');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    if (await _save()) {
      try {
        await SupabaseBoot.client.rpc('submit_driver_application');
        HapticFeedback.mediumImpact();
        ref.invalidate(driverApplicationProvider);
        _note = 'Sent. Nolifa will check your details and photos, usually within a day.';
      } catch (e) {
        _error = friendlyError(e, doing: 'send your application');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _chips(List<String> options, String? value, ValueChanged<String> onPick, bool locked) => Wrap(
        spacing: AppTheme.s2,
        runSpacing: AppTheme.s2,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(o),
              selected: value == o,
              onSelected: locked ? null : (_) => setState(() => onPick(o)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (!SupabaseBoot.ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('Become a driver')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.s6),
            child: Text('Driver applications need the shared database. Connect to it and try again.',
                textAlign: TextAlign.center, style: AppTheme.callout),
          ),
        ),
      );
    }
    final app = ref.watch(driverApplicationProvider);
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: app.when(
            loading: () => Center(child: CircularProgressIndicator(color: AppTheme.sprout)),
            error: (e, _) => Center(child: Text(friendlyError(e, doing: 'load your application'))),
            data: (row) {
              _hydrate(row);
              final status = '${row?['status'] ?? 'draft'}';
              final locked = status == 'submitted' || status == 'approved';
              final review = '${row?['review_note'] ?? ''}';
              final ready = _data.values.every((v) => v is bool ? v : '$v'.isNotEmpty) &&
                  _photos.every((p) => _uploaded.contains(p.$1));
              return CustomScrollView(slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  flexibleSpace: const GlassBar(),
                  title: const Text('Become a driver'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
                  sliver: SliverList.list(children: [
                    GlassCard(
                      tint: (status == 'approved' ? AppTheme.sprout : AppTheme.warn).withValues(alpha: 0.12),
                      child: Row(children: [
                        Icon(
                          status == 'approved' ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                          color: status == 'approved' ? AppTheme.sprout : AppTheme.warn,
                        ),
                        const SizedBox(width: AppTheme.s3),
                        Expanded(
                          child: Text(
                            switch (status) {
                              'approved' => 'You are approved. Go online on the Jobs tab to start earning.',
                              'submitted' => 'With Nolifa for review. We will let you know.',
                              'needs_info' => 'Nolifa needs more: $review',
                              'rejected' => 'Not approved: $review',
                              _ => 'Fill this in once. Nolifa checks it before your first job.',
                            },
                            style: AppTheme.callout.copyWith(color: AppTheme.textPrimary),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: AppTheme.s4),
                    GlassField(
                        controller: _name,
                        label: 'Full name',
                        icon: Icons.person_outline_rounded,
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: AppTheme.s3),
                    GlassField(
                        controller: _id,
                        label: 'ID number',
                        icon: Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: AppTheme.s3),
                    GlassField(
                        controller: _phone,
                        label: 'Phone number',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: AppTheme.s4),
                    Text('What do you drive?', style: AppTheme.headline),
                    const SizedBox(height: AppTheme.s2),
                    _chips(_vehicles, _vehicle, (v) => _vehicle = v, locked),
                    const SizedBox(height: AppTheme.s3),
                    GlassField(
                        controller: _plate,
                        label: 'Number plate (write NONE for a bicycle)',
                        icon: Icons.directions_car_outlined,
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: AppTheme.s4),
                    Text('Licence code', style: AppTheme.headline),
                    const SizedBox(height: AppTheme.s2),
                    _chips(_licences, _licence, (v) => _licence = v, locked),
                    const SizedBox(height: AppTheme.s4),
                    Text('Photos', style: AppTheme.headline),
                    const SizedBox(height: AppTheme.s2),
                    for (final p in _photos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.s2),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s3),
                          onTap: locked || _busy ? null : () => _photo(p.$1),
                          child: Row(children: [
                            Icon(
                              _uploaded.contains(p.$1) ? Icons.check_circle_rounded : Icons.photo_camera_rounded,
                              color: _uploaded.contains(p.$1) ? AppTheme.sprout : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: AppTheme.s3),
                            Expanded(child: Text(p.$2, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary))),
                            Text(_uploaded.contains(p.$1) ? 'Done' : 'Take photo', style: AppTheme.caption),
                          ]),
                        ),
                      ),
                    const SizedBox(height: AppTheme.s2),
                    CheckboxListTile(
                      value: _consent,
                      onChanged: locked ? null : (v) => setState(() => _consent = v ?? false),
                      activeColor: AppTheme.sprout,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'I agree that Nolifa may check my ID and licence, and keep these photos safely to verify me.',
                        style: AppTheme.footnote,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppTheme.s2),
                      Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
                    ],
                    if (_note != null) ...[
                      const SizedBox(height: AppTheme.s2),
                      Text(_note!, style: AppTheme.footnote.copyWith(color: AppTheme.sprout)),
                    ],
                    const SizedBox(height: AppTheme.s4),
                    if (!locked)
                      GlassButton(
                        label: ready ? 'Send to Nolifa' : 'Fill in everything above',
                        icon: Icons.send_rounded,
                        busy: _busy,
                        onPressed: ready && !_busy ? _submit : null,
                      ),
                  ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
