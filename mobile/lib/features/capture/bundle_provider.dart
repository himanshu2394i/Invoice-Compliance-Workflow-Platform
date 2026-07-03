import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/bundle.dart';
import '../../core/models/buyer_requirement.dart';
import '../../core/storage/hive_service.dart';

const _uuid = Uuid();

class CaptureSession {
  final String sessionId;
  final List<String> invoicePhotoPaths; // local compressed paths, page 1..N
  final String invoiceNumber;
  final String entityGstin;
  final String buyerGstin;
  final String buyerName;
  final String invoiceDate;
  final double taxableAmount;
  final double totalAmount;
  final String paymentType; // '' | 'CASH' | 'CREDIT'
  final int? paymentTermsDays;
  final String? buyerBranchId;
  final List<BuyerRequirement>
      requiredDocs; // populated after buyer GSTIN lookup
  final List<QueuedPhoto> additionalPhotos; // supporting docs captured so far
  final bool isSaving;
  final String? error;

  const CaptureSession({
    required this.sessionId,
    this.invoicePhotoPaths = const [],
    this.invoiceNumber = '',
    this.entityGstin = '',
    this.buyerGstin = '',
    this.buyerName = '',
    this.invoiceDate = '',
    this.taxableAmount = 0,
    this.totalAmount = 0,
    this.paymentType = '',
    this.paymentTermsDays,
    this.buyerBranchId,
    this.requiredDocs = const [],
    this.additionalPhotos = const [],
    this.isSaving = false,
    this.error,
  });

  factory CaptureSession.fromBundle(QueuedBundle bundle) {
    final invoicePages = bundle.photos.where((p) => p.isPrimary).toList()
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    final extraInvoicePages =
        bundle.photos.where((p) => p.documentType == 'INVOICE_PAGE').toList()
          ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    final supporting = bundle.photos
        .where((p) => !p.isPrimary && p.documentType != 'INVOICE_PAGE')
        .toList();
    return CaptureSession(
      sessionId: bundle.localId,
      invoicePhotoPaths: [
        ...invoicePages.map((p) => p.localPath),
        ...extraInvoicePages.map((p) => p.localPath),
      ],
      invoiceNumber: bundle.invoiceNumber,
      entityGstin: bundle.entityGstin,
      buyerGstin: bundle.buyerGstin,
      buyerName: bundle.buyerName,
      invoiceDate: bundle.invoiceDate,
      taxableAmount: bundle.taxableAmount,
      totalAmount: bundle.totalAmount,
      paymentType: bundle.paymentType ?? '',
      paymentTermsDays: bundle.paymentTermsDays,
      buyerBranchId: bundle.buyerBranchId,
      additionalPhotos: supporting,
    );
  }

  CaptureSession copyWith({
    List<String>? invoicePhotoPaths,
    String? invoiceNumber,
    String? entityGstin,
    String? buyerGstin,
    String? buyerName,
    String? invoiceDate,
    double? taxableAmount,
    double? totalAmount,
    String? paymentType,
    int? paymentTermsDays,
    bool clearPaymentTerms = false,
    String? buyerBranchId,
    bool clearBuyerBranch = false,
    List<BuyerRequirement>? requiredDocs,
    List<QueuedPhoto>? additionalPhotos,
    bool? isSaving,
    String? error,
  }) =>
      CaptureSession(
        sessionId: sessionId,
        invoicePhotoPaths: invoicePhotoPaths ?? this.invoicePhotoPaths,
        invoiceNumber: invoiceNumber ?? this.invoiceNumber,
        entityGstin: entityGstin ?? this.entityGstin,
        buyerGstin: buyerGstin ?? this.buyerGstin,
        buyerName: buyerName ?? this.buyerName,
        invoiceDate: invoiceDate ?? this.invoiceDate,
        taxableAmount: taxableAmount ?? this.taxableAmount,
        totalAmount: totalAmount ?? this.totalAmount,
        paymentType: paymentType ?? this.paymentType,
        paymentTermsDays: clearPaymentTerms
            ? null
            : (paymentTermsDays ?? this.paymentTermsDays),
        buyerBranchId:
            clearBuyerBranch ? null : (buyerBranchId ?? this.buyerBranchId),
        requiredDocs: requiredDocs ?? this.requiredDocs,
        additionalPhotos: additionalPhotos ?? this.additionalPhotos,
        isSaving: isSaving ?? this.isSaving,
        error: error,
      );

  /// Returns the document types that have not yet had a photo captured.
  List<BuyerRequirement> get pendingDocs => requiredDocs
      .where(
          (r) => !additionalPhotos.any((p) => p.documentType == r.documentType))
      .toList();

  bool get allDocsComplete => pendingDocs.isEmpty;

  QueuedBundle toBundle() {
    final invoicePhotos = [
      for (var i = 0; i < invoicePhotoPaths.length; i++)
        QueuedPhoto(
          localId: _uuid.v4(),
          localPath: invoicePhotoPaths[i],
          documentType: i == 0 ? 'INVOICE' : 'INVOICE_PAGE',
          label: 'Tax Invoice',
          isPrimary: i == 0,
          pageNumber: i + 1,
        ),
    ];
    final photos = [
      ...invoicePhotos,
      ...additionalPhotos,
    ];
    return QueuedBundle(
      localId: sessionId,
      invoiceNumber: invoiceNumber,
      entityGstin: entityGstin,
      buyerGstin: buyerGstin,
      buyerName: buyerName,
      invoiceDate: invoiceDate,
      taxableAmount: taxableAmount,
      totalAmount: totalAmount,
      photos: photos,
      status: 'pending',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      paymentType: paymentType.isEmpty ? null : paymentType,
      paymentTermsDays: paymentType == 'CREDIT' ? paymentTermsDays : null,
      buyerBranchId: buyerBranchId,
    );
  }

  QueuedBundle toDraftBundle() {
    final draft = toBundle();
    draft.status = 'draft';
    return draft;
  }
}

class BundleNotifier extends StateNotifier<CaptureSession> {
  BundleNotifier() : super(CaptureSession(sessionId: _uuid.v4()));

  void reset({bool clearDraft = true}) {
    state = CaptureSession(sessionId: _uuid.v4());
    if (clearDraft) unawaited(HiveService.clearCaptureDraft());
  }

  void restoreDraft(QueuedBundle draft) {
    state = CaptureSession.fromBundle(draft);
  }

  void _persistDraft() {
    unawaited(HiveService.saveCaptureDraft(state.toDraftBundle()));
  }

  void addInvoicePage(String path) {
    state =
        state.copyWith(invoicePhotoPaths: [...state.invoicePhotoPaths, path]);
    _persistDraft();
  }

  void replaceInvoicePage(int index, String path) {
    final updated = [...state.invoicePhotoPaths];
    updated[index] = path;
    state = state.copyWith(invoicePhotoPaths: updated);
    _persistDraft();
  }

  void removeInvoicePage(int index) {
    final updated = [...state.invoicePhotoPaths]..removeAt(index);
    state = state.copyWith(invoicePhotoPaths: updated);
    _persistDraft();
  }

  void updateInvoiceFields({
    String? invoiceNumber,
    String? entityGstin,
    String? buyerGstin,
    String? buyerName,
    String? invoiceDate,
    double? taxableAmount,
    double? totalAmount,
    String? paymentType,
    int? paymentTermsDays,
    bool clearPaymentTerms = false,
    String? buyerBranchId,
    bool clearBuyerBranch = false,
  }) {
    state = state.copyWith(
      invoiceNumber: invoiceNumber,
      entityGstin: entityGstin,
      buyerGstin: buyerGstin,
      buyerName: buyerName,
      invoiceDate: invoiceDate,
      taxableAmount: taxableAmount,
      totalAmount: totalAmount,
      paymentType: paymentType,
      paymentTermsDays: paymentTermsDays,
      clearPaymentTerms: clearPaymentTerms,
      buyerBranchId: buyerBranchId,
      clearBuyerBranch: clearBuyerBranch,
    );
    _persistDraft();
  }

  void setRequiredDocs(List<BuyerRequirement> docs) =>
      state = state.copyWith(requiredDocs: docs);

  void addSupportingPhoto(QueuedPhoto photo) {
    final updated = [...state.additionalPhotos, photo];
    state = state.copyWith(additionalPhotos: updated);
    _persistDraft();
  }

  void setSaving(bool saving) => state = state.copyWith(isSaving: saving);

  void setError(String? error) => state = state.copyWith(error: error);
}

final bundleProvider = StateNotifierProvider<BundleNotifier, CaptureSession>(
    (_) => BundleNotifier());
