import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_capture/core/models/receivables.dart';
import 'package:invoice_capture/features/auth/auth_provider.dart';
import 'package:invoice_capture/features/owner/owner_provider.dart';
import 'package:invoice_capture/features/receivables/buyer_receivables_screen.dart';
import 'package:invoice_capture/features/receivables/receivables_screen.dart';

const _summary = ReceivablesSummary(
  totalOutstanding: 30549.0,
  totalOverdue: 19636.0,
  buyers: [
    BuyerReceivable(
      buyerId: 'b-zepto',
      buyerName: 'Zepto Limited',
      buyerGstin: '06AAAAA0014A1ZE',
      outstanding: 19636.0,
      overdue: 19636.0,
      bucketCurrent: 0,
      bucket1To30: 19636.0,
      bucket31To60: 0,
      bucket60Plus: 0,
      openInvoices: 1,
    ),
    BuyerReceivable(
      buyerId: 'b-vishal',
      buyerName: 'Vishal Mega Mart',
      buyerGstin: '06AAAAA0013A1ZD',
      outstanding: 10913.0,
      overdue: 0,
      bucketCurrent: 10913.0,
      bucket1To30: 0,
      bucket31To60: 0,
      bucket60Plus: 0,
      openInvoices: 1,
    ),
  ],
);

final _invoices = [
  ReceivableInvoice(
    invoiceId: 'inv-1',
    invoiceNumber: 'REHIN000800',
    invoiceDate: DateTime(2026, 6, 3),
    dueDate: DateTime(2026, 6, 3),
    total: 19636.0,
    paid: 0,
    balance: 19636.0,
    daysOverdue: 29,
  ),
];

Widget _app({required Widget home, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/test',
        routes: [
          GoRoute(path: '/test', builder: (_, __) => home),
          GoRoute(
              path: '/owner/receivables/:buyerId',
              builder: (_, state) => Scaffold(
                  body: Text('Drilldown ${state.pathParameters['buyerId']}'))),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('receivables tab renders totals and ranked buyers',
      (tester) async {
    await tester.pumpWidget(_app(
      home: const ReceivablesScreen(),
      overrides: [
        receivablesProvider.overrideWith((ref) async => _summary),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Total outstanding'), findsOneWidget);
    expect(find.text('₹30,549'), findsOneWidget);
    expect(find.text('₹19,636'), findsWidgets); // overdue total + buyer row
    expect(find.text('Zepto Limited'), findsOneWidget);
    expect(find.text('Vishal Mega Mart'), findsOneWidget);

    // Tapping a buyer opens the drill-down route.
    await tester.tap(find.text('Zepto Limited'));
    await tester.pumpAndSettle();
    expect(find.text('Drilldown b-zepto'), findsOneWidget);
  });

  Future<void> pumpBuyerScreenAs(WidgetTester tester, String role) async {
    await tester.pumpWidget(_app(
      home: const BuyerReceivablesScreen(
          buyerId: 'b-zepto', buyerName: 'Zepto Limited'),
      overrides: [
        buyerReceivablesProvider('b-zepto')
            .overrideWith((ref) async => _invoices),
        authProvider.overrideWith(
          (_) => AuthNotifier(
            initialState: AuthState(
              isLoggedIn: true,
              user: {'full_name': '$role User', 'role': role},
            ),
          ),
        ),
      ],
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('reviewer sees invoices but cannot record payments',
      (tester) async {
    await pumpBuyerScreenAs(tester, 'REVIEWER');
    expect(find.text('REHIN000800'), findsOneWidget);
    expect(find.text('29 day(s) overdue'), findsOneWidget);
    expect(find.text('Record payment'), findsNothing);
  });

  testWidgets('finance can record payments', (tester) async {
    await pumpBuyerScreenAs(tester, 'FINANCE');
    expect(find.text('Record payment'), findsOneWidget);
  });

  test('formatMoney groups digits the Indian way', () {
    expect(formatMoney(19636), '₹19,636');
    expect(formatMoney(1234567), '₹12,34,567');
    expect(formatMoney(10913.5), '₹10,913.50');
    expect(formatMoney(999), '₹999');
  });
}
