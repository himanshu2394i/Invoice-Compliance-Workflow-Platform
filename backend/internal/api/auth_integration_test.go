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

func TestChangePassword_RejectsWrongCurrentPassword(t *testing.T) {
	ts := startTestServer(t)
	resp := ts.post(t, "/api/v1/auth/change-password", ts.AdminToken, map[string]string{
		"current_password": "wrong-password",
		"new_password":     "BetterPass2026",
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 for wrong current password, got %d", resp.StatusCode)
	}
}

func TestChangePassword_UpdatesLoginCredential(t *testing.T) {
	ts := startTestServer(t)
	adminEmail := "admin+" + ts.OrgID[:8] + "@demo.local"
	newPassword := "BetterPass2026"

	resp := ts.post(t, "/api/v1/auth/change-password", ts.AdminToken, map[string]string{
		"current_password": "ChangeMe123!",
		"new_password":     newPassword,
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected password change to succeed, got %d", resp.StatusCode)
	}

	oldLogin := ts.post(t, "/api/v1/auth/login", "", map[string]string{
		"email":    adminEmail,
		"password": "ChangeMe123!",
	})
	defer oldLogin.Body.Close()
	if oldLogin.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected old password to stop working, got %d", oldLogin.StatusCode)
	}

	_ = ts.loginAs(t, adminEmail, newPassword)
}

func TestAdminResetPassword_UpdatesStaffLoginCredential(t *testing.T) {
	ts := startTestServer(t)
	workerEmail := "worker+" + ts.OrgID[:8] + "@demo.local"
	newPassword := "ResetPass2026"

	resp := ts.post(t, "/api/v1/auth/users/reset-password", ts.AdminToken, map[string]string{
		"email":        workerEmail,
		"new_password": newPassword,
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected admin reset to succeed, got %d", resp.StatusCode)
	}

	oldLogin := ts.post(t, "/api/v1/auth/login", "", map[string]string{
		"email":    workerEmail,
		"password": "ChangeMe123!",
	})
	defer oldLogin.Body.Close()
	if oldLogin.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected old worker password to stop working, got %d", oldLogin.StatusCode)
	}

	_ = ts.loginAs(t, workerEmail, newPassword)
}

func TestAdminResetPassword_WorkerCannotResetPassword(t *testing.T) {
	ts := startTestServer(t)
	managerEmail := "manager+" + ts.OrgID[:8] + "@demo.local"

	resp := ts.post(t, "/api/v1/auth/users/reset-password", ts.WorkerToken, map[string]string{
		"email":        managerEmail,
		"new_password": "ResetPass2026",
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("expected worker reset attempt to be forbidden, got %d", resp.StatusCode)
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
