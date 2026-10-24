import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/members/members_service.dart';
import 'package:nolifa_grow/members/membership_screen.dart';

Future<void> open(WidgetTester t, Membership? m) async {
  t.view.physicalSize = const Size(1206, 2622);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
  await t.pumpWidget(ProviderScope(
    overrides: [membershipProvider.overrideWith((ref) => Stream.value(m))],
    child: const MaterialApp(home: MembershipScreen()),
  ));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('before joining: both plans and the 24 month commitment spelled out', (t) async {
    await open(t, null);
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    await t.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Read this before you join'), findsOneWidget);
    expect(find.textContaining('minimum of 24 months', skipOffstage: false), findsWidgets);
    expect(find.textContaining('24 month commitment'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('waiting for payment: a Pay by card button with the right amount', (t) async {
    await open(t, const Membership(Tier.max, 'awaiting_payment', null, null));
    expect(find.text('One step left: pay the first month'), findsOneWidget);
    expect(find.text('Pay R7 000 by card'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('once paid the screen shows the active plan and the term', (t) async {
    await open(t, Membership(Tier.member, 'active', DateTime(2026, 10, 24), DateTime(2028, 10, 24)));
    expect(find.text('You are a Member member'), findsOneWidget);
    expect(find.textContaining('24 month term'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}

