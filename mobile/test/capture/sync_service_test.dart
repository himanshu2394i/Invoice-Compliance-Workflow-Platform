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
    Hive.registerAdapter(QueuedPhotoAdapter());
    Hive.registerAdapter(QueuedBundleAdapter());
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
}
