import 'package:flutter/material.dart' hide Text;
import '../theme/app_theme.dart';
import 'resilient.dart';

import '../tr_text.dart' show Text;
import '../tr.dart' show tr, trn;
/// The delete-account flow every app shows: say what goes, ask for the word
/// DELETE, run it, and explain plainly if it cannot be done yet.
Future<void> confirmDeleteAccount(BuildContext context, Future<void> Function() delete) async {
  final c = TextEditingController();
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: AppTheme.sheet,
        title: Text('Delete your account?', style: AppTheme.title3),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'This removes your sign-in, your profile, your herd and health records, your listings, your photos and ID documents, and your vet cases. It cannot be undone.\n\n'
              'Finished orders stay for the other person\'s accounts, with your name and address taken out. A membership you paid for is not refunded.',
              style: AppTheme.footnote),
          const SizedBox(height: AppTheme.s3),
          TextField(controller: c, enabled: !busy, decoration: InputDecoration(labelText: tr('Type DELETE to confirm'))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: AppTheme.danger))),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Keep my account')),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    if (c.text.trim() != 'DELETE') {
                      setS(() => error = 'Type DELETE in capital letters to go ahead.');
                      return;
                    }
                    setS(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await delete();
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setS(() {
                        busy = false;
                        error = e is StateError ? e.message : friendlyError(e, doing: 'delete your account');
                      });
                    }
                  },
            child: Text(busy ? 'Deleting' : 'Delete everything', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    ),
  );
  c.dispose();
}
