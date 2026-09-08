import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/navigation/app_shell.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/capture/camera_screen.dart';
import 'features/capture/review_screen.dart';
import 'features/capture/checklist_screen.dart';
import 'features/capture/entity_select_screen.dart';
import 'features/queue/queue_screen.dart';
import 'features/capture/my_invoices_screen.dart';
import 'features/owner/owner_dashboard_screen.dart';
import 'features/owner/owner_invoices_screen.dart';
import 'features/owner/invoice_detail_screen.dart';
import 'features/owner/alerts_screen.dart';
import 'features/owner/more_screen.dart';
import 'features/receivables/receivables_screen.dart';
import 'features/receivables/buyer_receivables_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/admin/buyer_requirements_screen.dart';
import 'features/admin/buyers_screen.dart';
import 'features/admin/principals_screen.dart';
import 'features/admin/rules_screen.dart';

/// Builds the app router: two role-scoped bottom-tab shells (worker capture
/// shell, owner dashboard shell) plus full-screen routes for login, the
/// capture flow, detail screens, and admin/master-data screens.
GoRouter buildAppRouter() => GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),

        // Capture flow — full-screen above whichever shell launched it.
        GoRoute(path: '/capture/select-entity', builder: (_, __) => const EntitySelectScreen()),
        GoRoute(path: '/capture/camera', builder: (_, __) => const CameraScreen()),
        GoRoute(path: '/capture/review', builder: (_, __) => const ReviewScreen()),
        GoRoute(
            path: '/capture/checklist',
            builder: (_, __) => const ChecklistScreen()),

        // Full-screen owner/admin routes.
        GoRoute(
          path: '/owner/invoices/:id',
          builder: (_, state) =>
              InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/owner/receivables/:buyerId',
          builder: (_, state) => BuyerReceivablesScreen(
            buyerId: state.pathParameters['buyerId']!,
            buyerName: state.extra as String?,
          ),
        ),
        GoRoute(
            path: '/owner/principals',
            builder: (_, __) => const PrincipalsScreen()),
        GoRoute(path: '/owner/buyers', builder: (_, __) => const BuyersScreen()),
        GoRoute(
          path: '/admin/buyer-requirements',
          builder: (_, __) => const BuyerRequirementsScreen(),
        ),
        GoRoute(path: '/admin/rules', builder: (_, __) => const RulesScreen()),

        // Worker shell: Capture | Queue | My Invoices.
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => WorkerShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/queue', builder: (_, __) => const QueueScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/my-invoices',
                  builder: (_, __) => const MyInvoicesScreen()),
            ]),
          ],
        ),

        // Owner shell: Dashboard | Invoices | Receivables | Alerts | More.
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => OwnerShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/owner',
                  builder: (_, __) => const OwnerDashboardScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/owner/invoices',
                  builder: (_, __) => const OwnerInvoicesScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/owner/receivables',
                  builder: (_, __) => const ReceivablesScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/alerts', builder: (_, __) => const AlertsScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/owner/more', builder: (_, __) => const MoreScreen()),
            ]),
          ],
        ),
      ],
      redirect: (context, state) {
        final container = ProviderScope.containerOf(context);
        final isLoggedIn = container.read(isAuthenticatedProvider);
        final role = container.read(currentUserProvider)?['role'] as String?;
        final loc = state.matchedLocation;
        final onAuthPage = loc == '/login';
        final onPublicPage = onAuthPage || loc == '/settings';

        if (!isLoggedIn && !onPublicPage) return '/login';
        if (isLoggedIn && onAuthPage) return homeLocationForRole(role);

        // Workers never see the owner side.
        if (isLoggedIn &&
            role == 'WORKER' &&
            (loc.startsWith('/owner') ||
                loc == '/alerts' ||
                loc.startsWith('/admin'))) {
          return '/home';
        }
        // Owner-side roles use the dashboard shell as home; the capture
        // flow and queue remain reachable for admins who capture invoices.
        if (isLoggedIn && role != null && role != 'WORKER' && loc == '/home') {
          return '/owner';
        }
        return null;
      },
    );

final _router = buildAppRouter();

class InvoiceCaptureApp extends ConsumerWidget {
  const InvoiceCaptureApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Meridian Ops',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      routerConfig: _router,
    );
  }
}
