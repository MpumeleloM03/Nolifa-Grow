
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Tr;

final languageProvider =
    StateNotifierProvider<LanguageNotifier, String>((ref) {
  return LanguageNotifier();
});

class LanguageNotifier extends StateNotifier<String> {
  LanguageNotifier() : super('en') {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('language') ?? 'en';
    state = saved;
    Tr.setLocale(saved);
  }

  Future<void> setLanguage(String code) async {
    state = code;
    Tr.setLocale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', code);
  }

  void toggle() {
    setLanguage(state == 'en' ? 'zu' : 'en');
  }
}