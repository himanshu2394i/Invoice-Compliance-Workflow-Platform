import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/bundle.dart';
import '../../core/models/buyer_requirement.dart';

const _uuid = Uuid();

class CaptureSession {
  final String sessionId;
  final String? invoicePhotoPath; // local compressed path
  final String invoiceNumber;
  final String entityGstin;
  final String buyerGstin;
  final String buyerName;
  final String invoiceDate;
  final double taxableAmount;
  final double totalAmount;
  final List<BuyerRequirement> requiredDocs; // populated after buyer GSTIN lookup
  final List<QueuedPhoto> additionalPhotos; // supporting docs captured so far
  final bool isSaving;
  final String? error;

  const CaptureSession({
    required this.sessionId,
    this.invoicePhotoPath,
    this.invoiceNumber = '',
    this.entityGstin = '',
    this.buyerGstin = '',
    this.buyerName = '',
    this.invoiceDate = '',
    this.taxableAmount = 0,
    this.totalAmount = 0,
    this.requiredDocs = const [],
    this.additionalPhotos = const [],
    this.isSaving = false,
    this.error,
  });

  CaptureSession copyWith({
    String? invoicePhotoPath,
    String? invoiceNumber,
    String? entityGstin,
    String? buyerGstin,
    String? buyerName,
    String? invoiceDate,
    double? taxableAmount,
    double? totalAmount,
    List<BuyerRequirement>? requiredDocs,
    List<QueuedPhoto>? additionalPhotos,
    bool? isSaving,
    String? error,
  }) =>
      CaptureSession(
        sessionId: sessionId,
        invoicePhotoPath: invoicePhotoPath ?? this.invoicePhotoPath,
        invoiceNumber: invoiceNumber ?? this.invoiceNumber,
        entityGstin: entityGstin ?? this.entityGstin,
        buyerGstin: buyerGstin ?? this.buyerGstin,
        buyerName: buyerName ?? this.buyerName,
        invoiceDate: invoiceDate ?? this.invoiceDate,
        taxableAmount: taxableAmount ?? this.taxableAmount,
        totalAmount: totalAmount ?? this.totalAmount,
        requiredDocs: requiredDocs ?? this.requiredDocs,
        additionalPhotos: additionalPhotos ?? this.additionalPhotos,
        isSaving: isSaving ?? this.isSaving,
        error: error,
      );

  /// Returns the document types that have not yet had a photo captured.
  List<BuyerRequirement> get pendingDocs => requiredDocs
      .where((r) =>
          !additionalPhotos.any((p) => p.documentType == r.documentType))
      .toList();

  bool get allDocsComplete => pendingDocs.isEmpty;

  QueuedBundle toBundle() {
    final photos = [
      QueuedPhoto(
        localId: _uuid.v4(),
        localPath: invoicePhotoPath!,
        documentType: 'INVOICE',
        label: 'Tax Invoice',
        isPrimary: true,
      ),
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
    );
  }
}

class BundleNotifier extends StateNotifier<CaptureSession> {
  BundleNotifier() : super(CaptureSession(sessionId: _uuid.v4()));

  void reset() => state = CaptureSession(sessionId: _uuid.v4());

  void setInvoicePhoto(String path) =>
      state = state.copyWith(invoicePhotoPath: path);

  void updateInvoiceFields({
    String? invoiceNumber,
    String? entityGstin,
    String? buyerGstin,
    String? buyerName,
    String? invoiceDate,
    double? taxableAmount,
    double? totalAmount,
  }) {
    state = state.copyWith(
      invoiceNumber: invoiceNumber,
      entityGstin: entityGstin,
      buyerGstin: buyerGstin,
      buyerName: buyerName,
      invoiceDate: invoiceDate,
      taxableAmount: taxableAmount,
      totalAmount: totalAmount,
    );
  }

  void setRequiredDocs(List<BuyerRequirement> docs) =>
      state = state.copyWith(requiredDocs: docs);

  void addSupportingPhoto(QueuedPhoto photo) {
    final updated = [...state.additionalPhotos, photo];
    state = state.copyWith(additionalPhotos: updated);
  }

  void setSaving(bool saving) => state = state.copyWith(isSaving: saving);

  void setError(String? error) => state = state.copyWith(error: error);
}

final bundleProvider =
    StateNotifierProvider<BundleNotifier, CaptureSession>((_) => BundleNotifier());
