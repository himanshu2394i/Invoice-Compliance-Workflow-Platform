package api

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"testing"
)

func TestDuplicateInvoiceCheck(t *testing.T) {
	ts := startTestServer(t)
	n := testInvoiceCounter.Add(1)
	invoiceNumber := fmt.Sprintf("A260000218-DUP-TEST-%d", n)

	uploadResp := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		map[string]string{
			"invoice_number": invoiceNumber,
			"entity_gstin":   "06AAAAA0003A1Z3",
			"buyer_gstin":    "06AAAAA0013A1ZD",
			"invoice_date":   "2026-06-09",
			"taxable_amount": "10393.45",
			"total_amount":   "10913.00",
		},
		"file", "duplicate-test.jpg", minimalJPEG(t))
	if uploadResp.StatusCode != http.StatusCreated {
		t.Fatalf("upload invoice: expected 201, got %d", uploadResp.StatusCode)
	}
	type uploadResponse struct {
		Invoice struct {
			ID string `json:"id"`
		} `json:"invoice"`
	}
	uploaded := decodeJSON[uploadResponse](t, uploadResp)
	if uploaded.Invoice.ID == "" {
		t.Fatal("upload did not return invoice id")
	}

	params := url.Values{}
	params.Set("invoice_number", invoiceNumber)
	params.Set("seller_gstin", "06AAAAA0003A1Z3")
	params.Set("buyer_gstin", "06AAAAA0013A1ZD")
	resp := ts.get(t, "/api/v1/mobile/invoices/duplicate-check?"+params.Encode(), ts.WorkerToken)
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("duplicate check: expected 200, got %d: %s", resp.StatusCode, body)
	}
	type duplicateResponse struct {
		Duplicate     bool    `json:"duplicate"`
		InvoiceID     string  `json:"invoice_id"`
		InvoiceNumber string  `json:"invoice_number"`
		BuyerName     string  `json:"buyer_name"`
		InvoiceDate   string  `json:"invoice_date"`
		TotalAmount   float64 `json:"total_amount"`
		Status        string  `json:"status"`
	}
	dup := decodeJSON[duplicateResponse](t, resp)
	if !dup.Duplicate {
		t.Fatal("expected duplicate=true for the uploaded invoice")
	}
	if dup.InvoiceID != uploaded.Invoice.ID {
		t.Fatalf("expected invoice_id %s, got %s", uploaded.Invoice.ID, dup.InvoiceID)
	}
	if dup.InvoiceNumber != invoiceNumber {
		t.Fatalf("expected invoice_number %s, got %s", invoiceNumber, dup.InvoiceNumber)
	}
	if dup.BuyerName == "" {
		t.Fatal("expected duplicate response to include buyer_name")
	}
	if dup.InvoiceDate != "2026-06-09" {
		t.Fatalf("expected invoice_date 2026-06-09, got %q", dup.InvoiceDate)
	}
	if dup.TotalAmount != 10913.00 {
		t.Fatalf("expected total_amount 10913.00, got %v", dup.TotalAmount)
	}
	if dup.Status == "" {
		t.Fatal("expected duplicate response to include status")
	}

	params.Set("invoice_number", "NOT-A-REAL-INVOICE")
	resp = ts.get(t, "/api/v1/mobile/invoices/duplicate-check?"+params.Encode(), ts.WorkerToken)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("unknown duplicate check: expected 200, got %d", resp.StatusCode)
	}
	unknown := decodeJSON[duplicateResponse](t, resp)
	if unknown.Duplicate {
		t.Fatal("expected duplicate=false for an unknown invoice")
	}

	resp = ts.get(t, "/api/v1/mobile/invoices/duplicate-check?seller_gstin=06AAAAA0003A1Z3", ts.WorkerToken)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("missing invoice_number: expected 400, got %d", resp.StatusCode)
	}
}
