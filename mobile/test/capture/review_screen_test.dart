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
    final container = await _pumpReview(tester);

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

    expect(find.text('Checklist'), findsOneWidget);
  });
}
