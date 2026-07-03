import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/core/models/status_labels.dart';

void main() {
  test('workflow states map to plain-language labels', () {
    expect(invoiceStatusLabel('INGESTED'), 'Submitted');
    expect(invoiceStatusLabel('VALIDATING'), 'Checking');
    expect(invoiceStatusLabel('VALIDATION_FAILED'), 'Needs Review');
    expect(invoiceStatusLabel('PENDING_MANAGER_APPROVAL'), 'Waiting for Manager');
    expect(invoiceStatusLabel('PENDING_FINANCE_APPROVAL'), 'Waiting for Finance');
    expect(invoiceStatusLabel('APPROVED'), 'Approved');
    expect(invoiceStatusLabel('REJECTED'), 'Rejected');
  });

  test('archived credit invoices show payment status instead of Archived', () {
    expect(
      invoiceStatusLabel('ARCHIVED', paymentType: 'CREDIT', balance: 5000),
      'Open',
    );
    expect(
      invoiceStatusLabel('ARCHIVED',
          paymentType: 'CREDIT', balance: 5000, overdue: true),
      'Overdue',
    );
    expect(
      invoiceStatusLabel('ARCHIVED', paymentType: 'CREDIT', balance: 0),
      'Paid',
    );
    // Cash/legacy invoices keep the plain label.
    expect(invoiceStatusLabel('ARCHIVED'), 'Archived');
    expect(invoiceStatusLabel('ARCHIVED', paymentType: 'CASH'), 'Archived');
  });

  test('unknown states fall back to a readable form of the raw state', () {
    expect(invoiceStatusLabel('SOME_NEW_STATE'), 'Some New State');
  });
}
