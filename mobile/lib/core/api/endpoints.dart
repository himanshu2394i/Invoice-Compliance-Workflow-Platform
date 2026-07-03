import '../config/server_config.dart';

class Endpoints {
  static String get _base => ServerConfig.baseUrl;

  static String get login => '$_base/api/v1/auth/login';
  static String get changePassword => '$_base/api/v1/auth/change-password';
  static String get resetStaffPassword =>
      '$_base/api/v1/auth/users/reset-password';
  static String get entities => '$_base/api/v1/entities';
  static String get buyers => '$_base/api/v1/buyers';
  static String get ledgerUpload => '$_base/api/v1/invoices/ledger-upload';
  static String get invoiceOcrPreview =>
      '$_base/api/v1/mobile/invoice-ocr-preview';
  static String invoiceDuplicateCheck({
    required String invoiceNumber,
    required String sellerGstin,
    required String buyerGstin,
  }) =>
      Uri.parse('$_base/api/v1/mobile/invoices/duplicate-check')
          .replace(queryParameters: {
        'invoice_number': invoiceNumber,
        'seller_gstin': sellerGstin,
        'buyer_gstin': buyerGstin,
      }).toString();
  static String get invoices => '$_base/api/v1/invoices';
  static String invoice(String id) => '$_base/api/v1/invoices/$id';
  static String get ownerDashboard => '$_base/api/v1/owner/dashboard';
  static String get ownerAlerts => '$_base/api/v1/owner/alerts';
  static String get ownerInvoices => '$_base/api/v1/owner/invoices';
  static String get disputes => '$_base/api/v1/disputes';

  static String buyerRequirementsByGstin(String gstin) =>
      '$_base/api/v1/mobile/buyers/requirements?gstin=$gstin';

  static String buyerRequirementsById(String buyerId) =>
      '$_base/api/v1/mobile/buyers/$buyerId/requirements';

  static String buyerRequirementDelete(String buyerId, String documentType) =>
      '$_base/api/v1/mobile/buyers/$buyerId/requirements/$documentType';

  static String invoiceDocuments(String invoiceId) =>
      '$_base/api/v1/invoices/$invoiceId/documents';

  static String documentVersions(String documentId) =>
      '$_base/api/v1/documents/$documentId/versions';

  static String ownerInvoice(String id) => '$_base/api/v1/owner/invoices/$id';

  static String ownerDocumentContent(String invoiceId, String docId) =>
      '$_base/api/v1/owner/invoices/$invoiceId/documents/$docId/content';

  static String dispute(String id) => '$_base/api/v1/disputes/$id';

  static String disputeCreditNote(String id) =>
      '$_base/api/v1/disputes/$id/credit-note';

  static String invoiceGateEntry(String invoiceId) =>
      '$_base/api/v1/invoices/$invoiceId/gate-entry';

  static String exceptionResolve(String id) =>
      '$_base/api/v1/exceptions/$id/resolve';

  static String invoiceApprove(String invoiceId) =>
      '$_base/api/v1/invoices/$invoiceId/approve';

  static String invoiceAuditTrail(String invoiceId) =>
      '$_base/api/v1/invoices/$invoiceId/audit-trail';

  static String get rules => '$_base/api/v1/rules';
  static String rule(String id) => '$_base/api/v1/rules/$id';

  // Receivables + payments
  static String get receivables => '$_base/api/v1/owner/receivables';
  static String buyerReceivables(String buyerId) =>
      '$_base/api/v1/owner/receivables/$buyerId';
  static String invoicePayments(String invoiceId) =>
      '$_base/api/v1/invoices/$invoiceId/payments';

  // Sales reports
  static String get salesReport => '$_base/api/v1/owner/reports/sales';

  // Master data
  static String get principals => '$_base/api/v1/principals';
  static String principal(String id) => '$_base/api/v1/principals/$id';
  static String get seriesRegistry => '$_base/api/v1/series-registry';
  static String seriesEntry(String id) => '$_base/api/v1/series-registry/$id';
  static String get allBuyerBranches => '$_base/api/v1/buyers/branches';
  static String buyerBranches(String buyerId) =>
      '$_base/api/v1/buyers/$buyerId/branches';
  static String buyerBranch(String branchId) =>
      '$_base/api/v1/buyers/branches/$branchId';
  static String buyer(String id) => '$_base/api/v1/buyers/$id';
}
