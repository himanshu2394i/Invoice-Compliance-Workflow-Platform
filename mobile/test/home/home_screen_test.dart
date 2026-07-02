import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:invoice_capture/core/models/bundle.dart';
import 'package:invoice_capture/core/navigation/app_shell.dart';
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

  /// Pumps HomeScreen inside the real worker shell, the way the app mounts
  /// it, so back behavior and tab chrome are exercised together.
  Future<void> pumpWorkerHome(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => WorkerShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/queue',
                  builder: (_, __) => const Scaffold(body: Text('Queue stub'))),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/my-invoices',
                  builder: (_, __) =>
                      const Scaffold(body: Text('My invoices stub'))),
            ]),
          ],
        ),
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
              initialState: const AuthState(
                isLoggedIn: true,
                user: {'full_name': 'Worker User', 'role': 'WORKER'},
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('worker home shows the capture action and tab bar',
      (tester) async {
    await pumpWorkerHome(tester);

    expect(find.text('Capture Invoice'), findsOneWidget);
    expect(find.text('Welcome, Worker User'), findsOneWidget);
    // Shell tabs are present.
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('My Invoices'), findsOneWidget);
  });

  testWidgets('home requires two Android back presses before exit',
      (tester) async {
    await pumpWorkerHome(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(find.text('Capture Invoice'), findsOneWidget);
  });
}
