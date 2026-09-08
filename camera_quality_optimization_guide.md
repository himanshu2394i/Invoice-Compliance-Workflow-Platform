# Max Camera Quality & Invoice Document Optimization Guide

> **Document Version:** 1.0.0  
> **Target Audience:** Engineering Team, Mobile Developers, Field Operations Team  
> **Goal:** Comprehensive guide detailing how to maximize camera capture quality, text sharpness, and OCR readability across iPhones, Android devices, and Flutter code settings.

---

## 1. Executive Summary

Document scanning quality directly impacts downstream OCR accuracy (AWS Textract & AI extraction) and invoice reconciliation speed. On high-end smartphones (e.g. iPhone 13/14/15/16 Pro, Samsung S-series, flagship Vivo), standard camera default settings often downsample and compress images, resulting in blurred line items and misread GSTIN numbers.

This guide details both **Software/Code Optimizations** applied in the mobile app and **Hardware & Operational Best Practices** for field operators to achieve maximum 4K camera quality.

---

## 2. Technical Code Pipeline Optimizations (Flutter Mobile App)

### 2.1 Native Camera Sensor Resolution (`ResolutionPreset.max`)

In `mobile/lib/features/capture/camera_screen.dart`:

```dart
// OLD: ResolutionPreset.high (Capped at 1080p / 720p)
// NEW: ResolutionPreset.max (Unlocks native 12MP / 48MP camera sensor)
final controller = CameraController(
  camera,
  ResolutionPreset.max,
  enableAudio: false,
);
```

- **Why it matters:** `ResolutionPreset.high` limits camera capture resolution to 1920x1080. `ResolutionPreset.max` requests the device's native full-resolution photo capture (e.g. 4032x3024 on iPhones), ensuring tiny 6pt font size numbers on invoices remain pin-sharp.

---

### 2.2 Image Store Downscaling & Compression Settings

In `mobile/lib/core/storage/image_store.dart`:

| Setting Parameter | Previous Value | Optimized Max Value | Technical Impact |
| :--- | :--- | :--- | :--- |
| `_maxDimension` | `2048px` | `3840px` (4K UHD) | Prevents resolution degradation; preserves full text detail across large multi-item A4 invoices. |
| `_jpegQuality` | `80%` | `92%` | Eliminates lossy compression block artifacts around digits and characters. |

```dart
class ImageStore {
  static const int _maxDimension = 3840; // 4K resolution limit
  static const int _jpegQuality = 92;     // High-fidelity JPEG encoding
  ...
}
```

---

### 2.3 Hardware Tap-to-Focus & Auto-Exposure Lock

High-aperture phone cameras (especially iPhones) have shallow depth of field. If the lens focuses on the background surface instead of the paper, invoice text becomes blurry.

We implemented touch-to-focus in `camera_screen.dart`:

```dart
Future<void> _onTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
  final offset = Offset(
    details.localPosition.dx / constraints.maxWidth,
    details.localPosition.dy / constraints.maxHeight,
  );
  await _controller!.setFocusPoint(offset);
  await _controller!.setFocusMode(FocusMode.auto);
  await _controller!.setExposurePoint(offset);
  await _controller!.setExposureMode(ExposureMode.auto);
}
```

- **User Action:** Operators can tap anywhere on the invoice text on screen to lock optical focus and adjust lighting exposure instantly.

---

### 2.4 Flash & Torch Lighting Toggle

In dim godowns, dark stores, or night shifts, camera sensors increase ISO gain, creating noise and grain that obscures small characters.

We added an integrated **Flash Torch Control** in the camera navigation bar:

```dart
Future<void> _toggleFlash() async {
  final nextMode = switch (_flashMode) {
    FlashMode.off => FlashMode.auto,
    FlashMode.auto => FlashMode.torch, // Constant LED light
    _ => FlashMode.off,
  };
  await _controller!.setFlashMode(nextMode);
  setState(() => _flashMode = nextMode);
}
```

- **Best Practice:** When scanning in dimly lit areas, turn on **Torch Mode** (`FlashMode.torch`) for constant bright white illumination.

---

## 3. Field Operator Shooting & Quality Guidelines

To achieve 100% OCR readability, field workers should follow these 5 rules:

```mermaid
flowchart LR
    A[1. Clean Lens] --> B[2. Flat Surface]
    B --> C[3. Perpendicular Angle]
    C --> D[4. Tap Text to Focus]
    D --> E[5. Confirm Torch Light]
```

### Rule 1: Lens Cleanliness
- **Check:** Wipe smartphone camera glass with a clean cloth. Fingerprint oils and grease create hazing and soft focus.

### Rule 2: Flat Surface & Framing
- Place the invoice flat on a clean table or smooth box.
- Avoid holding the paper in hand while taking photos (prevents hand-shake blur and paper bending distortion).
- Align invoice corners within the on-screen white crop guides.

### Rule 3: Shooting Angle (Perpendicular 90°)
- Hold the phone directly above the invoice (90-degree angle).
- Avoid steep side angles or tilted shots, which cause trapezoid distortion and uneven focus across lines.

### Rule 4: Eliminate Glare & Shadows
- Position light sources to the side or turn on **Torch Mode**.
- Avoid casting phone or body shadows over the invoice totals/GSTIN block.

### Rule 5: Tap-to-Focus Before Clicking
- Tap the screen directly on the smallest text line items before pressing the capture button.

---

## 4. Automated Quality Inspection & Validation Rules

The app automatically validates every captured photo using **`PhotoQualityService`** (`mobile/lib/features/capture/photo_quality.dart`):

```
+------------------+-----------------------+------------------------------------------+
| Quality Check    | Threshold             | User Warning Action Triggered            |
+------------------+-----------------------+------------------------------------------+
| Luminance        | Grayscale < 55        | "Too dark - Turn on Flash Torch"         |
| Overexposure     | Grayscale > 238       | "Too bright - Reduce overhead glare"     |
| Sharpness Blur   | Laplacian Var < 85    | "May be blurry - Tap text to re-focus"   |
| Framing Boundary | Document Coverage <30%| "Document too small or cut off"          |
+------------------+-----------------------+------------------------------------------+
```

---

## 5. Platform-Specific Camera Optimization Summary

### iOS (iPhone 12/13/14/15/16 Series)
- High-resolution camera sensors utilize 12MP/48MP raw stream output.
- Disables automatic digital crop smoothing.
- Optical Image Stabilization (OIS) automatically active.

### Android (Mid-Range to Flagship Devices)
- Supports Camera2 API Hardware Level (`HARDWARE_LEVEL_FULL`).
- Auto-focus mode set to continuous video/photo document scanning mode (`FocusMode.auto`).

---

## 6. Summary of Quality Improvement Metrics

| Metric | Before Optimization | After Optimization |
| :--- | :--- | :--- |
| **Max Image Resolution** | 2048 x 1536 px | **3840 x 2880 px (4K)** |
| **JPEG Quality Factor** | 80% | **92%** |
| **Camera Sensor Mode** | `ResolutionPreset.high` | **`ResolutionPreset.max`** |
| **Blur Warning System** | Passive | **Active Laplacian Variance Analysis** |
| **Low-Light Capture** | High ISO Noise | **Active Torch Mode Toggle** |

---
*Document prepared for Meridian Distributors mobile invoice capture system.*
