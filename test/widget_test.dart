import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/theme/app_theme.dart';
import 'package:nolifa_grow/theme/glass.dart';

void main() {
  testWidgets('GlassButton shows its label and fires onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: GlassButton(label: 'Sign in', onPressed: () => taps++),
      ),
    ));

    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    expect(taps, 1);
  });

  testWidgets('GlassButton is inert while busy', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassButton(label: 'Save', busy: true, onPressed: () => taps++),
      ),
    ));

    await tester.tap(find.byType(GlassButton));
    expect(taps, 0);
  });
}
