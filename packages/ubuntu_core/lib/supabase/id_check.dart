/// Checks that can be done on the phone before anything is sent. They catch
/// typing mistakes. They do not prove who someone is: a person at Nolifa still
/// compares the ID photo and the selfie before a farm is approved.

class IdCheck {
  final bool ok;
  final String message;
  final DateTime? born;
  final bool? citizen;
  const IdCheck(this.ok, this.message, {this.born, this.citizen});
}

/// South African ID number: YYMMDD SSSS C A Z. Thirteen digits, a real date of
/// birth, citizenship 0 or 1, and a Luhn check digit.
IdCheck checkSaId(String raw, {DateTime? now}) {
  final id = raw.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^\d{13}$').hasMatch(id)) return const IdCheck(false, 'An ID number is 13 digits.');
  final yy = int.parse(id.substring(0, 2));
  final mm = int.parse(id.substring(2, 4));
  final dd = int.parse(id.substring(4, 6));
  final today = now ?? DateTime.now();
  var year = 2000 + yy;
  if (year > today.year) year -= 100;
  final born = DateTime(year, mm, dd);
  if (mm < 1 || mm > 12 || born.month != mm || born.day != dd) {
    return const IdCheck(false, 'The date of birth in that number is not a real date.');
  }
  if (born.isAfter(today)) return const IdCheck(false, 'That date of birth is in the future.');
  final adult = DateTime(born.year + 18, born.month, born.day);
  if (adult.isAfter(today)) return const IdCheck(false, 'You must be 18 or older to sell on Nolifa.');
  final c = int.parse(id[10]);
  if (c != 0 && c != 1) return const IdCheck(false, 'That ID number is not valid. Check each digit.');
  var sum = 0;
  for (var i = 0; i < 13; i++) {
    var d = int.parse(id[12 - i]);
    if (i.isOdd) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  if (sum % 10 != 0) return const IdCheck(false, 'That ID number is not valid. Check each digit.');
  return IdCheck(true, 'ID number looks right.', born: born, citizen: c == 0);
}

/// CIPC company number, for example 2015/123456/07. Co-operatives use the same
/// shape with /24. An empty answer is allowed: a sole farmer need not have one.
String? checkCompanyNumber(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  if (!RegExp(r'^\d{4}/\d{6}/\d{2}$').hasMatch(v)) {
    return 'Use the CIPC format, like 2015/123456/07.';
  }
  final year = int.parse(v.substring(0, 4));
  if (year < 1900 || year > DateTime.now().year) return 'The year in that number is not right.';
  return null;
}

/// South African mobile numbers, with or without +27.
String? checkSaPhone(String raw) {
  final v = raw.replaceAll(RegExp(r'[\s\-()]'), '');
  if (RegExp(r'^(\+27|0027|0)[6-8]\d{8}$').hasMatch(v)) return null;
  return 'Use a South African mobile number, like 082 123 4567.';
}
