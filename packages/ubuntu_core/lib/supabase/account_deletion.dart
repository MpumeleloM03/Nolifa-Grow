import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_boot.dart';

/// Why this account cannot be deleted yet (orders in progress, an open
/// dispute), or null when it can.
Future<String?> accountDeletionBlocker() async {
  final r = await SupabaseBoot.client.rpc('delete_blocker');
  return r as String?;
}

Future<void> _emptyFolder(StorageFileApi bucket, String folder) async {
  final items = await bucket.list(path: folder);
  final files = <String>[];
  for (final i in items) {
    if (i.id == null) {
      await _emptyFolder(bucket, '$folder/${i.name}');
    } else {
      files.add('$folder/${i.name}');
    }
  }
  if (files.isNotEmpty) await bucket.remove(files);
}

/// Deletes the signed-in person's account for good: their files, their records,
/// and the sign-in itself. Orders already completed stay for the other side's
/// accounts, with this person's name and address taken out.
Future<void> deleteMyAccount() async {
  final db = SupabaseBoot.client;
  final uid = db.auth.currentUser?.id;
  if (uid == null) return;
  final blocker = await accountDeletionBlocker();
  if (blocker != null) throw StateError(blocker);
  for (final b in const ['verification', 'consult-videos']) {
    try {
      await _emptyFolder(db.storage.from(b), uid);
    } catch (_) {
      // A missing folder is fine. The records below are what matter.
    }
  }
  await db.rpc('delete_my_account');
  try {
    await db.auth.signOut();
  } catch (_) {}
}
