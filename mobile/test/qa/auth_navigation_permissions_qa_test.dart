import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_capture/features/capture/bundle_provider.dart';
import 'package:invoice_capture/features/capture/review_screen.dart';

GoRouter _buildTestRouter() => GoRouter(
      initialLocation: '/capture/review',
      routes: [
        GoRoute(
          path: '/capture/camera',
          builder: (_, __) => const Scaffold(body: Text('Camera Target Screen')),
        ),
        GoRoute(
          path: '/capture/review',
          builder: (_, __) => const ReviewScreen(),
        ),
      ],
    );

void main() {
  group('QA Tests 10, 11 & 12: Auth, Navigation Interceptors & Permissions', () {
    testWidgets('Navigation: Hardware back button on ReviewScreen returns to CameraScreen', (tester) async {
      final container = ProviderContainer();
      container.read(bundleProvider.notifier).addInvoicePage('/tmp/nav_test.jpg');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: _buildTestRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);

      // Trigger back navigation
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Camera Target Screen'), findsOneWidget);
    });
  });
}
