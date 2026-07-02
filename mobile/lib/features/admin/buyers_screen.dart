import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/buyer_requirement.dart';
import '../../core/models/master_data.dart';
import '../../core/navigation/app_back.dart';
import '../auth/auth_provider.dart';
import '../owner/owner_provider.dart';

final _buyersListProvider = FutureProvider<List<Buyer>>((ref) async {
  final resp = await buildDio().get(Endpoints.buyers);
  return ((resp.data['buyers'] as List?) ?? const [])
      .map((b) => Buyer.fromJson(b as Map<String, dynamic>))
      .toList();
});

/// Buyer master data: sales channel, default credit terms, and branches.
class BuyersScreen extends ConsumerWidget {
  const BuyersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buyers = ref.watch(_buyersListProvider);
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
          title: const Text('Buyers'),
        ),
        body: buyers.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load buyers: $e')),
          data: (list) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(_buyersListProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final b = list[i];
                final meta = [
                  if (b.salesChannel != null) b.salesChannel!,
                  if (b.defaultPaymentTermsDays != null)
                    '${b.defaultPaymentTermsDays}d terms',
                ].join(' • ');
                return Card(
                  child: ListTile(
                    title: Text(b.name),
                    subtitle: Text(
                        meta.isEmpty ? b.gstin : '$meta • ${b.gstin}',
                        style: const TextStyle(fontSize: 12)),
                    trailing: isAdmin ? const Icon(Icons.edit_outlined) : null,
                    onTap: isAdmin
                        ? () async {
                            final changed =
                                await _showEditBuyerSheet(context, b);
                            if (changed == true) {
                              ref.invalidate(_buyersListProvider);
                            }
                          }
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _showEditBuyerSheet(BuildContext context, Buyer buyer) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(_).viewInsets.bottom),
        child: _EditBuyerSheet(buyer: buyer),
      ),
    );
  }
}

class _EditBuyerSheet extends StatefulWidget {
  final Buyer buyer;

  const _EditBuyerSheet({required this.buyer});

  @override
  State<_EditBuyerSheet> createState() => _EditBuyerSheetState();
}

class _EditBuyerSheetState extends State<_EditBuyerSheet> {
  static const channels = ['GT', 'MT', 'ECOM', 'HOSPITALITY', 'INDUSTRIAL'];

  late String? _channel = widget.buyer.salesChannel;
  late final TextEditingController _termsController = TextEditingController(
      text: widget.buyer.defaultPaymentTermsDays?.toString() ?? '');
  final _branchNameController = TextEditingController();
  final _branchCodeController = TextEditingController();
  List<BuyerBranch> _branches = [];
  bool _loadingBranches = true;
  bool _saving = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final branches =
          await ownerService.listBuyerBranches(buyerId: widget.buyer.id);
      if (mounted) {
        setState(() {
          _branches = branches;
          _loadingBranches = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  @override
  void dispose() {
    _termsController.dispose();
    _branchNameController.dispose();
    _branchCodeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ownerService.updateBuyer(
        widget.buyer.id,
        salesChannel: _channel,
        defaultPaymentTermsDays: int.tryParse(_termsController.text.trim()),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.data is Map
                ? (e.response?.data['error']?.toString() ?? 'Save failed')
                : 'Save failed')));
      }
    }
  }

  Future<void> _addBranch() async {
    final name = _branchNameController.text.trim();
    if (name.isEmpty) return;
    try {
      await ownerService.createBuyerBranch(
        buyerId: widget.buyer.id,
        name: name,
        code: _branchCodeController.text.trim(),
      );
      _branchNameController.clear();
      _branchCodeController.clear();
      _changed = true;
      await _loadBranches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add branch: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.buyer.name,
                style: Theme.of(context).textTheme.titleMedium),
            Text(widget.buyer.gstin,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _channel,
              decoration: const InputDecoration(
                labelText: 'Sales channel',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in channels)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _channel = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _termsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Default credit terms (days)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Branches', style: Theme.of(context).textTheme.titleSmall),
            if (_loadingBranches)
              const LinearProgressIndicator()
            else if (_branches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No branches recorded.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              )
            else
              for (final br in _branches)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.store_outlined, size: 20),
                  title: Text(br.name),
                  subtitle: br.code == null ? null : Text(br.code!),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Delete branch',
                    onPressed: () async {
                      await ownerService.deleteBuyerBranch(br.id);
                      _changed = true;
                      await _loadBranches();
                    },
                  ),
                ),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _branchNameController,
                    decoration: const InputDecoration(
                        labelText: 'New branch name', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _branchCodeController,
                    decoration: const InputDecoration(
                        labelText: 'Code', isDense: true),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Add branch',
                  onPressed: _addBranch,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_changed),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
