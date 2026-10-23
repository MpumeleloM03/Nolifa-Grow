import 'dart:math' show Random;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot;
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cattle.dart';
import '../models/species.dart';
import 'auth_service.dart';
import 'local_backend.dart';

class ImportResult {
  final int added;
  final int skipped;
  final List<String> problems;

  const ImportResult(this.added, this.skipped, this.problems);
}

/// The herd register, stored in the `cattle` table.
///
/// Every row carries its owner's uid, so a farmer's herd is private by default
/// and the row level security is a single ownership check.
class CattleService {
  SupabaseClient get _db => SupabaseBoot.client;

  static bool get _live => SupabaseBoot.ready;

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

  Map<String, dynamic> _row(String uid, String id, Cattle c) => {
        'uid': uid,
        'id': id,
        'data': c.toMap()..['createdAt'] = DateTime.now().toUtc().toIso8601String(),
      };

  Stream<List<Cattle>> watch(String uid) => _live ? _herdStream(uid) : LocalBackend.instance.watchHerd();

  Stream<List<Cattle>> _herdStream(String uid) =>
      _db.from('cattle').stream(primaryKey: ['uid', 'id']).eq('uid', uid).map((rows) => [
            for (final r in rows) Cattle.fromMap(r['id'] as String, Map<String, dynamic>.from(r['data'] as Map)),
          ]..sort((a, b) => a.tagNumber.compareTo(b.tagNumber)));

  Future<void> add(String uid, Cattle c) =>
      _live ? _db.from('cattle').insert(_row(uid, _newId(), c)) : LocalBackend.instance.addCattle(c);

  Future<void> update(String uid, Cattle c) => _live
      ? _db.from('cattle').update({'data': c.toMap()}).eq('uid', uid).eq('id', c.id)
      : LocalBackend.instance.updateCattle(c);

  Future<void> remove(String uid, String id) =>
      _live ? _db.from('cattle').delete().eq('uid', uid).eq('id', id) : LocalBackend.instance.removeCattle(id);

  /// Vendor exports rarely agree on header names, so each field accepts the
  /// spellings Allflex, Datamars and Shearwell actually emit.
  static const _aliases = <String, List<String>>{
    'tagNumber': [
      'tag', 'tagnumber', 'tag number', 'tag_number', 'eid', 'e-id',
      'electronic id', 'visual id', 'vid', 'animal id', 'animalid', 'id',
      'rfid', 'nlis', 'management tag',
    ],
    'tagStandard': ['tag standard', 'tag_standard', 'tagstandard', 'tag type'],
    'species': ['species', 'animal', 'animal type', 'type', 'kind'],
    'name': ['name', 'animal name', 'nickname'],
    'breed': ['breed', 'breed name'],
    'sex': ['sex', 'gender', 'class'],
    'birthDate': ['birth date', 'birth_date', 'birthdate', 'dob', 'date of birth'],
    'status': ['status', 'state', 'disposal'],
    'notes': ['notes', 'note', 'comment', 'comments', 'remarks'],
    'camp': ['camp', 'paddock', 'field', 'location'],
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
    // Text pasted on a phone ends its lines with \n, while the parser expects
    // \r\n, so make them all the same first.
    final text = raw.trim().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(text);
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

    final existing = _live
        ? [
            for (final r in await _db.from('cattle').select('data').eq('uid', uid))
              ((r['data'] as Map)['tagNumber'] as String? ?? '').toLowerCase()
          ].toSet()
        : await LocalBackend.instance.existingTags();

    final batch = _live ? <Map<String, dynamic>>[] : null;
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

      // The species column wins; otherwise a class word like "ewe" tells us.
      final species = Species.fromWord(cell(row, 'species')) ?? Species.fromWord(cell(row, 'sex')) ?? Species.cattle;
      final animal = Cattle(
        id: '',
        species: species,
        tagNumber: tag,
        tagStandard: _standardFrom(cell(row, 'tagStandard')),
        name: cell(row, 'name'),
        breed: cell(row, 'breed'),
        camp: cell(row, 'camp'),
        sex: _sexFrom(cell(row, 'sex'), species),
        birthDate: _dateFrom(cell(row, 'birthDate')),
        status: CattleStatus.parse(cell(row, 'status').toLowerCase()),
        notes: cell(row, 'notes'),
      );

      if (batch != null) {
        batch.add(_row(uid, _newId(), animal));
      } else {
        await LocalBackend.instance.addCattle(animal);
      }
      existing.add(tag.toLowerCase());
      added++;
    }

    if (added > 0 && batch != null) await _db.from('cattle').insert(batch);
    return ImportResult(added, skipped, problems);
  }

  String exportCsv(List<Cattle> herd) {
    final rows = <List<String>>[
      ['tag_number', 'species', 'tag_standard', 'name', 'breed', 'sex', 'birth_date', 'status', 'camp', 'notes'],
      ...herd.map((c) => [
            c.tagNumber,
            c.species.name,
            c.tagStandard.name,
            c.name,
            c.breed,
            c.sex,
            c.birthDate == null
                ? ''
                : '${c.birthDate!.year}-${c.birthDate!.month.toString().padLeft(2, '0')}-${c.birthDate!.day.toString().padLeft(2, '0')}',
            c.status.name,
            c.camp,
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

  static String _sexFrom(String raw, Species species) {
    final v = raw.toLowerCase();
    // Longer words first so "heifer" is not read as "if".
    final options = [...species.sexes]..sort((a, b) => b.length.compareTo(a.length));
    for (final s in options) {
      if (v.contains(s)) return s;
    }
    return species.defaultSex;
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
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(cattleServiceProvider).watch(uid);
});
