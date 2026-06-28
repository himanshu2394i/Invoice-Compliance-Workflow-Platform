import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/bundle.dart';
import '../../core/storage/image_store.dart';
import 'bundle_provider.dart';

// Which document is being photographed — injected via GoRouter extras.
class CameraTarget {
  final String documentType;
  final String label;
  final bool isPrimary;

  const CameraTarget({
    required this.documentType,
    required this.label,
    required this.isPrimary,
  });
}

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCapturing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _errorMessage = 'Camera permission denied. Enable it in Settings.');
      return;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _errorMessage = 'No camera found on this device.');
      return;
    }
    // Prefer back camera
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to initialize camera: $e');
    }
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final xFile = await _controller!.takePicture();
      final compressedPath =
          await ImageStore.saveCompressed(File(xFile.path));
      // Delete temp camera file
      await File(xFile.path).delete();

      final extra = GoRouterState.of(context).extra;
      final target = extra is CameraTarget ? extra : null;
      final isPrimary = target?.isPrimary ?? true;

      if (isPrimary) {
        ref.read(bundleProvider.notifier).setInvoicePhoto(compressedPath);
        if (mounted) context.go('/capture/review');
      } else {
        // Supporting document
        ref.read(bundleProvider.notifier).addSupportingPhoto(
              QueuedPhoto(
                localId: const Uuid().v4(),
                localPath: compressedPath,
                documentType: target!.documentType,
                label: target.label,
                isPrimary: false,
              ),
            );
        if (mounted) context.go('/capture/checklist');
      }
    } catch (e) {
      setState(() => _isCapturing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra;
    final target = extra is CameraTarget ? extra : null;
    final label = target?.label ?? 'Tax Invoice';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label),
      ),
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_alt, size: 64, color: Colors.white54),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _initCamera,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _controller == null || !_controller!.value.isInitialized
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Stack(
                  children: [
                    SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _controller!.value.previewSize!.height,
                          height: _controller!.value.previewSize!.width,
                          child: CameraPreview(_controller!),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 48,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _capture,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: _isCapturing
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 32),
                          ),
                        ),
                      ),
                    ),
                    // Corner crop guides
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _CropGuidePainter()),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// Subtle corner guides to help workers frame the invoice
class _CropGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const margin = 20.0;
    const lineLen = 30.0;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(Offset(margin, margin + lineLen), Offset(margin, margin), paint);
    canvas.drawLine(Offset(margin, margin), Offset(margin + lineLen, margin), paint);
    // Top-right
    canvas.drawLine(
        Offset(size.width - margin, margin + lineLen), Offset(size.width - margin, margin), paint);
    canvas.drawLine(
        Offset(size.width - margin, margin), Offset(size.width - margin - lineLen, margin), paint);
    // Bottom-left
    canvas.drawLine(Offset(margin, size.height - margin - lineLen),
        Offset(margin, size.height - margin), paint);
    canvas.drawLine(Offset(margin, size.height - margin),
        Offset(margin + lineLen, size.height - margin), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width - margin, size.height - margin - lineLen),
        Offset(size.width - margin, size.height - margin), paint);
    canvas.drawLine(Offset(size.width - margin, size.height - margin),
        Offset(size.width - margin - lineLen, size.height - margin), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
