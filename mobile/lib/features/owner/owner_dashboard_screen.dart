import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../capture/bundle_provider.dart';
import '../capture/camera_screen.dart';
import 'owner_provider.dart';
import 'sales_report_section.dart';

class OwnerDashboardScreen extends ConsumerWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(ownerDashboardProvider);
    final invoicesAsync = ref.watch(ownerInvoicesProvider);
    final user = ref.watch(currentUserProvider);

    // Tab root inside the owner shell: no back affordance, the shell
    // handles back and exit. Admin screens moved to the More tab.
    return Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard'),
          actions: [
            if (user?['role'] == 'ADMIN' || user?['role'] == 'MANAGER')
              IconButton(
                icon: const Icon(Icons.camera_alt_outlined),
                tooltip: 'Capture invoice',
                onPressed: () {
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
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(ownerDashboardProvider);
                ref.invalidate(ownerInvoicesProvider);
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(ownerDashboardProvider);
            ref.invalidate(ownerInvoicesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary tiles
              dashAsync.when(
                loading: () => const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load dashboard: $e'),
                  ),
                ),
                data: (dash) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Summary',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _StatTile(
                          label: 'Total Invoices',
                          value: '${dash.totalInvoices}',
                          icon: Icons.receipt_long,
                          color: Colors.blue,
                        )),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _StatTile(
                          label: "Today's Value",
                          value: '₹${_fmt(dash.todayAmount)}',
                          icon: Icons.currency_rupee,
                          color: Colors.green,
                        )),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _StatTile(
                          label: 'Open Exceptions',
                          value: '${dash.openExceptions}',
                          icon: Icons.warning_amber,
                          color: dash.openExceptions > 0
                              ? Colors.orange
                              : Colors.grey,
                          urgent: dash.openExceptions > 0,
                        )),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _StatTile(
                          label: 'Open Disputes',
                          value: '${dash.openDisputes}',
                          icon: Icons.gavel,
                          color:
                              dash.openDisputes > 0 ? Colors.red : Colors.grey,
                          urgent: dash.openDisputes > 0,
                        )),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const SalesReportSection(),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Invoices',
                      style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => context.go('/owner/invoices'),
                    child: const Text('See all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Recent invoice list
              invoicesAsync.when(
                loading: () => const Center(
                    child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                )),
                error: (e, _) => Text('Failed to load invoices: $e',
                    style: const TextStyle(color: Colors.red)),
                data: (invoices) => invoices.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text('No invoices yet',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    : Column(
                        children: invoices
                            .take(10)
                            .map((inv) => _InvoiceCard(invoice: inv))
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool urgent;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.urgent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: urgent ? color.withOpacity(0.08) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final OwnerInvoice invoice;
  const _InvoiceCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.go('/owner/invoices/${invoice.id}'),
        title: Text(invoice.invoiceNumber,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${invoice.buyerName ?? "Unknown buyer"}  •  ${invoice.invoiceDate.substring(0, 10)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${invoice.grossAmount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (invoice.openDisputes > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${invoice.openDisputes} dispute${invoice.openDisputes > 1 ? "s" : ""}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              )
            else if (invoice.openExceptions > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${invoice.openExceptions} issue${invoice.openExceptions > 1 ? "s" : ""}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
          ],
        ),
        leading: CircleAvatar(
          backgroundColor:
              invoice.openDisputes > 0 ? Colors.red[100] : Colors.blue[50],
          child: Icon(
            invoice.openDisputes > 0 ? Icons.gavel : Icons.receipt_long,
            color: invoice.openDisputes > 0 ? Colors.red : Colors.blue,
            size: 20,
          ),
        ),
      ),
    );
  }
}
