import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'app.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppTheme.isLight = true; // the back office is a light, paper-like site
  // Build with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  // (use http://127.0.0.1:54321 and the local anon key to test on this computer).
  await SupabaseBoot.init();
  if (!SupabaseBoot.ready) {
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Text('This back office is not connected to a database yet.')))));
    return;
  }
  runApp(ProviderScope(overrides: backOfficeOverrides(), child: const BackOfficeApp()));
}
