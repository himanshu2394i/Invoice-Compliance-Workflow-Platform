class Endpoints {
  static const String _base = 'http://10.0.2.2:8000'; // Android emulator → localhost

  static const String login = '$_base/api/v1/auth/login';
  static const String entities = '$_base/api/v1/entities';
  static const String buyers = '$_base/api/v1/buyers';
  static const String ledgerUpload = '$_base/api/v1/invoices/ledger-upload';

  static String buyerRequirementsByGstin(String gstin) =>
      '$_base/api/v1/mobile/buyers/requirements?gstin=$gstin';

  static String buyerRequirementsById(String buyerId) =>
      '$_base/api/v1/mobile/buyers/$buyerId/requirements';

  static String invoiceDocuments(String invoiceId) =>
      '$_base/api/v1/invoices/$invoiceId/documents';
}
