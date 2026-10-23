import 'package:cloud_firestore/cloud_firestore.dart';
import 'species.dart';

/// How an animal is identified in the field.
///
/// Vendors differ, so the standard is stored alongside the number rather than
/// assumed — an ISO electronic tag and a painted management number are both
/// valid, and a farmer often runs several at once.
enum TagStandard {
  iso11784('ISO 11784/11785', 'Electronic (RFID) ear tag'),
  visual('Visual tag', 'Printed plastic ear tag'),
  brand('Brand / tattoo', 'Hot brand, freeze brand or tattoo'),
  management('Management number', 'Your own on-farm numbering');

  final String label;
  final String description;
  const TagStandard(this.label, this.description);

  static TagStandard parse(String? raw) => TagStandard.values.firstWhere(
        (t) => t.name == raw,
        orElse: () => TagStandard.visual,
      );
}

enum CattleStatus {
  active('On farm'),
  sold('Sold'),
  deceased('Deceased');

  final String label;
  const CattleStatus(this.label);

  static CattleStatus parse(String? raw) => CattleStatus.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => CattleStatus.active,
      );
}

/// One animal on the register. The class is still called Cattle from when the
/// register only held cows; [species] now says what it is.
class Cattle {
  final String id;
  final Species species;
  final String tagNumber;
  final TagStandard tagStandard;
  final String name;
  final String breed;
  final String sex; // one of species.sexes
  final DateTime? birthDate;
  final CattleStatus status;
  final String notes;

  /// Where the animal is kept: a camp name and a pin on the map.
  final String camp;
  final double? lat;
  final double? lng;
  final DateTime? locatedAt;

  const Cattle({
    required this.id,
    required this.tagNumber,
    required this.tagStandard,
    this.species = Species.cattle,
    this.name = '',
    this.breed = '',
    this.sex = 'cow',
    this.birthDate,
    this.status = CattleStatus.active,
    this.notes = '',
    this.camp = '',
    this.lat,
    this.lng,
    this.locatedAt,
  });

  bool get hasLocation => lat != null && lng != null;

  /// The name to show: its given name, otherwise its tag.
  String get label => name.isEmpty ? tagNumber : name;

  int? get ageMonths {
    if (birthDate == null) return null;
    final now = DateTime.now();
    return (now.year - birthDate!.year) * 12 + now.month - birthDate!.month;
  }

  Map<String, dynamic> toMap() => {
        'tagNumber': tagNumber,
        'tagStandard': tagStandard.name,
        'species': species.name,
        'name': name,
        'breed': breed,
        'sex': sex,
        'birthDate':
            birthDate == null ? null : Timestamp.fromDate(birthDate!),
        'status': status.name,
        'notes': notes,
        'camp': camp,
        'lat': lat,
        'lng': lng,
        'locatedAt': locatedAt == null ? null : Timestamp.fromDate(locatedAt!),
      };

  factory Cattle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Cattle(
      id: doc.id,
      tagNumber: d['tagNumber'] as String? ?? '',
      tagStandard: TagStandard.parse(d['tagStandard'] as String?),
      species: Species.parse(d['species'] as String?),
      name: d['name'] as String? ?? '',
      breed: d['breed'] as String? ?? '',
      sex: d['sex'] as String? ?? 'cow',
      birthDate: (d['birthDate'] as Timestamp?)?.toDate(),
      status: CattleStatus.parse(d['status'] as String?),
      notes: d['notes'] as String? ?? '',
      camp: d['camp'] as String? ?? '',
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      locatedAt: (d['locatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Cattle copyWith({
    String? tagNumber,
    TagStandard? tagStandard,
    Species? species,
    String? name,
    String? breed,
    String? sex,
    DateTime? birthDate,
    CattleStatus? status,
    String? notes,
    String? camp,
    double? lat,
    double? lng,
    DateTime? locatedAt,
  }) =>
      Cattle(
        id: id,
        species: species ?? this.species,
        tagNumber: tagNumber ?? this.tagNumber,
        tagStandard: tagStandard ?? this.tagStandard,
        name: name ?? this.name,
        breed: breed ?? this.breed,
        sex: sex ?? this.sex,
        birthDate: birthDate ?? this.birthDate,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        camp: camp ?? this.camp,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        locatedAt: locatedAt ?? this.locatedAt,
      );
}

typedef Animal = Cattle;
