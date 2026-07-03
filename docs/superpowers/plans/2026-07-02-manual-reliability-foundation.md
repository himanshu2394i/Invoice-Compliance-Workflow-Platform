# Manual Reliability Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the manual invoice workflow dependable before expanding OCR/AI: recover drafts, warn about duplicates, improve server-side invoice search/filtering, make alerts filterable/aged, allow buyer requirement deletion, and improve non-technical status wording.

**Architecture:** Keep the current Go API + Postgres + Flutter architecture. Capture drafts are local-only Hive records because unfinished invoices should survive app restarts without creating server records. Backend changes stay in repository/handler files that already own each domain. Mobile changes keep service classes Dio-injectable and use existing Riverpod/Hive patterns.

**Tech Stack:** Go + pgx + Postgres migrations + existing integration harness; Flutter + Riverpod + GoRouter + Hive; `flutter_test`; Puro-managed Flutter SDK.

## Global Constraints

- Manual workflow must work with OCR/AI disabled.
- Migrations are immutable once applied; add `000010_*` if schema is needed.
- Existing Hive models must use explicit `@HiveField(N, defaultValue: X)` for any added field.
- Mobile service classes continue constructor DI with `Dio?`.
- Worker role cannot access owner routes.
- Backend verification target after Go changes: `go build ./... && go vet ./...`; integration tests require Docker Postgres+Temporal.
- Mobile verification target after Flutter changes: `puro flutter analyze` compared against `mobile/analysis_baseline.txt`, plus focused widget/unit tests.
- Do not touch abandoned `frontend/`.

---

## File Structure

Backend:

- `backend/internal/db/db.go`
- `backend/internal/api/api.go`
- `backend/internal/api/mobile_handlers.go`
- `backend/internal/api/owner_handlers.go`
- `backend/internal/api/manual_reliability_integration_test.go`

Mobile:

- `mobile/lib/core/models/bundle.dart`
- `mobile/lib/core/models/bundle.g.dart`
- `mobile/lib/core/storage/hive_service.dart`
- `mobile/lib/features/capture/bundle_provider.dart`
- `mobile/lib/features/capture/review_screen.dart`
- `mobile/lib/features/capture/checklist_screen.dart`
- `mobile/lib/features/owner/alerts_screen.dart`
- `mobile/lib/features/owner/owner_provider.dart`
- `mobile/lib/features/admin/buyer_requirements_screen.dart`
- `mobile/test/capture/bundle_provider_test.dart`
- `mobile/test/capture/review_screen_test.dart`
- `mobile/test/capture/sync_service_test.dart`
- `mobile/test/owner/owner_invoice_search_test.dart`

Docs:

- `task.md`

---

## Task 1: Draft Recovery for Worker Capture

**Files:**

- Modify: `mobile/lib/core/models/bundle.dart`
- Modify generated: `mobile/lib/core/models/bundle.g.dart`
- Modify: `mobile/lib/core/storage/hive_service.dart`
- Modify: `mobile/lib/features/capture/bundle_provider.dart`
- Modify: `mobile/lib/features/home/home_screen.dart`
- Test: `mobile/test/capture/bundle_provider_test.dart`

**Interfaces:**

- Produces local draft persistence API using `QueuedBundle`:
  - `HiveService.saveCaptureDraft(QueuedBundle draft)`
  - `HiveService.loadCaptureDraft() -> QueuedBundle?`
  - `HiveService.clearCaptureDraft()`
- Consumers: capture screens restore in-progress work after app restart.

- [x] **Step 1: Add failing draft serialization tests**

Create tests asserting a `CaptureSession` with invoice pages, buyer fields, payment type, required docs, and supporting photos can round-trip through the new draft API.

Run:

```powershell
cd mobile
puro flutter test test/capture/bundle_provider_test.dart
```

Expected: fails because draft persistence functions do not exist.

- [x] **Step 2: Implement draft persistence**

Use Hive storage, not server storage, because drafts are local in-progress work. Persist after meaningful capture changes:

- invoice page added/removed/replaced
- invoice fields updated
- required docs loaded
- supporting photo added

Clear draft only after successful submit/save-to-queue handoff or explicit reset.

- [x] **Step 3: Add resume/discard UI**

On Capture tab, if a draft exists, show:

- Resume Draft
- Discard Draft
- Capture New Invoice

The user must not accidentally lose an unfinished invoice.

- [x] **Step 4: Verify**

Run:

```powershell
cd mobile
puro flutter test test/capture/bundle_provider_test.dart
puro flutter analyze
```

Expected: draft tests pass; analyzer remains at accepted baseline.

---

## Task 2: Duplicate Invoice Warning Before Submit

**Files:**

- Modify: `backend/internal/db/db.go`
- Modify: `backend/internal/api/api.go`
- Modify: `backend/internal/api/mobile_handlers.go`
- Test: `backend/internal/api/manual_reliability_integration_test.go`
- Modify: `mobile/lib/core/api/endpoints.dart`
- Modify: `mobile/lib/features/capture/review_screen.dart`
- Test: `mobile/test/capture/review_screen_test.dart`

**Interfaces:**

- Backend endpoint:
  - `GET /api/v1/mobile/invoices/duplicate-check?invoice_number=&seller_gstin=&buyer_gstin=`
- Response:

```json
{
  "duplicate": true,
  "invoice_id": "uuid",
  "invoice_number": "A260000218",
  "buyer_name": "Airplaza Retail Holdings Pvt Ltd",
  "invoice_date": "2026-06-09",
  "total_amount": 10913.0,
  "status": "ARCHIVED"
}
```

- [x] **Step 1: Backend failing test**

Add an integration test that creates an invoice, calls duplicate-check with same invoice number + seller GSTIN, and expects `duplicate: true`. Also test an unknown number returns `duplicate: false`.

Run:

```powershell
cd backend
go test ./internal/api -run TestDuplicateInvoiceCheck -count=1
```

Expected: fails because route does not exist.

- [x] **Step 2: Repository method**

Add a tenant-scoped repository method that searches by invoice number and seller entity GSTIN. Buyer GSTIN narrows the match when supplied but should not be required.

- [x] **Step 3: Handler + route**

Register route for WORKER/ADMIN. Return 400 when invoice number is empty. Never expose another tenant's invoice.

- [x] **Step 4: Mobile warning**

When invoice number and seller entity are available, run duplicate check before proceeding to Supporting Docs. If duplicate exists, show a confirmation dialog:

> "This invoice number already exists. Continue only if this is a correction or extra document."

Buttons:

- Go Back
- Continue Anyway

- [x] **Step 5: Verify**

Run:

```powershell
cd backend
go test ./internal/api -run TestDuplicateInvoiceCheck -count=1
go build ./...
go vet ./...
cd ..\mobile
puro flutter test test/capture/review_screen_test.dart
puro flutter analyze
```

---

## Task 3: Server-Side Owner Invoice Search and Filters

**Files:**

- Modify: `backend/internal/db/db.go`
- Modify: `backend/internal/api/owner_handlers.go`
- Test: `backend/internal/api/manual_reliability_integration_test.go`
- Modify: `mobile/lib/features/owner/owner_provider.dart`
- Modify: `mobile/lib/features/owner/owner_invoices_screen.dart`
- Test: `mobile/test/owner/owner_invoice_search_test.dart`

**Interfaces:**

- Extend `GET /api/v1/owner/invoices` query params:
  - `q`
  - `status`
  - `buyer_id`
  - `from`
  - `to`
  - `has_open_issues=true|false`
  - `limit`
  - `offset`

- [x] **Step 1: Backend search/filter tests**

Test invoice number, buyer GSTIN/name, status, date range, and open issue filter.

- [x] **Step 2: Repository filtering**

Move filtering to SQL so the app can search beyond the currently loaded page.

- [x] **Step 3: Mobile query UI**

Keep the simple search box, but call backend with `q`. Add filter chips for status and open issues.

- [x] **Step 4: Verify**

Run backend integration test and owner invoice widget test.

---

## Task 4: Alert Filters and Aging

**Files:**

- Modify: `backend/internal/db/db.go`
- Modify: `backend/internal/api/owner_handlers.go`
- Modify: `mobile/lib/features/owner/owner_provider.dart`
- Modify: `mobile/lib/features/owner/alerts_screen.dart`
- Test: `mobile/test/home/home_screen_test.dart` or new `mobile/test/owner/alerts_screen_test.dart`

**Interfaces:**

- Extend `GET /api/v1/owner/alerts` query params:
  - `type=exception|dispute|overdue_invoice`
  - `min_age_days`
  - `limit`
  - `offset`
- Add response fields:
  - `age_days`
  - `priority`

- [x] **Step 1: Backend filtering tests**

Create exception/dispute/overdue examples and assert type/age filters.

- [x] **Step 2: Repository query**

Calculate `age_days` in SQL from raised/due date to current date. Priority:

- critical: overdue 30+ days or open dispute 7+ days
- warning: any open exception/dispute/overdue
- info: none for current v1

- [x] **Step 3: Mobile UI**

Add filter chips:

- All
- Exceptions
- Disputes
- Overdue

Show age like "3 days open".

- [x] **Step 4: Verify**

Run focused tests and analyze.

---

## Task 5: Delete Buyer Document Requirements

**Files:**

- Modify: `backend/internal/db/db.go`
- Modify: `backend/internal/api/api.go`
- Modify: `backend/internal/api/mobile_handlers.go`
- Test: `backend/internal/api/manual_reliability_integration_test.go`
- Modify: `mobile/lib/core/api/endpoints.dart`
- Modify: `mobile/lib/features/admin/buyer_requirements_screen.dart`

**Interfaces:**

- Backend route:
  - `DELETE /api/v1/mobile/buyers/{buyer_id}/requirements/{document_type}`
- Role:
  - ADMIN only

- [x] **Step 1: Backend failing test**

Upsert requirement, delete it, list requirements, assert it is gone.

- [x] **Step 2: Repository delete**

Delete by tenant, buyer id, and uppercased document type.

- [x] **Step 3: Handler + route**

Return 404 when buyer does not belong to tenant. Return 200 with `{"status":"deleted"}` for idempotent deletes.

- [x] **Step 4: Mobile delete action**

Add delete icon on requirement row with confirmation dialog.

- [x] **Step 5: Verify**

Run backend test and mobile analyze.

---

## Task 6: Staff-Friendly Status Labels

**Files:**

- Modify: `mobile/lib/features/capture/my_invoices_screen.dart`
- Modify: `mobile/lib/features/owner/invoice_detail_screen.dart`
- Modify: `mobile/lib/features/owner/owner_invoices_screen.dart`
- Create: `mobile/lib/core/models/status_labels.dart`
- Tests: focused widget/unit tests

**Interfaces:**

- Function:

```dart
String invoiceStatusLabel(String state, {String? paymentType, bool overdue = false, double? balance})
```

- [x] **Step 1: Unit tests for status labels**

Examples:

- `INGESTED` -> `Submitted`
- `VALIDATING` -> `Checking`
- `VALIDATION_FAILED` -> `Needs Review`
- `PENDING_MANAGER_APPROVAL` -> `Waiting for Manager`
- `PENDING_FINANCE_APPROVAL` -> `Waiting for Finance`
- `APPROVED` -> `Approved`
- `ARCHIVED` with credit balance -> `Open`
- overdue credit balance -> `Overdue`
- fully paid -> `Paid`

- [x] **Step 2: Replace raw labels in UI**

Keep raw backend state available for debugging only if needed, not as the main label.

- [x] **Step 3: Verify**

Run focused Flutter tests and analyze.

---

## Task 7: Milestone Verification

**Files:**

- Modify: `task.md`
- Modify: `docs/founder_app_walkthrough.md`

- [x] **Step 1: Run backend checks**

```powershell
cd backend
go build ./...
go vet ./...
go test ./internal/api -run "TestDuplicateInvoiceCheck|TestOwnerInvoiceFilters|TestAlertFilters|TestBuyerRequirementDelete" -count=1
```

- [x] **Step 2: Run mobile checks**

```powershell
cd mobile
puro flutter test test/capture/bundle_provider_test.dart test/capture/review_screen_test.dart test/owner/owner_invoice_search_test.dart
puro flutter analyze
```

- [x] **Step 3: Update docs**

Mark completed items in `task.md` and update founder walkthrough if wording changed.
