import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import 'firebase_boot.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Stream<User?> authState() {
    if (!FirebaseBoot.ready) return const Stream.empty();
    return _auth.authStateChanges();
  }

  User? get current => FirebaseBoot.ready ? _auth.currentUser : null;

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_readable(e));
    }
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String region,
    required String farmType,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      await cred.user!.updateDisplayName(name.trim());
      await _db.collection('users').doc(uid).set(
            AppUser(
              uid: uid,
              name: name.trim(),
              email: email.trim(),
              region: region,
              farmType: farmType,
            ).toMap()
              ..['createdAt'] = FieldValue.serverTimestamp(),
          );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_readable(e));
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_readable(e));
    }
  }

  Future<AppUser?> profile(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    final data = snap.data();
    return data == null ? null : AppUser.fromMap(data);
  }

  /// Firebase's raw codes are not something a farmer should ever read.
  String _readable(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address does not look right.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection. Check your signal and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a moment and try again.';
      default:
        return e.message ?? 'Something went wrong. Try again.';
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authState(),
);

/// The signed-in farmer's stored profile, including the region their reports
/// are attributed to on the outbreak map.
final userProfileProvider = FutureProvider<AppUser?>((ref) async {
  // Re-reads whenever sign-in state changes.
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth == null) return null;
  return ref.read(authServiceProvider).profile(auth.uid);
});
