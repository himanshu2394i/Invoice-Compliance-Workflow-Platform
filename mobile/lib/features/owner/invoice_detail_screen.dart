import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'owner_provider.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  ConsumerState<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
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

  Future<void> _downloadDoc(String docId) async {
    setState(() => _downloading[docId] = true);
    try {
      final path = await ownerService.downloadDocument(widget.invoiceId, docId);
      setState(() {
        _downloadedPaths[docId] = path;
        _downloading[docId] = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to: $path')),
        );
      }
    } catch (e) {
      setState(() => _downloading[docId] = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red),
        );
      }
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

    return Scaffold(
      appBar: AppBar(
        title: detailAsync.when(
          data: (d) => Text(d.invoice.invoiceNumber),
          loading: () => const Text('Invoice'),
          error: (_, __) => const Text('Invoice'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(ownerInvoiceDetailProvider(widget.invoiceId)),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (detail) => _buildBody(context, detail),
      ),
    );
  }

  Widget _buildBody(BuildContext context, InvoiceDetail detail) {
    final inv = detail.invoice;
    final groups = detail.documentGroups;

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
                    _StatusChip(inv.currentState),
                  ],
                ),
                const SizedBox(height: 8),
                _InfoRow('Buyer', inv.buyerName ?? '—'),
                _InfoRow('Seller', inv.entityName ?? '—'),
                _InfoRow('Date', inv.invoiceDate.substring(0, 10)),
                _InfoRow('Gross', '₹${inv.grossAmount.toStringAsFixed(2)}'),
                _InfoRow('Tax', '₹${inv.taxAmount.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Disputes section
        if (detail.disputes.isNotEmpty) ...[
          _SectionHeader('Disputes (${detail.disputes.length})', Icons.gavel),
          ...detail.disputes.map((d) => _DisputeCard(
                dispute: d,
                invoiceId: widget.invoiceId,
                onUpdate: () => ref.invalidate(ownerInvoiceDetailProvider(widget.invoiceId)),
              )),
          const SizedBox(height: 16),
        ],

        // Exceptions section
        if (detail.exceptions.isNotEmpty) ...[
          _SectionHeader('Exceptions (${detail.exceptions.length})', Icons.warning_amber),
          ...detail.exceptions.map((e) => Card(
                color: e.status == 'open' ? Colors.orange[50] : null,
                child: ListTile(
                  leading: Icon(
                    e.status == 'open' ? Icons.warning_amber : Icons.check_circle,
                    color: e.status == 'open' ? Colors.orange : Colors.green,
                  ),
                  title: Text(e.exceptionType.replaceAll('_', ' ')),
                  subtitle: Text(e.status),
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
                    // Download button
                    isDownloading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: Icon(
                              savedPath != null
                                  ? Icons.check_circle
                                  : Icons.download,
                              color: savedPath != null ? Colors.green : null,
                            ),
                            tooltip: savedPath != null ? 'Saved' : 'Download',
                            onPressed: savedPath != null
                                ? null
                                : () => _downloadDoc(doc.id),
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
                DropdownMenuItem(value: 'SHORT_RECEIPT', child: Text('Short Receipt')),
                DropdownMenuItem(value: 'CREDIT_NOTE_REQUESTED', child: Text('Credit Note Requested')),
                DropdownMenuItem(value: 'ARITHMETIC_ERROR', child: Text('Arithmetic Error')),
                DropdownMenuItem(value: 'MISSING_PAGE', child: Text('Missing Page')),
                DropdownMenuItem(value: 'TAX_STRUCTURE_ERROR', child: Text('Tax Structure Error')),
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
                  decoration: const InputDecoration(labelText: 'Gate Entry Number'),
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
    final isOpen =
        d.status == 'OPEN' || d.status == 'OWNER_REVIEWING';

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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            if (isOpen) ...[
              const SizedBox(height: 12),
              _loading
                  ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
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
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
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
                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
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
  const _StatusChip(this.status);

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
        status,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
