import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:invoice_capture/core/config/server_config.dart';
import 'package:invoice_capture/features/owner/owner_provider.dart';

void main() {
  // Owner dashboard: the summary tiles on OwnerDashboardScreen are driven
  // entirely by OwnerDashboard.fromJson via this service call.
  test('getDashboard parses the dashboard summary', () async {
    final dio = Dio();
    final adapter = DioAdapter(dio: dio);
    adapter.onGet(
      '${ServerConfig.baseUrl}/api/v1/owner/dashboard',
      (server) => server.reply(200, {
        'total_invoices': 42,
        'today_amount': 125000.50,
        'open_exceptions': 3,
        'open_disputes': 1,
        'pending_review': 5,
      }),
    );

    final dash = await OwnerService(dio: dio).getDashboard();

    expect(dash.totalInvoices, 42);
    expect(dash.todayAmount, 125000.50);
    expect(dash.openExceptions, 3);
    expect(dash.openDisputes, 1);
    expect(dash.pendingReview, 5);
  });

  // Recent-invoices list on OwnerDashboardScreen / the full owner invoices
  // screen -- proves the real Meridian-shaped invoice JSON round-trips
  // correctly, including the nested buyer/exception/dispute counts the
  // dashboard cards key off of.
  test('listInvoices parses real Meridian invoice data', () async {
    final dio = Dio();
    final adapter = DioAdapter(
      dio: dio,
      matcher: const UrlRequestMatcher(matchMethod: true),
    );
    adapter.onGet(
      '${ServerConfig.baseUrl}/api/v1/owner/invoices',
      (server) => server.reply(200, {
        'invoices': [
          {
            'id': 'inv-1',
            'invoice_number': 'A260000218',
            'invoice_date': '2026-06-09T00:00:00Z',
            'gross_amount': 10393.45,
            'tax_amount': 519.55,
            'current_state': 'INGESTED',
            'created_at': '2026-06-09T10:00:00Z',
            'buyer_name': 'Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)',
            'buyer_gstin': '06AAAAA0013A1ZD',
            'entity_name': 'Meridian Brothers',
            'open_exceptions': 0,
            'open_disputes': 1,
            'document_count': 2,
          },
        ],
      }),
    );

    final invoices = await OwnerService(dio: dio).listInvoices();

    expect(invoices, hasLength(1));
    final inv = invoices.first;
    expect(inv.invoiceNumber, 'A260000218');
    expect(inv.buyerName, 'Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)');
    expect(inv.grossAmount, 10393.45);
    expect(inv.openDisputes, 1);
    expect(inv.documentCount, 2);
  });

  // Invoice detail screen: documents/exceptions/disputes all come from this
  // one nested payload, and documentGroups is what drives the per-page
  // document list (including the gate-entry-note grouping the gate entry
  // form attaches to).
  test('getInvoiceDetail parses nested documents, exceptions, and disputes',
      () async {
    final dio = Dio();
    final adapter = DioAdapter(
      dio: dio,
      matcher: const UrlRequestMatcher(matchMethod: true),
    );
    adapter.onGet(
      '${ServerConfig.baseUrl}/api/v1/owner/invoices/inv-1',
      (server) => server.reply(200, {
        'invoice': {
          'id': 'inv-1',
          'invoice_number': 'A260000218',
          'invoice_date': '2026-06-09T00:00:00Z',
          'gross_amount': 10393.45,
          'tax_amount': 519.55,
          'current_state': 'INGESTED',
          'created_at': '2026-06-09T10:00:00Z',
          'open_exceptions': 0,
          'open_disputes': 1,
          'document_count': 2,
        },
        'documents': [
          {
            'id': 'doc-1',
            'document_type': 'INVOICE',
            'is_primary': true,
            'created_at': '2026-06-09T10:00:00Z',
          },
          {
            'id': 'doc-2',
            'document_type': 'GATE_ENTRY_NOTE',
            'is_primary': false,
            'created_at': '2026-06-09T11:00:00Z',
          },
        ],
        'exceptions': [],
        'disputes': [
          {
            'id': 'dispute-1',
            'invoice_id': 'inv-1',
            'dispute_type': 'SHORT_RECEIPT',
            'description': '8 units short on cheese block line',
            'status': 'OPEN',
            'created_at': '2026-06-09T12:00:00Z',
          },
        ],
      }),
    );

    final detail = await OwnerService(dio: dio).getInvoiceDetail('inv-1');

    expect(detail.invoice.invoiceNumber, 'A260000218');
    expect(detail.documents, hasLength(2));
    expect(detail.documentGroups['GATE_ENTRY_NOTE'], hasLength(1));
    expect(detail.disputes, hasLength(1));
    expect(detail.disputes.first.disputeType, 'SHORT_RECEIPT');
    expect(detail.disputes.first.statusLabel, 'Open');
  });

  // Dispute screens: raising a dispute via the InvoiceDetailScreen dialog.
  test('createDispute posts the exact dispute payload and parses the response',
      () async {
    final dio = Dio();
    final adapter = DioAdapter(dio: dio);
    adapter.onPost(
      '${ServerConfig.baseUrl}/api/v1/disputes',
      (server) => server.reply(201, {
        'id': 'dispute-2',
        'invoice_id': 'inv-1',
        'dispute_type': 'ARITHMETIC_ERROR',
        'description': "CGST/SGST split doesn't sum to stated GST amount",
        'status': 'OPEN',
        'created_at': '2026-06-09T12:00:00Z',
      }),
      data: {
        'invoice_id': 'inv-1',
        'dispute_type': 'ARITHMETIC_ERROR',
        'description': "CGST/SGST split doesn't sum to stated GST amount",
      },
    );

    final dispute = await OwnerService(dio: dio).createDispute(
      invoiceId: 'inv-1',
      disputeType: 'ARITHMETIC_ERROR',
      description: "CGST/SGST split doesn't sum to stated GST amount",
    );

    expect(dispute.id, 'dispute-2');
    expect(dispute.status, 'OPEN');
  });

  // Dispute screens: the owner resolving/rejecting a dispute with notes.
  test('updateDispute posts status and notes, parses the resolved dispute',
      () async {
    final dio = Dio();
    final adapter = DioAdapter(dio: dio);
    adapter.onPatch(
      '${ServerConfig.baseUrl}/api/v1/disputes/dispute-2',
      (server) => server.reply(200, {
        'id': 'dispute-2',
        'invoice_id': 'inv-1',
        'dispute_type': 'ARITHMETIC_ERROR',
        'description': 'GST split mismatch',
        'status': 'RESOLVED',
        'resolution_notes': 'Confirmed correct with vendor, credit note issued',
        'created_at': '2026-06-09T12:00:00Z',
      }),
      data: {
        'status': 'RESOLVED',
        'notes': 'Confirmed correct with vendor, credit note issued',
      },
    );

    final dispute = await OwnerService(dio: dio).updateDispute(
      'dispute-2',
      'RESOLVED',
      notes: 'Confirmed correct with vendor, credit note issued',
    );

    expect(dispute.status, 'RESOLVED');
    expect(dispute.resolutionNotes, 'Confirmed correct with vendor, credit note issued');
  });

  // Gate entry form: proves the discrepancy_amount the owner never types
  // directly is computed correctly server-side-shaped (invoiceQty -
  // acceptedQty), and that an empty gate entry number is omitted rather
  // than sent as an empty string.
  test('setGateEntry computes discrepancy_amount and omits empty optional fields',
      () async {
    final dio = Dio();
    final adapter = DioAdapter(dio: dio);
    adapter.onPost(
      '${ServerConfig.baseUrl}/api/v1/invoices/inv-1/gate-entry',
      (server) => server.reply(200, {'status': 'ok'}),
      data: {
        'document_id': 'doc-2',
        'accepted_qty': 80.0,
        'invoice_qty': 92.0,
        'discrepancy_amount': 12.0,
        'is_short_receipt': true,
        'notes': '8 units short on cheese block line',
      },
    );

    await OwnerService(dio: dio).setGateEntry(
      invoiceId: 'inv-1',
      documentId: 'doc-2',
      gateEntryNumber: '', // worker left this blank
      acceptedQty: 80.0,
      invoiceQty: 92.0,
      isShortReceipt: true,
      notes: '8 units short on cheese block line',
    );
    // adapter.onPost's exact-body match (FullHttpRequestMatcher) already
    // proves gate_entry_number was omitted and discrepancy_amount was
    // computed correctly -- if either were wrong, this request would not
    // have matched and Dio would have thrown.
  });
}
