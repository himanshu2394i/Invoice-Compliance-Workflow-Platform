import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/navigation/app_back.dart';

class TenantRule {
  final String id;
  final String field;
  final String operator;
  final double value;
  final String action;

  const TenantRule({
    required this.id,
    required this.field,
    required this.operator,
    required this.value,
    required this.action,
  });

  factory TenantRule.fromJson(Map<String, dynamic> j) => TenantRule(
        id: j['id'] as String,
        field: j['field'] as String? ?? '',
        operator: j['operator'] as String? ?? '',
        value: (j['value'] as num? ?? 0).toDouble(),
        action: j['action'] as String? ?? '',
      );
}

/// Admin screen for the matching rules that decide when an invoice needs
/// manager/finance approval. An empty list means the tenant is on the
/// backend's default policy (manager approval above 0, finance above 5000)
/// -- adding any rule here replaces that default entirely, no merging.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final _dio = buildDio();
  List<TenantRule> _rules = [];
  bool _loading = true;
  String? _error;

  static const _fields = ['GrossAmount', 'NetAmount', 'TaxAmount'];
  static const _operators = ['>', '<', '==', '>=', '<='];
  static const _actions = [
    'REQUIRE_MANAGER_APPROVAL',
    'REQUIRE_FINANCE_APPROVAL'
  ];

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
      final resp = await _dio.get(Endpoints.rules);
      final list = (resp.data['rules'] as List? ?? [])
          .map((r) => TenantRule.fromJson(r as Map<String, dynamic>))
          .toList();
      setState(() {
        _rules = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load rules: $e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteRule(String id) async {
    try {
      await _dio.delete(Endpoints.rule(id));
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

  void _showAddDialog() {
    String field = _fields.first;
    String operator = _operators.first;
    String action = _actions.first;
    final valueCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Rule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: field,
                  decoration: const InputDecoration(labelText: 'Field'),
                  items: _fields
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => field = v!),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: operator,
                  decoration: const InputDecoration(labelText: 'Operator'),
                  items: _operators
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => operator = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: valueCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Value (₹)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: action,
                  decoration: const InputDecoration(labelText: 'Action'),
                  items: _actions
                      .map((a) => DropdownMenuItem(
                          value: a, child: Text(a.replaceAll('_', ' '))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => action = v!),
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
                final value = double.tryParse(valueCtrl.text);
                if (value == null) return;
                Navigator.pop(ctx);
                try {
                  await _dio.post(Endpoints.rules, data: {
                    'field': field,
                    'operator': operator,
                    'value': value,
                    'action': action,
                  });
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
          title: const Text('Approval Rules'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : Column(
                    children: [
                      if (_rules.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No custom rules — using the default policy '
                            '(manager approval above ₹0, finance approval above ₹5,000).',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _rules.length,
                          itemBuilder: (context, i) {
                            final r = _rules[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                title: Text(
                                    '${r.field} ${r.operator} ₹${r.value.toStringAsFixed(2)}'),
                                subtitle: Text(r.action.replaceAll('_', ' ')),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _deleteRule(r.id),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddDialog,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
