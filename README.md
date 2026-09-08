# Meridian Distributors — Invoice Capture & Distributor Ops Platform

A multi-tenant invoice digitization + distributor operations system built for
**Meridian Brothers / Meridian Distributors (Meridian Gurgaon)** — a real distribution
business. This is an internal pilot, **not a public product** (Android only,
sideloaded APK, no Play Store).

Workers photograph invoices in the field with a phone; the backend reconciles
them against expected purchase/buyer data and routes exceptions (short
receipts, missing documents, mismatches) to manager/finance for approval —
with a full audit trail.

> **Status:** private pilot, actively developed on the
> `feat/mobile-capture-app` branch (default branch). See
> [task.md](task.md) for the live status tracker.

---

## Key capabilities

| Area | What it does |
| :--- | :--- |
| **Capture (mobile)** | Camera → review screen → supporting-document checklist → offline queue → sync. Manual data entry by the worker, with **AI-assisted autofill**. Draft recovery, duplicate-invoice warning, photo quality gate (blur/lighting/framing). |
| **AI extraction** | `Claude (Opus, vision) → AWS Textract → simulation` fallback chain in the OCR worker. Multi-page invoices (up to 6 pages), per-field confidence, plain-language warnings; fills the form at ≥0.90 confidence ("AI-filled" cue), 0.70–0.89 ("verify" cue), below that skips. |
| **Master-data autofill** | **1,285 retailer records** extracted from 8 legacy Excel series masters (CAD / HAL0 / MORDE00 / NIV / DBR0 / IN00 / REHIN / HYGIN0) into a `master_retailers` table + JSON/CSV exports. On-device **fuzzy matching** (Levenshtein + token-set) resolves noisy OCR text to the exact seller entity, buyer, GSTIN, route, and credit terms. |
| **Camera quality** | `ResolutionPreset.max` (full sensor), 4K UHD (3840 px) at 92% JPEG, dynamic contrast + gamma for faint dot-matrix/thermal prints, touch-to-focus, flash-torch toggle. |
| **Owner dashboard (mobile)** | Dashboard, invoice detail, disputes, gate entry, receivables with aging buckets, sales reports, alerts, approval workflows, in-app document viewer, audit trail. |
| **Approvals & exceptions** | Manager/finance approval chains, dispute creation/resolution, buyer document requirements, admin-managed matching rules. Exceptions → alerts feed. |
| **Backend workflows** | Temporal workflows + rules DSL (`internal/workflow/rules.go`) for reconciliation and ledger scans. |

---

## Architecture

```
┌───────────────────────┐     ┌──────────────────────────────────────┐
│  Mobile (Flutter)     │     │  Backend (Go, port 8000)             │
│  Android-only,        │ ──▶ │  - HTTP API (internal/api)           │
│  offline-friendly     │     │  - JWT + bcrypt auth (internal/auth) │
│  Hive offline queue   │     │  - Postgres repo layer (internal/db) │
└───────────────────────┘     │  - Temporal workflows + activities  │
                              └───────┬──────────────────────────────┘
                                      │
                    ┌─────────────────┼──────────────────┐
                    ▼                 ▼                  ▼
             ┌────────────┐   ┌───────────────┐   ┌──────────────────┐
             │ PostgreSQL │   │  Temporal     │   │ Python OCR worker│
             │ multi-     │   │  workers + UI │   │ activities.py    │
             │ tenant RLS │   │               │   │ Claude→Textract  │
             └────────────┘   └───────────────┘   └──────────────────┘
```

**Tenancy & security:** organizations → entities (GSTINs) → users with roles
(WORKER / REVIEWER / MANAGER / FINANCE / ADMIN), row-level security,
JWT + bcrypt, and role-gated API routes. Documents are immutable,
version-stamped files with an append-only audit trail.

---

## Repo layout

```
backend/                 Go API + Temporal worker + OCR worker
  cmd/api/               HTTP API server (port 8000)
  cmd/worker/            Temporal worker (reconciliation, ledger scans)
  cmd/migrate/           golang-migrate CLI wrapper
  internal/api/          HTTP handlers (api.go, owner_handlers.go, mobile_handlers.go, auth_handlers.go)
  internal/db/           Repository + struct defs — JSON field names live here
  internal/workflow/     Temporal workflows + rules.go (approval-rule DSL)
  internal/auth/         JWT + bcrypt
  python_worker/         OCR activities (activities.py, Claude + Textract)
  db/migrations/         numbered SQL; immutable once applied anywhere
mobile/                  Flutter app (Android)
  lib/features/capture/  worker flow: camera → review → checklist → sync
  lib/features/owner/    dashboard, invoice detail, disputes, gate entry, audit trail
  lib/features/admin/    buyer doc requirements, approval rules
  lib/features/auth/     login · lib/features/home/ worker landing
  lib/core/api/          Dio client + Endpoints (one method per backend route)
  lib/core/models/       Hive offline-queue models + DTOs
deploy/                  Production stack (docker-compose.prod.yml + Caddyfile)
data/                    Invoice photos + master-retailer JSON/CSV exports
docs/                    Founder walkthrough + design specs/plans
*.md (root)              Analysis docs, task.md, README.md, AGENTS.md
```

> `frontend/` is an **abandoned Next.js dashboard** — superseded by the mobile
> owner dashboard. Don't assume it's current.

---

## Tech stack

| Layer | Tech |
| :--- | :--- |
| Backend | Go, `net/http`, golang-migrate |
| Database | PostgreSQL (multi-tenant, RLS, immutable document rows) |
| Workflows | Temporal (reconciliation, ledger scans, approval routing) |
| OCR/AI | Python + Claude (Anthropic SDK, structured JSON) → AWS Textract fallback |
| Mobile | Flutter (Riverpod, go_router), Hive offline queue, Dio, `flutter_secure_storage` |
| Infra | Docker Compose, Caddy (auto TLS), single EC2 pilot |

---

## Getting started

### Local stack (backend)

Requires **Docker** (Postgres + Temporal) and **Go**.

```bash
cd backend
go build ./... && go vet ./...     # always before considering Go changes done
go test ./...                       # needs live Postgres + Temporal (no mock-everything path)
```

Local dev stack lives at the repo root (NOT `deploy/`, which is the
production-only variant):

```bash
docker-compose up -d   # repo root: postgres, temporal, ocr-worker, worker, api
```

### Mobile (Flutter)

This repo uses **Puro** for the Flutter SDK (`puro flutter …`):

```bash
cd mobile
puro flutter analyze                # compare against mobile/analysis_baseline.txt
puro flutter test                   # 100+ unit, widget & permutation tests
puro flutter build apk --release   # ~minutes; outputs in build/app/outputs/flutter-apk/
```

The app defaults to **`https://203.0.113.10`** (editable in the app's Settings
screen; persisted in encrypted secure storage). Camera tests require a real
device — `puro flutter devices`.

---

## Deployment (pilot)

Production runs on a single EC2 instance behind Caddy.

```bash
# Secrets live in deploy/.env (gitignored — copy deploy/.env.example first)
docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env up -d --build
docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env run --rm migrate up
```

Key notes:

- Run migrations **before** opening to traffic: the `app_user` Postgres role
  doesn't exist until the migrations create it.
- Caddy auto-provisions HTTPS and also serves a self-signed cert on the raw IP
  (`https://203.0.113.10`) because some Indian ISPs block sslip.io wildcard
  DNS — the app's `badCertificateCallback` accepts it.
- Release APK downloads at `https://203.0.113.10/downloads/app-release.apk` so
  the pilot device pulls updates without re-sharing files.
- AI extraction needs `ANTHROPIC_API_KEY` in `deploy/.env` (Claude primary,
  Textract/simulation fallback).
- Never edit an already-applied migration — add a new numbered file instead.

---

## Documentation index

| Doc | What it is |
| :--- | :--- |
| [`task.md`](task.md) | Live status tracker (current phase, verified items, gaps) |
| [`AGENTS.md`](AGENTS.md) | Repo agent guide — read before changing patterns |
| [`walkthrough.md`](walkthrough.md) | End-to-end build + verification walkthrough |
| [`project_changes_and_optimizations_summary.md`](project_changes_and_optimizations_summary.md) | Session changelog + rationale |
| [`series_master_autofill_guide.md`](series_master_autofill_guide.md) | Master catalog + autofill architecture |
| [`full_extracted_series_master_data.md`](full_extracted_series_master_data.md) | Extracted dataset catalog + seed guide |
| [`camera_quality_optimization_guide.md`](camera_quality_optimization_guide.md) | 4K camera + faint-print pipeline |
| [`docs/founder_app_walkthrough.md`](docs/founder_app_walkthrough.md) | Non-technical founder demo script |