/// A farmer's profile, mirrored into Firestore at users/{uid}.
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String region;
  final String farmType; // 'plants' | 'livestock' | 'both'

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.region,
    required this.farmType,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'email': email,
        'region': region,
        'farmType': farmType,
      };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        uid: map['uid'] as String? ?? '',
        name: map['name'] as String? ?? '',
        email: map['email'] as String? ?? '',
        region: map['region'] as String? ?? '',
        farmType: map['farmType'] as String? ?? 'both',
      );
}
