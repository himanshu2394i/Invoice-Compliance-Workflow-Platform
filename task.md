# Task List — Meridian Invoice Capture (Pilot)

Status as of 2026-06-29. Updated as work progresses — check this file for the
current state before starting new work. Mirrors the in-session task tracker.

## Phase 1 — Original MVP build (done)

- `[x]` Step 1: Infrastructure Setup (Docker Compose)
- `[x]` Step 2: Go Backend Initialization & Database Schema
- `[x]` Step 3: Go Core API & PostgreSQL Data Repository
- `[x]` Step 4: Temporal Workflows & Activities
- `[x]` Step 5: Next.js Frontend Ingestion & Dashboard UI
- `[x]` Step 6: System Verification & Integration Testing

## Phase 2 — Code review fixes (`feat/mobile-capture-app` branch, done)

- `[x]` Fix CI lint policy to use a warning/info baseline instead of blanket suppression
- `[x]` Add automated tests for owner dashboard, gate-entry form, dispute, and review screens
- `[x]` Make CI worker liveness check sustained, not single-probe
- `[x]` Validate DisputeType against DB CHECK constraint before insert
- `[x]` Fix gofmt spacing nit in owner_handlers.go

## Phase 3 — AWS pilot deployment (done)

Live at `https://203-0-113-10.sslip.io` (EC2 t3.small, ap-south-1, account
separate from `terraform-deploy`). Postgres/Temporal/OCR-worker/API/Caddy all
running via `deploy/docker-compose.prod.yml`. Real org seeded (Meridian
Brothers / Meridian Distributors / Meridian Gurgaon); worker + admin pilot
passwords rotated off the shared demo default.

- `[x]` Install Docker + Docker Compose on the pilot EC2 instance
- `[x]` Ship backend code + production docker-compose to the server
- `[x]` Run migrations and seed real Meridian org/entity/user data
- `[x]` Build and sideload a release APK pointed at the live server
- `[ ]` End-to-end smoke test on a real device against the live server — **in progress, blocked on feedback from device testing**

## Phase 4 — Mobile/backend feature parity buildout (in progress)

Full release build verified green 2026-06-30 after all items below (worked
around a Windows Gradle/Kotlin incremental-compiler file-lock bug introduced
by the new `image_picker` dependency — see `kotlin.incremental=false` in
`mobile/android/gradle.properties`). Latest APK built at
`mobile/build/app/outputs/flutter-apk/app-release.apk`. Not yet re-sideloaded
to a device.

Triggered by gaps found during the smoke test: backend has more capability
than the mobile app exposes, and several rough edges in the capture flow.

- `[x]` Add in-app document viewer for owner dashboard (was download-only)
- `[x]` Support multi-page capture for the primary invoice (was capped at 1 page)
- `[x]` Add buyer GSTIN/name autocomplete (searchable dropdown over the fixed buyer list)
- `[x]` Add mobile UI to manage buyer document requirements (`/admin/buyer-requirements`)
- `[x]` Add worker visibility into invoice status post-sync (`/my-invoices`)
- `[x]` Split reviewer role from owner + add exception alerts
- `[x]` Add exception resolution UI (resolve / not-applicable buttons)
- `[x]` Add invoice approval workflow UI (approve/reject, role-gated)
- `[x]` Add credit note upload UI for disputes (camera or gallery via `image_picker`)
- `[x]` Add audit trail viewing UI (`/owner/invoices/:id` → history icon)
- `[x]` Add matching rules management UI (`/admin/rules`, route + nav wired, `flutter analyze` clean against updated baseline)
- `[x]` Enable real OCR (AWS Textract) in the ocr-worker — boto3 installed, ocr-worker authenticates via
  EC2 instance role `meridian-ocr-worker-role` (no static AWS keys anywhere). Verified end-to-end: credentials
  resolve and Textract's `AnalyzeExpense` API is reachable. Runs as backend-side post-hoc validation only —
  does not yet pre-fill the mobile review screen (see next item).
- `[x]` Wire OCR extraction into the live mobile capture flow — added short-timeout OCR preview before review form
  autofill. It stores a temporary preview image only, creates no draft invoice/document rows, fills only empty fields,
  and falls back to manual entry if OCR fails or times out.

## Phase 5 — Bug fixes + real data cleanup (2026-06-29/30)

- `[x]` Fix session-restore race condition: app logged users out on every reopen. Root cause:
  `main()` called `runApp()` before the saved token was read, so GoRouter's first redirect always saw
  "not logged in." Fixed by awaiting `loadInitialAuthState()` (decodes the saved JWT) before `runApp` and
  seeding `authProvider`'s initial state via override — see `lib/main.dart`, `lib/features/auth/auth_provider.dart`,
  `lib/core/api/api_client.dart` (`decodeJwtPayload`).
- `[x]` Simplify pilot login credentials to `himanshu{worker,manager,admin,finance}@gmail.com`, all
  password `Pilot@2026` (shared for now since it's solo testing — rotate before handing devices to real staff).
- `[x]` Verified approval rules work end-to-end: live CRUD round-trip via API, and confirmed
  `workflows.go` actually reads tenant rules and drives manager/finance approval routing from them
  (not dead code). Note: backend DSL also defines `AUTO_APPROVE`/`AUTO_REJECT` actions, but
  `workflows.go` doesn't act on them yet — mobile UI correctly only exposes the two actions that work.
- `[x]` Populated real buyer data from `dataset_registry.md`/`invoice_extraction.md` (actual invoice
  history) — went from 4 buyers to 20, each with real GSTIN. Added `GATE_ENTRY_NOTE` requirement for
  Zepto and V-Mart Retail Limited (strong repeated evidence of a separate gate-entry document in the
  historical data, same pattern as the already-configured Airplaza requirement).
- `[x]` Configured receipt-proof requirements from the extractor for organized/e-commerce buyers: Flipkart
  `GRN_SEAL`, Max Hypermarket `SECURITY_INWARD_STAMP`, Innovative Retail Concepts `STOCK_RECEIVING_ACK`,
  plus normalized Airplaza/Vishal, Zepto, and V-Mart receiving-note labels through migration upserts.
- Prepared but **not deployed**: a public `/downloads/` static-file route on Caddy to self-host the latest
  APK (`deploy/Caddyfile`, `deploy/docker-compose.prod.yml`) — user said leave it for now, keep sharing
  the APK file directly instead.

## Phase 7 — Exception/dispute alerts (2026-06-30)

- `[x]` Built task #16: reviewer role split plus alert feed. New
  `GET /api/v1/owner/alerts` backend endpoint (`internal/db/db.go`'s `GetOpenAlerts`,
  `internal/api/owner_handlers.go`'s `handleGetAlerts`) unions open exceptions + open disputes into one
  feed. Mobile: bell icon with a live badge count in the home screen app bar (visible to ADMIN/MANAGER/FINANCE/REVIEWER,
  polled on every home-screen build) → new `/alerts` screen (`lib/features/owner/alerts_screen.dart`) listing
  each item, tap-through to the invoice. In-app only, no push/SMS/email — those would need separate
  infra (Firebase/SES) that wasn't asked for.
- Verified live: endpoint returns `{"alerts":[],"count":0}` correctly against the current (empty)
  exceptions/disputes tables.

## Phase 6 — Review fix pass (in progress, 2026-06-30)

- `[x]` Fix OCR validation trust boundaries: distinguish real vs simulated/inconclusive extraction and reconcile OCR
  output against the invoice the worker submitted.
- `[x]` Fix supporting-document matching so empty real OCR output does not get logged as a clean match.
- `[x]` Fix multi-page invoice upload so all captured invoice pages reach the backend intentionally.
- `[x]` Fix gate-entry document ownership validation and mobile role/navigation gaps, including FINANCE dashboard access
  and Android back behavior in the capture flow.
- `[x]` Review alert routing and worker input workflow: route OCR/validation problems into open invoice exceptions,
  default invoice date, improve buyer autocomplete, normalize GSTIN input, and reject impossible amount totals.
- `[x]` Wire OCR extraction into live mobile autofill via a temporary OCR preview endpoint and review-screen autofill.
- `[x]` Change corrected supporting-document uploads to immutable document-version appends; workers can add the first
  required supporting proof, but replacing an existing document type is manager/admin-only. Manager/admin can view
  document version history.

### Known gaps not yet on this list

- Password-change/reset and buyer requirement delete support have since been
  implemented; keep this section for future newly found gaps.

## Phase 8 — Navigation, search, and product hardening roadmap (2026-07-01)

- `[x]` Add app-wide Android back handling and visible back buttons across mobile screens.
- `[x]` Add admin/manager invoice search by invoice number, buyer, GSTIN, amount, and status.
- `[x]` Add OCR review cues on autofilled worker fields. Numeric confidence display waits on backend confidence values.
- `[x]` Add photo quality checks for blur, darkness, and missing document edges.
- `[x]` Add duplicate-invoice warning before submit.
- `[x]` Add capture draft recovery.
- `[x]` Add alert filters and aging for exceptions/disputes/approval work.
- `[x]` Add password-change/reset support before real staff rollout.
- `[ ]` Add MFA for admin/manager users before broader pilot use.
- `[ ]` Define DPDP/CERT-In operating checklist while keeping data indefinitely for now.

## Phase 9 — Distributor-ops rebuild (2026-07-02)

Spec: `docs/superpowers/specs/2026-07-02-distributor-ops-rebuild-design.md`;
plan: `docs/superpowers/plans/2026-07-02-distributor-ops-rebuild.md`. Turns
the capture pilot into a distributor operations product around the real
business documented in `invoice_extraction.md`.

- `[x]` Migration 000009: principals, invoice-series registry, buyer
  branches, buyer sales-channel + default credit terms, invoice payment
  fields (type/terms/due date/salesman/beat), invoice_payments table — all
  additive with RLS; seeds the known Meridian principals + series mappings.
- `[x]` Receivables: `GET /owner/receivables` (+ per-buyer drill-down) with
  aging buckets over CREDIT invoices; `POST/GET /invoices/{id}/payments`
  with in-transaction over-balance rejection; overdue invoices join the
  alerts feed.
- `[x]` Sales reports: `GET /owner/reports/sales` grouped by
  principal/buyer/channel/entity/salesman (whitelisted).
- `[x]` Master data CRUD: principals, series registry, buyer branches,
  PATCH buyer channel/terms (reads all-authed, writes ADMIN).
- `[x]` Ledger upload stamps payment terms/due date and resolves
  principal/series by longest invoice-number prefix; gate-entry auto-dispute
  now fires on any receiving mismatch, idempotently.
- `[x]` Mobile navigation rebuilt into role shells: worker
  Capture|Queue|My Invoices, owner Dashboard|Invoices|Receivables|Alerts|More
  (BackButtonListener-based back policy, double-back exit).
- `[x]` Mobile receivables tab + record-payment sheet; dashboard sales
  section; capture Cash/Credit + terms + series chip + branch picker;
  invoice-detail payment history/balance.
- `[x]` Verified: full backend suite green against Docker Postgres+Temporal;
  47+ mobile tests green; analyzer at the 27-issue baseline.
- `[x]` Deploy to pilot EC2 (2026-07-02): shipped tracked backend/deploy
  files via tarball to `~/meridian`, rebuilt api/worker/ocr-worker/migrate
  images, migrated DB 6 → 9 (clean), restarted stack. Verified live:
  principals + all 11 series seeded for the real org, receivables and
  sales-report endpoints responding. Note: SSH SG rule for the old home IP
  122.177.103.185/32 is stale (current IP rule added 2026-07-02) — remove
  the old one when convenient.
- `[x]` Release APK built (`mobile/build/app/outputs/flutter-apk/app-release.apk`,
  56.8MB, defaults to the live server URL). **Still to do: sideload onto the
  pilot device.**

## Phase 10 - Founder walkthrough prep (2026-07-02)

- `[x]` Added `docs/founder_app_walkthrough.md`: non-technical founder demo
  guide covering app purpose, roles, worker/owner/admin flows, storage reality
  without S3, alerts, OCR status, working features, known gaps, and a suggested
  presentation script.

## Phase 11 - AI structured extraction design (2026-07-02)

- `[x]` Added `docs/superpowers/specs/2026-07-02-ai-structured-extraction-v1-design.md`
  for Option B: strict JSON AI extraction for invoice header/totals plus
  supporting-document matching, explicitly excluding line items from v1.

## Phase 12 - Enterprise invoice management manual-first rebuild (2026-07-02)

- `[x]` Added `docs/superpowers/specs/2026-07-02-enterprise-invoice-management-manual-first-design.md`
  defining the world-class manual invoice-management layers before OCR/AI:
  document vault, invoice registry, capture, master data, workflow/review,
  disputes, receivables, alerts/tasks, audit, security, reporting, and later AI.
- `[x]` Added `docs/superpowers/plans/2026-07-02-manual-reliability-foundation.md`
  as Milestone 1 plan: draft recovery, duplicate warning, server-side filters,
  alert aging/filters, buyer requirement delete, and staff-friendly status labels.
- `[x]` Implemented first Milestone 1 slice: local worker capture draft
  persistence/resume/discard using Hive. Verified
  `puro flutter test test/capture/bundle_provider_test.dart` passes and
  `puro flutter analyze` remains at the existing 27-issue baseline.

## Phase 13 - Pilot review fixes: real OCR + manual reliability (2026-07-03)

Trigger: pilot review — OCR filled nothing and the form demanded too much
typing ("it should have taken everything on its own is the whole premise").

- `[x]` **Root cause of dead OCR**: the ocr-worker container had no volume
  mounts, so extraction activities could never read the files the api saved;
  every extraction silently ran in simulation mode (prod AND local dev,
  since the beginning). Fixed by sharing the storage volume + STORAGE_ROOT
  in both compose files. Verified live: the preview endpoint now returns
  real invoice number/GSTINs/amounts from a real photo in ~5s.
- `[x]` Manual reliability Milestone 1 completed (plan tasks 3-6):
  server-side owner invoice search/filters (q/status/buyer/date/open-issues),
  alert type+age filters with age_days and critical/warning priority,
  ADMIN delete for buyer document requirements, and staff-friendly status
  labels (Submitted / Waiting for Manager / Paid / Open / Overdue).
- `[x]` Confidence-driven autofill (ai-extraction-v1 thresholds, Textract as
  the provider): per-field confidence flows worker -> Go -> mobile; >=0.90
  fills with an AI-filled cue, 0.70-0.89 fills with a verify cue, <0.70 is
  skipped with a plain-language warning. No OpenAI key needed for this path.
- `[ ]` Full AI envelope provider (spec Phase 2, OpenAI/other LLM): blocked
  on choosing a provider + API key. Textract confidence path covers capture
  autofill in the meantime.
- `[x]` Deployed to pilot EC2 (2026-07-03): rebuilt api/worker/ocr-worker,
  no migration needed. Live smoke test: preview returns per-field
  confidence and correctly warned on a low-confidence total amount while
  the other five fields read at 91-99%. Alert filters + server search live.
- `[ ]` Sideload the new APK (app-release.apk, 56.9MB) onto the pilot device.
- `[x]` Implemented second Milestone 1 slice: duplicate invoice preflight
  warning before the worker reaches supporting documents. Added
  `GET /api/v1/mobile/invoices/duplicate-check`, tenant-scoped by seller GSTIN
  and invoice number with optional buyer GSTIN narrowing, plus a mobile
  confirmation dialog (`Go Back` / `Continue Anyway`). Verified
  `go test ./internal/api -run TestDuplicateInvoiceCheck -count=1`,
  `go build ./...`, `go vet ./...`,
  `puro flutter test test/capture/bundle_provider_test.dart test/capture/review_screen_test.dart`,
  and `puro flutter analyze` at the existing 27-issue baseline.
- `[x]` Photo quality warning gate for worker captures: local mobile analyzer
  checks lighting, blur, and framing before saving captured images. Bad photos
  show `Retake` / `Use Anyway`, so field work is not hard-blocked. Verified
  `puro flutter test test/capture/photo_quality_test.dart test/capture/bundle_provider_test.dart test/capture/review_screen_test.dart`
  and `puro flutter analyze`; analyzer baseline lowered from 27 to 26 after
  removing an existing camera async-context warning.
- `[x]` Password management for real staff rollout: users can change their own
  password from Settings, and ADMIN can reset a staff password by email.
  Backend routes are `POST /api/v1/auth/change-password` and
  `POST /api/v1/auth/users/reset-password`; both store bcrypt hashes only.
