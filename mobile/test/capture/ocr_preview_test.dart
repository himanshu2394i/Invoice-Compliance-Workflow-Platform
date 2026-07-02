import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/features/capture/review_screen.dart';

void main() {
  test('InvoiceOCRPreview parses extracted fields from API response', () {
    final preview = InvoiceOCRPreview.fromJson({
      'ocr_available': true,
      'invoice_number': 'A260000218',
      'seller_gstin': '06AAAAA0003A1Z3',
      'buyer_gstin': '06AAAAA0013A1ZD',
      'taxable_amount': 10393.45,
      'gross_amount': 10913.0,
    });

    expect(preview.ocrAvailable, isTrue);
    expect(preview.invoiceNumber, 'A260000218');
    expect(preview.sellerGstin, '06AAAAA0003A1Z3');
    expect(preview.buyerGstin, '06AAAAA0013A1ZD');
    expect(preview.taxableAmount, 10393.45);
    expect(preview.grossAmount, 10913.0);
  });

  test('OCR helper text is shown only for OCR-filled fields', () {
    const filledFields = {'invoice_number', 'gross_amount'};

    expect(
      ocrFieldHelperText(filledFields, 'invoice_number'),
      ocrFilledHelperText,
    );
    expect(ocrFieldHelperText(filledFields, 'buyer_gstin'), isNull);
  });
}
