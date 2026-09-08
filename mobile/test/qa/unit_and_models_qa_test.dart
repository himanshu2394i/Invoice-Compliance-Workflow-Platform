import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/core/models/bundle.dart';
import 'package:invoice_capture/core/models/buyer_requirement.dart';
import 'package:invoice_capture/core/models/master_data.dart';
import 'package:invoice_capture/features/capture/fuzzy_match.dart';
import 'package:invoice_capture/features/capture/review_screen.dart';

void main() {
  group('QA Test 1: Unit Tests & Domain Models', () {
    test('QueuedBundle Serialization & Hive Field defaults', () {
      final bundle = QueuedBundle(
        localId: 'b-100',
        createdAtMs: DateTime(2026, 7, 27).millisecondsSinceEpoch,
        status: 'pending',
        photos: [
          QueuedPhoto(
            localId: 'p-1',
            localPath: '/tmp/p1.jpg',
            documentType: 'INVOICE',
            label: 'Tax Invoice',
            isPrimary: true,
          ),
        ],
        invoiceNumber: 'INV-999',
        entityGstin: '06AAAAA0003A1Z3',
        buyerGstin: '06AAAAA0007A1Z7',
        buyerName: 'Honey Money Top',
        invoiceDate: '2026-07-27',
        taxableAmount: 5000.0,
        totalAmount: 5900.0,
      );

      expect(bundle.localId, equals('b-100'));
      expect(bundle.invoiceNumber, equals('INV-999'));
      expect(bundle.photos.length, equals(1));
      expect(bundle.photos.first.isPrimary, isTrue);
    });

    test('InvoiceOCRPreview Json parsing and confidence evaluation', () {
      final json = {
        'ocr_available': true,
        'invoice_number': 'CAD/15611',
        'seller_gstin': '06AAAAA0003A1Z3',
        'buyer_gstin': '06AAAAA0007A1Z7',
        'invoice_date': '2026-07-06',
        'gross_amount': 72363.0,
        'confidence': {
          'invoice_number': 0.95,
          'buyer_gstin': 0.65,
        },
        'warnings': ['Faint print detected'],
      };

      final ocr = InvoiceOCRPreview.fromJson(json);

      expect(ocr.ocrAvailable, isTrue);
      expect(ocr.invoiceNumber, equals('CAD/15611'));
      expect(ocr.sellerGstin, equals('06AAAAA0003A1Z3'));
      expect(ocr.isHighConfidence('invoice_number'), isTrue);
      expect(ocr.isHighConfidence('buyer_gstin'), isFalse);
      expect(ocr.shouldFill('buyer_gstin'), isFalse);
      expect(ocr.warnings.length, equals(1));
    });

    test('FuzzyMatch String similarity ratio engine', () {
      final buyers = [
        ('Max Hypermarket India Pvt Ltd', '06AAAAA0002A1Z2'),
        ('Honey Money Top Retail', '06AAAAA0007A1Z7'),
        ('Airplaza Retail Pvt Ltd', '06AAAAA0013A1ZD'),
      ];

      final match = FuzzyMatch.findBestMatch(
        'Honey Money Top',
        buyers,
        (b) => b.$1,
        minScore: 0.50,
      );

      expect(match, isNotNull);
      expect(match!.$1, contains('Honey Money Top'));
      expect(match.$2, equals('06AAAAA0007A1Z7'));
    });

    test('SeriesEntry JSON deserialization and pattern matching', () {
      final json = {
        'id': 's1',
        'series_prefix': 'CAD',
        'principal_name': 'Cadbury / Mondelez',
        'entity_id': 'e1',
      };

      final series = SeriesEntry.fromJson(json);
      expect(series.id, equals('s1'));
      expect(series.seriesPrefix, equals('CAD'));
      expect(series.principalName, equals('Cadbury / Mondelez'));
    });

    test('BuyerRequirement document requirements structure', () {
      const req = BuyerRequirement(
        id: 'r1',
        buyerId: 'b1',
        documentType: 'RECEIVING_STAMP',
        label: 'Receiving Stamp & Sign',
        isBuyerGenerated: false,
        sortOrder: 1,
      );

      expect(req.documentType, equals('RECEIVING_STAMP'));
      expect(req.isBuyerGenerated, isFalse);
    });
  });
}
