import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:invoice_capture/core/models/bundle.dart';
import 'package:invoice_capture/core/storage/hive_service.dart';
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

  group('capture draft persistence', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('draft_hive_test');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(QueuedPhotoAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(QueuedBundleAdapter());
      }
      await Hive.openBox<QueuedBundle>('capture_draft');
    });

    tearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('capture session can round-trip through the local draft store',
        () async {
      const session = CaptureSession(
        sessionId: 'draft-1',
        invoicePhotoPaths: ['/tmp/page1.jpg', '/tmp/page2.jpg'],
        invoiceNumber: 'CAD/15442',
        entityGstin: '06AAAAA0003A1Z3',
        buyerGstin: '06AAAAA0010A1ZA',
        buyerName: 'Elenta Mart Private Limited',
        invoiceDate: '2026-06-06',
        taxableAmount: 3632.65,
        totalAmount: 3814,
        paymentType: 'CREDIT',
        paymentTermsDays: 7,
      );

      await HiveService.saveCaptureDraft(session.toDraftBundle());

      final restored = HiveService.loadCaptureDraft();
      expect(restored, isNotNull);
      expect(restored!.status, 'draft');

      final restoredSession = CaptureSession.fromBundle(restored);
      expect(restoredSession.sessionId, 'draft-1');
      expect(restoredSession.invoicePhotoPaths,
          ['/tmp/page1.jpg', '/tmp/page2.jpg']);
      expect(restoredSession.invoiceNumber, 'CAD/15442');
      expect(restoredSession.paymentType, 'CREDIT');
      expect(restoredSession.paymentTermsDays, 7);
    });

    test('clearCaptureDraft removes the saved draft', () async {
      const session = CaptureSession(
        sessionId: 'draft-2',
        invoiceNumber: 'A260000218',
      );

      await HiveService.saveCaptureDraft(session.toDraftBundle());
      expect(HiveService.hasCaptureDraft(), true);

      await HiveService.clearCaptureDraft();
      expect(HiveService.hasCaptureDraft(), false);
    });
  });
}
