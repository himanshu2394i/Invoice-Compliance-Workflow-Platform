import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_capture/features/capture/bundle_provider.dart';
import 'package:invoice_capture/features/capture/review_screen.dart';

GoRouter _buildRouter() => GoRouter(
      initialLocation: '/capture/review',
      routes: [
        GoRoute(
          path: '/capture/camera',
          builder: (_, __) => const Scaffold(body: Text('Camera Screen')),
        ),
        GoRoute(
          path: '/capture/review',
          builder: (_, __) => const ReviewScreen(),
        ),
        GoRoute(
          path: '/capture/checklist',
          builder: (_, __) => const Scaffold(body: Text('Checklist Screen')),
        ),
      ],
    );

ProviderContainer _createSessionWithPhoto({String path = '/tmp/fake_inv.jpg'}) {
  final container = ProviderContainer();
  container.read(bundleProvider.notifier).addInvoicePage(path);
  return container;
}

void main() {
  group('QA Tests 5 & 6: Invalid Inputs & Empty States Validation', () {
    testWidgets('Invalid Input: Rejects GSTIN with incorrect character count', (tester) async {
      final container = _createSessionWithPhoto();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      // Invoice Number
      await tester.enterText(fields.at(0), 'INV-100');
      // Short GSTIN (< 15 chars)
      await tester.enterText(fields.at(2), '06AAABC1234');
      // Buyer Name
      await tester.enterText(fields.at(3), 'Test Buyer');
      // Date
      await tester.enterText(fields.at(4), '2026-07-27');
      // Amount
      await tester.enterText(fields.at(5), '500.00');

      final submitBtn = find.text('Next — Supporting Docs');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('GSTIN must be 15 characters'), findsOneWidget);
      expect(find.text('Checklist Screen'), findsNothing);
    });

    testWidgets('Invalid Input: Rejects Date not matching YYYY-MM-DD', (tester) async {
      final container = _createSessionWithPhoto();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'INV-101');
      await tester.enterText(fields.at(2), '06AAAAA0003A1Z3');
      await tester.enterText(fields.at(3), 'Test Buyer');
      // Malformed date DD/MM/YYYY
      await tester.enterText(fields.at(4), '27/07/2026');
      await tester.enterText(fields.at(5), '500.00');

      final submitBtn = find.text('Next — Supporting Docs');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Use YYYY-MM-DD format'), findsOneWidget);
      expect(find.text('Checklist Screen'), findsNothing);
    });

    testWidgets('Empty State: Session without photos initializes cleanly', (tester) async {
      final container = ProviderContainer(); // empty session

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
    });
  });
}
