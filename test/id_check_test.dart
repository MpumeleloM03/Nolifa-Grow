import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/members/id_check.dart';

void main() {
  final now = DateTime(2026, 10, 24);

  group('SA ID number', () {
    test('accepts a valid number and reads the birth date', () {
      final r = checkSaId('8001015009087', now: now);
      expect(r.ok, isTrue);
      expect(r.born, DateTime(1980, 1, 1));
      expect(r.citizen, isTrue);
    });

    test('spaces are ignored', () => expect(checkSaId('800101 5009 087', now: now).ok, isTrue));
    test('wrong length', () => expect(checkSaId('80010150090', now: now).ok, isFalse));
    test('letters', () => expect(checkSaId('80010150090ab', now: now).ok, isFalse));
    test('bad check digit', () => expect(checkSaId('8001015009088', now: now).ok, isFalse));
    test('impossible date', () => expect(checkSaId('8013015009087', now: now).ok, isFalse));
    test('31 February', () => expect(checkSaId('8002315009083', now: now).ok, isFalse));

    test('under 18 is refused', () {
      // 2012-05-05 born, check digit worked out below
      final base = '120505500908';
      var sum = 0;
      for (var i = 0; i < 12; i++) {
        var d = int.parse(base[11 - i]);
        if (i.isEven) {
          d *= 2;
          if (d > 9) d -= 9;
        }
        sum += d;
      }
      final id = '$base${(10 - sum % 10) % 10}';
      final r = checkSaId(id, now: now);
      expect(r.ok, isFalse);
      expect(r.message, contains('18'));
    });
  });

  group('company number and phone', () {
    test('empty company number is fine', () => expect(checkCompanyNumber(''), isNull));
    test('good number', () => expect(checkCompanyNumber('2015/123456/07'), isNull));
    test('bad shape', () => expect(checkCompanyNumber('12345'), isNotNull));
    test('future year', () => expect(checkCompanyNumber('2999/123456/07'), isNotNull));
    test('phone forms', () {
      expect(checkSaPhone('082 123 4567'), isNull);
      expect(checkSaPhone('+27821234567'), isNull);
      expect(checkSaPhone('0111234567'), isNotNull);
      expect(checkSaPhone('12345'), isNotNull);
    });
  });
}
