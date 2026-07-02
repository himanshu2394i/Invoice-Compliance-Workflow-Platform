import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_capture/core/navigation/app_shell.dart';
import 'package:invoice_capture/features/owner/owner_provider.dart';

GoRouter _workerRouter() => GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => WorkerShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/home', builder: (_, __) => const Text('Capture root')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/queue', builder: (_, __) => const Text('Queue root')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/my-invoices',
                  builder: (_, __) => const Text('My invoices root')),
            ]),
          ],
        ),
      ],
    );

GoRouter _ownerRouter() => GoRouter(
      initialLocation: '/owner',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => OwnerShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/owner', builder: (_, __) => const Text('Dashboard root')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/owner/invoices',
                  builder: (_, __) => const Text('Invoices root')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/owner/receivables',
                  builder: (_, __) => const Text('Receivables root')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/alerts', builder: (_, __) => const Text('Alerts root')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/owner/more', builder: (_, __) => const Text('More root')),
            ]),
          ],
        ),
      ],
    );

void main() {
  testWidgets('worker shell shows three tabs and switches branches',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _workerRouter()));
    await tester.pumpAndSettle();

    expect(find.text('Capture root'), findsOneWidget);
    expect(find.text('Capture'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('My Invoices'), findsOneWidget);

    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();
    expect(find.text('Queue root'), findsOneWidget);
  });

  testWidgets('hardware back on a non-first tab returns to the first tab',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _workerRouter()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Invoices'));
    await tester.pumpAndSettle();
    expect(find.text('My invoices root'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Capture root'), findsOneWidget);
  });

  testWidgets('hardware back on the first tab asks for a second press to exit',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _workerRouter()));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(find.text('Capture root'), findsOneWidget);
  });

  testWidgets('owner shell shows five tabs and switches to receivables',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // OwnerShell watches the alert feed for its badge; keep it inert.
          ownerAlertsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp.router(routerConfig: _ownerRouter()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard root'), findsOneWidget);
    for (final label in ['Dashboard', 'Invoices', 'Receivables', 'Alerts', 'More']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Receivables'));
    await tester.pumpAndSettle();
    expect(find.text('Receivables root'), findsOneWidget);
  });

  test('homeLocationForRole routes workers to capture, owners to dashboard', () {
    expect(homeLocationForRole('WORKER'), '/home');
    expect(homeLocationForRole('ADMIN'), '/owner');
    expect(homeLocationForRole('MANAGER'), '/owner');
    expect(homeLocationForRole('FINANCE'), '/owner');
    expect(homeLocationForRole('REVIEWER'), '/owner');
    expect(homeLocationForRole(null), '/owner');
  });
}
