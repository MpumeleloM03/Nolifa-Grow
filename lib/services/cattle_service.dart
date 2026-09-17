import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cattle.dart';
import 'auth_service.dart';

class ImportResult {
  final int added;
  final int skipped;
  final List<String> problems;

  const ImportResult(this.added, this.skipped, this.problems);
}

/// The herd register, stored at users/{uid}/cattle.
///
/// Scoped under the owner rather than a global collection so a farmer's herd
/// is private by default and the security rules stay a single ownership check.
class CattleService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _herd(String uid) =>
      _db.collection('users').doc(uid).collection('cattle');

  Stream<List<Cattle>> watch(String uid) => _herd(uid)
      .orderBy('tagNumber')
      .snapshots()
      .map((s) => s.docs.map(Cattle.fromDoc).toList());

  Future<void> add(String uid, Cattle c) =>
      _herd(uid).add(c.toMap()..['createdAt'] = FieldValue.serverTimestamp());

  Future<void> update(String uid, Cattle c) =>
      _herd(uid).doc(c.id).update(c.toMap());

  Future<void> remove(String uid, String id) => _herd(uid).doc(id).delete();

  /// Vendor exports rarely agree on header names, so each field accepts the
  /// spellings Allflex, Datamars and Shearwell actually emit.
  static const _aliases = <String, List<String>>{
    'tagNumber': [
      'tag', 'tagnumber', 'tag number', 'tag_number', 'eid', 'e-id',
      'electronic id', 'visual id', 'vid', 'animal id', 'animalid', 'id',
      'rfid', 'nlis', 'management tag',
    ],
    'tagStandard': ['tag standard', 'tag_standard', 'tagstandard', 'tag type', 'type'],
    'name': ['name', 'animal name', 'nickname'],
    'breed': ['breed', 'breed name'],
    'sex': ['sex', 'gender', 'class'],
    'birthDate': ['birth date', 'birth_date', 'birthdate', 'dob', 'date of birth'],
    'status': ['status', 'state', 'disposal'],
    'notes': ['notes', 'note', 'comment', 'comments', 'remarks'],
  };

  static String _normalise(String h) =>
      h.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 _-]'), '');

  static int? _columnFor(String field, List<String> headers) {
    final wanted = _aliases[field]!;
    for (var i = 0; i < headers.length; i++) {
      if (wanted.contains(_normalise(headers[i]))) return i;
    }
    return null;
  }

  /// Parses a pasted or loaded CSV into the herd.
  ///
  /// Rows without a tag number are skipped rather than imported blank, since a
  /// tagless record cannot be matched back to an animal in the kraal.
  Future<ImportResult> importCsv(String uid, String raw) async {
    final rows = const CsvToListConverter(shouldParseNumbers: false)
        .convert(raw.trim());
    if (rows.length < 2) {
      return const ImportResult(0, 0, ['Need a header row and at least one animal.']);
    }

    final headers = rows.first.map((e) => e.toString()).toList();
    final tagCol = _columnFor('tagNumber', headers);
    if (tagCol == null) {
      return ImportResult(0, 0, [
        'No tag column found. Expected one of: ${_aliases['tagNumber']!.take(6).join(", ")}.'
      ]);
    }

    final cols = {
      for (final f in _aliases.keys) f: _columnFor(f, headers),
    };

    String cell(List<dynamic> row, String field) {
      final i = cols[field];
      if (i == null || i >= row.length) return '';
      return row[i].toString().trim();
    }

    final existing = (await _herd(uid).get())
        .docs
        .map((d) => (d.data()['tagNumber'] as String? ?? '').toLowerCase())
        .toSet();

    final batch = _db.batch();
    var added = 0;
    var skipped = 0;
    final problems = <String>[];

    for (final row in rows.skip(1)) {
      if (row.isEmpty) continue;
      final tag = cell(row, 'tagNumber');
      if (tag.isEmpty) {
        skipped++;
        continue;
      }
      if (existing.contains(tag.toLowerCase())) {
        skipped++;
        problems.add('$tag already in your herd');
        continue;
      }

      final animal = Cattle(
        id: '',
        tagNumber: tag,
        tagStandard: _standardFrom(cell(row, 'tagStandard')),
        name: cell(row, 'name'),
        breed: cell(row, 'breed'),
        sex: _sexFrom(cell(row, 'sex')),
        birthDate: _dateFrom(cell(row, 'birthDate')),
        status: CattleStatus.parse(cell(row, 'status').toLowerCase()),
        notes: cell(row, 'notes'),
      );

      batch.set(
        _herd(uid).doc(),
        animal.toMap()..['createdAt'] = FieldValue.serverTimestamp(),
      );
      existing.add(tag.toLowerCase());
      added++;
    }

    if (added > 0) await batch.commit();
    return ImportResult(added, skipped, problems);
  }

  String exportCsv(List<Cattle> herd) {
    final rows = <List<String>>[
      ['tag_number', 'tag_standard', 'name', 'breed', 'sex', 'birth_date', 'status', 'notes'],
      ...herd.map((c) => [
            c.tagNumber,
            c.tagStandard.name,
            c.name,
            c.breed,
            c.sex,
            c.birthDate == null
                ? ''
                : '${c.birthDate!.year}-${c.birthDate!.month.toString().padLeft(2, '0')}-${c.birthDate!.day.toString().padLeft(2, '0')}',
            c.status.name,
            c.notes,
          ]),
    ];
    return const ListToCsvConverter().convert(rows);
  }

  static TagStandard _standardFrom(String raw) {
    final v = raw.toLowerCase();
    if (v.contains('iso') || v.contains('rfid') || v.contains('electronic')) {
      return TagStandard.iso11784;
    }
    if (v.contains('brand') || v.contains('tattoo')) return TagStandard.brand;
    if (v.contains('manage')) return TagStandard.management;
    return TagStandard.visual;
  }

  static String _sexFrom(String raw) {
    final v = raw.toLowerCase();
    for (final s in ['heifer', 'steer', 'calf', 'bull', 'cow']) {
      if (v.contains(s)) return s;
    }
    return 'cow';
  }

  /// Handles ISO dates plus the day-first formats common in South African exports.
  static DateTime? _dateFrom(String raw) {
    if (raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;

    final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$').firstMatch(raw);
    if (m == null) return null;
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    return DateTime(year, int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
}

final cattleServiceProvider = Provider<CattleService>((ref) => CattleService());

final herdProvider = StreamProvider<List<Cattle>>((ref) {
  final uid = ref.watch(authServiceProvider).current?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(cattleServiceProvider).watch(uid);
});
