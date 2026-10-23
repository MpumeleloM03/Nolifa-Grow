import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart';
import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppTheme.isLight = true; // the back office is a light, paper-like site
  const emulator = bool.fromEnvironment('EMULATOR');
  await Firebase.initializeApp(
      options: emulator
          ? FirebaseOptions(
              apiKey: webOptions.apiKey,
              appId: webOptions.appId,
              messagingSenderId: webOptions.messagingSenderId,
              projectId: 'demo-nolifa', // the emulators' made-up project, never the real one
              authDomain: webOptions.authDomain)
          : webOptions);
  // For testing on this computer only: build with --dart-define=EMULATOR=true
  // to use the local Firebase emulators and touch nothing real.
  if (emulator) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8089);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }
  runApp(ProviderScope(overrides: backOfficeOverrides(), child: const BackOfficeApp()));
}
