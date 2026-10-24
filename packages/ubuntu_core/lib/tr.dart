import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'zulu_strings.dart';

/// The words on screen, in the language the person chose.
///
/// Every `Text` in the three apps and the back office goes through [Tr.of]
/// (see tr_text.dart), so a screen is translated even when its words come from
/// a constant, a list or a built-up sentence. English is the source. Zulu is
/// looked up in two steps:
///
///  1. the exact sentence, and
///  2. a template with gaps for numbers and names, for sentences built at run
///     time, for example `R{0} delivery fee`.
///
/// Anything that has no translation stays in English rather than breaking. In
/// debug builds [misses] lists what was not found, so the gaps can be closed.
class Tr {
  static final ValueNotifier<String> locale = ValueNotifier('en');

  static bool get zulu => locale.value == 'zu';

  /// Sentences shown in Zulu mode that had no Zulu version. Debug aid.
  static final Set<String> misses = {};

  static final _memo = <String, String>{};
  static List<_Pattern>? _patterns;

  /// Reads the saved choice. Call it before the first frame.
  static Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString('language');
      if (saved != null) setLocale(saved);
    } catch (e) {
      debugPrint('language: could not read the saved choice: $e');
    }
  }

  /// The person's choice: applied now and remembered.
  static Future<void> choose(String code) async {
    setLocale(code);
    try {
      await (await SharedPreferences.getInstance()).setString('language', code);
    } catch (e) {
      debugPrint('language: could not save the choice: $e');
    }
  }

  static void setLocale(String code) {
    if (code != 'en' && code != 'zu') return;
    _memo.clear();
    locale.value = code;
  }

  static String of(String s) {
    if (!zulu || s.isEmpty) return s;
    final hit = _memo[s];
    if (hit != null) return hit;
    final out = _lookup(s);
    if (out == null) {
      if (kDebugMode && _worthTranslating(s)) misses.add(s);
      return s;
    }
    if (_memo.length > 6000) _memo.clear();
    return _memo[s] = out;
  }

  static String? _lookup(String s) {
    final exact = zuExact[s];
    if (exact != null) return exact;
    final trimmed = s.trim();
    if (trimmed != s) {
      final inner = of(trimmed);
      return inner == trimmed ? null : s.replaceFirst(trimmed, inner);
    }
    for (final p in (_patterns ??= _compile())) {
      final m = p.re.firstMatch(s);
      if (m == null) continue;
      var out = p.zulu;
      for (var i = 1; i <= m.groupCount; i++) {
        // A gap often holds a word too (a status, a kind of animal): translate it.
        final part = m.group(i)!;
        out = out.replaceAll('{${i - 1}}', part.length > 2 ? (_lookupExactOnly(part) ?? part) : part);
      }
      return out;
    }
    return _lookupParts(s);
  }

  static String? _lookupExactOnly(String s) => zuExact[s] ?? zuExact[s.trim()];

  // Emoji or an arrow around a sentence, several lines, or several sentences.
  static final _decorated = RegExp(r'^([^\p{L}\p{N}]*)(.*?)([\s\u2192\u203A\u00BB:\u2026\u00B7\u2022]*)$', unicode: true, dotAll: true);
  static final _sentenceEnd = RegExp(r'(?<=[.!?])\s+');

  static String? _lookupParts(String s) {
    final d = _decorated.firstMatch(s);
    if (d != null && d.group(2)!.isNotEmpty && (d.group(1)!.isNotEmpty || d.group(3)!.isNotEmpty)) {
      final inner = _lookup(d.group(2)!);
      if (inner != null) return '${d.group(1)}$inner${d.group(3)}';
    }
    if (s.contains('\n')) {
      var hit = false;
      final lines = [
        for (final line in s.split('\n'))
          if (_lookup(line) case final t?) (hit = true) ? t : t else line
      ];
      if (hit) return lines.join('\n');
    }
    // CAPITALS headings come from a sentence-case sentence.
    if (s.length > 2 && s == s.toUpperCase() && RegExp(r'[A-Z]{2}').hasMatch(s)) {
      final lower = s.toLowerCase();
      final sentence = lower[0].toUpperCase() + lower.substring(1);
      final t = zuExact[sentence] ?? zuExact[s] ;
      if (t != null) return t.toUpperCase();
    }
    // Pieces joined with a bullet or a middle dot: "1 item  •  R45  •  Checkout".
    for (final sep in const ['  \u2022  ', ' \u2022 ', '  \u00B7  ', ' \u00B7 ', ' \u00D7 ']) {
      if (!s.contains(sep)) continue;
      var hit = false;
      final parts = [
        for (final p in s.split(sep))
          if (_lookup(p) case final t?) (hit = true) ? t : t else p
      ];
      if (hit) return parts.join(sep);
    }
    final sentences = s.split(_sentenceEnd);
    if (sentences.length > 1) {
      var hit = false;
      final parts = [
        for (final p in sentences)
          if (_lookup(p) case final t?) (hit = true) ? t : t else p
      ];
      if (hit) return parts.join(' ');
    }
    return null;
  }

  // Numbers, ids and punctuation need no translation.
  static bool _worthTranslating(String s) => RegExp(r'[A-Za-z]{3,}').hasMatch(s);

  static List<_Pattern> _compile() {
    final list = <_Pattern>[
      for (final t in zuTemplates) _Pattern(_regexFor(t.$1), t.$2, t.$1.replaceAll(RegExp(r'\{\d+\}'), '').length),
    ]..sort((a, b) => b.literalLength.compareTo(a.literalLength));
    return list;
  }

  static RegExp _regexFor(String template) {
    final buf = StringBuffer('^');
    var last = 0;
    for (final m in RegExp(r'\{\d+\}').allMatches(template)) {
      buf.write(RegExp.escape(template.substring(last, m.start)));
      buf.write('(.*?)');
      last = m.end;
    }
    buf.write(RegExp.escape(template.substring(last)));
    buf.write(r'$');
    return RegExp(buf.toString(), dotAll: true);
  }
}

class _Pattern {
  final RegExp re;
  final String zulu;
  final int literalLength;
  _Pattern(this.re, this.zulu, this.literalLength);
}

/// Translates one string. Use it for words that are not shown through a `Text`:
/// hints, tooltips, notifications.
String tr(String s) => Tr.of(s);

/// [tr] for a value that may be null.
String? trn(String? s) => s == null ? null : Tr.of(s);
