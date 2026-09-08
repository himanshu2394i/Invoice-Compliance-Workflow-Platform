# Project Changes, Technical Rationale & Enhancements Summary

> **Document Version:** 1.0.0  
> **Date:** July 27, 2026  
> **Target Audience:** Product Lead, Mobile Engineering Team, Backend Team  
> **Goal:** Comprehensive documentation of all user requests, architectural changes, code modifications, technical rationales, and verification results implemented during this session.

---

## 1. User Requests & Business Objectives

1. **Master Series Catalog & Extraction ("Khud Se Bharna Easy Banaye")**:
   - *User Request:* Read all Excel files in the folder containing invoice series names and extract all dataset information so form filling is effortless.
2. **Camera Hardware Quality Upgrade ("iPhone vs Vivo Quality Cap")**:
   - *User Request:* Upgrade camera capture quality so high-end sensors (e.g. iPhone) utilize full sensor resolution instead of looking like a budget phone.
3. **Auto-Filling Seller Entity & Buyer Name**:
   - *User Request:* Fix camera OCR auto-fill so Seller Entity Type and Buyer Name are automatically populated without manual typing.
4. **Fuzzy OCR String Matching**:
   - *User Request:* Use a master candidate list to perform fuzzy matching ("give it a list and ask what is written there most similar to from these") to resolve OCR typos.
5. **Handling Faint / Low-Ink Invoices**:
   - *User Request:* Add solutions for faint/light dot-matrix and thermal printed invoices ("some invoices are too light").
6. **End-to-End Build & Permutation Verification**:
   - *User Request:* Build everything end-to-end, test all permutations, and build the release APK.

---

## 2. Comprehensive Breakdown of All Changes & Technical Rationales

### 2.1 Master Series Data Extraction & Unification

- **What Was Done:**
  - Parsed all 8 Master Series Excel files:
    1. `ACCOUNT MASTER this is CAD series.xlsx` (387 records — Cadbury / Mondelez)
    2. `Customer_Master_Report (3) HAL0 series.xlsx` (139 records — Haldiram Foods)
    3. `MORDE PARTY MASTER MORDE00 series.xlsx` (446 records — Morde Chocolates)
    4. `Retailer Master Detail Report nivea NIV35941826 series.xls` (61 records — Nivea Personal Care)
    5. `Retailer Master Report nestle DBR0 series.xlsx` (53 records — Nestle India)
    6. `RetailerMasterDump ecom IN00 series.xlsx` (72 records — Reckitt E-Com)
    7. `RetailerMasterDump ecom home REHIN000 series.xlsx` (31 records — Reckitt Home)
    8. `RetailerMasterDump mt rbi HYGIN0 series.xlsx` (96 records — Reckitt Hygiene)
  - Generated **18 exported dataset files** (9 JSON + 9 CSV) in [`data/master_exports/`](file:///d:/MeridianDist/data/master_exports), including a 1,285-record unified dataset (`unified_master_retailers.json` & `.csv`).
  - Added PostgreSQL migration **[`000010_master_retailers.up.sql`](file:///d:/MeridianDist/backend/db/migrations/000010_master_retailers.up.sql)**.
- **Why It Was Done:**
  - Standardizes 8 different legacy spreadsheet formats into a single database schema (`master_retailers`) to enable 1-tap pre-filling in the mobile app and database lookup APIs.

---

### 2.2 Unlocking Native Ultra-HD Camera Resolution

- **Files Modified:** [`mobile/lib/features/capture/camera_screen.dart`](file:///d:/MeridianDist/mobile/lib/features/capture/camera_screen.dart), [`mobile/lib/core/storage/image_store.dart`](file:///d:/MeridianDist/mobile/lib/core/storage/image_store.dart)
- **What Was Changed:**
  1. Changed `ResolutionPreset.high` ➡️ **`ResolutionPreset.max`** in `CameraController`.
  2. Increased downscaling dimension limit from `2048px` ➡️ **`3840px` (4K UHD)** in `ImageStore`.
  3. Upgraded JPEG compression quality from `80%` ➡️ **`92%`**.
- **Why It Was Done:**
  - `ResolutionPreset.high` capped camera capture at 1080p, while `_maxDimension = 2048` downsampled photos captured by 12MP/48MP iPhone optics, making text look blurred. Unlocking native 4K sensor capture preserves crisp line-item legibility.

---

### 2.3 Faint Invoice Dynamic Contrast & Gamma Filter

- **Files Modified:** [`mobile/lib/core/storage/image_store.dart`](file:///d:/MeridianDist/mobile/lib/core/storage/image_store.dart), [`mobile/lib/features/capture/photo_quality.dart`](file:///d:/MeridianDist/mobile/lib/features/capture/photo_quality.dart)
- **What Was Changed:**
  1. Applied dynamic color adjustment in `ImageStore.saveCompressed()`:
     ```dart
     image = img.adjustColor(
       image,
       contrast: 1.30,
       gamma: 0.75,
     );
     ```
  2. Added contrast standard deviation check (`_stdDev`) in `PhotoQualityService` to tag faint prints (`code: 'faint'`).
- **Why It Was Done:**
  - Field dot-matrix and thermal receipts often have low-ink grey print that blends into white paper. Stretching contrast and applying `gamma: 0.75` darkens mid-tone grey ink to crisp black without over-exposing the white paper.

---

### 2.4 Hardware Tap-to-Focus & Flash Torch Control

- **File Modified:** [`mobile/lib/features/capture/camera_screen.dart`](file:///d:/MeridianDist/mobile/lib/features/capture/camera_screen.dart)
- **What Was Changed:**
  1. Added `_onTapToFocus(TapDownDetails details, BoxConstraints constraints)` listener to `CameraPreview`.
  2. Added Flash Torch mode toggle (`_toggleFlash`) with an AppBar icon button (Off / Auto / Torch).
- **Why It Was Done:**
  - High-aperture smartphone lenses have shallow depth-of-field; tap-to-focus allows operators to tap directly on tiny text to force optical focus. Flash torch mode provides bright illumination in dark godowns.

---

### 2.5 Fuzzy OCR Matching Engine & Auto-Filling Seller Entity / Buyer Name

- **Files Created/Modified:**
  - [`mobile/lib/features/capture/fuzzy_match.dart`](file:///d:/MeridianDist/mobile/lib/features/capture/fuzzy_match.dart) (New Fuzzy Matching Utility)
  - [`mobile/lib/features/capture/review_screen.dart`](file:///d:/MeridianDist/mobile/lib/features/capture/review_screen.dart)
- **What Was Changed:**
  1. Implemented Levenshtein distance & Token Set ratio similarity algorithm (`FuzzyMatch.findBestMatch`).
  2. Updated `_detectSeriesFromNumber()` in `review_screen.dart` to automatically set the Seller Entity Dropdown (`_entityGstin`):
     - `HAL` series ➡️ *Meridian Distributors* (`06AAAAA0015A1ZF`).
     - `IN00` / `REHIN` / `HYGIN` series ➡️ *Meridian Gurgaon* (`06AAAAA0017A1ZH`).
     - `CAD` / `MORDE` / `NIV` / `DBR` series ➡️ *Meridian Brothers* (`06AAAAA0003A1Z3`).
  3. Updated OCR preview handler (`_runOCRPreviewIfPossible`) to fuzzy-match extracted seller and buyer strings against the master lists.
- **Why It Was Done:**
  - OCR often extracts noisy strings with minor typos (e.g. `"Airplaza Retail Hold"`, `"Zepto Ltd"`, `"Meridian Brothrs"`). Fuzzy matching resolves them to the exact master records, auto-filling **Buyer Name, GSTIN, Address, Route, and Payment Terms** automatically.

---

## 3. Test Suites & Verification Summary

### Permutation Unit Tests Created
1. **[`series_entity_permutation_test.dart`](file:///d:/MeridianDist/mobile/test/capture/series_entity_permutation_test.dart)**:
   - Verified 100% accurate entity resolution across all 8 series prefixes, case variations, and numeric formats.
2. **[`fuzzy_permutation_test.dart`](file:///d:/MeridianDist/mobile/test/capture/fuzzy_permutation_test.dart)**:
   - Verified fuzzy matching across 20+ OCR typo variations against master buyer names.
3. **[`fuzzy_match_test.dart`](file:///d:/MeridianDist/mobile/test/capture/fuzzy_match_test.dart)**:
   - Verified string similarity scores and token set overlap calculations.

### Test Execution Results

```
Backend Go Build:   go build ./... ; go vet ./... ➡️ 0 errors
Flutter Unit Tests: puro flutter test ➡️ 104 / 104 tests passed
Flutter Analyzer:   puro flutter analyze ➡️ No issues found! (0 warnings, 0 errors)
```

---

## 4. Master Document Index

| Document Name | Path | Description |
| :--- | :--- | :--- |
| **Project Summary & Changelog** | [`project_changes_and_optimizations_summary.md`](file:///d:/MeridianDist/project_changes_and_optimizations_summary.md) | This complete summary document. |
| **Series Auto-Fill Architecture** | [`series_master_autofill_guide.md`](file:///d:/MeridianDist/series_master_autofill_guide.md) | Master catalog and 1-tap pre-fill technical design. |
| **Extracted Datasets Catalog** | [`full_extracted_series_master_data.md`](file:///d:/MeridianDist/full_extracted_series_master_data.md) | Master extracted data directory and Postgres seed guide. |
| **Camera Quality Optimization** | [`camera_quality_optimization_guide.md`](file:///d:/MeridianDist/camera_quality_optimization_guide.md) | 4K camera quality & faint print enhancement guide. |
| **Systems Walkthrough** | [`walkthrough.md`](file:///d:/MeridianDist/walkthrough.md) | Updated end-to-end verification walkthrough report. |

---
*Document prepared for Meridian Distributors system.*
