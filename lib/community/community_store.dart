import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecurePrefs;
import '../services/auth_service.dart';
import 'proof_post.dart';

/// The community feed on this phone. With no backend it holds the farmer's own
/// posts plus a few neighbour posts marked as demo. A shared backend replaces
/// the storage, not the screens.
class CommunityStore extends Notifier<List<ProofPost>> {
  String get _key => 'community_${ref.read(currentUserProvider)?.uid ?? 'guest'}';
  Future<void> _ready = Future.value();

  @override
  List<ProofPost> build() {
    ref.watch(currentUserProvider.select((u) => u?.uid));
    _ready = _load();
    return const [];
  }

  Future<void> _load() async {
    final raw = await SecurePrefs.getString(_key);
    var saved = <ProofPost>[];
    if (raw != null) {
      try {
        saved = [for (final m in jsonDecode(raw) as List) ProofPost.fromJson(Map<String, dynamic>.from(m as Map))];
      } catch (_) {
        // Unreadable save: start clean rather than crash the page.
      }
    } else {
      saved = demoPosts(DateTime.now());
    }
    final ids = {for (final p in state) p.id};
    state = [...state, for (final p in saved) if (!ids.contains(p.id)) p];
    if (raw == null) await _save();
  }

  Future<void> _save() async {
    final key = _key; // read before awaiting: the store may be disposed by then
    final payload = jsonEncode([for (final p in state) p.toJson()]);
    await _ready;
    await SecurePrefs.setString(key, payload);
  }

  void add(ProofPost p) {
    state = [p, ...state];
    _save();
  }

  void confirm(String id) {
    state = [
      for (final p in state)
        if (p.id == id && !p.iConfirmed) p.copyWith(confirmations: p.confirmations + 1, iConfirmed: true) else p
    ];
    _save();
  }

  void remove(String id) {
    state = [for (final p in state) if (p.id != id) p];
    _save();
  }
}

final communityStoreProvider = NotifierProvider<CommunityStore, List<ProofPost>>(CommunityStore.new);

/// Neighbour posts that show how the feed reads. They are marked demo.
List<ProofPost> demoPosts(DateTime now) => [
      ProofPost(
        id: 'demo-1',
        uid: 'n1',
        author: 'Nomsa M.',
        region: 'KZN Midlands',
        topic: PostTopic.crop,
        headline: 'Late Blight on potatoes',
        detail: 'Spread over three rows since Monday after the rain.',
        severity: 'red',
        proof: ProofKind.aiScan,
        aiSummary: 'Scanned on her phone: Late Blight, 91% confidence',
        emoji: '🥔',
        at: now.subtract(const Duration(hours: 5)),
        confirmations: 6,
        demo: true,
      ),
      ProofPost(
        id: 'demo-2',
        uid: 'n2',
        author: 'Bheki D.',
        region: 'Zululand',
        topic: PostTopic.livestock,
        headline: 'Lumpy Skin Disease',
        detail: 'Four head with nodules on the neck. Isolated them and called the vet.',
        severity: 'red',
        proof: ProofKind.symptomCheck,
        aiSummary: 'Symptom check on his phone: Lumpy Skin Disease, strong match',
        emoji: '🐄',
        at: now.subtract(const Duration(hours: 9)),
        confirmations: 3,
        demo: true,
      ),
      ProofPost(
        id: 'demo-3',
        uid: 'n3',
        author: 'Thandi N.',
        region: 'Greater Durban',
        topic: PostTopic.water,
        headline: 'Low pressure, taps dry by evening',
        detail: 'Tank at a quarter. Borehole pump holding for the cattle.',
        severity: 'orange',
        proof: ProofKind.photoOnly,
        aiSummary: 'Photo of the tank gauge attached',
        emoji: '💧',
        at: now.subtract(const Duration(hours: 2)),
        confirmations: 11,
        demo: true,
      ),
      ProofPost(
        id: 'demo-4',
        uid: 'n4',
        author: 'Sipho K.',
        region: 'Greater Durban',
        topic: PostTopic.crop,
        headline: 'Fall armyworm on maize',
        detail: 'Found early. Sprayed this morning and will re-scan on Friday.',
        severity: 'orange',
        proof: ProofKind.aiScan,
        aiSummary: 'Scanned on his phone: armyworm damage, 84% confidence',
        emoji: '🌽',
        at: now.subtract(const Duration(hours: 20)),
        confirmations: 4,
        demo: true,
      ),
    ];
