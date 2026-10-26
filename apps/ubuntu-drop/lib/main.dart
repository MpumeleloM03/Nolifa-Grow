import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show notifierProvider, AppearanceController, SupabaseBoot, Tr;

import 'app.dart';
import 'services/phone_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppearanceController.instance.load();
  await Tr.load();
  await SupabaseBoot.init();
  await _portraitOnPhones();
  runApp(
    ProviderScope(
      overrides: [...dropOverrides, notifierProvider.overrideWithValue(PhoneNotifier.instance)],
      child: const NolifaDropApp(),
    ),
  );
}

/// Phones stay upright. Tablets have the room to turn.
Future<void> _portraitOnPhones() async {
  final view = PlatformDispatcher.instance.views.first;
  final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
  if (shortestSide < 600) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
}
