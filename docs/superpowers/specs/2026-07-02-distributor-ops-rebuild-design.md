# Distributor Ops Rebuild — Design

Date: 2026-07-02
Status: Approved (user approved pillars: domain model fix, receivables/collections,
delivery reconciliation, sales reporting; scope: mobile + backend; approach:
shell rebuild + reuse).

## Why

`invoice_extraction.md` (60/61 source documents logged) established what the
business actually is: a family FMCG distribution group in Gurgaon operating
three separate legal firms (Meridian Brothers, Meridian Distributors, DBR
Gurgaon), each an authorized distributor for multiple principals (Mondelez,
Nestlé, HUL, Britannia, Reckitt, Haleon, Nivea, HELL Energy, Morde, dairy).
Each principal has its own invoice series (CAD, DBR, GST, HAL, HELL, HYGIN,
REHIN, NIV, A26, BIB, MORDE) and its own PO per buyer. Buyers span four
channels — GT (small stores), MT (Vishal Mega Mart, Max Hypermarket, V-Mart),
E-com/quick-commerce (Flipkart, Zepto), hospitality/industrial — with multiple
branches under one GSTIN, buyer-specific proof-of-receipt processes, credit
terms from 0 to 365 days, and salesman/beat/van field structure.

The current system captures and files invoices well (offline capture, OCR
autofill, buyer-specific proof checklists, exceptions, disputes, audit chain)
but cannot answer the distributor's three daily questions:

1. **Who owes us what, and what's overdue?** (most invoices are CREDIT — no
   receivables/payments tracking exists)
2. **Did the buyer accept everything we billed?** (gate entries and disputes
   exist but are not connected — mismatches don't automatically open disputes)
3. **How is the business doing?** (no sales reporting by principal, buyer,
   channel, firm, or salesman — the schema can't even express those groupings)

## Product structure

Two personas, two app shells:

- **Worker** — captures invoices fast, attaches buyer-required proofs, works
  offline, fixes own exceptions.
- **Owner side** (ADMIN / MANAGER / FINANCE / REVIEWER) — business health,
  exceptions, delivery reconciliation, receivables, master data.

## Navigation (mobile)

Replace the flat route list with two role-scoped bottom-tab shells using
go_router `StatefulShellRoute.indexedStack`:

- **Worker shell:** `Capture | Queue | My Invoices` — settings/logout in the
  app bar.
- **Owner shell:** `Dashboard | Invoices | Receivables | Alerts | More` —
  More holds Buyers & branches, Buyer requirements, Rules, Principals &
  series, Settings. Owner-side users also get a Capture action on the
  Dashboard (admins capture during the pilot).

The camera → review → checklist capture flow stays a full-screen push stack
above the shell. `AppBackScope` double-back-to-exit applies on tab roots; tab
switching preserves per-tab state. Existing screens are reused inside the
shells; only their entry points and back fallbacks change.

## Domain model (additive migrations, pattern of 000003)

`entities` already models the Meridian firms; `buyers` (GSTIN-keyed) and
`invoices.invoice_series` already exist. New migration adds:

- **`principals`** — id, organization_id, name, code. Seeded from the
  extraction log (Mondelez, Nestlé, HUL, Reckitt, Haleon, Nivea, HELL Energy,
  Morde, Britannia, dairy/CBB).
- **`invoice_series_registry`** — series prefix → (entity_id, principal_id
  nullable). Mappings are loose by design: REHIN covers Harpic and Mortein;
  HAL covers the whole Haleon family.
- **`buyer_branches`** — buyer_id, name, code (e.g. "B-04 Badshahpur"),
  address JSONB, gate_entry_prefix. Confirmed multi-branch-per-GSTIN buyers:
  Vishal Mega Mart, Flipkart, Zepto, Superwell.
- **`buyers`** gains `sales_channel` (GT / MT / ECOM / HOSPITALITY /
  INDUSTRIAL, nullable) and `default_payment_terms_days` (nullable).
- **`invoices`** gain nullable `principal_id`, `buyer_branch_id`,
  `payment_type` (CASH/CREDIT), `payment_terms_days`, `due_date` (computed at
  ingest: invoice_date + terms), `salesman`, `beat`.
- **`payments`** — invoice_id, amount, paid_on, mode (CASH/UPI/CHEQUE/NEFT/
  OTHER), reference, notes, recorded_by, created_at. Partial payments
  allowed. RLS + app_user grants like every tenant table.

All columns nullable/additive; nothing existing is altered or dropped.
Legacy invoices with NULL payment_type are "unclassified": never counted
overdue, shown separately — no false alarms on old data.

## Capture flow additions (worker)

Review screen gains:

- **Payment type + terms** — Cash/Credit toggle; terms days prefilled from
  the buyer's `default_payment_terms_days`, editable.
- **Principal/series auto-detect** — invoice-number prefix matched against
  the cached series registry; result shown as an editable dropdown.
- **Branch picker** — shown only when the selected buyer has branches.

OCR autofill is unchanged. New fields ride the existing offline bundle/sync
path (Hive fields get explicit defaults so old queued bundles don't crash).

## Receivables

Backend:

- `GET /api/v1/owner/receivables` — per-buyer outstanding total, overdue
  total, aging buckets (current / 1–30 / 31–60 / 60+ days past due),
  open-invoice count. CREDIT invoices only; balance = gross_amount +
  tax_amount − Σ payments.
- `GET /api/v1/owner/receivables/{buyer_id}` — open invoices with paid-so-far,
  balance, due date, days overdue.
- `POST /api/v1/invoices/{id}/payments` (FINANCE/MANAGER/ADMIN) — validates
  amount > 0 and ≤ remaining balance; writes audit event.
- `GET /api/v1/invoices/{id}/payments` — payment history.
- Overdue invoices appear as a new alert type in the existing
  `GET /owner/alerts` feed.

Mobile: Receivables tab — total outstanding/overdue header, buyers ranked by
outstanding with aging chips → buyer detail invoice list → record-payment
sheet (amount, date, mode, reference). Invoice detail gains a Payments
section. Online-only: offline shows last-fetched data with a banner; payment
recording requires connectivity (no offline payment queue — double-entry risk
is not worth it in v1).

## Delivery reconciliation

When a gate entry is recorded whose accepted qty/amount mismatches the
invoice, the backend auto-opens a dispute (today dispute creation is manual).
Invoice detail gets a reconciliation strip: Invoiced → Accepted → Credit note
→ Net receivable. Existing dispute lifecycle (PATCH status, credit-note
upload) is reused unchanged. Unreconciled mismatches feed the alerts screen.

## Reporting

Backend: `GET /api/v1/owner/reports/sales?from=&to=&group_by=principal|buyer|
channel|entity|salesman` — SQL GROUP BY over invoices; returns rows of
{key_id, key_label, invoice_count, gross, tax, total}.

Mobile Dashboard tab: period selector (today / this week / this month), KPI
cards (sales, invoice count, outstanding, open exceptions), group-by
breakdown rendered as a ranked bar list. Existing exception counts remain.

## Master data

More tab (ADMIN-gated): principals & series registry CRUD, buyer editing
(channel, default terms, branches), plus the existing buyer-requirements and
rules screens relocated. Backend: CRUD endpoints for principals, series
registry, buyer branches; PATCH buyers.

## Roles

FINANCE gains payment recording. REVIEWER is read-only on receivables.
All existing role gates unchanged.

## Error handling

- Back navigation never silently loses in-progress capture data (existing
  confirmations preserved).
- Receivables/reports handle empty, loading, error, and offline-with-cache
  states.
- Payment validation errors (over-balance, non-positive) return 400 with a
  message the mobile sheet surfaces inline.
- Series auto-detect failing (unknown prefix) leaves principal unset — never
  blocks submission.

## Testing

- Go: unit tests for receivables aggregation/aging math, payment validation,
  auto-dispute trigger; integration tests on the existing
  Postgres+Temporal harness for new endpoints and RLS.
- Flutter: widget tests for shell navigation and back behavior, receivables
  screens and payment sheet with injected Dio mocks, series-detect unit
  tests; `puro flutter analyze` compared against `mobile/analysis_baseline.txt`.
- Manual smoke checklist updated for tab navigation and payment recording.

## Out of scope

- Reviving the abandoned `frontend/` Next.js dashboard.
- Push/SMS/email notifications.
- IRN/e-invoice generation and GST filing exports.
- Line-item-level extraction.
- Worker batch mode.
- Data deletion/retention workflows.
- Offline payment recording.
