import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/owner/owner_provider.dart';

/// Where a freshly logged-in (or misrouted) user belongs: workers live in the
/// capture shell, every owner-side role lands on the dashboard shell.
String homeLocationForRole(String? role) =>
    role == 'WORKER' ? '/home' : '/owner';

/// Worker shell: Capture | Queue | My Invoices.
class WorkerShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const WorkerShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return ShellScaffold(
      navigationShell: navigationShell,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.camera_alt_outlined),
          selectedIcon: Icon(Icons.camera_alt),
          label: 'Capture',
        ),
        NavigationDestination(
          icon: Icon(Icons.cloud_upload_outlined),
          selectedIcon: Icon(Icons.cloud_upload),
          label: 'Queue',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'My Invoices',
        ),
      ],
    );
  }
}

/// Owner shell: Dashboard | Invoices | Receivables | Alerts | More.
/// The Alerts destination carries a live badge so an owner opening the app
/// sees open work without visiting the tab.
class OwnerShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const OwnerShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertCount = ref
        .watch(ownerAlertsProvider)
        .maybeWhen(data: (alerts) => alerts.length, orElse: () => 0);
    return ShellScaffold(
      navigationShell: navigationShell,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        const NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Invoices',
        ),
        const NavigationDestination(
          icon: Icon(Icons.currency_rupee_outlined),
          selectedIcon: Icon(Icons.currency_rupee),
          label: 'Receivables',
        ),
        NavigationDestination(
          icon: Badge(
            label: Text('$alertCount'),
            isLabelVisible: alertCount > 0,
            child: const Icon(Icons.notifications_outlined),
          ),
          selectedIcon: Badge(
            label: Text('$alertCount'),
            isLabelVisible: alertCount > 0,
            child: const Icon(Icons.notifications),
          ),
          label: 'Alerts',
        ),
        const NavigationDestination(
          icon: Icon(Icons.more_horiz),
          label: 'More',
        ),
      ],
    );
  }
}

/// Shared shell chrome: bottom NavigationBar + the app-wide Android back
/// policy. Back on a non-first tab returns to the first tab; back on the
/// first tab requires a second press within [exitWindow] to leave the app.
class ShellScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final List<NavigationDestination> destinations;
  final Duration exitWindow;

  const ShellScaffold({
    super.key,
    required this.navigationShell,
    required this.destinations,
    this.exitWindow = const Duration(seconds: 2),
  });

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold> {
  DateTime? _lastExitRequest;

  /// Returns true when the back press was consumed (tab switch or exit
  /// prompt), false to let the system handle it (actual app exit).
  bool _handleBack() {
    final shell = widget.navigationShell;
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return true;
    }
    final now = DateTime.now();
    final shouldExit = _lastExitRequest != null &&
        now.difference(_lastExitRequest!) <= widget.exitWindow;
    if (shouldExit) {
      SystemNavigator.pop();
      return true;
    }
    _lastExitRequest = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Press back again to exit')),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // BackButtonListener catches the Android hardware/system back through
    // go_router's BackButtonDispatcher — a PopScope inside the shell page
    // never sees it because the branch navigators sit in between. PopScope
    // still guards predictive-back/edge gestures, which bypass the
    // dispatcher and pop the enclosing route directly.
    return BackButtonListener(
      onBackButtonPressed: () async {
        // A full-screen route (capture flow, invoice detail) pushed above
        // the shell must handle its own back; only intercept when the shell
        // page itself is current.
        final modalRoute = ModalRoute.of(context);
        if (modalRoute != null && !modalRoute.isCurrent) return false;
        return _handleBack();
      },
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (didPop) return;
          _handleBack();
        },
        child: Scaffold(
          body: widget.navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: widget.navigationShell.currentIndex,
            destinations: widget.destinations,
            onDestinationSelected: (index) => widget.navigationShell.goBranch(
              index,
              // Re-tapping the active tab resets that tab to its root.
              initialLocation: index == widget.navigationShell.currentIndex,
            ),
          ),
        ),
      ),
    );
  }
}
