import 'package:flutter/material.dart' hide Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/tr_text.dart';
import 'package:ubuntu_core/tr.dart';
import 'package:ubuntu_core/zulu_strings.dart';

void main() {
  tearDown(() => Tr.setLocale('en'));

  test('English is left exactly as it is', () {
    Tr.setLocale('en');
    expect(Tr.of('Sign in'), 'Sign in');
    expect(Tr.of('No such sentence anywhere'), 'No such sentence anywhere');
  });

  group('Zulu', () {
    setUp(() => Tr.setLocale('zu'));

    test('an exact sentence', () => expect(Tr.of('Welcome back'), 'Siyakwamukela futhi'));

    test('a sentence with gaps keeps the numbers and names', () {
      expect(Tr.of('Collect at Mkhize Farm'), 'Landa ku-Mkhize Farm');
      expect(Tr.of('R12 + R2.50 a km'), 'R12 + R2.50 ngekhilomitha');
    });

    test('leading and trailing spaces survive', () {
      final s = Tr.of('If the customer\'s delivery fee does not cover that, Nolifa pays the difference. ');
      expect(s.endsWith(' '), isTrue);
      expect(s, isNot(contains('Nolifa pays')));
    });

    test('a sentence with no translation stays in English', () {
      expect(Tr.of('Mkhize Family Farm'), 'Mkhize Family Farm');
    });

    test('numbers alone are not touched', () => expect(Tr.of('12.5'), '12.5'));

    test('switching back restores English', () {
      Tr.setLocale('en');
      expect(Tr.of('Welcome back'), 'Welcome back');
    });
  });

  group('the dictionary', () {
    test('every template compiles and every key is unique', () {
      Tr.setLocale('zu');
      final seen = <String>{};
      for (final t in zuTemplates) {
        expect(seen.add(t.$1), isTrue, reason: 'duplicate template ${t.$1}');
        expect(() => Tr.of(t.$1.replaceAll(RegExp(r'\{\d+\}'), 'x')), returnsNormally);
      }
    });

    test('a Zulu sentence never carries a gap the English does not have', () {
      final gap = RegExp(r'\{\d+\}');
      for (final t in zuTemplates) {
        final english = gap.allMatches(t.$1).map((m) => m.group(0)).toSet();
        final zulu = gap.allMatches(t.$2).map((m) => m.group(0)).toSet();
        expect(english.containsAll(zulu), isTrue, reason: t.$1);
      }
      for (final e in zuExact.entries) {
        expect(gap.hasMatch(e.value), isFalse, reason: e.key);
      }
    });

    test('no em dashes in anything the app shows', () {
      for (final e in [...zuExact.values, ...zuTemplates.map((t) => t.$2)]) {
        expect(e.contains('—'), isFalse, reason: e);
      }
    });

    test('it is big enough to be the whole app', () {
      expect(zuExact.length + zuTemplates.length, greaterThan(2800));
    });
  });

  group('on screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('a Text changes language when the person picks isiZulu, and it is remembered', (t) async {
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => LanguageScope(child: child!),
        home: const Scaffold(body: Column(children: [Text('Welcome back'), LanguagePicker()])),
      ));
      expect(find.text('Welcome back'), findsOneWidget);
      await t.tap(find.text('isiZulu'));
      await t.pumpAndSettle();
      expect(find.text('Siyakwamukela futhi'), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
      expect((await SharedPreferences.getInstance()).getString('language'), 'zu');
      await t.tap(find.text('English'));
      await t.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('rich text is translated piece by piece', (t) async {
      Tr.setLocale('zu');
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: Text.rich(TextSpan(children: [TextSpan(text: 'Welcome back'), TextSpan(text: ' Ngiyabonga')])))));
      expect(find.textContaining('Siyakwamukela futhi', findRichText: true), findsOneWidget);
    });

    test('a saved choice is read at start-up', () async {
      SharedPreferences.setMockInitialValues({'language': 'zu'});
      await Tr.load();
      expect(Tr.zulu, isTrue);
    });
  });
}
