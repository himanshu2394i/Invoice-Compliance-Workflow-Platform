import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/features/owner/owner_invoices_screen.dart';
import 'package:invoice_capture/features/owner/owner_provider.dart';

OwnerInvoice _invoice({
  required String invoiceNumber,
  required String buyerName,
  required String gstin,
  required double amount,
  required String state,
}) =>
    OwnerInvoice(
      id: invoiceNumber,
      invoiceNumber: invoiceNumber,
      invoiceDate: '2026-06-30',
      grossAmount: amount,
      taxAmount: 0,
      currentState: state,
      createdAt: '2026-06-30T00:00:00Z',
      buyerName: buyerName,
      buyerGstin: gstin,
      entityName: 'Meridian Brothers',
      openExceptions: 0,
      openDisputes: 0,
      documentCount: 1,
    );

void main() {
  final invoices = [
    _invoice(
      invoiceNumber: 'HAL08222',
      buyerName: 'Flipkart India Pvt Ltd',
      gstin: '06AAAAA0012A1ZC',
      amount: 10913,
      state: 'PENDING_REVIEW',
    ),
    _invoice(
      invoiceNumber: 'MAX-100',
      buyerName: 'Max Hypermarket',
      gstin: '06AAAAA0005A1Z5',
      amount: 25100,
      state: 'APPROVED',
    ),
  ];

  test('empty query returns all invoices', () {
    expect(filterOwnerInvoices(invoices, ''), hasLength(2));
  });

  test('matches invoice number, buyer, GSTIN, amount, and state', () {
    expect(filterOwnerInvoices(invoices, 'hal'), [invoices.first]);
    expect(filterOwnerInvoices(invoices, 'hypermarket'), [invoices.last]);
    expect(filterOwnerInvoices(invoices, '4872'), [invoices.first]);
    expect(filterOwnerInvoices(invoices, '25100'), [invoices.last]);
    expect(filterOwnerInvoices(invoices, 'approved'), [invoices.last]);
  });
}
