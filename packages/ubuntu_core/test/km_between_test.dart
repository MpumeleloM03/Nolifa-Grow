import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  test('a place with no position gives no distance, not a crash', () {
    expect(kmBetween(double.nan, 31, -29.8, 31), 0);
    expect(kmBetween(-29.8, 31, -29.8, double.nan), 0);
  });

  test('the same point is no distance, and Durban to Pietermaritzburg is about 65 km', () {
    expect(kmBetween(-29.85, 31.02, -29.85, 31.02), 0);
    expect(kmBetween(-29.85, 31.02, -29.60, 30.38), inInclusiveRange(55, 75));
  });
}
