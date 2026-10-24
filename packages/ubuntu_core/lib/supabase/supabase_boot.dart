import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'resilient.dart';

/// Where the shared Nolifa database lives. Pass these when building:
/// `--dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_ANON_KEY=...`
/// The anon key is public by design. Row level security is what protects data.
/// The defaults point at the Nolifa Suite project. Override them to test on a
/// local Supabase. Pass an empty URL to stay on the phone alone (local mode).
const String supabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://ysjitrdzraofzfqhbcfp.supabase.co');
const String supabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlzaml0cmR6cmFvZnpmcWhiY2ZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI3NzEwNDcsImV4cCI6MjEwODM0NzA0N30.u3sHZSFcp_RdDzJ_-i5YmGaEIVBtgtM6VcjuRvNKh3c');

/// Tracks whether Supabase actually came up. A failed init must never blank
/// the screen: everything cloud-backed checks [ready] and falls back to the phone.
class SupabaseBoot {
  static bool ready = false;

  static bool get configured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> init() async {
    if (!configured) return;
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      ready = true;
    } catch (e) {
      ready = false;
      debugPrint('supabase: init failed, running in Local mode: $e');
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}

/// True when Supabase is connected. Tests override this to run on-device only.
final supabaseReadyProvider = Provider<bool>((ref) => SupabaseBoot.ready);

/// Rows of a table as a live list. Row level security decides what is visible.
Stream<List<Map<String, dynamic>>> liveTable(SupabaseClient db, String table,
        {String key = 'id'}) =>
    resilientRows(
      open: () => db.from(table).stream(primaryKey: [key]),
      fetch: () async => [for (final r in await db.from(table).select()) Map<String, dynamic>.from(r)],
    );

/// The stored document of a row, with its id added.
Map<String, dynamic> docOf(Map<String, dynamic> row, {String column = 'data', String idKey = 'id'}) =>
    {...Map<String, dynamic>.from(row[column] as Map), idKey: row[idKey]};
