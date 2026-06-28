import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../capture/bundle_provider.dart';
import '../capture/camera_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final pending =
        HiveService.allBundles().where((b) => b.status != 'synced').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Capture'),
        actions: [
          if (pending > 0)
            IconButton(
              icon: Badge(
                label: Text('$pending'),
                child: const Icon(Icons.cloud_upload_outlined),
              ),
              onPressed: () => context.go('/queue'),
              tooltip: '$pending pending sync',
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.receipt_long, size: 80, color: Color(0xFF1A237E)),
              const SizedBox(height: 16),
              Text(
                'Welcome, ${user?['full_name'] ?? 'Worker'}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the button below to start capturing an invoice.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: () {
                  // Reset any previous session
                  ref.read(bundleProvider.notifier).reset();
                  context.go(
                    '/capture/camera',
                    extra: const CameraTarget(
                      documentType: 'INVOICE',
                      label: 'Tax Invoice',
                      isPrimary: true,
                    ),
                  );
                },
                icon: const Icon(Icons.camera_alt, size: 28),
                label: const Text('Capture Invoice', style: TextStyle(fontSize: 18)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.go('/queue'),
                icon: const Icon(Icons.history),
                label: Text(
                  pending > 0 ? 'View Queue ($pending pending)' : 'View Queue',
                  style: const TextStyle(fontSize: 16),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              // Owner dashboard — only for ADMIN and MANAGER roles
              if (user?['role'] == 'ADMIN' || user?['role'] == 'MANAGER') ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.go('/owner'),
                  icon: const Icon(Icons.dashboard, color: Color(0xFF1A237E)),
                  label: const Text(
                    'Owner Dashboard',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: const Color(0xFF1A237E),
                    side: const BorderSide(color: Color(0xFF1A237E)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
