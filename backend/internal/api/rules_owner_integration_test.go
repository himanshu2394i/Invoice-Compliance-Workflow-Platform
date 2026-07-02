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

// TestRules_CreateListDelete exercises ADMIN-only rule CRUD. Note: the real
// db.TenantRule / handleCreateRule schema is {field, operator, value, action}
// (see backend/internal/db/db.go:950 and backend/internal/api/api.go:854-886)
// -- not the {name, rule_type} shape from the original plan draft. field must
// be one of GrossAmount/NetAmount/TaxAmount, operator one of >,<,==,>=,<=,
// and action one of REQUIRE_MANAGER_APPROVAL/REQUIRE_FINANCE_APPROVAL.
func TestRules_CreateListDelete(t *testing.T) {
	ts := startTestServer(t)

	createResp := ts.post(t, "/api/v1/rules", ts.AdminToken, map[string]interface{}{
		"field":    "GrossAmount",
		"operator": ">",
		"value":    50000,
		"action":   "REQUIRE_FINANCE_APPROVAL",
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

func TestOwnerDashboard_ReturnsStatsForAdminManagerFinanceAndReviewer(t *testing.T) {
	ts := startTestServer(t)

	for _, token := range []string{ts.AdminToken, ts.ManagerToken, ts.FinanceToken, ts.ReviewerToken} {
		resp := ts.get(t, "/api/v1/owner/dashboard", token)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("owner dashboard: expected 200, got %d", resp.StatusCode)
		}
	}

	// WORKER is not permitted on this route.
	for _, token := range []string{ts.WorkerToken} {
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
		Total    int                      `json:"total"`
	}
	page := decodeJSON[invoiceListResp](t, resp)
	if len(page.Invoices) > 2 {
		t.Fatalf("expected at most 2 invoices with limit=2, got %d", len(page.Invoices))
	}
	if page.Total < 3 {
		t.Fatalf("expected total >= 3 after creating 3 invoices, got %d", page.Total)
	}
}

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

	// invoice_exceptions.exception_type is constrained to 'missing_document' or
	// 'document_mismatch' (backend/db/migrations/000003_buyer_ledger.up.sql:44)
	// -- the plan draft's "DUPLICATE_INVOICE_NUMBER" violates that check constraint.
	if err := repo.RaiseExceptionIfNotOpen(context.Background(), ts.OrgID, invoiceID,
		"document_mismatch", []byte(`{"matched_invoice_number":"A260000218"}`)); err != nil {
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

func TestReviewer_CanResolveExceptionsButCannotApproveOrConfigure(t *testing.T) {
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
		"document_mismatch", []byte(`{"reason":"reviewer test"}`)); err != nil {
		t.Fatalf("seed exception: %v", err)
	}

	listResp := ts.get(t, "/api/v1/exceptions", ts.ReviewerToken)
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
		t.Fatal("seeded exception did not appear for reviewer")
	}

	resolveResp := ts.post(t, "/api/v1/exceptions/"+exceptionID+"/resolve", ts.ReviewerToken,
		map[string]string{"status": "resolved"})
	resolveResp.Body.Close()
	if resolveResp.StatusCode != http.StatusOK {
		t.Fatalf("reviewer resolve exception: expected 200, got %d", resolveResp.StatusCode)
	}

	approveResp := ts.post(t, "/api/v1/invoices/"+invoiceID+"/approve", ts.ReviewerToken,
		map[string]interface{}{"approved": true, "comments": "reviewed"})
	approveResp.Body.Close()
	if approveResp.StatusCode != http.StatusForbidden {
		t.Fatalf("reviewer approve: expected 403, got %d", approveResp.StatusCode)
	}

	rulesResp := ts.get(t, "/api/v1/rules", ts.ReviewerToken)
	rulesResp.Body.Close()
	if rulesResp.StatusCode != http.StatusForbidden {
		t.Fatalf("reviewer rules: expected 403, got %d", rulesResp.StatusCode)
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
