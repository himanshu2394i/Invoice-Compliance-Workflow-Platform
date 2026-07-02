import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

/// Lets a worker see what happened to an invoice after they synced it --
/// the local queue only tracks upload status, not the backend's approval/
/// dispute state. Uses the plain (non-owner) /invoices endpoint since WORKER
/// isn't allowed on /owner/* routes.
class MyInvoicesScreen extends StatefulWidget {
  const MyInvoicesScreen({super.key});

  @override
  State<MyInvoicesScreen> createState() => _MyInvoicesScreenState();
}

class _SimpleInvoice {
  final String id;
  final String invoiceNumber;
  final String invoiceDate;
  final double grossAmount;
  final String currentState;

  _SimpleInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.grossAmount,
    required this.currentState,
  });

  factory _SimpleInvoice.fromJson(Map<String, dynamic> j) => _SimpleInvoice(
        id: j['id'] as String,
        invoiceNumber: j['invoice_number'] as String? ?? '',
        invoiceDate: j['invoice_date'] as String? ?? '',
        grossAmount: (j['gross_amount'] as num? ?? 0).toDouble(),
        currentState: j['current_state'] as String? ?? '',
      );
}

class _MyInvoicesScreenState extends State<MyInvoicesScreen> {
  final _dio = buildDio();
  List<_SimpleInvoice> _invoices = [];
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
      final resp =
          await _dio.get(Endpoints.invoices, queryParameters: {'limit': 50});
      final list = (resp.data['invoices'] as List? ?? [])
          .map((i) => _SimpleInvoice.fromJson(i as Map<String, dynamic>))
          .toList();
      setState(() {
        _invoices = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load invoices: $e';
        _loading = false;
      });
    }
  }

  Color _stateColor(String state) => switch (state) {
        'INGESTED' || 'PENDING_MANAGER_APPROVAL' => Colors.blue,
        'APPROVED' => Colors.green,
        'REJECTED' => Colors.red,
        _ => Colors.grey,
      };

  String _stateLabel(String state) => state.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    // Tab root inside the worker shell: no back affordance, the shell
    // handles it.
    return Scaffold(
        appBar: AppBar(
          title: const Text('My Invoices'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _invoices.isEmpty
                    ? const Center(child: Text('No invoices submitted yet.'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _invoices.length,
                          itemBuilder: (context, i) {
                            final inv = _invoices[i];
                            final color = _stateColor(inv.currentState);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(inv.invoiceNumber),
                                subtitle: Text(
                                  '${inv.invoiceDate.length >= 10 ? inv.invoiceDate.substring(0, 10) : inv.invoiceDate}  •  ₹${inv.grossAmount.toStringAsFixed(2)}',
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: color),
                                  ),
                                  child: Text(
                                    _stateLabel(inv.currentState),
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
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
