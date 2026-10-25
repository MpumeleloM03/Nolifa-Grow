import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_grow/edition.dart';

void main() {
  tearDown(() => AppEdition.current = Edition.nolifa);

  test('Nolifa takes every role and is called Nolifa', () {
    AppEdition.current = Edition.nolifa;
    expect(AppEdition.name, 'Nolifa');
    for (final r in ['farmer', 'community', 'driver']) {
      expect(AppEdition.allowsRole(r), isTrue);
    }
  });

  test('Nolifa Grow is for farmers only', () {
    AppEdition.current = Edition.grow;
    expect(AppEdition.name, 'Nolifa Grow');
    expect(AppEdition.allowsRole('farmer'), isTrue);
    expect(AppEdition.allowsRole('community'), isFalse);
    expect(AppEdition.allowsRole('driver'), isFalse);
  });
}
