import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, PostgrestException;
import 'package:ubuntu_core/ubuntu_core.dart';

import '../auth/auth_service.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show trn;
/// This driver's application, live.
final driverApplicationProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
  if (uid == null || !SupabaseBoot.ready) return Stream.value(null);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('driver_applications').stream(primaryKey: ['uid']).eq('uid', uid),
    fetch: () async => [for (final r in await db.from('driver_applications').select().eq('uid', uid)) Map<String, dynamic>.from(r)],
  ).map((rows) => rows.isEmpty ? null : rows.first);
});

/// True once Nolifa has approved this person as a driver. Null in phone-only mode.
final driverApprovedProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
  if (uid == null || !SupabaseBoot.ready) return Stream.value(false);
  final db = SupabaseBoot.client;
  return resilientRows(
    open: () => db.from('approved_drivers').stream(primaryKey: ['uid']).eq('uid', uid),
    fetch: () async => [for (final r in await db.from('approved_drivers').select().eq('uid', uid)) Map<String, dynamic>.from(r)],
  ).map((rows) => rows.isNotEmpty);
});

/// What Nolifa needs before a person carries other people's food and knocks on
/// their doors: who they are, their licence, their vehicle, and photos staff check.
class DriverApplicationScreen extends ConsumerStatefulWidget {
  const DriverApplicationScreen({super.key});

  @override
  ConsumerState<DriverApplicationScreen> createState() => _State();
}

class _State extends ConsumerState<DriverApplicationScreen> {
  final _d = <String, dynamic>{};
  final _c = <String, TextEditingController>{};
  var _loaded = false;
  var _busy = false;
  String? _error, _saved;
  List<Map<String, dynamic>> _files = [];

  TextEditingController _ctl(String k) => _c.putIfAbsent(k, () => TextEditingController(text: '${_d[k] ?? ''}'));

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _locked {
    final st = ref.read(driverApplicationProvider).valueOrNull?['status'];
    return st == 'submitted' || st == 'approved';
  }

  Future<void> _loadFiles() async {
    try {
      final uid = SupabaseBoot.client.auth.currentUser!.id;
      final rows = await SupabaseBoot.client.from('application_files').select().eq('uid', uid);
      if (mounted) setState(() => _files = [for (final r in rows) Map<String, dynamic>.from(r)]);
    } catch (_) {}
  }

  bool _has(String kind) => _files.any((f) => f['kind'] == kind);

  Future<bool> _save({bool quiet = false}) async {
    for (final e in _c.entries) {
      _d[e.key] = e.value.text.trim();
    }
    try {
      await SupabaseBoot.client.rpc('save_driver_application', params: {'p_data': _d});
      if (!quiet && mounted) setState(() => _saved = 'Draft saved.');
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, doing: 'save your application'));
      return false;
    }
  }

  Future<void> _photo(String kind, {bool selfie = false}) async {
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
          imageQuality: 80,
          maxWidth: 1800);
      if (x == null) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final db = SupabaseBoot.client;
      final uid = db.auth.currentUser!.id;
      final path = '$uid/$kind-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await db.storage.from('verification').upload(path, File(x.path), fileOptions: const FileOptions(contentType: 'image/jpeg'));
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
    });
    if (!await _save(quiet: true)) {
      setState(() => _busy = false);
      return;
    }
    try {
      await SupabaseBoot.client.rpc('submit_driver_application');
      HapticFeedback.mediumImpact();
    } on PostgrestException catch (e) {
      _error = e.code == 'P0004' ? 'Still needed: ${e.message.replaceFirst(RegExp(r'^.*Still missing: '), '')}.' : friendlyError(e, doing: 'send your application');
    } catch (e) {
      _error = friendlyError(e, doing: 'send your application');
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _field(String k, String label, IconData icon, {TextInputType? type, String? Function(String?)? check}) {
    final ctl = _ctl(k);
    final msg = check?.call(ctl.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.s3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: ctl,
          enabled: !_locked,
          keyboardType: type,
          onChanged: (_) => setState(() {}),
          style: AppTheme.callout.copyWith(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: trn(label),
            prefixIcon: Icon(icon, size: 20),
            filled: true,
            fillColor: AppTheme.glassFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.rChip)),
          ),
        ),
        if (msg != null && ctl.text.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(left: 12, top: 2), child: Text(msg, style: AppTheme.caption.copyWith(color: AppTheme.danger))),
      ]),
    );
  }

  Widget _photoRow(String kind, String title, String hint, {bool selfie = false}) => GlassCard(
        padding: const EdgeInsets.all(AppTheme.s4),
        child: Row(children: [
          Icon(_has(kind) ? Icons.check_circle_rounded : Icons.photo_camera_rounded, color: _has(kind) ? AppTheme.ok : AppTheme.textTertiary),
          const SizedBox(width: AppTheme.s3),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: AppTheme.headline), Text(_has(kind) ? 'Added' : hint, style: AppTheme.footnote)])),
          if (!_locked) GhostButton(label: _has(kind) ? 'Retake' : 'Take photo', onPressed: _busy ? null : () => _photo(kind, selfie: selfie)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final appAsync = ref.watch(driverApplicationProvider);
    final app = appAsync.valueOrNull;
    if (appAsync.hasValue && !_loaded) {
      _loaded = true;
      _d.addAll((app?['data'] as Map?)?.cast<String, dynamic>() ?? {});
      _loadFiles();
    }
    final status = app?['status'] as String? ?? 'draft';
    final note = app?['review_note'] as String? ?? '';
    final idRes = checkSaId('${_d['idNumber'] ?? ''}');
    final banner = switch (status) {
      'submitted' => 'With Nolifa for review. We will tell you when you can start.',
      'approved' => 'Approved. You can go online.',
      'needs_info' => 'We need a bit more: $note',
      'rejected' => 'Not approved: $note',
      _ => null,
    };
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: const GlassBar(),
              leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
              title: const Text('Become a driver'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
              sliver: SliverList.list(children: [
                Text('Apply to drive', style: AppTheme.title1),
                const SizedBox(height: AppTheme.s1),
                Text('Drivers carry food and know where people live, so Nolifa checks every driver before the first job. Staff compare your ID with your selfie. Photos are kept private.', style: AppTheme.callout),
                if (banner != null) Padding(padding: const EdgeInsets.only(top: AppTheme.s3), child: GlassCard(child: Text(banner, style: AppTheme.callout))),
                const SizedBox(height: AppTheme.s4),
                _field('fullName', 'Full name and surname', Icons.person_rounded),
                _field('idNumber', 'South African ID number', Icons.badge_rounded, type: TextInputType.number, check: (_) => idRes.ok ? null : idRes.message),
                _field('phone', 'Mobile number', Icons.phone_rounded, type: TextInputType.phone, check: (v) => checkSaPhone(v ?? '')),
                Text('Your vehicle', style: AppTheme.headline),
                const SizedBox(height: AppTheme.s2),
                Wrap(spacing: AppTheme.s2, children: [
                  for (final v in const ['motorbike', 'car', 'bakkie', 'bicycle'])
                    ChoiceChip(label: Text(v), selected: _d['vehicle'] == v, onSelected: _locked ? null : (_) => setState(() => _d['vehicle'] = v)),
                ]),
                const SizedBox(height: AppTheme.s3),
                _field('plate', 'Number plate', Icons.pin_rounded),
                Text('Licence code', style: AppTheme.headline),
                const SizedBox(height: AppTheme.s2),
                Wrap(spacing: AppTheme.s2, children: [
                  for (final v in const ['A1', 'A', 'B', 'EB', 'C1', 'None (bicycle)'])
                    ChoiceChip(label: Text(v), selected: _d['licenceCode'] == v, onSelected: _locked ? null : (_) => setState(() => _d['licenceCode'] = v)),
                ]),
                const SizedBox(height: AppTheme.s4),
                _photoRow('driver_id_front', 'Photo of your ID', 'The front of your ID card, in good light.'),
                const SizedBox(height: AppTheme.s2),
                _photoRow('driver_selfie_with_id', 'Selfie holding your ID', 'Hold the ID next to your face.', selfie: true),
                const SizedBox(height: AppTheme.s2),
                _photoRow('driver_licence', 'Driver\'s licence', 'Front of the card.'),
                const SizedBox(height: AppTheme.s2),
                _photoRow('driver_vehicle', 'Your vehicle', 'Side on, with the number plate visible.'),
                const SizedBox(height: AppTheme.s3),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _d['consent'] == true,
                  onChanged: _locked ? null : (v) => setState(() => _d['consent'] = v == true),
                  title: Text('Everything here is true. Nolifa may check it and keep my ID and photos safely for verification under POPIA.', style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
                ),
                if (_error != null) Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
                if (_saved != null && _error == null) Text(_saved!, style: AppTheme.footnote.copyWith(color: AppTheme.ok)),
                if (_busy) const Padding(padding: EdgeInsets.only(top: AppTheme.s2), child: LinearProgressIndicator()),
                const SizedBox(height: AppTheme.s3),
                if (!_locked) ...[
                  GhostButton(label: 'Save draft', icon: Icons.save_rounded, onPressed: _busy ? null : _save),
                  const SizedBox(height: AppTheme.s2),
                  GlassButton(label: 'Send to Nolifa', icon: Icons.send_rounded, onPressed: _busy ? null : _submit),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
