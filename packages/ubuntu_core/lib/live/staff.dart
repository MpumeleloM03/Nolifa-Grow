import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_store.dart' show marketUidProvider;

/// What an admin has allowed this person to do: work at the warehouse, or
/// certify it. An admin adds people by hand to the `staff` and `certifiers`
/// collections in the Firebase console, and the security rules stop anyone
/// adding themselves.
class StaffRoles {
  final bool hub;
  final bool certifier;
  const StaffRoles({this.hub = false, this.certifier = false});
}

final staffRolesProvider = FutureProvider<StaffRoles>((ref) async {
  final uid = ref.watch(marketUidProvider);
  if (uid.isEmpty || uid == 'guest') return const StaffRoles();
  try {
    final db = FirebaseFirestore.instance;
    final staff = await db.collection('staff').doc(uid).get();
    final cert = await db.collection('certifiers').doc(uid).get();
    return StaffRoles(hub: staff.exists, certifier: cert.exists);
  } catch (e) {
    debugPrint('staff: could not read roles: $e');
    return const StaffRoles();
  }
});
