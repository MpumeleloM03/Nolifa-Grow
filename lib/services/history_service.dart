import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecurePrefs;
import '../models/diagnosis_record.dart';

/// Past scans. Plant and herd health records are personal information, so the
/// list is stored sealed (AES-256-GCM). Lists saved by older versions are read
/// once, sealed, and the plain copy is deleted.
class HistoryService {
  static const String _legacyKey = 'diagnosis_history';
  static const String _key = 'diagnosis_history_v2';

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await SecurePrefs.getString(_key);
    if (raw != null) {
      try {
        return [for (final m in jsonDecode(raw) as List) Map<String, dynamic>.from(m as Map)];
      } catch (_) {
        return [];
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getStringList(_legacyKey);
    if (old == null) return [];
    final list = [for (final item in old) Map<String, dynamic>.from(jsonDecode(item) as Map)];
    await _store(list);
    await prefs.remove(_legacyKey);
    return list;
  }

  Future<void> _store(List<Map<String, dynamic>> list) =>
      SecurePrefs.setString(_key, jsonEncode(list));

  Future<void> saveRecord(DiagnosisRecord record) async {
    final history = await _load();
    history.insert(0, record.toMap());
    // Keep only last 50 records
    if (history.length > 50) history.removeLast();
    await _store(history);
  }

  Future<List<DiagnosisRecord>> getHistory() async =>
      [for (final m in await _load()) DiagnosisRecord.fromMap(m)];

  Future<void> clearHistory() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}
