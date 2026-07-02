# AGENTS.md — Meridian Invoice Capture

Instructions for AI coding agents (Claude, Codex, Cursor, etc.) working in
this repository. See [task.md](task.md) for current work-in-progress status —
check it before starting anything and update it as you go.

## What this is

A multi-tenant invoice digitization system for Meridian Brothers/Distributors,
a real distribution business. Not a public product — built for one
internal pilot. Two parts:

- **`backend/`** — Go API + Postgres + Temporal workflows + a Python OCR
  worker. Workers photograph invoices in the field; the backend reconciles
  them against expected purchase/buyer data and routes exceptions for
  manager/finance approval.
- **`mobile/`** — Flutter app (Android only, sideloaded, no Play Store). Two
  user-facing modes: capture (WORKER role) and an owner dashboard
  (ADMIN/MANAGER roles).

Other roots (`frontend/`, `data/`, the various root-level `.py` scripts and
`*.md` analysis docs) are earlier-phase artifacts — `frontend/` was an
abandoned Next.js dashboard, superseded by the mobile app's owner dashboard.
Don't assume they're current; check `task.md` and git history before
touching them.

## Repo layout

```
backend/
  cmd/api/         HTTP API server (port 8000)
  cmd/worker/       Temporal worker (reconciliation, ledger scans)
  cmd/migrate/      golang-migrate CLI wrapper
  cmd/tester/       manual/dev test harness, not part of the deployed stack
  internal/api/     HTTP handlers (api.go, owner_handlers.go, mobile_handlers.go, auth_handlers.go)
  internal/db/      Repository layer + struct defs (db.go) — read this for JSON field names
  internal/workflow/ Temporal workflows + rules.go (DSL for approval rules)
  internal/auth/    JWT + bcrypt password hashing
  python_worker/    OCR activities (activities.py) — real AWS Textract integration exists,
                    gated behind boto3 being installed; falls back to simulation otherwise
  db/migrations/    golang-migrate SQL, numbered sequentially — never edit a migration
                    that's already run anywhere; add a new one instead
mobile/
  lib/features/capture/   worker flow: camera -> review (manual data entry, NOT OCR) ->
                          checklist (supporting docs) -> sync_service (offline queue)
  lib/features/owner/     dashboard, invoice detail, disputes, gate entry, audit trail
  lib/features/admin/     buyer document requirements, approval rules (admin-only screens)
  lib/features/auth/      login
  lib/features/home/      worker landing screen
  lib/core/api/           Dio client, Endpoints (one static method per backend route)
  lib/core/models/        Hive-backed offline queue models (bundle.dart) + plain DTOs
deploy/
  docker-compose.prod.yml  production stack (postgres, temporal, temporal-ui, ocr-worker,
                            worker, api, migrate, caddy) — Caddy auto-provisions HTTPS
  Caddyfile
  .env.example             template; real .env lives only on the server + locally, gitignored
```

## Building & running

**Backend** (from `backend/`):
- `go build ./... && go vet ./...` — always run before considering Go changes done.
- `go test ./...` — needs a real Postgres + Temporal; there is no mock-everything
  path. If Docker isn't available locally, you can't run these — say so rather
  than claiming tests pass.
- Local dev stack: root `docker-compose.yml` (NOT `deploy/docker-compose.prod.yml`,
  which is the production-only variant with Caddy/secrets wiring).

**Mobile** (from `mobile/`):
- This machine uses **Puro** to manage the Flutter SDK — prefix commands with
  `puro`, e.g. `puro flutter analyze`, `puro flutter build apk --release`.
- `puro flutter analyze` after every change — compare against
  `mobile/analysis_baseline.txt` (a warning/info count) rather than expecting
  zero issues; CI enforces the same baseline, not a blanket suppression.
- `puro flutter build apk --release` takes several minutes (first build
  compiles native Gradle/R8 from scratch) — run it in the background and wait
  for the completion notification rather than polling.
- No `image_picker`/camera testing without a real device or emulator attached;
  `puro flutter devices` to check what's connected.

**Deploy**: see `deploy/.env.example` for required secrets (generate with the
`openssl rand` commands listed there). Bring up with
`docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env up -d --build`,
then `docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env run --rm migrate up`
before anything will accept real traffic — `app_user`'s Postgres role doesn't
exist until migrations run.

## Conventions established in this codebase (read before changing patterns)

- **Service classes take `Dio?` via constructor DI** (`Service({Dio? dio}) : _dio = dio ?? buildDio();`)
  — every mobile service class (`AuthNotifier`, `SyncService`, `OwnerService`)
  follows this so tests can inject a mock. Match it for new services.
- **Hive models need explicit `@HiveField(N, defaultValue: X)`** when adding a
  field to an existing `HiveObject` — omitting the default makes old persisted
  records crash on read (`null as Type` throws). Regenerate with build_runner
  after any `@HiveType`/`@HiveField` change.
- **The capture flow is manual data entry, not OCR.** Workers type invoice
  number/GSTIN/amounts themselves on the Review screen; the photo is stored
  as a record, not auto-extracted. Backend OCR activities
  (`extract_text_and_layout`, `extract_document_header` in `python_worker/activities.py`)
  exist and have working Textract integration, but currently run only as
  post-hoc backend-side validation (flagging mismatch exceptions), not to
  pre-fill the mobile form. See `task.md` Phase 4 for the plan to wire this up.
- **Buyers are a small, fixed list** (4 as of this writing — Flipkart, Max
  Hypermarket, Airplaza/Vishal Mega Mart, Innovative Retail Concepts). Buyer
  document requirements (`buyer_document_requirements` table) are mostly
  unconfigured — check before assuming a buyer's requirement list is complete.
- **Backend route role-gating is in `internal/api/api.go`'s `RegisterRoutes`** —
  always check `requireRole(...)` there before building a mobile screen that
  assumes a role can call an endpoint.
- **Migrations are immutable once applied anywhere** — never edit a numbered
  migration file that could have already run; add a new one.
- **Git on this Windows box has `core.autocrlf=true`**, which makes `gofmt -l`
  report spurious diffs locally on files that are actually fine in the
  committed (LF) content CI sees. Don't "fix" gofmt issues without checking
  `git stash` first to rule this out.

## Pilot server access

Production stack runs on a single EC2 instance behind Caddy (auto HTTPS via
sslip.io + Let's Encrypt). Connection details (host, SSH key path, AWS
profile name) and all real secrets are intentionally **not** written here —
they're either in the operator's local shell history/notes or in
`deploy/.env` (gitignored, never committed). If you need them and don't have
them, ask the user rather than guessing or regenerating credentials, since
regenerating secrets on a live pilot invalidates existing sessions/passwords.
