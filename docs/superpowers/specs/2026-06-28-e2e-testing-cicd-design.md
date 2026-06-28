# E2E Testing + CI/CD Pipeline — Design

## Context

This is phase 1 of a 3-phase push toward production:

1. **This spec** — automated end-to-end testing of every existing workflow + CI/CD pipeline
2. *(future spec)* Rebuild the invoice OCR extractor — `backend/python_worker/activities.py` currently keeps only 4 flat fields (`GrossAmount`, `NetAmount`, `TaxAmount`, `VendorGSTIN`) via AWS Textract's generic `AnalyzeExpense`, with a non-functional "LayoutLMv3" stub that returns hardcoded numbers regardless of input. Real invoices (logged exhaustively in `invoice_extraction.md`, 60+ documents) have line items with per-HSN-band GST, IRN/e-invoice numbers, PO numbers, multiple vendor legal entities, trade schemes, payout/rebate lines, and a separate Gate Entry/Discrepancy Note document type that must reconcile against the invoice.
3. *(future spec)* AWS production deployment

This spec covers phase 1 only. Phases 2-3 are deliberately out of scope here and will get their own design docs.

## Goal

Build automated, repeatable coverage for every existing workflow (backend + mobile), wire up CI/CD on GitHub Actions, and fix any real bugs the testing surfaces along the way — inline, not deferred.

## Approach: test pyramid (hybrid)

- **Unit tests** for pure logic (validation, GST math, reconciliation matching) — fast, no infra.
- **Black-box HTTP integration tests** for full workflow chains — drive the real API over real HTTP against the actual docker-composed Postgres + Temporal stack. This is the layer that would have caught the past production bugs (RLS being a no-op under the superuser connection, the reconciliation workflow-ID bug) since those only manifest when real components are wired together.
- **Flutter widget/unit tests** for mobile screens that don't need real camera hardware.

Rejected alternatives: pure black-box-only (simpler but slower CI, harder to localize failures) and pure unit-only (fast but wouldn't catch integration-level bugs — this is exactly the category of bug that has bitten this project before).

## Scope

### Backend (Go) — integration tests against real Postgres + Temporal

- Auth: login, JWT validation, `requireAuth`/`requireRole` 401/403 boundary cases
- Invoices: create, upload, ledger-upload, list (pagination), get, approve, audit-trail
- OCR/Temporal workflow: full extract → validate → approve/exception chain
- Gate entry: get/post, auto-raise `SHORT_RECEIPT` dispute on shortage
- Disputes: list, create, patch, credit-note issuance, all 6 dispute types
- Exceptions: list, resolve
- Missing invoice numbers: resolve
- Rules: list, create, delete
- Buyers, entities: list, create
- Owner dashboard: stats, recent invoices, document download
- Reconciliation worker: duplicate-detection logic (the workflow-ID/task-queue bug class)
- Multi-tenant RLS: live cross-tenant query proof (the superuser-bypass bug class)

### Backend (Go) — unit tests (kept/extended)

- `internal/validation/validation_test.go` already exists; extend as needed for new logic surfaced during the integration pass.

### Mobile (Flutter) — widget/unit tests

- Auth (login screen, error states)
- Settings/server config (the screen verified manually earlier this session)
- Offline queue: persistence, sync-on-reconnect, retry/conflict behavior
- Document checklist: multi-page logic ("Add page N" per doc type)
- Review screen
- Owner dashboard, gate-entry form, dispute screens — using mocked HTTP responses, no real backend needed

### Explicitly NOT automated

- Actual camera capture / crop guides (needs real device hardware). Documented as a manual smoke-test checklist instead, kept alongside the test suite.

## Test architecture

**Backend**: new integration test package (e.g. `backend/internal/api/integration_test.go` or a dedicated `backend/tests/` package) that:
- Starts the real API server in-process (same `main.go` wiring) pointed at the docker-composed Postgres + Temporal
- Seeds tenant/user data via the existing `POST /api/v1/admin/seed` endpoint
- Drives every workflow via real HTTP calls (`httptest`-style client), asserting on HTTP responses and, where needed, directly on DB state (e.g. RLS isolation proof)

**Mobile**: standard `flutter_test` widget tests in `mobile/test/`, with the HTTP/Dio layer mocked so tests don't require a live backend.

## CI/CD pipeline (GitHub Actions)

- Remote: add `https://github.com/himanshu2394i/MeridianDistributors.git` as `origin`, push current branch.
- Workflow triggers on push + pull_request to any branch.
- **Job 1 — backend**: `docker compose up -d postgres temporal`, wait for health, `go vet ./...`, `go test ./...`.
- **Job 2 — mobile**: `flutter analyze`, `flutter test`.
- No deploy step in this phase — build/push/deploy is phase 3's concern.

## Bug-handling process

Fixed inline as found, TDD-style: write the test, watch it fail, fix the underlying bug, watch it pass. No separate deferred punch-list — consistent with how the 2026-06-27 MVP-fix pass worked.

## Success criteria

- Every workflow listed in Scope has at least one passing automated test.
- `go test ./...` and `flutter test` both pass locally and in CI.
- GitHub Actions workflow is green on the pushed branch.
- Any bugs found during this pass are fixed, not just logged.
- Manual smoke-test checklist exists for camera-dependent mobile flows that can't be automated.

## Out of scope (deferred to later specs)

- OCR extractor rebuild (real line-item/multi-page/multi-entity extraction)
- AWS deployment, infrastructure-as-code, secrets management
- Build/push of Docker images or mobile APKs in CI
