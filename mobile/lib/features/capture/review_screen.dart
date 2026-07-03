import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/buyer_requirement.dart';
import '../../core/models/master_data.dart';
import 'bundle_provider.dart';
import 'camera_screen.dart'; // CameraTarget
import 'series_detect.dart';

final reviewDioProvider = Provider<Dio>((ref) => buildDio());
final ocrPreviewProvider = Provider<Future<InvoiceOCRPreview> Function(String)>(
  (ref) {
    final dio = ref.watch(reviewDioProvider);
    return (path) => fetchInvoiceOCRPreview(dio, path);
  },
);

const ocrFilledHelperText = 'Filled by OCR - verify';

String? ocrFieldHelperText(Set<String> ocrFilledFields, String fieldKey) {
  return ocrFilledFields.contains(fieldKey) ? ocrFilledHelperText : null;
}

class InvoiceOCRPreview {
  final bool ocrAvailable;
  final String? invoiceNumber;
  final String? sellerGstin;
  final String? buyerGstin;
  final double? taxableAmount;
  final double? grossAmount;

  const InvoiceOCRPreview({
    required this.ocrAvailable,
    this.invoiceNumber,
    this.sellerGstin,
    this.buyerGstin,
    this.taxableAmount,
    this.grossAmount,
  });

  factory InvoiceOCRPreview.fromJson(Map<String, dynamic> json) =>
      InvoiceOCRPreview(
        ocrAvailable: json['ocr_available'] == true,
        invoiceNumber: json['invoice_number'] as String?,
        sellerGstin: json['seller_gstin'] as String?,
        buyerGstin: json['buyer_gstin'] as String?,
        taxableAmount: (json['taxable_amount'] as num?)?.toDouble(),
        grossAmount: (json['gross_amount'] as num?)?.toDouble(),
  );
}

class InvoiceDuplicateCheck {
  final bool duplicate;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? buyerName;
  final String? invoiceDate;
  final double? totalAmount;
  final String? status;

  const InvoiceDuplicateCheck({
    required this.duplicate,
    this.invoiceId,
    this.invoiceNumber,
    this.buyerName,
    this.invoiceDate,
    this.totalAmount,
    this.status,
  });

  factory InvoiceDuplicateCheck.fromJson(Map<String, dynamic> json) =>
      InvoiceDuplicateCheck(
        duplicate: json['duplicate'] == true,
        invoiceId: json['invoice_id'] as String?,
        invoiceNumber: json['invoice_number'] as String?,
        buyerName: json['buyer_name'] as String?,
        invoiceDate: json['invoice_date'] as String?,
        totalAmount: (json['total_amount'] as num?)?.toDouble(),
        status: json['status'] as String?,
      );
}

Future<InvoiceOCRPreview> fetchInvoiceOCRPreview(Dio dio, String path) async {
  final resp = await dio.post(
    Endpoints.invoiceOcrPreview,
    data: FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
        filename: 'invoice-preview.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    }),
  );
  return InvoiceOCRPreview.fromJson(resp.data as Map<String, dynamic>? ?? {});
}

Future<InvoiceDuplicateCheck> fetchInvoiceDuplicateCheck(
  Dio dio, {
  required String invoiceNumber,
  required String sellerGstin,
  required String buyerGstin,
}) async {
  final resp = await dio.get(
    Endpoints.invoiceDuplicateCheck(
      invoiceNumber: invoiceNumber,
      sellerGstin: sellerGstin,
      buyerGstin: buyerGstin,
    ),
  );
  return InvoiceDuplicateCheck.fromJson(
    resp.data as Map<String, dynamic>? ?? {},
  );
}

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
  bool _lookingUpOcr = false;
  bool _checkingDuplicate = false;
  bool _ocrAttempted = false;
  String? _ocrStatus;
  String? _ocrWarning;
  Set<String> _ocrFilledFields = {};
  List<Buyer> _buyers = [];

  // Distributor-domain capture fields
  final _termsCtrl = TextEditingController();
  String _paymentType = 'CASH'; // what's printed on the invoice: CASH | CREDIT
  List<SeriesEntry> _seriesRegistry = [];
  SeriesEntry? _detectedSeries;
  List<BuyerBranch> _buyerBranches = [];
  String? _selectedBranchId;

  @override
  void initState() {
    super.initState();
    _hydrateFromSession();
    _loadBuyers();
    _loadSeriesRegistry();
    _invNumCtrl.addListener(_detectSeriesFromNumber);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_buyerGstinCtrl.text.trim().length == 15) {
        _lookupBuyer();
      }
      _runOCRPreviewIfPossible();
    });
  }

  void _hydrateFromSession() {
    final session = ref.read(bundleProvider);
    final today = DateTime.now();
    final todayText =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    _invNumCtrl.text = session.invoiceNumber;
    _buyerGstinCtrl.text = session.buyerGstin;
    _buyerNameCtrl.text = session.buyerName;
    _invDateCtrl.text =
        session.invoiceDate.trim().isEmpty ? todayText : session.invoiceDate;
    _taxableCtrl.text = session.taxableAmount == 0
        ? ''
        : session.taxableAmount.toStringAsFixed(2);
    _totalCtrl.text =
        session.totalAmount == 0 ? '' : session.totalAmount.toStringAsFixed(2);
    if (_entities.any((e) => e.$2 == session.entityGstin)) {
      _entityGstin = session.entityGstin;
    }
    if (session.paymentType == 'CASH' || session.paymentType == 'CREDIT') {
      _paymentType = session.paymentType;
    }
    if (session.paymentTermsDays != null) {
      _termsCtrl.text = session.paymentTermsDays.toString();
    }
    _selectedBranchId = session.buyerBranchId;
  }

  Future<void> _loadSeriesRegistry() async {
    try {
      final dio = ref.read(reviewDioProvider);
      final resp = await dio.get(Endpoints.seriesRegistry);
      final list = ((resp.data['series'] as List?) ?? const [])
          .map((j) => SeriesEntry.fromJson(j as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() => _seriesRegistry = list);
        _detectSeriesFromNumber();
      }
    } catch (_) {
      // Non-fatal: series detection simply stays off while offline.
    }
  }

  void _detectSeriesFromNumber() {
    final hit = detectSeries(_invNumCtrl.text, _seriesRegistry);
    if (hit?.id != _detectedSeries?.id && mounted) {
      setState(() => _detectedSeries = hit);
    }
  }

  Future<void> _loadBuyerBranches(String buyerId) async {
    try {
      final dio = ref.read(reviewDioProvider);
      final resp = await dio.get(Endpoints.buyerBranches(buyerId));
      final list = ((resp.data['branches'] as List?) ?? const [])
          .map((j) => BuyerBranch.fromJson(j as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _buyerBranches = list;
          _selectedBranchId = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _buyerBranches = [];
          _selectedBranchId = null;
        });
      }
    }
  }

  Future<void> _loadBuyers() async {
    try {
      final dio = ref.read(reviewDioProvider);
      final resp = await dio.get(Endpoints.buyers);
      final list = (resp.data['buyers'] as List? ?? [])
          .map((b) => Buyer.fromJson(b as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() => _buyers = list);
        final sessionBuyerGstin = ref.read(bundleProvider).buyerGstin;
        final match = list
            .where((b) => b.gstin.toUpperCase() == sessionBuyerGstin.toUpperCase())
            .toList();
        if (match.isNotEmpty) {
          _loadBuyerBranches(match.first.id);
        }
      }
    } catch (_) {
      // Non-fatal: worker can still type the GSTIN manually below
    }
  }

  void _selectBuyer(Buyer buyer) {
    _buyerGstinCtrl.text = buyer.gstin;
    _buyerNameCtrl.text = buyer.name;
    // Prefill credit terms from the buyer's default; branches drive the
    // delivery-location picker below.
    if (buyer.defaultPaymentTermsDays != null && _termsCtrl.text.isEmpty) {
      _termsCtrl.text = buyer.defaultPaymentTermsDays.toString();
    }
    _loadBuyerBranches(buyer.id);
    _persistDraftFields();
    _lookupBuyer();
  }

  Future<void> _runOCRPreviewIfPossible() async {
    if (_ocrAttempted || !mounted) return;
    final pagePaths = ref.read(bundleProvider).invoicePhotoPaths;
    if (pagePaths.isEmpty) return;
    _ocrAttempted = true;
    if (!File(pagePaths.first).existsSync()) return;
    setState(() {
      _lookingUpOcr = true;
      _ocrStatus = 'Reading invoice photo...';
      _ocrWarning = null;
      _ocrFilledFields = {};
    });
    try {
      final data = await ref.read(ocrPreviewProvider)(pagePaths.first);
      if (!data.ocrAvailable) {
        if (mounted) {
          setState(() {
            _ocrStatus = null;
            _ocrWarning = null;
            _ocrFilledFields = {};
          });
        }
        return;
      }

      final filled = <String>[];
      final filledFields = <String>{};
      void fillIfEmpty(
        TextEditingController ctrl,
        Object? value,
        String fieldKey,
        String label,
      ) {
        final text = value?.toString().trim() ?? '';
        if (text.isEmpty || ctrl.text.trim().isNotEmpty) return;
        ctrl.text = text;
        filled.add(label);
        filledFields.add(fieldKey);
      }

      fillIfEmpty(
        _invNumCtrl,
        data.invoiceNumber,
        'invoice_number',
        'invoice number',
      );
      final sellerGSTIN = data.sellerGstin?.trim();
      if (sellerGSTIN != null && sellerGSTIN.isNotEmpty) {
        final match = _entities.where((e) => e.$2 == sellerGSTIN).toList();
        if (match.isNotEmpty) _entityGstin = match.first.$2;
      }
      final extractedBuyerGSTIN = data.buyerGstin?.trim();
      final existingBuyerGSTIN = _buyerGstinCtrl.text.trim();
      if (extractedBuyerGSTIN != null && extractedBuyerGSTIN.isNotEmpty) {
        if (existingBuyerGSTIN.isEmpty) {
          _buyerGstinCtrl.text = extractedBuyerGSTIN.toUpperCase();
          filled.add('buyer GSTIN');
          filledFields.add('buyer_gstin');
          await _lookupBuyer();
        } else if (existingBuyerGSTIN.toUpperCase() !=
            extractedBuyerGSTIN.toUpperCase()) {
          _ocrWarning = 'Buyer GSTIN from photo differs. Check the invoice.';
        }
      }
      if (_taxableCtrl.text.trim().isEmpty && data.taxableAmount != null) {
        _taxableCtrl.text = data.taxableAmount!.toStringAsFixed(2);
        filled.add('taxable amount');
        filledFields.add('taxable_amount');
      }
      if (_totalCtrl.text.trim().isEmpty && data.grossAmount != null) {
        _totalCtrl.text = data.grossAmount!.toStringAsFixed(2);
        filled.add('total amount');
        filledFields.add('gross_amount');
      }
      if (mounted) {
        setState(() {
          _ocrStatus = filled.isEmpty
              ? null
              : 'OCR filled ${filled.join(', ')}. Verify before continuing.';
          _ocrFilledFields = filledFields;
        });
        _persistDraftFields();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ocrStatus = null;
          _ocrWarning = null;
          _ocrFilledFields = {};
        });
      }
    } finally {
      if (mounted) setState(() => _lookingUpOcr = false);
    }
  }

  @override
  void dispose() {
    _invNumCtrl.removeListener(_detectSeriesFromNumber);
    _invNumCtrl.dispose();
    _buyerGstinCtrl.dispose();
    _buyerNameCtrl.dispose();
    _invDateCtrl.dispose();
    _taxableCtrl.dispose();
    _totalCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupBuyer() async {
    final gstin = _buyerGstinCtrl.text.trim();
    if (gstin.length != 15) return;
    setState(() => _lookingUpBuyer = true);
    try {
      final dio = ref.read(reviewDioProvider);
      final resp = await dio.get(Endpoints.buyerRequirementsByGstin(gstin));
      final data =
          BuyerWithRequirements.fromJson(resp.data as Map<String, dynamic>);
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

  void _persistDraftFields() {
    final terms = int.tryParse(_termsCtrl.text.trim());
    ref.read(bundleProvider.notifier).updateInvoiceFields(
          invoiceNumber: _invNumCtrl.text.trim(),
          entityGstin: _entityGstin,
          buyerGstin: _buyerGstinCtrl.text.trim().toUpperCase(),
          buyerName: _buyerNameCtrl.text.trim(),
          invoiceDate: _invDateCtrl.text.trim(),
          taxableAmount: double.tryParse(_taxableCtrl.text) ?? 0,
          totalAmount: double.tryParse(_totalCtrl.text) ?? 0,
          paymentType: _paymentType,
          paymentTermsDays: _paymentType == 'CREDIT' ? terms : null,
          clearPaymentTerms: _paymentType != 'CREDIT' || terms == null,
          buyerBranchId: _selectedBranchId,
          clearBuyerBranch: _selectedBranchId == null,
        );
  }

  Future<bool> _confirmDuplicateInvoice(InvoiceDuplicateCheck duplicate) async {
    final details = <String>[
      if (duplicate.buyerName != null && duplicate.buyerName!.isNotEmpty)
        duplicate.buyerName!,
      if (duplicate.invoiceDate != null && duplicate.invoiceDate!.isNotEmpty)
        duplicate.invoiceDate!,
      if (duplicate.totalAmount != null)
        'Rs ${duplicate.totalAmount!.toStringAsFixed(2)}',
      if (duplicate.status != null && duplicate.status!.isNotEmpty)
        duplicate.status!,
    ];
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Possible duplicate invoice'),
            content: Text(
              [
                'This invoice number already exists. Continue only if this is a correction or extra document.',
                if (details.isNotEmpty) details.join(' • '),
              ].join('\n\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Go Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _proceed() async {
    if (!_formKey.currentState!.validate()) return;
    if (ref.read(bundleProvider).invoicePhotoPaths.isEmpty) return;
    _persistDraftFields();
    setState(() => _checkingDuplicate = true);
    var shouldContinue = true;
    InvoiceDuplicateCheck? duplicate;
    try {
      duplicate = await fetchInvoiceDuplicateCheck(
        ref.read(reviewDioProvider),
        invoiceNumber: _invNumCtrl.text.trim(),
        sellerGstin: _entityGstin,
        buyerGstin: _buyerGstinCtrl.text.trim().toUpperCase(),
      );
    } catch (_) {
      shouldContinue = true;
    } finally {
      if (mounted) setState(() => _checkingDuplicate = false);
    }
    if (duplicate != null && duplicate.duplicate && mounted) {
      shouldContinue = await _confirmDuplicateInvoice(duplicate);
    }
    if (!mounted || !shouldContinue) return;
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
    String? ocrFieldKey,
  }) {
    final helperText = ocrFieldKey == null
        ? null
        : ocrFieldHelperText(_ocrFilledFields, ocrFieldKey);
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
        helperText: helperText,
        helperStyle: TextStyle(
          color: Colors.blueGrey.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
      keyboardType: keyboardType,
      onEditingComplete: onEditingComplete,
      onChanged: (_) {
        if (ocrFieldKey != null && _ocrFilledFields.contains(ocrFieldKey)) {
          setState(() {
            _ocrFilledFields = {..._ocrFilledFields}..remove(ocrFieldKey);
          });
        }
        _persistDraftFields();
      },
      validator:
          validator ?? (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(bundleProvider);
    final pagePaths = session.invoicePhotoPaths;

    return BackButtonListener(
      onBackButtonPressed: () async {
        context.go('/capture/camera');
        return true;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          context.go('/capture/camera');
        },
        child: Scaffold(
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
                    // Invoice photo pages — tap a page to retake it, "+" to add another
                    Text(
                      pagePaths.length > 1
                          ? 'Invoice pages (${pagePaths.length})'
                          : 'Invoice photo',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < pagePaths.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () => context.go(
                                      '/capture/camera',
                                      extra: CameraTarget(
                                        documentType: 'INVOICE',
                                        label: 'Tax Invoice (page ${i + 1})',
                                        isPrimary: true,
                                        replaceIndex: i,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(pagePaths[i]),
                                        width: 90,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('Page ${i + 1}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11)),
                                    ),
                                  ),
                                  if (pagePaths.length > 1)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: GestureDetector(
                                        onTap: () => ref
                                            .read(bundleProvider.notifier)
                                            .removeInvoicePage(i),
                                        child: const CircleAvatar(
                                          radius: 11,
                                          backgroundColor: Colors.black54,
                                          child: Icon(Icons.close,
                                              size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          // "Add page" tile — for invoices that span 2-3 pages
                          GestureDetector(
                            onTap: () => context.go(
                              '/capture/camera',
                              extra: const CameraTarget(
                                documentType: 'INVOICE',
                                label: 'Tax Invoice',
                                isPrimary: true,
                              ),
                            ),
                            child: Container(
                              width: 90,
                              height: 120,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[400]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo, color: Colors.grey),
                                  SizedBox(height: 4),
                                  Text('Add page',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_lookingUpOcr ||
                        _ocrStatus != null ||
                        _ocrWarning != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _ocrWarning != null
                              ? Colors.orange.withValues(alpha: 0.10)
                              : Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _ocrWarning != null
                                ? Colors.orange
                                : Colors.blueGrey.shade100,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_lookingUpOcr)
                              const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              Icon(
                                _ocrWarning != null
                                    ? Icons.warning_amber
                                    : Icons.document_scanner_outlined,
                                size: 20,
                                color: _ocrWarning != null
                                    ? Colors.orange
                                    : Colors.blueGrey,
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _ocrWarning ?? _ocrStatus ?? '',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

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
                      onChanged: (v) {
                        setState(() => _entityGstin = v!);
                        _persistDraftFields();
                      },
                    ),
                    const SizedBox(height: 12),

                    _field(
                      ctrl: _invNumCtrl,
                      label: 'Invoice Number',
                      hint: 'A26/001',
                      ocrFieldKey: 'invoice_number',
                    ),
                    if (_detectedSeries != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                            avatar: const Icon(Icons.auto_awesome, size: 16),
                            label: Text(
                              [
                                _detectedSeries!.seriesPrefix,
                                if (_detectedSeries!.principalName != null)
                                  _detectedSeries!.principalName!,
                                if (_detectedSeries!.entityName != null)
                                  _detectedSeries!.entityName!,
                              ].join(' • '),
                              style: const TextStyle(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Search buyer by name — picks from the known buyer list and
                    // auto-fills GSTIN + name below (which stay editable as a fallback
                    // for a buyer not yet in the system).
                    Autocomplete<Buyer>(
                      optionsBuilder: (textEditingValue) {
                        final q = textEditingValue.text.toLowerCase();
                        if (q.isEmpty) return _buyers;
                        return _buyers.where((b) =>
                            b.name.toLowerCase().contains(q) ||
                            b.gstin.toLowerCase().contains(q));
                      },
                      displayStringForOption: (b) => b.name,
                      onSelected: _selectBuyer,
                      fieldViewBuilder:
                          (context, controller, focusNode, onSubmitted) =>
                              TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Search Buyer',
                          hintText: 'Start typing buyer name…',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: _lookupBuyer,
                              tooltip: 'Look up buyer',
                            ),
                      onEditingComplete: _lookupBuyer,
                      ocrFieldKey: 'buyer_gstin',
                      validator: (v) {
                        final value = (v ?? '').trim().toUpperCase();
                        if (value.isEmpty) return 'Required';
                        if (value.length != 15) {
                          return 'GSTIN must be 15 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    _field(
                        ctrl: _buyerNameCtrl,
                        label: 'Buyer Name',
                        hint: 'Vishal Mega Mart'),
                    const SizedBox(height: 12),

                    // Delivery branch — only when the buyer has branches
                    // (Vishal stores, Flipkart/Zepto warehouses).
                    if (_buyerBranches.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _selectedBranchId,
                        decoration: const InputDecoration(
                          labelText: 'Delivery branch / store (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Not specified'),
                          ),
                          for (final b in _buyerBranches)
                            DropdownMenuItem(
                              value: b.id,
                              child: Text(b.code == null
                                  ? b.name
                                  : '${b.name} (${b.code})'),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedBranchId = v);
                          _persistDraftFields();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Payment type as printed on the invoice; CREDIT gets
                    // terms (prefilled from the buyer's default).
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: 'CASH', label: Text('Cash')),
                              ButtonSegment(
                                  value: 'CREDIT', label: Text('Credit')),
                            ],
                            selected: {_paymentType},
                            onSelectionChanged: (s) {
                              setState(() => _paymentType = s.first);
                              _persistDraftFields();
                            },
                            showSelectedIcon: false,
                          ),
                        ),
                        if (_paymentType == 'CREDIT') ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _termsCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Terms (days)',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => _persistDraftFields(),
                              validator: (v) {
                                if (_paymentType != 'CREDIT') return null;
                                if (v == null || v.trim().isEmpty) {
                                  return null; // buyer default applies
                                }
                                final days = int.tryParse(v.trim());
                                if (days == null || days < 0) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
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
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            ocrFieldKey: 'taxable_amount',
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              final taxable = double.tryParse(v);
                              if (taxable == null) return 'Must be a number';
                              final total = double.tryParse(_totalCtrl.text);
                              if (total != null && total < taxable) {
                                return 'Cannot exceed total';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            ctrl: _totalCtrl,
                            label: 'Total Amount (₹)',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            ocrFieldKey: 'gross_amount',
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              final total = double.tryParse(v);
                              if (total == null) return 'Must be a number';
                              final taxable =
                                  double.tryParse(_taxableCtrl.text);
                              if (taxable != null && total < taxable) {
                                return 'Must be at least taxable';
                              }
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
                        onPressed: _checkingDuplicate ? null : _proceed,
                        icon: _checkingDuplicate
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_forward),
                        label: Text(_checkingDuplicate
                            ? 'Checking invoice...'
                            : 'Next — Supporting Docs'),
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
        ),
      ),
    );
  }
}
