import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/navigation/app_back.dart';
import '../auth/auth_provider.dart';
import 'owner_provider.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  final Map<String, bool> _downloading = {};
  final Map<String, String> _downloadedPaths = {};

  // Gate entry input state
  String? _selectedDocId;
  final _gateQtyController = TextEditingController();
  final _invoiceQtyController = TextEditingController();
  final _gateNumberController = TextEditingController();
  final _gateNotesController = TextEditingController();
  bool _isShortReceipt = false;
  bool _savingGateEntry = false;

  @override
  void dispose() {
    _gateQtyController.dispose();
    _invoiceQtyController.dispose();
    _gateNumberController.dispose();
    _gateNotesController.dispose();
    super.dispose();
  }

  Future<void> _viewDoc(String docId, {int? versionNumber}) async {
    var path = _downloadedPaths[docId];
    if (versionNumber != null) path = null;
    if (path == null) {
      setState(() => _downloading[docId] = true);
      try {
        path = await ownerService.downloadDocument(widget.invoiceId, docId,
            versionNumber: versionNumber);
        setState(() {
          if (versionNumber == null) _downloadedPaths[docId] = path!;
          _downloading[docId] = false;
        });
      } catch (e) {
        setState(() => _downloading[docId] = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to load document: $e'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
    }
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => _DocumentViewerScreen(imagePath: path!)),
      );
    }
  }

  Future<void> _showDocumentVersions(InvoiceDocument doc) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => FutureBuilder<List<DocumentVersion>>(
        future: ownerService.listDocumentVersions(doc.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final versions = snapshot.data ?? [];
          if (versions.isEmpty) {
            return const SizedBox(
              height: 160,
              child: Center(child: Text('No version history')),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemBuilder: (context, i) {
              final version = versions[i];
              final uploadedAt = version.createdAt.length >= 16
                  ? version.createdAt.substring(0, 16).replaceFirst('T', ' ')
                  : version.createdAt;
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text('Version ${version.versionNumber}'),
                subtitle: Text(uploadedAt),
                trailing: const Icon(Icons.visibility_outlined),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _viewDoc(doc.id, versionNumber: version.versionNumber);
                },
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: versions.length,
          );
        },
      ),
    );
  }

  bool _resolvingException = false;

  Future<void> _resolveException(String exceptionId, String status) async {
    setState(() => _resolvingException = true);
    try {
      await ownerService.resolveException(exceptionId, status);
      ref.invalidate(ownerInvoiceDetailProvider(widget.invoiceId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _resolvingException = false);
    }
  }

  bool _approving = false;

  Future<void> _approveInvoice(bool approved) async {
    final commentsCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approved ? 'Approve Invoice' : 'Reject Invoice'),
        content: TextField(
          controller: commentsCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
              labelText: 'Comments (optional)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(approved ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _approving = true);
    try {
      await ownerService.approveInvoice(widget.invoiceId,
          approved: approved, comments: commentsCtrl.text.trim());
      ref.invalidate(ownerInvoiceDetailProvider(widget.invoiceId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(approved ? 'Invoice approved.' : 'Invoice rejected.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _saveGateEntry() async {
    if (_selectedDocId == null) return;
    setState(() => _savingGateEntry = true);
    try {
      await ownerService.setGateEntry(
        invoiceId: widget.invoiceId,
        documentId: _selectedDocId!,
        gateEntryNumber: _gateNumberController.text.trim(),
        acceptedQty: double.tryParse(_gateQtyController.text),
        invoiceQty: double.tryParse(_invoiceQtyController.text),
        isShortReceipt: _isShortReceipt,
        notes: _gateNotesController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gate entry saved.')),
        );
        setState(() => _selectedDocId = null);
        ref.invalidate(ownerInvoiceDetailProvider(widget.invoiceId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingGateEntry = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(ownerInvoiceDetailProvider(widget.invoiceId));

    return AppBackScope(
      fallbackLocation: '/owner/invoices',
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => AppBackScope.goBack(
              context,
              fallbackLocation: '/owner/invoices',
            ),
          ),
          title: detailAsync.when(
            data: (d) => Text(d.invoice.invoiceNumber),
            loading: () => const Text('Invoice'),
            error: (_, __) => const Text('Invoice'),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.history_edu_outlined),
              tooltip: 'Audit trail',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        _AuditTrailScreen(invoiceId: widget.invoiceId)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  ref.invalidate(ownerInvoiceDetailProvider(widget.invoiceId)),
            ),
          ],
        ),
        body: detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (detail) => _buildBody(context, detail),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, InvoiceDetail detail) {
    final inv = detail.invoice;
    final groups = detail.documentGroups;
    final role = ref.watch(currentUserProvider)?['role'];
    final canApprove =
        (role == 'MANAGER' || role == 'FINANCE' || role == 'ADMIN') &&
            inv.currentState.startsWith('PENDING');
    final canViewDocumentHistory = role == 'ADMIN' || role == 'MANAGER';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Invoice summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(inv.invoiceNumber,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    _StatusChip(inv.currentState, label: inv.statusLabel),
                  ],
                ),
                const SizedBox(height: 8),
                _InfoRow('Buyer', inv.buyerName ?? '—'),
                _InfoRow('Seller', inv.entityName ?? '—'),
                _InfoRow('Date', inv.invoiceDate.substring(0, 10)),
                _InfoRow('Gross', '₹${inv.grossAmount.toStringAsFixed(2)}'),
                _InfoRow('Tax', '₹${inv.taxAmount.toStringAsFixed(2)}'),
                if (inv.paymentType != null)
                  _InfoRow(
                      'Payment',
                      inv.dueDate == null
                          ? inv.paymentType!
                          : '${inv.paymentType} — due ${inv.dueDate!.substring(0, 10)}'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Payments + balance — only meaningful for CREDIT invoices.
        if (inv.paymentType == 'CREDIT') ...[
          _PaymentsSection(
            invoiceId: widget.invoiceId,
            billTotal: inv.grossAmount,
            hasOpenShortReceipt: detail.disputes.any((d) =>
                d.disputeType == 'SHORT_RECEIPT' &&
                (d.status == 'OPEN' || d.status == 'OWNER_REVIEWING')),
          ),
          const SizedBox(height: 16),
        ],

        if (canApprove) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _approving ? null : () => _approveInvoice(false),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _approving ? null : () => _approveInvoice(true),
                  child: _approving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Approve'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Disputes section
        if (detail.disputes.isNotEmpty) ...[
          _SectionHeader('Disputes (${detail.disputes.length})', Icons.gavel),
          ...detail.disputes.map((d) => _DisputeCard(
                dispute: d,
                invoiceId: widget.invoiceId,
                onUpdate: () => ref
                    .invalidate(ownerInvoiceDetailProvider(widget.invoiceId)),
              )),
          const SizedBox(height: 16),
        ],

        // Exceptions section
        if (detail.exceptions.isNotEmpty) ...[
          _SectionHeader(
              'Exceptions (${detail.exceptions.length})', Icons.warning_amber),
          ...detail.exceptions.map((e) => Card(
                color: e.status == 'open' ? Colors.orange[50] : null,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        e.status == 'open'
                            ? Icons.warning_amber
                            : Icons.check_circle,
                        color:
                            e.status == 'open' ? Colors.orange : Colors.green,
                      ),
                      title: Text(e.exceptionType.replaceAll('_', ' ')),
                      subtitle: Text(e.status),
                    ),
                    if (e.status == 'open')
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _resolvingException
                                  ? null
                                  : () =>
                                      _resolveException(e.id, 'not_applicable'),
                              child: const Text('Not Applicable'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: _resolvingException
                                  ? null
                                  : () => _resolveException(e.id, 'resolved'),
                              child: const Text('Resolve'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              )),
          const SizedBox(height: 16),
        ],

        // Raise new dispute button
        OutlinedButton.icon(
          onPressed: () => _showRaiseDisputeDialog(context, inv.id),
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Raise Dispute / Note Issue'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
        ),

        const SizedBox(height: 24),

        // Documents section
        _SectionHeader('Documents', Icons.folder_open),
        const SizedBox(height: 8),

        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4, top: 8),
            child: Text(
              _docTypeLabel(entry.key),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Colors.grey[700]),
            ),
          ),
          ...entry.value.asMap().entries.map((pageEntry) {
            final pageNum = pageEntry.key + 1;
            final doc = pageEntry.value;
            final isDownloading = _downloading[doc.id] ?? false;
            final savedPath = _downloadedPaths[doc.id];

            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                onTap: isDownloading ? null : () => _viewDoc(doc.id),
                leading: savedPath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(File(savedPath),
                            width: 48, height: 48, fit: BoxFit.cover),
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
                title: Text('Page $pageNum'),
                subtitle: Text(
                  doc.createdAt.length >= 16
                      ? doc.createdAt.substring(0, 16).replaceFirst('T', ' ')
                      : doc.createdAt,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Gate Entry button for Gate Entry Note docs
                    if (entry.key == 'GATE_ENTRY_NOTE')
                      IconButton(
                        icon: const Icon(Icons.edit_note, color: Colors.blue),
                        tooltip: 'Enter gate entry details',
                        onPressed: () {
                          setState(() {
                            _selectedDocId = doc.id;
                            _isShortReceipt = false;
                            _gateQtyController.clear();
                            _invoiceQtyController.clear();
                            _gateNumberController.clear();
                            _gateNotesController.clear();
                          });
                          _showGateEntryDialog(context, doc.id);
                        },
                      ),
                    if (canViewDocumentHistory)
                      IconButton(
                        icon: const Icon(Icons.history, color: Colors.blueGrey),
                        tooltip: 'Version history',
                        onPressed: () => _showDocumentVersions(doc),
                      ),
                    // View button — downloads on first tap if needed, then opens full-screen
                    isDownloading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.visibility_outlined),
                            tooltip: 'View',
                            onPressed: () => _viewDoc(doc.id),
                          ),
                  ],
                ),
              ),
            );
          }),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  String _docTypeLabel(String type) => switch (type) {
        'INVOICE' => 'Tax Invoice',
        'INVOICE_PAGE' => 'Tax Invoice',
        'GATE_ENTRY_NOTE' => 'Gate Entry / Discrepancy Note',
        'CREDIT_NOTE' => 'Credit Note',
        'GRN' => 'Goods Receipt Note',
        _ => type.replaceAll('_', ' '),
      };

  void _showRaiseDisputeDialog(BuildContext context, String invoiceId) {
    String disputeType = 'OTHER';
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise Dispute'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: disputeType,
              decoration: const InputDecoration(labelText: 'Dispute Type'),
              items: const [
                DropdownMenuItem(
                    value: 'SHORT_RECEIPT', child: Text('Short Receipt')),
                DropdownMenuItem(
                    value: 'CREDIT_NOTE_REQUESTED',
                    child: Text('Credit Note Requested')),
                DropdownMenuItem(
                    value: 'ARITHMETIC_ERROR', child: Text('Arithmetic Error')),
                DropdownMenuItem(
                    value: 'MISSING_PAGE', child: Text('Missing Page')),
                DropdownMenuItem(
                    value: 'TAX_STRUCTURE_ERROR',
                    child: Text('Tax Structure Error')),
                DropdownMenuItem(value: 'OTHER', child: Text('Other')),
              ],
              onChanged: (v) => disputeType = v ?? 'OTHER',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ownerService.createDispute(
                  invoiceId: invoiceId,
                  disputeType: disputeType,
                  description: descController.text,
                );
                ref.invalidate(ownerInvoiceDetailProvider(widget.invoiceId));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dispute raised.')),
                  );
                }
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
            child: const Text('Raise'),
          ),
        ],
      ),
    );
  }

  void _showGateEntryDialog(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Gate Entry Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _gateNumberController,
                  decoration:
                      const InputDecoration(labelText: 'Gate Entry Number'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _invoiceQtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Invoice Qty (cases/units)',
                    hintText: 'As on invoice',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _gateQtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Accepted Qty',
                    hintText: 'As per gate entry',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Short Receipt'),
                  subtitle: const Text('Accepted < Invoiced qty'),
                  value: _isShortReceipt,
                  onChanged: (v) {
                    setState(() => _isShortReceipt = v);
                    setDialogState(() {});
                  },
                ),
                TextField(
                  controller: _gateNotesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Any discrepancy notes from gate stamp',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _savingGateEntry
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _selectedDocId = docId;
                      _saveGateEntry();
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisputeCard extends StatefulWidget {
  final InvoiceDispute dispute;
  final String invoiceId;
  final VoidCallback onUpdate;

  const _DisputeCard({
    required this.dispute,
    required this.invoiceId,
    required this.onUpdate,
  });

  @override
  State<_DisputeCard> createState() => _DisputeCardState();
}

class _DisputeCardState extends State<_DisputeCard> {
  bool _loading = false;
  bool _uploadingCreditNote = false;

  Future<void> _uploadCreditNote() async {
    final picked = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take photo'),
              onTap: () async => Navigator.pop(ctx,
                  await ImagePicker().pickImage(source: ImageSource.camera)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () async => Navigator.pop(ctx,
                  await ImagePicker().pickImage(source: ImageSource.gallery)),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;

    setState(() => _uploadingCreditNote = true);
    try {
      await ownerService.uploadCreditNote(widget.dispute.id, File(picked.path));
      widget.onUpdate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credit note uploaded.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingCreditNote = false);
    }
  }

  Color _statusColor() => switch (widget.dispute.status) {
        'OPEN' => Colors.red,
        'OWNER_REVIEWING' => Colors.orange,
        'RESOLVED' => Colors.green,
        'REJECTED' => Colors.grey,
        _ => Colors.grey,
      };

  Future<void> _update(String status) async {
    setState(() => _loading = true);
    try {
      await ownerService.updateDispute(widget.dispute.id, status);
      widget.onUpdate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dispute;
    final isOpen = d.status == 'OPEN' || d.status == 'OWNER_REVIEWING';

    return Card(
      color: isOpen ? Colors.red[50] : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    d.disputeType.replaceAll('_', ' '),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor().withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusColor()),
                  ),
                  child: Text(
                    d.statusLabel,
                    style: TextStyle(
                        color: _statusColor(),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (d.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(d.description, style: TextStyle(color: Colors.grey[700])),
            ],
            if (d.resolutionNotes != null && d.resolutionNotes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Resolution: ${d.resolutionNotes}',
                  style: const TextStyle(
                      fontStyle: FontStyle.italic, fontSize: 12)),
            ],
            if (d.disputeType == 'CREDIT_NOTE_REQUESTED') ...[
              const SizedBox(height: 8),
              if (d.creditNoteDocumentId != null)
                const Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green),
                    SizedBox(width: 4),
                    Text('Credit note attached',
                        style: TextStyle(fontSize: 12, color: Colors.green)),
                  ],
                )
              else if (isOpen)
                _uploadingCreditNote
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : OutlinedButton.icon(
                        onPressed: _uploadCreditNote,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Upload Credit Note'),
                      ),
            ],
            if (isOpen) ...[
              const SizedBox(height: 12),
              _loading
                  ? const Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : Row(
                      children: [
                        if (d.status == 'OPEN')
                          TextButton(
                            onPressed: () => _update('OWNER_REVIEWING'),
                            child: const Text('Mark Reviewing'),
                          ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: () => _showResolveDialog(context, false),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey),
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => _showResolveDialog(context, true),
                          child: const Text('Resolve'),
                        ),
                      ],
                    ),
            ],
          ],
        ),
      ),
    );
  }

  void _showResolveDialog(BuildContext context, bool resolve) {
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(resolve ? 'Resolve Dispute' : 'Reject Dispute'),
        content: TextField(
          controller: notesController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: resolve ? 'Resolution notes' : 'Reason for rejection',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _loading = true);
              try {
                await ownerService.updateDispute(
                  widget.dispute.id,
                  resolve ? 'RESOLVED' : 'REJECTED',
                  notes: notesController.text,
                );
                widget.onUpdate();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
            child: Text(resolve ? 'Resolve' : 'Reject'),
          ),
        ],
      ),
    );
  }
}

class _AuditTrailScreen extends StatefulWidget {
  final String invoiceId;
  const _AuditTrailScreen({required this.invoiceId});

  @override
  State<_AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<_AuditTrailScreen> {
  List<AuditEvent>? _events;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await ownerService.getAuditTrail(widget.invoiceId);
      if (mounted) setState(() => _events = events);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load audit trail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Trail')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _events == null
              ? const Center(child: CircularProgressIndicator())
              : _events!.isEmpty
                  ? const Center(child: Text('No events recorded yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _events!.length,
                      itemBuilder: (context, i) {
                        final e = _events![i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: const Icon(Icons.circle, size: 10),
                            title: Text(e.eventType.replaceAll('_', ' ')),
                            subtitle: Text(
                              '${e.description}\n${e.actorId}  •  ${e.createdAt.length >= 16 ? e.createdAt.substring(0, 16).replaceFirst('T', ' ') : e.createdAt}',
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
    );
  }
}

class _DocumentViewerScreen extends StatelessWidget {
  final String imagePath;
  const _DocumentViewerScreen({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.file(File(imagePath)),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final String label;
  const _StatusChip(this.status, {String? label}) : label = label ?? status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'INGESTED' => Colors.blue,
      'APPROVED' => Colors.green,
      'REJECTED' => Colors.red,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Payments made against a CREDIT invoice, plus the running balance and a
/// pointer at any unresolved short-receipt dispute (the reconciliation view:
/// invoiced -> paid -> balance, with credit-note work still open).
class _PaymentsSection extends ConsumerWidget {
  final String invoiceId;
  final double billTotal;
  final bool hasOpenShortReceipt;

  const _PaymentsSection({
    required this.invoiceId,
    required this.billTotal,
    required this.hasOpenShortReceipt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(invoicePaymentsProvider(invoiceId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Payments', Icons.payments_outlined),
        const SizedBox(height: 8),
        payments.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load payments: $e',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          data: (list) {
            final paid =
                list.fold<double>(0, (sum, p) => sum + p.amount);
            final balance = billTotal - paid;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Paid Rs.${paid.toStringAsFixed(2)}'),
                        Text(
                          balance <= 0.005
                              ? 'Settled'
                              : 'Balance Rs.${balance.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: balance <= 0.005
                                ? Colors.green
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (hasOpenShortReceipt)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Short-receipt dispute open - final receivable may drop once the credit note lands.',
                          style:
                              TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    if (list.isNotEmpty) const Divider(),
                    for (final p in list)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${p.mode}${p.reference == null ? '' : ' - ${p.reference}'}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              'Rs.${p.amount.toStringAsFixed(2)}'
                              '${p.paidOn == null ? '' : '  ${p.paidOn!.day.toString().padLeft(2, '0')}/${p.paidOn!.month.toString().padLeft(2, '0')}/${p.paidOn!.year}'}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
