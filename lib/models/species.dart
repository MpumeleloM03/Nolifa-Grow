/// The kinds of livestock a farmer can keep on the register.
///
/// Each species has its own classes (a female cow is a cow, a female goat is a
/// doe), its own common breeds in South Africa and its own list of diseases,
/// so the symptom checker never offers "milk drop in a stallion".
enum Species {
  cattle('Cattle', 'Cow', '🐄', ['cow', 'bull', 'heifer', 'steer', 'calf'],
      ['Nguni', 'Bonsmara', 'Brahman', 'Afrikaner', 'Drakensberger', 'Holstein', 'Jersey', 'Angus']),
  goat('Goats', 'Goat', '🐐', ['doe', 'buck', 'kid', 'wether'],
      ['Boer goat', 'Savanna', 'Kalahari Red', 'Indigenous veld goat', 'Saanen']),
  sheep('Sheep', 'Sheep', '🐑', ['ewe', 'ram', 'lamb', 'wether'],
      ['Dorper', 'Merino', 'Damara', 'Meatmaster', 'Namaqua Afrikaner', 'Persian']),
  horse('Horses', 'Horse', '🐴', ['mare', 'stallion', 'gelding', 'filly', 'colt', 'foal'],
      ['Boerperd', 'Nooitgedachter', 'Basuto pony', 'Thoroughbred', 'SA Warmblood']);

  final String plural;
  final String singular;
  final String emoji;
  final List<String> sexes;
  final List<String> breeds;
  const Species(this.plural, this.singular, this.emoji, this.sexes, this.breeds);

  String get defaultSex => sexes.first;

  /// How much water this animal drinks next to a cow. Goats and sheep drink
  /// roughly a seventh of what a cow does; a horse a little less than a cow.
  double get waterWeight => switch (this) {
        Species.cattle => 1.0,
        Species.horse => 0.9,
        Species.goat => 0.15,
        Species.sheep => 0.15,
      };

  /// "12 goats" or "1 horse".
  String count(int n) => '$n ${n == 1 ? singular.toLowerCase() : plural.toLowerCase()}';

  static Species parse(String? raw) =>
      Species.values.firstWhere((s) => s.name == raw, orElse: () => Species.cattle);

  /// Finds the species a word belongs to ("goats", "Sheep", "stallion").
  static Species? fromWord(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final s in Species.values) {
      if (v == s.name || v == s.plural.toLowerCase() || v == s.singular.toLowerCase()) return s;
      if (s.sexes.contains(v)) return s;
    }
    return null;
  }
}
