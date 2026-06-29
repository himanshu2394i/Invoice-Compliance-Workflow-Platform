import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

// ─── Data Models ─────────────────────────────────────────────────────────────

class OwnerDashboard {
  final int totalInvoices;
  final double todayAmount;
  final int openExceptions;
  final int openDisputes;
  final int pendingReview;

  const OwnerDashboard({
    required this.totalInvoices,
    required this.todayAmount,
    required this.openExceptions,
    required this.openDisputes,
    required this.pendingReview,
  });

  factory OwnerDashboard.fromJson(Map<String, dynamic> j) => OwnerDashboard(
        totalInvoices: (j['total_invoices'] as num? ?? 0).toInt(),
        todayAmount: (j['today_amount'] as num? ?? 0).toDouble(),
        openExceptions: (j['open_exceptions'] as num? ?? 0).toInt(),
        openDisputes: (j['open_disputes'] as num? ?? 0).toInt(),
        pendingReview: (j['pending_review'] as num? ?? 0).toInt(),
      );
}

class OwnerInvoice {
  final String id;
  final String invoiceNumber;
  final String invoiceDate;
  final double grossAmount;
  final double taxAmount;
  final String currentState;
  final String createdAt;
  final String? buyerName;
  final String? buyerGstin;
  final String? entityName;
  final int openExceptions;
  final int openDisputes;
  final int documentCount;

  const OwnerInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.grossAmount,
    required this.taxAmount,
    required this.currentState,
    required this.createdAt,
    this.buyerName,
    this.buyerGstin,
    this.entityName,
    required this.openExceptions,
    required this.openDisputes,
    required this.documentCount,
  });

  factory OwnerInvoice.fromJson(Map<String, dynamic> j) => OwnerInvoice(
        id: j['id'] as String,
        invoiceNumber: j['invoice_number'] as String,
        invoiceDate: (j['invoice_date'] as String? ?? '').substring(0, 10),
        grossAmount: (j['gross_amount'] as num? ?? 0).toDouble(),
        taxAmount: (j['tax_amount'] as num? ?? 0).toDouble(),
        currentState: j['current_state'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        buyerName: j['buyer_name'] as String?,
        buyerGstin: j['buyer_gstin'] as String?,
        entityName: j['entity_name'] as String?,
        openExceptions: (j['open_exceptions'] as num? ?? 0).toInt(),
        openDisputes: (j['open_disputes'] as num? ?? 0).toInt(),
        documentCount: (j['document_count'] as num? ?? 0).toInt(),
      );
}

class InvoiceDocument {
  final String id;
  final String documentType;
  final bool isPrimary;
  final String createdAt;

  const InvoiceDocument({
    required this.id,
    required this.documentType,
    required this.isPrimary,
    required this.createdAt,
  });

  factory InvoiceDocument.fromJson(Map<String, dynamic> j) => InvoiceDocument(
        id: j['id'] as String,
        documentType: j['document_type'] as String? ?? '',
        isPrimary: j['is_primary'] as bool? ?? false,
        createdAt: j['created_at'] as String? ?? '',
      );

  String get friendlyLabel {
    return switch (documentType) {
      'INVOICE' => 'Tax Invoice',
      'GATE_ENTRY_NOTE' => 'Gate Entry Note',
      'CREDIT_NOTE' => 'Credit Note',
      'GRN' => 'Goods Receipt Note',
      _ => documentType.replaceAll('_', ' ').toLowerCase()
          .split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' '),
    };
  }
}

class InvoiceException {
  final String id;
  final String exceptionType;
  final String status;
  final String raisedAt;

  const InvoiceException({
    required this.id,
    required this.exceptionType,
    required this.status,
    required this.raisedAt,
  });

  factory InvoiceException.fromJson(Map<String, dynamic> j) => InvoiceException(
        id: j['id'] as String,
        exceptionType: j['exception_type'] as String? ?? '',
        status: j['status'] as String? ?? '',
        raisedAt: j['raised_at'] as String? ?? '',
      );
}

class InvoiceDispute {
  final String id;
  final String invoiceId;
  final String disputeType;
  final String description;
  final String status;
  final String? resolutionNotes;
  final String? creditNoteDocumentId;
  final String createdAt;

  const InvoiceDispute({
    required this.id,
    required this.invoiceId,
    required this.disputeType,
    required this.description,
    required this.status,
    this.resolutionNotes,
    this.creditNoteDocumentId,
    required this.createdAt,
  });

  factory InvoiceDispute.fromJson(Map<String, dynamic> j) => InvoiceDispute(
        id: j['id'] as String,
        invoiceId: j['invoice_id'] as String? ?? '',
        disputeType: j['dispute_type'] as String? ?? '',
        description: j['description'] as String? ?? '',
        status: j['status'] as String? ?? '',
        resolutionNotes: j['resolution_notes'] as String?,
        creditNoteDocumentId: j['credit_note_document_id'] as String?,
        createdAt: j['created_at'] as String? ?? '',
      );

  String get statusLabel => switch (status) {
        'OPEN' => 'Open',
        'OWNER_REVIEWING' => 'Reviewing',
        'RESOLVED' => 'Resolved',
        'REJECTED' => 'Rejected',
        _ => status,
      };
}

class InvoiceDetail {
  final OwnerInvoice invoice;
  final List<InvoiceDocument> documents;
  final List<InvoiceException> exceptions;
  final List<InvoiceDispute> disputes;

  const InvoiceDetail({
    required this.invoice,
    required this.documents,
    required this.exceptions,
    required this.disputes,
  });

  factory InvoiceDetail.fromJson(Map<String, dynamic> j) => InvoiceDetail(
        invoice: OwnerInvoice.fromJson(j['invoice'] as Map<String, dynamic>),
        documents: (j['documents'] as List? ?? [])
            .map((d) => InvoiceDocument.fromJson(d as Map<String, dynamic>))
            .toList(),
        exceptions: (j['exceptions'] as List? ?? [])
            .map((e) => InvoiceException.fromJson(e as Map<String, dynamic>))
            .toList(),
        disputes: (j['disputes'] as List? ?? [])
            .map((d) => InvoiceDispute.fromJson(d as Map<String, dynamic>))
            .toList(),
      );

  /// Documents grouped by document_type for display as "pages"
  Map<String, List<InvoiceDocument>> get documentGroups {
    final Map<String, List<InvoiceDocument>> groups = {};
    for (final doc in documents) {
      groups.putIfAbsent(doc.documentType, () => []).add(doc);
    }
    return groups;
  }
}

// ─── API Service ─────────────────────────────────────────────────────────────

class OwnerService {
  final Dio _dio;

  OwnerService({Dio? dio}) : _dio = dio ?? buildDio();

  Future<OwnerDashboard> getDashboard() async {
    final resp = await _dio.get(Endpoints.ownerDashboard);
    return OwnerDashboard.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<OwnerInvoice>> listInvoices({int offset = 0, int limit = 30}) async {
    final resp = await _dio.get(
      Endpoints.ownerInvoices,
      queryParameters: {'offset': offset, 'limit': limit},
    );
    final list = resp.data['invoices'] as List? ?? [];
    return list.map((j) => OwnerInvoice.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<InvoiceDetail> getInvoiceDetail(String invoiceId) async {
    final resp = await _dio.get(Endpoints.ownerInvoice(invoiceId));
    return InvoiceDetail.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<InvoiceDispute> createDispute({
    required String invoiceId,
    required String disputeType,
    required String description,
  }) async {
    final resp = await _dio.post(Endpoints.disputes, data: {
      'invoice_id': invoiceId,
      'dispute_type': disputeType,
      'description': description,
    });
    return InvoiceDispute.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<InvoiceDispute> updateDispute(String id, String status, {String notes = ''}) async {
    final resp = await _dio.patch(
      Endpoints.dispute(id),
      data: {'status': status, 'notes': notes},
    );
    return InvoiceDispute.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<String> uploadCreditNote(String disputeId, File file) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: 'credit_note.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    final resp = await _dio.post(Endpoints.disputeCreditNote(disputeId), data: formData);
    return resp.data['document_id'] as String;
  }

  Future<void> setGateEntry({
    required String invoiceId,
    required String documentId,
    String? gateEntryNumber,
    double? acceptedQty,
    double? invoiceQty,
    bool isShortReceipt = false,
    String? notes,
  }) async {
    await _dio.post(
      Endpoints.invoiceGateEntry(invoiceId),
      data: {
        'document_id': documentId,
        if (gateEntryNumber != null && gateEntryNumber.isNotEmpty)
          'gate_entry_number': gateEntryNumber,
        if (acceptedQty != null) 'accepted_qty': acceptedQty,
        if (invoiceQty != null) 'invoice_qty': invoiceQty,
        if (acceptedQty != null && invoiceQty != null)
          'discrepancy_amount': invoiceQty - acceptedQty,
        'is_short_receipt': isShortReceipt,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
  }

  /// Downloads a document to the app's documents directory.
  /// Returns the local path where it was saved.
  Future<String> downloadDocument(String invoiceId, String docId) async {
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/downloads/${invoiceId}_$docId.jpg';
    await Directory('${dir.path}/downloads').create(recursive: true);
    await _dio.download(
      Endpoints.ownerDocumentContent(invoiceId, docId),
      savePath,
    );
    return savePath;
  }
}

final ownerService = OwnerService();

// ─── Riverpod Providers ───────────────────────────────────────────────────────

final ownerDashboardProvider = FutureProvider<OwnerDashboard>((ref) async {
  return ownerService.getDashboard();
});

final ownerInvoicesProvider = FutureProvider<List<OwnerInvoice>>((ref) async {
  return ownerService.listInvoices();
});

final ownerInvoiceDetailProvider =
    FutureProvider.family<InvoiceDetail, String>((ref, invoiceId) async {
  return ownerService.getInvoiceDetail(invoiceId);
});
