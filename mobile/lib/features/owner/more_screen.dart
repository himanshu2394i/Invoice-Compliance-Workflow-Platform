import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';

/// Owner shell's More tab: master data, admin screens, sync queue, settings.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?['role'] == 'ADMIN';

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          if (user != null)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(user['full_name']?.toString() ?? ''),
              subtitle: Text(user['role']?.toString() ?? ''),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Capture invoice'),
            subtitle: const Text('Photograph and file a new invoice'),
            onTap: () => context.push('/capture/camera'),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Sync queue'),
            subtitle: const Text('Pending and synced capture bundles'),
            onTap: () => context.go('/queue'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: const Text('Principals & series'),
            subtitle: const Text('Brands and invoice-number prefixes'),
            onTap: () => context.push('/owner/principals'),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Buyers'),
            subtitle: const Text('Sales channel, credit terms, branches'),
            onTap: () => context.push('/owner/buyers'),
          ),
          if (isAdmin) ...[
            ListTile(
              leading: const Icon(Icons.checklist_outlined),
              title: const Text('Buyer document requirements'),
              onTap: () => context.push('/admin/buyer-requirements'),
            ),
            ListTile(
              leading: const Icon(Icons.rule_outlined),
              title: const Text('Approval rules'),
              onTap: () => context.push('/admin/rules'),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Server settings'),
            onTap: () => context.push('/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }
}
