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
      ],
    );

void main() {
  group('QA Tests 13, 14 & 15: Responsive Layouts, Lifecycle & Performance', () {
    testWidgets('Responsive Layout: Renders cleanly on Compact Phone (360x640)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer();
      container.read(bundleProvider.notifier).addInvoicePage('/tmp/compact_test.jpg');

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

    testWidgets('Responsive Layout: Renders cleanly on Tablet Landscape (1280x800)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer();
      container.read(bundleProvider.notifier).addInvoicePage('/tmp/tablet_test.jpg');

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
