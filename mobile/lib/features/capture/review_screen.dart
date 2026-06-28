import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/buyer_requirement.dart';
import 'bundle_provider.dart';
import 'camera_screen.dart'; // CameraTarget

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _invNumCtrl = TextEditingController();
  final _buyerGstinCtrl = TextEditingController();
  final _buyerNameCtrl = TextEditingController();
  final _invDateCtrl = TextEditingController();
  final _taxableCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();

  // Seller entity GSTIN — three entities; worker picks from dropdown
  static const _entities = [
    ('Meridian Brothers', '06AAAAA0003A1Z3'),
    ('Meridian Distributors', '06AAAAA0015A1ZF'),
    ('Meridian Gurgaon', '06AAAAA0017A1ZH'),
  ];
  String _entityGstin = _entities.first.$2;

  bool _lookingUpBuyer = false;

  @override
  void dispose() {
    _invNumCtrl.dispose();
    _buyerGstinCtrl.dispose();
    _buyerNameCtrl.dispose();
    _invDateCtrl.dispose();
    _taxableCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupBuyer() async {
    final gstin = _buyerGstinCtrl.text.trim();
    if (gstin.length != 15) return;
    setState(() => _lookingUpBuyer = true);
    try {
      final dio = buildDio();
      final resp = await dio.get(Endpoints.buyerRequirementsByGstin(gstin));
      final data = BuyerWithRequirements.fromJson(resp.data as Map<String, dynamic>);
      if (data.buyer != null) {
        _buyerNameCtrl.text = data.buyer!['name'] as String? ?? '';
      }
      ref.read(bundleProvider.notifier).setRequiredDocs(data.requirements);
    } catch (_) {
      // Non-fatal: worker can fill in the name manually
    } finally {
      if (mounted) setState(() => _lookingUpBuyer = false);
    }
  }

  void _proceed() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(bundleProvider.notifier).updateInvoiceFields(
          invoiceNumber: _invNumCtrl.text.trim(),
          entityGstin: _entityGstin,
          buyerGstin: _buyerGstinCtrl.text.trim(),
          buyerName: _buyerNameCtrl.text.trim(),
          invoiceDate: _invDateCtrl.text.trim(),
          taxableAmount: double.tryParse(_taxableCtrl.text) ?? 0,
          totalAmount: double.tryParse(_totalCtrl.text) ?? 0,
        );
    context.go('/capture/checklist');
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    Widget? suffix,
    String? Function(String?)? validator,
    VoidCallback? onEditingComplete,
  }) =>
      TextFormField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: suffix,
        ),
        keyboardType: keyboardType,
        onEditingComplete: onEditingComplete,
        validator: validator ?? (v) => (v == null || v.isEmpty) ? 'Required' : null,
      );

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(bundleProvider);
    final photoPath = session.invoicePhotoPath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Invoice'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/capture/camera'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Invoice photo thumbnail
                if (photoPath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(photoPath),
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => context.go(
                    '/capture/camera',
                    extra: const CameraTarget(
                      documentType: 'INVOICE',
                      label: 'Tax Invoice',
                      isPrimary: true,
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Retake photo'),
                ),
                const SizedBox(height: 16),

                // Seller entity
                DropdownButtonFormField<String>(
                  value: _entityGstin,
                  decoration: const InputDecoration(
                    labelText: 'Seller Entity',
                    border: OutlineInputBorder(),
                  ),
                  items: _entities
                      .map((e) => DropdownMenuItem(
                            value: e.$2,
                            child: Text(e.$1),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _entityGstin = v!),
                ),
                const SizedBox(height: 12),

                _field(ctrl: _invNumCtrl, label: 'Invoice Number', hint: 'A26/001'),
                const SizedBox(height: 12),

                // Buyer GSTIN with auto-lookup
                _field(
                  ctrl: _buyerGstinCtrl,
                  label: 'Buyer GSTIN',
                  hint: '06AAAAA0013A1ZD',
                  suffix: _lookingUpBuyer
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _lookupBuyer,
                          tooltip: 'Look up buyer',
                        ),
                  onEditingComplete: _lookupBuyer,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length != 15) return 'GSTIN must be 15 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                _field(ctrl: _buyerNameCtrl, label: 'Buyer Name', hint: 'Vishal Mega Mart'),
                const SizedBox(height: 12),

                _field(
                  ctrl: _invDateCtrl,
                  label: 'Invoice Date',
                  hint: 'YYYY-MM-DD',
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                    if (!re.hasMatch(v)) return 'Use YYYY-MM-DD format';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _field(
                        ctrl: _taxableCtrl,
                        label: 'Taxable Amount (₹)',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Must be a number';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        ctrl: _totalCtrl,
                        label: 'Total Amount (₹)',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Must be a number';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _proceed,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next — Supporting Docs'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
