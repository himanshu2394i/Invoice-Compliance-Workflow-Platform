/// Receivables DTOs. Mirrors backend/internal/db/distributor.go JSON field
/// names. All money fields tolerate JSON ints (num -> double).
double _asDouble(dynamic v) => (v as num?)?.toDouble() ?? 0;

class BuyerReceivable {
  final String buyerId;
  final String buyerName;
  final String buyerGstin;
  final double outstanding;
  final double overdue;
  final double bucketCurrent;
  final double bucket1To30;
  final double bucket31To60;
  final double bucket60Plus;
  final int openInvoices;

  const BuyerReceivable({
    required this.buyerId,
    required this.buyerName,
    required this.buyerGstin,
    required this.outstanding,
    required this.overdue,
    required this.bucketCurrent,
    required this.bucket1To30,
    required this.bucket31To60,
    required this.bucket60Plus,
    required this.openInvoices,
  });

  factory BuyerReceivable.fromJson(Map<String, dynamic> json) =>
      BuyerReceivable(
        buyerId: json['buyer_id'] as String,
        buyerName: json['buyer_name'] as String? ?? '',
        buyerGstin: json['buyer_gstin'] as String? ?? '',
        outstanding: _asDouble(json['outstanding']),
        overdue: _asDouble(json['overdue']),
        bucketCurrent: _asDouble(json['bucket_current']),
        bucket1To30: _asDouble(json['bucket_1_30']),
        bucket31To60: _asDouble(json['bucket_31_60']),
        bucket60Plus: _asDouble(json['bucket_60_plus']),
        openInvoices: (json['open_invoices'] as num?)?.toInt() ?? 0,
      );
}

class ReceivablesSummary {
  final double totalOutstanding;
  final double totalOverdue;
  final List<BuyerReceivable> buyers;

  const ReceivablesSummary({
    required this.totalOutstanding,
    required this.totalOverdue,
    required this.buyers,
  });

  factory ReceivablesSummary.fromJson(Map<String, dynamic> json) =>
      ReceivablesSummary(
        totalOutstanding: _asDouble(json['total_outstanding']),
        totalOverdue: _asDouble(json['total_overdue']),
        buyers: ((json['buyers'] as List?) ?? const [])
            .map((b) => BuyerReceivable.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}

class ReceivableInvoice {
  final String invoiceId;
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final DateTime? dueDate;
  final double total;
  final double paid;
  final double balance;
  final int daysOverdue;

  const ReceivableInvoice({
    required this.invoiceId,
    required this.invoiceNumber,
    this.invoiceDate,
    this.dueDate,
    required this.total,
    required this.paid,
    required this.balance,
    required this.daysOverdue,
  });

  factory ReceivableInvoice.fromJson(Map<String, dynamic> json) =>
      ReceivableInvoice(
        invoiceId: json['invoice_id'] as String,
        invoiceNumber: json['invoice_number'] as String? ?? '',
        invoiceDate: DateTime.tryParse(json['invoice_date'] as String? ?? ''),
        dueDate: DateTime.tryParse(json['due_date'] as String? ?? ''),
        total: _asDouble(json['total']),
        paid: _asDouble(json['paid']),
        balance: _asDouble(json['balance']),
        daysOverdue: (json['days_overdue'] as num?)?.toInt() ?? 0,
      );
}

class PaymentRecord {
  final String id;
  final String invoiceId;
  final double amount;
  final DateTime? paidOn;
  final String mode;
  final String? reference;
  final String? notes;

  const PaymentRecord({
    required this.id,
    required this.invoiceId,
    required this.amount,
    this.paidOn,
    required this.mode,
    this.reference,
    this.notes,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
        id: json['id'] as String,
        invoiceId: json['invoice_id'] as String? ?? '',
        amount: _asDouble(json['amount']),
        paidOn: DateTime.tryParse(json['paid_on'] as String? ?? ''),
        mode: json['mode'] as String? ?? '',
        reference: json['reference'] as String?,
        notes: json['notes'] as String?,
      );
}

class SalesReportRow {
  final String keyId;
  final String keyLabel;
  final int invoiceCount;
  final double gross;
  final double tax;

  const SalesReportRow({
    required this.keyId,
    required this.keyLabel,
    required this.invoiceCount,
    required this.gross,
    required this.tax,
  });

  factory SalesReportRow.fromJson(Map<String, dynamic> json) => SalesReportRow(
        keyId: json['key_id'] as String? ?? '',
        keyLabel: json['key_label'] as String? ?? '',
        invoiceCount: (json['invoice_count'] as num?)?.toInt() ?? 0,
        gross: _asDouble(json['gross']),
        tax: _asDouble(json['tax']),
      );
}
