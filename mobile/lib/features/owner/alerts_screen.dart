import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'owner_provider.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  String _typeFilter = ''; // '' | exception | dispute | overdue_invoice

  IconData _icon(String type) => switch (type) {
        'dispute' => Icons.gavel,
        'overdue_invoice' => Icons.currency_rupee,
        _ => Icons.warning_amber,
      };

  Color _color(AlertItem a) => a.priority == 'critical'
      ? Colors.red
      : (a.type == 'dispute' ? Colors.deepOrange : Colors.orange);

  String _typeLabel(String type) => switch (type) {
        'dispute' => 'Dispute',
        'overdue_invoice' => 'Overdue payment',
        _ => 'Exception',
      };

  String _subtypeLabel(String subtype) => subtype.replaceAll('_', ' ');

  String _ageLabel(AlertItem a) {
    if (a.ageDays <= 0) return 'today';
    final noun = a.type == 'overdue_invoice' ? 'overdue' : 'open';
    return '${a.ageDays} day${a.ageDays == 1 ? '' : 's'} $noun';
  }

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(ownerAlertsProvider);

    // Tab root inside the owner shell: no back affordance, the shell
    // handles it.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(ownerAlertsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in const [
                    ('', 'All'),
                    ('exception', 'Exceptions'),
                    ('dispute', 'Disputes'),
                    ('overdue_invoice', 'Overdue'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected: _typeFilter == entry.$1,
                        onSelected: (_) =>
                            setState(() => _typeFilter = entry.$1),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: alertsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Failed to load alerts: $e')),
              data: (alerts) {
                final visible = _typeFilter.isEmpty
                    ? alerts
                    : alerts.where((a) => a.type == _typeFilter).toList();
                if (visible.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 64, color: Colors.green),
                        SizedBox(height: 16),
                        Text('Nothing needs your attention right now.',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(ownerAlertsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final a = visible[i];
                      final color = _color(a);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.15),
                            child: Icon(_icon(a.type), color: color),
                          ),
                          title: Text(
                            '${_typeLabel(a.type)}: ${_subtypeLabel(a.subtype)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Invoice ${a.invoiceNumber} • ${_ageLabel(a)}'
                            '${a.description.isNotEmpty ? '\n${a.description}' : ''}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: a.description.isNotEmpty,
                          trailing: a.priority == 'critical'
                              ? const Icon(Icons.priority_high,
                                  color: Colors.red)
                              : null,
                          onTap: () =>
                              context.push('/owner/invoices/${a.invoiceId}'),
                        ),
                      );
                    },
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
