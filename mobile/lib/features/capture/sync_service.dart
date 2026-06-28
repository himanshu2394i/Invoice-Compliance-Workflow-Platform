import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/bundle.dart';
import '../../core/storage/hive_service.dart';

class SyncService {
  final Dio _dio;

  SyncService({Dio? dio}) : _dio = dio ?? buildDio();

  /// Sync all pending (status = 'pending' | 'failed') bundles to the backend.
  /// Each bundle:
  ///   1. POST /api/v1/invoices/ledger-upload  → creates invoice + uploads primary photo
  ///   2. POST /api/v1/invoices/{id}/documents  → uploads each supporting photo
  ///
  /// Returns (synced, failed) counts.
  Future<(int, int)> syncPending() async {
    final pending = HiveService.pendingBundles();
    int synced = 0, failed = 0;

    for (final bundle in pending) {
      try {
        await _syncBundle(bundle);
        await HiveService.updateBundleStatus(bundle.localId, 'synced');
        synced++;
      } catch (e) {
        await HiveService.updateBundleStatus(
          bundle.localId,
          'failed',
          error: e.toString(),
        );
        failed++;
      }
    }
    return (synced, failed);
  }

  Future<void> _syncBundle(QueuedBundle bundle) async {
    final primary = bundle.photos.firstWhere((p) => p.isPrimary);
    final supporting = bundle.photos.where((p) => !p.isPrimary).toList();

    // Step 1: Upload primary invoice photo
    final invoiceId = await _uploadLedgerInvoice(bundle, primary);

    // Step 2: Upload each supporting document
    for (final photo in supporting) {
      await _uploadSupportingDoc(invoiceId, photo);
    }
  }

  Future<String> _uploadLedgerInvoice(
      QueuedBundle bundle, QueuedPhoto primary) async {
    final formData = FormData.fromMap({
      'invoice_number': bundle.invoiceNumber,
      'entity_gstin': bundle.entityGstin,
      'buyer_gstin': bundle.buyerGstin,
      'buyer_name': bundle.buyerName,
      'invoice_date': bundle.invoiceDate,
      'taxable_amount': bundle.taxableAmount.toString(),
      'total_amount': bundle.totalAmount.toString(),
      'file': await MultipartFile.fromFile(
        primary.localPath,
        filename: '${bundle.invoiceNumber}.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });

    final resp = await _dio.post(Endpoints.ledgerUpload, data: formData);
    final invoiceId = resp.data['invoice']?['id'] as String?;
    if (invoiceId == null) throw Exception('Server did not return invoice id');
    return invoiceId;
  }

  Future<void> _uploadSupportingDoc(String invoiceId, QueuedPhoto photo) async {
    final formData = FormData.fromMap({
      'document_type': photo.documentType,
      'label': photo.label,
      'file': await MultipartFile.fromFile(
        photo.localPath,
        filename: '${photo.documentType.toLowerCase()}.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    await _dio.post(Endpoints.invoiceDocuments(invoiceId), data: formData);
  }
}

// Singleton instance shared across the app
final syncService = SyncService();
