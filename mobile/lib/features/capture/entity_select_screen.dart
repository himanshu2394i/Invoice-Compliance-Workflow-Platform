import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'bundle_provider.dart';
import 'camera_screen.dart';

// Fixed list of seller entities for the pilot.
const _entities = [
  ('Meridian Brothers', '06AAAAA0003A1Z3'),
  ('Meridian Distributors', '06AAAAA0008A1Z8'),
  ('Meridian Gurgaon', '06AAAAA0001A1Z1'),
];

class EntitySelectScreen extends ConsumerWidget {
  const EntitySelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Seller Entity'),
        leading: BackButton(onPressed: () => context.go('/home')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Row(
            children: [
              Icon(Icons.business, color: Color(0xFF1A237E), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Choose the seller entity issuing this invoice:',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          for (final entity in _entities)
            Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1A237E),
                  child:
                      Icon(Icons.store_outlined, color: Colors.white, size: 22),
                ),
                title: Text(
                  entity.$1,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Text('GSTIN: ${entity.$2}',
                    style: const TextStyle(fontSize: 13)),
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 16, color: Color(0xFF1A237E)),
                onTap: () {
                  ref.read(bundleProvider.notifier).reset();
                  ref
                      .read(bundleProvider.notifier)
                      .setPreselectedEntityGstin(entity.$2);
                  context.go(
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
    );
  }
}
