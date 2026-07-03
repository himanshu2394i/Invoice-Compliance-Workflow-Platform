# Photo Quality Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Warn workers when a captured invoice/supporting-document photo is likely too dark, blurry, too small, or cut off before it enters the manual/OCR workflow.

**Architecture:** Add a local image analyzer in the mobile capture feature using the existing `image` package. The camera flow calls it after `takePicture()` and before compression/storage, showing a warning dialog with `Retake` and `Use Anyway` when needed.

**Tech Stack:** Flutter, Dart, `image` package, `flutter_test`.

## Global Constraints

- The gate is warning-only: workers can continue with `Use Anyway`.
- No backend, OCR, AI, or Hive schema changes in v1.
- Keep the existing capture queue and draft behavior intact.
- Use generated synthetic images for tests so no camera device is required.
- Run `puro flutter test test/capture/photo_quality_test.dart` and `puro flutter analyze`.

---

## File Structure

- Create: `mobile/lib/features/capture/photo_quality.dart`
- Modify: `mobile/lib/features/capture/camera_screen.dart`
- Create: `mobile/test/capture/photo_quality_test.dart`
- Modify: `task.md`

---

## Task 1: Local Photo Quality Analyzer

**Files:**

- Create: `mobile/lib/features/capture/photo_quality.dart`
- Create: `mobile/test/capture/photo_quality_test.dart`

**Interfaces:**

- Produces:
  - `PhotoQualityIssue`
  - `PhotoQualityResult`
  - `PhotoQualityService.analyzeFile(File file)`
  - `PhotoQualityService.analyzeImage(img.Image image)`

- [x] **Step 1: Write failing tests**

Add tests for:

- centered high-contrast document has no warning
- dark image warns with issue code `dark`
- blurred image warns with issue code `blurry`
- tiny/cut-off document warns with issue code `framing`

Run:

```powershell
cd mobile
puro flutter test test/capture/photo_quality_test.dart
```

Expected: fails because `photo_quality.dart` does not exist.

- [x] **Step 2: Implement analyzer**

Implement brightness, Laplacian-variance sharpness, and edge-bounds/content-coverage checks in `PhotoQualityService`.

- [x] **Step 3: Verify analyzer**

Run:

```powershell
cd mobile
puro flutter test test/capture/photo_quality_test.dart
```

Expected: all photo-quality tests pass.

---

## Task 2: Camera Warning Dialog

**Files:**

- Modify: `mobile/lib/features/capture/camera_screen.dart`

**Interfaces:**

- Consumes `PhotoQualityService.analyzeFile(File file)`.
- Does not change `bundleProvider`, `ImageStore`, or queue models.

- [x] **Step 1: Wire analyzer into `_capture()`**

Analyze the temporary camera file before `ImageStore.saveCompressed(...)`.

- [x] **Step 2: Add warning dialog**

Show `Photo may be hard to read` with issue messages and actions:

- `Retake`: delete temp file and keep the user on the camera screen.
- `Use Anyway`: continue with current compression and navigation.

- [x] **Step 3: Verify capture code**

Run:

```powershell
cd mobile
puro flutter analyze
```

Expected: analyzer remains at the accepted baseline count.

---

## Task 3: Docs and Final Verification

**Files:**

- Modify: `task.md`

- [x] **Step 1: Update task docs**

Mark photo quality checks complete and add the verification commands.

- [x] **Step 2: Run focused verification**

Run:

```powershell
cd mobile
puro flutter test test/capture/photo_quality_test.dart test/capture/bundle_provider_test.dart test/capture/review_screen_test.dart
puro flutter analyze
```

Expected: tests pass; analyzer remains at the accepted baseline.
