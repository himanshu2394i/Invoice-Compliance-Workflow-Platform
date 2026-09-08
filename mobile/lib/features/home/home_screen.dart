import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../capture/bundle_provider.dart';
import '../capture/camera_screen.dart';

/// Worker shell's Capture tab root. Queue and My Invoices live on their own
/// tabs; back-navigation and exit handling belong to the shell.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final pending =
        HiveService.allBundles().where((b) => b.status != 'synced').length;
    final draft = HiveService.loadCaptureDraft();

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
              if (draft != null) ...[
                FilledButton.icon(
                  onPressed: () {
                    ref.read(bundleProvider.notifier).restoreDraft(draft);
                    context.push('/capture/review');
                  },
                  icon: const Icon(Icons.restore_page_outlined, size: 24),
                  label: const Text('Resume Draft',
                      style: TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await HiveService.clearCaptureDraft();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Discard Draft'),
                ),
                const SizedBox(height: 24),
              ],
              FilledButton.icon(
                onPressed: () => _showEntitySelectionModal(context),
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

  void _showEntitySelectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.business, color: Color(0xFF1A237E), size: 28),
                SizedBox(width: 12),
                Text(
                  'Select Billing Seller Entity',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the seller entity issuing this invoice:',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            for (final entity in [
              ('Meridian Brothers', '06AAAAA0003A1Z3'),
              ('Meridian Distributors', '06AAAAA0008A1Z8'),
              ('Meridian Gurgaon', '06AAAAA0001A1Z1'),
            ])
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.store, color: Color(0xFF1A237E)),
                  title: Text(
                    entity.$1,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('GSTIN: ${entity.$2}'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(bundleProvider.notifier).reset();
                    ref
                        .read(bundleProvider.notifier)
                        .setPreselectedEntityGstin(entity.$2);
                    context.push(
                      '/capture/camera',
                      extra: const CameraTarget(
                        documentType: 'INVOICE',
                        label: 'Tax Invoice',
                        isPrimary: true,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
