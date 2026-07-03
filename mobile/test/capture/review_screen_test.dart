import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_capture/features/capture/bundle_provider.dart';
import 'package:invoice_capture/features/capture/review_screen.dart';

// Field order as laid out in ReviewScreen.build: Invoice Number, Search Buyer,
// Buyer GSTIN, Buyer Name, Invoice Date, Taxable Amount, Total Amount (the
// seller entity selector is a DropdownButtonFormField, not a TextFormField).
const _invoiceNumberField = 0;
const _buyerGstinField = 2;
const _buyerNameField = 3;
const _invoiceDateField = 4;
const _taxableAmountField = 5;
const _totalAmountField = 6;

GoRouter _buildRouter() => GoRouter(
      initialLocation: '/capture/review',
      routes: [
        GoRoute(
          path: '/capture/camera',
          builder: (_, __) => const Scaffold(body: Text('Camera')),
        ),
        GoRoute(
          path: '/capture/review',
          builder: (_, __) => const ReviewScreen(),
        ),
        GoRoute(
          path: '/capture/checklist',
          builder: (_, __) => const Scaffold(body: Text('Checklist')),
        ),
      ],
    );

Future<void> _fillValidForm(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(_invoiceNumberField), 'A26/001');
  await tester.enterText(fields.at(_buyerGstinField), '06AAAAA0013A1ZD');
  await tester.enterText(fields.at(_buyerNameField), 'Vishal Mega Mart');
  await tester.enterText(fields.at(_invoiceDateField), '2026-06-09');
  await tester.enterText(fields.at(_taxableAmountField), '10393.45');
  await tester.enterText(fields.at(_totalAmountField), '10913.00');
}

ProviderContainer _containerWithInvoicePhoto({
  String path = '/tmp/invoice.jpg',
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(overrides: overrides);
  container.read(bundleProvider.notifier).addInvoicePage(path);
  return container;
}

Future<ProviderContainer> _pumpReview(WidgetTester tester,
    {GoRouter? router,
    String? invoicePath,
    List<Override> overrides = const [],
    bool settle = true}) async {
  final container = _containerWithInvoicePhoto(
    path: invoicePath ?? '/tmp/invoice.jpg',
    overrides: overrides,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router ?? _buildRouter()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return container;
}

Future<void> _tapNext(WidgetTester tester) async {
  final next = find.text('Next — Supporting Docs');
  await tester.ensureVisible(next);
  await tester.pumpAndSettle();
  await tester.tap(next);
  await tester.pumpAndSettle();
}

Dio _reviewDioWithDuplicateResponse(Map<String, dynamic> response) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      if (options.uri.path.endsWith('/api/v1/mobile/invoices/duplicate-check')) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: response,
        ));
        return;
      }
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        error: 'unmocked review request',
      ));
    },
  ));
  return dio;
}

void main() {
  testWidgets(
      'blocks submission and shows "Required" errors when fields are empty',
      (tester) async {
    await _pumpReview(tester);

    await _tapNext(tester);

    expect(find.text('Required'), findsWidgets);
    expect(find.text('Checklist'), findsNothing);
  });

  testWidgets('rejects a buyer GSTIN that is not 15 characters',
      (tester) async {
    await _pumpReview(tester);

    await _fillValidForm(tester);
    await tester.enterText(find.byType(TextFormField).at(_buyerGstinField),
        '06AAICA76'); // 9 chars

    await _tapNext(tester);

    expect(find.text('GSTIN must be 15 characters'), findsOneWidget);
    expect(find.text('Checklist'), findsNothing);
  });

  testWidgets('back from review returns to camera instead of exiting',
      (tester) async {
    final router = _buildRouter();
    await _pumpReview(tester, router: router);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('rejects an invoice date not in YYYY-MM-DD format',
      (tester) async {
    await _pumpReview(tester);

    await _fillValidForm(tester);
    await tester.enterText(
        find.byType(TextFormField).at(_invoiceDateField), '09-06-2026');

    await _tapNext(tester);

    expect(find.text('Use YYYY-MM-DD format'), findsOneWidget);
    expect(find.text('Checklist'), findsNothing);
  });

  testWidgets('rejects a non-numeric taxable amount', (tester) async {
    await _pumpReview(tester);

    await _fillValidForm(tester);
    await tester.enterText(
        find.byType(TextFormField).at(_taxableAmountField), 'not-a-number');

    await _tapNext(tester);

    expect(find.text('Must be a number'), findsOneWidget);
    expect(find.text('Checklist'), findsNothing);
  });

  testWidgets('rejects total amount lower than taxable amount', (tester) async {
    await _pumpReview(tester);

    await _fillValidForm(tester);
    await tester.enterText(
        find.byType(TextFormField).at(_taxableAmountField), '200');
    await tester.enterText(
        find.byType(TextFormField).at(_totalAmountField), '100');

    await _tapNext(tester);

    expect(find.text('Cannot exceed total'), findsOneWidget);
    expect(find.text('Must be at least taxable'), findsOneWidget);
    expect(find.text('Checklist'), findsNothing);
  });

  testWidgets(
      'valid input saves the parsed fields to bundleProvider and advances to the checklist',
      (tester) async {
    final container = await _pumpReview(
      tester,
      overrides: [
        reviewDioProvider.overrideWithValue(
          _reviewDioWithDuplicateResponse({'duplicate': false}),
        ),
      ],
    );

    await _fillValidForm(tester);
    await _tapNext(tester);

    final session = container.read(bundleProvider);
    expect(session.invoiceNumber, 'A26/001');
    // entityGstin defaults to the first entity in the dropdown -- proves
    // updateInvoiceFields was called with the selector's current value, not
    // left blank.
    expect(session.entityGstin, '06AAAAA0003A1Z3');
    expect(session.buyerGstin, '06AAAAA0013A1ZD');
    expect(session.buyerName, 'Vishal Mega Mart');
    expect(session.invoiceDate, '2026-06-09');
    expect(session.taxableAmount, 10393.45);
    expect(session.totalAmount, 10913.00);
    // Cash is the default payment type; no terms/branch carried.
    expect(session.paymentType, 'CASH');
    expect(session.paymentTermsDays, isNull);

    expect(find.text('Checklist'), findsOneWidget);
  });

  testWidgets('selecting Credit reveals terms and carries them to the bundle',
      (tester) async {
    final container = await _pumpReview(
      tester,
      overrides: [
        reviewDioProvider.overrideWithValue(
          _reviewDioWithDuplicateResponse({'duplicate': false}),
        ),
      ],
    );

    // Terms field is hidden while Cash is selected.
    expect(find.text('Terms (days)'), findsNothing);

    // Fill first: the terms field inserts itself mid-form once Credit is
    // selected, which would shift _fillValidForm's positional indices.
    await _fillValidForm(tester);

    await tester.ensureVisible(find.text('Credit'));
    await tester.tap(find.text('Credit'));
    await tester.pumpAndSettle();
    expect(find.text('Terms (days)'), findsOneWidget);
    // The terms field is the last TextFormField added by the Credit toggle;
    // find it by its label's ancestor form field.
    await tester.enterText(
      find.ancestor(
        of: find.text('Terms (days)'),
        matching: find.byType(TextFormField),
      ),
      '30',
    );
    await _tapNext(tester);

    final session = container.read(bundleProvider);
    expect(session.paymentType, 'CREDIT');
    expect(session.paymentTermsDays, 30);
    expect(find.text('Checklist'), findsOneWidget);
  });

  testWidgets('duplicate invoice check warns before moving to checklist',
      (tester) async {
    final dio = _reviewDioWithDuplicateResponse({
      'duplicate': true,
      'invoice_id': 'invoice-1',
      'invoice_number': 'A26/001',
      'buyer_name': 'Vishal Mega Mart',
      'invoice_date': '2026-06-09',
      'total_amount': 10913.00,
      'status': 'ARCHIVED',
    });

    await _pumpReview(
      tester,
      overrides: [reviewDioProvider.overrideWithValue(dio)],
    );
    await _fillValidForm(tester);
    await _tapNext(tester);

    expect(
      find.textContaining(
        'This invoice number already exists. Continue only if this is a correction or extra document.',
      ),
      findsOneWidget,
    );
    expect(find.text('Checklist'), findsNothing);

    await tester.tap(find.text('Continue Anyway'));
    await tester.pumpAndSettle();

    expect(find.text('Checklist'), findsOneWidget);
  });
}
