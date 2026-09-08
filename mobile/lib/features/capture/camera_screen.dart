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
import 'photo_quality.dart';

// Which document is being photographed — injected via GoRouter extras.
class CameraTarget {
  final String documentType;
  final String label;
  final bool isPrimary;
  final int pageNumber; // 1-based; > 1 means this is an additional page of an existing doc type
  final int? replaceIndex; // primary invoice only: retake an existing page instead of adding a new one

  const CameraTarget({
    required this.documentType,
    required this.label,
    required this.isPrimary,
    this.pageNumber = 1,
    this.replaceIndex,
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
  FlashMode _flashMode = FlashMode.off;

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
      setState(() =>
          _errorMessage = 'Camera permission denied. Enable it in Settings.');
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
    // ResolutionPreset.max unlocks native full sensor photo quality (12MP/48MP)
    final controller = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to initialize camera: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final nextMode = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.torch,
      _ => FlashMode.off,
    };
    try {
      await _controller!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
    } catch (_) {}
  }

  Future<void> _onTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    try {
      await _controller!.setFocusPoint(offset);
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposurePoint(offset);
      await _controller!.setExposureMode(ExposureMode.auto);
    } catch (_) {}
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isCapturing) return;
    final extra = GoRouterState.of(context).extra;
    final target = extra is CameraTarget ? extra : null;
    final isPrimary = target?.isPrimary ?? true;
    setState(() => _isCapturing = true);

    try {
      final xFile = await _controller!.takePicture();
      final tempFile = File(xFile.path);
      final quality = await PhotoQualityService.analyzeFile(tempFile);
      if (quality.shouldWarn && mounted) {
        final useAnyway = await _showQualityWarning(quality);
        if (!mounted) {
          await tempFile.delete();
          return;
        }
        if (!useAnyway) {
          await tempFile.delete();
          setState(() => _isCapturing = false);
          return;
        }
      }
      if (!mounted) {
        await tempFile.delete();
        return;
      }

      final compressedPath = await ImageStore.saveCompressed(tempFile);
      // Delete temp camera file
      await tempFile.delete();

      if (isPrimary) {
        final replaceIndex = target?.replaceIndex;
        if (replaceIndex != null) {
          ref
              .read(bundleProvider.notifier)
              .replaceInvoicePage(replaceIndex, compressedPath);
        } else {
          ref.read(bundleProvider.notifier).addInvoicePage(compressedPath);
        }
        if (mounted) context.go('/capture/review');
      } else {
        // Supporting document (page 1 or additional pages)
        ref.read(bundleProvider.notifier).addSupportingPhoto(
              QueuedPhoto(
                localId: const Uuid().v4(),
                localPath: compressedPath,
                documentType: target!.documentType,
                label: target.label,
                isPrimary: false,
                pageNumber: target.pageNumber,
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

  Future<bool> _showQualityWarning(PhotoQualityResult quality) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Photo may be hard to read'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final issue in quality.issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('- '),
                        Expanded(child: Text(issue.message)),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Retake'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Use Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra;
    final target = extra is CameraTarget ? extra : null;
    final label = target?.label ?? 'Tax Invoice';

    Future<bool> handleBack() async {
      if (target != null && !target.isPrimary) {
        context.go('/capture/checklist');
      } else {
        context.go('/home');
      }
      return true;
    }

    return BackButtonListener(
      onBackButtonPressed: handleBack,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (target != null && !target.isPrimary) {
            context.go('/capture/checklist');
          } else {
            context.go('/home');
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(label),
            actions: [
              IconButton(
                icon: Icon(
                  switch (_flashMode) {
                    FlashMode.torch => Icons.flash_on,
                    FlashMode.auto => Icons.flash_auto,
                    _ => Icons.flash_off,
                  },
                  color: _flashMode == FlashMode.off ? Colors.white54 : Colors.amber,
                ),
                onPressed: _toggleFlash,
                tooltip: 'Toggle Flash',
              ),
            ],
          ),
          body: _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.camera_alt,
                            size: 64, color: Colors.white54),
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
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : LayoutBuilder(
                      builder: (context, constraints) => GestureDetector(
                        onTapDown: (details) => _onTapToFocus(details, constraints),
                        behavior: HitTestBehavior.opaque,
                        child: Stack(
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
                                      border: Border.all(
                                          color: Colors.white, width: 4),
                                    ),
                                    child: _isCapturing
                                        ? const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2),
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
                      ),
                    ),
        ),
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
    canvas.drawLine(
        Offset(margin, margin + lineLen), Offset(margin, margin), paint);
    canvas.drawLine(
        Offset(margin, margin), Offset(margin + lineLen, margin), paint);
    // Top-right
    canvas.drawLine(Offset(size.width - margin, margin + lineLen),
        Offset(size.width - margin, margin), paint);
    canvas.drawLine(Offset(size.width - margin, margin),
        Offset(size.width - margin - lineLen, margin), paint);
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
