import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/core/models/receivables.dart';

void main() {
  test('ReceivablesSummary parses the backend payload', () {
    final summary = ReceivablesSummary.fromJson({
      'total_outstanding': 10913.0,
      'total_overdue': 5000.5,
      'buyers': [
        {
          'buyer_id': 'b1',
          'buyer_name': 'Vishal Mega Mart',
          'buyer_gstin': '06AAAAA0013A1ZD',
          'outstanding': 10913.0,
          'overdue': 5000.5,
          'bucket_current': 5912.5,
          'bucket_1_30': 5000.5,
          'bucket_31_60': 0,
          'bucket_60_plus': 0,
          'open_invoices': 2,
        }
      ],
    });
    expect(summary.totalOutstanding, 10913.0);
    expect(summary.totalOverdue, 5000.5);
    expect(summary.buyers, hasLength(1));
    expect(summary.buyers.first.buyerName, 'Vishal Mega Mart');
    expect(summary.buyers.first.bucket1To30, 5000.5);
    expect(summary.buyers.first.openInvoices, 2);
  });

  test('ReceivableInvoice parses balances and integer amounts', () {
    final inv = ReceivableInvoice.fromJson({
      'invoice_id': 'i1',
      'invoice_number': 'CAD/15442',
      'invoice_date': '2026-06-06T00:00:00Z',
      'due_date': '2026-07-06T00:00:00Z',
      'total': 3814, // ints from JSON must not crash double fields
      'paid': 0,
      'balance': 3814,
      'days_overdue': 0,
    });
    expect(inv.invoiceNumber, 'CAD/15442');
    expect(inv.balance, 3814.0);
    expect(inv.dueDate, isNotNull);
  });

  test('PaymentRecord parses with nullable reference', () {
    final p = PaymentRecord.fromJson({
      'id': 'p1',
      'invoice_id': 'i1',
      'amount': 5000,
      'paid_on': '2026-07-02T00:00:00Z',
      'mode': 'UPI',
      'reference': null,
      'created_at': '2026-07-02T10:00:00Z',
    });
    expect(p.amount, 5000.0);
    expect(p.mode, 'UPI');
    expect(p.reference, isNull);
  });
}
