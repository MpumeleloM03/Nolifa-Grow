import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import '../models/cattle.dart';
import '../models/chat_message.dart';
import '../models/outbreak_report.dart';
import '../models/outbreak_report.dart' show OutbreakKind;
import 'package:latlong2/latlong.dart';

/// On-device stand-in for Firebase, used whenever the cloud project is absent.
///
/// It keeps the app fully usable — you can sign up, chat, build a herd and
/// watch the map fill in — without a Firebase project existing. Everything
/// lives in SharedPreferences on this phone only, so nothing here is shared
/// between devices. The moment Firebase is configured, the services stop
/// calling into this and the real backend takes over.
class LocalBackend {
  LocalBackend._();
  static final LocalBackend instance = LocalBackend._();

  static const _kAccounts = 'local_accounts';
  static const _kSession = 'local_session';
  static const _kChat = 'local_chat';
  static const _kHerd = 'local_herd';
  static const _kOutbreaks = 'local_outbreaks';
  static const _kSeeded = 'local_seeded_v1';

  SharedPreferences? _prefs;

  final _session = StreamController<AppUser?>.broadcast();
  final _chat = StreamController<void>.broadcast();
  final _herd = StreamController<void>.broadcast();
  final _outbreaks = StreamController<void>.broadcast();

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> init() async {
    final p = await _p;
    if (!(p.getBool(_kSeeded) ?? false)) {
      await _seed(p);
      await p.setBool(_kSeeded, true);
    }
    _session.add(await currentUser());
  }

  // ── Accounts ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _accounts() async {
    final raw = (await _p).getString(_kAccounts);
    return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<AppUser?> currentUser() async {
    final uid = (await _p).getString(_kSession);
    if (uid == null) return null;
    final acc = await _accounts();
    final data = acc[uid];
    return data == null ? null : AppUser.fromMap(Map<String, dynamic>.from(data));
  }

  Stream<AppUser?> watchSession() async* {
    yield await currentUser();
    yield* _session.stream;
  }

  Future<AppUser> signUp({
    required String name,
    required String email,
    required String region,
    required String farmType,
  }) async {
    final p = await _p;
    final acc = await _accounts();
    final key = email.trim().toLowerCase();

    if (acc.values.any((v) => (v['email'] as String?)?.toLowerCase() == key)) {
      throw Exception('An account already exists for that email.');
    }

    final user = AppUser(
      uid: 'local-${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      email: email.trim(),
      region: region,
      farmType: farmType,
    );
    acc[user.uid] = user.toMap();
    await p.setString(_kAccounts, jsonEncode(acc));
    await p.setString(_kSession, user.uid);
    _session.add(user);
    return user;
  }

  /// Passwords are not checked in local mode — there is no secure store on
  /// device to check them against, and pretending otherwise would imply a
  /// protection this mode does not offer.
  Future<AppUser> signIn(String email) async {
    final acc = await _accounts();
    final key = email.trim().toLowerCase();
    final match = acc.entries.firstWhere(
      (e) => (e.value['email'] as String?)?.toLowerCase() == key,
      orElse: () => throw Exception('No local account for that email. Create one first.'),
    );
    final user = AppUser.fromMap(Map<String, dynamic>.from(match.value));
    await (await _p).setString(_kSession, user.uid);
    _session.add(user);
    return user;
  }

  Future<void> signOut() async {
    await (await _p).remove(_kSession);
    _session.add(null);
  }

  // ── Chat ──────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _rawChat() async {
    final raw = (await _p).getString(_kChat);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Stream<List<ChatMessage>> watchChat(String region) async* {
    yield await _chatFor(region);
    yield* _chat.stream.asyncMap((_) => _chatFor(region));
  }

  Future<List<ChatMessage>> _chatFor(String region) async {
    final all = await _rawChat();
    final mine = all.where((m) => m['region'] == region).toList()
      ..sort((a, b) => (b['at'] as int).compareTo(a['at'] as int));
    return mine
        .map((m) => ChatMessage(
              id: m['id'] as String,
              uid: m['uid'] as String,
              authorName: m['authorName'] as String,
              text: m['text'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
              kind: m['kind'] as String,
            ))
        .toList();
  }

  Future<void> sendChat({
    required String region,
    required String uid,
    required String authorName,
    required String text,
    required String kind,
  }) async {
    final all = await _rawChat();
    all.add({
      'id': 'm${DateTime.now().microsecondsSinceEpoch}',
      'region': region,
      'uid': uid,
      'authorName': authorName,
      'text': text,
      'kind': kind,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    await (await _p).setString(_kChat, jsonEncode(all));
    _chat.add(null);
  }

  // ── Herd ──────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _rawHerd() async {
    final raw = (await _p).getString(_kHerd);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Stream<List<Cattle>> watchHerd() async* {
    yield await _herdNow();
    yield* _herd.stream.asyncMap((_) => _herdNow());
  }

  Future<List<Cattle>> _herdNow() async {
    final all = await _rawHerd();
    final list = all.map(_cattleFrom).toList()
      ..sort((a, b) => a.tagNumber.compareTo(b.tagNumber));
    return list;
  }

  static Cattle _cattleFrom(Map<String, dynamic> m) => Cattle(
        id: m['id'] as String,
        tagNumber: m['tagNumber'] as String? ?? '',
        tagStandard: TagStandard.parse(m['tagStandard'] as String?),
        name: m['name'] as String? ?? '',
        breed: m['breed'] as String? ?? '',
        sex: m['sex'] as String? ?? 'cow',
        birthDate: m['birthDate'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['birthDate'] as int),
        status: CattleStatus.parse(m['status'] as String?),
        notes: m['notes'] as String? ?? '',
      );

  static Map<String, dynamic> _cattleTo(Cattle c, String id) => {
        'id': id,
        'tagNumber': c.tagNumber,
        'tagStandard': c.tagStandard.name,
        'name': c.name,
        'breed': c.breed,
        'sex': c.sex,
        'birthDate': c.birthDate?.millisecondsSinceEpoch,
        'status': c.status.name,
        'notes': c.notes,
      };

  Future<void> addCattle(Cattle c) async {
    final all = await _rawHerd();
    all.add(_cattleTo(c, 'c${DateTime.now().microsecondsSinceEpoch}'));
    await (await _p).setString(_kHerd, jsonEncode(all));
    _herd.add(null);
  }

  Future<void> updateCattle(Cattle c) async {
    final all = await _rawHerd();
    final i = all.indexWhere((m) => m['id'] == c.id);
    if (i != -1) all[i] = _cattleTo(c, c.id);
    await (await _p).setString(_kHerd, jsonEncode(all));
    _herd.add(null);
  }

  Future<void> removeCattle(String id) async {
    final all = await _rawHerd();
    all.removeWhere((m) => m['id'] == id);
    await (await _p).setString(_kHerd, jsonEncode(all));
    _herd.add(null);
  }

  Future<Set<String>> existingTags() async =>
      (await _rawHerd()).map((m) => (m['tagNumber'] as String).toLowerCase()).toSet();

  // ── Outbreaks ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _rawOutbreaks() async {
    final raw = (await _p).getString(_kOutbreaks);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Stream<List<OutbreakReport>> watchOutbreaks() async* {
    yield await _outbreaksNow();
    yield* _outbreaks.stream.asyncMap((_) => _outbreaksNow());
  }

  Future<List<OutbreakReport>> _outbreaksNow() async {
    return (await _rawOutbreaks())
        .map((m) => OutbreakReport(
              id: m['id'] as String,
              disease: m['disease'] as String,
              severity: m['severity'] as String,
              kind: m['kind'] == 'livestock'
                  ? OutbreakKind.livestock
                  : OutbreakKind.plant,
              location: LatLng(m['lat'] as double, m['lng'] as double),
              region: m['region'] as String,
              reportedAt: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
            ))
        .toList();
  }

  Future<void> addOutbreak({
    required String disease,
    required String severity,
    required OutbreakKind kind,
    required LatLng location,
    required String region,
  }) async {
    final all = await _rawOutbreaks();
    all.add({
      'id': 'o${DateTime.now().microsecondsSinceEpoch}',
      'disease': disease,
      'severity': severity,
      'kind': kind.name,
      'lat': location.latitude,
      'lng': location.longitude,
      'region': region,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    await (await _p).setString(_kOutbreaks, jsonEncode(all));
    _outbreaks.add(null);
  }

  // ── Seed ──────────────────────────────────────────────────────────────────

  /// Gives the community and herd screens something to show on first run, so
  /// the layouts can be judged with real content rather than empty states.
  Future<void> _seed(SharedPreferences p) async {
    final now = DateTime.now();
    int ago(int hours) =>
        now.subtract(Duration(hours: hours)).millisecondsSinceEpoch;

    await p.setString(_kChat, jsonEncode([
      {
        'id': 's1', 'region': 'Greater Durban', 'uid': 'demo-1',
        'authorName': 'Thandeka M.',
        'text': 'Morning everyone. Anyone else seeing yellow spots on their tomato leaves this week?',
        'kind': 'message', 'at': ago(26),
      },
      {
        'id': 's2', 'region': 'Greater Durban', 'uid': 'demo-2',
        'authorName': 'Sipho N.',
        'text': 'Yes, same on my side near Pinetown. Started after the rain.',
        'kind': 'message', 'at': ago(24),
      },
      {
        'id': 's3', 'region': 'Greater Durban', 'uid': 'demo-3',
        'authorName': 'Farmer Dube',
        'text': 'Early blight is moving through the area. Spray before it reaches the fruit.',
        'kind': 'alert', 'at': ago(20),
      },
      {
        'id': 's4', 'region': 'KZN Midlands', 'uid': 'demo-4',
        'authorName': 'Nkosi B.',
        'text': 'Late blight confirmed on two farms outside Howick. Check your potatoes.',
        'kind': 'alert', 'at': ago(8),
      },
      {
        'id': 's5', 'region': 'KZN Midlands', 'uid': 'demo-5',
        'authorName': 'Precious K.',
        'text': 'Thanks for the warning. Spraying tomorrow morning.',
        'kind': 'message', 'at': ago(6),
      },
      {
        'id': 's6', 'region': 'Zululand', 'uid': 'demo-6',
        'authorName': 'Mandla Z.',
        'text': 'Two cows limping and drooling badly. State vet is coming out tomorrow.',
        'kind': 'alert', 'at': ago(3),
      },
    ]));

    await p.setString(_kHerd, jsonEncode([
      {'id': 'c1', 'tagNumber': 'ZA-0014', 'tagStandard': 'iso11784', 'name': 'Nandi', 'breed': 'Nguni', 'sex': 'cow', 'birthDate': DateTime(2021, 3, 14).millisecondsSinceEpoch, 'status': 'active', 'notes': ''},
      {'id': 'c2', 'tagNumber': 'ZA-0015', 'tagStandard': 'iso11784', 'name': '', 'breed': 'Nguni', 'sex': 'heifer', 'birthDate': DateTime(2024, 8, 2).millisecondsSinceEpoch, 'status': 'active', 'notes': ''},
      {'id': 'c3', 'tagNumber': 'ZA-0016', 'tagStandard': 'visual', 'name': 'Bheki', 'breed': 'Brahman', 'sex': 'bull', 'birthDate': DateTime(2020, 11, 9).millisecondsSinceEpoch, 'status': 'active', 'notes': 'Herd sire'},
      {'id': 'c4', 'tagNumber': 'ZA-0021', 'tagStandard': 'visual', 'name': '', 'breed': 'Bonsmara', 'sex': 'steer', 'birthDate': DateTime(2023, 5, 20).millisecondsSinceEpoch, 'status': 'active', 'notes': ''},
      {'id': 'c5', 'tagNumber': 'ZA-0022', 'tagStandard': 'management', 'name': '', 'breed': 'Bonsmara', 'sex': 'calf', 'birthDate': DateTime(2026, 6, 11).millisecondsSinceEpoch, 'status': 'active', 'notes': ''},
      {'id': 'c6', 'tagNumber': 'ZA-0009', 'tagStandard': 'brand', 'name': 'Thuli', 'breed': 'Nguni', 'sex': 'cow', 'birthDate': DateTime(2019, 1, 30).millisecondsSinceEpoch, 'status': 'sold', 'notes': 'Sold at Dundee auction'},
    ]));

    await p.setString(_kOutbreaks, jsonEncode([
      {'id': 'o1', 'disease': 'Late Blight', 'severity': 'red', 'kind': 'plant', 'lat': -29.60, 'lng': 30.40, 'region': 'KZN Midlands', 'at': ago(30)},
      {'id': 'o2', 'disease': 'Late Blight', 'severity': 'red', 'kind': 'plant', 'lat': -29.55, 'lng': 30.35, 'region': 'KZN Midlands', 'at': ago(48)},
      {'id': 'o3', 'disease': 'Early Blight', 'severity': 'orange', 'kind': 'plant', 'lat': -29.85, 'lng': 31.00, 'region': 'Greater Durban', 'at': ago(20)},
      {'id': 'o4', 'disease': 'Foot-and-Mouth Disease', 'severity': 'red', 'kind': 'livestock', 'lat': -28.75, 'lng': 31.90, 'region': 'Zululand', 'at': ago(3)},
      {'id': 'o5', 'disease': 'Foot-and-Mouth Disease', 'severity': 'red', 'kind': 'livestock', 'lat': -28.80, 'lng': 31.85, 'region': 'Zululand', 'at': ago(5)},
    ]));
  }
}
