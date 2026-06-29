import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:invoice_capture/core/config/server_config.dart';
import 'package:invoice_capture/core/models/bundle.dart';
import 'package:invoice_capture/core/storage/hive_service.dart';
import 'package:invoice_capture/features/capture/sync_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(QueuedPhotoAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(QueuedBundleAdapter());
    }
    await Hive.openBox<QueuedBundle>('queued_bundles');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('syncPending uploads a queued bundle using real Meridian invoice data',
      () async {
    // Real, fully cross-checked figures from invoice_extraction.md entry [1]:
    // Meridian Brothers (06AAAAA0003A1Z3) -> Vishal Mega Mart (06AAAAA0013A1ZD).
    final photoFile = File(p.join(tempDir.path, 'photo.jpg'));
    await photoFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]); // minimal JPEG marker bytes

    final bundle = QueuedBundle(
      localId: 'local-1',
      invoiceNumber: 'A260000218',
      entityGstin: '06AAAAA0003A1Z3',
      buyerGstin: '06AAAAA0013A1ZD',
      buyerName: 'Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)',
      invoiceDate: '2026-06-09',
      taxableAmount: 10393.45,
      totalAmount: 10913.00,
      photos: [
        QueuedPhoto(
          localId: 'photo-1',
          localPath: photoFile.path,
          documentType: 'INVOICE',
          label: 'Tax Invoice',
          isPrimary: true,
        ),
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await HiveService.saveBundle(bundle);

    final dio = Dio();
    // The default FullHttpRequestMatcher requires the mocked `data` to match
    // the actual request body exactly. The real request body here is
    // multipart FormData built from a file on disk (boundary + content
    // differ per the temp file), and we only care about asserting the
    // upload flow, not the exact form contents, so use UrlRequestMatcher
    // (route + method only) instead of trying to construct a byte-identical
    // FormData matcher.
    final adapter = DioAdapter(
      dio: dio,
      matcher: const UrlRequestMatcher(matchMethod: true),
    );
    // UrlRequestMatcher compares against RequestOptions.path, which Dio sets
    // to the full absolute URL when given one (as Endpoints.ledgerUpload
    // produces), so the mock route must include ServerConfig.baseUrl rather
    // than a bare path.
    adapter.onPost(
      '${ServerConfig.baseUrl}/api/v1/invoices/ledger-upload',
      (server) => server.reply(201, {
        'invoice': {'id': 'server-invoice-id-1'},
        'status': 'INGESTED',
      }),
    );

    final service = SyncService(dio: dio);
    final (synced, failed) = await service.syncPending();

    expect(synced, 1);
    expect(failed, 0);

    final updated = HiveService.bundleBox.get('local-1');
    expect(updated?.status, 'synced');
  });

  test(
      'a retried sync after a supporting-doc failure does not re-create the invoice',
      () async {
    final photoFile = File(p.join(tempDir.path, 'photo.jpg'));
    await photoFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
    final gateEntryFile = File(p.join(tempDir.path, 'gate_entry.jpg'));
    await gateEntryFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

    final bundle = QueuedBundle(
      localId: 'local-2',
      invoiceNumber: 'A260000219',
      entityGstin: '06AAAAA0003A1Z3',
      buyerGstin: '06AAAAA0013A1ZD',
      buyerName: 'Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)',
      invoiceDate: '2026-06-09',
      taxableAmount: 10393.45,
      totalAmount: 10913.00,
      photos: [
        QueuedPhoto(
          localId: 'photo-2',
          localPath: photoFile.path,
          documentType: 'INVOICE',
          label: 'Tax Invoice',
          isPrimary: true,
        ),
        QueuedPhoto(
          localId: 'photo-3',
          localPath: gateEntryFile.path,
          documentType: 'GATE_ENTRY_NOTE',
          label: 'Gate Entry / Discrepancy Note',
          isPrimary: false,
        ),
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await HiveService.saveBundle(bundle);

    final dio = Dio();
    final adapter = DioAdapter(
      dio: dio,
      matcher: const UrlRequestMatcher(matchMethod: true),
    );

    // http_mock_adapter resolves each request against whichever registered
    // matcher for the route was added *last* (see Recording.mockResponse),
    // and a plain reply()'s status code is fixed at registration time -- it
    // can't vary per actual request. So counting must happen inside a
    // replyCallback's data callback (which runs once per matched request),
    // and "first call fails, second succeeds" is simulated by re-registering
    // the documents route with a new response between the two sync attempts.
    var ledgerUploadCalls = 0;
    adapter.onPost(
      '${ServerConfig.baseUrl}/api/v1/invoices/ledger-upload',
      (server) => server.replyCallback(201, (options) {
        ledgerUploadCalls++;
        return {
          'invoice': {'id': 'server-invoice-id-2'},
          'status': 'INGESTED',
        };
      }),
    );

    var documentUploadCalls = 0;
    adapter.onPost(
      '${ServerConfig.baseUrl}/api/v1/invoices/server-invoice-id-2/documents',
      (server) => server.replyCallback(500, (options) {
        documentUploadCalls++;
        return {'error': 'simulated transient failure'};
      }),
    );

    final service = SyncService(dio: dio);

    // First attempt: primary upload succeeds, supporting-doc upload fails.
    final (synced1, failed1) = await service.syncPending();
    expect(synced1, 0);
    expect(failed1, 1);
    expect(ledgerUploadCalls, 1);
    expect(documentUploadCalls, 1);

    final afterFirstAttempt = HiveService.bundleBox.get('local-2');
    expect(afterFirstAttempt?.status, 'failed');
    expect(afterFirstAttempt?.remoteInvoiceId, 'server-invoice-id-2');

    // Now let the supporting-doc upload succeed for the retry.
    adapter.onPost(
      '${ServerConfig.baseUrl}/api/v1/invoices/server-invoice-id-2/documents',
      (server) => server.replyCallback(202, (options) {
        documentUploadCalls++;
        return {
          'document_id': 'doc-1',
          'invoice_id': 'server-invoice-id-2',
          'status': 'DOCUMENT_STORED_MATCHING_STARTED',
        };
      }),
    );

    // Retry: must reuse the already-created invoice (no second ledger-upload
    // call) and only re-send the supporting doc that never landed.
    final (synced2, failed2) = await service.syncPending();
    expect(synced2, 1);
    expect(failed2, 0);
    expect(ledgerUploadCalls, 1,
        reason:
            'retry must not re-create the invoice once remoteInvoiceId is known');
    expect(documentUploadCalls, 2);

    final afterRetry = HiveService.bundleBox.get('local-2');
    expect(afterRetry?.status, 'synced');
    expect(afterRetry?.photos.firstWhere((p) => !p.isPrimary).uploaded, true);
  });

  test('concurrent syncPending calls only upload each pending bundle once',
      () async {
    final photoFile = File(p.join(tempDir.path, 'photo.jpg'));
    await photoFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

    final bundle = QueuedBundle(
      localId: 'local-3',
      invoiceNumber: 'A260000220',
      entityGstin: '06AAAAA0003A1Z3',
      buyerGstin: '06AAAAA0013A1ZD',
      buyerName: 'Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)',
      invoiceDate: '2026-06-09',
      taxableAmount: 10393.45,
      totalAmount: 10913.00,
      photos: [
        QueuedPhoto(
          localId: 'photo-4',
          localPath: photoFile.path,
          documentType: 'INVOICE',
          label: 'Tax Invoice',
          isPrimary: true,
        ),
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await HiveService.saveBundle(bundle);

    final dio = Dio();
    final adapter = DioAdapter(
      dio: dio,
      matcher: const UrlRequestMatcher(matchMethod: true),
    );

    // Count via replyCallback's per-request data callback, not the outer
    // onPost callback -- the outer callback only runs once, at registration
    // time, so it can't observe how many real HTTP requests occur.
    var ledgerUploadCalls = 0;
    adapter.onPost(
      '${ServerConfig.baseUrl}/api/v1/invoices/ledger-upload',
      (server) => server.replyCallback(
        201,
        (options) {
          ledgerUploadCalls++;
          return {
            'invoice': {'id': 'server-invoice-id-3'},
            'status': 'INGESTED',
          };
        },
        // Delay so the two concurrent syncPending() calls below genuinely
        // overlap instead of completing sequentially.
        delay: const Duration(milliseconds: 50),
      ),
    );

    final service = SyncService(dio: dio);

    // Fire two syncs without awaiting the first -- mirrors a connectivity
    // callback and a manual "sync now" tap racing each other.
    final results = await Future.wait([
      service.syncPending(),
      service.syncPending(),
    ]);

    expect(ledgerUploadCalls, 1,
        reason: 'the second concurrent call must be a no-op, not a duplicate upload');

    final totalSynced = results.map((r) => r.$1).reduce((a, b) => a + b);
    expect(totalSynced, 1);

    final updated = HiveService.bundleBox.get('local-3');
    expect(updated?.status, 'synced');
  });
}
