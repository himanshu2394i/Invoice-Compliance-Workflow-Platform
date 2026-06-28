import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/storage/hive_service.dart';
import 'bundle_provider.dart';
import 'camera_screen.dart';
import 'sync_service.dart';

class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key});

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  bool _isSubmitting = false;
  String? _submitError;

  Future<void> _captureDoc(String docType, String label) async {
    context.go(
      '/capture/camera',
      extra: CameraTarget(
        documentType: docType,
        label: label,
        isPrimary: false,
      ),
    );
  }

  Future<void> _submit() async {
    final session = ref.read(bundleProvider);
    if (!session.allDocsComplete) {
      setState(() =>
          _submitError = 'Please photograph all required supporting documents first.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final bundle = session.toBundle();
      await HiveService.saveBundle(bundle);
      // Attempt immediate sync; failure queues it for later (handled by connectivity watcher)
      await syncService.syncPending();
      ref.read(bundleProvider.notifier).reset();
      if (mounted) context.go('/home');
    } catch (e) {
      // Even on sync error, the bundle was saved locally — tell user it will sync later
      ref.read(bundleProvider.notifier).reset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved offline — will sync when connection is restored.'),
            duration: Duration(seconds: 3),
          ),
        );
        context.go('/home');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(bundleProvider);
    final required = session.requiredDocs;
    final captured = session.additionalPhotos;

    return Scaffold(
      appBar: AppBar(title: const Text('Supporting Documents')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Primary invoice summary
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.invoiceNumber,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${session.buyerName}  •  ₹${session.totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.check_circle, color: Colors.green),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (required.isEmpty) ...[
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No additional documents required for this buyer.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'Required supporting documents (${captured.length}/${required.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: required.length,
                    itemBuilder: (context, i) {
                      final req = required[i];
                      final done = captured
                          .any((p) => p.documentType == req.documentType);
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            done ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: done ? Colors.green : Colors.grey,
                          ),
                          title: Text(req.label),
                          subtitle: req.isBuyerGenerated
                              ? const Text(
                                  'Buyer-generated — ask the store for this document',
                                  style: TextStyle(
                                      fontSize: 12, fontStyle: FontStyle.italic),
                                )
                              : null,
                          trailing: done
                              ? const Icon(Icons.photo_camera, color: Colors.green)
                              : FilledButton.tonal(
                                  onPressed: () =>
                                      _captureDoc(req.documentType, req.label),
                                  child: const Text('Capture'),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],

              if (_submitError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _submitError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.upload),
                  label: Text(
                    session.allDocsComplete ? 'Submit Bundle' : 'Submit Anyway',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: session.allDocsComplete
                        ? null
                        : Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
