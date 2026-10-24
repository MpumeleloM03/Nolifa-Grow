import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, friendlyError;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:video_player/video_player.dart';
import '../models/cattle.dart';
import '../services/cattle_service.dart';
import '../screens/livestock/symptom_checker_screen.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'members_service.dart';
import 'membership_screen.dart';

const _maxSeconds = 120;

Widget _frame(BuildContext context, String title, List<Widget> children) => Scaffold(
      body: AppBackdrop(
        tint: AppTheme.livestockAccent,
        child: SafeArea(
          child: CustomScrollView(slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: const GlassBar(),
              leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
              title: Text(title),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppTheme.s6, AppTheme.s2, AppTheme.s6, AppTheme.s10),
              sliver: SliverList.list(children: children),
            ),
          ]),
        ),
      ),
    );

/// Your vet cases. Locked until there is an active membership.
class VetHomeScreen extends ConsumerWidget {
  const VetHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(membershipProvider);
    final cases = ref.watch(consultsProvider);
    final left = ref.watch(videosLeftProvider).valueOrNull;
    final active = m.valueOrNull?.active ?? false;
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    return _frame(context, 'Ask a vet', [
      Text('A vet looks at your animal', style: AppTheme.title1),
      const SizedBox(height: AppTheme.s1),
      Text('Words alone cannot tell a vet what is wrong. Film the animal, and a vet will watch it, say what they think it is and why, and tell you what to do.',
          style: AppTheme.callout),
      const SizedBox(height: AppTheme.s4),
      if (m.isLoading)
        const Center(child: CircularProgressIndicator())
      else if (!active) ...[
        GlassCard(
          tint: AppTheme.warn.withValues(alpha: 0.10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.valueOrNull?.awaitingPayment == true ? 'Your membership is waiting for payment' : 'Vet videos are for members', style: AppTheme.headline),
            const SizedBox(height: AppTheme.s1),
            Text(
                m.valueOrNull?.awaitingPayment == true
                    ? 'It switches on as soon as Nolifa confirms your first payment.'
                    : 'Members send up to 4 videos a month (R3 000), or 15 and an on-site vet visit (Max, R7 000). Membership is 24 months.',
                style: AppTheme.footnote),
            const SizedBox(height: AppTheme.s3),
            GlassButton(label: 'See membership', icon: Icons.verified_rounded, onPressed: () => go(const MembershipScreen())),
          ]),
        ),
      ] else ...[
        GlassButton(
          label: left == 0 ? 'No videos left this month' : 'Send a new video${left == null ? '' : ' ($left left this month)'}',
          icon: Icons.videocam_rounded,
          onPressed: left == 0 ? null : () => go(const NewConsultScreen()),
        ),
      ],
      const SizedBox(height: AppTheme.s4),
      GlassCard(
        padding: const EdgeInsets.all(AppTheme.s4),
        onTap: () => go(const SymptomCheckerScreen()),
        child: Row(children: [
          const Icon(Icons.checklist_rounded),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Quick check while you wait', style: AppTheme.headline),
              Text('Tick the signs you see. It flags controlled diseases and emergencies first. It is guidance, not a diagnosis.', style: AppTheme.footnote),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
        ]),
      ),
      const SizedBox(height: AppTheme.s5),
      Text('Your cases', style: AppTheme.title3),
      const SizedBox(height: AppTheme.s2),
      cases.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text(friendlyError(e, doing: 'load your cases'), style: AppTheme.callout),
        data: (list) => list.isEmpty
            ? Text('No cases yet.', style: AppTheme.footnote)
            : Column(children: [
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s2),
                    child: GlassCard(
                      padding: const EdgeInsets.all(AppTheme.s4),
                      onTap: () => go(ConsultScreen(c.id)),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.title, style: AppTheme.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('${c.animalLabel.isEmpty ? c.species : c.animalLabel}  ·  ${c.statusLabel}', style: AppTheme.footnote),
                          ]),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
                      ]),
                    ),
                  ),
              ]),
      ),
    ]);
  }
}

/// Pick an animal, say what you see, film it, send it.
class NewConsultScreen extends ConsumerStatefulWidget {
  const NewConsultScreen({super.key});

  @override
  ConsumerState<NewConsultScreen> createState() => _NewConsultState();
}

class _NewConsultState extends ConsumerState<NewConsultScreen> {
  final _title = TextEditingController();
  final _what = TextEditingController();
  Cattle? _animal;
  final _files = <(File, int)>[]; // file, seconds
  bool _busy = false;
  String? _error;
  String _step = '';

  @override
  void dispose() {
    _title.dispose();
    _what.dispose();
    super.dispose();
  }

  Future<void> _add(ImageSource src) async {
    try {
      final x = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(seconds: _maxSeconds));
      if (x == null) return;
      final f = File(x.path);
      final vc = VideoPlayerController.file(f);
      await vc.initialize();
      final secs = vc.value.duration.inSeconds.clamp(1, 100000);
      await vc.dispose();
      if (secs > _maxSeconds) {
        setState(() => _error = 'That video is ${secs ~/ 60} min ${secs % 60} s. The limit is 2 minutes. Pick a shorter one.');
        return;
      }
      setState(() {
        _files.add((f, secs));
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'We could not read that video. Try filming it again.');
    }
  }

  Future<void> _send() async {
    if (_title.text.trim().length < 3) {
      setState(() => _error = 'Give the case a short title, like "Limping cow".');
      return;
    }
    if (_files.isEmpty) {
      setState(() => _error = 'Add at least one video.');
      return;
    }
    final left = ref.read(videosLeftProvider).valueOrNull ?? 0;
    if (_files.length > left) {
      setState(() => _error = 'You have $left videos left this month. Remove ${_files.length - left}.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _step = 'Opening your case';
    });
    final db = SupabaseBoot.client;
    try {
      final id = await db.rpc('open_consult', params: {
        'p_title': _title.text.trim(),
        'p_description': _what.text.trim(),
        'p_animal_id': _animal?.id,
        'p_animal_label': _animal?.label ?? '',
        'p_species': _animal?.species.singular ?? '',
      }) as String;
      final uid = db.auth.currentUser!.id;
      for (var i = 0; i < _files.length; i++) {
        setState(() => _step = 'Uploading video ${i + 1} of ${_files.length}. On mobile data this can take a few minutes.');
        final (f, secs) = _files[i];
        final path = '$uid/$id/${DateTime.now().millisecondsSinceEpoch}-$i.mp4';
        await db.storage.from('consult-videos').upload(path, f, fileOptions: const FileOptions(contentType: 'video/mp4'));
        await db.from('consult_videos').insert({'consult_id': id, 'farmer_id': uid, 'path': path, 'duration_s': secs, 'bytes': await f.length()});
      }
      ref.invalidate(videosLeftProvider);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ConsultScreen(id)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, doing: 'send your video');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final herd = ref.watch(herdProvider).valueOrNull ?? const <Cattle>[];
    final active = [for (final c in herd) if (c.status == CattleStatus.active) c];
    return _frame(context, 'New vet video', [
      Text('Which animal?', style: AppTheme.headline),
      const SizedBox(height: AppTheme.s2),
      Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
        for (final c in active)
          ChoiceChip(label: Text('${c.species.emoji} ${c.label}'), selected: _animal?.id == c.id, onSelected: (_) => setState(() => _animal = _animal?.id == c.id ? null : c)),
        if (active.isEmpty) Text('Add animals to your herd to pick one, or just describe it below.', style: AppTheme.footnote),
      ]),
      const SizedBox(height: AppTheme.s4),
      GlassField(controller: _title, label: 'Short title, like "Limping cow"', icon: Icons.title_rounded),
      const SizedBox(height: AppTheme.s3),
      TextField(
        controller: _what,
        maxLines: 4,
        maxLength: 1000,
        style: AppTheme.callout.copyWith(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'What have you noticed, since when, what has it eaten, any treatment so far?',
          hintStyle: AppTheme.caption,
          filled: true,
          fillColor: AppTheme.glassFill,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.rChip)),
        ),
      ),
      const SizedBox(height: AppTheme.s3),
      Text('Videos (up to 2 minutes each)', style: AppTheme.headline),
      Text('Show the whole animal walking, then close up of the problem, then how it eats and drinks. Good light helps.', style: AppTheme.footnote),
      const SizedBox(height: AppTheme.s2),
      for (var i = 0; i < _files.length; i++)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.movie_rounded),
          title: Text('Video ${i + 1}  ·  ${_files[i].$2} seconds'),
          trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _busy ? null : () => setState(() => _files.removeAt(i))),
        ),
      Row(children: [
        Expanded(child: GhostButton(label: 'Film now', icon: Icons.videocam_rounded, onPressed: _busy ? null : () => _add(ImageSource.camera))),
        const SizedBox(width: AppTheme.s2),
        Expanded(child: GhostButton(label: 'From gallery', icon: Icons.video_library_rounded, onPressed: _busy ? null : () => _add(ImageSource.gallery))),
      ]),
      if (_error != null) ...[
        const SizedBox(height: AppTheme.s3),
        Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
      ],
      if (_busy) ...[
        const SizedBox(height: AppTheme.s3),
        const LinearProgressIndicator(),
        const SizedBox(height: AppTheme.s1),
        Text(_step, style: AppTheme.footnote),
      ],
      const SizedBox(height: AppTheme.s4),
      GlassButton(label: 'Send to the vet', icon: Icons.send_rounded, onPressed: _busy ? null : _send),
    ]);
  }
}

/// One case: the vet's diagnosis, the chat, and the on-site visit.
class ConsultScreen extends ConsumerStatefulWidget {
  final String id;
  const ConsultScreen(this.id, {super.key});

  @override
  ConsumerState<ConsultScreen> createState() => _ConsultScreenState();
}

class _ConsultScreenState extends ConsumerState<ConsultScreen> {
  final _msg = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _msg.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await SupabaseBoot.client.rpc('send_consult_message', params: {'p_consult': widget.id, 'p_body': t});
      _msg.clear();
    } catch (e) {
      _error = friendlyError(e, doing: 'send that');
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _visit() async {
    final when = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 2)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      helpText: 'Best day for the vet to visit',
    );
    if (when == null || !mounted) return;
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.sheet,
        title: Text('Request a farm visit', style: AppTheme.title3),
        content: TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(hintText: 'Where to find you, gate codes, which animals')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Request')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseBoot.client.rpc('request_vet_visit', params: {
        'p_consult': widget.id,
        'p_preferred': '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}',
        'p_notes': notes.text.trim(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visit requested. The vet will confirm a day.'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().contains('P0003') || '$e'.contains('partner vet') ? 'We do not have a partner vet in your area yet. Right now we cover KwaZulu-Natal.' : friendlyError(e, doing: 'request a visit'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(consultsProvider).valueOrNull?.where((x) => x.id == widget.id).firstOrNull;
    final chat = ref.watch(consultChatProvider(widget.id));
    final tier = ref.watch(membershipProvider).valueOrNull;
    if (c == null) return _frame(context, 'Case', [const Center(child: CircularProgressIndicator())]);
    final d = c.diagnosis;
    return _frame(context, c.title, [
      Wrap(spacing: AppTheme.s2, children: [
        Chip(label: Text(c.statusLabel)),
        if (c.animalLabel.isNotEmpty) Chip(label: Text(c.animalLabel)),
      ]),
      if (c.description.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: AppTheme.s2), child: Text(c.description, style: AppTheme.callout)),
      ref.watch(consultVideosProvider(c.id)).maybeWhen(
            data: (v) => Text('${v.length} video${v.length == 1 ? '' : 's'} sent', style: AppTheme.footnote),
            orElse: () => const SizedBox.shrink(),
          ),
      const SizedBox(height: AppTheme.s3),
      if (d == null)
        GlassCard(child: Text('A vet will look at your video and write back here. Check this case for the answer. Push alerts for replies are not built yet.', style: AppTheme.callout))
      else
        GlassCard(
          tint: AppTheme.ok.withValues(alpha: 0.10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('The vet\'s diagnosis', style: AppTheme.headline),
            const SizedBox(height: AppTheme.s2),
            _line('What they think it is', d['suspected']),
            _line('Why they think so', d['why']),
            _line('What to do', d['remedy']),
            _line('How that helps', d['howItHelps']),
            if ((d['handling'] ?? '').toString().isNotEmpty) _line('Handling and care', d['handling']),
            if ((d['urgency'] ?? '').toString().isNotEmpty) _line('How urgent', d['urgency']),
            const SizedBox(height: AppTheme.s2),
            Text('This is a remote opinion from a video. If the animal gets worse, call a vet to see it in person.', style: AppTheme.caption),
          ]),
        ),
      const SizedBox(height: AppTheme.s4),
      if (tier?.tier.vetVisits == true && c.status != 'closed' && c.status != 'visit_requested' && c.status != 'visit_booked')
        GhostButton(label: 'Ask the vet to visit the farm', icon: Icons.home_work_rounded, onPressed: _visit),
      if (c.status == 'visit_requested') Text('Visit requested. The vet will confirm a day in the chat.', style: AppTheme.footnote),
      if (c.status == 'visit_booked') Text('Visit booked for ${c.visit?['bookedFor'] ?? ''}. ${c.visit?['vetNote'] ?? ''}', style: AppTheme.callout),
      if (tier?.tier.vetVisits != true && c.status != 'closed')
        Text('On-site visits are part of the Max membership.', style: AppTheme.caption),
      const SizedBox(height: AppTheme.s5),
      Text('Chat with the vet', style: AppTheme.title3),
      const SizedBox(height: AppTheme.s2),
      chat.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text(friendlyError(e, doing: 'load the chat'), style: AppTheme.footnote),
        data: (lines) => Column(children: [
          for (final l in lines)
            Align(
              alignment: l.role == 'farmer' ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: AppTheme.s2),
                padding: const EdgeInsets.all(AppTheme.s3),
                constraints: const BoxConstraints(maxWidth: 300),
                decoration: BoxDecoration(
                  color: (l.role == 'farmer' ? AppTheme.sprout : AppTheme.glassFill).withValues(alpha: l.role == 'farmer' ? 0.2 : 1),
                  borderRadius: BorderRadius.circular(AppTheme.rChip),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.role == 'vet' ? 'Vet' : 'You', style: AppTheme.caption),
                  Text(l.body, style: AppTheme.callout.copyWith(color: AppTheme.textPrimary)),
                ]),
              ),
            ),
          if (lines.isEmpty) Text('No messages yet.', style: AppTheme.footnote),
        ]),
      ),
      if (c.status != 'closed') ...[
        Row(children: [
          Expanded(child: GlassField(controller: _msg, label: 'Message the vet', icon: Icons.chat_bubble_outline_rounded, onSubmitted: (_) => _send())),
          IconButton(onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded)),
        ]),
        if (_error != null) Text(_error!, style: AppTheme.footnote.copyWith(color: AppTheme.danger)),
      ],
    ]);
  }

  Widget _line(String k, Object? v) => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.s2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: AppTheme.caption),
          Text('${v ?? ''}', style: AppTheme.callout.copyWith(color: AppTheme.textPrimary)),
        ]),
      );
}
