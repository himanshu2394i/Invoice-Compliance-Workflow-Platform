// gate_entry_dispute_integration_test.go
package api

import (
	"fmt"
	"net/http"
	"sync/atomic"
	"testing"
)

// testInvoiceCounter guarantees each createTestInvoice call gets a distinct
// invoice_number. Needed since uq_invoice_ledger_dedup (organization_id,
// entity_id, invoice_number, invoice_date) now makes a repeated identical
// upload idempotent (see handleUploadLedgerInvoice) -- callers that
// deliberately create several distinct invoices in one test (e.g.
// TestInvoiceList_Pagination) would otherwise all collapse onto the same
// underlying invoice.
var testInvoiceCounter atomic.Int64

func createTestInvoice(t *testing.T, ts *testServer) string {
	t.Helper()
	n := testInvoiceCounter.Add(1)
	resp := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		map[string]string{
			"invoice_number": fmt.Sprintf("A260000218-GATE-TEST-%d", n),
			"entity_gstin":   "06AAAAA0003A1Z3",
			"buyer_gstin":    "06AAAAA0013A1ZD",
			"invoice_date":   "2026-06-09",
			"taxable_amount": "10393.45",
			"total_amount":   "10913.00",
		},
		"file", "gate-test.jpg", minimalJPEG(t))
	type uploadResp struct {
		Invoice struct {
			ID string `json:"id"`
		} `json:"invoice"`
	}
	return decodeJSON[uploadResp](t, resp).Invoice.ID
}

// mustPrimaryDocumentID fetches the invoice's primary document (the one
// created by the ledger-upload itself) via GET /invoices/{id}, since
// gate_entry_metadata.document_id is a real foreign key into documents(id)
// -- a synthetic string like "manual-test-doc" fails the FK constraint.
func mustPrimaryDocumentID(t *testing.T, ts *testServer, invoiceID string) string {
	t.Helper()
	resp := ts.get(t, "/api/v1/invoices/"+invoiceID, ts.WorkerToken)
	type document struct {
		ID string `json:"id"`
	}
	type invoiceDetailResp struct {
		Documents []document `json:"documents"`
	}
	docs := decodeJSON[invoiceDetailResp](t, resp).Documents
	if len(docs) == 0 {
		t.Fatal("expected at least one document on the invoice")
	}
	return docs[0].ID
}

func TestGateEntry_ShortReceipt_AutoRaisesDispute(t *testing.T) {
	ts := startTestServer(t)
	invoiceID := createTestInvoice(t, ts)
	documentID := mustPrimaryDocumentID(t, ts, invoiceID)

	acceptedQty := 80.0
	invoiceQty := 92.0 // matches entry [1]'s "qty 2 lines / 92 units total"
	discrepancy := 1200.0

	resp := ts.post(t, "/api/v1/invoices/"+invoiceID+"/gate-entry", ts.WorkerToken, map[string]interface{}{
		"document_id":        documentID,
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

// TestGateEntry_CrossTenantInvoice_Returns404 proves a worker can't attach
// gate entry metadata (or auto-raise a dispute) against another tenant's
// invoice ID.
func TestGateEntry_CrossTenantInvoice_Returns404(t *testing.T) {
	tsA := startTestServer(t)
	tsB := startTestServer(t) // a second, independently-seeded tenant
	otherTenantsInvoiceID := createTestInvoice(t, tsB)
	otherTenantsDocumentID := mustPrimaryDocumentID(t, tsB, otherTenantsInvoiceID)

	resp := tsA.post(t, "/api/v1/invoices/"+otherTenantsInvoiceID+"/gate-entry", tsA.WorkerToken, map[string]interface{}{
		"document_id":      otherTenantsDocumentID,
		"is_short_receipt": true,
		"notes":            "should be rejected -- this invoice belongs to tenant B",
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("expected 404 for a gate entry against another tenant's invoice, got %d", resp.StatusCode)
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

// TestDispute_InvalidDisputeType_Returns400 proves an unrecognized
// dispute_type is rejected at the API layer with a clean 400, rather than
// reaching the database and surfacing as an opaque 500 from the
// invoice_disputes.dispute_type CHECK constraint.
func TestDispute_InvalidDisputeType_Returns400(t *testing.T) {
	ts := startTestServer(t)
	invoiceID := createTestInvoice(t, ts)

	resp := ts.post(t, "/api/v1/disputes", ts.WorkerToken, map[string]interface{}{
		"invoice_id":   invoiceID,
		"dispute_type": "NOT_A_REAL_TYPE",
		"description":  "should be rejected before it reaches the database",
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for an invalid dispute_type, got %d", resp.StatusCode)
	}
}

// TestDispute_CrossTenantInvoice_Returns404 proves a worker can't create a
// dispute against another tenant's invoice ID, even though disputes and
// invoices live in separate RLS-scoped tables with no FK between them.
func TestDispute_CrossTenantInvoice_Returns404(t *testing.T) {
	tsA := startTestServer(t)
	tsB := startTestServer(t) // a second, independently-seeded tenant
	otherTenantsInvoiceID := createTestInvoice(t, tsB)

	resp := tsA.post(t, "/api/v1/disputes", tsA.WorkerToken, map[string]interface{}{
		"invoice_id":   otherTenantsInvoiceID,
		"dispute_type": "ARITHMETIC_ERROR",
		"description":  "should be rejected -- this invoice belongs to tenant B",
	})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("expected 404 for a dispute against another tenant's invoice, got %d", resp.StatusCode)
	}
}
