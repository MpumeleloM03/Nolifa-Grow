import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_store.dart' show marketUidProvider;
import '../supabase/supabase_boot.dart';

/// What an admin has allowed this person to do: work at the warehouse, or
/// certify it. An admin adds people by hand to the `staff` and `certifiers`
/// tables in the Supabase dashboard, and the row level security stops anyone
/// adding themselves.
class StaffRoles {
  final bool hub;
  final bool certifier;
  final bool admin;
  final bool vet;
  const StaffRoles({this.hub = false, this.certifier = false, this.admin = false, this.vet = false});
}

final staffRolesProvider = FutureProvider<StaffRoles>((ref) async {
  final uid = ref.watch(marketUidProvider);
  if (uid.isEmpty || uid == 'guest') return const StaffRoles();
  try {
    final db = SupabaseBoot.client;
    final staff = await db.from('staff').select('uid').eq('uid', uid).maybeSingle();
    final cert = await db.from('certifiers').select('uid').eq('uid', uid).maybeSingle();
    final adm = await db.from('admins').select('uid').eq('uid', uid).maybeSingle();
    final vet = await db.from('vets').select('uid').eq('uid', uid).maybeSingle();
    return StaffRoles(hub: staff != null, certifier: cert != null, admin: adm != null, vet: vet != null);
  } catch (e) {
    debugPrint('staff: could not read roles: $e');
    return const StaffRoles();
  }
});
