import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'package:ubuntu_drop/onboarding/onboarding_screen.dart';

import 'support.dart';

Future<int> mount(WidgetTester tester, VoidCallback onDone) async {
  ignoreFontOverflow();
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: OnboardingScreen(onDone: onDone),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return 0;
}

Future<void> swipeLeft(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
  await tester.pumpAndSettle();
}

/// Width of the dot that stands for page [i].
double dotWidth(WidgetTester tester, int i) {
  final dots = find.descendant(
    of: find.bySemanticsLabel(RegExp('Page ')),
    matching: find.byType(Container),
  );
  return tester.getSize(dots.at(i)).width;
}

void main() {
  // Widget tests cannot reach the Keychain, so use a fixed test key.
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  bigTextTest();
  testWidgets('three cards with the right words, swiped one at a time', (
    tester,
  ) async {
    await mount(tester, () {});
    expect(find.text('A community that stays fed'), findsOneWidget);
    await swipeLeft(tester);
    expect(find.text('Water you can count on'), findsOneWidget);
    await swipeLeft(tester);
    expect(find.text('Delivered to your door'), findsOneWidget);
  });

  testWidgets('Next moves on, and only the last card says Let\'s go', (
    tester,
  ) async {
    var done = 0;
    await mount(tester, () => done++);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Let\'s go'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Water you can count on'), findsOneWidget);
    expect(done, 0);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Let\'s go'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    // Nothing left to skip on the last card.
    expect(find.text('Skip'), findsNothing);

    await tester.tap(find.text('Let\'s go'));
    expect(done, 1);
  });

  testWidgets('Skip leaves straight away', (tester) async {
    var done = 0;
    await mount(tester, () => done++);
    await tester.tap(find.text('Skip'));
    expect(done, 1);
  });

  testWidgets('the page dots stretch toward the current card', (tester) async {
    await mount(tester, () {});
    expect(dotWidth(tester, 0), greaterThan(dotWidth(tester, 1)));
    expect(dotWidth(tester, 1), dotWidth(tester, 2));

    await swipeLeft(tester);
    expect(dotWidth(tester, 1), greaterThan(dotWidth(tester, 0)));
    expect(dotWidth(tester, 0), dotWidth(tester, 2));
  });
}

void bigTextTest() {
  testWidgets('large system text on the longest card scrolls, not overflows', (
    tester,
  ) async {
    // No ignoreFontOverflow here: any overflow must fail the test.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        builder: (c, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.6,
          maxScaleFactor: 1.6,
          child: child!,
        ),
        home: OnboardingScreen(onDone: () {}),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await swipeLeft(tester);
    expect(find.text('Water you can count on'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
