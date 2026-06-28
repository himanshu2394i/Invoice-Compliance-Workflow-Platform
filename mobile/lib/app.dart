import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/capture/camera_screen.dart';
import 'features/capture/review_screen.dart';
import 'features/capture/checklist_screen.dart';
import 'features/queue/queue_screen.dart';
import 'features/owner/owner_dashboard_screen.dart';
import 'features/owner/owner_invoices_screen.dart';
import 'features/owner/invoice_detail_screen.dart';
import 'features/settings/settings_screen.dart';

final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/capture/camera', builder: (_, __) => const CameraScreen()),
    GoRoute(path: '/capture/review', builder: (_, __) => const ReviewScreen()),
    GoRoute(path: '/capture/checklist', builder: (_, __) => const ChecklistScreen()),
    GoRoute(path: '/queue', builder: (_, __) => const QueueScreen()),
    // Owner routes — dashboard + invoice detail
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/owner', builder: (_, __) => const OwnerDashboardScreen()),
    GoRoute(path: '/owner/invoices', builder: (_, __) => const OwnerInvoicesScreen()),
    GoRoute(
      path: '/owner/invoices/:id',
      builder: (_, state) => InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
    ),
  ],
  redirect: (context, state) {
    final container = ProviderScope.containerOf(context);
    final isLoggedIn = container.read(isAuthenticatedProvider);
    final onAuthPage = state.matchedLocation == '/login';
    if (!isLoggedIn && !onAuthPage) return '/login';
    if (isLoggedIn && onAuthPage) return '/home';
    return null;
  },
);

class InvoiceCaptureApp extends ConsumerWidget {
  const InvoiceCaptureApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Invoice Capture',
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
