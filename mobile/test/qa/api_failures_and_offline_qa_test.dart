import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_capture/features/capture/bundle_provider.dart';
import 'package:invoice_capture/features/capture/review_screen.dart';

class MockErrorDioAdapter implements HttpClientAdapter {
  final int statusCode;
  MockErrorDioAdapter({this.statusCode = 500});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: options,
        statusCode: statusCode,
        data: {'error': 'Server error'},
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

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

void main() {
  group('QA Tests 8 & 9: API Failures, Timeouts & Offline Resiliency', () {
    testWidgets('API Failure 500: Handles OCR preview server error gracefully', (tester) async {
      final dio = Dio()..httpClientAdapter = MockErrorDioAdapter(statusCode: 500);

      final container = ProviderContainer(
        overrides: [
          reviewDioProvider.overrideWithValue(dio),
        ],
      );
      container.read(bundleProvider.notifier).addInvoicePage('/tmp/invoice_test.jpg');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // UI remains functional for manual entry even when OCR server returns 500
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('Next — Supporting Docs'), findsOneWidget);
    });

    testWidgets('Offline Handling: Network timeout falls back to local manual review', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = MockErrorDioAdapter(statusCode: 504);

      final container = ProviderContainer(
        overrides: [
          reviewDioProvider.overrideWithValue(dio),
        ],
      );
      container.read(bundleProvider.notifier).addInvoicePage('/tmp/offline_invoice.jpg');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Form can still be submitted offline
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'OFFLINE-001');
      await tester.enterText(fields.at(2), '06AAAAA0003A1Z3');
      await tester.enterText(fields.at(3), 'Offline Buyer');
      await tester.enterText(fields.at(4), '2026-07-27');
      await tester.enterText(fields.at(5), '1200.00');

      final submitBtn = find.text('Next — Supporting Docs');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Checklist Screen'), findsOneWidget);
    });
  });
}
