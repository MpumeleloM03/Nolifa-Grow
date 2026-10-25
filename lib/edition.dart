/// Which app this build is. Nolifa and Nolifa Grow share one code base and one
/// backend; the edition decides who may use it and what it is called.
///
///  * [Edition.nolifa]: the main app. Everything in one place, for farmers,
///    households and drivers, with focus areas for the farm, delivery and the
///    marketplace.
///  * [Edition.grow]: Nolifa Grow, the focused app for farmers only.
enum Edition { nolifa, grow }

class AppEdition {
  static Edition current = Edition.nolifa;

  static bool get isGrow => current == Edition.grow;

  /// The name on the home screen, the sign-in page and in messages.
  static String get name => isGrow ? 'Nolifa Grow' : 'Nolifa';

  /// Whether this build is meant for someone who signed up with [role]
  /// ('farmer', 'community' or 'driver'). Nolifa takes everyone.
  static bool allowsRole(String role) => !isGrow || role == 'farmer';
}
