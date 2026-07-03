# Photo Quality Gate Design

## Goal

Add a local, offline photo-quality warning step to the worker capture flow so obviously bad invoice/supporting-document photos are caught before they enter the queue, OCR preview, or backend workflow.

## Scope

The first version is a warning gate, not a hard blocker. A worker can still choose `Use Anyway` when field conditions are poor, but the default path nudges them to retake bad photos.

This applies to:

- Primary invoice photos.
- Additional invoice pages.
- Supporting documents such as gate-entry notes and credit/receipt proofs captured through the worker camera flow.

It does not add backend scoring, AI scoring, document perspective correction, or OCR feedback loops. Those can build on this later.

## Checks

The app evaluates the just-captured image locally before compression/storage:

- **Lighting:** warn when average luminance is too low or too high.
- **Blur:** warn when Laplacian variance is below the pilot threshold.
- **Framing:** warn when edge/content bounds suggest the document is too small in frame or cut off at the outer edge.

The thresholds are conservative because false positives are acceptable in a warning-only pilot, while false hard blocks would slow workers down.

## User Experience

After capture:

1. The app analyzes the image.
2. If no warning is found, it behaves exactly like today.
3. If warnings are found, it shows a plain dialog:
   - Title: `Photo may be hard to read`
   - Body: short bullet-like lines, for example `Too dark`, `May be blurry`, `Document may be too small or cut off`.
   - Actions: `Retake` and `Use Anyway`.
4. `Retake` deletes the temporary camera file and returns to the camera preview.
5. `Use Anyway` continues with the existing compression and queue/draft flow.

## Architecture

Create a focused analyzer in `mobile/lib/features/capture/photo_quality.dart`. It exposes:

```dart
class PhotoQualityResult {
  final double brightness;
  final double sharpness;
  final double contentCoverage;
  final List<PhotoQualityIssue> issues;
  bool get shouldWarn;
}

class PhotoQualityService {
  static Future<PhotoQualityResult> analyzeFile(File file);
  static PhotoQualityResult analyzeImage(img.Image image);
}
```

`CameraScreen` consumes this service after `takePicture()` and before `ImageStore.saveCompressed(...)`. No Hive schema change is required because this v1 does not persist scores.

## Testing

Unit tests generate synthetic images with the existing `image` package:

- A well-lit, sharp, centered document passes.
- A dark image warns for lighting.
- A blurred image warns for blur.
- A tiny/edge-cropped document warns for framing.

Camera hardware is not required for these tests.
