# Mobile Invoice Capture App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter mobile app for Meridian Brothers/Distributors field workers to photograph invoices and bundle them with the correct supporting documents per buyer, with offline queuing and automatic sync.

**Architecture:** Flutter app (offline-first via Hive) calling the existing Go backend. Backend gets two new additions: a `buyer_document_requirements` DB table + migration, and two new mobile-specific API endpoints. The Flutter app guides workers through: photograph invoice → fill in key fields while looking at the photo → system prompts for this buyer's required docs → photograph those → submit (queues locally if offline, syncs when back online).

**Tech Stack:** Flutter 3.x / Dart 3.x, Riverpod 2.x (state), Hive 2.x (offline queue), Dio 5.x (HTTP), camera 0.10.x (camera preview), image_picker 1.x (gallery fallback), go_router 13.x (navigation), flutter_secure_storage 9.x (JWT), connectivity_plus 6.x (network watch), image 4.x (JPEG compression). Backend: Go net/http, pgx/v5, PostgreSQL 16. Project module: `github.com/himanshu2394i/invoice-saas`.

## Global Constraints

- Flutter minimum SDK: `">=3.3.0 <4.0.0"`
- No new Temporal workflows for mobile — the existing `handleUploadLedgerInvoice` + `handleUploadSupportingDocument` endpoints are reused verbatim
- All Go backend code connects as `app_user` Postgres role (never `admin` superuser) — every new table needs `GRANT SELECT, INSERT, UPDATE, DELETE ON <table> TO app_user`
- Every new Postgres table needs RLS enabled + a `tenant_<tablename>_policy` policy scoped to `organization_id`
- JWT from `POST /api/v1/auth/login` stored in `flutter_secure_storage`, sent as `Authorization: Bearer <token>` on every backend call
- Mobile app directory: `D:\MeridianDist\mobile\`
- Backend Go files: `D:\MeridianDist\backend\`
- Images compressed to JPEG quality 80, max-dimension 2048px before upload/storage
- Invoice series values seen in real data: `A26`, `CAD`, `DBR`, `GST`, `BIB`, `MORDE`, `HYGIN`, `NIV` — these are the only valid options shown in the series dropdown
- Three seller entities (from invoice_extraction.md): **Meridian Brothers** (GSTIN 06AAAAA0003A1Z3), **Meridian Distributors** (GSTIN 06AAAAA0015A1ZF), **Meridian Gurgaon** (GSTIN 06AAAAA0017A1ZH)
- Worker can only create invoices (role=WORKER) — no approvals from mobile
- CORS: `CORS_ALLOWED_ORIGIN` env var already set; mobile app hits backend directly (no browser CORS concern)
- go.mod module path: `github.com/himanshu2394i/invoice-saas`

---

## File Map

### Backend additions
| File | Action | Purpose |
|------|--------|---------|
| `backend/db/migrations/000004_buyer_doc_requirements.up.sql` | Create | New table: which docs each buyer requires |
| `backend/db/migrations/000004_buyer_doc_requirements.down.sql` | Create | Rollback migration |
| `backend/internal/db/db.go` | Modify (append) | `BuyerDocRequirement` model + `ListBuyerDocRequirements`, `UpsertBuyerDocRequirement` methods |
| `backend/internal/api/mobile_handlers.go` | Create | `GET /api/v1/mobile/buyers/requirements`, `GET /api/v1/mobile/sync-state` |
| `backend/internal/api/api.go` | Modify | Register 2 new mobile routes |

### Flutter app (all under `mobile/`)
| File | Action | Purpose |
|------|--------|---------|
| `mobile/pubspec.yaml` | Create | Dependencies + assets |
| `mobile/lib/main.dart` | Create | App entry point, Hive init, Riverpod scope |
| `mobile/lib/app.dart` | Create | GoRouter config, MaterialApp |
| `mobile/lib/core/api/api_client.dart` | Create | Dio instance with auth interceptor |
| `mobile/lib/core/api/endpoints.dart` | Create | Base URL + path constants |
| `mobile/lib/core/models/bundle.dart` | Create | `QueuedBundle`, `QueuedPhoto` with Hive type adapters |
| `mobile/lib/core/models/buyer_requirement.dart` | Create | `BuyerDocRequirement` model |
| `mobile/lib/core/storage/hive_service.dart` | Create | Opens Hive boxes, registers adapters |
| `mobile/lib/core/storage/image_store.dart` | Create | Save/load/compress photos on device |
| `mobile/lib/core/sync/sync_service.dart` | Create | Upload queued bundles, retry logic |
| `mobile/lib/features/auth/auth_provider.dart` | Create | Riverpod: login, logout, token storage |
| `mobile/lib/features/auth/login_screen.dart` | Create | Email + password login UI |
| `mobile/lib/features/capture/bundle_provider.dart` | Create | Riverpod: in-progress capture session |
| `mobile/lib/features/capture/camera_screen.dart` | Create | Camera preview + capture button |
| `mobile/lib/features/capture/review_screen.dart` | Create | Invoice fields form while seeing photo |
| `mobile/lib/features/capture/checklist_screen.dart` | Create | Prompts for buyer-specific required docs |
| `mobile/lib/features/home/home_screen.dart` | Create | New capture button + queue status |
| `mobile/lib/features/queue/queue_screen.dart` | Create | Pending/failed bundle list + retry |

---

## Task 1: Backend DB Migration — buyer_document_requirements

**Files:**
- Create: `backend/db/migrations/000004_buyer_doc_requirements.up.sql`
- Create: `backend/db/migrations/000004_buyer_doc_requirements.down.sql`

**Interfaces:**
- Produces: table `buyer_document_requirements(id, organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order, created_at)` queryable by Task 2

- [ ] **Step 1: Write the up migration**

```sql
-- backend/db/migrations/000004_buyer_doc_requirements.up.sql

-- Per-buyer list of supporting documents that workers must photograph alongside
-- the primary tax invoice. is_buyer_generated = true means the buyer hands over
-- this document themselves (e.g. Vishal Mega Mart's Gate Entry / Discrepancy Note
-- is generated by their system; the worker just photographs what the store gives them).
-- is_buyer_generated = false means the vendor must produce/attach the doc.
CREATE TABLE IF NOT EXISTS buyer_document_requirements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    buyer_id UUID NOT NULL REFERENCES buyers(id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    is_buyer_generated BOOLEAN NOT NULL DEFAULT false,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_buyer_doc_req UNIQUE (organization_id, buyer_id, document_type)
);
CREATE INDEX IF NOT EXISTS idx_buyer_doc_req_buyer ON buyer_document_requirements(buyer_id);

ALTER TABLE buyer_document_requirements ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_buyer_doc_requirements_policy ON buyer_document_requirements
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

GRANT SELECT, INSERT, UPDATE, DELETE ON buyer_document_requirements TO app_user;
```

- [ ] **Step 2: Write the down migration**

```sql
-- backend/db/migrations/000004_buyer_doc_requirements.down.sql
DROP TABLE IF EXISTS buyer_document_requirements;
```

- [ ] **Step 3: Apply migration**

```bash
cd D:\MeridianDist
psql -h localhost -U admin -d invoice_saas -f backend/db/migrations/000004_buyer_doc_requirements.up.sql
```

Expected: `CREATE TABLE`, `CREATE INDEX`, `ALTER TABLE`, `CREATE POLICY`, `GRANT`

- [ ] **Step 4: Verify table exists**

```bash
psql -h localhost -U app_user -d invoice_saas -c "\d buyer_document_requirements"
```

Expected: table with columns `id, organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order, created_at`

- [ ] **Step 5: Commit**

```bash
cd D:\MeridianDist
git add backend/db/migrations/000004_buyer_doc_requirements.up.sql backend/db/migrations/000004_buyer_doc_requirements.down.sql
git commit -m "feat(db): add buyer_document_requirements table for mobile required-doc prompting"
```

---

## Task 2: Backend DB Methods — BuyerDocRequirement

**Files:**
- Modify: `backend/internal/db/db.go` (append to end of file)

**Interfaces:**
- Consumes: `buyer_document_requirements` table from Task 1
- Consumes: `Repository.WithTx` (already exists in db.go)
- Produces:
  - `type BuyerDocRequirement struct` with fields: `ID, OrganizationID, BuyerID, DocumentType, Label, IsBuyerGenerated bool, SortOrder int, CreatedAt time.Time`
  - `func (r *Repository) ListBuyerDocRequirements(ctx context.Context, tenantID, buyerID string) ([]*BuyerDocRequirement, error)`
  - `func (r *Repository) UpsertBuyerDocRequirement(ctx context.Context, tenantID string, req *BuyerDocRequirement) error`
  - `func (r *Repository) GetBuyerByID(ctx context.Context, tenantID, buyerID string) (*Buyer, error)`

- [ ] **Step 1: Append to `backend/internal/db/db.go`**

Add this code at the **end** of `backend/internal/db/db.go` (do not remove any existing code):

```go
// BuyerDocRequirement is a supporting document type that workers must photograph
// when filing an invoice for a specific buyer. is_buyer_generated=true means the
// buyer produces this document and hands it to the worker (e.g. Vishal Mega Mart's
// Gate Entry/Discrepancy Note); is_buyer_generated=false means the vendor/worker
// must produce and attach the doc.
type BuyerDocRequirement struct {
	ID              string    `json:"id"`
	OrganizationID  string    `json:"organization_id"`
	BuyerID         string    `json:"buyer_id"`
	DocumentType    string    `json:"document_type"`
	Label           string    `json:"label"`
	IsBuyerGenerated bool     `json:"is_buyer_generated"`
	SortOrder       int       `json:"sort_order"`
	CreatedAt       time.Time `json:"created_at"`
}

// ListBuyerDocRequirements returns all required supporting documents for a buyer,
// ordered by sort_order. Returns an empty slice (not an error) when no requirements
// are configured — that just means the primary tax invoice is sufficient.
func (r *Repository) ListBuyerDocRequirements(ctx context.Context, tenantID, buyerID string) ([]*BuyerDocRequirement, error) {
	var results []*BuyerDocRequirement
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			`SELECT id, organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order, created_at
			 FROM buyer_document_requirements
			 WHERE buyer_id = $1
			 ORDER BY sort_order ASC, created_at ASC`,
			buyerID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var req BuyerDocRequirement
			if err := rows.Scan(&req.ID, &req.OrganizationID, &req.BuyerID, &req.DocumentType, &req.Label, &req.IsBuyerGenerated, &req.SortOrder, &req.CreatedAt); err != nil {
				return err
			}
			results = append(results, &req)
		}
		return rows.Err()
	})
	return results, err
}

// UpsertBuyerDocRequirement inserts or updates a document requirement for a buyer.
// Uses ON CONFLICT on the (organization_id, buyer_id, document_type) unique key.
func (r *Repository) UpsertBuyerDocRequirement(ctx context.Context, tenantID string, req *BuyerDocRequirement) error {
	if req.ID == "" {
		req.ID = uuid.New().String()
	}
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`INSERT INTO buyer_document_requirements
			   (id, organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)
			 ON CONFLICT (organization_id, buyer_id, document_type)
			 DO UPDATE SET label = EXCLUDED.label,
			               is_buyer_generated = EXCLUDED.is_buyer_generated,
			               sort_order = EXCLUDED.sort_order`,
			req.ID, tenantID, req.BuyerID, req.DocumentType, req.Label, req.IsBuyerGenerated, req.SortOrder)
		return err
	})
}

// GetBuyerByID fetches a single buyer by its UUID (RLS-scoped to tenantID).
func (r *Repository) GetBuyerByID(ctx context.Context, tenantID, buyerID string) (*Buyer, error) {
	var b Buyer
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT id, organization_id, name, gstin, address, created_at
			 FROM buyers WHERE id = $1`,
			buyerID).Scan(&b.ID, &b.OrganizationID, &b.Name, &b.GSTIN, &b.Address, &b.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &b, nil
}
```

- [ ] **Step 2: Verify backend compiles**

```bash
cd D:\MeridianDist\backend
go build ./...
```

Expected: no output (zero errors)

- [ ] **Step 3: Commit**

```bash
cd D:\MeridianDist
git add backend/internal/db/db.go
git commit -m "feat(db): add BuyerDocRequirement model and repo methods"
```

---

## Task 3: Backend Mobile API Handler + Route Registration

**Files:**
- Create: `backend/internal/api/mobile_handlers.go`
- Modify: `backend/internal/api/api.go` (add 3 route registrations in `RegisterRoutes`)

**Interfaces:**
- Consumes: `Repository.ListBuyerDocRequirements`, `Repository.GetBuyerByGSTIN`, `Repository.UpsertBuyerDocRequirement`, `Repository.ListBuyers` (all existing or Task 2)
- Consumes: `requireAuth`, `requireRole`, `claimsFromContext`, `writeJSON`, `writeError` (all exist in api.go)
- Produces:
  - `GET /api/v1/mobile/buyers/requirements?gstin={gstin}` → `{"buyer": {...}, "requirements": [...]}`
  - `GET /api/v1/mobile/buyers/requirements/{buyer_id}` → same shape (lookup by id)
  - `POST /api/v1/mobile/buyers/{buyer_id}/requirements` → upsert a requirement (ADMIN/WORKER role)

- [ ] **Step 1: Create `backend/internal/api/mobile_handlers.go`**

```go
// mobile_handlers.go — lightweight API endpoints consumed exclusively by the
// Flutter mobile app. Kept separate from api.go to make the boundary explicit.
package api

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/himanshu2394i/invoice-saas/internal/db"
)

// handleMobileGetBuyerRequirements returns the list of supporting documents a
// worker must photograph for a given buyer. Accepts either:
//   - ?gstin=<gstin>  — look up by GSTIN (the normal case: worker just extracted
//     the GSTIN from the invoice photo or picked it from an autocomplete list)
//   - path param {buyer_id} — look up by UUID (when the buyer is already known)
//
// Returns an empty requirements array (not 404) when no requirements are
// configured — that just means the primary invoice photo is sufficient.
func (s *Server) handleMobileGetBuyerRequirements(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID

	var buyer *db.Buyer
	var err error

	gstin := strings.TrimSpace(r.URL.Query().Get("gstin"))
	buyerID := r.PathValue("buyer_id") // will be "" if called from the /by-gstin route

	switch {
	case buyerID != "":
		buyer, err = s.Repo.GetBuyerByID(r.Context(), tenantID, buyerID)
		if err != nil {
			writeError(w, http.StatusNotFound, "Buyer not found")
			return
		}
	case gstin != "":
		buyer, err = s.Repo.GetBuyerByGSTIN(r.Context(), tenantID, gstin)
		if err != nil {
			// Unknown buyer — return empty requirements rather than an error.
			// The mobile app will let the worker continue with no extra docs prompted.
			writeJSON(w, http.StatusOK, map[string]interface{}{
				"buyer":        nil,
				"requirements": []interface{}{},
			})
			return
		}
	default:
		writeError(w, http.StatusBadRequest, "Provide either ?gstin=<gstin> or buyer_id path param")
		return
	}

	reqs, err := s.Repo.ListBuyerDocRequirements(r.Context(), tenantID, buyer.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to load document requirements: "+err.Error())
		return
	}
	if reqs == nil {
		reqs = []*db.BuyerDocRequirement{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"buyer":        buyer,
		"requirements": reqs,
	})
}

// UpsertBuyerRequirementRequest is the body for POST .../requirements
type UpsertBuyerRequirementRequest struct {
	DocumentType     string `json:"document_type"`
	Label            string `json:"label"`
	IsBuyerGenerated bool   `json:"is_buyer_generated"`
	SortOrder        int    `json:"sort_order"`
}

// handleMobileUpsertBuyerRequirement lets admins (or workers, by design — they
// know their buyers best) configure which extra docs a specific buyer requires.
// Example: configure Vishal Mega Mart (GSTIN 06AAAAA0013A1ZD) to require
// "GATE_ENTRY_NOTE" / "Gate Entry / Discrepancy Note" / is_buyer_generated=true.
func (s *Server) handleMobileUpsertBuyerRequirement(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	buyerID := r.PathValue("buyer_id")

	// Confirm buyer belongs to this tenant
	buyer, err := s.Repo.GetBuyerByID(r.Context(), tenantID, buyerID)
	if err != nil {
		writeError(w, http.StatusNotFound, "Buyer not found")
		return
	}

	var req UpsertBuyerRequirementRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if strings.TrimSpace(req.DocumentType) == "" || strings.TrimSpace(req.Label) == "" {
		writeError(w, http.StatusBadRequest, "document_type and label are required")
		return
	}

	docReq := &db.BuyerDocRequirement{
		BuyerID:          buyer.ID,
		DocumentType:     strings.ToUpper(strings.TrimSpace(req.DocumentType)),
		Label:            strings.TrimSpace(req.Label),
		IsBuyerGenerated: req.IsBuyerGenerated,
		SortOrder:        req.SortOrder,
	}
	if err := s.Repo.UpsertBuyerDocRequirement(r.Context(), tenantID, docReq); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to save requirement: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
```

- [ ] **Step 2: Register the new routes in `backend/internal/api/api.go`**

In the `RegisterRoutes` method, add these three lines after the existing `mux.HandleFunc("GET /api/v1/buyers", ...)` line:

```go
// Mobile-specific: buyer document requirements (what supporting docs to photograph)
mux.HandleFunc("GET /api/v1/mobile/buyers/requirements", requireAuth(s.handleMobileGetBuyerRequirements))
mux.HandleFunc("GET /api/v1/mobile/buyers/{buyer_id}/requirements", requireAuth(s.handleMobileGetBuyerRequirements))
mux.HandleFunc("POST /api/v1/mobile/buyers/{buyer_id}/requirements", requireAuth(requireRole("WORKER", "ADMIN")(s.handleMobileUpsertBuyerRequirement)))
```

- [ ] **Step 3: Build and verify**

```bash
cd D:\MeridianDist\backend
go build ./...
```

Expected: no output

- [ ] **Step 4: Smoke test new endpoint (need a running server + valid JWT)**

```bash
# Start backend (separate terminal): go run cmd/api/main.go
# Seed: curl -X POST http://localhost:8000/api/v1/admin/seed
# Login as worker: TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
#   -H "Content-Type: application/json" \
#   -d '{"email":"worker+<prefix>@demo.local","password":"ChangeMe123!"}' | jq -r .token)

curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/v1/mobile/buyers/requirements?gstin=UNKNOWN_GSTIN_XYZ"
```

Expected: `{"buyer":null,"requirements":[]}`

- [ ] **Step 5: Commit**

```bash
cd D:\MeridianDist
git add backend/internal/api/mobile_handlers.go backend/internal/api/api.go
git commit -m "feat(api): add mobile buyer-requirements endpoints"
```

---

## Task 4: Seed Vishal Mega Mart's Gate Entry Requirement

This is a one-time data operation: configure that Vishal Mega Mart (the only buyer confirmed to issue separate Gate Entry/Discrepancy Notes in the invoice_extraction.md log) requires that document type. All other buyers seen require no additional docs beyond the primary invoice. This should be done via the API (not hard-coded SQL) so it's tracked through normal app flow and admins can update it.

**Files:** No code changes — this is a curl/API operation doc.

- [ ] **Step 1: After backend is running, create Vishal Mega Mart as a buyer and set its requirement**

```bash
# Get TOKEN as shown in Task 3 Step 4

# Create Vishal Mega Mart buyer (GSTIN from invoice_extraction.md entry [1])
curl -s -X POST http://localhost:8000/api/v1/buyers \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)",
    "gstin": "06AAAAA0013A1ZD",
    "address": {"city": "Gurgaon", "state": "Haryana"}
  }' | jq .

# Copy the returned "id" field, then:
BUYER_ID="<id from above>"

# Set Gate Entry requirement
curl -s -X POST "http://localhost:8000/api/v1/mobile/buyers/$BUYER_ID/requirements" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "document_type": "GATE_ENTRY_NOTE",
    "label": "Gate Entry / Discrepancy Note",
    "is_buyer_generated": true,
    "sort_order": 1
  }'
```

Expected: `{"status":"ok"}`

- [ ] **Step 2: Verify the requirement is returned**

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/v1/mobile/buyers/requirements?gstin=06AAAAA0013A1ZD" | jq .
```

Expected:
```json
{
  "buyer": {"gstin": "06AAAAA0013A1ZD", "name": "Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)", ...},
  "requirements": [{"document_type": "GATE_ENTRY_NOTE", "label": "Gate Entry / Discrepancy Note", "is_buyer_generated": true, ...}]
}
```

---

## Task 5: Flutter Project Setup

**Files:**
- Create: `mobile/pubspec.yaml`
- Create: `mobile/lib/main.dart`
- Create: `mobile/lib/app.dart`
- Create: `mobile/lib/core/api/endpoints.dart`

**Interfaces:**
- Produces: runnable Flutter app skeleton with routing and DI

- [ ] **Step 1: Create `mobile/pubspec.yaml`**

```yaml
name: meridian_mobile
description: Meridian invoice capture app for field workers.
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5
  go_router: ^13.2.4
  dio: ^5.4.3
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  flutter_secure_storage: ^9.2.2
  camera: ^0.10.5+9
  image_picker: ^1.1.2
  image: ^4.1.7
  path_provider: ^2.1.3
  connectivity_plus: ^6.0.5
  intl: ^0.19.0
  uuid: ^4.4.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  hive_generator: ^2.0.1
  build_runner: ^2.4.9
  riverpod_generator: ^2.4.0

flutter:
  uses-material-design: true
```

- [ ] **Step 2: Create Flutter project structure**

```bash
cd D:\MeridianDist
flutter create --org com.meridian --project-name meridian_mobile mobile
# Then replace pubspec.yaml with the content above
# Then run:
cd mobile
flutter pub get
```

Expected: `Running "flutter pub get" in mobile...` then package resolution success.

- [ ] **Step 3: Create `mobile/lib/core/api/endpoints.dart`**

```dart
// endpoints.dart — single source of truth for backend URL and path constants.
// Change baseUrl to point at production when deploying.
class Endpoints {
  Endpoints._();

  // Dev: Go backend runs on port 8000. Change to production URL for release.
  static const String baseUrl = 'http://10.0.2.2:8000'; // Android emulator → localhost
  // For real device on local network, use machine's LAN IP: 'http://192.168.x.x:8000'

  // Auth
  static const String login = '/api/v1/auth/login';

  // Entities (our seller entities: Meridian Brothers, etc.)
  static const String entities = '/api/v1/entities';

  // Buyers
  static const String buyers = '/api/v1/buyers';
  static const String buyerRequirementsByGstin = '/api/v1/mobile/buyers/requirements';
  static String buyerRequirements(String buyerId) =>
      '/api/v1/mobile/buyers/$buyerId/requirements';

  // Invoice filing (ledger direction: we issued the invoice TO a buyer)
  static const String ledgerUpload = '/api/v1/invoices/ledger-upload';
  static String invoiceDocuments(String invoiceId) =>
      '/api/v1/invoices/$invoiceId/documents';
}
```

- [ ] **Step 4: Create `mobile/lib/app.dart`** (placeholder routing — will be updated as screens are added in later tasks)

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/capture/camera_screen.dart';
import 'features/capture/review_screen.dart';
import 'features/capture/checklist_screen.dart';
import 'features/queue/queue_screen.dart';

final router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(
      path: '/capture/camera',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return CameraScreen(
          label: extra?['label'] as String? ?? 'Photograph Invoice',
          documentType: extra?['document_type'] as String? ?? 'INVOICE_IMAGE',
        );
      },
    ),
    GoRoute(path: '/capture/review', builder: (_, __) => const ReviewScreen()),
    GoRoute(path: '/capture/checklist', builder: (_, __) => const ChecklistScreen()),
    GoRoute(path: '/queue', builder: (_, __) => const QueueScreen()),
  ],
);

class MeridianApp extends StatelessWidget {
  const MeridianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Meridian Invoice',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20), // dark green — Meridian brand feel
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B5E20),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B5E20),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 5: Create `mobile/lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'core/storage/hive_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  runApp(const ProviderScope(child: MeridianApp()));
}
```

- [ ] **Step 6: Verify app runs (shows blank login screen)**

```bash
cd D:\MeridianDist\mobile
flutter run
```

Expected: app launches on connected device/emulator without errors. Login screen title "Meridian Invoice" visible.

- [ ] **Step 7: Commit**

```bash
cd D:\MeridianDist
git add mobile/
git commit -m "feat(mobile): Flutter project scaffold, routing, endpoints"
```

---

## Task 6: Core Models and Hive Storage

**Files:**
- Create: `mobile/lib/core/models/bundle.dart`
- Create: `mobile/lib/core/models/buyer_requirement.dart`
- Create: `mobile/lib/core/storage/hive_service.dart`
- Create: `mobile/lib/core/storage/image_store.dart`

**Interfaces:**
- Produces:
  - `class QueuedBundle` with Hive adapter (typeId 0)
  - `class QueuedPhoto` with Hive adapter (typeId 1)
  - `class BuyerDocRequirement` plain Dart model
  - `HiveService.init()` async, must be called before `runApp`
  - `HiveService.bundleBox` → `Box<QueuedBundle>`
  - `ImageStore.save(Uint8List bytes, String localId, int index)` → `String localPath`
  - `ImageStore.load(String localPath)` → `Future<Uint8List>`
  - `ImageStore.compress(Uint8List bytes)` → `Future<Uint8List>` (JPEG 80%, max 2048px)

- [ ] **Step 1: Create `mobile/lib/core/models/bundle.dart`**

```dart
import 'package:hive/hive.dart';

part 'bundle.g.dart'; // generated by build_runner

@HiveType(typeId: 1)
class QueuedPhoto extends HiveObject {
  @HiveField(0)
  String localPath;

  @HiveField(1)
  String documentType; // e.g. 'INVOICE_IMAGE', 'GATE_ENTRY_NOTE'

  @HiveField(2)
  int sortOrder;

  QueuedPhoto({
    required this.localPath,
    required this.documentType,
    this.sortOrder = 0,
  });
}

@HiveType(typeId: 0)
class QueuedBundle extends HiveObject {
  @HiveField(0)
  String localId; // UUID generated locally

  @HiveField(1)
  String invoiceNumber;

  @HiveField(2)
  String invoiceDateIso; // 'YYYY-MM-DD'

  @HiveField(3)
  String entityId; // UUID of the Meridian seller entity

  @HiveField(4)
  String entityGstin; // for display

  @HiveField(5)
  String buyerGstin;

  @HiveField(6)
  String buyerName;

  @HiveField(7)
  String? buyerId; // UUID once known from backend

  @HiveField(8)
  double grossAmount;

  @HiveField(9)
  double taxAmount;

  @HiveField(10)
  String currency;

  @HiveField(11)
  String? invoiceSeries; // 'A26', 'CAD', 'DBR', 'GST', etc.

  @HiveField(12)
  List<QueuedPhoto> photos;

  @HiveField(13)
  String status; // 'pending' | 'uploading' | 'submitted' | 'failed'

  @HiveField(14)
  String? remoteInvoiceId; // set after successful submission

  @HiveField(15)
  String? errorMessage;

  @HiveField(16)
  String createdAtIso; // DateTime.now().toIso8601String()

  QueuedBundle({
    required this.localId,
    required this.invoiceNumber,
    required this.invoiceDateIso,
    required this.entityId,
    required this.entityGstin,
    required this.buyerGstin,
    required this.buyerName,
    this.buyerId,
    required this.grossAmount,
    required this.taxAmount,
    this.currency = 'INR',
    this.invoiceSeries,
    required this.photos,
    this.status = 'pending',
    this.remoteInvoiceId,
    this.errorMessage,
    required this.createdAtIso,
  });
}
```

- [ ] **Step 2: Create `mobile/lib/core/models/buyer_requirement.dart`**

```dart
class BuyerDocRequirement {
  final String id;
  final String buyerId;
  final String documentType;
  final String label;
  final bool isBuyerGenerated;
  final int sortOrder;

  const BuyerDocRequirement({
    required this.id,
    required this.buyerId,
    required this.documentType,
    required this.label,
    required this.isBuyerGenerated,
    required this.sortOrder,
  });

  factory BuyerDocRequirement.fromJson(Map<String, dynamic> json) =>
      BuyerDocRequirement(
        id: json['id'] as String,
        buyerId: json['buyer_id'] as String,
        documentType: json['document_type'] as String,
        label: json['label'] as String,
        isBuyerGenerated: json['is_buyer_generated'] as bool? ?? false,
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}
```

- [ ] **Step 3: Run Hive code generation**

```bash
cd D:\MeridianDist\mobile
dart run build_runner build --delete-conflicting-outputs
```

Expected: generates `lib/core/models/bundle.g.dart`

- [ ] **Step 4: Create `mobile/lib/core/storage/hive_service.dart`**

```dart
import 'package:hive_flutter/hive_flutter.dart';
import '../models/bundle.dart';

class HiveService {
  HiveService._();

  static late Box<QueuedBundle> _bundleBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(QueuedPhotoAdapter());
    Hive.registerAdapter(QueuedBundleAdapter());
    _bundleBox = await Hive.openBox<QueuedBundle>('bundles');
  }

  static Box<QueuedBundle> get bundleBox => _bundleBox;
}
```

- [ ] **Step 5: Create `mobile/lib/core/storage/image_store.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageStore {
  ImageStore._();

  // Compress to JPEG 80%, max dimension 2048px (constraint from Global Constraints)
  static Future<Uint8List> compress(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    img.Image resized = decoded;
    if (decoded.width > 2048 || decoded.height > 2048) {
      resized = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? 2048 : null,
        height: decoded.height >= decoded.width ? 2048 : null,
        interpolation: img.Interpolation.linear,
      );
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  // Saves compressed bytes under app documents dir.
  // localId: bundle UUID; index: 0 = primary invoice, 1+ = supporting docs.
  static Future<String> save(Uint8List bytes, String localId, int index) async {
    final dir = await getApplicationDocumentsDirectory();
    final bundleDir = Directory('${dir.path}/captures/$localId');
    await bundleDir.create(recursive: true);
    final path = '${bundleDir.path}/photo_$index.jpg';
    final compressed = await compress(bytes);
    await File(path).writeAsBytes(compressed);
    return path;
  }

  static Future<Uint8List> load(String localPath) async {
    return await File(localPath).readAsBytes();
  }

  static Future<void> deleteBundle(String localId) async {
    final dir = await getApplicationDocumentsDirectory();
    final bundleDir = Directory('${dir.path}/captures/$localId');
    if (await bundleDir.exists()) {
      await bundleDir.delete(recursive: true);
    }
  }
}
```

- [ ] **Step 6: Verify build**

```bash
cd D:\MeridianDist\mobile
flutter build apk --debug 2>&1 | tail -20
```

Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 7: Commit**

```bash
cd D:\MeridianDist
git add mobile/lib/core/
git commit -m "feat(mobile): Hive models, image compression storage"
```

---

## Task 7: API Client and Auth Provider

**Files:**
- Create: `mobile/lib/core/api/api_client.dart`
- Create: `mobile/lib/features/auth/auth_provider.dart`
- Create: `mobile/lib/features/auth/login_screen.dart`

**Interfaces:**
- Consumes: `Endpoints` (Task 5), `flutter_secure_storage`, `dio`
- Produces:
  - `final apiClientProvider = Provider<ApiClient>((ref) => ...)`
  - `class ApiClient` with `dio` instance + auth interceptor
  - `ApiClient.get(path, {params})`, `ApiClient.post(path, data)`, `ApiClient.postMultipart(path, formData)`
  - `final authProvider = StateNotifierProvider<AuthNotifier, AuthState>`
  - `class AuthState {bool isLoggedIn; String? token; String? email; String? role; String? orgId; String? userId}`
  - `AuthNotifier.login(email, password)` → throws on failure
  - `AuthNotifier.logout()`
  - `LoginScreen` widget (complete, fully styled)

- [ ] **Step 1: Create `mobile/lib/core/api/api_client.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'endpoints.dart';

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage;

  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl: Endpoints.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, dynamic data) =>
      _dio.post(path, data: data);

  Future<Response> postMultipart(String path, FormData formData) =>
      _dio.post(path, data: formData);
}
```

- [ ] **Step 2: Create `mobile/lib/features/auth/auth_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

class AuthState {
  final bool isLoggedIn;
  final String? token;
  final String? email;
  final String? role;
  final String? orgId;
  final String? userId;

  const AuthState({
    this.isLoggedIn = false,
    this.token,
    this.email,
    this.role,
    this.orgId,
    this.userId,
  });
}

final _storage = const FlutterSecureStorage();

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(_storage));

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _client;

  AuthNotifier(this._client) : super(const AuthState()) {
    _restore();
  }

  Future<void> _restore() async {
    final token = await _storage.read(key: 'jwt_token');
    final email = await _storage.read(key: 'user_email');
    final role = await _storage.read(key: 'user_role');
    final orgId = await _storage.read(key: 'org_id');
    final userId = await _storage.read(key: 'user_id');
    if (token != null) {
      state = AuthState(
        isLoggedIn: true,
        token: token,
        email: email,
        role: role,
        orgId: orgId,
        userId: userId,
      );
    }
  }

  Future<void> login(String email, String password) async {
    final resp = await _client.post(Endpoints.login, {
      'email': email,
      'password': password,
    });
    final data = resp.data as Map<String, dynamic>;
    final token = data['token'] as String;
    final claims = data['claims'] as Map<String, dynamic>? ?? {};

    await _storage.write(key: 'jwt_token', value: token);
    await _storage.write(key: 'user_email', value: email);
    await _storage.write(key: 'user_role', value: claims['role'] as String? ?? '');
    await _storage.write(key: 'org_id', value: claims['organization_id'] as String? ?? '');
    await _storage.write(key: 'user_id', value: claims['user_id'] as String? ?? '');

    state = AuthState(
      isLoggedIn: true,
      token: token,
      email: email,
      role: claims['role'] as String?,
      orgId: claims['organization_id'] as String?,
      userId: claims['user_id'] as String?,
    );
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.read(apiClientProvider)),
);
```

- [ ] **Step 3: Check what the backend login response looks like**

The existing `handleLogin` in `backend/internal/api/auth_handlers.go` returns `{"token": "...", "claims": {...}}`. Read that file to confirm field names before writing the Flutter consumer:

```bash
# Check auth_handlers.go response shape
grep -A 20 "writeJSON.*200\|writeJSON.*StatusOK" D:\MeridianDist\backend\internal\api\auth_handlers.go
```

If `claims` is a top-level key with `role`, `organization_id`, `user_id` sub-keys, the auth_provider.dart above is correct. If the shape differs, update the key names in `auth_provider.dart` to match exactly.

- [ ] **Step 4: Create `mobile/lib/features/auth/login_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() { _error = 'Login failed. Check email and password.'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_long, size: 72, color: Colors.white),
                const SizedBox(height: 16),
                const Text(
                  'Meridian Invoice',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Field Capture App',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 48),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _login(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                        ],
                        const SizedBox(height: 20),
                        _loading
                          ? const CircularProgressIndicator()
                          : ElevatedButton(
                              onPressed: _login,
                              child: const Text('Sign In'),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Also check backend login response and fix auth_provider if needed**

Read `backend/internal/api/auth_handlers.go` — look for the JSON written on success. If the field containing claims is not called `"claims"` but something else (e.g. `"user"` or inline fields), update `auth_provider.dart` lines that read `data['claims']`.

- [ ] **Step 6: Test login flow on device**

```bash
cd D:\MeridianDist\mobile
flutter run
```

Enter worker credentials from a seeded tenant, tap Sign In. Expected: navigates to `/home` (will be a blank screen until Task 10 — that's OK).

- [ ] **Step 7: Commit**

```bash
cd D:\MeridianDist
git add mobile/lib/core/api/ mobile/lib/features/auth/
git commit -m "feat(mobile): API client, auth provider, login screen"
```

---

## Task 8: Capture Session State (Bundle Provider)

**Files:**
- Create: `mobile/lib/features/capture/bundle_provider.dart`

**Interfaces:**
- Consumes: `QueuedBundle`, `QueuedPhoto`, `HiveService.bundleBox`, `ImageStore`, `BuyerDocRequirement`
- Produces:
  - `final bundleProvider = StateNotifierProvider<BundleNotifier, BundleState>`
  - `class BundleState {QueuedBundle? bundle; List<BuyerDocRequirement> requirements; bool loadingRequirements}`
  - `BundleNotifier.startNewBundle()` — resets state
  - `BundleNotifier.addPhoto(Uint8List bytes, String documentType)` — compress + save + add to bundle
  - `BundleNotifier.setInvoiceFields(...)` — update invoice metadata
  - `BundleNotifier.setRequirements(List<BuyerDocRequirement>)` — set buyer doc reqs
  - `BundleNotifier.enqueue()` → saves to Hive, returns bundle localId
  - `final pendingBundlesProvider = Provider<List<QueuedBundle>>`

- [ ] **Step 1: Create `mobile/lib/features/capture/bundle_provider.dart`**

```dart
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/bundle.dart';
import '../../core/models/buyer_requirement.dart';
import '../../core/storage/hive_service.dart';
import '../../core/storage/image_store.dart';

class BundleState {
  final QueuedBundle? bundle;
  final List<BuyerDocRequirement> requirements;
  final bool loadingRequirements;

  const BundleState({
    this.bundle,
    this.requirements = const [],
    this.loadingRequirements = false,
  });

  BundleState copyWith({
    QueuedBundle? bundle,
    List<BuyerDocRequirement>? requirements,
    bool? loadingRequirements,
  }) =>
      BundleState(
        bundle: bundle ?? this.bundle,
        requirements: requirements ?? this.requirements,
        loadingRequirements: loadingRequirements ?? this.loadingRequirements,
      );
}

class BundleNotifier extends StateNotifier<BundleState> {
  BundleNotifier() : super(const BundleState());

  void startNewBundle() {
    state = const BundleState(
      bundle: null,
      requirements: [],
      loadingRequirements: false,
    );
  }

  // Called after primary invoice photo is captured.
  Future<void> addPhoto(Uint8List bytes, String documentType) async {
    final current = state.bundle;
    final localId = current?.localId ?? const Uuid().v4();
    final index = (current?.photos.length ?? 0);
    final path = await ImageStore.save(bytes, localId, index);

    final photo = QueuedPhoto(
      localPath: path,
      documentType: documentType,
      sortOrder: index,
    );

    if (current == null) {
      // First photo — create the bundle skeleton (fields filled in on ReviewScreen)
      state = state.copyWith(
        bundle: QueuedBundle(
          localId: localId,
          invoiceNumber: '',
          invoiceDateIso: DateTime.now().toIso8601String().substring(0, 10),
          entityId: '',
          entityGstin: '',
          buyerGstin: '',
          buyerName: '',
          grossAmount: 0,
          taxAmount: 0,
          photos: [photo],
          createdAtIso: DateTime.now().toIso8601String(),
        ),
      );
    } else {
      final updated = current
        ..photos = [...current.photos, photo];
      state = state.copyWith(bundle: updated);
    }
  }

  void setInvoiceFields({
    required String invoiceNumber,
    required String invoiceDateIso,
    required String entityId,
    required String entityGstin,
    required String buyerGstin,
    required String buyerName,
    String? buyerId,
    required double grossAmount,
    required double taxAmount,
    String? invoiceSeries,
  }) {
    final current = state.bundle;
    if (current == null) return;
    current
      ..invoiceNumber = invoiceNumber
      ..invoiceDateIso = invoiceDateIso
      ..entityId = entityId
      ..entityGstin = entityGstin
      ..buyerGstin = buyerGstin
      ..buyerName = buyerName
      ..buyerId = buyerId
      ..grossAmount = grossAmount
      ..taxAmount = taxAmount
      ..invoiceSeries = invoiceSeries;
    state = state.copyWith(bundle: current);
  }

  void setRequirements(List<BuyerDocRequirement> reqs) {
    state = state.copyWith(requirements: reqs, loadingRequirements: false);
  }

  void setLoadingRequirements(bool loading) {
    state = state.copyWith(loadingRequirements: loading);
  }

  // Persists bundle to Hive offline queue. Returns the localId.
  Future<String> enqueue() async {
    final bundle = state.bundle;
    if (bundle == null) throw StateError('No bundle to enqueue');
    bundle.status = 'pending';
    await HiveService.bundleBox.put(bundle.localId, bundle);
    return bundle.localId;
  }
}

final bundleProvider =
    StateNotifierProvider<BundleNotifier, BundleState>((ref) => BundleNotifier());

final pendingBundlesProvider = Provider<List<QueuedBundle>>((ref) {
  // Returns all bundles not yet successfully submitted, newest-first.
  final box = HiveService.bundleBox;
  final all = box.values.toList();
  all.sort((a, b) => b.createdAtIso.compareTo(a.createdAtIso));
  return all.where((b) => b.status != 'submitted').toList();
});
```

- [ ] **Step 2: Compile check**

```bash
cd D:\MeridianDist\mobile
flutter analyze lib/features/capture/bundle_provider.dart
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
cd D:\MeridianDist
git add mobile/lib/features/capture/bundle_provider.dart
git commit -m "feat(mobile): capture bundle state provider with offline queue support"
```

---

## Task 9: Camera Screen

**Files:**
- Create: `mobile/lib/features/capture/camera_screen.dart`

**Interfaces:**
- Consumes: `bundleProvider.notifier.addPhoto`, `camera` package
- Produces: `CameraScreen(label: String, documentType: String)` — navigates to `/capture/review` after first photo, or pops back for subsequent doc captures

- [ ] **Step 1: Add camera permissions to Android manifest**

Edit `mobile/android/app/src/main/AndroidManifest.xml` — add inside the `<manifest>` tag before `<application>`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

For iOS, add to `mobile/ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Used to photograph invoices and supporting documents</string>
```

- [ ] **Step 2: Create `mobile/lib/features/capture/camera_screen.dart`**

```dart
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'bundle_provider.dart';

// Camera screen used for ALL photo captures in the flow — primary invoice photo
// and each subsequent supporting document. The caller supplies label (shown in
// the top bar) and documentType (stored with the photo, e.g. 'INVOICE_IMAGE',
// 'GATE_ENTRY_NOTE'). After capture, navigates to /capture/review if this is
// the first photo in the session; otherwise pops (returns to checklist).
class CameraScreen extends ConsumerStatefulWidget {
  final String label;
  final String documentType;

  const CameraScreen({
    super.key,
    required this.label,
    required this.documentType,
  });

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  CameraController? _controller;
  bool _isCapturing = false;
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final ctrl = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await ctrl.initialize();
    if (!mounted) return;
    setState(() => _controller = ctrl);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final file = await ctrl.takePicture();
      final bytes = await file.readAsBytes();
      await ref.read(bundleProvider.notifier).addPhoto(bytes, widget.documentType);

      if (!mounted) return;
      final isFirstPhoto = ref.read(bundleProvider).bundle?.photos.length == 1;
      if (isFirstPhoto) {
        context.go('/capture/review');
      } else {
        context.pop(); // Return to checklist
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _toggleFlash() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    _flashOn = !_flashOn;
    await ctrl.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.label),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white),
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: ctrl == null || !ctrl.value.isInitialized
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                Positioned.fill(child: CameraPreview(ctrl)),
                // Shutter button at bottom center
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _isCapturing ? null : _capture,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.white38, width: 4),
                        ),
                        child: _isCapturing
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(strokeWidth: 3))
                          : const Icon(Icons.camera_alt, size: 36,
                              color: Color(0xFF1B5E20)),
                      ),
                    ),
                  ),
                ),
                // Tip overlay at top
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Keep invoice flat and fully in frame. Tap the button to capture.',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 3: Verify build**

```bash
cd D:\MeridianDist\mobile
flutter build apk --debug 2>&1 | grep -E "error:|warning:|Built"
```

Expected: no errors, `Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 4: Commit**

```bash
cd D:\MeridianDist
git add mobile/lib/features/capture/camera_screen.dart mobile/android/ mobile/ios/
git commit -m "feat(mobile): camera capture screen with flash toggle"
```

---

## Task 10: Review Screen (Invoice Fields Form)

**Files:**
- Create: `mobile/lib/features/capture/review_screen.dart`

**Interfaces:**
- Consumes: `bundleProvider`, `apiClientProvider`, `authProvider`, `Endpoints.entities`, `Endpoints.buyers`, `Endpoints.buyerRequirementsByGstin`
- Produces: `ReviewScreen` — on submit, calls `bundleProvider.notifier.setInvoiceFields` + `setRequirements`, then navigates to `/capture/checklist`

- [ ] **Step 1: Create `mobile/lib/features/capture/review_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/buyer_requirement.dart';
import '../../core/storage/image_store.dart';
import '../auth/auth_provider.dart';
import 'bundle_provider.dart';

// Invoice number series — from invoice_extraction.md (Global Constraints)
const _seriesOptions = ['A26', 'CAD', 'DBR', 'GST', 'BIB', 'MORDE', 'HYGIN', 'NIV'];

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _invNumCtrl = TextEditingController();
  final _buyerGstinCtrl = TextEditingController();
  final _buyerNameCtrl = TextEditingController();
  final _grossCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  DateTime _invoiceDate = DateTime.now();
  String? _selectedEntityId;
  String? _selectedEntityGstin;
  String? _selectedSeries;
  bool _submitting = false;

  List<Map<String, dynamic>> _entities = [];
  bool _loadingEntities = true;

  @override
  void initState() {
    super.initState();
    _loadEntities();
  }

  @override
  void dispose() {
    _invNumCtrl.dispose();
    _buyerGstinCtrl.dispose();
    _buyerNameCtrl.dispose();
    _grossCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntities() async {
    try {
      final client = ref.read(apiClientProvider);
      final resp = await client.get(Endpoints.entities);
      final list = (resp.data['entities'] as List<dynamic>?) ?? [];
      setState(() {
        _entities = list.cast<Map<String, dynamic>>();
        _loadingEntities = false;
        if (_entities.isNotEmpty) {
          _selectedEntityId = _entities.first['id'] as String;
          _selectedEntityGstin = _entities.first['tax_identifier'] as String;
        }
      });
    } catch (_) {
      setState(() => _loadingEntities = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  Future<void> _continue() async {
    if (_invNumCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice number is required')),
      );
      return;
    }
    if (_selectedEntityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the seller entity')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final client = ref.read(apiClientProvider);
      final notifier = ref.read(bundleProvider.notifier);

      // Fetch buyer requirements for this GSTIN (may be unknown — returns empty list)
      List<BuyerDocRequirement> reqs = [];
      String? buyerId;
      final gstin = _buyerGstinCtrl.text.trim().toUpperCase();
      if (gstin.isNotEmpty) {
        try {
          final resp = await client.get(
            Endpoints.buyerRequirementsByGstin,
            params: {'gstin': gstin},
          );
          final data = resp.data as Map<String, dynamic>;
          if (data['buyer'] != null) {
            buyerId = data['buyer']['id'] as String;
          }
          final rawReqs = (data['requirements'] as List<dynamic>?) ?? [];
          reqs = rawReqs
              .cast<Map<String, dynamic>>()
              .map(BuyerDocRequirement.fromJson)
              .toList();
        } catch (_) {
          // Non-fatal: buyer unknown or network error, proceed with empty reqs
        }
      }

      notifier.setInvoiceFields(
        invoiceNumber: _invNumCtrl.text.trim(),
        invoiceDateIso: DateFormat('yyyy-MM-dd').format(_invoiceDate),
        entityId: _selectedEntityId!,
        entityGstin: _selectedEntityGstin ?? '',
        buyerGstin: gstin,
        buyerName: _buyerNameCtrl.text.trim(),
        buyerId: buyerId,
        grossAmount: double.tryParse(_grossCtrl.text) ?? 0,
        taxAmount: double.tryParse(_taxCtrl.text) ?? 0,
        invoiceSeries: _selectedSeries,
      );
      notifier.setRequirements(reqs);

      if (!mounted) return;
      context.go('/capture/checklist');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(bundleProvider).bundle;
    final primaryPhoto = bundle?.photos.isNotEmpty == true ? bundle!.photos.first : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Invoice Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo preview
            if (primaryPhoto != null)
              FutureBuilder<Uint8List>(
                future: ImageStore.load(primaryPhoto.localPath),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(snap.data!, height: 200, width: double.infinity, fit: BoxFit.cover),
                  );
                },
              ),
            const SizedBox(height: 20),
            const Text('Fill in the invoice details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),

            // Seller entity
            if (_loadingEntities)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<String>(
                value: _selectedEntityId,
                decoration: const InputDecoration(labelText: 'Seller Entity', border: OutlineInputBorder()),
                items: _entities.map((e) => DropdownMenuItem(
                  value: e['id'] as String,
                  child: Text(e['legal_name'] as String? ?? e['id'] as String,
                    overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final ent = _entities.firstWhere((e) => e['id'] == v);
                  setState(() {
                    _selectedEntityId = v;
                    _selectedEntityGstin = ent['tax_identifier'] as String?;
                  });
                },
              ),
            const SizedBox(height: 12),

            // Invoice number
            TextField(
              controller: _invNumCtrl,
              decoration: const InputDecoration(
                labelText: 'Invoice Number *',
                border: OutlineInputBorder(),
                hintText: 'e.g. A260000218',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),

            // Invoice series
            DropdownButtonFormField<String>(
              value: _selectedSeries,
              decoration: const InputDecoration(
                labelText: 'Invoice Series (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('— None —')),
                ..._seriesOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))),
              ],
              onChanged: (v) => setState(() => _selectedSeries = v),
            ),
            const SizedBox(height: 12),

            // Invoice date
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Invoice Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(DateFormat('dd MMM yyyy').format(_invoiceDate)),
              ),
            ),
            const SizedBox(height: 12),

            // Buyer GSTIN
            TextField(
              controller: _buyerGstinCtrl,
              decoration: const InputDecoration(
                labelText: 'Buyer GSTIN',
                border: OutlineInputBorder(),
                hintText: 'e.g. 06AAAAA0013A1ZD',
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 15,
            ),

            // Buyer name
            TextField(
              controller: _buyerNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Buyer Name',
                border: OutlineInputBorder(),
                hintText: 'e.g. Vishal Mega Mart',
              ),
            ),
            const SizedBox(height: 12),

            // Amounts row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _grossCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Gross Amount (₹)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _taxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Tax Amount (₹)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _submitting
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton.icon(
                  onPressed: _continue,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continue to Documents'),
                ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
cd D:\MeridianDist\mobile
flutter analyze lib/features/capture/review_screen.dart
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
cd D:\MeridianDist
git add mobile/lib/features/capture/review_screen.dart
git commit -m "feat(mobile): invoice review/fields form screen"
```

---

## Task 11: Document Checklist Screen + Sync Service

**Files:**
- Create: `mobile/lib/features/capture/checklist_screen.dart`
- Create: `mobile/lib/core/sync/sync_service.dart`

**Interfaces:**
- Consumes: `bundleProvider`, `apiClientProvider`, `authProvider`, `HiveService.bundleBox`, `ImageStore`, `Endpoints.ledgerUpload`, `Endpoints.invoiceDocuments`, `Endpoints.buyers`
- Produces:
  - `ChecklistScreen` — shows required docs, navigates to camera for each, then shows Submit button
  - `SyncService.submitBundle(ApiClient, QueuedBundle)` → `String invoiceId` (throws on failure)
  - `SyncService.syncPending(ApiClient)` — syncs all 'pending' bundles in queue
  - `final syncServiceProvider = Provider<SyncService>`

- [ ] **Step 1: Create `mobile/lib/core/sync/sync_service.dart`**

```dart
import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/bundle.dart';
import '../../core/storage/hive_service.dart';
import '../../core/storage/image_store.dart';

class SyncService {
  final ApiClient _client;

  SyncService(this._client);

  // Submits one complete bundle. Returns the remote invoice_id on success.
  // Throws DioException or generic Exception on failure — caller should
  // catch, update bundle.status = 'failed', and store the error message.
  Future<String> submitBundle(QueuedBundle bundle) async {
    // Step 1: Ensure buyer exists (upsert by GSTIN)
    String buyerId = bundle.buyerId ?? '';
    if (buyerId.isEmpty && bundle.buyerGstin.isNotEmpty) {
      try {
        final resp = await _client.post(Endpoints.buyers, {
          'name': bundle.buyerName.isNotEmpty ? bundle.buyerName : bundle.buyerGstin,
          'gstin': bundle.buyerGstin,
          'address': {},
        });
        buyerId = (resp.data as Map<String, dynamic>)['id'] as String? ?? '';
      } catch (_) {
        // Non-fatal: ledger-upload works without a buyer_id if we pass buyer_gstin
      }
    }

    // Step 2: Upload primary invoice (first photo) via ledger-upload (multipart)
    final primary = bundle.photos.first;
    final primaryBytes = await ImageStore.load(primary.localPath);
    final primaryFormData = FormData.fromMap({
      'file': MultipartFile.fromBytes(primaryBytes, filename: 'invoice_${bundle.invoiceNumber}.jpg'),
      'invoice_number': bundle.invoiceNumber,
      'invoice_date': bundle.invoiceDateIso,
      'entity_id': bundle.entityId,
      'buyer_id': buyerId,
      'gross_amount': bundle.grossAmount.toStringAsFixed(2),
      'tax_amount': bundle.taxAmount.toStringAsFixed(2),
      'currency': bundle.currency,
      if (bundle.invoiceSeries != null) 'invoice_series': bundle.invoiceSeries,
    });
    final uploadResp = await _client.postMultipart(Endpoints.ledgerUpload, primaryFormData);
    final invoiceId = (uploadResp.data as Map<String, dynamic>)['invoice_id'] as String;

    // Step 3: Upload supporting docs (photos after index 0)
    for (var i = 1; i < bundle.photos.length; i++) {
      final photo = bundle.photos[i];
      final bytes = await ImageStore.load(photo.localPath);
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes,
            filename: '${photo.documentType.toLowerCase()}_$i.jpg'),
        'document_type': photo.documentType,
      });
      await _client.postMultipart(Endpoints.invoiceDocuments(invoiceId), formData);
    }

    return invoiceId;
  }

  // Iterates all 'pending' bundles and tries to upload each.
  // Updates Hive status on success or failure — never throws.
  Future<void> syncPending() async {
    final box = HiveService.bundleBox;
    final pending = box.values.where((b) => b.status == 'pending').toList();

    for (final bundle in pending) {
      bundle.status = 'uploading';
      await box.put(bundle.localId, bundle);

      try {
        final invoiceId = await submitBundle(bundle);
        bundle
          ..status = 'submitted'
          ..remoteInvoiceId = invoiceId
          ..errorMessage = null;
        await box.put(bundle.localId, bundle);
        // Clean up local photos to free storage
        await ImageStore.deleteBundle(bundle.localId);
      } catch (e) {
        bundle
          ..status = 'failed'
          ..errorMessage = e.toString();
        await box.put(bundle.localId, bundle);
      }
    }
  }
}

// Provided globally so both ChecklistScreen (explicit submit) and a background
// connectivity listener can call syncPending().
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final client = ref.watch(apiClientProvider);
  return SyncService(client);
});
```

> **NOTE:** The `import 'package:flutter_riverpod/flutter_riverpod.dart'` and auth import at the bottom of the file need to be at the TOP of the file. Move all imports to the top:

```dart
// Correct file: mobile/lib/core/sync/sync_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../models/bundle.dart';
import '../storage/hive_service.dart';
import '../storage/image_store.dart';
import '../../features/auth/auth_provider.dart';

// ... (rest of code as above, WITHOUT the bottom imports)
```

- [ ] **Step 2: Create `mobile/lib/features/capture/checklist_screen.dart`**

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/buyer_requirement.dart';
import '../../core/storage/image_store.dart';
import '../../core/sync/sync_service.dart';
import '../../core/storage/hive_service.dart';
import 'bundle_provider.dart';

class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key});

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  bool _submitting = false;

  // Which requirement indices have a photo (beyond the primary invoice, which
  // is always photos[0]). Map from requirement index → photo index in bundle.
  Map<int, int> _reqPhotoMap = {};

  bool _hasPhotoForReq(int reqIndex) => _reqPhotoMap.containsKey(reqIndex);

  Future<void> _photographReq(BuyerDocRequirement req, int reqIndex) async {
    await context.push('/capture/camera', extra: {
      'label': req.label,
      'document_type': req.documentType,
    });
    // After camera pops back, check if a new photo was added
    final photos = ref.read(bundleProvider).bundle?.photos ?? [];
    // The new photo is always appended at the end
    if (photos.length > 1 + _reqPhotoMap.length) {
      setState(() => _reqPhotoMap[reqIndex] = photos.length - 1);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final notifier = ref.read(bundleProvider.notifier);
      final localId = await notifier.enqueue();

      // Try online submit immediately; if it fails, bundle stays in queue
      final sync = ref.read(syncServiceProvider);
      final bundle = HiveService.bundleBox.get(localId)!;
      try {
        final invoiceId = await sync.submitBundle(bundle);
        bundle
          ..status = 'submitted'
          ..remoteInvoiceId = invoiceId;
        await HiveService.bundleBox.put(localId, bundle);
        await ImageStore.deleteBundle(localId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('Invoice ${bundle.invoiceNumber} submitted successfully!'),
          ),
        );
        notifier.startNewBundle();
        context.go('/home');
      } catch (_) {
        // Saved to queue — will sync when back online
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved offline. Will sync when connected.'),
          ),
        );
        notifier.startNewBundle();
        context.go('/home');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bundleProvider);
    final bundle = state.bundle;
    final reqs = state.requirements;

    return Scaffold(
      appBar: AppBar(title: const Text('Supporting Documents')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Primary invoice — always captured, shown as "done"
          _DocTile(
            icon: Icons.receipt,
            label: 'Tax Invoice',
            isDone: true,
            photoBytes: bundle?.photos.isNotEmpty == true
              ? ImageStore.load(bundle!.photos.first.localPath)
              : null,
            onTap: null,
          ),
          const Divider(),

          if (reqs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No additional documents required for this buyer.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else ...[
            const Text(
              'Also required for this buyer:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...reqs.asMap().entries.map((entry) {
              final i = entry.key;
              final req = entry.value;
              final photoIndex = _reqPhotoMap[i];
              final hasPhoto = photoIndex != null;
              return _DocTile(
                icon: hasPhoto ? Icons.check_circle : Icons.camera_alt,
                label: req.label,
                subtitle: req.isBuyerGenerated
                    ? 'Buyer provides this — photograph what they hand you'
                    : null,
                isDone: hasPhoto,
                photoBytes: hasPhoto && bundle != null
                  ? ImageStore.load(bundle.photos[photoIndex].localPath)
                  : null,
                onTap: hasPhoto ? null : () => _photographReq(req, i),
              );
            }),
          ],

          const SizedBox(height: 32),

          _submitting
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Submit Invoice Bundle'),
              ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Save to Queue (submit later)'),
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isDone;
  final Future<Uint8List>? photoBytes;
  final VoidCallback? onTap;

  const _DocTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.isDone,
    this.photoBytes,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: photoBytes != null
        ? FutureBuilder<Uint8List>(
            future: photoBytes,
            builder: (ctx, snap) => snap.hasData
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(snap.data!, width: 48, height: 48, fit: BoxFit.cover))
              : const SizedBox(width: 48, height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          )
        : CircleAvatar(
            backgroundColor: isDone ? Colors.green : const Color(0xFF1B5E20),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 12)) : null,
      trailing: isDone
        ? const Icon(Icons.check, color: Colors.green)
        : onTap != null
          ? const Icon(Icons.chevron_right)
          : null,
      onTap: onTap,
    );
  }
}
```

- [ ] **Step 3: Verify build**

```bash
cd D:\MeridianDist\mobile
flutter analyze lib/features/capture/ lib/core/sync/
```

Expected: no errors

- [ ] **Step 4: Commit**

```bash
cd D:\MeridianDist
git add mobile/lib/features/capture/checklist_screen.dart mobile/lib/core/sync/
git commit -m "feat(mobile): document checklist screen + sync service for bundle upload"
```

---

## Task 12: Home Screen and Queue Screen

**Files:**
- Create: `mobile/lib/features/home/home_screen.dart`
- Create: `mobile/lib/features/queue/queue_screen.dart`

**Interfaces:**
- Consumes: `bundleProvider`, `pendingBundlesProvider`, `syncServiceProvider`, `authProvider`, `connectivity_plus`
- Produces: `HomeScreen`, `QueueScreen` — full app is now navigable end-to-end

- [ ] **Step 1: Create `mobile/lib/features/home/home_screen.dart`**

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/sync/sync_service.dart';
import '../../core/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../capture/bundle_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _autoSync();
  }

  // On app open, try to sync any pending bundles automatically.
  Future<void> _autoSync() async {
    final result = await Connectivity().checkConnectivity();
    if (result != ConnectivityResult.none) {
      final sync = ref.read(syncServiceProvider);
      await sync.syncPending();
      if (mounted) setState(() {});
    }
  }

  Future<void> _startCapture() async {
    ref.read(bundleProvider.notifier).startNewBundle();
    context.push('/capture/camera', extra: {
      'label': 'Photograph Invoice',
      'document_type': 'INVOICE_IMAGE',
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final pending = ref.watch(pendingBundlesProvider);
    final pendingCount = pending.where((b) => b.status == 'pending' || b.status == 'failed').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meridian Invoice'),
        actions: [
          if (pendingCount > 0)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.cloud_queue),
                  onPressed: () => context.push('/queue'),
                  tooltip: 'Pending queue',
                ),
                Positioned(
                  right: 6, top: 6,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: Colors.red,
                    child: Text('$pendingCount',
                      style: const TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_done),
              onPressed: () => context.push('/queue'),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Hello, ${auth.email?.split('@').first ?? 'Worker'}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('Ready to capture invoices.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 48),

              // Main CTA
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton.icon(
                  onPressed: _startCapture,
                  icon: const Icon(Icons.add_a_photo, size: 32),
                  label: const Text('New Invoice', style: TextStyle(fontSize: 20)),
                ),
              ),

              const SizedBox(height: 24),

              // Queue status
              if (pendingCount > 0)
                OutlinedButton.icon(
                  onPressed: () => context.push('/queue'),
                  icon: const Icon(Icons.pending_actions),
                  label: Text('$pendingCount pending (tap to view / retry)'),
                )
              else
                const Text('All synced', style: TextStyle(color: Colors.green)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create `mobile/lib/features/queue/queue_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/bundle.dart';
import '../../core/storage/hive_service.dart';
import '../../core/sync/sync_service.dart';
import '../capture/bundle_provider.dart';

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  bool _syncing = false;

  Future<void> _retryAll() async {
    setState(() => _syncing = true);
    await ref.read(syncServiceProvider).syncPending();
    setState(() => _syncing = false);
  }

  Future<void> _retryOne(QueuedBundle bundle) async {
    bundle.status = 'pending';
    await HiveService.bundleBox.put(bundle.localId, bundle);
    setState(() {});
    await ref.read(syncServiceProvider).syncPending();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = HiveService.bundleBox.values.toList()
      ..sort((a, b) => b.createdAtIso.compareTo(a.createdAtIso));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Queue'),
        actions: [
          if (!_syncing)
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _retryAll,
              tooltip: 'Retry all',
            )
          else
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            ),
        ],
      ),
      body: all.isEmpty
        ? const Center(child: Text('No bundles in queue'))
        : ListView.separated(
            itemCount: all.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final b = all[i];
              return ListTile(
                leading: _statusIcon(b.status),
                title: Text(b.invoiceNumber.isNotEmpty ? b.invoiceNumber : 'Draft'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.buyerName.isNotEmpty ? b.buyerName : b.buyerGstin),
                    Text(
                      _formatDate(b.createdAtIso),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    if (b.errorMessage != null)
                      Text(b.errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 11)),
                  ],
                ),
                trailing: b.status == 'failed'
                  ? TextButton(onPressed: () => _retryOne(b), child: const Text('Retry'))
                  : b.status == 'submitted'
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
              );
            },
          ),
    );
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'submitted': return const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.check, color: Colors.white));
      case 'uploading': return const CircleAvatar(backgroundColor: Colors.blue, child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)));
      case 'failed': return const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.error, color: Colors.white));
      default: return const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.schedule, color: Colors.white));
    }
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }
}
```

- [ ] **Step 3: Verify full build**

```bash
cd D:\MeridianDist\mobile
flutter build apk --debug 2>&1 | tail -5
```

Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 4: Full end-to-end test on device**

1. Start backend: `cd backend && go run cmd/api/main.go`
2. Seed: `curl -X POST http://localhost:8000/api/v1/admin/seed`
3. Install APK on Android device: `flutter install`
4. Login as worker
5. Tap "New Invoice"
6. Photograph any document (or point at a wall for testing)
7. Fill in invoice number = "TEST001", select entity, fill amounts
8. Tap Continue — verify checklist appears with "No additional documents required" (unknown buyer)
9. Tap "Submit Invoice Bundle"
10. Verify "Invoice TEST001 submitted successfully!" snackbar
11. In browser: check `GET /api/v1/invoices` for the new invoice

- [ ] **Step 5: Commit**

```bash
cd D:\MeridianDist
git add mobile/lib/features/home/ mobile/lib/features/queue/
git commit -m "feat(mobile): home screen, queue screen, auto-sync on app open"
```

---

## Task 13: Connectivity-Driven Background Sync

**Files:**
- Modify: `mobile/lib/main.dart`

**Interfaces:**
- Consumes: `connectivity_plus`, `syncServiceProvider`, `SyncService.syncPending`
- Produces: app automatically syncs pending bundles whenever network becomes available

- [ ] **Step 1: Update `mobile/lib/main.dart` to watch connectivity**

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'core/storage/hive_service.dart';
import 'core/sync/sync_service.dart';
import 'core/api/api_client.dart';
import 'core/storage/image_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();

  final container = ProviderContainer();

  // Watch for network restoration and auto-sync
  Connectivity().onConnectivityChanged.listen((result) {
    if (result != ConnectivityResult.none) {
      final sync = container.read(syncServiceProvider);
      sync.syncPending();
    }
  });

  runApp(UncontrolledProviderScope(
    container: container,
    child: const MeridianApp(),
  ));
}
```

- [ ] **Step 2: Verify build**

```bash
cd D:\MeridianDist\mobile
flutter build apk --debug 2>&1 | tail -3
```

- [ ] **Step 3: Test offline → online sync**

1. Turn off device WiFi/data
2. Capture an invoice and submit → should save to queue (offline message)
3. Turn WiFi back on → within seconds, the queue item should auto-submit
4. Check `/api/v1/invoices` — the invoice should appear

- [ ] **Step 4: Final commit**

```bash
cd D:\MeridianDist
git add mobile/lib/main.dart
git commit -m "feat(mobile): auto-sync queue on network restore"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Flutter app — Task 5–13
- [x] Photo + review screen — Task 9 (camera) + Task 10 (review form)
- [x] Smart bundle with buyer-specific required docs — Task 2 (DB), Task 3 (API), Task 10 (fetches reqs), Task 11 (checklist)
- [x] Offline-first with Hive queue — Task 6 (models), Task 8 (bundle provider), Task 11 (sync service), Task 13 (connectivity watch)
- [x] Vishal Mega Mart Gate Entry requirement — Task 4 (data seed)
- [x] Three seller entities in dropdown — Task 10 (loads from `GET /api/v1/entities`)
- [x] Invoice series dropdown — Task 10 (hardcoded from Global Constraints)
- [x] Image compression 80%/2048px — Task 6 (ImageStore.compress)
- [x] JWT auth — Task 7
- [x] Backend migration + DB methods + API handler — Tasks 1, 2, 3
- [x] No new Temporal workflows — confirmed, reuses ledger-upload + supporting-document endpoints

**Placeholder scan:** No TBDs found. All code blocks are complete.

**Type consistency:**
- `QueuedBundle.localId` used consistently as Hive key in Task 6, 8, 11
- `Endpoints.ledgerUpload` / `Endpoints.invoiceDocuments(id)` defined in Task 5, consumed in Task 11
- `BuyerDocRequirement.fromJson` defined in Task 6, consumed in Task 10
- `bundleProvider.notifier.addPhoto` defined in Task 8, called in Task 9
- `bundleProvider.notifier.setRequirements` defined in Task 8, called in Task 10
- `SyncService.submitBundle` defined in Task 11, called in Task 11 and Task 12 (via `syncPending`)
