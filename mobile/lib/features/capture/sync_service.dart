import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/bundle.dart';
import '../../core/storage/hive_service.dart';

class SyncService {
  final Dio _dio;

  // Guards against two concurrent syncPending() calls (e.g. a connectivity
  // change and a manual "sync now" tap firing back-to-back) racing to upload
  // the same pending bundle twice.
  bool _isSyncing = false;

  SyncService({Dio? dio}) : _dio = dio ?? buildDio();

  /// Sync all pending (status = 'pending' | 'failed') bundles to the backend.
  /// Each bundle:
  ///   1. POST /api/v1/invoices/ledger-upload  → creates invoice + uploads primary photo
  ///   2. POST /api/v1/invoices/{id}/documents  → uploads each supporting photo
  ///
  /// Resumable: a bundle that already has a remoteInvoiceId (step 1 already
  /// succeeded) skips straight to uploading whichever supporting photos
  /// aren't yet marked `uploaded`, so a retry after a partial failure never
  /// re-creates the invoice or re-uploads documents that already landed.
  ///
  /// Returns (synced, failed) counts.
  Future<(int, int)> syncPending() async {
    if (_isSyncing) return (0, 0);
    _isSyncing = true;
    try {
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
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncBundle(QueuedBundle bundle) async {
    final primary = bundle.photos.firstWhere((p) => p.isPrimary);
    final supporting = bundle.photos.where((p) => !p.isPrimary).toList();

    // Step 1: Upload primary invoice photo (skip if a prior attempt already
    // created the invoice — the server is also idempotent on invoice_number
    // as a second line of defense, but checking first avoids the round trip).
    var invoiceId = bundle.remoteInvoiceId;
    if (invoiceId == null) {
      invoiceId = await _uploadLedgerInvoice(bundle, primary);
      bundle.remoteInvoiceId = invoiceId;
      await bundle.save();
    }

    // Step 2: Upload each supporting document not yet confirmed uploaded
    for (final photo in supporting) {
      if (photo.uploaded) continue;
      await _uploadSupportingDoc(invoiceId, photo);
      photo.uploaded = true;
      await bundle.save();
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
      if (bundle.paymentType != null) 'payment_type': bundle.paymentType,
      if (bundle.paymentTermsDays != null)
        'payment_terms_days': bundle.paymentTermsDays.toString(),
      if (bundle.buyerBranchId != null) 'buyer_branch_id': bundle.buyerBranchId,
      if (bundle.salesman != null) 'salesman': bundle.salesman,
      if (bundle.beat != null) 'beat': bundle.beat,
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
