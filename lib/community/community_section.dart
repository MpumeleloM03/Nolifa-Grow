import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show BusinessScreen, IncidentStage, IncidentStageX, Pill, marketProvider, waterProvider;
import '../models/livestock_disease.dart';
import '../services/auth_service.dart';
import '../services/crop_scan.dart';
import '../services/proof_photo.dart';
import '../store/store_common.dart' show SheetFrame, timeAgo;
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'community_store.dart';
import 'proof_post.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// How the share sheet gets a proof photo and a crop scan. Tests replace them.
final proofPickerProvider = Provider<Future<File?> Function()>((ref) => pickProofPhoto);
final cropCaptureProvider = Provider<Future<CropScanResult?> Function(BuildContext, WidgetRef)>(
    (ref) => (context, ref) => captureCrop(context, ref, addToMap: false));

Color _sev(String s) => switch (s) { 'red' => AppTheme.danger, 'orange' => AppTheme.warn, _ => AppTheme.ok };
String _sevLabel(String s) => switch (s) { 'red' => 'Urgent', 'orange' => 'Watch', _ => 'Low' };

/// The community on the Alerts page. Nothing here is just talk: each post
/// carries a photo and, for crops and livestock, an AI check done on the phone.
class CommunitySection extends ConsumerStatefulWidget {
  const CommunitySection({super.key});

  @override
  ConsumerState<CommunitySection> createState() => _CommunitySectionState();
}

class _CommunitySectionState extends ConsumerState<CommunitySection> {
  FeedFilter _filter = FeedFilter.both;

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(marketProvider.select((s) => s.demoMode));
    final region = ref.watch(currentUserProvider)?.region ?? '';
    var posts = ref.watch(communityStoreProvider).where((p) => demo || !p.demo).where((p) => _filter.matches(p.topic));
    var ranked = rankPosts(posts);
    if (_filter == FeedFilter.water) {
      // Reports from the farmer's own area come first.
      ranked = [...ranked.where((p) => p.region == region), ...ranked.where((p) => p.region != region)];
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('🗣️', style: TextStyle(fontSize: 20)),
        const SizedBox(width: AppTheme.s2),
        Expanded(child: Text('Community', style: AppTheme.title3)),
      ]),
      const SizedBox(height: AppTheme.s1),
      Text('Every post is backed by proof: a photo you took and an AI check on your phone.',
          style: AppTheme.footnote),
      const SizedBox(height: AppTheme.s3),
      Wrap(spacing: AppTheme.s2, runSpacing: AppTheme.s2, children: [
        for (final f in FeedFilter.values)
          ChoiceChip(
            label: Text(f.label),
            selected: _filter == f,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              setState(() => _filter = f);
            },
          ),
      ]),
      const SizedBox(height: AppTheme.s3),
      GlassButton(
        label: 'Share proof with your area',
        icon: Icons.add_a_photo_rounded,
        onPressed: () => showShareProof(context),
      ),
      const SizedBox(height: AppTheme.s3),
      if (_filter == FeedFilter.water) const _MunicipalUpdates(),
      if (ranked.isEmpty)
        GlassCard(
          child: Text(
              _filter == FeedFilter.water
                  ? 'No water reports yet. Take a photo of your tank or tap and share it.'
                  : 'Nothing here yet. Scan something and share it so neighbours can prepare.',
              style: AppTheme.callout),
        )
      else
        for (final p in ranked)
          Padding(padding: const EdgeInsets.only(bottom: AppTheme.s3), child: _PostCard(p, region)),
    ]);
  }
}

/// Replies from the water provider (the municipality), shown only when one has
/// answered a community's request. No answer means the box says so.
class _MunicipalUpdates extends ConsumerWidget {
  const _MunicipalUpdates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(waterProvider);
    final answered = [
      for (final i in w.incidents)
        if (i.stage == IncidentStage.acknowledged || i.stage == IncidentStage.dispatched) i
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.s3),
      child: GlassCard(
        tint: const Color(0xFF5AB8F0).withValues(alpha: 0.10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.account_balance_rounded, color: Color(0xFF5AB8F0)),
            const SizedBox(width: AppTheme.s2),
            Expanded(child: Text('From the municipality', style: AppTheme.headline)),
          ]),
          const SizedBox(height: AppTheme.s2),
          if (answered.isEmpty)
            Text(
                'No updates yet. When your municipality or water provider answers a community request, you see when help is coming here. Not every municipality helps farmers with water yet.',
                style: AppTheme.footnote)
          else
            for (final i in answered)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.s2),
                child: Builder(builder: (_) {
                  final zone = w.zones.where((z) => z.id == i.zoneId).firstOrNull;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${zone?.name ?? 'A community'}: ${i.stage.label}', style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary)),
                    Text(
                        '${zone?.provider ?? 'Provider'}${i.trucks > 0 ? ' • ${i.trucks} truck${i.trucks == 1 ? '' : 's'}' : ''}${i.etaMinutes > 0 ? ' • about ${i.etaMinutes} min' : ''}${i.note.isEmpty ? '' : '\n${i.note}'}',
                        style: AppTheme.footnote),
                  ]);
                }),
              ),
        ]),
      ),
    );
  }
}

class _PostCard extends ConsumerWidget {
  final ProofPost p;
  final String myRegion;
  const _PostCard(this.p, this.myRegion);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _sev(p.severity);
    final emoji = p.emoji ?? (p.topic == PostTopic.livestock ? '🐄' : p.topic == PostTopic.water ? '💧' : '🌿');
    return GlassCard(
      padding: EdgeInsets.zero,
      tint: p.urgent ? AppTheme.danger.withValues(alpha: 0.06) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The proof: the photo they took, or a stand-in on demo posts.
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: p.photoPath != null && File(p.photoPath!).existsSync()
                ? Image.file(File(p.photoPath!), fit: BoxFit.cover)
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [color.withValues(alpha: 0.35), AppTheme.surface],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: const TextStyle(fontSize: 64)),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppTheme.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${p.author}  •  ${p.region == myRegion ? 'your area' : p.region}  •  ${timeAgo(p.at)}',
                    style: AppTheme.caption),
              ),
              Pill(_sevLabel(p.severity), color: color),
            ]),
            const SizedBox(height: AppTheme.s2),
            Text(p.headline, style: AppTheme.headline),
            if (p.detail.isNotEmpty) ...[
              const SizedBox(height: AppTheme.s1),
              Text(p.detail, style: AppTheme.callout),
            ],
            const SizedBox(height: AppTheme.s3),
            Container(
              padding: const EdgeInsets.all(AppTheme.s3),
              decoration: BoxDecoration(
                color: AppTheme.glassFill,
                borderRadius: BorderRadius.circular(AppTheme.rControl),
                border: Border.all(color: AppTheme.glassBorderSoft),
              ),
              child: Row(children: [
                Icon(
                    p.proof == ProofKind.photoOnly ? Icons.photo_camera_rounded : Icons.verified_rounded,
                    size: 18,
                    color: AppTheme.sprout),
                const SizedBox(width: AppTheme.s2),
                Expanded(child: Text(p.aiSummary, style: AppTheme.footnote.copyWith(color: AppTheme.textPrimary))),
              ]),
            ),
            const SizedBox(height: AppTheme.s3),
            Row(children: [
              GestureDetector(
                onTap: p.iConfirmed ? null : () {
                  HapticFeedback.lightImpact();
                  if (!ref.read(marketProvider).canConfirmOutbreaks) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Only verified farmers can confirm a post, so reports cannot be faked.'),
                      action: SnackBarAction(
                        label: 'Verify',
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const BusinessScreen())),
                      ),
                    ));
                    return;
                  }
                  ref.read(communityStoreProvider.notifier).confirm(p.id);
                },
                child: Pill(p.iConfirmed ? 'You see this too' : 'I see this too',
                    color: p.iConfirmed ? AppTheme.sprout : AppTheme.livestockAccent,
                    icon: p.iConfirmed ? Icons.check_rounded : Icons.visibility_rounded),
              ),
              const SizedBox(width: AppTheme.s2),
              Text('${p.confirmations} neighbour${p.confirmations == 1 ? '' : 's'} confirmed', style: AppTheme.caption),
              if (p.demo) ...[const Spacer(), Text('Demo', style: AppTheme.caption)],
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ sharing

Future<void> showShareProof(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ShareSheet(),
    );

const _waterProblems = [
  ('No water at all', 'red'),
  ('Dirty or unsafe water', 'red'),
  ('Low pressure', 'orange'),
  ('Tanker came, thank you', 'green'),
  ('Borehole can help others', 'green'),
];

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet();

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  PostTopic _topic = PostTopic.crop;
  CropScanResult? _scan;
  File? _photo;
  final _symptoms = <String>{};
  int _water = 0;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<ConditionMatch> get _matches => LivestockDatabase.match(_symptoms);

  bool get _ready => switch (_topic) {
        PostTopic.crop => _scan != null,
        PostTopic.livestock => _photo != null && _matches.isNotEmpty,
        PostTopic.water => _photo != null,
      };

  Future<void> _post() async {
    final user = ref.read(currentUserProvider);
    final region = (user?.region.isNotEmpty ?? false) ? user!.region : 'Other';
    final author = (user?.name.trim().isNotEmpty ?? false) ? user!.name.trim().split(' ').first : 'Farmer';
    late final ProofPost post;
    final id = 'post-${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();
    switch (_topic) {
      case PostTopic.crop:
        final s = _scan!;
        post = ProofPost(
          id: id, uid: user?.uid ?? '', author: author, region: region, topic: PostTopic.crop,
          headline: s.plainName, detail: _note.text.trim(), severity: s.severity,
          proof: ProofKind.aiScan,
          aiSummary: 'Scanned on this phone: ${s.plainName}, ${s.confidence}% confidence${s.offline ? ' (offline)' : ''}',
          photoPath: s.image.path, at: now, confirmations: 0,
        );
      case PostTopic.livestock:
        final m = _matches.first;
        final sev = switch (m.condition.urgency) {
          Urgency.notifiable || Urgency.emergency => 'red',
          Urgency.soon => 'orange',
          Urgency.monitor => 'green',
        };
        post = ProofPost(
          id: id, uid: user?.uid ?? '', author: author, region: region, topic: PostTopic.livestock,
          headline: m.condition.name, detail: _note.text.trim(), severity: sev,
          proof: ProofKind.symptomCheck,
          aiSummary: 'Symptom check on this phone: ${m.condition.name}, ${(m.score * 100).round()}% match. ${m.condition.urgency.label}.',
          photoPath: _photo!.path, at: now,
        );
      case PostTopic.water:
        final w = _waterProblems[_water];
        post = ProofPost(
          id: id, uid: user?.uid ?? '', author: author, region: region, topic: PostTopic.water,
          headline: w.$1, detail: _note.text.trim(), severity: w.$2,
          proof: ProofKind.photoOnly, aiSummary: 'Photo taken at the source and attached',
          photoPath: _photo!.path, at: now,
        );
    }
    ref.read(communityStoreProvider.notifier).add(post);
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Shared with your area'), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    Widget photoRow(String label) => Row(children: [
          Expanded(
            child: GlassButton(
              label: _photo == null ? label : 'Retake photo',
              icon: Icons.photo_camera_rounded,
              onPressed: () async {
                final f = await ref.read(proofPickerProvider)();
                if (f != null) setState(() => _photo = f);
              },
            ),
          ),
          if (_photo != null) ...[
            const SizedBox(width: AppTheme.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_photo!, width: 52, height: 52, fit: BoxFit.cover),
            ),
          ],
        ]);

    return SheetFrame(
      title: 'Share proof',
      subtitle: 'No proof, no post. Your photo and the AI check go with it.',
      children: [
        Row(children: [
          for (final t in PostTopic.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: AppTheme.s2),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _topic = t;
                    _photo = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: AppTheme.s3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _topic == t ? AppTheme.sprout : AppTheme.glassFill,
                      borderRadius: BorderRadius.circular(AppTheme.rControl),
                      border: Border.all(color: _topic == t ? AppTheme.sprout : AppTheme.glassBorder),
                    ),
                    child: Text(
                        switch (t) { PostTopic.crop => '🌿 Crop', PostTopic.livestock => '🐄 Animal', PostTopic.water => '💧 Water' },
                        style: AppTheme.subhead.copyWith(
                            color: _topic == t ? AppTheme.onAccent : AppTheme.textPrimary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: AppTheme.s3),
        if (_topic == PostTopic.crop) ...[
          GlassButton(
            label: _scan == null ? 'Scan a leaf with the AI' : 'Scan again',
            icon: Icons.document_scanner_rounded,
            onPressed: () async {
              final r = await ref.read(cropCaptureProvider)(context, ref);
              if (r != null && mounted) setState(() => _scan = r);
            },
          ),
          if (_scan != null) ...[
            const SizedBox(height: AppTheme.s3),
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_scan!.image, width: 64, height: 64, fit: BoxFit.cover),
              ),
              const SizedBox(width: AppTheme.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_scan!.plainName, style: AppTheme.headline),
                  Text('${_scan!.confidence}% confidence on this phone', style: AppTheme.footnote),
                ]),
              ),
              Pill(_sevLabel(_scan!.severity), color: _sev(_scan!.severity)),
            ]),
          ],
        ],
        if (_topic == PostTopic.livestock) ...[
          Text('What do you see?', style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s1),
          Wrap(spacing: AppTheme.s2, children: [
            for (final s in LivestockDatabase.symptoms)
              FilterChip(
                label: Text(s.label),
                selected: _symptoms.contains(s.id),
                onSelected: (on) => setState(() => on ? _symptoms.add(s.id) : _symptoms.remove(s.id)),
              ),
          ]),
          if (_matches.isNotEmpty) ...[
            const SizedBox(height: AppTheme.s3),
            GlassCard(
              radius: AppTheme.rControl,
              padding: const EdgeInsets.all(AppTheme.s3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Best match: ${_matches.first.condition.name}', style: AppTheme.headline),
                Text(_matches.first.condition.urgency.label, style: AppTheme.footnote),
              ]),
            ),
          ],
          const SizedBox(height: AppTheme.s3),
          photoRow('Take a photo of the animal'),
        ],
        if (_topic == PostTopic.water) ...[
          Wrap(spacing: AppTheme.s2, children: [
            for (var i = 0; i < _waterProblems.length; i++)
              ChoiceChip(
                label: Text(_waterProblems[i].$1),
                selected: _water == i,
                onSelected: (_) => setState(() => _water = i),
              ),
          ]),
          const SizedBox(height: AppTheme.s3),
          photoRow('Take a photo of the tank or tap'),
        ],
        const SizedBox(height: AppTheme.s3),
        GlassField(controller: _note, label: 'Add a note (optional)', icon: Icons.notes_rounded),
        const SizedBox(height: AppTheme.s3),
        GlassButton(label: 'Post to my area', icon: Icons.send_rounded, onPressed: _ready ? _post : null),
        if (!_ready)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.s2),
            child: Text(
                switch (_topic) {
                  PostTopic.crop => 'Scan a leaf first. The result is the proof.',
                  PostTopic.livestock => 'Pick the symptoms and take a photo to post.',
                  PostTopic.water => 'Take a photo to post.',
                },
                style: AppTheme.caption),
          ),
      ],
    );
  }
}
