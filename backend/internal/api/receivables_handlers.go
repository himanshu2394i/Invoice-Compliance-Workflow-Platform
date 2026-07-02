package api

// Receivables, payment recording, and sales reports — the "get paid" and
// "know the business" halves of the distributor-ops rebuild (see
// docs/superpowers/specs/2026-07-02-distributor-ops-rebuild-design.md).

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/db"
)

// handleGetReceivables returns the per-buyer outstanding summary over CREDIT
// invoices, with aging buckets. Legacy invoices (NULL payment_type) never
// appear here by construction of the underlying query.
func (s *Server) handleGetReceivables(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	buyers, err := s.Repo.GetReceivablesSummary(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to load receivables: "+err.Error())
		return
	}
	if buyers == nil {
		buyers = []*db.BuyerReceivable{}
	}
	var totalOutstanding, totalOverdue float64
	for _, b := range buyers {
		totalOutstanding += b.Outstanding
		totalOverdue += b.Overdue
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"total_outstanding": totalOutstanding,
		"total_overdue":     totalOverdue,
		"buyers":            buyers,
	})
}

func (s *Server) handleGetBuyerReceivables(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	buyerID := r.PathValue("buyer_id")

	buyer, err := s.Repo.GetBuyerByID(r.Context(), tenantID, buyerID)
	if err != nil {
		writeError(w, http.StatusNotFound, "Buyer not found")
		return
	}
	invoices, err := s.Repo.ListReceivableInvoices(r.Context(), tenantID, buyerID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to load buyer receivables: "+err.Error())
		return
	}
	if invoices == nil {
		invoices = []*db.ReceivableInvoice{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"buyer":    buyer,
		"invoices": invoices,
	})
}

type RecordPaymentRequest struct {
	Amount    float64 `json:"amount"`
	PaidOn    string  `json:"paid_on"` // YYYY-MM-DD; defaults to today
	Mode      string  `json:"mode"`    // CASH | UPI | CHEQUE | NEFT | OTHER
	Reference *string `json:"reference,omitempty"`
	Notes     *string `json:"notes,omitempty"`
}

var validPaymentModes = map[string]bool{
	"CASH": true, "UPI": true, "CHEQUE": true, "NEFT": true, "OTHER": true,
}

func (s *Server) handleRecordPayment(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID
	invoiceID := r.PathValue("id")

	var req RecordPaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if req.Amount <= 0 {
		writeError(w, http.StatusBadRequest, "amount must be positive")
		return
	}
	if !validPaymentModes[req.Mode] {
		writeError(w, http.StatusBadRequest, "mode must be one of CASH, UPI, CHEQUE, NEFT, OTHER")
		return
	}
	paidOn := time.Now()
	if req.PaidOn != "" {
		d, err := time.Parse("2006-01-02", req.PaidOn)
		if err != nil {
			writeError(w, http.StatusBadRequest, "paid_on must be YYYY-MM-DD")
			return
		}
		paidOn = d
	}

	// Tenant-ownership check before writing anything against the invoice.
	inv, err := s.Repo.GetInvoice(r.Context(), tenantID, invoiceID)
	if err != nil {
		writeError(w, http.StatusNotFound, "Invoice not found")
		return
	}

	userID := claims.UserID
	payment := &db.InvoicePayment{
		InvoiceID:  invoiceID,
		Amount:     req.Amount,
		PaidOn:     paidOn,
		Mode:       req.Mode,
		Reference:  req.Reference,
		Notes:      req.Notes,
		RecordedBy: &userID,
	}
	if err := s.Repo.CreatePayment(r.Context(), tenantID, payment); err != nil {
		if errors.Is(err, db.ErrPaymentExceedsBalance) {
			writeError(w, http.StatusBadRequest, "Payment exceeds the invoice's remaining balance")
			return
		}
		writeError(w, http.StatusInternalServerError, "Failed to record payment: "+err.Error())
		return
	}

	_ = s.Repo.WriteAuditLog(r.Context(), tenantID, invoiceID, "PAYMENT_RECORDED",
		claims.Email, "Payment recorded against invoice "+inv.InvoiceNumber,
		map[string]interface{}{"amount": req.Amount, "mode": req.Mode, "paid_on": paidOn.Format("2006-01-02")})

	writeJSON(w, http.StatusCreated, payment)
}

func (s *Server) handleListPayments(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	invoiceID := r.PathValue("id")
	payments, err := s.Repo.ListPaymentsByInvoice(r.Context(), tenantID, invoiceID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list payments: "+err.Error())
		return
	}
	if payments == nil {
		payments = []*db.InvoicePayment{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"payments": payments})
}

// handleSalesReport aggregates the ledger by principal/buyer/channel/entity/
// salesman over an inclusive invoice-date range. Defaults to the current
// month when from/to are omitted.
func (s *Server) handleSalesReport(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	q := r.URL.Query()

	groupBy := q.Get("group_by")
	if groupBy == "" {
		groupBy = "principal"
	}

	now := time.Now()
	from := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	to := now
	if v := q.Get("from"); v != "" {
		d, err := time.Parse("2006-01-02", v)
		if err != nil {
			writeError(w, http.StatusBadRequest, "from must be YYYY-MM-DD")
			return
		}
		from = d
	}
	if v := q.Get("to"); v != "" {
		d, err := time.Parse("2006-01-02", v)
		if err != nil {
			writeError(w, http.StatusBadRequest, "to must be YYYY-MM-DD")
			return
		}
		to = d
	}

	rows, err := s.Repo.GetSalesReport(r.Context(), tenantID, from, to, groupBy)
	if err != nil {
		// GetSalesReport rejects unknown group_by values before touching SQL.
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if rows == nil {
		rows = []*db.SalesReportRow{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"from":     from.Format("2006-01-02"),
		"to":       to.Format("2006-01-02"),
		"group_by": groupBy,
		"rows":     rows,
	})
}
