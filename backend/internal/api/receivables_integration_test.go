package api

import (
	"fmt"
	"net/http"
	"testing"
	"time"
)

// uploadCreditInvoice files a ledger invoice with the distributor-domain
// payment fields set, returning the new invoice's ID. Amounts mirror entry
// [1] of invoice_extraction.md (bill total 10913.00).
func uploadCreditInvoice(t *testing.T, ts *testServer, buyerGstin, paymentType, termsDays, invoiceDate string) string {
	t.Helper()
	n := testInvoiceCounter.Add(1)
	fields := map[string]string{
		"invoice_number": fmt.Sprintf("RCV-TEST-%d", n),
		"entity_gstin":   "06AAAAA0003A1Z3",
		"buyer_gstin":    buyerGstin,
		"buyer_name":     "Receivables Test Buyer " + buyerGstin,
		"invoice_date":   invoiceDate,
		"taxable_amount": "10393.45",
		"total_amount":   "10913.00",
	}
	if paymentType != "" {
		fields["payment_type"] = paymentType
	}
	if termsDays != "" {
		fields["payment_terms_days"] = termsDays
	}
	resp := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		fields, "file", "rcv-test.jpg", minimalJPEG(t))
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("ledger upload: expected 201, got %d", resp.StatusCode)
	}
	type uploadResp struct {
		Invoice struct {
			ID string `json:"id"`
		} `json:"invoice"`
	}
	return decodeJSON[uploadResp](t, resp).Invoice.ID
}

type receivablesSummaryResp struct {
	TotalOutstanding float64 `json:"total_outstanding"`
	TotalOverdue     float64 `json:"total_overdue"`
	Buyers           []struct {
		BuyerID       string  `json:"buyer_id"`
		BuyerName     string  `json:"buyer_name"`
		Outstanding   float64 `json:"outstanding"`
		Overdue       float64 `json:"overdue"`
		BucketCurrent float64 `json:"bucket_current"`
		OpenInvoices  int     `json:"open_invoices"`
	} `json:"buyers"`
}

func TestReceivables_CreditInvoiceLifecycle(t *testing.T) {
	ts := startTestServer(t)
	today := time.Now().Format("2006-01-02")

	// A CREDIT invoice with 30-day terms is outstanding but not overdue.
	invoiceID := uploadCreditInvoice(t, ts, "06AAAAA0013A1ZD", "CREDIT", "30", today)

	// A CASH invoice and a legacy invoice (no payment_type) must never
	// appear in receivables.
	uploadCreditInvoice(t, ts, "06AAAAA0013A1ZD", "CASH", "", today)
	uploadCreditInvoice(t, ts, "06AAAAA0013A1ZD", "", "", today)

	resp := ts.get(t, "/api/v1/owner/receivables", ts.ManagerToken)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("receivables: expected 200, got %d", resp.StatusCode)
	}
	summary := decodeJSON[receivablesSummaryResp](t, resp)
	if len(summary.Buyers) != 1 {
		t.Fatalf("expected exactly 1 buyer with receivables, got %d", len(summary.Buyers))
	}
	b := summary.Buyers[0]
	if b.OpenInvoices != 1 {
		t.Fatalf("expected 1 open credit invoice (CASH/legacy excluded), got %d", b.OpenInvoices)
	}
	if b.Outstanding < 10912.9 || b.Outstanding > 10913.1 {
		t.Fatalf("expected outstanding ~10913.00, got %f", b.Outstanding)
	}
	if b.Overdue != 0 {
		t.Fatalf("expected no overdue amount for 30-day terms, got %f", b.Overdue)
	}

	// Buyer-level drill-down shows the invoice with a full balance.
	buyerResp := ts.get(t, "/api/v1/owner/receivables/"+b.BuyerID, ts.FinanceToken)
	type buyerReceivablesResp struct {
		Invoices []struct {
			InvoiceID   string  `json:"invoice_id"`
			Balance     float64 `json:"balance"`
			DaysOverdue int     `json:"days_overdue"`
		} `json:"invoices"`
	}
	br := decodeJSON[buyerReceivablesResp](t, buyerResp)
	if len(br.Invoices) != 1 || br.Invoices[0].InvoiceID != invoiceID {
		t.Fatalf("expected the credit invoice in the buyer drill-down, got %+v", br.Invoices)
	}
	if br.Invoices[0].DaysOverdue != 0 {
		t.Fatalf("expected 0 days overdue, got %d", br.Invoices[0].DaysOverdue)
	}

	// Workers cannot record payments.
	forbidden := ts.post(t, "/api/v1/invoices/"+invoiceID+"/payments", ts.WorkerToken,
		map[string]interface{}{"amount": 100.0, "mode": "CASH"})
	forbidden.Body.Close()
	if forbidden.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403 for worker payment, got %d", forbidden.StatusCode)
	}

	// Finance records a partial payment.
	payResp := ts.post(t, "/api/v1/invoices/"+invoiceID+"/payments", ts.FinanceToken,
		map[string]interface{}{"amount": 5000.0, "paid_on": today, "mode": "UPI", "reference": "UTR123"})
	if payResp.StatusCode != http.StatusCreated {
		t.Fatalf("record payment: expected 201, got %d", payResp.StatusCode)
	}
	payResp.Body.Close()

	// Balance drops by the paid amount.
	resp2 := ts.get(t, "/api/v1/owner/receivables", ts.ManagerToken)
	summary2 := decodeJSON[receivablesSummaryResp](t, resp2)
	if len(summary2.Buyers) != 1 {
		t.Fatalf("expected 1 buyer after partial payment, got %d", len(summary2.Buyers))
	}
	remaining := summary2.Buyers[0].Outstanding
	if remaining < 5912.9 || remaining > 5913.1 {
		t.Fatalf("expected outstanding ~5913.00 after 5000 payment, got %f", remaining)
	}

	// Overpaying the remaining balance is rejected.
	overpay := ts.post(t, "/api/v1/invoices/"+invoiceID+"/payments", ts.FinanceToken,
		map[string]interface{}{"amount": 6000.0, "mode": "CASH"})
	overpay.Body.Close()
	if overpay.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for over-balance payment, got %d", overpay.StatusCode)
	}

	// Paying off exactly the remaining balance clears the receivable.
	settle := ts.post(t, "/api/v1/invoices/"+invoiceID+"/payments", ts.FinanceToken,
		map[string]interface{}{"amount": remaining, "mode": "NEFT"})
	settle.Body.Close()
	if settle.StatusCode != http.StatusCreated {
		t.Fatalf("expected 201 settling payment, got %d", settle.StatusCode)
	}
	resp3 := ts.get(t, "/api/v1/owner/receivables", ts.ManagerToken)
	summary3 := decodeJSON[receivablesSummaryResp](t, resp3)
	if len(summary3.Buyers) != 0 {
		t.Fatalf("expected no receivables after full settlement, got %+v", summary3.Buyers)
	}

	// Payment history lists both payments.
	histResp := ts.get(t, "/api/v1/invoices/"+invoiceID+"/payments", ts.ReviewerToken)
	type paymentsResp struct {
		Payments []struct {
			Amount float64 `json:"amount"`
			Mode   string  `json:"mode"`
		} `json:"payments"`
	}
	hist := decodeJSON[paymentsResp](t, histResp)
	if len(hist.Payments) != 2 {
		t.Fatalf("expected 2 payments in history, got %d", len(hist.Payments))
	}
}

func TestReceivables_OverdueInvoiceRaisesAlert(t *testing.T) {
	ts := startTestServer(t)
	// Terms 0 with yesterday's invoice date -> due yesterday -> overdue today.
	yesterday := time.Now().AddDate(0, 0, -1).Format("2006-01-02")
	invoiceID := uploadCreditInvoice(t, ts, "06AAAAA0011A1ZB", "CREDIT", "0", yesterday)

	resp := ts.get(t, "/api/v1/owner/receivables", ts.ManagerToken)
	summary := decodeJSON[receivablesSummaryResp](t, resp)
	if len(summary.Buyers) != 1 || summary.Buyers[0].Overdue < 10912.9 {
		t.Fatalf("expected the full amount overdue, got %+v", summary.Buyers)
	}

	alertsResp := ts.get(t, "/api/v1/owner/alerts", ts.ManagerToken)
	type alertsBody struct {
		Alerts []struct {
			Type      string `json:"type"`
			InvoiceID string `json:"invoice_id"`
		} `json:"alerts"`
	}
	alerts := decodeJSON[alertsBody](t, alertsResp)
	found := false
	for _, a := range alerts.Alerts {
		if a.Type == "overdue_invoice" && a.InvoiceID == invoiceID {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected an overdue_invoice alert for %s, alerts were %+v", invoiceID, alerts.Alerts)
	}
}

func TestSalesReport_Groupings(t *testing.T) {
	ts := startTestServer(t)
	today := time.Now().Format("2006-01-02")

	// Register a principal and a series prefix, then file an invoice whose
	// number matches the prefix — the report should group it under the
	// principal via the registry stamp applied at upload time.
	prinResp := ts.post(t, "/api/v1/principals", ts.AdminToken,
		map[string]interface{}{"name": "Mondelez", "code": "CAD"})
	if prinResp.StatusCode != http.StatusCreated {
		t.Fatalf("create principal: expected 201, got %d", prinResp.StatusCode)
	}
	type principal struct {
		ID string `json:"id"`
	}
	prin := decodeJSON[principal](t, prinResp)

	seriesResp := ts.post(t, "/api/v1/series-registry", ts.AdminToken,
		map[string]interface{}{"series_prefix": "CAD", "principal_id": prin.ID})
	seriesResp.Body.Close()
	if seriesResp.StatusCode != http.StatusCreated {
		t.Fatalf("create series entry: expected 201, got %d", seriesResp.StatusCode)
	}

	n := testInvoiceCounter.Add(1)
	up := ts.uploadMultipart(t, "/api/v1/invoices/ledger-upload", ts.WorkerToken,
		map[string]string{
			"invoice_number": fmt.Sprintf("CAD/%d", n),
			"entity_gstin":   "06AAAAA0003A1Z3",
			"buyer_gstin":    "06AAAAA0013A1ZD",
			"invoice_date":   today,
			"taxable_amount": "3632.65",
			"total_amount":   "3814.00",
		}, "file", "cad-test.jpg", minimalJPEG(t))
	up.Body.Close()
	if up.StatusCode != http.StatusCreated {
		t.Fatalf("ledger upload: expected 201, got %d", up.StatusCode)
	}

	reportResp := ts.get(t, "/api/v1/owner/reports/sales?group_by=principal&from="+today+"&to="+today, ts.ManagerToken)
	if reportResp.StatusCode != http.StatusOK {
		t.Fatalf("sales report: expected 200, got %d", reportResp.StatusCode)
	}
	type reportBody struct {
		Rows []struct {
			KeyLabel     string  `json:"key_label"`
			InvoiceCount int     `json:"invoice_count"`
			Gross        float64 `json:"gross"`
		} `json:"rows"`
	}
	report := decodeJSON[reportBody](t, reportResp)
	foundMondelez := false
	for _, row := range report.Rows {
		if row.KeyLabel == "Mondelez" {
			foundMondelez = true
			if row.InvoiceCount != 1 || row.Gross < 3813.9 || row.Gross > 3814.1 {
				t.Fatalf("expected 1 Mondelez invoice of ~3814.00, got %+v", row)
			}
		}
	}
	if !foundMondelez {
		t.Fatalf("expected a Mondelez row in the principal report, got %+v", report.Rows)
	}

	// Unknown group_by is rejected, not silently defaulted.
	bad := ts.get(t, "/api/v1/owner/reports/sales?group_by=magic", ts.ManagerToken)
	bad.Body.Close()
	if bad.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for unknown group_by, got %d", bad.StatusCode)
	}
}
