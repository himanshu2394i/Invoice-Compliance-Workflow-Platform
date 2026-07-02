import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/receivables.dart';
import '../auth/auth_provider.dart';
import '../owner/owner_provider.dart';
import 'receivables_screen.dart' show formatMoney;
import 'record_payment_sheet.dart';

/// Full-screen drill-down: one buyer's open credit invoices, oldest due
/// first, with payment recording for FINANCE/MANAGER/ADMIN.
class BuyerReceivablesScreen extends ConsumerWidget {
  final String buyerId;
  final String? buyerName;

  const BuyerReceivablesScreen({
    super.key,
    required this.buyerId,
    this.buyerName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(buyerReceivablesProvider(buyerId));
    final role = ref.watch(currentUserProvider)?['role'];
    final canRecord =
        role == 'ADMIN' || role == 'MANAGER' || role == 'FINANCE';

    return Scaffold(
      appBar: AppBar(title: Text(buyerName ?? 'Buyer receivables')),
      body: invoices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (list) => list.isEmpty
            ? const Center(
                child: Text('No open credit invoices for this buyer.'))
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(buyerReceivablesProvider(buyerId)),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _InvoiceCard(
                    invoice: list[i],
                    canRecord: canRecord,
                    onRecorded: () {
                      ref.invalidate(buyerReceivablesProvider(buyerId));
                      ref.invalidate(receivablesProvider);
                    },
                  ),
                ),
              ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final ReceivableInvoice invoice;
  final bool canRecord;
  final VoidCallback onRecorded;

  const _InvoiceCard({
    required this.invoice,
    required this.canRecord,
    required this.onRecorded,
  });

  String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final overdue = invoice.daysOverdue > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(invoice.invoiceNumber,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(formatMoney(invoice.balance),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: overdue ? Colors.red.shade700 : null,
                    )),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Invoiced ${_date(invoice.invoiceDate)} • Due ${_date(invoice.dueDate)}'
              '${invoice.paid > 0 ? ' • Paid ${formatMoney(invoice.paid)} of ${formatMoney(invoice.total)}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (overdue)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${invoice.daysOverdue} day(s) overdue',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600)),
              ),
            if (canRecord)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Record payment'),
                  onPressed: () async {
                    final recorded = await showRecordPaymentSheet(
                      context,
                      invoiceId: invoice.invoiceId,
                      invoiceNumber: invoice.invoiceNumber,
                      balance: invoice.balance,
                    );
                    if (recorded == true) onRecorded();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
