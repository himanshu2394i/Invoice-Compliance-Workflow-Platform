import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'owner_provider.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  IconData _icon(String type) =>
      type == 'dispute' ? Icons.gavel : Icons.warning_amber;

  Color _color(String type) => type == 'dispute' ? Colors.red : Colors.orange;

  String _subtypeLabel(String subtype) => subtype.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        body: alertsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load alerts: $e')),
          data: (alerts) => alerts.isEmpty
              ? const Center(
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
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(ownerAlertsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: alerts.length,
                    itemBuilder: (context, i) {
                      final a = alerts[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                _color(a.type).withValues(alpha: 0.15),
                            child: Icon(_icon(a.type), color: _color(a.type)),
                          ),
                          title: Text(
                            '${a.type == 'dispute' ? 'Dispute' : 'Exception'}: ${_subtypeLabel(a.subtype)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Invoice ${a.invoiceNumber}'
                            '${a.description.isNotEmpty ? '\n${a.description}' : ''}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: a.description.isNotEmpty,
                          onTap: () =>
                              context.push('/owner/invoices/${a.invoiceId}'),
                        ),
                      );
                    },
                  ),
                ),
        ),
    );
  }
}
