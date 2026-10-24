import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, PostgrestException;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, deviceLocation, friendlyError;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'id_check.dart';
import 'members_service.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
import 'package:ubuntu_core/tr.dart' show tr, trn;
const provinces = [
  'Eastern Cape', 'Free State', 'Gauteng', 'KwaZulu-Natal', 'Limpopo', 'Mpumalanga', 'North West', 'Northern Cape', 'Western Cape',
];
const _sells = ['Cattle', 'Goats', 'Sheep', 'Pigs', 'Poultry', 'Eggs', 'Dairy', 'Vegetables', 'Fruit', 'Grain and maize', 'Honey'];
const _feeds = ['Veld grazing', 'Planted pasture', 'Hay', 'Silage', 'Lick or supplement', 'Grain or feedlot ration', 'Crop residue'];

/// What Nolifa needs to know about a farm before it sells to the public. Staff
/// read all of this. The vets use the husbandry answers to understand the farm.
class FarmApplicationScreen extends ConsumerStatefulWidget {
  const FarmApplicationScreen({super.key});

  @override
  ConsumerState<FarmApplicationScreen> createState() => _FarmApplicationState();
}

class _FarmApplicationState extends ConsumerState<FarmApplicationScreen> {
  final _d = <String, dynamic>{'practices': <String, dynamic>{}, 'products': <String>[]};
  final _c = <String, TextEditingController>{};
  var _loaded = false;
  var _busy = false;
  String? _error;
  String? _saved;
  List<Map<String, dynamic>> _files = [];

  TextEditingController _ctl(String k, {bool practice = false}) => _c.putIfAbsent(k, () {
        final src = practice ? (_d['practices'] as Map)[k] : _d[k];
        return TextEditingController(text: src == null ? '' : '$src');
      });

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _p => _d['practices'] as Map<String, dynamic>;
  List<String> get _products => (_d['products'] as List).cast<String>();

  Future<void> _loadFiles() async {
    try {
      final uid = SupabaseBoot.client.auth.currentUser!.id;
      final rows = await SupabaseBoot.client.from('application_files').select().eq('uid', uid);
      if (mounted) setState(() => _files = [for (final r in rows) Map<String, dynamic>.from(r)]);
    } catch (_) {}
  }

  int _count(String kind) => _files.where((f) => f['kind'] == kind).length;

  void _hydrate(Map<String, dynamic>? app) {
    if (_loaded) return;
    _loaded = true;
    final data = (app?['data'] as Map?)?.cast<String, dynamic>() ?? {};
    _d.addAll(data);
    _d['practices'] = Map<String, dynamic>.from((data['practices'] as Map?) ?? {});
    _d['products'] = [for (final p in (data['products'] as List? ?? const [])) '$p'];
    _loadFiles();
  }

  bool get _locked {
    final st = ref.read(applicationProvider).valueOrNull?['status'];
    return st == 'submitted' || st == 'approved';
  }

  void _set(String k, Object? v) => setState(() => _d[k] = v);
  void _practice(String k, Object? v) => setState(() => _p[k] = v);

  Future<bool> _save({bool quiet = false}) async {
    for (final e in _c.entries) {
      // Text controllers hold the live values.
      final isPractice = const ['feedNotes', 'waterSource', 'housing', 'vaccineProgramme', 'dewormFreq', 'vetName', 'quarantine', 'records', 'cropInputs', 'irrigation', 'harvest'].contains(e.key);
      if (isPractice) {
        _p[e.key] = e.value.text.trim();
      } else if (e.key == 'sizeHa') {
        _d[e.key] = double.tryParse(e.value.text.replaceAll(',', '.'));
      } else {
        _d[e.key] = e.value.text.trim();
      }
    }
    try {
      await SupabaseBoot.client.rpc('save_application', params: {'p_data': _d});
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
        source: selfie ? ImageSource.camera : ImageSource.camera,
        preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
        imageQuality: 80,
        maxWidth: 1800,
      );
      if (x == null) return;
      await _upload(kind, File(x.path));
    } catch (e) {
      // The camera may be unavailable, or permission denied. Offer the gallery.
      try {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1800);
        if (x != null) await _upload(kind, File(x.path));
      } catch (e2) {
        if (mounted) setState(() => _error = 'We could not open the camera or photos. Allow access in Settings and try again.');
      }
    }
  }

  Future<void> _upload(String kind, File f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = SupabaseBoot.client;
      final uid = db.auth.currentUser!.id;
      final path = '$uid/$kind-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await db.storage.from('verification').upload(path, f, fileOptions: const FileOptions(contentType: 'image/jpeg'));
      await db.rpc('add_application_file', params: {'p_kind': kind, 'p_path': path});
      await _loadFiles();
    } catch (e) {
      _error = friendlyError(e, doing: 'upload that photo');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _locate() async {
    final here = await deviceLocation();
    if (!mounted) return;
    if (here == null) {
      setState(() => _error = 'We could not find your position. Turn on location for Nolifa Grow and stand on the farm.');
      return;
    }
    setState(() {
      _d['lat'] = here.$1;
      _d['lng'] = here.$2;
      _error = null;
    });
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
      await SupabaseBoot.client.rpc('submit_application');
      HapticFeedback.mediumImpact();
    } on PostgrestException catch (e) {
      _error = e.code == 'P0004' ? _missing(e.message) : friendlyError(e, doing: 'send your application');
    } catch (e) {
      _error = friendlyError(e, doing: 'send your application');
    }
    if (mounted) setState(() => _busy = false);
  }

  String _missing(String m) {
    const names = {
      'fullName': 'your full name', 'idNumber': 'your ID number', 'phone': 'your phone number', 'farmName': 'the farm name',
      'province': 'the province', 'lat': 'the farm location', 'lng': 'the farm location', 'sizeHa': 'the farm size',
      'farmKind': 'what you farm', 'consent': 'your agreement', 'photo:id_front': 'a photo of your ID',
      'photo:selfie_with_id': 'a selfie holding your ID', 'photo:land_photo': 'a photo of your land',
    };
    final raw = m.replaceFirst(RegExp(r'^.*Still missing: '), '').split(', ');
    final seen = <String>{};
    final out = [for (final k in raw) if (seen.add(names[k.trim()] ?? k.trim())) names[k.trim()] ?? k.trim()];
    return 'Still needed: ${out.join(', ')}.';
  }

  Widget _section(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: AppTheme.s6, bottom: AppTheme.s2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: AppTheme.title3),
          if (sub != null) Text(sub, style: AppTheme.footnote),
        ]),
      );

  Widget _field(String k, String label, IconData icon, {bool practice = false, TextInputType? type, String? Function(String?)? check, int lines = 1}) {
    final ctl = _ctl(k, practice: practice);
    if (lines > 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.s3),
        child: TextField(
          controller: ctl,
          maxLines: lines,
          enabled: !_locked,
          style: AppTheme.callout.copyWith(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: trn(label),
            labelStyle: AppTheme.caption,
            filled: true,
            fillColor: AppTheme.glassFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.rChip)),
          ),
        ),
      );
    }
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
            labelStyle: AppTheme.caption,
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

  Widget _chips(List<String> all, List<String> on, void Function(String) toggle) => Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
        for (final o in all) FilterChip(label: Text(o), selected: on.contains(o), onSelected: _locked ? null : (_) => toggle(o)),
      ]);

  Widget _photoRow(String kind, String title, String hint, {bool selfie = false, bool multi = false}) {
    final n = _count(kind);
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.s4),
      child: Row(children: [
        Icon(n > 0 ? Icons.check_circle_rounded : Icons.photo_camera_rounded, color: n > 0 ? AppTheme.ok : AppTheme.textTertiary),
        const SizedBox(width: AppTheme.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTheme.headline),
            Text(n > 0 ? (multi ? '$n added' : 'Added') : hint, style: AppTheme.footnote),
          ]),
        ),
        if (!_locked) GhostButton(label: n > 0 ? (multi ? 'Add more' : 'Retake') : 'Take photo', onPressed: _busy ? null : () => _photo(kind, selfie: selfie)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appAsync = ref.watch(applicationProvider);
    final app = appAsync.valueOrNull;
    if (appAsync.hasValue) _hydrate(app);
    final status = app?['status'] as String? ?? 'draft';
    final note = app?['review_note'] as String? ?? '';
    final idRes = checkSaId('${_d['idNumber'] ?? ''}');
    final livestock = _d['farmKind'] == 'livestock' || _d['farmKind'] == 'both';
    final crops = _d['farmKind'] == 'crops' || _d['farmKind'] == 'both';

    Widget banner() => switch (status) {
          'submitted' => GlassCard(tint: AppTheme.warn.withValues(alpha: 0.12), child: Text('With Nolifa for review. We will message you. You cannot change it while we look.', style: AppTheme.callout)),
          'approved' => GlassCard(tint: AppTheme.ok.withValues(alpha: 0.12), child: Text('Approved. Your farm is verified and buyers see your farm profile.', style: AppTheme.callout)),
          'needs_info' => GlassCard(tint: AppTheme.warn.withValues(alpha: 0.12), child: Text('We need a bit more from you: $note', style: AppTheme.callout)),
          'rejected' => GlassCard(tint: AppTheme.danger.withValues(alpha: 0.12), child: Text('Not approved: $note', style: AppTheme.callout)),
          _ => const SizedBox.shrink(),
        };

    return Scaffold(
      body: AppBackdrop(
        tint: AppTheme.sprout,
        child: SafeArea(
          child: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: const GlassBar(),
              leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
              title: const Text('Farm application'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
              sliver: SliverList.list(children: [
                Text('Get verified to sell', style: AppTheme.title1),
                const SizedBox(height: AppTheme.s1),
                Text('Buyers trust farms that Nolifa has checked. This also builds your farm profile on Nolifa Drop and helps our vets understand how you farm. Staff read it. Your ID and photos are never shown to buyers.', style: AppTheme.callout),
                const SizedBox(height: AppTheme.s3),
                banner(),
                _section('1. Who you are', 'Exactly as on your ID.'),
                _field('fullName', 'Full name and surname', Icons.person_rounded),
                _field('idNumber', 'South African ID number', Icons.badge_rounded, type: TextInputType.number, check: (_) => idRes.ok ? null : idRes.message),
                _field('phone', 'Mobile number', Icons.phone_rounded, type: TextInputType.phone, check: (v) => checkSaPhone(v ?? '')),
                _section('2. Your business'),
                Wrap(spacing: AppTheme.s2, children: [
                  for (final k in const ['individual', 'cooperative', 'company'])
                    ChoiceChip(label: Text(k), selected: (_d['kind'] ?? 'individual') == k, onSelected: _locked ? null : (_) => _set('kind', k)),
                ]),
                const SizedBox(height: AppTheme.s3),
                _field('businessName', 'Registered business name (if any)', Icons.business_rounded),
                _field('regNumber', 'CIPC registration number (if any)', Icons.numbers_rounded, check: (v) => checkCompanyNumber(v ?? '')),
                _section('3. The farm'),
                _field('farmName', 'Farm or trading name', Icons.agriculture_rounded),
                DropdownButtonFormField<String>(
                  initialValue: provinces.contains(_d['province']) ? _d['province'] as String : null,
                  decoration: InputDecoration(labelText: tr('Province'), filled: true, fillColor: AppTheme.glassFill, border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.rChip))),
                  items: [for (final p in provinces) DropdownMenuItem(value: p, child: Text(p))],
                  onChanged: _locked ? null : (v) => _set('province', v),
                ),
                const SizedBox(height: AppTheme.s3),
                _field('town', 'Nearest town', Icons.location_city_rounded),
                _field('sizeHa', 'Size of the farm in hectares', Icons.square_foot_rounded, type: const TextInputType.numberWithOptions(decimal: true)),
                Wrap(spacing: AppTheme.s2, children: [
                  for (final t in const [('own', 'I own the land'), ('lease', 'I lease it'), ('communal', 'Communal or permission to occupy')])
                    ChoiceChip(label: Text(t.$2), selected: _d['tenure'] == t.$1, onSelected: _locked ? null : (_) => _set('tenure', t.$1)),
                ]),
                const SizedBox(height: AppTheme.s3),
                GlassCard(
                  padding: const EdgeInsets.all(AppTheme.s4),
                  child: Row(children: [
                    Icon(_d['lat'] != null ? Icons.check_circle_rounded : Icons.pin_drop_rounded, color: _d['lat'] != null ? AppTheme.ok : AppTheme.textTertiary),
                    const SizedBox(width: AppTheme.s3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Farm location', style: AppTheme.headline),
                        Text(_d['lat'] != null ? '${(_d['lat'] as num).toStringAsFixed(5)}, ${(_d['lng'] as num).toStringAsFixed(5)}' : 'Stand on the farm and tap the button.', style: AppTheme.footnote),
                      ]),
                    ),
                    if (!_locked) GhostButton(label: 'Use my position', onPressed: _locate),
                  ]),
                ),
                _section('4. What you sell'),
                _chips(_sells, _products, (o) => setState(() => _products.contains(o) ? _products.remove(o) : _products.add(o))),
                const SizedBox(height: AppTheme.s3),
                Wrap(spacing: AppTheme.s2, children: [
                  for (final t in const [('livestock', 'Livestock'), ('crops', 'Crops'), ('both', 'Both')])
                    ChoiceChip(label: Text(t.$2), selected: _d['farmKind'] == t.$1, onSelected: _locked ? null : (_) => _set('farmKind', t.$1)),
                ]),
                if (livestock) ...[
                  _section('5. How you look after your animals', 'Our vets read this to understand your farm. Be honest: it helps them help you.'),
                  Text('What do they eat?', style: AppTheme.footnote),
                  const SizedBox(height: AppTheme.s2),
                  _chips(_feeds, [for (final f in ((_p['feeds'] as List?) ?? const [])) '$f'], (o) {
                    final cur = [for (final f in ((_p['feeds'] as List?) ?? const [])) '$f'];
                    cur.contains(o) ? cur.remove(o) : cur.add(o);
                    _practice('feeds', cur);
                  }),
                  const SizedBox(height: AppTheme.s3),
                  _field('feedNotes', 'Feed in detail: brands, amounts, how often', Icons.grass_rounded, practice: true, lines: 3),
                  _field('waterSource', 'Where do they drink? (borehole, dam, river, trough)', Icons.water_drop_rounded, practice: true),
                  _field('housing', 'Camps, kraals, shelter and shade', Icons.fence_rounded, practice: true),
                  _field('vaccineProgramme', 'Vaccines you give and how often', Icons.vaccines_rounded, practice: true, lines: 2),
                  _field('dewormFreq', 'Deworming and dipping, how often', Icons.bug_report_rounded, practice: true),
                  _field('vetName', 'Which vet do you use? (name and town)', Icons.medical_services_rounded, practice: true),
                  _field('quarantine', 'Do you isolate new or sick animals? How?', Icons.health_and_safety_rounded, practice: true),
                  _field('records', 'How do you keep records? (ear tags, books, app)', Icons.menu_book_rounded, practice: true),
                ],
                if (crops) ...[
                  _section(livestock ? '6. How you grow your crops' : '5. How you grow your crops'),
                  _field('irrigation', 'Irrigation and water source', Icons.water_rounded, practice: true),
                  _field('cropInputs', 'Fertiliser, sprays and seed you use', Icons.science_rounded, practice: true, lines: 2),
                  _field('harvest', 'How you harvest, wash, pack and store', Icons.inventory_2_rounded, practice: true, lines: 2),
                ],
                _section('Photos', 'Taken with the camera now. Staff compare the ID with the selfie.'),
                _photoRow('id_front', 'Photo of your ID', 'The front of your ID card or the photo page of your smart card, in good light.'),
                const SizedBox(height: AppTheme.s2),
                _photoRow('selfie_with_id', 'Selfie holding your ID', 'Hold the ID next to your face so both can be seen.', selfie: true),
                const SizedBox(height: AppTheme.s2),
                _photoRow('land_photo', 'Your land', 'Your field, camps or buildings. More than one is better.', multi: true),
                const SizedBox(height: AppTheme.s2),
                _photoRow('certificate', 'Certificates and papers', 'Title deed or lease or PTO letter, brand or livestock owner registration, animal health certificate or vet letter, food safety papers if you have them.', multi: true),
                const SizedBox(height: AppTheme.s4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _d['consent'] == true,
                  onChanged: _locked ? null : (v) => _set('consent', v == true),
                  title: Text('Everything here is true. Nolifa may check it, keep my ID and photos safely for verification under POPIA, and share my farm profile (not my ID) with buyers and vets.', style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary)),
                ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: AppTheme.s2), child: Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger))),
                if (_saved != null && _error == null) Padding(padding: const EdgeInsets.only(top: AppTheme.s2), child: Text(_saved!, style: AppTheme.footnote.copyWith(color: AppTheme.ok))),
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
