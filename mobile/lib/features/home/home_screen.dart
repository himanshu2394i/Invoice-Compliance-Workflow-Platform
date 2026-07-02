import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../capture/bundle_provider.dart';
import '../capture/camera_screen.dart';

/// Worker shell's Capture tab root. Queue and My Invoices live on their own
/// tabs; back-navigation and exit handling belong to the shell.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final pending =
        HiveService.allBundles().where((b) => b.status != 'synced').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture'),
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
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: 'Server settings',
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
              const Icon(Icons.receipt_long,
                  size: 80, color: Color(0xFF1A237E)),
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
                  context.push(
                    '/capture/camera',
                    extra: const CameraTarget(
                      documentType: 'INVOICE',
                      label: 'Tax Invoice',
                      isPrimary: true,
                    ),
                  );
                },
                icon: const Icon(Icons.camera_alt, size: 28),
                label: const Text('Capture Invoice',
                    style: TextStyle(fontSize: 18)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
