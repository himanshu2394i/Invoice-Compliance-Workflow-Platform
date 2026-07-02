import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/features/capture/bundle_provider.dart';

void main() {
  test(
      'additional invoice pages are queued as invoice pages, not matchable supporting documents',
      () {
    const session = CaptureSession(
      sessionId: 'session-1',
      invoicePhotoPaths: ['/tmp/page1.jpg', '/tmp/page2.jpg'],
      invoiceNumber: 'A260000218',
      entityGstin: '06AAAAA0003A1Z3',
      buyerGstin: '06AAAAA0013A1ZD',
      buyerName: 'Airplaza Retail Holdings Pvt Ltd',
      invoiceDate: '2026-06-09',
      taxableAmount: 10393.45,
      totalAmount: 10913,
    );

    final bundle = session.toBundle();

    expect(bundle.photos, hasLength(2));
    expect(bundle.photos[0].documentType, 'INVOICE');
    expect(bundle.photos[0].isPrimary, true);
    expect(bundle.photos[0].pageNumber, 1);
    expect(bundle.photos[1].documentType, 'INVOICE_PAGE');
    expect(bundle.photos[1].isPrimary, false);
    expect(bundle.photos[1].pageNumber, 2);
  });
}
