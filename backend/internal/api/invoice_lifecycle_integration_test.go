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
		Invoice struct {
			ID string `json:"id"`
		} `json:"invoice"`
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
	// handleGetAuditTrail (api.go) writes the []*db.AuditEvent slice straight
	// to the response body -- it's a bare JSON array, not wrapped in an
	// {"events": [...]} envelope.
	auditResp := ts.get(t, "/api/v1/invoices/"+invoiceID+"/audit-trail", ts.WorkerToken)
	type auditEvent struct {
		EventType string `json:"event_type"`
		ActorID   string `json:"actor_id"`
	}
	events := decodeJSON[[]auditEvent](t, auditResp)
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

func TestLedgerUpload_StoresTotalAsGrossAndTaxDelta(t *testing.T) {
	ts := startTestServer(t)

	resp := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		map[string]string{
			"invoice_number": "A260000218-AMOUNT-TEST",
			"entity_gstin":   "06AAAAA0003A1Z3",
			"buyer_gstin":    "06AAAAA0013A1ZD",
			"buyer_name":     "Airplaza Retail Holdings Pvt Ltd (Vishal Mega Mart)",
			"invoice_date":   "2026-06-09",
			"taxable_amount": "10393.45",
			"total_amount":   "10913.00",
		},
		"file", "amount-test.jpg", minimalJPEG(t))
	type uploadResp struct {
		Invoice struct {
			ID string `json:"id"`
		} `json:"invoice"`
	}
	invoiceID := decodeJSON[uploadResp](t, resp).Invoice.ID

	detailResp := ts.get(t, "/api/v1/invoices/"+invoiceID, ts.WorkerToken)
	type invoiceResp struct {
		Invoice struct {
			GrossAmount float64 `json:"gross_amount"`
			TaxAmount   float64 `json:"tax_amount"`
		} `json:"invoice"`
	}
	inv := decodeJSON[invoiceResp](t, detailResp).Invoice
	if inv.GrossAmount != 10913.00 {
		t.Fatalf("gross_amount should store the submitted total amount, got %.2f", inv.GrossAmount)
	}
	if inv.TaxAmount != 519.55 {
		t.Fatalf("tax_amount should store total-taxable, got %.2f", inv.TaxAmount)
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
		Invoice struct {
			ID string `json:"id"`
		} `json:"invoice"`
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
