import 'package:flutter/material.dart' as m;
import 'tr.dart';

/// A `Text` that shows its words in the chosen language. It is a drop-in for
/// Flutter's own `Text`: the apps import this one in its place, so no screen has
/// to be rewritten to be translated. In English it changes nothing.
class Text extends m.StatelessWidget {
  final String? data;
  final m.InlineSpan? textSpan;
  final m.TextStyle? style;
  final m.StrutStyle? strutStyle;
  final m.TextAlign? textAlign;
  final m.TextDirection? textDirection;
  final m.Locale? locale;
  final bool? softWrap;
  final m.TextOverflow? overflow;
  final m.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final m.TextWidthBasis? textWidthBasis;
  final m.TextHeightBehavior? textHeightBehavior;
  final m.Color? selectionColor;

  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    m.InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  static m.InlineSpan _span(m.InlineSpan s) {
    if (s is! m.TextSpan) return s;
    return m.TextSpan(
      text: s.text == null ? null : Tr.of(s.text!),
      children: s.children?.map(_span).toList(),
      style: s.style,
      recognizer: s.recognizer,
      mouseCursor: s.mouseCursor,
      onEnter: s.onEnter,
      onExit: s.onExit,
      semanticsLabel: s.semanticsLabel == null ? null : Tr.of(s.semanticsLabel!),
      locale: s.locale,
      spellOut: s.spellOut,
    );
  }

  @override
  m.Widget build(m.BuildContext context) {
    // Listening to the scope is what makes a const screen re-translate when the
    // language changes. Without a scope (a test, a bare widget) it just reads Tr.
    context.dependOnInheritedWidgetOfExactType<_LanguageInherited>();
    final label = semanticsLabel == null ? null : Tr.of(semanticsLabel!);
    if (data != null) {
      return m.Text(
        Tr.of(data!),
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: label,
        semanticsIdentifier: semanticsIdentifier,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return m.Text.rich(
      Tr.zulu ? _span(textSpan!) : textSpan!,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}

/// Tells every `Text` under it that the language changed, so each re-reads its
/// words. Put it inside MaterialApp.builder. Nothing is rebuilt that does not
/// show text, and screens keep their place.
class LanguageScope extends m.StatelessWidget {
  final m.Widget child;
  const LanguageScope({super.key, required this.child});

  @override
  m.Widget build(m.BuildContext context) => m.ValueListenableBuilder<String>(
        valueListenable: Tr.locale,
        builder: (context, code, _) => _LanguageInherited(code: code, child: child),
      );
}

class _LanguageInherited extends m.InheritedWidget {
  final String code;
  const _LanguageInherited({required this.code, required super.child});

  @override
  bool updateShouldNotify(_LanguageInherited old) => old.code != code;
}

/// English or isiZulu, one tap. The choice is remembered.
class LanguagePicker extends m.StatelessWidget {
  const LanguagePicker({super.key});

  @override
  m.Widget build(m.BuildContext context) => m.ValueListenableBuilder<String>(
        valueListenable: Tr.locale,
        builder: (context, code, _) => m.Wrap(spacing: 8, crossAxisAlignment: m.WrapCrossAlignment.center, children: [
          const m.Icon(m.Icons.translate_rounded, size: 18),
          for (final o in const [('en', 'English'), ('zu', 'isiZulu')])
            m.ChoiceChip(
              label: m.Text(o.$2),
              selected: code == o.$1,
              onSelected: (_) => Tr.choose(o.$1),
            ),
        ]),
      );
}
