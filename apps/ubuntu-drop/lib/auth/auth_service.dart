import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb show AuthException, GoTrueClient, User;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot, deleteMyAccount, supabaseReadyProvider;

import 'auth_user.dart';
import 'device_accounts.dart';

/// Email and password sign-in. Uses Supabase when it is connected and accounts
/// stored on the phone when it is not, so callers never care which one is live.
class AuthService {
  AuthService({required this.useCloud, DeviceAccounts? accounts})
    : _devices = accounts ?? DeviceAccounts();

  final bool useCloud;
  final DeviceAccounts _devices;

  /// True when accounts live on this phone only.
  bool get isLocal => !useCloud;

  sb.GoTrueClient get _auth => SupabaseBoot.client.auth;

  /// The signed-in person now, then again whenever that changes.
  Stream<AuthUser?> authState() => isLocal
      ? _devices.watchSession()
      // The first event carries the saved session, so a returning person stays in.
      : _auth.onAuthStateChange.map((e) => _fromSupabase(e.session?.user));

  static AuthUser? _fromSupabase(sb.User? u) {
    if (u == null) return null;
    final email = u.email ?? '';
    final name = ((u.userMetadata?['name'] as String?) ?? '').trim();
    return AuthUser(
      uid: u.id,
      // The email is private, so it never stands in for a missing name.
      name: name.isNotEmpty ? name : 'Neighbour',
      email: email,
    );
  }

  /// Signs in with email and password, on Supabase or on this phone.
  Future<void> signIn(String email, String password) async {
    if (isLocal) {
      await _devices.signIn(email: email, password: password);
      return;
    }
    try {
      await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on sb.AuthException catch (e) {
      throw AuthException(_readable(e));
    } catch (e) {
      throw AuthException(_offline);
    }
  }

  /// Creates an account and signs it in. The name is what neighbours see.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    if (isLocal) {
      await _devices.signUp(name: name, email: email, password: password);
      return;
    }
    final problem =
        checkName(name) ?? checkEmail(email) ?? checkPassword(password);
    if (problem != null) throw AuthException(problem);
    try {
      final res = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {'name': name.trim()},
      );
      if (res.session == null) {
        throw const AuthException('Check your email to confirm the account, then sign in.');
      }
    } on AuthException {
      rethrow;
    } on sb.AuthException catch (e) {
      throw AuthException(_readable(e));
    } catch (e) {
      throw AuthException(_offline);
    }
  }

  /// Deletes the account and everything stored for it. On the shared database
  /// that includes ID photos and records. Throws a [StateError] with a plain
  /// reason if it cannot be done yet (an order in progress, an open dispute).
  Future<void> deleteAccount() async {
    if (isLocal) return _devices.deleteCurrent();
    await deleteMyAccount();
  }

  /// Ends the session. Nothing is deleted.
  Future<void> signOut() => isLocal ? _devices.signOut() : _auth.signOut();

  /// Emails a password reset link. Needs Supabase.
  Future<void> sendReset(String email) async {
    if (isLocal) {
      throw const AuthException(
        'Password reset needs the shared database. Accounts in Local mode only live on this phone, so create a new one.',
      );
    }
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on sb.AuthException catch (e) {
      throw AuthException(_readable(e));
    } catch (e) {
      throw AuthException(_offline);
    }
  }

  /// True when this account carries the water provider permission
  /// (app_metadata `utility == true`). Always false in Local mode.
  Future<bool> utilityClaim() async {
    if (isLocal) return false;
    try {
      await _auth.refreshSession();
      return _auth.currentUser?.appMetadata['utility'] == true;
    } catch (e) {
      debugPrint('auth: could not read claims: $e');
      return false;
    }
  }

  static const _offline = 'No internet. Check your signal and try again.';

  /// Raw server messages are not something a person should ever read.
  static String _readable(sb.AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'Email or password is not right. Check both and try again.';
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'An account with that email already exists. Sign in instead.';
    }
    if (m.contains('password') && (m.contains('least') || m.contains('weak'))) {
      return 'Use at least 8 characters, with letters and a number.';
    }
    if (m.contains('valid email') || m.contains('invalid email')) {
      return 'That email address does not look right.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Too many tries. Wait a minute and try again.';
    }
    if (m.contains('not confirmed')) {
      return 'Confirm your email first, then sign in.';
    }
    return 'Something went wrong on our side. Try again in a moment.';
  }
}

/// The one [AuthService], on Supabase or on-device depending on boot.
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(useCloud: ref.watch(supabaseReadyProvider)),
);

/// Who is signed in, as a stream the gate rebuilds on.
final authStateProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authServiceProvider).authState(),
);

/// The signed-in person. Null when signed out or still loading.
final currentUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(authStateProvider).valueOrNull,
);

/// Whether the signed-in person works for the water provider. False until the
/// sign-in token has been read.
final utilityClaimProvider = FutureProvider<bool>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.uid));
  if (uid == null) return false;
  return ref.watch(authServiceProvider).utilityClaim();
});
