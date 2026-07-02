import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/master_data.dart';
import '../../core/navigation/app_back.dart';
import '../auth/auth_provider.dart';
import '../owner/owner_provider.dart';

/// Principals (brands distributed) and the invoice-series registry that maps
/// invoice-number prefixes to (entity, principal). Reads for everyone on the
/// owner side; add/delete is ADMIN-only, matching the backend gates.
class PrincipalsScreen extends ConsumerWidget {
  const PrincipalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final principals = ref.watch(principalsProvider);
    final series = ref.watch(seriesRegistryProvider);
    final isAdmin = ref.watch(currentUserProvider)?['role'] == 'ADMIN';

    return AppBackScope(
      fallbackLocation: '/owner/more',
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () =>
                AppBackScope.goBack(context, fallbackLocation: '/owner/more'),
          ),
          title: const Text('Principals & Series'),
        ),
        floatingActionButton: isAdmin
            ? FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: () => _showAddMenu(context, ref),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(principalsProvider);
            ref.invalidate(seriesRegistryProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('Principals',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              principals.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Could not load principals: $e'),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No principals yet.',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : Column(
                        children: [
                          for (final p in list)
                            Card(
                              child: ListTile(
                                leading:
                                    const Icon(Icons.business_outlined),
                                title: Text(p.name),
                                subtitle:
                                    p.code == null ? null : Text(p.code!),
                                trailing: isAdmin
                                    ? IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline),
                                        tooltip: 'Delete principal',
                                        onPressed: () =>
                                            _deletePrincipal(
                                                context, ref, p),
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              Text('Invoice series',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text(
                'Invoice numbers starting with a prefix are stamped with '
                'that entity and principal automatically.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              series.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Could not load series: $e'),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No series mapped yet.',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : Column(
                        children: [
                          for (final s in list)
                            Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    s.seriesPrefix.length > 3
                                        ? s.seriesPrefix.substring(0, 3)
                                        : s.seriesPrefix,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                title: Text(s.seriesPrefix),
                                subtitle: Text([
                                  if (s.principalName != null)
                                    s.principalName!,
                                  if (s.entityName != null) s.entityName!,
                                ].join(' • ')),
                                trailing: isAdmin
                                    ? IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline),
                                        tooltip: 'Delete series mapping',
                                        onPressed: () =>
                                            _deleteSeries(context, ref, s),
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.business_outlined),
              title: const Text('Add principal'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addPrincipal(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tag),
              title: const Text('Add series mapping'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addSeries(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPrincipal(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add principal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Name (e.g. Mondelez)'),
            ),
            TextField(
              controller: codeController,
              decoration:
                  const InputDecoration(labelText: 'Code (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || nameController.text.trim().isEmpty) return;
    try {
      await ownerService.createPrincipal(nameController.text.trim(),
          code: codeController.text.trim());
      ref.invalidate(principalsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not add principal: $e')));
      }
    }
  }

  Future<void> _addSeries(BuildContext context, WidgetRef ref) async {
    final prefixController = TextEditingController();
    final principals =
        await ref.read(principalsProvider.future).catchError((_) => <Principal>[]);
    String? principalId;
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add series mapping'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: prefixController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Series prefix (e.g. CAD)'),
            ),
            DropdownButtonFormField<String>(
              decoration:
                  const InputDecoration(labelText: 'Principal (optional)'),
              items: [
                for (final p in principals)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => principalId = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || prefixController.text.trim().isEmpty) return;
    try {
      await ownerService.upsertSeriesEntry(
        seriesPrefix: prefixController.text.trim().toUpperCase(),
        principalId: principalId,
      );
      ref.invalidate(seriesRegistryProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not add series: $e')));
      }
    }
  }

  Future<void> _deletePrincipal(
      BuildContext context, WidgetRef ref, Principal p) async {
    final confirmed = await _confirm(context, 'Delete principal ${p.name}?');
    if (confirmed != true) return;
    try {
      await ownerService.deletePrincipal(p.id);
      ref.invalidate(principalsProvider);
      ref.invalidate(seriesRegistryProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  Future<void> _deleteSeries(
      BuildContext context, WidgetRef ref, SeriesEntry s) async {
    final confirmed =
        await _confirm(context, 'Delete series mapping ${s.seriesPrefix}?');
    if (confirmed != true) return;
    try {
      await ownerService.deleteSeriesEntry(s.id);
      ref.invalidate(seriesRegistryProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  Future<bool?> _confirm(BuildContext context, String message) =>
      showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
}
