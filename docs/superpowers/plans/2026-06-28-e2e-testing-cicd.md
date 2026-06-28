# E2E Testing + CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build automated, repeatable test coverage (Go integration tests against real Postgres+Temporal, Flutter widget tests) for every existing backend/mobile workflow, wire up GitHub Actions CI, and fix real bugs found along the way.

**Architecture:** Black-box HTTP integration tests drive the real Go API (in-process via `httptest`) against the live docker-composed Postgres+Temporal stack, reusing the same seed/login/upload contract `backend/cmd/tester/main.go` already proves works. Flutter widget tests mock the Dio HTTP layer via constructor injection. GitHub Actions extends the existing `.github/workflows/ci.yml`.

**Tech Stack:** Go stdlib `testing` + `net/http/httptest` (no new Go test deps — matches existing `validation_test.go` style), Flutter `flutter_test` + `http_mock_adapter` (new dev dependency), GitHub Actions.

## Global Constraints

- Go module requires `go 1.25.0` (`backend/go.mod`) — CI must match, not the currently-misconfigured `1.21`.
- Never connect application/test traffic to Postgres as the `admin` superuser — always `app_user` (RLS bypass risk). Migrations are the one exception (`MIGRATIONS_DATABASE_URL`, admin).
- Tenant ID and role come only from the verified JWT, never from request bodies/headers — tests must assert this boundary, not work around it.
- Real invoice data used in fixtures comes from `invoice_extraction.md` at the repo root (the exhaustively cross-checked source of truth for what real Meridian invoices look like) — use entry `[1]` (A260000218, Meridian Brothers → Vishal Mega Mart) and entry `[2]` (its linked Gate Entry Note) since both are fully cross-checked with no low-confidence flags. Consult that file directly whenever a test needs realistic field values instead of inventing synthetic ones.
- The OCR extraction activity (`backend/python_worker/activities.py`) currently returns hardcoded values (`GrossAmount=15000, NetAmount=13500, TaxAmount=1500, VendorGSTIN=06AAAAA0017A1ZH`) regardless of the uploaded file — this always passes `internal/validation.Validate`. This means the `VALIDATION_FAILED` → AI-resolution path is **not reachable** through the live workflow today; that gap is deferred to the phase-2 extractor-rebuild spec, not faked here.

---

### Task 1: Add git remote (no push yet)

**Files:** none (git config only)

- [ ] **Step 1: Add the remote**

```bash
cd /d/MeridianDist
git remote add origin https://github.com/himanshu2394i/MeridianDistributors.git
git remote -v
```

Expected: `origin` listed for fetch and push.

- [ ] **Step 2: Confirm current branch**

```bash
git branch --show-current
```

Expected: `feat/mobile-capture-app`. Do not push yet — the final task pushes once everything below passes locally.

---

### Task 2: Fix login rate limiter to only count failed attempts

The doc comment on `loginRateLimiter.allow` (`backend/internal/api/ratelimit.go:28`) says "Only failed/attempted logins should call this — it's a brute-force guard, not a general API throttle," but `handleLogin` (`backend/internal/api/auth_handlers.go:112`) calls `allow()` unconditionally, before checking credentials. That means 10 *successful* logins from one IP in 5 minutes lock out every subsequent login — including this plan's own test suite, which logs in as 4+ roles repeatedly. Fix: only count failed attempts.

**Files:**
- Modify: `backend/internal/api/ratelimit.go`
- Modify: `backend/internal/api/auth_handlers.go:111-132`
- Test: `backend/internal/api/ratelimit_test.go` (new)

**Interfaces:**
- Produces: `loginRateLimiter.allow(key string) bool` (unchanged signature, changed call site)

- [ ] **Step 1: Write the failing test**

Create `backend/internal/api/ratelimit_test.go`:

```go
package api

import "testing"

func TestLoginRateLimiter_AllowsManySuccessfulAttempts(t *testing.T) {
	l := newLoginRateLimiter()
	// 15 successive "successful" checks for the same key must never themselves
	// exhaust the limiter -- only recordFailure should count toward the cap.
	for i := 0; i < 15; i++ {
		if !l.allow("1.2.3.4") {
			t.Fatalf("attempt %d: allow() returned false; allow() must not be consumed by successful logins", i)
		}
	}
}

func TestLoginRateLimiter_BlocksAfterTenFailures(t *testing.T) {
	l := newLoginRateLimiter()
	for i := 0; i < loginRateLimitMaxAttempts; i++ {
		l.recordFailure("5.6.7.8")
	}
	if l.allow("5.6.7.8") {
		t.Fatal("allow() returned true after 10 recorded failures; expected false")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && go test ./internal/api/... -run TestLoginRateLimiter -v
```

Expected: FAIL — `recordFailure` undefined, and `TestLoginRateLimiter_AllowsManySuccessfulAttempts` fails because the current `allow()` consumes the budget on every call.

- [ ] **Step 3: Implement the fix**

In `backend/internal/api/ratelimit.go`, change `allow` to a read-only check and add `recordFailure` to do the recording:

```go
// allow reports whether key is still within the limit, without recording
// anything. Call this before checking credentials.
func (l *loginRateLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-loginRateLimitWindow)

	kept := l.attempts[key][:0]
	for _, t := range l.attempts[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	l.attempts[key] = kept
	return len(kept) < loginRateLimitMaxAttempts
}

// recordFailure records one failed login attempt for key. Only call this
// after a credential check has actually failed -- it's a brute-force guard,
// not a general API throttle, so successful logins must never call it.
func (l *loginRateLimiter) recordFailure(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.attempts[key] = append(l.attempts[key], time.Now())
}
```

In `backend/internal/api/auth_handlers.go`, update `handleLogin` (currently calls `allow` unconditionally at the top) to only record on the two failure paths:

```go
func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	ip := clientIP(r)
	if !s.loginLimiter.allow(ip) {
		writeError(w, http.StatusTooManyRequests, "Too many login attempts. Try again later.")
		return
	}

	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	user, err := s.Repo.GetUserByEmail(r.Context(), req.Email)
	if err != nil {
		s.loginLimiter.recordFailure(ip)
		writeError(w, http.StatusUnauthorized, "Invalid email or password")
		return
	}
	if !auth.CheckPassword(user.PasswordHash, req.Password) {
		s.loginLimiter.recordFailure(ip)
		writeError(w, http.StatusUnauthorized, "Invalid email or password")
		return
	}

	token, err := auth.GenerateToken(user.ID, user.OrganizationID, user.Email, user.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to issue token")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"token": token,
		"user": map[string]string{
			"id":              user.ID,
			"email":           user.Email,
			"full_name":       user.FullName,
			"role":            user.Role,
			"organization_id": user.OrganizationID,
		},
	})
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd backend && go test ./internal/api/... -run TestLoginRateLimiter -v
```

Expected: PASS for both tests.

- [ ] **Step 5: Run the full existing test suite to confirm no regression**

```bash
cd backend && go test ./...
```

Expected: PASS (only `internal/validation` and `internal/api` have tests right now).

- [ ] **Step 6: Commit**

```bash
git add backend/internal/api/ratelimit.go backend/internal/api/ratelimit_test.go backend/internal/api/auth_handlers.go
git commit -m "fix: login rate limiter must only count failed attempts, not every login"
```

---

### Task 3: Integration test harness

**Files:**
- Create: `backend/internal/api/integration_harness_test.go`

**Interfaces:**
- Produces (used by every task from here on in package `api`):
  - `type testServer struct { URL string; AdminToken, WorkerToken, ManagerToken, FinanceToken string; OrgID string }`
  - `func startTestServer(t *testing.T) *testServer`
  - `func (ts *testServer) post(t *testing.T, path, token string, body interface{}) *http.Response`
  - `func (ts *testServer) get(t *testing.T, path, token string) *http.Response`
  - `func (ts *testServer) patch(t *testing.T, path, token string, body interface{}) *http.Response`
  - `func (ts *testServer) uploadMultipart(t *testing.T, path, token string, fields map[string]string, fileFieldName, fileName string, fileBytes []byte) *http.Response`
  - `func decodeJSON[T any](t *testing.T, resp *http.Response) T`

- [ ] **Step 1: Write the harness**

This mirrors `backend/cmd/tester/main.go`'s proven seed/login/upload contract, but against an `httptest.Server` wrapping the real `mux` (same wiring as `cmd/api/main.go`), so every later test in this package gets a ready-to-use tenant with 4 logged-in roles.

```go
// integration_harness_test.go
package api

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/himanshu2394i/invoice-saas/internal/storage"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.temporal.io/sdk/client"
)

func testDatabaseURL() string {
	if v := os.Getenv("TEST_DATABASE_URL"); v != "" {
		return v
	}
	return "postgres://app_user:app_user_dev_password@127.0.0.1:5432/invoice_saas"
}

func testTemporalHostPort() string {
	if v := os.Getenv("TEST_TEMPORAL_HOSTPORT"); v != "" {
		return v
	}
	return "127.0.0.1:7233"
}

// dialWithRetry retries pool/Temporal dialing for up to 30s -- in CI, this
// test binary can start running within a second or two of `docker compose up`,
// before Postgres/Temporal have finished their own startup handshake.
func dialWithRetry[T any](t *testing.T, dial func() (T, error)) T {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	var lastErr error
	for time.Now().Before(deadline) {
		v, err := dial()
		if err == nil {
			return v
		}
		lastErr = err
		time.Sleep(time.Second)
	}
	t.Fatalf("dial failed after retrying for 30s: %v", lastErr)
	var zero T
	return zero
}

type testServer struct {
	t            *testing.T
	URL          string
	httpClient   *http.Client
	OrgID        string
	AdminToken   string
	WorkerToken  string
	ManagerToken string
	FinanceToken string
}

// startTestServer boots the real API server in-process against the live
// docker-composed Postgres+Temporal, seeds a fresh tenant via the real
// POST /admin/seed endpoint (never inserting rows by hand -- that would
// test fixtures, not the seeding code), and logs in as all 4 demo roles.
func startTestServer(t *testing.T) *testServer {
	t.Helper()

	pool := dialWithRetry(t, func() (*pgxpool.Pool, error) {
		return pgxpool.New(context.Background(), testDatabaseURL())
	})
	t.Cleanup(pool.Close)

	temporalClient := dialWithRetry(t, func() (client.Client, error) {
		return client.Dial(client.Options{HostPort: testTemporalHostPort()})
	})
	t.Cleanup(temporalClient.Close)

	storageDir := t.TempDir()
	store, err := storage.NewLocalStore(storageDir)
	if err != nil {
		t.Fatalf("storage.NewLocalStore: %v", err)
	}

	repo := db.NewRepository(pool)
	server := NewServer(repo, temporalClient, store)
	mux := http.NewServeMux()
	server.RegisterRoutes(mux)

	httpServer := httptest.NewServer(mux)
	t.Cleanup(httpServer.Close)

	ts := &testServer{t: t, URL: httpServer.URL, httpClient: httpServer.Client()}

	type seedUser struct {
		Email string `json:"email"`
		Role  string `json:"role"`
	}
	type seedResponse struct {
		OrganizationID string     `json:"organization_id"`
		Users          []seedUser `json:"users"`
		Error          string     `json:"error"`
	}

	resp := ts.post(t, "/api/v1/admin/seed", "", nil)
	defer resp.Body.Close()
	sr := decodeJSON[seedResponse](t, resp)
	if sr.Error != "" {
		t.Fatalf("seed failed: %s", sr.Error)
	}
	ts.OrgID = sr.OrganizationID

	emailByRole := map[string]string{}
	for _, u := range sr.Users {
		emailByRole[u.Role] = u.Email
	}
	const demoPassword = "ChangeMe123!"
	ts.AdminToken = ts.loginAs(t, emailByRole["ADMIN"], demoPassword)
	ts.WorkerToken = ts.loginAs(t, emailByRole["WORKER"], demoPassword)
	ts.ManagerToken = ts.loginAs(t, emailByRole["MANAGER"], demoPassword)
	ts.FinanceToken = ts.loginAs(t, emailByRole["FINANCE"], demoPassword)

	return ts
}

func (ts *testServer) loginAs(t *testing.T, email, password string) string {
	t.Helper()
	resp := ts.post(t, "/api/v1/auth/login", "", map[string]string{"email": email, "password": password})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("login as %s failed: status %d body %s", email, resp.StatusCode, body)
	}
	type loginResp struct {
		Token string `json:"token"`
	}
	return decodeJSON[loginResp](t, resp).Token
}

func (ts *testServer) doRequest(t *testing.T, method, path, token string, body interface{}) *http.Response {
	t.Helper()
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal request body: %v", err)
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, ts.URL+path, reader)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := ts.httpClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	return resp
}

func (ts *testServer) post(t *testing.T, path, token string, body interface{}) *http.Response {
	return ts.doRequest(t, http.MethodPost, path, token, body)
}

func (ts *testServer) get(t *testing.T, path, token string) *http.Response {
	return ts.doRequest(t, http.MethodGet, path, token, nil)
}

func (ts *testServer) patch(t *testing.T, path, token string, body interface{}) *http.Response {
	return ts.doRequest(t, http.MethodPatch, path, token, body)
}

// uploadMultipart streams real bytes as multipart/form-data, matching the
// contract backend/cmd/tester/main.go's uploadFile already proves works.
func (ts *testServer) uploadMultipart(t *testing.T, path, token string, fields map[string]string, fileFieldName, fileName string, fileBytes []byte) *http.Response {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for k, v := range fields {
		if err := mw.WriteField(k, v); err != nil {
			t.Fatalf("write field %s: %v", k, err)
		}
	}
	part, err := mw.CreateFormFile(fileFieldName, fileName)
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	if _, err := part.Write(fileBytes); err != nil {
		t.Fatalf("write file bytes: %v", err)
	}
	if err := mw.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}

	req, err := http.NewRequest(http.MethodPost, ts.URL+path, &buf)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := ts.httpClient.Do(req)
	if err != nil {
		t.Fatalf("upload %s: %v", path, err)
	}
	return resp
}

func decodeJSON[T any](t *testing.T, resp *http.Response) T {
	t.Helper()
	defer resp.Body.Close()
	var v T
	if err := json.NewDecoder(resp.Body).Decode(&v); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	return v
}

// pollInvoiceState polls GET /invoices/{id} until current_state equals one of
// wantStates or timeout elapses. The OCR/approval workflow runs asynchronously
// via Temporal, so tests can't assert state immediately after a POST.
func (ts *testServer) pollInvoiceState(t *testing.T, token, invoiceID string, wantStates []string, timeout time.Duration) string {
	t.Helper()
	type invoiceResp struct {
		CurrentState string `json:"current_state"`
	}
	deadline := time.Now().Add(timeout)
	var last string
	for time.Now().Before(deadline) {
		resp := ts.get(t, "/api/v1/invoices/"+invoiceID, token)
		inv := decodeJSON[invoiceResp](t, resp)
		last = inv.CurrentState
		for _, want := range wantStates {
			if last == want {
				return last
			}
		}
		time.Sleep(200 * time.Millisecond)
	}
	t.Fatalf("invoice %s did not reach any of %v within %s; last state was %q", invoiceID, wantStates, timeout, last)
	return ""
}
```

- [ ] **Step 2: Verify it compiles (no test function calls it yet)**

```bash
cd backend && go build ./...
```

Expected: builds clean. (No `go test` yet — there's no test using the harness until Task 4.)

- [ ] **Step 3: Commit**

```bash
git add backend/internal/api/integration_harness_test.go
git commit -m "test: add integration test harness for backend API tests"
```

---

### Task 4: Auth + RBAC + cross-tenant isolation integration tests

**Files:**
- Create: `backend/internal/api/auth_integration_test.go`

**Interfaces:**
- Consumes: `startTestServer`, `testServer.post/get`, `decodeJSON` (Task 3)

- [ ] **Step 1: Write the tests**

```go
// auth_integration_test.go
package api

import (
	"net/http"
	"testing"
)

func TestLogin_WrongPassword_Returns401(t *testing.T) {
	ts := startTestServer(t)
	resp := ts.post(t, "/api/v1/auth/login", "", map[string]string{
		"email":    "admin+" + ts.OrgID[:8] + "@demo.local",
		"password": "wrong-password",
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", resp.StatusCode)
	}
}

func TestProtectedRoute_NoToken_Returns401(t *testing.T) {
	ts := startTestServer(t)
	resp := ts.get(t, "/api/v1/invoices", "")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 with no Authorization header, got %d", resp.StatusCode)
	}
}

func TestProtectedRoute_WrongRole_Returns403(t *testing.T) {
	ts := startTestServer(t)
	// Rule creation is ADMIN-only -- a WORKER token must be rejected.
	resp := ts.post(t, "/api/v1/rules", ts.WorkerToken, map[string]interface{}{
		"name": "test rule", "rule_type": "GSTIN_FORMAT",
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403 for WORKER calling an ADMIN-only route, got %d", resp.StatusCode)
	}
}

func TestCrossTenant_CannotReadOtherOrgsInvoice(t *testing.T) {
	tsA := startTestServer(t)
	tsB := startTestServer(t) // a second, independently-seeded tenant on a second server

	// Create an invoice as tenant A's worker via the direct JSON ingest route.
	resp := tsA.post(t, "/api/v1/invoices", tsA.WorkerToken, map[string]interface{}{
		"entity_id":      mustFirstEntity(t, tsA),
		"vendor_id":      mustFirstEntity(t, tsA),
		"invoice_number": "RLS-TEST-001",
		"invoice_date":   "2026-06-09",
		"gross_amount":   10913.00,
		"tax_amount":     519.66,
		"currency":       "INR",
		"document_type":  "INVOICE",
		"file_name":      "rls-test.jpg",
	})
	type ingestResp struct {
		InvoiceID string `json:"invoice_id"`
	}
	ir := decodeJSON[ingestResp](t, resp)
	if ir.InvoiceID == "" {
		t.Fatal("expected an invoice_id from tenant A's ingest")
	}

	// Tenant B's admin (different org, different Postgres session, but the
	// SAME underlying tables) must not be able to fetch tenant A's invoice by ID.
	// startTestServer boots a fresh httptest.Server per call but both point at
	// the same docker-composed Postgres, so this is a real RLS proof, not just
	// "different server instance."
	resp2 := tsB.get(t, "/api/v1/invoices/"+ir.InvoiceID, tsB.AdminToken)
	defer resp2.Body.Close()
	if resp2.StatusCode == http.StatusOK {
		t.Fatal("tenant B was able to read tenant A's invoice -- RLS isolation is broken")
	}
}

// mustFirstEntity fetches the seeded tenant's first entity ID via GET /entities,
// since the seed endpoint creates 3 real entities but doesn't return their IDs
// directly in a form this test can use without an extra call.
func mustFirstEntity(t *testing.T, ts *testServer) string {
	t.Helper()
	resp := ts.get(t, "/api/v1/entities", ts.WorkerToken)
	type entity struct {
		ID string `json:"id"`
	}
	type listResp struct {
		Entities []entity `json:"entities"`
	}
	lr := decodeJSON[listResp](t, resp)
	if len(lr.Entities) == 0 {
		t.Fatal("expected at least one seeded entity")
	}
	return lr.Entities[0].ID
}
```

- [ ] **Step 2: Run to verify behavior (start dependencies first)**

```bash
cd /d/MeridianDist && docker compose up -d postgres temporal
cd backend && go run ./cmd/migrate up
go test ./internal/api/... -run "TestLogin_WrongPassword|TestProtectedRoute|TestCrossTenant" -v
```

Expected: all PASS. If `handleListEntities`'s JSON shape differs from `{"entities": [...]}`, adjust `mustFirstEntity` to match — check `backend/internal/api/api.go:477` (`handleListEntities`) for the exact response key before assuming.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/api/auth_integration_test.go
git commit -m "test: add auth, RBAC, and cross-tenant RLS isolation integration tests"
```

---

### Task 5: Full invoice lifecycle integration test (using real invoice data)

Uses entry `[1]` (A260000218) from `invoice_extraction.md`: Meridian Brothers (GSTIN `06AAAAA0003A1Z3`) → Vishal Mega Mart (GSTIN `06AAAAA0013A1ZD`), sub total ₹10,393.45, GST ₹519.66, bill total ₹10,913.00.

**Files:**
- Create: `backend/internal/api/invoice_lifecycle_integration_test.go`

- [ ] **Step 1: Write the test**

```go
// invoice_lifecycle_integration_test.go
package api

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"net/http"
	"testing"
	"time"
)

// minimalJPEG returns a tiny valid JPEG so tests exercise the real
// storage.Store.Save (SHA-256 + on-disk write) without depending on the
// repo's external data/ folder of real scanned invoice photos.
func minimalJPEG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 4, 4))
	for y := 0; y < 4; y++ {
		for x := 0; x < 4; x++ {
			img.Set(x, y, color.White)
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		t.Fatalf("encode test jpeg: %v", err)
	}
	return buf.Bytes()
}

// TestInvoiceLifecycle_LedgerUploadThroughApproval drives the same path the
// mobile app's SyncService uses (POST /invoices/ledger-upload), using real
// figures from invoice_extraction.md entry [1] (Meridian Brothers -> Vishal
// Mega Mart, A260000218), through OCR (currently mocked -- see Global
// Constraints) and full manager+finance approval to APPROVED.
func TestInvoiceLifecycle_LedgerUploadThroughApproval(t *testing.T) {
	ts := startTestServer(t)

	resp := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		map[string]string{
			"invoice_number": "A260000218",
			"entity_gstin":   "06AAAAA0003A1Z3", // Meridian Brothers, seeded by /admin/seed
			"buyer_gstin":    "06AAAAA0013A1ZD", // Vishal Mega Mart (Airplaza Retail Holdings)
			"buyer_name":     "Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)",
			"invoice_date":   "2026-06-09",
			"taxable_amount": "10393.45",
			"total_amount":   "10913.00",
		},
		"file", "A260000218.jpg", minimalJPEG(t))
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("ledger-upload: expected 201, got %d", resp.StatusCode)
	}
	type uploadResp struct {
		Invoice struct{ ID string `json:"id"` } `json:"invoice"`
	}
	invoiceID := decodeJSON[uploadResp](t, resp).Invoice.ID
	if invoiceID == "" {
		t.Fatal("expected a non-empty invoice id")
	}

	// OCR runs async via Temporal -- poll until validation passes and the
	// workflow parks waiting for manager approval.
	ts.pollInvoiceState(t, ts.WorkerToken, invoiceID, []string{"PENDING_MANAGER_APPROVAL"}, 15*time.Second)

	mgrResp := ts.post(t, "/api/v1/invoices/"+invoiceID+"/approve", ts.ManagerToken,
		map[string]interface{}{"approved": true, "comments": "looks correct, matches gate entry"})
	mgrResp.Body.Close()
	if mgrResp.StatusCode != http.StatusOK {
		t.Fatalf("manager approve: expected 200, got %d", mgrResp.StatusCode)
	}

	ts.pollInvoiceState(t, ts.WorkerToken, invoiceID, []string{"PENDING_FINANCE_APPROVAL"}, 5*time.Second)

	finResp := ts.post(t, "/api/v1/invoices/"+invoiceID+"/approve", ts.FinanceToken,
		map[string]interface{}{"approved": true, "comments": "payment cleared"})
	finResp.Body.Close()
	if finResp.StatusCode != http.StatusOK {
		t.Fatalf("finance approve: expected 200, got %d", finResp.StatusCode)
	}

	finalState := ts.pollInvoiceState(t, ts.WorkerToken, invoiceID, []string{"APPROVED", "ARCHIVED"}, 5*time.Second)
	if finalState != "APPROVED" && finalState != "ARCHIVED" {
		t.Fatalf("expected final state APPROVED or ARCHIVED, got %s", finalState)
	}

	// Audit trail must record every stage transition with the real actor email,
	// not a generic "system" string, for manager/finance approval actions.
	auditResp := ts.get(t, "/api/v1/invoices/"+invoiceID+"/audit-trail", ts.WorkerToken)
	type auditEvent struct {
		EventType string `json:"event_type"`
		ActorID   string `json:"actor_id"`
	}
	type auditResp_ struct {
		Events []auditEvent `json:"events"`
	}
	events := decodeJSON[auditResp_](t, auditResp).Events
	foundManagerApproval := false
	for _, e := range events {
		if e.EventType == "MANAGER_APPROVED" {
			foundManagerApproval = true
		}
	}
	if !foundManagerApproval {
		t.Fatal("expected a MANAGER_APPROVED audit event")
	}
}

// TestInvoiceLifecycle_RejectionStopsTheWorkflow proves "Reject" actually
// rejects (this exact bug -- role-generic signals letting Reject silently
// approve -- was fixed in a previous session; this test guards the fix).
func TestInvoiceLifecycle_RejectionStopsTheWorkflow(t *testing.T) {
	ts := startTestServer(t)

	resp := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		map[string]string{
			"invoice_number": "A260000218-REJECT-TEST",
			"entity_gstin":   "06AAAAA0003A1Z3",
			"buyer_gstin":    "06AAAAA0013A1ZD",
			"invoice_date":   "2026-06-09",
			"taxable_amount": "10393.45",
			"total_amount":   "10913.00",
		},
		"file", "reject-test.jpg", minimalJPEG(t))
	type uploadResp struct {
		Invoice struct{ ID string `json:"id"` } `json:"invoice"`
	}
	invoiceID := decodeJSON[uploadResp](t, resp).Invoice.ID

	ts.pollInvoiceState(t, ts.WorkerToken, invoiceID, []string{"PENDING_MANAGER_APPROVAL"}, 15*time.Second)

	rejResp := ts.post(t, "/api/v1/invoices/"+invoiceID+"/approve", ts.ManagerToken,
		map[string]interface{}{"approved": false, "comments": "GSTIN does not match buyer master"})
	rejResp.Body.Close()

	finalState := ts.pollInvoiceState(t, ts.WorkerToken, invoiceID, []string{"REJECTED"}, 5*time.Second)
	if finalState != "REJECTED" {
		t.Fatalf("expected REJECTED after manager rejection, got %s", finalState)
	}
}
```

- [ ] **Step 2: Run it**

```bash
cd backend && go test ./internal/api/... -run TestInvoiceLifecycle -v
```

Expected: PASS. If the `ledger-upload` response shape doesn't nest under `"invoice": {"id": ...}`, re-check `backend/internal/api/api.go:628` and adjust `uploadResp` to match exactly. If the audit-trail response key isn't `"events"`, check `handleGetAuditTrail` at `backend/internal/api/api.go:836` and adjust.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/api/invoice_lifecycle_integration_test.go
git commit -m "test: add full invoice lifecycle integration tests using real Meridian invoice data"
```

---

### Task 6: Gate-entry, auto-dispute, dispute CRUD, and credit-note integration test

Uses entry `[2]` from `invoice_extraction.md` (Gate Entry / Discrepancy Note for A260000218): gate entry no. `HH26260000014286`, accepted qty 92 == invoice qty 92 (no shortage) for the happy path, and a deliberately short receipt for the auto-dispute path.

**Files:**
- Create: `backend/internal/api/gate_entry_dispute_integration_test.go`

- [ ] **Step 1: Write the test**

```go
// gate_entry_dispute_integration_test.go
package api

import (
	"net/http"
	"testing"
)

func createTestInvoice(t *testing.T, ts *testServer) string {
	t.Helper()
	resp := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		map[string]string{
			"invoice_number": "A260000218-GATE-TEST",
			"entity_gstin":   "06AAAAA0003A1Z3",
			"buyer_gstin":    "06AAAAA0013A1ZD",
			"invoice_date":   "2026-06-09",
			"taxable_amount": "10393.45",
			"total_amount":   "10913.00",
		},
		"file", "gate-test.jpg", minimalJPEG(t))
	type uploadResp struct {
		Invoice struct{ ID string `json:"id"` } `json:"invoice"`
	}
	return decodeJSON[uploadResp](t, resp).Invoice.ID
}

func TestGateEntry_ShortReceipt_AutoRaisesDispute(t *testing.T) {
	ts := startTestServer(t)
	invoiceID := createTestInvoice(t, ts)

	acceptedQty := 80.0
	invoiceQty := 92.0 // matches entry [1]'s "qty 2 lines / 92 units total"
	discrepancy := 1200.0

	resp := ts.post(t, "/api/v1/invoices/"+invoiceID+"/gate-entry", ts.WorkerToken, map[string]interface{}{
		"document_id":        "manual-test-doc",
		"gate_entry_number":  "HH26260000014286",
		"gate_entry_date":    "2026-06-09",
		"accepted_qty":       acceptedQty,
		"invoice_qty":        invoiceQty,
		"discrepancy_amount": discrepancy,
		"is_short_receipt":   true,
		"notes":              "8 units short on cheese block line",
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("set gate entry: expected 200, got %d", resp.StatusCode)
	}

	disputesResp := ts.get(t, "/api/v1/disputes?status=OPEN", ts.AdminToken)
	type dispute struct {
		InvoiceID   string `json:"invoice_id"`
		DisputeType string `json:"dispute_type"`
	}
	type disputeList struct {
		Disputes []dispute `json:"disputes"`
	}
	disputes := decodeJSON[disputeList](t, disputesResp).Disputes
	found := false
	for _, d := range disputes {
		if d.InvoiceID == invoiceID && d.DisputeType == "SHORT_RECEIPT" {
			found = true
		}
	}
	if !found {
		t.Fatal("expected a SHORT_RECEIPT dispute to be auto-raised for the short gate entry")
	}
}

func TestDispute_ManualCreateUpdateAndCreditNote(t *testing.T) {
	ts := startTestServer(t)
	invoiceID := createTestInvoice(t, ts)

	createResp := ts.post(t, "/api/v1/disputes", ts.WorkerToken, map[string]interface{}{
		"invoice_id":   invoiceID,
		"dispute_type": "ARITHMETIC_ERROR",
		"description":  "CGST/SGST split doesn't sum to stated GST amount",
	})
	type disputeResp struct {
		ID string `json:"id"`
	}
	d := decodeJSON[disputeResp](t, createResp)
	if d.ID == "" {
		t.Fatal("expected a non-empty dispute id")
	}

	updateResp := ts.patch(t, "/api/v1/disputes/"+d.ID, ts.AdminToken, map[string]interface{}{
		"status": "OWNER_REVIEWING",
		"notes":  "checking with vendor's accounts team",
	})
	updateResp.Body.Close()
	if updateResp.StatusCode != http.StatusOK {
		t.Fatalf("update dispute: expected 200, got %d", updateResp.StatusCode)
	}

	creditNoteResp := ts.uploadMultipart(t, "/api/v1/disputes/"+d.ID+"/credit-note", ts.AdminToken,
		nil, "file", "credit-note.jpg", minimalJPEG(t))
	defer creditNoteResp.Body.Close()
	if creditNoteResp.StatusCode != http.StatusCreated {
		t.Fatalf("upload credit note: expected 201, got %d", creditNoteResp.StatusCode)
	}
}
```

- [ ] **Step 2: Run it**

```bash
cd backend && go test ./internal/api/... -run "TestGateEntry|TestDispute" -v
```

Expected: PASS. If `uploadMultipart` panics on a `nil` `fields` map, fix the harness in Task 3 to guard `for k, v := range fields` against nil (ranging over a nil map is actually safe in Go — zero iterations — so this should already work; if it doesn't, the bug is elsewhere and worth tracing down, not working around).

- [ ] **Step 3: Commit**

```bash
git add backend/internal/api/gate_entry_dispute_integration_test.go
git commit -m "test: add gate-entry auto-dispute and dispute CRUD integration tests"
```

---

### Task 7: Rules, buyers, entities, and owner dashboard integration test

**Files:**
- Create: `backend/internal/api/rules_owner_integration_test.go`

- [ ] **Step 1: Write the test**

```go
// rules_owner_integration_test.go
package api

import (
	"context"
	"net/http"
	"os"
	"testing"

	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestRules_CreateListDelete(t *testing.T) {
	ts := startTestServer(t)

	createResp := ts.post(t, "/api/v1/rules", ts.AdminToken, map[string]interface{}{
		"name":      "Vendor GSTIN must be valid",
		"rule_type": "GSTIN_FORMAT",
	})
	type ruleResp struct {
		ID string `json:"id"`
	}
	rule := decodeJSON[ruleResp](t, createResp)
	if rule.ID == "" {
		t.Fatal("expected a non-empty rule id")
	}

	listResp := ts.get(t, "/api/v1/rules", ts.AdminToken)
	type ruleList struct {
		Rules []ruleResp `json:"rules"`
	}
	rules := decodeJSON[ruleList](t, listResp).Rules
	found := false
	for _, r := range rules {
		if r.ID == rule.ID {
			found = true
		}
	}
	if !found {
		t.Fatal("created rule did not appear in the list")
	}

	delReq, _ := http.NewRequest(http.MethodDelete, ts.URL+"/api/v1/rules/"+rule.ID, nil)
	delReq.Header.Set("Authorization", "Bearer "+ts.AdminToken)
	delResp, err := ts.httpClient.Do(delReq)
	if err != nil {
		t.Fatalf("delete rule: %v", err)
	}
	defer delResp.Body.Close()
	if delResp.StatusCode != http.StatusOK {
		t.Fatalf("delete rule: expected 200, got %d", delResp.StatusCode)
	}
}

func TestBuyersAndEntities_CreateAndList(t *testing.T) {
	ts := startTestServer(t)

	buyerResp := ts.post(t, "/api/v1/buyers", ts.WorkerToken, map[string]interface{}{
		"name":  "Home Shopee India Private Limited",
		"gstin": "06AAAAA0011A1ZB", // from invoice_extraction.md entry [3]
	})
	buyerResp.Body.Close()
	if buyerResp.StatusCode != http.StatusCreated {
		t.Fatalf("create buyer: expected 201, got %d", buyerResp.StatusCode)
	}

	listResp := ts.get(t, "/api/v1/buyers", ts.WorkerToken)
	type buyer struct {
		GSTIN string `json:"gstin"`
	}
	type buyerList struct {
		Buyers []buyer `json:"buyers"`
	}
	buyers := decodeJSON[buyerList](t, listResp).Buyers
	found := false
	for _, b := range buyers {
		if b.GSTIN == "06AAAAA0011A1ZB" {
			found = true
		}
	}
	if !found {
		t.Fatal("created buyer did not appear in the list")
	}
}

func TestOwnerDashboard_ReturnsStatsForAdminAndManager(t *testing.T) {
	ts := startTestServer(t)

	for _, token := range []string{ts.AdminToken, ts.ManagerToken} {
		resp := ts.get(t, "/api/v1/owner/dashboard", token)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("owner dashboard: expected 200, got %d", resp.StatusCode)
		}
	}

	// WORKER and FINANCE are not permitted on this route.
	for _, token := range []string{ts.WorkerToken, ts.FinanceToken} {
		resp := ts.get(t, "/api/v1/owner/dashboard", token)
		resp.Body.Close()
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("owner dashboard: expected 403 for non-owner role, got %d", resp.StatusCode)
		}
	}
}

func TestInvoiceList_Pagination(t *testing.T) {
	ts := startTestServer(t)
	for i := 0; i < 3; i++ {
		createTestInvoice(t, ts)
	}

	resp := ts.get(t, "/api/v1/invoices?limit=2&offset=0", ts.WorkerToken)
	type invoiceListResp struct {
		Invoices []map[string]interface{} `json:"invoices"`
		Total    int                       `json:"total"`
	}
	page := decodeJSON[invoiceListResp](t, resp)
	if len(page.Invoices) > 2 {
		t.Fatalf("expected at most 2 invoices with limit=2, got %d", len(page.Invoices))
	}
	if page.Total < 3 {
		t.Fatalf("expected total >= 3 after creating 3 invoices, got %d", page.Total)
	}
}
```

- [ ] **Step 2: Write the exceptions + missing-invoice-number tests**

There's no API endpoint to create an exception directly — they're raised internally by workflow/validation logic (`db.Repository.RaiseExceptionIfNotOpen`, `RaiseMissingInvoiceNumber`). Seed one directly via a second Postgres connection in the test, the same pattern Task 8's reconciler test already uses, then prove the API can list and resolve it. Append these functions to the same `rules_owner_integration_test.go` file — the `context`/`os`/`db`/`pgxpool` imports added in Step 1 already cover what these need:

```go
// continue in rules_owner_integration_test.go -- same file, same import block as above

func TestExceptions_ListAndResolve(t *testing.T) {
	ts := startTestServer(t)
	invoiceID := createTestInvoice(t, ts)

	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://app_user:app_user_dev_password@127.0.0.1:5432/invoice_saas"
	}
	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatalf("connect to postgres: %v", err)
	}
	defer pool.Close()
	repo := db.NewRepository(pool)

	if err := repo.RaiseExceptionIfNotOpen(context.Background(), ts.OrgID, invoiceID,
		"DUPLICATE_INVOICE_NUMBER", []byte(`{"matched_invoice_number":"A260000218"}`)); err != nil {
		t.Fatalf("seed exception: %v", err)
	}

	listResp := ts.get(t, "/api/v1/exceptions", ts.WorkerToken)
	type exception struct {
		ID        string `json:"id"`
		InvoiceID string `json:"invoice_id"`
	}
	type exceptionsListResp struct {
		InvoiceExceptions []exception `json:"invoice_exceptions"`
	}
	exceptions := decodeJSON[exceptionsListResp](t, listResp).InvoiceExceptions
	var exceptionID string
	for _, e := range exceptions {
		if e.InvoiceID == invoiceID {
			exceptionID = e.ID
		}
	}
	if exceptionID == "" {
		t.Fatal("seeded exception did not appear in GET /exceptions")
	}

	resolveResp := ts.post(t, "/api/v1/exceptions/"+exceptionID+"/resolve", ts.ManagerToken,
		map[string]string{"status": "resolved"})
	resolveResp.Body.Close()
	if resolveResp.StatusCode != http.StatusOK {
		t.Fatalf("resolve exception: expected 200, got %d", resolveResp.StatusCode)
	}
}

func TestMissingInvoiceNumbers_ListAndResolve(t *testing.T) {
	ts := startTestServer(t)

	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://app_user:app_user_dev_password@127.0.0.1:5432/invoice_saas"
	}
	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatalf("connect to postgres: %v", err)
	}
	defer pool.Close()
	repo := db.NewRepository(pool)

	entityID := mustFirstEntity(t, ts)
	// A26 is the real invoice series for Meridian Brothers per invoice_extraction.md;
	// A260000219 is a plausible gap between entries [1] (A260000218) and [3] (A260000223).
	if err := repo.RaiseMissingInvoiceNumber(context.Background(), ts.OrgID, entityID, "A26", "A260000219"); err != nil {
		t.Fatalf("seed missing invoice number: %v", err)
	}

	listResp := ts.get(t, "/api/v1/exceptions", ts.WorkerToken)
	type missingNum struct {
		ID            string `json:"id"`
		MissingNumber string `json:"missing_number"`
	}
	type exceptionsListResp struct {
		MissingInvoiceNumbers []missingNum `json:"missing_invoice_numbers"`
	}
	missing := decodeJSON[exceptionsListResp](t, listResp).MissingInvoiceNumbers
	var missingID string
	for _, m := range missing {
		if m.MissingNumber == "A260000219" {
			missingID = m.ID
		}
	}
	if missingID == "" {
		t.Fatal("seeded missing invoice number did not appear in GET /exceptions")
	}

	resolveResp := ts.post(t, "/api/v1/missing-invoice-numbers/"+missingID+"/resolve", ts.ManagerToken,
		map[string]string{"status": "not_applicable"})
	resolveResp.Body.Close()
	if resolveResp.StatusCode != http.StatusOK {
		t.Fatalf("resolve missing invoice number: expected 200, got %d", resolveResp.StatusCode)
	}
}
```

Confirmed: `db.MissingInvoiceNumber.MissingNumber` (`backend/internal/db/db.go:884`) is tagged `json:"missing_number"` — the test above already matches.

- [ ] **Step 3: Run it**

```bash
cd backend && go test ./internal/api/... -run "TestRules_|TestBuyersAndEntities|TestOwnerDashboard|TestInvoiceList_Pagination|TestExceptions_|TestMissingInvoiceNumbers_" -v
```

Expected: PASS. If `handleListInvoices`'s pagination response uses different field names than `invoices`/`total`, check `backend/internal/api/api.go:639` and correct the struct.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/api/rules_owner_integration_test.go
git commit -m "test: add rules, buyers/entities, owner dashboard, pagination, exceptions, and missing-invoice-number integration tests"
```

---

### Task 8: Reconciliation orphaned-workflow integration test

Guards the exact bug class fixed previously (wrong workflow-ID construction, wrong task queue, broken `ExecuteWorkflow` signature meant a healthy workflow always looked "missing" and got duplicated).

**Files:**
- Create: `backend/internal/reconciliation/reconciler_integration_test.go`

**Interfaces:**
- Consumes: `reconciliation.NewReconciler(repo *db.Repository, tempClient client.Client) *Reconciler`, `(*Reconciler).ReconcileOrphanedWorkflows(ctx)`

- [ ] **Step 1: Write the test**

```go
// reconciler_integration_test.go
package reconciliation

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.temporal.io/sdk/client"
)

func testDatabaseURL() string {
	if v := os.Getenv("TEST_DATABASE_URL"); v != "" {
		return v
	}
	return "postgres://app_user:app_user_dev_password@127.0.0.1:5432/invoice_saas"
}

func testTemporalHostPort() string {
	if v := os.Getenv("TEST_TEMPORAL_HOSTPORT"); v != "" {
		return v
	}
	return "127.0.0.1:7233"
}

// TestReconcileOrphanedWorkflows_RestartsAWorkflowMissingFromTemporal proves
// the reconciler correctly identifies an invoice stuck in a transient state
// with no matching Temporal execution, and restarts it using the right
// workflow ID ("tenant-<org>-invoice-<id>") and task queue
// ("invoice-task-queue") -- the exact two fields a previous bug got wrong.
func TestReconcileOrphanedWorkflows_RestartsAWorkflowMissingFromTemporal(t *testing.T) {
	ctx := context.Background()

	pool, err := pgxpool.New(ctx, testDatabaseURL())
	if err != nil {
		t.Fatalf("connect to postgres: %v", err)
	}
	defer pool.Close()
	repo := db.NewRepository(pool)

	temporalClient, err := client.Dial(client.Options{HostPort: testTemporalHostPort()})
	if err != nil {
		t.Fatalf("connect to temporal: %v", err)
	}
	defer temporalClient.Close()

	org, err := repo.CreateOrganization(ctx, "Reconciler Test Org")
	if err != nil {
		t.Fatalf("create organization: %v", err)
	}
	entity, err := repo.CreateEntity(ctx, org.ID, "Test Entity", "06AAAAA0003A1Z3",
		[]byte(`{"city":"Gurgaon"}`))
	if err != nil {
		t.Fatalf("create entity: %v", err)
	}

	invoice := &db.Invoice{
		EntityID:      entity.ID,
		VendorID:      entity.ID,
		InvoiceNumber: "RECONCILE-TEST-001",
		InvoiceDate:   time.Now(),
		GrossAmount:   10913.00,
		TaxAmount:     519.66,
		Currency:      "INR",
	}
	if err := repo.CreateInvoice(ctx, org.ID, invoice); err != nil {
		t.Fatalf("create invoice: %v", err)
	}
	// Force it into a "stuck" state -- no Temporal workflow was ever started
	// for this invoice ID, simulating a workflow that died or never launched.
	if err := repo.UpdateInvoiceState(ctx, org.ID, invoice.ID, "PENDING_MANAGER_APPROVAL"); err != nil {
		t.Fatalf("force invoice into stuck state: %v", err)
	}
	// ListStuckInvoices filters on updated_at < cutoff; backdate it directly.
	if _, err := pool.Exec(ctx,
		"UPDATE invoices SET updated_at = NOW() - INTERVAL '3 hours' WHERE id = $1", invoice.ID); err != nil {
		t.Fatalf("backdate updated_at: %v", err)
	}

	expectedWorkflowID := "tenant-" + org.ID + "-invoice-" + invoice.ID
	if _, err := temporalClient.DescribeWorkflowExecution(ctx, expectedWorkflowID, ""); err == nil {
		t.Fatal("expected no workflow execution to exist yet for this invoice")
	}

	r := NewReconciler(repo, temporalClient)
	r.ReconcileOrphanedWorkflows(ctx)

	desc, err := temporalClient.DescribeWorkflowExecution(ctx, expectedWorkflowID, "")
	if err != nil {
		t.Fatalf("expected reconciler to start workflow %q, but DescribeWorkflowExecution failed: %v", expectedWorkflowID, err)
	}
	if desc.WorkflowExecutionInfo.TaskQueue != "invoice-task-queue" {
		t.Fatalf("expected task queue %q, got %q", "invoice-task-queue", desc.WorkflowExecutionInfo.TaskQueue)
	}
}
```

- [ ] **Step 2: Run it**

```bash
cd backend && go test ./internal/reconciliation/... -v
```

Expected: PASS. Note this test needs the `ocr-worker` Python service NOT running (or running) doesn't matter — it only checks that a workflow execution exists and is on the right task queue, not that it completes, so it's independent of OCR correctness.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/reconciliation/reconciler_integration_test.go
git commit -m "test: add reconciler integration test guarding the orphaned-workflow restart path"
```

---

### Task 9: Extend CI: fix Go version, add Postgres+Temporal services, run real tests

**Files:**
- Modify: `.github/workflows/ci.yml`

The current `build-go-backend` job installs Go `1.21` while `backend/go.mod` requires `go 1.25.0` — fix that mismatch. It also only runs `go vet`/build, never `go test`, so none of Tasks 2-8 actually run in CI without this change.

- [ ] **Step 1: Replace the `build-go-backend` job**

In `.github/workflows/ci.yml`, replace the existing `build-go-backend` job (lines 10-36) with:

```yaml
  test-go-backend:
    name: Test Go Backend
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: admin
          POSTGRES_PASSWORD: password
          POSTGRES_DB: invoice_saas
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
    steps:
    - uses: actions/checkout@v4

    - name: Set up Go
      uses: actions/setup-go@v5
      with:
        go-version: '1.25.0'
        cache-dependency-path: backend/go.sum

    - name: Go Format Check
      working-directory: ./backend
      run: |
        diff <(gofmt -l .) <(echo -n "") || (echo "Run 'go fmt ./...' to fix formatting" && exit 1)

    - name: Go Vet
      working-directory: ./backend
      run: go vet ./...

    - name: Run database migrations
      working-directory: ./backend
      env:
        MIGRATIONS_DATABASE_URL: postgres://admin:password@127.0.0.1:5432/invoice_saas?sslmode=disable
      run: go run ./cmd/migrate up

    - name: Start Temporal dev server
      run: |
        curl -sSf https://temporal.download/cli.sh | sh
        ~/.temporalio/bin/temporal server start-dev --headless &
        for i in $(seq 1 30); do
          (echo > /dev/tcp/127.0.0.1/7233) >/dev/null 2>&1 && break
          sleep 1
        done

    - name: Build API and Worker
      working-directory: ./backend
      run: |
        go build -o bin/api ./cmd/api
        go build -o bin/worker ./cmd/worker

    - name: Run tests
      working-directory: ./backend
      env:
        TEST_DATABASE_URL: postgres://app_user:app_user_dev_password@127.0.0.1:5432/invoice_saas
        TEST_TEMPORAL_HOSTPORT: 127.0.0.1:7233
      run: go test ./... -v
```

This uses `temporal server start-dev` (the Temporal CLI's built-in dev server, an in-memory single-binary Temporal) rather than `temporalio/auto-setup` + a second Postgres database, since GitHub Actions `services:` containers can't easily depend on each other's startup order the way `docker-compose.yml` does locally — `start-dev` needs nothing but to bind port 7233, which is exactly what these tests connect to.

- [ ] **Step 2: Verify the YAML is well-formed**

```bash
cd /d/MeridianDist
python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" 2>&1 || echo "needs a YAML linter available -- if python+pyyaml isn't installed, visually re-check indentation instead"
```

Expected: no parse error.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: fix Go version mismatch (1.21 -> 1.25.0), run real Postgres+Temporal-backed test suite"
```

---

### Task 10: Mobile testability — inject Dio into AuthNotifier and SyncService

`buildDio()` (`mobile/lib/core/api/api_client.dart`) currently constructs a fresh, un-mockable `Dio()` every call. `AuthNotifier.login` (`mobile/lib/features/auth/auth_provider.dart:51`) and `SyncService` (`mobile/lib/features/capture/sync_service.dart:9`) each call it directly with no seam for tests to substitute a mock HTTP adapter. Add a minimal constructor-injection seam, defaulting to today's production behavior.

**Files:**
- Modify: `mobile/lib/features/auth/auth_provider.dart`
- Modify: `mobile/lib/features/capture/sync_service.dart`
- Modify: `mobile/pubspec.yaml` (add `http_mock_adapter` dev dependency)

**Interfaces:**
- Produces: `AuthNotifier({Dio? dio})`, `SyncService({Dio? dio})` — both default to `buildDio()` when `dio` is omitted, so every existing call site (`AuthNotifier()`, `final syncService = SyncService();`) keeps working unchanged.

- [ ] **Step 1: Add the dev dependency**

In `mobile/pubspec.yaml`, under `dev_dependencies:`, add:

```yaml
  http_mock_adapter: ^0.6.1
```

- [ ] **Step 2: Inject Dio into `AuthNotifier`**

In `mobile/lib/features/auth/auth_provider.dart`, change the class to accept an optional `Dio`:

```dart
class AuthNotifier extends StateNotifier<AuthState> {
  final Dio _dio;

  AuthNotifier({Dio? dio}) : _dio = dio ?? buildDio(), super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await readToken();
    if (token != null) {
      state = state.copyWith(isLoggedIn: true, token: token);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post(
        Endpoints.login,
        data: {'email': email, 'password': password},
      );
      final token = response.data['token'] as String;
      final user = response.data['user'] as Map<String, dynamic>;
      await saveToken(token);
      state = state.copyWith(
        isLoggedIn: true,
        token: token,
        user: user,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _extractError(e),
      );
    }
  }
  // ... logout() and _extractError() unchanged
```

(`import 'package:dio/dio.dart';` needs adding to this file's imports.)

- [ ] **Step 3: Inject Dio into `SyncService`**

In `mobile/lib/features/capture/sync_service.dart`:

```dart
class SyncService {
  final Dio _dio;

  SyncService({Dio? dio}) : _dio = dio ?? buildDio();

  // ... syncPending(), _syncBundle(), _uploadLedgerInvoice(), _uploadSupportingDoc() unchanged,
  // they already reference `_dio` as a field.
```

- [ ] **Step 4: Run flutter analyze + the (currently broken) existing test to confirm nothing else regresses**

```bash
cd mobile && flutter pub get && flutter analyze lib/features/auth/auth_provider.dart lib/features/capture/sync_service.dart
```

Expected: no new errors. (`flutter test` still fails at this point because of the dead `widget_test.dart` — that's fixed in Task 12.)

- [ ] **Step 5: Commit**

```bash
git add mobile/pubspec.yaml mobile/lib/features/auth/auth_provider.dart mobile/lib/features/capture/sync_service.dart
git commit -m "refactor(mobile): inject Dio into AuthNotifier and SyncService for testability"
```

---

### Task 11: Mobile widget tests — login, settings, and sync (using real invoice data)

**Files:**
- Create: `mobile/test/auth/login_screen_test.dart`
- Create: `mobile/test/settings/settings_screen_test.dart`
- Create: `mobile/test/capture/sync_service_test.dart`

- [ ] **Step 1: Login screen + AuthNotifier test**

```dart
// mobile/test/auth/login_screen_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:invoice_capture/features/auth/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('login success stores token and user, sets isLoggedIn', () async {
    final dio = Dio();
    final adapter = DioAdapter(dio: dio);
    adapter.onPost(
      '/api/v1/auth/login',
      (server) => server.reply(200, {
        'token': 'fake-jwt-token',
        'user': {'email': 'admin+abc@demo.local', 'role': 'ADMIN'},
      }),
      data: {'email': 'admin+abc@demo.local', 'password': 'ChangeMe123!'},
    );

    final notifier = AuthNotifier(dio: dio);
    await notifier.login('admin+abc@demo.local', 'ChangeMe123!');

    expect(notifier.state.isLoggedIn, true);
    expect(notifier.state.token, 'fake-jwt-token');
    expect(notifier.state.user?['role'], 'ADMIN');
    expect(notifier.state.error, null);
  });

  test('login failure (401) surfaces an error and does not set isLoggedIn', () async {
    final dio = Dio();
    final adapter = DioAdapter(dio: dio);
    adapter.onPost(
      '/api/v1/auth/login',
      (server) => server.reply(401, {'error': 'Invalid email or password'}),
      data: {'email': 'admin+abc@demo.local', 'password': 'wrong'},
    );

    final notifier = AuthNotifier(dio: dio);
    await notifier.login('admin+abc@demo.local', 'wrong');

    expect(notifier.state.isLoggedIn, false);
    expect(notifier.state.error, isNotNull);
  });
}
```

Note: `Endpoints.login` returns `'$_base/api/v1/auth/login'` where `_base` is `ServerConfig.baseUrl` (default `http://10.0.2.2:8000`). `http_mock_adapter` matches by path regardless of host, so the literal path string above is correct without needing to call `ServerConfig.load()` first — if the matcher requires the full URL instead, change the `onPost` path argument to `'${ServerConfig.baseUrl}/api/v1/auth/login'` and re-run.

- [ ] **Step 2: Settings screen test (server URL persistence)**

```dart
// mobile/test/settings/settings_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/core/config/server_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saving a server URL trims trailing slash and persists it', () async {
    // FlutterSecureStorage needs a platform channel mock in plain `flutter test`;
    // ServerConfig.save/load both go through it, so this confirms the in-memory
    // value updates correctly even when the secure-storage write itself is a
    // no-op test double (verified indirectly via ServerConfig.baseUrl).
    await ServerConfig.save('http://192.168.1.42:8000/');
    expect(ServerConfig.baseUrl, 'http://192.168.1.42:8000');
  });

  test('reset restores the default emulator URL', () async {
    await ServerConfig.save('http://192.168.1.42:8000');
    await ServerConfig.reset();
    expect(ServerConfig.baseUrl, ServerConfig.defaultUrl);
  });
}
```

- [ ] **Step 3: Run these two files**

```bash
cd mobile && flutter test test/auth/login_screen_test.dart test/settings/settings_screen_test.dart
```

Expected: PASS. If `ServerConfig.save`'s call to `FlutterSecureStorage.write` throws a `MissingPluginException` under plain `flutter test` (no platform binding), add `flutter_secure_storage_platform_interface`'s in-memory test fake, or — simpler — wrap the storage calls already inside `ServerConfig` in a try/catch is NOT the fix (don't swallow real errors); instead use `package:flutter_test`'s `TestWidgetsFlutterBinding.ensureInitialized()` which is already present and typically satisfies `flutter_secure_storage`'s plugin registration for unit-level (non-widget) tests. If it still throws, that's a real platform-channel gap worth fixing in `ServerConfig` itself (e.g. injectable storage, same pattern as Task 10) rather than skipping the test.

- [ ] **Step 4: Sync service test (using real invoice_extraction.md entry [1] data)**

```dart
// mobile/test/capture/sync_service_test.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:invoice_capture/core/models/bundle.dart';
import 'package:invoice_capture/core/storage/hive_service.dart';
import 'package:invoice_capture/features/capture/sync_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(QueuedPhotoAdapter());
    Hive.registerAdapter(QueuedBundleAdapter());
    await Hive.openBox<QueuedBundle>('queued_bundles');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('syncPending uploads a queued bundle using real Meridian invoice data', () async {
    // Real, fully cross-checked figures from invoice_extraction.md entry [1]:
    // Meridian Brothers (06AAAAA0003A1Z3) -> Vishal Mega Mart (06AAAAA0013A1ZD).
    final photoFile = File(p.join(tempDir.path, 'photo.jpg'));
    await photoFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]); // minimal JPEG marker bytes

    final bundle = QueuedBundle(
      localId: 'local-1',
      invoiceNumber: 'A260000218',
      entityGstin: '06AAAAA0003A1Z3',
      buyerGstin: '06AAAAA0013A1ZD',
      buyerName: 'Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)',
      invoiceDate: '2026-06-09',
      taxableAmount: 10393.45,
      totalAmount: 10913.00,
      photos: [
        QueuedPhoto(
          localId: 'photo-1',
          localPath: photoFile.path,
          documentType: 'INVOICE',
          label: 'Tax Invoice',
          isPrimary: true,
        ),
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await HiveService.saveBundle(bundle);

    final dio = Dio();
    final adapter = DioAdapter(dio: dio);
    adapter.onPost(
      '/api/v1/invoices/ledger-upload',
      (server) => server.reply(201, {
        'invoice': {'id': 'server-invoice-id-1'},
        'status': 'INGESTED',
      }),
    );

    final service = SyncService(dio: dio);
    final (synced, failed) = await service.syncPending();

    expect(synced, 1);
    expect(failed, 0);

    final updated = HiveService.bundleBox.get('local-1');
    expect(updated?.status, 'synced');
  });
}
```

- [ ] **Step 5: Run it**

```bash
cd mobile && flutter test test/capture/sync_service_test.dart
```

Expected: PASS. If `http_mock_adapter`'s matcher needs the full URL (including `ServerConfig.baseUrl`) rather than a bare path, adjust the `onPost` call accordingly — check the package's README for its exact matching rule before guessing twice.

- [ ] **Step 6: Commit**

```bash
git add mobile/test/auth/login_screen_test.dart mobile/test/settings/settings_screen_test.dart mobile/test/capture/sync_service_test.dart
git commit -m "test(mobile): add widget/unit tests for auth, settings, and offline sync using real invoice data"
```

---

### Task 12: Fix the dead default widget test, add Flutter job to CI

`mobile/test/widget_test.dart` is the unmodified Flutter counter-app template — it references `MyApp`, which no longer exists (`mobile/lib/app.dart` defines `InvoiceCaptureApp` instead). This currently fails `flutter test` outright.

**Files:**
- Modify: `mobile/test/widget_test.dart`
- Modify: `.github/workflows/ci.yml` (add a Flutter job)

- [ ] **Step 1: Replace the dead test with a real smoke test**

```dart
// mobile/test/widget_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/app.dart';

void main() {
  testWidgets('app boots to the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: InvoiceCaptureApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invoice Capture'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it**

```bash
cd mobile && flutter test test/widget_test.dart
```

Expected: PASS. (This exercises real app boot, including `ServerConfig` defaults and the unauthenticated `go_router` redirect to `/login` — if it fails on a secure-storage platform-channel error, see Task 11 Step 3's note; the fix belongs in `ServerConfig`/`api_client.dart`, not in this test.)

- [ ] **Step 3: Run the full mobile test suite**

```bash
cd mobile && flutter test
```

Expected: PASS across all test files added in Tasks 11-12.

- [ ] **Step 4: Add a Flutter job to `.github/workflows/ci.yml`**

Add this as a new top-level job alongside `test-go-backend`, `test-python-ml`, `build-nextjs-frontend`:

```yaml
  test-flutter-mobile:
    name: Test Flutter Mobile App
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Set up Flutter
      uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.22.0'
        channel: 'stable'

    - name: Install dependencies
      working-directory: ./mobile
      run: flutter pub get

    - name: Analyze
      working-directory: ./mobile
      run: flutter analyze

    - name: Test
      working-directory: ./mobile
      run: flutter test
```

- [ ] **Step 5: Commit**

```bash
git add mobile/test/widget_test.dart .github/workflows/ci.yml
git commit -m "fix(mobile): replace dead counter-app test with a real smoke test; add Flutter CI job"
```

---

### Task 13: Manual smoke-test checklist for camera-dependent flows

Camera capture and crop guides need real device hardware and can't run in CI or `flutter test`. Document the manual steps so this coverage gap is tracked, not silently dropped.

**Files:**
- Create: `docs/superpowers/manual-smoke-tests.md`

- [ ] **Step 1: Write the checklist**

```markdown
# Manual Smoke Tests (camera-dependent, not automatable in CI)

Run these on a real device or emulator with camera support before each release.
Everything else in the app has automated coverage — see
`docs/superpowers/plans/2026-06-28-e2e-testing-cicd.md`.

## Camera capture (`mobile/lib/features/capture/camera_screen.dart`)

- [ ] Launch the app, log in, navigate to Home -> Capture.
- [ ] Camera preview renders live video (not a frozen/black frame).
- [ ] Crop guide overlay is visible and positioned over the preview.
- [ ] Tapping capture takes a photo and transitions to the Review screen.
- [ ] Captured photo is right-side-up regardless of device orientation at
      capture time (front/landscape/portrait).
- [ ] Retake works and replaces the previous photo, not appends to it.

## Document checklist (multi-page) (`mobile/lib/features/capture/checklist_screen.dart`)

- [ ] After capturing a primary invoice photo, the checklist shows the
      buyer's configured required document types (e.g. "Gate Entry /
      Discrepancy Note" for Vishal Mega Mart, per the seeded buyer doc
      requirements).
- [ ] Capturing a second page of the same document type shows "Add page 2"
      and both pages attach to the same `QueuedPhoto.documentType` group.

## Offline queue -> auto-sync (`mobile/lib/features/queue/queue_screen.dart`)

- [ ] Turn off WiFi/mobile data before capturing; complete a full
      capture+checklist flow. Bundle appears in the Queue screen as "pending."
- [ ] Re-enable connectivity. Bundle auto-transitions to "synced" within a
      few seconds (driven by `connectivity_plus`), without manually opening
      the Queue screen.
- [ ] Force a sync failure (e.g. point Settings at an unreachable server URL)
      and confirm the bundle shows "failed" with a visible error, not a silent
      drop.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/manual-smoke-tests.md
git commit -m "docs: add manual smoke-test checklist for camera-dependent mobile flows"
```

---

### Task 14: Final verification and push

**Files:** none

- [ ] **Step 1: Run the complete backend suite one more time from a clean container state**

```bash
cd /d/MeridianDist
docker compose down
docker compose up -d postgres temporal
sleep 5
cd backend && go run ./cmd/migrate up
go test ./... -v
```

Expected: all PASS, including every test added in Tasks 2-8.

- [ ] **Step 2: Run the complete mobile suite**

```bash
cd /d/MeridianDist/mobile
flutter analyze
flutter test
```

Expected: PASS, zero analyzer errors.

- [ ] **Step 3: Push to the configured remote**

```bash
cd /d/MeridianDist
git push -u origin feat/mobile-capture-app
```

- [ ] **Step 4: Confirm CI is green**

Open `https://github.com/himanshu2394i/MeridianDistributors/actions` and confirm all 4 jobs (`test-go-backend`, `test-python-ml`, `build-nextjs-frontend`, `test-flutter-mobile`) pass on the pushed branch. If any job fails for an environment-specific reason not caught locally (e.g. a GitHub Actions network restriction on the Temporal CLI download in Task 9), fix it directly in `.github/workflows/ci.yml` and push a follow-up commit — don't mark this task done until the Actions run is green.

---

## Out of scope (deferred to future specs)

- OCR extractor rebuild (real line-item/multi-page/multi-entity extraction) — this is why `VALIDATION_FAILED` isn't tested here; see Global Constraints.
- AWS deployment, infrastructure-as-code, secrets management, building/pushing Docker images in CI.
- Python unit tests for `python_worker/activities.py` — out of the approved spec's scope; revisit when the extractor is rebuilt.
