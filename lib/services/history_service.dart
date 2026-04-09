import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/diagnosis_record.dart';

class HistoryService {
  static const String _key = 'diagnosis_history';

  Future<void> saveRecord(DiagnosisRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(_key) ?? [];
    history.insert(0, jsonEncode(record.toMap()));

    // Keep only last 50 records
    if (history.length > 50) {
      history.removeLast();
    }

    await prefs.setStringList(_key, history);
  }

  Future<List<DiagnosisRecord>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(_key) ?? [];

    return history
        .map((item) => DiagnosisRecord.fromMap(jsonDecode(item)))
        .toList();
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}