# Distributor Ops Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the invoice-capture pilot into a distributor operations product: model principals/series/branches/payment-terms, add receivables + payment recording, auto-open disputes on gate-entry mismatches, add sales reporting, and rebuild mobile navigation into role-based tab shells.

**Architecture:** Additive Postgres migration (000009) extends the existing RLS'd schema; new Go repository methods + handlers follow the `owner_handlers.go` patterns and are registered in `api.go`'s `RegisterRoutes` with the existing `requireRole` gates. Mobile keeps every existing screen but re-homes them inside two `StatefulShellRoute.indexedStack` shells (worker / owner); new Riverpod providers extend `OwnerService` (Dio-injectable, per convention).

**Tech Stack:** Go 1.25 + pgx + Temporal, golang-migrate SQL, Flutter + Riverpod + GoRouter + Hive, `flutter_test`, existing Postgres+Temporal integration harness (`integration_harness_test.go`).

## Global Constraints

- Migrations are immutable once applied — new migration is `000009_*`, never edit 000001–000008.
- All schema changes additive/nullable; nothing existing altered or dropped.
- Every new tenant table gets RLS policy + `GRANT SELECT, INSERT, UPDATE, DELETE ... TO app_user` (pattern of 000003/000005).
- `invoices.gross_amount` stores the BILL TOTAL (see `handleUploadLedgerInvoice`); receivable balance = `gross_amount` − Σ payments. Do not add tax_amount on top.
- Legacy invoices (`payment_type IS NULL`) are never counted outstanding/overdue.
- Backend: `go build ./... && go vet ./...` before done; integration tests need Docker Postgres+Temporal — if unavailable, say so.
- Mobile: prefix Flutter commands with `puro`; `puro flutter analyze` must match `mobile/analysis_baseline.txt` (27); Hive fields added to existing types need explicit `defaultValue`; regenerate `bundle.g.dart` with build_runner.
- Mobile service classes take `Dio?` via constructor DI.
- Role gates: payments POST = FINANCE/MANAGER/ADMIN; master-data writes = ADMIN; receivables/reports GET = ADMIN/MANAGER/FINANCE/REVIEWER.
- Do not touch abandoned `frontend/`.

---

### Task 1: Migration 000009 — domain model tables + seed

**Files:**
- Create: `backend/db/migrations/000009_distributor_domain.up.sql`
- Create: `backend/db/migrations/000009_distributor_domain.down.sql`

**Interfaces:**
- Produces tables: `principals(id, organization_id, name, code)`, `invoice_series_registry(id, organization_id, series_prefix, entity_id, principal_id)`, `buyer_branches(id, organization_id, buyer_id, name, code, address, gate_entry_prefix)`, `invoice_payments(id, organization_id, invoice_id, amount, paid_on, mode, reference, notes, recorded_by, created_at)`
- Produces columns: `buyers.sales_channel`, `buyers.default_payment_terms_days`, `invoices.{principal_id, buyer_branch_id, payment_type, payment_terms_days, due_date, salesman, beat}`

- [ ] **Step 1: Write the up migration** — full content:

```sql
-- Distributor domain: principals, series registry, buyer branches,
-- payment terms, and payments. Everything additive; legacy rows keep NULLs.

CREATE TABLE IF NOT EXISTS principals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_principal_name UNIQUE (organization_id, name)
);
CREATE INDEX IF NOT EXISTS idx_principals_org ON principals(organization_id);

CREATE TABLE IF NOT EXISTS invoice_series_registry (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    series_prefix VARCHAR(20) NOT NULL,
    entity_id UUID REFERENCES entities(id),
    principal_id UUID REFERENCES principals(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_series_prefix UNIQUE (organization_id, series_prefix)
);

CREATE TABLE IF NOT EXISTS buyer_branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    buyer_id UUID NOT NULL REFERENCES buyers(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50),
    address JSONB,
    gate_entry_prefix VARCHAR(20),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_buyer_branch UNIQUE (organization_id, buyer_id, name)
);
CREATE INDEX IF NOT EXISTS idx_buyer_branches_buyer ON buyer_branches(buyer_id);

ALTER TABLE buyers ADD COLUMN IF NOT EXISTS sales_channel VARCHAR(20);
ALTER TABLE buyers DROP CONSTRAINT IF EXISTS buyers_sales_channel_check;
ALTER TABLE buyers ADD CONSTRAINT buyers_sales_channel_check
    CHECK (sales_channel IS NULL OR sales_channel IN ('GT','MT','ECOM','HOSPITALITY','INDUSTRIAL'));
ALTER TABLE buyers ADD COLUMN IF NOT EXISTS default_payment_terms_days INT;

ALTER TABLE invoices ADD COLUMN IF NOT EXISTS principal_id UUID;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS buyer_branch_id UUID;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_type VARCHAR(10);
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_payment_type_check;
ALTER TABLE invoices ADD CONSTRAINT invoices_payment_type_check
    CHECK (payment_type IS NULL OR payment_type IN ('CASH','CREDIT'));
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_terms_days INT;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS salesman VARCHAR(255);
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS beat VARCHAR(255);
CREATE INDEX IF NOT EXISTS idx_invoices_receivable
    ON invoices(organization_id, payment_type, due_date);

CREATE TABLE IF NOT EXISTS invoice_payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL,
    amount NUMERIC(15,4) NOT NULL CHECK (amount > 0),
    paid_on DATE NOT NULL,
    mode VARCHAR(20) NOT NULL CHECK (mode IN ('CASH','UPI','CHEQUE','NEFT','OTHER')),
    reference VARCHAR(255),
    notes TEXT,
    recorded_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_invoice_payments_invoice ON invoice_payments(invoice_id);

ALTER TABLE principals ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_series_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE buyer_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_principals_policy ON principals
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
CREATE POLICY tenant_series_registry_policy ON invoice_series_registry
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
CREATE POLICY tenant_buyer_branches_policy ON buyer_branches
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
CREATE POLICY tenant_invoice_payments_policy ON invoice_payments
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

GRANT SELECT, INSERT, UPDATE, DELETE ON principals TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON invoice_series_registry TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON buyer_branches TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON invoice_payments TO app_user;

-- Seed principals + series registry for any org that owns the Meridian
-- Brothers entity (the real pilot org), keyed by GSTIN like 000008 does.
INSERT INTO principals (organization_id, name, code)
SELECT e.organization_id, p.name, p.code
FROM entities e
CROSS JOIN (VALUES
    ('Mondelez', 'CAD'), ('Nestle', 'DBR'), ('HUL', 'HUL'),
    ('Britannia', 'BRIT'), ('Reckitt', 'RB'), ('Haleon', 'HAL'),
    ('Nivea', 'NIV'), ('HELL Energy', 'HELL'), ('Morde', 'MORDE')
) AS p(name, code)
WHERE e.tax_identifier = '06AAAAA0003A1Z3'
ON CONFLICT (organization_id, name) DO NOTHING;

-- Series -> (entity, principal). Entity GSTINs: Meridian Brothers
-- 06AAAAA0003A1Z3, Meridian Distributors 06AAAAA0015A1ZF, Meridian Gurgaon
-- 06AAAAA0017A1ZH. BIB left unmapped to a principal (evidence conflicting).
INSERT INTO invoice_series_registry (organization_id, series_prefix, entity_id, principal_id)
SELECT e.organization_id, m.prefix, e.id, pr.id
FROM (VALUES
    ('CAD',   '06AAAAA0003A1Z3', 'Mondelez'),
    ('DBR',   '06AAAAA0003A1Z3', 'Nestle'),
    ('MORDE', '06AAAAA0003A1Z3', 'Morde'),
    ('A26',   '06AAAAA0003A1Z3', 'Britannia'),
    ('NIV',   '06AAAAA0003A1Z3', 'Nivea'),
    ('GST',   '06AAAAA0015A1ZF', 'HUL'),
    ('HAL',   '06AAAAA0017A1ZH', 'Haleon'),
    ('HELL',  '06AAAAA0017A1ZH', 'HELL Energy'),
    ('HYGIN', '06AAAAA0017A1ZH', 'Reckitt'),
    ('REHIN', '06AAAAA0017A1ZH', 'Reckitt')
) AS m(prefix, gstin, principal_name)
JOIN entities e ON e.tax_identifier = m.gstin
LEFT JOIN principals pr ON pr.organization_id = e.organization_id AND pr.name = m.principal_name
ON CONFLICT (organization_id, series_prefix) DO NOTHING;

INSERT INTO invoice_series_registry (organization_id, series_prefix, entity_id, principal_id)
SELECT e.organization_id, 'BIB', e.id, NULL
FROM entities e WHERE e.tax_identifier = '06AAAAA0017A1ZH'
ON CONFLICT (organization_id, series_prefix) DO NOTHING;
```

- [ ] **Step 2: Write the down migration** — drop the four tables, the two buyer columns, the seven invoice columns, and `idx_invoices_receivable` (reverse order, `IF EXISTS` everywhere).

- [ ] **Step 3: Verify SQL applies** — if Docker Postgres is up: run migrate up (see AGENTS.md); otherwise verify via the integration test suite in Task 2 which runs migrations.

- [ ] **Step 4: Commit** — `git commit -m "feat(db): distributor domain migration 000009 - principals, series, branches, payments"`

---

### Task 2: Repository layer — structs + queries

**Files:**
- Modify: `backend/internal/db/db.go` (Invoice struct ~line 114, Buyer struct ~line 137, CreateInvoice ~470, invoice SELECTs; append new sections at end)

**Interfaces (produces — later tasks consume exactly these):**

```go
type Principal struct { ID, OrganizationID, Name string; Code *string }
type SeriesRegistryEntry struct {
    ID, SeriesPrefix string
    EntityID, EntityName, PrincipalID, PrincipalName *string
}
type BuyerBranch struct {
    ID, BuyerID, Name string
    Code, GateEntryPrefix *string
    Address []byte
}
type InvoicePayment struct {
    ID, InvoiceID, Mode string
    Amount float64
    PaidOn time.Time
    Reference, Notes, RecordedBy *string
    CreatedAt time.Time
}
type BuyerReceivable struct {
    BuyerID, BuyerName, BuyerGstin string
    Outstanding, Overdue float64
    BucketCurrent, Bucket1To30, Bucket31To60, Bucket60Plus float64
    OpenInvoices int
}
type ReceivableInvoice struct {
    InvoiceID, InvoiceNumber string
    InvoiceDate time.Time
    DueDate *time.Time
    Total, Paid, Balance float64
    DaysOverdue int
}
type SalesReportRow struct {
    KeyID, KeyLabel string
    InvoiceCount int
    Gross, Tax float64  // Gross = bill total sum, Tax = tax sum
}

// Invoice struct gains: PrincipalID, BuyerBranchID, PaymentType *string;
// PaymentTermsDays *int; DueDate *time.Time; Salesman, Beat *string
// Buyer struct gains: SalesChannel *string; DefaultPaymentTermsDays *int

func (r *Repository) CreatePrincipal(ctx, tenantID, name, code string) (*Principal, error)
func (r *Repository) ListPrincipals(ctx, tenantID string) ([]*Principal, error)
func (r *Repository) DeletePrincipal(ctx, tenantID, id string) error
func (r *Repository) UpsertSeriesEntry(ctx, tenantID, prefix string, entityID, principalID *string) (*SeriesRegistryEntry, error)
func (r *Repository) ListSeriesRegistry(ctx, tenantID string) ([]*SeriesRegistryEntry, error)
func (r *Repository) DeleteSeriesEntry(ctx, tenantID, id string) error
func (r *Repository) CreateBuyerBranch(ctx, tenantID, buyerID, name string, code, gateEntryPrefix *string, address []byte) (*BuyerBranch, error)
func (r *Repository) ListBuyerBranches(ctx, tenantID, buyerID string) ([]*BuyerBranch, error)  // buyerID "" = all
func (r *Repository) DeleteBuyerBranch(ctx, tenantID, id string) error
func (r *Repository) UpdateBuyerMeta(ctx, tenantID, buyerID string, salesChannel *string, defaultTermsDays *int) error
func (r *Repository) CreatePayment(ctx, tenantID string, p *InvoicePayment) error  // inside WithTx: SELECT invoice total + SUM(existing payments); reject if p.Amount > balance+0.005
func (r *Repository) ListPaymentsByInvoice(ctx, tenantID, invoiceID string) ([]*InvoicePayment, error)
func (r *Repository) GetReceivablesSummary(ctx, tenantID string) ([]*BuyerReceivable, error)
func (r *Repository) ListReceivableInvoices(ctx, tenantID, buyerID string) ([]*ReceivableInvoice, error)
func (r *Repository) GetSalesReport(ctx, tenantID string, from, to time.Time, groupBy string) ([]*SalesReportRow, error)
func (r *Repository) ListOverdueInvoices(ctx, tenantID string) ([]*ReceivableInvoice, error)  // feeds alerts
```

- [ ] **Step 1: Extend Invoice/Buyer structs and CreateInvoice/Get/List column lists** with the new nullable columns.
- [ ] **Step 2: Implement master-data + payment methods** following existing method style (`WithTx`, `set_config`, RETURNING id).
- [ ] **Step 3: Implement the receivables aggregation** — core query:

```sql
SELECT b.id, b.name, b.gstin,
  COALESCE(SUM(i.gross_amount - COALESCE(p.paid,0)),0) AS outstanding,
  COALESCE(SUM(CASE WHEN i.due_date < CURRENT_DATE THEN i.gross_amount - COALESCE(p.paid,0) ELSE 0 END),0) AS overdue,
  COALESCE(SUM(CASE WHEN i.due_date >= CURRENT_DATE OR i.due_date IS NULL THEN i.gross_amount - COALESCE(p.paid,0) ELSE 0 END),0) AS bucket_current,
  COALESCE(SUM(CASE WHEN CURRENT_DATE - i.due_date BETWEEN 1 AND 30 THEN i.gross_amount - COALESCE(p.paid,0) ELSE 0 END),0) AS bucket_1_30,
  COALESCE(SUM(CASE WHEN CURRENT_DATE - i.due_date BETWEEN 31 AND 60 THEN i.gross_amount - COALESCE(p.paid,0) ELSE 0 END),0) AS bucket_31_60,
  COALESCE(SUM(CASE WHEN CURRENT_DATE - i.due_date > 60 THEN i.gross_amount - COALESCE(p.paid,0) ELSE 0 END),0) AS bucket_60_plus,
  COUNT(*) AS open_invoices
FROM invoices i
JOIN buyers b ON b.id = i.buyer_id
LEFT JOIN (SELECT invoice_id, SUM(amount) AS paid FROM invoice_payments GROUP BY invoice_id) p
  ON p.invoice_id = i.id
WHERE i.payment_type = 'CREDIT'
  AND i.gross_amount - COALESCE(p.paid,0) > 0.005
GROUP BY b.id, b.name, b.gstin
ORDER BY outstanding DESC
```

- [ ] **Step 4: Implement GetSalesReport** — `groupBy` whitelist maps to join/label expression (principal → `LEFT JOIN principals`, buyer → `LEFT JOIN buyers`, channel → `buyers.sales_channel`, entity → `JOIN entities`, salesman → `i.salesman`); reject any other value with an error. Sum `gross_amount` as total sales, `tax_amount` as tax, count invoices, `WHERE i.invoice_date BETWEEN $from AND $to`, label NULL keys `'Unassigned'`.
- [ ] **Step 5: `go build ./... && go vet ./...`** — expect clean.
- [ ] **Step 6: Commit** — `feat(db): repository support for principals, branches, payments, receivables, reports`

---

### Task 3: Receivables + payments + reports + master-data endpoints, auto-dispute, overdue alerts

**Files:**
- Create: `backend/internal/api/receivables_handlers.go`
- Create: `backend/internal/api/master_data_handlers.go`
- Modify: `backend/internal/api/api.go` (RegisterRoutes; `handleUploadLedgerInvoice`; `handleSetGateEntry` in whichever file holds it)
- Modify: `backend/internal/db/db.go` (`GetOpenAlerts` union arm)
- Test: `backend/internal/api/receivables_integration_test.go`
- Test: `backend/internal/api/master_data_integration_test.go`

**Interfaces (routes produced):**

```
GET    /api/v1/owner/receivables                     -> {"total_outstanding":n,"total_overdue":n,"buyers":[BuyerReceivable...]}
GET    /api/v1/owner/receivables/{buyer_id}          -> {"buyer":{...},"invoices":[ReceivableInvoice...]}
POST   /api/v1/invoices/{id}/payments   (F/M/A)      <- {"amount":n,"paid_on":"YYYY-MM-DD","mode":"UPI","reference":"","notes":""} -> 201 payment | 400 over-balance
GET    /api/v1/invoices/{id}/payments                -> {"payments":[...]}
GET    /api/v1/owner/reports/sales?from&to&group_by  -> {"rows":[SalesReportRow...]} (group_by whitelist else 400)
GET    /api/v1/principals                             (all authed)
POST   /api/v1/principals               (ADMIN)      <- {"name":"","code":""}
DELETE /api/v1/principals/{id}          (ADMIN)
GET    /api/v1/series-registry                        (all authed; mobile caches for prefix detect)
POST   /api/v1/series-registry          (ADMIN)      <- {"series_prefix":"","entity_id":"","principal_id":""}
DELETE /api/v1/series-registry/{id}     (ADMIN)
GET    /api/v1/buyers/{id}/branches                   (all authed)
POST   /api/v1/buyers/{id}/branches     (ADMIN)      <- {"name":"","code":"","gate_entry_prefix":"","address":{}}
DELETE /api/v1/buyers/branches/{id}     (ADMIN)
PATCH  /api/v1/buyers/{id}              (ADMIN)      <- {"sales_channel":"GT","default_payment_terms_days":30}
```

Ledger upload accepts new optional form fields: `payment_type` (CASH|CREDIT), `payment_terms_days`, `buyer_branch_id`, `salesman`, `beat`. If CREDIT: `due_date = invoice_date + terms` (terms default: buyer's `default_payment_terms_days`, else 0). Principal resolved by longest-prefix match of `invoice_number` against series registry (also fills `invoice_series` when absent).

Auto-dispute: after gate-entry upsert, if short receipt (accepted_qty < invoice_qty, or discrepancy_amount > 0, or is_short_receipt) and no OPEN/OWNER_REVIEWING dispute exists for the invoice, create a `SHORT_RECEIPT` dispute (description auto-generated, raised_by = current user) + audit event.

Overdue alerts: `GetOpenAlerts` gains a third union arm from `ListOverdueInvoices` with `alert_type='OVERDUE_INVOICE'`.

- [ ] **Step 1: Write failing integration tests** — receivables happy path (CREDIT invoice with terms → shows in summary; record partial payment → balance drops; overpay → 400; CASH invoice absent; legacy NULL absent), auto-dispute trigger, reports group_by=principal, master-data CRUD + role gates (worker POST principal → 403).
- [ ] **Step 2: Run tests to verify they fail** — `go test ./internal/api/ -run 'Receivables|MasterData' -v` (needs Docker stack).
- [ ] **Step 3: Implement handlers + route registration + ledger-upload/gate-entry extensions.**
- [ ] **Step 4: Run tests to verify they pass; `go build ./... && go vet ./...`.**
- [ ] **Step 5: Commit** — `feat(api): receivables, payments, sales reports, master data, auto-dispute, overdue alerts`

---

### Task 4: Mobile data layer — endpoints, models, services, series detect, Hive fields

**Files:**
- Modify: `mobile/lib/core/api/endpoints.dart`
- Modify: `mobile/lib/features/owner/owner_provider.dart`
- Create: `mobile/lib/core/models/master_data.dart` (Principal, SeriesEntry, BuyerBranch DTOs)
- Create: `mobile/lib/core/models/receivables.dart` (BuyerReceivable, ReceivableInvoice, PaymentRecord, ReceivablesSummary DTOs)
- Create: `mobile/lib/features/capture/series_detect.dart`
- Modify: `mobile/lib/core/models/bundle.dart` + regenerate `bundle.g.dart`
- Modify: `mobile/lib/features/capture/sync_service.dart` (send new form fields)
- Test: `mobile/test/capture/series_detect_test.dart`, `mobile/test/owner/receivables_models_test.dart`

**Interfaces:**
- Produces: `SeriesEntry? detectSeries(String invoiceNumber, List<SeriesEntry> registry)` — longest matching prefix, case-insensitive, null when no match.
- Produces on `OwnerService`: `getReceivables()`, `getBuyerReceivables(String buyerId)`, `recordPayment({required String invoiceId, required double amount, required String paidOn, required String mode, String? reference, String? notes})`, `listPayments(String invoiceId)`, `getSalesReport({required String from, required String to, required String groupBy})`, `listPrincipals()`, `createPrincipal(name, code)`, `deletePrincipal(id)`, `listSeriesRegistry()`, `upsertSeriesEntry(...)`, `deleteSeriesEntry(id)`, `listBuyerBranches(buyerId)`, `createBuyerBranch(...)`, `deleteBuyerBranch(id)`, `updateBuyer(buyerId, {salesChannel, defaultTermsDays})`
- Produces Riverpod: `receivablesProvider`, `buyerReceivablesProvider(buyerId)`, `salesReportProvider((from,to,groupBy))`, `principalsProvider`, `seriesRegistryProvider`, `buyerBranchesProvider(buyerId)`
- `QueuedBundle` gains `@HiveField(13) String? paymentType`, `@HiveField(14, defaultValue: null) int? paymentTermsDays`, `@HiveField(15) String? buyerBranchId`, `@HiveField(16) String? salesman`, `@HiveField(17) String? beat`.

- [ ] **Step 1: Write failing tests** — series detect (exact prefix, longest-wins REHIN vs RE, case-insensitive, no match → null) and DTO JSON round-trips.
- [ ] **Step 2: Run to verify fail.** `cd mobile; puro flutter test test/capture/series_detect_test.dart`
- [ ] **Step 3: Implement DTOs, endpoints, service methods, providers, Hive fields; run build_runner** (`puro dart run build_runner build --delete-conflicting-outputs`).
- [ ] **Step 4: Extend `SyncService` ledger-upload form-data map with the new bundle fields (skip nulls).**
- [ ] **Step 5: Tests pass + `puro flutter analyze` vs baseline.**
- [ ] **Step 6: Commit** — `feat(mobile): data layer for receivables, master data, series detection, capture terms`

---

### Task 5: Mobile shell navigation rebuild

**Files:**
- Modify: `mobile/lib/app.dart` (router rebuild)
- Create: `mobile/lib/core/navigation/app_shell.dart` (`WorkerShell`, `OwnerShell` — `StatefulShellRoute.indexedStack` scaffolds with `NavigationBar`)
- Modify: `mobile/lib/features/home/home_screen.dart` (becomes worker Capture tab root; owner-side users no longer land here)
- Create: `mobile/lib/features/owner/more_screen.dart` (owner More tab: list tiles → buyers, buyer requirements, rules, principals & series, settings, logout)
- Modify: screens' `AppBackScope` fallbacks (tab roots: back → switch to first tab; first tab: double-back exit)
- Test: `mobile/test/core/navigation/shell_test.dart`

**Interfaces:**
- Routes: worker shell branches `/home`, `/queue`, `/my-invoices`; owner shell branches `/owner`, `/owner/invoices`, `/owner/receivables`, `/alerts`, `/owner/more`. Full-screen (outside shells): `/login`, `/capture/*`, `/owner/invoices/:id`, `/admin/*`, `/settings`, `/owner/principals`.
- Redirect: logged-in WORKER → `/home`; ADMIN/MANAGER/FINANCE/REVIEWER → `/owner`. Workers blocked from owner shell; owner-side users may still open `/capture/*` (Dashboard capture button) and `/home` is redirected to `/owner` for them.
- Produces: `class WorkerShell extends StatelessWidget { const WorkerShell({required this.navigationShell}); }` (same for `OwnerShell`) using `navigationShell.goBranch(index, initialLocation: ...)`.

- [ ] **Step 1: Write failing shell tests** — worker login lands on capture tab with 3 destinations; owner login lands on dashboard with 5; tapping Receivables switches branch; hardware back on non-first tab returns to first tab.
- [ ] **Step 2: Verify fail.**
- [ ] **Step 3: Implement shells + router; update `context.go('/home')` call sites across screens to role-aware home (helper `String homeLocationForRole(String? role)` in app_shell.dart).**
- [ ] **Step 4: All mobile tests + analyze vs baseline.**
- [ ] **Step 5: Commit** — `feat(mobile): role-based bottom-tab shells for worker and owner navigation`

---

### Task 6: Receivables screens + dashboard reports

**Files:**
- Create: `mobile/lib/features/receivables/receivables_screen.dart` (tab root: header totals, buyer list ranked by outstanding, aging chips; pull-to-refresh; offline → last data + banner)
- Create: `mobile/lib/features/receivables/buyer_receivables_screen.dart` (route `/owner/receivables/:buyerId`; open invoices with balance/due/days-overdue; tap → invoice detail)
- Create: `mobile/lib/features/receivables/record_payment_sheet.dart` (`showModalBottomSheet` form: amount, paid_on date picker, mode dropdown CASH/UPI/CHEQUE/NEFT/OTHER, reference, notes; validates amount > 0 and ≤ balance; surfaces server 400 inline; on success invalidates `receivablesProvider` + `buyerReceivablesProvider`)
- Modify: `mobile/lib/features/owner/invoice_detail_screen.dart` (Payments section + reconciliation strip: Invoiced / Accepted / Credit note / Net)
- Modify: `mobile/lib/features/owner/owner_dashboard_screen.dart` (period selector today/week/month, KPI row incl. outstanding, group-by ranked-bar breakdown fed by `salesReportProvider`)
- Test: `mobile/test/receivables/receivables_screen_test.dart`, `mobile/test/receivables/record_payment_sheet_test.dart`

**Interfaces:**
- Consumes Task 4 providers/services; FINANCE/MANAGER/ADMIN see the Record-payment button, REVIEWER read-only (`currentUserProvider` role check).

- [ ] **Step 1: Failing widget tests** — mocked Dio: summary renders buyer rows + totals; payment sheet rejects over-balance locally; REVIEWER sees no record button.
- [ ] **Step 2: Verify fail. Step 3: Implement. Step 4: Tests + analyze. Step 5: Commit** — `feat(mobile): receivables tab, payment recording, dashboard sales reports`

---

### Task 7: Capture flow additions + master-data screens

**Files:**
- Modify: `mobile/lib/features/capture/review_screen.dart` (payment-type segmented Cash/Credit; terms field prefilled from buyer default, visible when Credit; series/principal chip from `detectSeries` on invoice-number changes, editable via dropdown of principals; branch dropdown when selected buyer has branches)
- Modify: `mobile/lib/features/capture/bundle_provider.dart` (carry new fields into `QueuedBundle`)
- Create: `mobile/lib/features/admin/principals_screen.dart` (route `/owner/principals`: two sections — principals list with add/delete, series registry list with add/edit prefix→entity+principal; ADMIN-gated)
- Modify: `mobile/lib/features/admin/buyer_requirements_screen.dart` OR create `mobile/lib/features/admin/buyer_edit_screen.dart` (buyer channel + default terms + branches management)
- Modify: `mobile/lib/features/owner/more_screen.dart` (wire tiles)
- Test: `mobile/test/capture/review_screen_terms_test.dart`, `mobile/test/admin/principals_screen_test.dart`

- [ ] **Step 1: Failing tests** — review screen: selecting Credit shows terms prefilled from buyer default; typing "CAD/15442" surfaces Mondelez chip; bundle carries fields. Principals screen renders list + add flow (mocked Dio).
- [ ] **Step 2: Verify fail. Step 3: Implement. Step 4: Tests + analyze. Step 5: Commit** — `feat(mobile): capture payment terms + series detect, master-data admin screens`

---

### Task 8: Final verification + docs

**Files:**
- Modify: `task.md` (add Phase 9 section with completed items)
- Verify only otherwise.

- [ ] **Step 1:** `cd backend; go build ./... ; go vet ./...` — clean.
- [ ] **Step 2:** Backend integration tests if Docker stack available: `go test ./...`; otherwise state explicitly they were not run locally.
- [ ] **Step 3:** `cd mobile; puro flutter test` — all pass.
- [ ] **Step 4:** `puro flutter analyze` — matches baseline (update baseline only with justification).
- [ ] **Step 5:** Update `task.md`, commit — `docs: record distributor-ops rebuild phase`

## Self-Review Notes

- Spec coverage: navigation (T5), domain model (T1/T2), capture additions (T4/T7), receivables (T2/T3/T6), reconciliation auto-dispute + strip (T3/T6), reporting (T2/T3/T6), master data (T3/T7), roles (T3/T6), error handling (T3 validation, T6 offline banner), testing (every task).
- Types consistent: `SeriesEntry`/`detectSeries` (T4) consumed in T7; `BuyerReceivable` fields (T2) mirrored in DTOs (T4) and screens (T6).
- Receivable math pinned to `gross_amount` = bill total (verified against `handleUploadLedgerInvoice`).
