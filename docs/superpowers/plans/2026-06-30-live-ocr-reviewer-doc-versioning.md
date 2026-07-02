# Live OCR, Reviewer Role, and Document Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add live OCR autofill before final invoice submission, split reviewer access from owner/admin powers, configure buyer receipt-proof requirements from the invoice extractor, and make corrected document uploads append versions instead of creating duplicate documents.

**Architecture:** Keep final ledger upload unchanged and add a short-timeout OCR preview endpoint that stores a temporary file and runs the existing Python OCR activity through a lightweight Temporal workflow. Add `REVIEWER` as an authorization role with read/resolve permissions but no approval/configuration powers. Treat document replacement as version append on the existing document, restricted to `MANAGER` and `ADMIN`.

**Tech Stack:** Go API, Postgres migrations, Temporal workflows, Python OCR worker, Flutter mobile app with Dio/Riverpod/Hive.

## Global Constraints

- Capture must never block if OCR fails or times out.
- OCR preview creates no invoice row and no document row.
- Reviewer can resolve exceptions/disputes but cannot approve invoices or manage admin configuration.
- No document delete path; corrected uploads create immutable `document_versions` rows.
- Workers cannot append/replace a document after an invoice exists; manager/admin only.
- Buyer document requirements are configured by migration/upsert from observed extractor evidence.

---

### Task 1: Reviewer Role

**Files:**
- Create: `backend/db/migrations/000008_reviewer_role_and_receipt_requirements.up.sql`
- Create: `backend/db/migrations/000008_reviewer_role_and_receipt_requirements.down.sql`
- Modify: `backend/internal/api/api.go`
- Modify: `mobile/lib/features/home/home_screen.dart`
- Test: existing backend route-gating tests and mobile home tests

**Steps:**
- [ ] Write failing tests showing `REVIEWER` can reach owner alerts/dashboard and cannot approve/admin-configure.
- [ ] Add the `users.role` CHECK migration for `REVIEWER`.
- [ ] Add `REVIEWER` to owner/read/resolve route gates only.
- [ ] Add reviewer home/dashboard/alert visibility on mobile.
- [ ] Run focused backend/mobile tests.

### Task 2: OCR Preview

**Files:**
- Modify: `backend/internal/api/api.go`
- Modify: `backend/internal/workflow/workflows.go`
- Modify: `backend/cmd/worker/main.go`
- Modify: `mobile/lib/core/api/endpoints.dart`
- Modify: `mobile/lib/features/capture/review_screen.dart`
- Test: backend workflow unit test and Flutter review-screen test

**Steps:**
- [ ] Write failing test for a preview response that safely returns extracted fields without creating invoice/doc rows.
- [ ] Add `InvoiceOCRPreviewWorkflow` that calls `ExtractTextAndLayout` only.
- [ ] Add `POST /api/v1/mobile/invoice-ocr-preview` with short synchronous wait and empty fallback on timeout/failure.
- [ ] Call preview from review screen for the primary photo and fill only empty fields.
- [ ] Add non-blocking OCR status/warning UI.

### Task 3: Document Version Replacement

**Files:**
- Modify: `backend/internal/db/db.go`
- Modify: `backend/internal/api/api.go`
- Modify: `backend/internal/api/owner_handlers.go`
- Modify: `mobile/lib/features/owner/invoice_detail_screen.dart`
- Test: backend API tests

**Steps:**
- [ ] Write failing test showing a second upload of the same document type by worker is forbidden after invoice creation.
- [ ] Write failing test showing manager/admin upload appends a new version to the existing document.
- [ ] Add repository helpers for latest version number, existing document by type, and version history.
- [ ] Change supporting-doc upload route gate to manager/admin and append versions on matching document type.
- [ ] Add optional version reads/history endpoint.

### Task 4: Buyer Receipt Requirements

**Files:**
- Modify: `backend/db/migrations/000008_reviewer_role_and_receipt_requirements.up.sql`
- Modify: `backend/db/migrations/000008_reviewer_role_and_receipt_requirements.down.sql`
- Modify: `backend/internal/api/api.go`
- Test: migration/seed assertions where available

**Steps:**
- [ ] Upsert receipt-proof requirements by GSTIN for Flipkart, Max Hypermarket, Innovative Retail Concepts, Zepto, V-Mart, and Airplaza/Vishal.
- [ ] Keep labels aligned with observed extractor wording.
- [ ] Remove the old task gap that said these were intentionally unconfigured.
