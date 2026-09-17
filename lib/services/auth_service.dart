import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import 'firebase_boot.dart';
import 'local_backend.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Accounts, backed by Firebase when it is configured and by on-device storage
/// when it is not.
///
/// Callers only ever see [AppUser], so nothing above this layer knows or cares
/// which backend is live.
class AuthService {
  fb.FirebaseAuth get _auth => fb.FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  LocalBackend get _local => LocalBackend.instance;

  bool get isLocal => !FirebaseBoot.ready;

  AppUser? _cached;
  AppUser? get current => _cached;

  Stream<AppUser?> authState() {
    if (isLocal) {
      return _local.watchSession().map((u) {
        _cached = u;
        return u;
      });
    }
    return _auth.authStateChanges().asyncMap((u) async {
      if (u == null) {
        _cached = null;
        return null;
      }
      _cached = await profile(u.uid) ??
          AppUser(
            uid: u.uid,
            name: u.displayName ?? '',
            email: u.email ?? '',
            region: '',
            farmType: 'both',
          );
      return _cached;
    });
  }

  Future<void> signIn(String email, String password) async {
    if (isLocal) {
      try {
        await _local.signIn(email);
      } catch (e) {
        throw AuthException(e.toString().replaceFirst('Exception: ', ''));
      }
      return;
    }
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on fb.FirebaseAuthException catch (e) {
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
    if (isLocal) {
      try {
        await _local.signUp(
          name: name,
          email: email,
          region: region,
          farmType: farmType,
        );
      } catch (e) {
        throw AuthException(e.toString().replaceFirst('Exception: ', ''));
      }
      return;
    }
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
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_readable(e));
    }
  }

  Future<void> signOut() => isLocal ? _local.signOut() : _auth.signOut();

  Future<void> sendReset(String email) async {
    if (isLocal) {
      throw const AuthException(
          'Password reset needs Firebase. In local mode, just sign in with your email.');
    }
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_readable(e));
    }
  }

  Future<AppUser?> profile(String uid) async {
    if (isLocal) return _local.currentUser();
    final snap = await _db.collection('users').doc(uid).get();
    final data = snap.data();
    return data == null ? null : AppUser.fromMap(data);
  }

  /// Firebase's raw codes are not something a farmer should ever read.
  String _readable(fb.FirebaseAuthException e) {
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

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authServiceProvider).authState(),
);

/// The signed-in farmer. Null when signed out.
final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authStateProvider).valueOrNull,
);
