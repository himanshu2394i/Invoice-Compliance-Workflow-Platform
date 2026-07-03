import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/buyer_requirement.dart';
import '../../core/navigation/app_back.dart';

/// Admin screen to view/add document requirements per buyer. Only an upsert
/// endpoint exists server-side (keyed on buyer_id + document_type) -- there's
/// no delete yet, so re-adding the same document type just updates it.
class BuyerRequirementsScreen extends StatefulWidget {
  const BuyerRequirementsScreen({super.key});

  @override
  State<BuyerRequirementsScreen> createState() =>
      _BuyerRequirementsScreenState();
}

class _BuyerRequirementsScreenState extends State<BuyerRequirementsScreen> {
  final _dio = buildDio();
  List<Buyer> _buyers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBuyers();
  }

  Future<void> _loadBuyers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _dio.get(Endpoints.buyers);
      final list = (resp.data['buyers'] as List? ?? [])
          .map((b) => Buyer.fromJson(b as Map<String, dynamic>))
          .toList();
      setState(() {
        _buyers = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load buyers: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackScope(
      fallbackLocation: '/owner',
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => AppBackScope.goBack(
              context,
              fallbackLocation: '/owner',
            ),
          ),
          title: const Text('Buyer Document Requirements'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _buyers.length,
                    itemBuilder: (context, i) {
                      final buyer = _buyers[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(buyer.name),
                          subtitle: Text(buyer.gstin),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _BuyerRequirementsDetailScreen(
                                  buyer: buyer, dio: _dio),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _BuyerRequirementsDetailScreen extends StatefulWidget {
  final Buyer buyer;
  final dynamic dio;
  const _BuyerRequirementsDetailScreen(
      {required this.buyer, required this.dio});

  @override
  State<_BuyerRequirementsDetailScreen> createState() =>
      _BuyerRequirementsDetailScreenState();
}

class _BuyerRequirementsDetailScreenState
    extends State<_BuyerRequirementsDetailScreen> {
  List<BuyerRequirement> _requirements = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await widget.dio
          .get(Endpoints.buyerRequirementsById(widget.buyer.id));
      final data =
          BuyerWithRequirements.fromJson(resp.data as Map<String, dynamic>);
      setState(() {
        _requirements = data.requirements;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load requirements: $e';
        _loading = false;
      });
    }
  }

  void _showAddDialog() {
    final docTypeCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final sortOrderCtrl = TextEditingController(text: '0');
    bool isBuyerGenerated = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Document Requirement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: docTypeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Document Type',
                    hintText: 'e.g. GATE_ENTRY_NOTE',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    hintText: 'e.g. Gate Entry / Discrepancy Note',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sortOrderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sort Order'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Buyer-generated'),
                  subtitle:
                      const Text('Worker must collect this from the buyer'),
                  value: isBuyerGenerated,
                  onChanged: (v) => setDialogState(() => isBuyerGenerated = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (docTypeCtrl.text.trim().isEmpty ||
                    labelCtrl.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await widget.dio.post(
                    Endpoints.buyerRequirementsById(widget.buyer.id),
                    data: {
                      'document_type': docTypeCtrl.text.trim(),
                      'label': labelCtrl.text.trim(),
                      'is_buyer_generated': isBuyerGenerated,
                      'sort_order': int.tryParse(sortOrderCtrl.text) ?? 0,
                    },
                  );
                  _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Failed: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuyerRequirement r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${r.label}"?'),
        content: const Text(
            'Workers will no longer be asked to photograph this document for this buyer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.dio.delete(Endpoints.buyerRequirementDelete(
          widget.buyer.id, r.documentType));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.buyer.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _requirements.isEmpty
                  ? const Center(
                      child: Text('No document requirements configured yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _requirements.length,
                      itemBuilder: (context, i) {
                        final r = _requirements[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            title: Text(r.label),
                            subtitle: Text(r.documentType +
                                (r.isBuyerGenerated ? ' • Buyer-generated' : '')),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete requirement',
                              onPressed: () => _confirmDelete(r),
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
