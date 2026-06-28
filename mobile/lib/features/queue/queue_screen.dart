import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/bundle.dart';
import '../../core/storage/hive_service.dart';
import '../capture/sync_service.dart';

// Provider that returns all bundles sorted by date desc
final pendingBundlesProvider = Provider<List<QueuedBundle>>((_) {
  return HiveService.allBundles();
});

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  bool _syncing = false;

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final (synced, failed) = await syncService.syncPending();
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? '$synced bundle(s) synced successfully.'
                : '$synced synced, $failed failed — will retry automatically.',
          ),
        ),
      );
    }
  }

  Color _statusColor(String status) {
    return switch (status) {
      'synced' => Colors.green,
      'failed' => Colors.red,
      'syncing' => Colors.orange,
      _ => Colors.grey,
    };
  }

  IconData _statusIcon(String status) {
    return switch (status) {
      'synced' => Icons.cloud_done,
      'failed' => Icons.cloud_off,
      'syncing' => Icons.sync,
      _ => Icons.schedule,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Re-read directly on build to get fresh data after sync
    final bundles = HiveService.allBundles();
    final pending = bundles.where((b) => b.status != 'synced').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Queue'),
        actions: [
          if (pending > 0)
            TextButton.icon(
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text('Sync ($pending)'),
            ),
        ],
      ),
      body: bundles.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No bundles yet', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: bundles.length,
              itemBuilder: (context, i) {
                final b = bundles[i];
                final date = DateTime.fromMillisecondsSinceEpoch(b.createdAtMs);
                return Card(
                  child: ListTile(
                    leading: Icon(
                      _statusIcon(b.status),
                      color: _statusColor(b.status),
                    ),
                    title: Text(b.invoiceNumber),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${b.buyerName}  •  ₹${b.totalAmount.toStringAsFixed(2)}'),
                        Text(
                          '${date.day.toString().padLeft(2, '0')}/'
                          '${date.month.toString().padLeft(2, '0')}/'
                          '${date.year}  ${date.hour.toString().padLeft(2, '0')}:'
                          '${date.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (b.syncError != null)
                          Text(
                            b.syncError!,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.redAccent),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(
                        b.status.toUpperCase(),
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                      backgroundColor: _statusColor(b.status),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
