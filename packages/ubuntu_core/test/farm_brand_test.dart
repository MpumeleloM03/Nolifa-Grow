import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  tearDown(() => FarmBrands.instance.load(const []));

  Map<String, dynamic> row(String name, {String? logo, String? banner}) => {
        'uid': 'u-$name',
        'data': {'farmName': name, 'logo': logo, 'banner': banner},
      };

  test('an approved farm picture replaces the drawn badge, matched by name without case', () {
    expect(farmLogoImage('Green Hills'), isNull);
    FarmBrands.instance.load([row('Green Hills', logo: 'u1/logo.png', banner: 'u1/banner.jpg')]);
    expect(farmLogoImage('green hills '), isA<NetworkImage>());
    expect((farmBanner('Green Hills') as NetworkImage).url, endsWith('/storage/v1/object/public/farm-brand/u1/banner.jpg'));
  });

  test('a farm with no pictures keeps what it had, and demo farms keep their bundled art', () {
    FarmBrands.instance.load([row('Green Hills')]);
    expect(farmLogoImage('Green Hills'), isNull);
    expect(farmBanner('Fatboy Butcheries'), isA<AssetImage>());
  });

  test('listeners hear about a new picture once, not on every refresh', () {
    var n = 0;
    void on() => n++;
    FarmBrands.instance.addListener(on);
    final rows = [row('Green Hills', logo: 'u1/logo.png')];
    FarmBrands.instance.load(rows);
    FarmBrands.instance.load(rows);
    FarmBrands.instance.removeListener(on);
    expect(n, 1);
  });

  testWidgets('the farm tag shows initials until the logo arrives', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: FarmTag('Green Hills'))));
    expect(find.text('GH'), findsOneWidget);
    expect(find.text('Green Hills'), findsOneWidget);
  });
}
