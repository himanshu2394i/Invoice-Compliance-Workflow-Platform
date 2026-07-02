import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../owner/owner_provider.dart';
import 'receivables_screen.dart' show formatMoney;

/// Opens the record-payment bottom sheet. Resolves to true when a payment
/// was recorded, so callers know to refresh their receivables providers.
Future<bool?> showRecordPaymentSheet(
  BuildContext context, {
  required String invoiceId,
  required String invoiceNumber,
  required double balance,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(_).viewInsets.bottom),
      child: RecordPaymentSheet(
        invoiceId: invoiceId,
        invoiceNumber: invoiceNumber,
        balance: balance,
      ),
    ),
  );
}

class RecordPaymentSheet extends StatefulWidget {
  final String invoiceId;
  final String invoiceNumber;
  final double balance;

  const RecordPaymentSheet({
    super.key,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.balance,
  });

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final _referenceController = TextEditingController();
  DateTime _paidOn = DateTime.now();
  String _mode = 'UPI';
  bool _saving = false;
  String? _serverError;

  static const modes = ['CASH', 'UPI', 'CHEQUE', 'NEFT', 'OTHER'];

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: widget.balance.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _serverError = null;
    });
    try {
      await ownerService.recordPayment(
        invoiceId: widget.invoiceId,
        amount: double.parse(_amountController.text.trim()),
        mode: _mode,
        paidOn:
            '${_paidOn.year}-${_paidOn.month.toString().padLeft(2, '0')}-${_paidOn.day.toString().padLeft(2, '0')}',
        reference: _referenceController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      setState(() {
        _saving = false;
        _serverError = e.response?.data is Map
            ? (e.response?.data['error']?.toString() ?? e.message)
            : (e.message ?? 'Failed to record payment');
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _serverError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Record payment — ${widget.invoiceNumber}',
                style: Theme.of(context).textTheme.titleMedium),
            Text('Balance: ${formatMoney(widget.balance)}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final amount = double.tryParse(v?.trim() ?? '');
                if (amount == null || amount <= 0) {
                  return 'Enter a positive amount';
                }
                if (amount > widget.balance + 0.005) {
                  return 'Cannot exceed the balance of ${formatMoney(widget.balance)}';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _mode,
                    decoration: const InputDecoration(
                      labelText: 'Mode',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final m in modes)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => setState(() => _mode = v ?? 'UPI'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                        '${_paidOn.day.toString().padLeft(2, '0')}/${_paidOn.month.toString().padLeft(2, '0')}/${_paidOn.year}'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _paidOn,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _paidOn = picked);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Reference (UTR / cheque no., optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_serverError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_serverError!,
                    style: TextStyle(color: Colors.red.shade700)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
  }
}
