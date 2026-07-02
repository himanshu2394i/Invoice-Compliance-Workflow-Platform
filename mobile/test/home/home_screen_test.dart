import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:invoice_capture/core/models/bundle.dart';
import 'package:invoice_capture/features/auth/auth_provider.dart';
import 'package:invoice_capture/features/home/home_screen.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('home_hive_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(QueuedPhotoAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(QueuedBundleAdapter());
    }
    await Hive.openBox<QueuedBundle>('queued_bundles');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpHomeAsRole(WidgetTester tester, String role) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(
            path: '/owner',
            builder: (_, __) => const Scaffold(body: Text('Owner'))),
        GoRoute(
            path: '/queue',
            builder: (_, __) => const Scaffold(body: Text('Queue'))),
        GoRoute(
            path: '/my-invoices',
            builder: (_, __) => const Scaffold(body: Text('My Invoices'))),
        GoRoute(
            path: '/settings',
            builder: (_, __) => const Scaffold(body: Text('Settings'))),
        GoRoute(
            path: '/capture/camera',
            builder: (_, __) => const Scaffold(body: Text('Camera'))),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (_) => AuthNotifier(
              initialState: AuthState(
                isLoggedIn: true,
                user: {'full_name': '$role User', 'role': role},
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('finance users can navigate to the review dashboard',
      (tester) async {
    await pumpHomeAsRole(tester, 'FINANCE');

    expect(find.text('Owner Dashboard'), findsOneWidget);
  });

  testWidgets('reviewer users can navigate to the review dashboard',
      (tester) async {
    await pumpHomeAsRole(tester, 'REVIEWER');

    expect(find.text('Owner Dashboard'), findsOneWidget);
  });

  testWidgets('home requires two Android back presses before exit',
      (tester) async {
    await pumpHomeAsRole(tester, 'WORKER');

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(find.text('Invoice Capture'), findsWidgets);
  });
}
