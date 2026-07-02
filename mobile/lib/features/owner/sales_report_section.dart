import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../receivables/receivables_screen.dart' show formatMoney;
import 'owner_provider.dart';

/// Dashboard section: sales for a period grouped by principal / buyer /
/// channel / firm / salesman, rendered as a ranked bar list.
class SalesReportSection extends ConsumerStatefulWidget {
  const SalesReportSection({super.key});

  @override
  ConsumerState<SalesReportSection> createState() =>
      _SalesReportSectionState();
}

enum _Period { today, week, month }

class _SalesReportSectionState extends ConsumerState<SalesReportSection> {
  _Period _period = _Period.month;
  String _groupBy = 'principal';

  static const groupings = {
    'principal': 'Principal',
    'buyer': 'Buyer',
    'channel': 'Channel',
    'entity': 'Firm',
    'salesman': 'Salesman',
  };

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  SalesReportQuery get _query {
    final now = DateTime.now();
    final from = switch (_period) {
      _Period.today => now,
      _Period.week => now.subtract(const Duration(days: 6)),
      _Period.month => DateTime(now.year, now.month, 1),
    };
    return (from: _iso(from), to: _iso(now), groupBy: _groupBy);
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(salesReportProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sales', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<_Period>(
          segments: const [
            ButtonSegment(value: _Period.today, label: Text('Today')),
            ButtonSegment(value: _Period.week, label: Text('7 days')),
            ButtonSegment(value: _Period.month, label: Text('This month')),
          ],
          selected: {_period},
          onSelectionChanged: (s) => setState(() => _period = s.first),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in groupings.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _groupBy == entry.key,
                    onSelected: (_) =>
                        setState(() => _groupBy = entry.key),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        report.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Could not load report: $e',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No sales in this period.',
                    style: TextStyle(color: Colors.grey)),
              );
            }
            final maxGross = rows
                .map((r) => r.gross)
                .reduce((a, b) => a > b ? a : b)
                .clamp(1, double.infinity);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final row in rows.take(8))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(row.keyLabel,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                ),
                                Text(
                                  '${formatMoney(row.gross)} • ${row.invoiceCount} inv',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: row.gross / maxGross,
                                minHeight: 6,
                                backgroundColor: Colors.grey.shade200,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
