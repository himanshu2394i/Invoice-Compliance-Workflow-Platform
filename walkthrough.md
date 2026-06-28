# Systems Walkthrough - MVP Invoice Compliance & Workflow platform

This walkthrough documents the code architecture, multi-tenant isolation mechanics, Temporal state machine execution, and local verification steps for the MVP.

---

## 1. Architectural Highlights

### Multi-Tenant Isolation (PostgreSQL Row-Level Security)
Every table is logical isolated using a `tenant_id` (represented by `organization_id`). In [schema.sql](file:///d:/MeridianDist/backend/db/schema.sql) we configured PostgreSQL Row-Level Security (RLS) rules:
```sql
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_invoices ON invoices
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
```
In [db.go](file:///d:/MeridianDist/backend/internal/db/db.go), our repository wraps queries in transactions and runs a database connection hook to scope the current session context:
```go
func (r *Repository) WithTx(ctx context.Context, tenantID string, fn func(pgx.Tx) error) error {
	tx, err := r.Pool.Begin(ctx)
	// ...
	_, err = tx.Exec(ctx, "SELECT set_config('app.current_tenant_id', $1, true)", tenantID)
	// ...
	return tx.Commit(ctx)
}
```
This guarantees that even if a developer forgets to append a `WHERE tenant_id = ...` clause to a query, PostgreSQL will reject or filter out records belonging to other tenants.

### Durable Temporal Approval State Machine
In [workflows.go](file:///d:/MeridianDist/backend/internal/workflow/workflows.go), the invoice lifecycle is structured using Temporal's durable execution:
* **Selector-Based Event Multiplexing**: Listens to multiple incoming signals (Manager Approval, Finance Approval, Rejections) and a recurring escalation timer:
  ```go
  selector.AddFuture(reminderTimer, func(f workflow.Future) {
      // Send Slack / Email reminder via Activity
  })
  ```
* **State Syncing Activities**: Operations like database edits (`UpdateInvoiceStateActivity`) and auditing (`LogAuditEventActivity`) are isolated to Activities so they can be retried safely without breaking workflow determinism.

---

## 2. Walkthrough of Created Code

### Backend Component
1. [schema.sql](file:///d:/MeridianDist/backend/db/schema.sql) - Database schemas for multi-tenant accounts, invoices, files, and crypto audit trails.
2. [db.go](file:///d:/MeridianDist/backend/internal/db/db.go) - Transactional repository implementing dynamic configuration for PostgreSQL RLS and append-only cryptographic chains.
3. [validation.go](file:///d:/MeridianDist/backend/internal/validation/validation.go) - Compliance rule filters evaluating gross/tax limits and Indian GSTIN formats.
4. [validation_test.go](file:///d:/MeridianDist/backend/internal/validation/validation_test.go) - Go unit tests targeting the validation regex patterns.
5. [workflows.go](file:///d:/MeridianDist/backend/internal/workflow/workflows.go) - Declarative Temporal workflow orchestrating states, signals, and reminders.
6. [main.go (API)](file:///d:/MeridianDist/backend/cmd/api/main.go) - HTTP REST API server binding routes, CORS, and logging.
7. [main.go (Worker)](file:///d:/MeridianDist/backend/cmd/worker/main.go) - Workflow client loop that registers and runs activities.
8. [encryption.go](file:///d:/MeridianDist/backend/internal/security/encryption.go) - AES-GCM envelope encryption utility for securing sensitive bank account details.
9. [reconciler.go](file:///d:/MeridianDist/backend/internal/reconciliation/reconciler.go) - State reconciler that scans PG database and bootstraps Temporal workflow executions.
10. [opensearch_mappings.json](file:///d:/MeridianDist/backend/db/opensearch_mappings.json) - OpenSearch database mapping parameters for full-text search.
11. [debezium_config.json](file:///d:/MeridianDist/backend/db/debezium_config.json) - CDC connector configs routing outbox mutations to Kafka.
12. [s3_lifecycle.tf](file:///d:/MeridianDist/backend/db/s3_lifecycle.tf) - Terraform configurations enforcing WORM lock and Standard -> Archive storage lifecycle.

### Next.js Frontend Component
1. [package.json](file:///d:/MeridianDist/frontend/package.json) & [tsconfig.json](file:///d:/MeridianDist/frontend/tsconfig.json) - Node environment and compilation specs.
2. [globals.css](file:///d:/MeridianDist/frontend/app/globals.css) - Styling foundation incorporating Google Inter & Outfit fonts, glassmorphic filters, and animated statuses.
3. [layout.tsx](file:///d:/MeridianDist/frontend/app/layout.tsx) - HTML template frame displaying active organization headers.
4. [page.tsx (Dashboard)](file:///d:/MeridianDist/frontend/app/page.tsx) - Reactive list, form ingestion console, and mock database seeder.
5. [page.tsx (Details)](file:///d:/MeridianDist/frontend/app/invoice/[id]/page.tsx) - Interactive workflow timeline tracking state transitions, approval form submit triggers, and cryptographically verified audit records.

---

## 3. Operational Guide (How to Run Locally)

Follow these steps to run and test the complete system locally:

### Step 1: Start Infrastructure (PostgreSQL, Temporal, Python OCR Worker)
With Docker Desktop running:
```bash
docker compose up -d --build
```
This boots Postgres, the Temporal server + Web UI, and the Python OCR worker
(`ocr-worker`, see [backend/python_worker](file:///d:/MeridianDist/backend/python_worker)).
The OCR worker is required -- without it, every invoice workflow hangs forever
waiting for the `ExtractTextAndLayout` activity on the `ocr-tasks` queue. It runs
in deterministic simulation mode by default (no GPU/torch required); install
`requirements-ml.txt` inside the container instead if you want real LayoutLMv3
inference.

### Step 2: Initialize Database and Start Go Backend Services
Initialize schema tables:
```bash
psql -h localhost -U admin -d invoice_saas -f backend/db/schema.sql
```
Start Core REST API:
```bash
cd backend
go run cmd/api/main.go
```
In a separate terminal, launch the Go Temporal worker (handles validation, state
persistence, and audit logging activities):
```bash
cd backend
go run cmd/worker/main.go
```

### Step 3: Run Next.js Frontend Development Server
In another terminal:
```bash
cd frontend
npm install
npm run dev
```
Open [http://localhost:3000](http://localhost:3000) in your browser.

### Step 4: Verification Walkthrough Flow
1. **Login Portal**: At `/login`, pick a role -- Worker, Reviewer, or Admin.
2. **Seed Database**: On the **Admin** dashboard (`/dashboard/admin`), click **"Seed Database"**. This provisions a test organization, a legal entity (GSTIN 27AAAAA1111A1Z1), and a vendor inside Postgres.
3. **Upload Invoice**: On the **Worker** dashboard (`/dashboard/worker`), click the drag-and-drop area to simulate an upload. This creates an invoice tied to the seeded entity/vendor and starts the Temporal workflow.
4. **Verify Temporal Execution**: Navigate to the Temporal Web UI at [http://localhost:8080](http://localhost:8080) to inspect the execution tree, or open the invoice from the main dashboard (`/`) to see its **Details profile**.
5. **Inspect Automated Validation**: The workflow transitions through `VALIDATING`. With the seeded dummy data it always passes, landing on `PENDING_MANAGER_APPROVAL` (and `PENDING_FINANCE_APPROVAL` for amounts over 5,000).
6. **Grant Approvals**: On the **Reviewer** dashboard (`/dashboard/reviewer`) or the invoice Details page, approve or reject. The signal sent is role-specific (Manager/Finance/Reject) -- approving at the wrong stage does nothing, by design, since the workflow listens on separate channels per role. You'll see the timeline update live through `APPROVED` to `ARCHIVED`.
7. **Audit Logs Cryptographic Verification**: Check the right-hand panel of the Invoice details profile. It sequence-links all operations with SHA-256 blocks (`SHA256(prevHash + eventType + payload)`) and flags "Verified Linked", proving immutability.
