package api

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"testing"
	"time"
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

type ownerInvoiceListResponse struct {
	Invoices []struct {
		ID            string  `json:"id"`
		InvoiceNumber string  `json:"invoice_number"`
		CurrentState  string  `json:"current_state"`
		BuyerName     *string `json:"buyer_name"`
		OpenDisputes  int     `json:"open_disputes"`
	} `json:"invoices"`
}

func uploadFilterTestInvoice(t *testing.T, ts *testServer, invoiceNumber, buyerGstin, buyerName, invoiceDate string) string {
	t.Helper()
	resp := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		map[string]string{
			"invoice_number": invoiceNumber,
			"entity_gstin":   "06AAAAA0003A1Z3",
			"buyer_gstin":    buyerGstin,
			"buyer_name":     buyerName,
			"invoice_date":   invoiceDate,
			"taxable_amount": "1000.00",
			"total_amount":   "1050.00",
		},
		"file", "filter-test.jpg", minimalJPEG(t))
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("upload %s: expected 201, got %d", invoiceNumber, resp.StatusCode)
	}
	type uploadResponse struct {
		Invoice struct {
			ID string `json:"id"`
		} `json:"invoice"`
	}
	return decodeJSON[uploadResponse](t, resp).Invoice.ID
}

func TestOwnerInvoiceFilters(t *testing.T) {
	ts := startTestServer(t)
	n := testInvoiceCounter.Add(1)
	numberA := fmt.Sprintf("FILT-A-%d", n)
	numberB := fmt.Sprintf("FILT-B-%d", n)

	invoiceA := uploadFilterTestInvoice(t, ts, numberA, "06AAAAA0013A1ZD", "Vishal Mega Mart", "2026-06-01")
	invoiceB := uploadFilterTestInvoice(t, ts, numberB, "06AAAAA0011A1ZB", "Home Shopee India", "2026-06-20")

	// Give invoiceB an open dispute so has_open_issues can separate them.
	dispResp := ts.post(t, "/api/v1/disputes", ts.WorkerToken, map[string]interface{}{
		"invoice_id":   invoiceB,
		"dispute_type": "OTHER",
		"description":  "filter test dispute",
	})
	dispResp.Body.Close()
	if dispResp.StatusCode != http.StatusCreated && dispResp.StatusCode != http.StatusOK {
		t.Fatalf("create dispute: expected 200/201, got %d", dispResp.StatusCode)
	}

	fetch := func(query string) ownerInvoiceListResponse {
		t.Helper()
		resp := ts.get(t, "/api/v1/owner/invoices?"+query, ts.ManagerToken)
		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			t.Fatalf("owner invoices %q: expected 200, got %d: %s", query, resp.StatusCode, body)
		}
		return decodeJSON[ownerInvoiceListResponse](t, resp)
	}
	only := func(list ownerInvoiceListResponse, wantID, label string) {
		t.Helper()
		if len(list.Invoices) != 1 || list.Invoices[0].ID != wantID {
			t.Fatalf("%s: expected exactly [%s], got %+v", label, wantID, list.Invoices)
		}
	}

	// q matches invoice number substring.
	only(fetch("q="+url.QueryEscape(numberA)), invoiceA, "q=invoice number")
	// q matches buyer name, case-insensitively.
	only(fetch("q=home+shopee"), invoiceB, "q=buyer name")
	// q matches buyer GSTIN.
	only(fetch("q=06AAAAA0013A1ZD"), invoiceA, "q=buyer gstin")
	// Date range separates the two.
	only(fetch("from=2026-06-15&to=2026-06-30"), invoiceB, "date range")
	// has_open_issues=true returns only the disputed invoice.
	only(fetch("has_open_issues=true"), invoiceB, "open issues")
	// status filters by current state; both were just INGESTED, so expect 2.
	byStatus := fetch("status=INGESTED")
	if len(byStatus.Invoices) != 2 {
		t.Fatalf("status=INGESTED: expected 2, got %d", len(byStatus.Invoices))
	}
	// buyer_id narrows to that buyer's invoices.
	type buyersResponse struct {
		Buyers []struct {
			ID    string `json:"id"`
			GSTIN string `json:"gstin"`
		} `json:"buyers"`
	}
	buyers := decodeJSON[buyersResponse](t, ts.get(t, "/api/v1/buyers", ts.ManagerToken))
	var buyerAID string
	for _, b := range buyers.Buyers {
		if b.GSTIN == "06AAAAA0013A1ZD" {
			buyerAID = b.ID
		}
	}
	if buyerAID == "" {
		t.Fatal("buyer A not found in buyers list")
	}
	only(fetch("buyer_id="+buyerAID), invoiceA, "buyer_id")
}

func TestAlertFilters(t *testing.T) {
	ts := startTestServer(t)
	n := testInvoiceCounter.Add(1)

	// A fresh dispute (age 0, priority warning).
	disputedInvoice := uploadFilterTestInvoice(t, ts,
		fmt.Sprintf("ALRT-DISP-%d", n), "06AAAAA0013A1ZD", "Vishal Mega Mart", "2026-06-01")
	dispResp := ts.post(t, "/api/v1/disputes", ts.WorkerToken, map[string]interface{}{
		"invoice_id":   disputedInvoice,
		"dispute_type": "OTHER",
		"description":  "alert filter test dispute",
	})
	dispResp.Body.Close()

	// A credit invoice due 40 days ago (age 40, priority critical).
	oldDate := time.Now().UTC().AddDate(0, 0, -40).Format("2006-01-02")
	overdueResp := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		map[string]string{
			"invoice_number":     fmt.Sprintf("ALRT-OVD-%d", n),
			"entity_gstin":       "06AAAAA0003A1Z3",
			"buyer_gstin":        "06AAAAA0011A1ZB",
			"invoice_date":       oldDate,
			"taxable_amount":     "1000.00",
			"total_amount":       "1050.00",
			"payment_type":       "CREDIT",
			"payment_terms_days": "0",
		},
		"file", "alert-overdue.jpg", minimalJPEG(t))
	if overdueResp.StatusCode != http.StatusCreated {
		t.Fatalf("upload overdue invoice: expected 201, got %d", overdueResp.StatusCode)
	}
	type uploadResponse struct {
		Invoice struct {
			ID string `json:"id"`
		} `json:"invoice"`
	}
	overdueInvoice := decodeJSON[uploadResponse](t, overdueResp).Invoice.ID

	type alertsBody struct {
		Alerts []struct {
			Type      string `json:"type"`
			InvoiceID string `json:"invoice_id"`
			AgeDays   int    `json:"age_days"`
			Priority  string `json:"priority"`
		} `json:"alerts"`
	}
	fetch := func(query string) alertsBody {
		t.Helper()
		resp := ts.get(t, "/api/v1/owner/alerts"+query, ts.ManagerToken)
		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			t.Fatalf("alerts %q: expected 200, got %d: %s", query, resp.StatusCode, body)
		}
		return decodeJSON[alertsBody](t, resp)
	}

	all := fetch("")
	var sawDispute, sawOverdue bool
	for _, a := range all.Alerts {
		switch {
		case a.Type == "dispute" && a.InvoiceID == disputedInvoice:
			sawDispute = true
			if a.AgeDays != 0 || a.Priority != "warning" {
				t.Fatalf("fresh dispute: expected age 0 priority warning, got %+v", a)
			}
		case a.Type == "overdue_invoice" && a.InvoiceID == overdueInvoice:
			sawOverdue = true
			if a.AgeDays < 39 || a.Priority != "critical" {
				t.Fatalf("40-day overdue: expected age ~40 priority critical, got %+v", a)
			}
		}
	}
	if !sawDispute || !sawOverdue {
		t.Fatalf("expected both alerts in unfiltered feed, got %+v", all.Alerts)
	}

	byType := fetch("?type=dispute")
	for _, a := range byType.Alerts {
		if a.Type != "dispute" {
			t.Fatalf("type=dispute returned a %q alert", a.Type)
		}
	}
	aged := fetch("?min_age_days=10")
	for _, a := range aged.Alerts {
		if a.AgeDays < 10 {
			t.Fatalf("min_age_days=10 returned an alert aged %d", a.AgeDays)
		}
	}
	var agedHasOverdue bool
	for _, a := range aged.Alerts {
		if a.InvoiceID == overdueInvoice {
			agedHasOverdue = true
		}
	}
	if !agedHasOverdue {
		t.Fatal("min_age_days=10 should still include the 40-day overdue invoice")
	}
}

func TestBuyerRequirementDelete(t *testing.T) {
	ts := startTestServer(t)

	buyerResp := ts.post(t, "/api/v1/buyers", ts.AdminToken, map[string]interface{}{
		"name":  "Requirement Delete Test Buyer",
		"gstin": "06AAAAA0016A1ZG",
	})
	type buyer struct {
		ID string `json:"id"`
	}
	if buyerResp.StatusCode != http.StatusCreated && buyerResp.StatusCode != http.StatusOK {
		t.Fatalf("create buyer: expected 200/201, got %d", buyerResp.StatusCode)
	}
	b := decodeJSON[buyer](t, buyerResp)

	upsert := ts.post(t, "/api/v1/mobile/buyers/"+b.ID+"/requirements", ts.AdminToken,
		map[string]interface{}{
			"document_type":      "GATE_ENTRY_NOTE",
			"label":              "Gate Entry Note",
			"is_buyer_generated": true,
		})
	upsert.Body.Close()
	if upsert.StatusCode != http.StatusOK && upsert.StatusCode != http.StatusCreated {
		t.Fatalf("upsert requirement: expected 200/201, got %d", upsert.StatusCode)
	}

	// Workers cannot delete master data.
	denied := ts.doRequest(t, http.MethodDelete,
		"/api/v1/mobile/buyers/"+b.ID+"/requirements/GATE_ENTRY_NOTE", ts.WorkerToken, nil)
	denied.Body.Close()
	if denied.StatusCode != http.StatusForbidden {
		t.Fatalf("worker delete: expected 403, got %d", denied.StatusCode)
	}

	del := ts.doRequest(t, http.MethodDelete,
		"/api/v1/mobile/buyers/"+b.ID+"/requirements/gate_entry_note", ts.AdminToken, nil)
	if del.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(del.Body)
		t.Fatalf("delete requirement: expected 200, got %d: %s", del.StatusCode, body)
	}
	del.Body.Close()

	// Requirement is gone from the buyer's list.
	type requirementsResponse struct {
		Requirements []struct {
			DocumentType string `json:"document_type"`
		} `json:"requirements"`
	}
	list := decodeJSON[requirementsResponse](t,
		ts.get(t, "/api/v1/mobile/buyers/"+b.ID+"/requirements", ts.AdminToken))
	for _, req := range list.Requirements {
		if req.DocumentType == "GATE_ENTRY_NOTE" {
			t.Fatal("requirement still present after delete")
		}
	}

	// Idempotent: deleting again still succeeds.
	again := ts.doRequest(t, http.MethodDelete,
		"/api/v1/mobile/buyers/"+b.ID+"/requirements/GATE_ENTRY_NOTE", ts.AdminToken, nil)
	again.Body.Close()
	if again.StatusCode != http.StatusOK {
		t.Fatalf("repeat delete: expected 200, got %d", again.StatusCode)
	}
}
