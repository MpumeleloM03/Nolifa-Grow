/// Someone using Nolifa, mirrored into Supabase at users.data.
///
/// [farmType] doubles as the role, so existing accounts and server rules keep
/// working: 'plants', 'livestock' and 'both' are farmers, 'community' is a
/// household that buys and follows alerts, and 'driver' delivers orders.
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String region;
  final String farmType; // 'plants' | 'livestock' | 'both' | 'community' | 'driver'

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.region,
    required this.farmType,
  });

  static const community = 'community';
  static const driver = 'driver';

  bool get isCommunity => farmType == community;
  bool get isDriver => farmType == driver;
  bool get isFarmer => !isCommunity && !isDriver;
  bool get growsCrops => farmType == 'plants' || farmType == 'both';
  bool get keepsLivestock => farmType == 'livestock' || farmType == 'both';

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
