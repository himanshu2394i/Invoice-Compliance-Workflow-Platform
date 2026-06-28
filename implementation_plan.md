# Implementation Plan - MVP Invoice Compliance & Workflow SaaS

This plan details the steps to build the first functioning MVP version of the Enterprise Multi-Tenant Invoice Compliance & Workflow platform. 

We will structure the project as a clean monorepo:
* `/backend` - Go backend containing the Core API, DB schema, Temporal Workflows, and Workers.
* `/frontend` - Next.js (TypeScript) dashboard styled with Vanilla CSS (via CSS Modules/CSS variables) to support high-fidelity, premium visual design.
* `/docker-compose.yml` - Sets up localized development dependencies (PostgreSQL, Temporal, Redis).

---

## Proposed Project Structure

```
d:\MeridianDist
├── backend/
│   ├── cmd/
│   │   ├── api/
│   │   │   └── main.go           # REST / HTTP API server
│   │   └── worker/
│   │       └── main.go           # Temporal workflow worker
│   ├── internal/
│   │   ├── api/                  # Handlers, request/response objects
│   │   ├── db/                   # DB connection, models, SQL queries (pgx)
│   │   ├── validation/           # Ingestion checking logic
│   │   └── workflow/             # Temporal workflow definitions & activities
│   ├── db/
│   │   └── schema.sql            # Core database schema
│   ├── go.mod
│   └── go.sum
├── frontend/                     # Next.js app
├── docker-compose.yml            # Local PostgreSQL + Temporal container orchestration
├── memory.md
└── architectural_blueprint.md
```

---

## Proposed Changes

### [Component: Infrastructure]

#### [NEW] [docker-compose.yml](file:///d:/MeridianDist/docker-compose.yml)
Set up:
1. **PostgreSQL 16**: Standard port `5432` with pre-created databases `invoice_saas` and `temporal`.
2. **Temporal Development Server**: A single-container Temporal server including its admin console (port `8080`).

---

### [Component: Go Backend]

#### [NEW] [schema.sql](file:///d:/MeridianDist/backend/db/schema.sql)
Creates tables (Organizations, Entities, Vendors, Invoices, Documents, DocumentVersions, AuditLogs) with RLS configuration and schema setup.

#### [NEW] [main.go (API)](file:///d:/MeridianDist/backend/cmd/api/main.go)
Initializes DB connection pools, starts the HTTP server on port `8000`, maps requests, sets tenant context headers (simulating gateway tenant mappings), and exposes endpoints:
* `POST /api/v1/invoices` - Ingests invoice metadata, generates upload details, and starts Temporal workflow.
* `GET /api/v1/invoices` - Lists invoices filtered by current tenant.
* `GET /api/v1/invoices/:id` - Fetch invoice details, missing documents list, validation errors, and workflow status.
* `POST /api/v1/invoices/:id/approve` - Signals the approval state to the Temporal workflow.
* `GET /api/v1/invoices/:id/audit-trail` - Fetch tamper-proof audit trail entries.

#### [NEW] [workflows.go & activities.go](file:///d:/MeridianDist/backend/internal/workflow/workflows.go)
Defines the Temporal Workflow `InvoiceWorkflow(ctx, invoiceID)`:
1. **State transition state machine**: Executes validation activities.
2. **Signal listeners**: Wait for approval signals (`ManagerApprovalReceived`, `FinanceApprovalReceived`).
3. **Timer controls**: Handles reminders and escalation alerts.

#### [NEW] [main.go (Worker)](file:///d:/MeridianDist/backend/cmd/worker/main.go)
Launches the Go Temporal worker that registers workflows and activities, connecting to the Temporal cluster.

---

### [Component: Next.js Frontend]

#### [NEW] [Next.js Project](file:///d:/MeridianDist/frontend)
Initialize a Next.js project styled with Vanilla CSS to build a premium, glassmorphism-inspired enterprise finance dashboard. 
Key UI Pages:
1. **Invoice List**: Showing a comprehensive dashboard containing validation statuses, approval steps, missing files indicators, and active workflow states.
2. **Invoice Detail Page**: Interactive timeline of Temporal status, visual approval progress tracking (Manager -> Finance), validation warnings (GSTIN matching, duplicate check results), and audit trail inspector.
3. **Upload Dialog**: Drag-and-drop ingestion interface simulating S3 upload.

---

## Verification Plan

### Automated Tests
* We will write Go unit tests for validation engine checks (GSTIN pattern check, amount mismatch).
* Integration tests checking the Temporal state transitions by spinning up a local Temporal test env.

### Manual Verification
1. Run local services via `docker-compose up -d`.
2. Boot Backend API and Temporal worker.
3. Use `curl` or UI to submit an invoice.
4. Verify invoice is created in PG, a Temporal workflow starts, and the UI dynamically reflects the state.
5. Signal approval from the dashboard UI and track state transitions through to final approval.
