import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import 'package:supabase_flutter/supabase_flutter.dart' as sb show AuthException;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, deleteMyAccount;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import 'local_backend.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Accounts, backed by Supabase when it is configured and by on-device storage
/// when it is not.
///
/// Callers only ever see [AppUser], so nothing above this layer knows or cares
/// which backend is live.
class AuthService {
  SupabaseClient get _db => SupabaseBoot.client;
  GoTrueClient get _auth => _db.auth;
  LocalBackend get _local => LocalBackend.instance;

  bool get isLocal => !SupabaseBoot.ready;

  AppUser? _cached;
  AppUser? get current => _cached;

  Stream<AppUser?> authState() {
    if (isLocal) {
      return _local.watchSession().map((u) {
        _cached = u;
        return u;
      });
    }
    // The first event carries the saved session, so a returning farmer stays in.
    return _auth.onAuthStateChange.asyncMap((e) async {
      final u = e.session?.user;
      if (u == null) {
        _cached = null;
        return null;
      }
      AppUser? saved;
      try {
        saved = await profile(u.id);
      } catch (_) {
        // A slow profile read must never lock a signed-in farmer out.
      }
      _cached = saved ??
          AppUser(
            uid: u.id,
            name: (u.userMetadata?['name'] as String?) ?? '',
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
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } on sb.AuthException catch (e) {
      throw AuthException(_readable(e));
    } catch (e) {
      throw AuthException(_offline(e));
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
      final res = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {'name': name.trim()},
      );
      final user = res.user;
      if (user == null) throw const AuthException('Could not create the account. Try again.');
      if (res.session == null) {
        throw const AuthException('Check your email to confirm the account, then sign in.');
      }
      await _db.from('users').upsert({
        'uid': user.id,
        'data': AppUser(
          uid: user.id,
          name: name.trim(),
          email: email.trim(),
          region: region,
          farmType: farmType,
        ).toMap(),
      });
    } on AuthException {
      rethrow;
    } on sb.AuthException catch (e) {
      throw AuthException(_readable(e));
    } catch (e) {
      throw AuthException(_offline(e));
    }
  }

  /// Saves the details a farmer can change in Settings.
  Future<void> updateProfile({
    required String name,
    required String region,
    required String farmType,
  }) async {
    if (isLocal) {
      await _local.updateUser(name: name, region: region, farmType: farmType);
      return;
    }
    final u = _auth.currentUser;
    if (u == null) return;
    await _auth.updateUser(UserAttributes(data: {'name': name.trim()}));
    final old = (await _db.from('users').select('data').eq('uid', u.id).maybeSingle())?['data'] as Map?;
    await _db.from('users').upsert({
      'uid': u.id,
      'data': {
        ...?old?.cast<String, dynamic>(),
        'uid': u.id,
        'email': u.email ?? '',
        'name': name.trim(),
        'region': region,
        'farmType': farmType,
      },
    });
  }

  /// Demo accounts the judges can open with one tap, one per role. The sign-in
  /// screen shows the emails and password so they can also be typed.
  static const demoPassword = 'NolifaDemo1';
  static const demoEmails = {
    'farmer': 'farmer@demo.nolifa.co.za',
    'community': 'community@demo.nolifa.co.za',
    'driver': 'driver@demo.nolifa.co.za',
  };

  /// Signs in to a demo account, creating it the first time if it is missing.
  Future<void> demoSignIn(String role) async {
    final email = demoEmails[role]!;
    try {
      await signIn(email, demoPassword);
      return;
    } on AuthException {
      // Not created yet; make it below.
    }
    await signUp(
      name: switch (role) {
        'community' => 'Lindiwe Ngcobo',
        'driver' => 'Sipho Dlamini',
        _ => 'Thandi Mkhize',
      },
      email: email,
      password: demoPassword,
      region: role == 'community' ? 'Greater Durban' : 'KZN Midlands',
      farmType: role == 'farmer' ? 'both' : role,
    );
  }

  Future<void> signOut() => isLocal ? _local.signOut() : _auth.signOut();

  /// Deletes the account and everything stored for it. Throws a [StateError]
  /// with a plain reason if it cannot be done yet.
  Future<void> deleteAccount() async {
    if (isLocal) return _local.deleteCurrentUser();
    await deleteMyAccount();
  }

  Future<void> sendReset(String email) async {
    if (isLocal) {
      throw const AuthException(
          'Password reset needs the shared database. In local mode, just sign in with your email.');
    }
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on sb.AuthException catch (e) {
      throw AuthException(_readable(e));
    } catch (e) {
      throw AuthException(_offline(e));
    }
  }

  Future<AppUser?> profile(String uid) async {
    if (isLocal) return _local.currentUser();
    final row = await _db.from('users').select('data').eq('uid', uid).maybeSingle();
    final data = row?['data'];
    return data == null ? null : AppUser.fromMap(Map<String, dynamic>.from(data as Map));
  }

  String _offline(Object e) => 'We could not reach the server. Check your connection, then try again.';

  /// Raw server codes are not something a farmer should ever read.
  String _readable(sb.AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'Email or password is incorrect.';
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'An account already exists for that email.';
    }
    if (m.contains('password') && (m.contains('least') || m.contains('weak'))) {
      return 'Password is too weak. Use at least 8 characters, with letters and a number.';
    }
    if (m.contains('valid email') || m.contains('invalid email')) {
      return 'That email address does not look right.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    if (m.contains('not confirmed')) {
      return 'Confirm your email first, then sign in.';
    }
    return e.message;
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
