import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTheme.isLight = false;
  });

  testWidgets('choosing Light repaints existing text and Dark restores it',
      (tester) async {
    await AppearanceController.instance.load();
    await AppearanceController.instance.set(AppearanceMode.dark);
    await tester.pumpWidget(AppearanceScope(
      builder: (context, light, dark, mode) => MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        home: const Scaffold(body: Column(children: [
          Text('hello'),
          AppearancePicker(),
        ])),
      ),
    ));
    expect(AppTheme.isLight, isFalse);
    Color hello() => tester.widget<Text>(find.text('hello')).style?.color ?? AppTheme.textPrimary;
    expect(AppTheme.textPrimary, const Color(0xFFF5F7F5));

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(AppTheme.isLight, isTrue);
    expect(AppTheme.textPrimary, const Color(0xFF0F2A1F));
    expect(Theme.of(tester.element(find.text('hello'))).brightness, Brightness.light);
    expect(hello(), isNotNull);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(AppTheme.isLight, isFalse);
    expect(Theme.of(tester.element(find.text('hello'))).brightness, Brightness.dark);
  });

  testWidgets('the choice is saved and reloaded', (tester) async {
    await AppearanceController.instance.set(AppearanceMode.light);
    await AppearanceController.instance.set(AppearanceMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appearance.mode'), 'light');
    await AppearanceController.instance.set(AppearanceMode.system);
    await AppearanceController.instance.load();
    expect(AppearanceController.instance.mode, AppearanceMode.system);
  });
}
