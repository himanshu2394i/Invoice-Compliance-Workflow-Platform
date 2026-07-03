import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/features/capture/review_screen.dart';

void main() {
  test('confidence map parses and drives autofill thresholds', () {
    final preview = InvoiceOCRPreview.fromJson({
      'ocr_available': true,
      'invoice_number': 'MORDE0031291',
      'seller_gstin': '06AAAAA0003A1Z3',
      'gross_amount': 126291,
      'confidence': {
        'invoice_number': 0.96, // high: fill silently
        'seller_gstin': 0.82, // medium: fill with verify cue
        'gross_amount': 0.55, // low: do not fill
      },
      'warnings': ['AI could not read the total amount clearly - please verify it.'],
    });

    expect(preview.shouldFill('invoice_number'), isTrue);
    expect(preview.isHighConfidence('invoice_number'), isTrue);

    expect(preview.shouldFill('seller_gstin'), isTrue);
    expect(preview.isHighConfidence('seller_gstin'), isFalse);

    expect(preview.shouldFill('gross_amount'), isFalse);
    // A field with no confidence entry is low confidence too.
    expect(preview.shouldFill('buyer_gstin'), isFalse);

    expect(preview.warnings, hasLength(1));
  });

  test('Claude extraction fields parse from the preview payload', () {
    final preview = InvoiceOCRPreview.fromJson({
      'ocr_available': true,
      'invoice_number': 'A260000218',
      'invoice_date': '2026-06-09',
      'payment_type': 'CASH',
      'buyer_name': 'Airplaza Retail Holdings Pvt Ltd',
      'confidence': {
        'invoice_date': 0.92,
        'payment_type': 0.75,
        'buyer_name': 0.88,
      },
    });
    expect(preview.invoiceDate, '2026-06-09');
    expect(preview.paymentType, 'CASH');
    expect(preview.buyerName, 'Airplaza Retail Holdings Pvt Ltd');
    expect(preview.shouldFill('invoice_date'), isTrue);
    expect(preview.isHighConfidence('invoice_date'), isTrue);
    expect(preview.shouldFill('payment_type'), isTrue);
    expect(preview.isHighConfidence('payment_type'), isFalse);
  });

  test('a server without confidence data keeps legacy fill behavior', () {
    final preview = InvoiceOCRPreview.fromJson({
      'ocr_available': true,
      'invoice_number': 'A260000218',
    });
    expect(preview.confidence, isEmpty);
    expect(preview.shouldFill('invoice_number'), isTrue);
    expect(preview.isHighConfidence('invoice_number'), isFalse);
  });

  test('helper text distinguishes high from medium confidence fills', () {
    expect(
      ocrFieldHelperText({'buyer_gstin'}, 'buyer_gstin'),
      ocrFilledHelperText,
    );
    expect(
      ocrFieldHelperText({}, 'invoice_number',
          highConfidenceFields: {'invoice_number'}),
      ocrHighConfidenceHelperText,
    );
    expect(ocrFieldHelperText({}, 'tax_amount'), isNull);
  });
}
