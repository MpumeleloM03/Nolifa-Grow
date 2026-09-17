import 'package:cloud_firestore/cloud_firestore.dart';

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

class Cattle {
  final String id;
  final String tagNumber;
  final TagStandard tagStandard;
  final String name;
  final String breed;
  final String sex; // 'cow' | 'bull' | 'heifer' | 'steer' | 'calf'
  final DateTime? birthDate;
  final CattleStatus status;
  final String notes;

  const Cattle({
    required this.id,
    required this.tagNumber,
    required this.tagStandard,
    this.name = '',
    this.breed = '',
    this.sex = 'cow',
    this.birthDate,
    this.status = CattleStatus.active,
    this.notes = '',
  });

  int? get ageMonths {
    if (birthDate == null) return null;
    final now = DateTime.now();
    return (now.year - birthDate!.year) * 12 + now.month - birthDate!.month;
  }

  Map<String, dynamic> toMap() => {
        'tagNumber': tagNumber,
        'tagStandard': tagStandard.name,
        'name': name,
        'breed': breed,
        'sex': sex,
        'birthDate':
            birthDate == null ? null : Timestamp.fromDate(birthDate!),
        'status': status.name,
        'notes': notes,
      };

  factory Cattle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Cattle(
      id: doc.id,
      tagNumber: d['tagNumber'] as String? ?? '',
      tagStandard: TagStandard.parse(d['tagStandard'] as String?),
      name: d['name'] as String? ?? '',
      breed: d['breed'] as String? ?? '',
      sex: d['sex'] as String? ?? 'cow',
      birthDate: (d['birthDate'] as Timestamp?)?.toDate(),
      status: CattleStatus.parse(d['status'] as String?),
      notes: d['notes'] as String? ?? '',
    );
  }

  Cattle copyWith({
    String? tagNumber,
    TagStandard? tagStandard,
    String? name,
    String? breed,
    String? sex,
    DateTime? birthDate,
    CattleStatus? status,
    String? notes,
  }) =>
      Cattle(
        id: id,
        tagNumber: tagNumber ?? this.tagNumber,
        tagStandard: tagStandard ?? this.tagStandard,
        name: name ?? this.name,
        breed: breed ?? this.breed,
        sex: sex ?? this.sex,
        birthDate: birthDate ?? this.birthDate,
        status: status ?? this.status,
        notes: notes ?? this.notes,
      );
}
