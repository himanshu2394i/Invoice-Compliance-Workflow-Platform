import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/receivables.dart';
import '../owner/owner_provider.dart';

String formatMoney(double v) {
  final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  // Indian digit grouping: 12,34,567
  final parts = s.split('.');
  var intPart = parts[0];
  final sign = intPart.startsWith('-') ? '-' : '';
  if (sign.isNotEmpty) intPart = intPart.substring(1);
  if (intPart.length > 3) {
    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    intPart = '${groups.join(',')},$last3';
  }
  return '₹$sign$intPart${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// Owner shell tab: who owes what, ranked by outstanding amount.
class ReceivablesScreen extends ConsumerWidget {
  const ReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receivables = ref.watch(receivablesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Receivables')),
      body: receivables.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('Could not load receivables.'),
                const SizedBox(height: 4),
                Text('$e',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(receivablesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (summary) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(receivablesProvider),
          child: summary.buyers.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Icon(Icons.task_alt, size: 64, color: Colors.green),
                    SizedBox(height: 16),
                    Center(
                        child: Text('No outstanding credit invoices.',
                            style: TextStyle(color: Colors.grey))),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _SummaryHeader(summary: summary),
                    const SizedBox(height: 8),
                    for (final buyer in summary.buyers)
                      _BuyerCard(buyer: buyer),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final ReceivablesSummary summary;

  const _SummaryHeader({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total outstanding'),
                  Text(
                    formatMoney(summary.totalOutstanding),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Overdue'),
                  Text(
                    formatMoney(summary.totalOverdue),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: summary.totalOverdue > 0
                              ? Colors.red.shade700
                              : null,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyerCard extends StatelessWidget {
  final BuyerReceivable buyer;

  const _BuyerCard({required this.buyer});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(buyer.buyerName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${buyer.openInvoices} open invoice(s) • ${buyer.buyerGstin}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (buyer.bucketCurrent > 0)
                  _AgingChip(
                      label: 'Current ${formatMoney(buyer.bucketCurrent)}',
                      color: Colors.green),
                if (buyer.bucket1To30 > 0)
                  _AgingChip(
                      label: '1-30d ${formatMoney(buyer.bucket1To30)}',
                      color: Colors.orange),
                if (buyer.bucket31To60 > 0)
                  _AgingChip(
                      label: '31-60d ${formatMoney(buyer.bucket31To60)}',
                      color: Colors.deepOrange),
                if (buyer.bucket60Plus > 0)
                  _AgingChip(
                      label: '60d+ ${formatMoney(buyer.bucket60Plus)}',
                      color: Colors.red),
              ],
            ),
          ],
        ),
        trailing: Text(
          formatMoney(buyer.outstanding),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: buyer.overdue > 0 ? Colors.red.shade700 : null,
          ),
        ),
        onTap: () => context.push(
          '/owner/receivables/${buyer.buyerId}',
          extra: buyer.buyerName,
        ),
      ),
    );
  }
}

class _AgingChip extends StatelessWidget {
  final String label;
  final MaterialColor color;

  const _AgingChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade200),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color.shade900)),
    );
  }
}
