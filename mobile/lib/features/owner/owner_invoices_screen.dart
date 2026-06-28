import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'owner_provider.dart';

class OwnerInvoicesScreen extends ConsumerWidget {
  const OwnerInvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(ownerInvoicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Invoices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(ownerInvoicesProvider),
          ),
        ],
      ),
      body: invoicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Failed to load: $e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(ownerInvoicesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (invoices) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(ownerInvoicesProvider),
          child: invoices.isEmpty
              ? const Center(
                  child: Text('No invoices yet', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: invoices.length,
                  itemBuilder: (context, i) {
                    final inv = invoices[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => context.go('/owner/invoices/${inv.id}'),
                        leading: CircleAvatar(
                          backgroundColor: inv.openDisputes > 0
                              ? Colors.red[100]
                              : inv.openExceptions > 0
                                  ? Colors.orange[100]
                                  : Colors.blue[50],
                          child: Icon(
                            inv.openDisputes > 0
                                ? Icons.gavel
                                : inv.openExceptions > 0
                                    ? Icons.warning_amber
                                    : Icons.receipt_long,
                            size: 20,
                            color: inv.openDisputes > 0
                                ? Colors.red
                                : inv.openExceptions > 0
                                    ? Colors.orange
                                    : Colors.blue,
                          ),
                        ),
                        title: Text(
                          inv.invoiceNumber,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${inv.buyerName ?? "Unknown"}  •  ${inv.invoiceDate}  •  ${inv.documentCount} doc${inv.documentCount == 1 ? "" : "s"}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${inv.grossAmount.toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (inv.openDisputes > 0)
                              Text(
                                '${inv.openDisputes} dispute${inv.openDisputes > 1 ? "s" : ""}',
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 11),
                              )
                            else if (inv.openExceptions > 0)
                              Text(
                                '${inv.openExceptions} issue${inv.openExceptions > 1 ? "s" : ""}',
                                style: const TextStyle(
                                    color: Colors.orange, fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
