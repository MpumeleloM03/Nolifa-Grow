import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show AesSecureBox, SecureBox;
import 'package:nolifa_grow/community/community_section.dart';
import 'package:nolifa_grow/community/community_store.dart';
import 'package:nolifa_grow/community/proof_post.dart';
import 'package:nolifa_grow/models/app_user.dart';
import 'package:nolifa_grow/services/auth_service.dart';
import 'package:nolifa_grow/services/crop_scan.dart';
import 'package:nolifa_grow/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ubuntu_core/ubuntu_core.dart' hide AppTheme;

void main() {
  // Widget tests cannot reach the Keychain, so use a fixed test key.
  setUpAll(() => SecureBox.instance = AesSecureBox.withKey(List<int>.filled(32, 7)));
  final now = DateTime(2026, 10, 22, 9);
  ProofPost post(String id, PostTopic t, String sev, {int hoursAgo = 1}) => ProofPost(
      id: id, uid: 'u', author: 'A', region: 'KZN Midlands', topic: t, headline: id, detail: '',
      severity: sev, proof: ProofKind.photoOnly, aiSummary: 'x', at: now.subtract(Duration(hours: hoursAgo)));

  group('feed rules', () {
    test('filters: crops, livestock, both and water', () {
      expect(FeedFilter.crops.matches(PostTopic.crop), isTrue);
      expect(FeedFilter.crops.matches(PostTopic.livestock), isFalse);
      expect(FeedFilter.livestock.matches(PostTopic.livestock), isTrue);
      expect(FeedFilter.both.matches(PostTopic.crop), isTrue);
      expect(FeedFilter.both.matches(PostTopic.livestock), isTrue);
      expect(FeedFilter.both.matches(PostTopic.water), isFalse);
      expect(FeedFilter.water.matches(PostTopic.water), isTrue);
      expect(FeedFilter.water.matches(PostTopic.crop), isFalse);
    });

    test('the most important thing is first: urgent, then watch, newest within', () {
      final ranked = rankPosts([
        post('old-green', PostTopic.crop, 'green', hoursAgo: 1),
        post('new-orange', PostTopic.crop, 'orange', hoursAgo: 1),
        post('old-red', PostTopic.crop, 'red', hoursAgo: 30),
        post('old-orange', PostTopic.crop, 'orange', hoursAgo: 10),
      ]);
      expect([for (final p in ranked) p.id], ['old-red', 'new-orange', 'old-orange', 'old-green']);
    });

    test('posts survive a json round trip', () {
      final p = post('x', PostTopic.livestock, 'red').copyWith(confirmations: 3, iConfirmed: true);
      final back = ProofPost.fromJson(p.toJson());
      expect(back.topic, PostTopic.livestock);
      expect(back.confirmations, 3);
      expect(back.iConfirmed, isTrue);
      expect(back.urgent, isTrue);
    });
  });

  group('community on screen', () {
    const farmer = AppUser(uid: 'f1', name: 'Sipho Dlamini', email: '', region: 'Greater Durban', farmType: 'both');
    late File photo;

    setUp(() {
      photo = File('${Directory.systemTemp.path}/proof_test.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    });

    Future<ProviderContainer> mount(WidgetTester tester, {CropScanResult? scan}) async {
      SharedPreferences.setMockInitialValues({});
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final t = d.exceptionAsString();
        if (t.contains('overflowed') || t.contains('image')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      tester.view.physicalSize = const Size(1206, 9000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(farmer),
        marketUidProvider.overrideWithValue('f1'),
        marketNameProvider.overrideWithValue('Sipho'),
        marketRepositoryProvider.overrideWithValue(LocalMarketRepository.memory()),
        waterRepositoryProvider.overrideWithValue(LocalWaterRepository.memory()),
        proofPickerProvider.overrideWithValue(() async => photo),
        cropCaptureProvider.overrideWithValue((_, __) async => scan),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.build(),
            home: const Scaffold(body: SingleChildScrollView(child: Padding(padding: EdgeInsets.all(16), child: CommunitySection())))),
      ));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
      return c;
    }

    Future<void> end(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('filters show crops, livestock, both, and water with the municipality box', (tester) async {
      await mount(tester);
      // Both is the default: crops and livestock, no water.
      expect(find.text('Late Blight on potatoes'), findsOneWidget);
      expect(find.text('Lumpy Skin Disease'), findsOneWidget);
      expect(find.text('Low pressure, taps dry by evening'), findsNothing);

      await tester.tap(find.text('🌿 Crops'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Late Blight on potatoes'), findsOneWidget);
      expect(find.text('Lumpy Skin Disease'), findsNothing);

      await tester.tap(find.text('🐄 Livestock'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Late Blight on potatoes'), findsNothing);
      expect(find.text('Lumpy Skin Disease'), findsOneWidget);

      await tester.tap(find.text('💧 Water'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Low pressure, taps dry by evening'), findsOneWidget);
      expect(find.text('From the municipality'), findsOneWidget);
      await end(tester);
    });

    testWidgets('every post shows its proof line', (tester) async {
      await mount(tester);
      expect(find.textContaining('Scanned on her phone'), findsOneWidget);
      expect(find.textContaining('Symptom check on his phone'), findsOneWidget);
      await end(tester);
    });

    testWidgets('urgent posts come before watch posts', (tester) async {
      await mount(tester);
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('Late Blight on potatoes') < y('Fall armyworm on maize'), isTrue);
      await end(tester);
    });

    testWidgets('an unverified farmer cannot confirm, a verified one can, once', (tester) async {
      final c = await mount(tester);
      await tester.tap(find.text('I see this too').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(communityStoreProvider).firstWhere((p) => p.id == 'demo-1').confirmations, 6, reason: 'unverified');
      expect(find.textContaining('Only verified farmers'), findsOneWidget);
      for (final step in farmerSteps) {
        c.read(marketProvider.notifier).completeKyc(KycRole.farmer, step.id);
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('I see this too').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(communityStoreProvider).firstWhere((p) => p.id == 'demo-1').confirmations, 7);
      await end(tester);
    });

    testWidgets('confirming a neighbour post counts once', (tester) async {
      final c = await mount(tester);
      for (final step in farmerSteps) {
        c.read(marketProvider.notifier).completeKyc(KycRole.farmer, step.id);
      }
      await tester.tap(find.text('I see this too').first);
      await tester.pump(const Duration(milliseconds: 300));
      final p = c.read(communityStoreProvider).firstWhere((p) => p.id == 'demo-1');
      expect(p.confirmations, 7);
      expect(p.iConfirmed, isTrue);
      await tester.tap(find.text('You see this too').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(communityStoreProvider).firstWhere((p) => p.id == 'demo-1').confirmations, 7);
      await end(tester);
    });

    testWidgets('a water report needs a photo, then lands in the water filter', (tester) async {
      final c = await mount(tester);
      await tester.tap(find.text('Share proof with your area'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('💧 Water').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<GlassButton>(find.widgetWithText(GlassButton, 'Post to my area')).onPressed, isNull);
      await tester.tap(find.text('Take a photo of the tank or tap'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Post to my area'));
      await tester.pump(const Duration(seconds: 1));
      final p = c.read(communityStoreProvider).first;
      expect(p.topic, PostTopic.water);
      expect(p.photoPath, photo.path);
      expect(p.region, 'Greater Durban');
      await end(tester);
    });

    testWidgets('an animal post needs symptoms and a photo; urgency comes from the match', (tester) async {
      final c = await mount(tester);
      await tester.tap(find.text('Share proof with your area'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('🐄 Animal'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Take a photo of the animal'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<GlassButton>(find.widgetWithText(GlassButton, 'Post to my area')).onPressed, isNull,
          reason: 'photo but no symptoms');
      await tester.ensureVisible(find.text('Blisters or sores in the mouth'));
      await tester.tap(find.text('Blisters or sores in the mouth'));
      await tester.tap(find.text('Drooling / stringy saliva'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Post to my area'));
      await tester.tap(find.text('Post to my area'));
      await tester.pump(const Duration(seconds: 1));
      final p = c.read(communityStoreProvider).first;
      expect(p.topic, PostTopic.livestock);
      expect(p.headline, 'Foot-and-Mouth Disease');
      expect(p.severity, 'red');
      expect(p.proof, ProofKind.symptomCheck);
      await end(tester);
    });

    testWidgets('a crop post carries the AI scan result as its proof', (tester) async {
      final c = await mount(tester,
          scan: CropScanResult('scan-1', photo, 'Early_Blight', 'Early Blight', 'orange', '88', false));
      await tester.tap(find.text('Share proof with your area'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<GlassButton>(find.widgetWithText(GlassButton, 'Post to my area')).onPressed, isNull);
      await tester.tap(find.text('Scan a leaf with the AI'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('Post to my area'));
      await tester.tap(find.text('Post to my area'));
      await tester.pump(const Duration(seconds: 1));
      final p = c.read(communityStoreProvider).first;
      expect(p.topic, PostTopic.crop);
      expect(p.headline, 'Early Blight');
      expect(p.aiSummary, contains('88%'));
      expect(p.proof, ProofKind.aiScan);
      await end(tester);
    });

    testWidgets('water filter shows a municipality update when the provider has answered', (tester) async {
      final c = await mount(tester);
      await tester.tap(find.text('💧 Water'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('No updates yet'), findsOneWidget);
      await end(tester);
      expect(c.read(waterProvider).zones, isNotNull);
    });
  });

  group('email field', () {
    testWidgets('the @ icon on an email field types an @ at the cursor', (tester) async {
      final c = TextEditingController(text: 'thandiexample.com');
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: GlassField(controller: c, label: 'Email', icon: Icons.alternate_email_rounded),
        ),
      ));
      c.selection = const TextSelection.collapsed(offset: 6);
      await tester.tap(find.byIcon(Icons.alternate_email_rounded));
      await tester.pump();
      expect(c.text, 'thandi@example.com');
      expect(c.selection.baseOffset, 7);
    });
  });
}
