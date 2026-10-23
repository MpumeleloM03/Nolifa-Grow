import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolifa_backoffice/labels.dart';
import 'package:ubuntu_core/ubuntu_core.dart';

void main() {
  final lot = StockLot(
    id: 'dep-1',
    hub: 'Durban hub',
    farmerId: 'f',
    farmName: 'Fatboy Butcheries',
    productName: 'Beef mince',
    category: Category.meat,
    unit: 'kg',
    qty: 40,
    remaining: 40,
    zone: StorageZone.chilled,
    useBy: DateTime(2026, 11, 2),
    expectedAt: DateTime(2026, 10, 27),
    status: LotStatus.stored,
    tag: 'NLF-DBN-0007',
    bay: 'C1-07',
    receivedAt: DateTime(2026, 10, 27, 8),
    receivedTempC: 2.4,
  );

  test('a lot tag prints as a one-page PDF', () async {
    final bytes = await lotTagPdf(lot);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(1500));
  });

  test('a dispatch label prints with the order, the weights and the lot tags', () async {
    final bytes = await dispatchLabelPdf(
      orderId: 'UD-1',
      customer: 'Thandi',
      dropArea: 'Umlazi',
      hub: 'Durban hub',
      packedAt: DateTime(2026, 10, 27, 9),
      items: [(product: 'Beef mince', kg: 2.04, tags: ['NLF-DBN-0007'], useBy: DateTime(2026, 11, 2))],
    );
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
