lass DiagnosisRecord {
  final String id;
  final String label;
  final String plainName;
  final String confidence;
  final String imagePath;
  final DateTime date;
  final bool offlineMode;
  final String? region;
  final double? latitude;
  final double? longitude;
  final String? cropType;

  DiagnosisRecord({
    required this.id,
    required this.label,
    required this.plainName,
    required this.confidence,
    required this.imagePath,
    required this.date,
    required this.offlineMode,
    this.region,
    this.latitude,
    this.longitude,
    this.cropType,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'plainName': plainName,
      'confidence': confidence,
      'imagePath': imagePath,
      'date': date.toIso8601String(),
      'offlineMode': offlineMode,
      'region': region,
      'latitude': latitude,
      'longitude': longitude,
      'cropType': cropType,
    };
  }

  factory DiagnosisRecord.fromMap(Map<String, dynamic> map) {
    return DiagnosisRecord(
      id: map['id'],
      label: map['label'],
      plainName: map['plainName'],
      confidence: map['confidence'],
      imagePath: map['imagePath'],
      date: DateTime.parse(map['date']),
      offlineMode: map['offlineMode'] ?? false,
      region: map['region'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      cropType: map['cropType'] as String?,
    );
  }
}
