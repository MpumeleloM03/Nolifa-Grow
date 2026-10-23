import 'dart:typed_data';
import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ubuntu_core/ubuntu_core.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _d(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}';
String _q(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

/// The page size of a 100 x 60 mm thermal label.
const labelFormat = PdfPageFormat(100 * PdfPageFormat.mm, 60 * PdfPageFormat.mm, marginAll: 3 * PdfPageFormat.mm);

pw.Widget _barcode(String data, {double h = 34}) => pw.BarcodeWidget(
      barcode: Barcode.code128(),
      data: data,
      height: h,
      drawText: false,
    );

/// The tag stuck on a stored lot: scannable tag code, what it is, whose it is,
/// which room and bay, how much, when it came in at what temperature, and the
/// use-by date.
Future<Uint8List> lotTagPdf(StockLot lot) async {
  final tag = lot.tag ?? lot.id;
  final doc = pw.Document(title: 'Tag $tag');
  doc.addPage(pw.Page(
    pageFormat: labelFormat,
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('NOLIFA WAREHOUSE', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
        pw.Text(lot.hub, style: const pw.TextStyle(fontSize: 7)),
      ]),
      pw.SizedBox(height: 2),
      pw.Text(lot.productName, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      pw.Text('${lot.farmName}  -  ${_q(lot.qty)} ${lot.unit}', style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 3),
      _barcode(tag),
      pw.SizedBox(height: 1),
      pw.Center(child: pw.Text(tag, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 2))),
      pw.Spacer(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('${lot.zone.label.toUpperCase()} ${lot.zone.band}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text('BAY ${lot.bay ?? '-'}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('IN ${lot.receivedAt == null ? '-' : _d(lot.receivedAt!)} at ${lot.receivedTempC?.toStringAsFixed(1) ?? '-'} C', style: const pw.TextStyle(fontSize: 8)),
        pw.Text('USE BY ${_d(lot.useBy)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ]),
    ]),
  ));
  return doc.save();
}

/// What goes on a packed order: where it is going, what is in it, the weight of
/// each cut and the lot it came from, with a barcode for the driver to scan.
Future<Uint8List> dispatchLabelPdf({
  required String orderId,
  required String customer,
  required String dropArea,
  required String hub,
  required List<({String product, double kg, List<String> tags, DateTime? useBy})> items,
  required DateTime packedAt,
}) async {
  final doc = pw.Document(title: 'Order $orderId');
  doc.addPage(pw.Page(
    pageFormat: labelFormat,
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('NOLIFA DELIVERY', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
        pw.Text('KEEP COLD', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Text(orderId, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      _barcode(orderId, h: 22),
      pw.SizedBox(height: 2),
      pw.Text('To: $customer, $dropArea', style: const pw.TextStyle(fontSize: 8)),
      pw.Text('From: $hub, packed ${_d(packedAt)} ${packedAt.hour.toString().padLeft(2, '0')}:${packedAt.minute.toString().padLeft(2, '0')}',
          style: const pw.TextStyle(fontSize: 7)),
      pw.SizedBox(height: 2),
      for (final i in items.take(5))
        pw.Text('${_q(i.kg)} kg  ${i.product}  [${i.tags.join(', ')}]${i.useBy == null ? '' : '  use by ${_d(i.useBy!)}'}',
            style: const pw.TextStyle(fontSize: 7)),
    ]),
  ));
  return doc.save();
}
