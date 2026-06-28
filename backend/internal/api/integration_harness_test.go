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
