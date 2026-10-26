/// Who is signed in. The same shape whether the account lives in Supabase or
/// on the phone.
class AuthUser {
  final String uid;
  final String name;
  final String email;
  const AuthUser({required this.uid, required this.name, required this.email});

  /// One letter for the avatar.
  String get initial {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    return source.isEmpty
        ? '?'
        : String.fromCharCode(source.runes.first).toUpperCase();
  }

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.uid == uid &&
      other.name == name &&
      other.email == email;

  @override
  int get hashCode => Object.hash(uid, name, email);
}

/// A sign-in problem in words a person can act on.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Shared checks, so Supabase and on-device accounts reject the same input.
String? checkName(String? v) => (v == null || v.trim().isEmpty)
    ? 'Add your name so neighbours know who you are.'
    : null;

String? checkEmail(String? v) {
  final s = v?.trim() ?? '';
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
      ? null
      : 'That email address does not look right.';
}

/// At least 8 characters with a letter and a number. The server enforces the same.
String? checkPassword(String? v) {
  if (v == null || v.length < 8) return 'Use at least 8 characters.';
  if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) return 'Use letters and at least one number.';
  return null;
}
