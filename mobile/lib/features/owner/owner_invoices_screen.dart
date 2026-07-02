import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'owner_provider.dart';

List<OwnerInvoice> filterOwnerInvoices(
  List<OwnerInvoice> invoices,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return invoices;

  return invoices.where((inv) {
    final haystack = [
      inv.invoiceNumber,
      inv.buyerName ?? '',
      inv.buyerGstin ?? '',
      inv.entityName ?? '',
      inv.currentState,
      inv.invoiceDate,
      inv.grossAmount.toStringAsFixed(0),
      inv.grossAmount.toStringAsFixed(2),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }).toList();
}

class OwnerInvoicesScreen extends ConsumerStatefulWidget {
  const OwnerInvoicesScreen({super.key});

  @override
  ConsumerState<OwnerInvoicesScreen> createState() =>
      _OwnerInvoicesScreenState();
}

class _OwnerInvoicesScreenState extends ConsumerState<OwnerInvoicesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(ownerInvoicesProvider);

    // Tab root inside the owner shell: no back affordance, the shell
    // handles it.
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
          data: _buildInvoices,
        ),
    );
  }

  Widget _buildInvoices(List<OwnerInvoice> invoices) {
    final visibleInvoices =
        filterOwnerInvoices(invoices, _searchController.text);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(ownerInvoicesProvider),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
              hintText: 'Search invoice, buyer, GSTIN, amount, status',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (invoices.isEmpty)
            const _EmptyInvoicesMessage(message: 'No invoices yet')
          else if (visibleInvoices.isEmpty)
            const _EmptyInvoicesMessage(message: 'No matching invoices')
          else
            for (final inv in visibleInvoices) _InvoiceListCard(invoice: inv),
        ],
      ),
    );
  }
}

class _EmptyInvoicesMessage extends StatelessWidget {
  final String message;

  const _EmptyInvoicesMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(message, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }
}

class _InvoiceListCard extends StatelessWidget {
  final OwnerInvoice invoice;

  const _InvoiceListCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.go('/owner/invoices/${invoice.id}'),
        leading: CircleAvatar(
          backgroundColor: invoice.openDisputes > 0
              ? Colors.red[100]
              : invoice.openExceptions > 0
                  ? Colors.orange[100]
                  : Colors.blue[50],
          child: Icon(
            invoice.openDisputes > 0
                ? Icons.gavel
                : invoice.openExceptions > 0
                    ? Icons.warning_amber
                    : Icons.receipt_long,
            size: 20,
            color: invoice.openDisputes > 0
                ? Colors.red
                : invoice.openExceptions > 0
                    ? Colors.orange
                    : Colors.blue,
          ),
        ),
        title: Text(
          invoice.invoiceNumber,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${invoice.buyerName ?? "Unknown"}  |  ${invoice.invoiceDate}  |  ${invoice.documentCount} doc${invoice.documentCount == 1 ? "" : "s"}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Rs ${invoice.grossAmount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (invoice.openDisputes > 0)
              Text(
                '${invoice.openDisputes} dispute${invoice.openDisputes > 1 ? "s" : ""}',
                style: const TextStyle(color: Colors.red, fontSize: 11),
              )
            else if (invoice.openExceptions > 0)
              Text(
                '${invoice.openExceptions} issue${invoice.openExceptions > 1 ? "s" : ""}',
                style: const TextStyle(color: Colors.orange, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
