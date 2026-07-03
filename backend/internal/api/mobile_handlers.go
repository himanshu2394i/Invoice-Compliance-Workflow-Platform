// mobile_handlers.go — lightweight API endpoints consumed exclusively by the
// Flutter mobile app. Kept separate from api.go to make the boundary explicit.
package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/jackc/pgx/v5"
)

func (s *Server) handleMobileDuplicateInvoiceCheck(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	invoiceNumber := strings.TrimSpace(r.URL.Query().Get("invoice_number"))
	sellerGSTIN := strings.TrimSpace(r.URL.Query().Get("seller_gstin"))
	buyerGSTIN := strings.TrimSpace(r.URL.Query().Get("buyer_gstin"))

	if invoiceNumber == "" {
		writeError(w, http.StatusBadRequest, "invoice_number is required")
		return
	}
	if sellerGSTIN == "" {
		writeError(w, http.StatusBadRequest, "seller_gstin is required")
		return
	}

	match, err := s.Repo.FindDuplicateInvoice(r.Context(), tenantID, invoiceNumber, sellerGSTIN, buyerGSTIN)
	if errors.Is(err, pgx.ErrNoRows) {
		writeJSON(w, http.StatusOK, map[string]bool{"duplicate": false})
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to check duplicate invoice: "+err.Error())
		return
	}

	buyerName := ""
	if match.BuyerName != nil {
		buyerName = *match.BuyerName
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"duplicate":      true,
		"invoice_id":     match.ID,
		"invoice_number": match.InvoiceNumber,
		"buyer_name":     buyerName,
		"invoice_date":   match.InvoiceDate.Format(time.DateOnly),
		"total_amount":   match.TotalAmount,
		"status":         match.Status,
	})
}

// handleMobileGetBuyerRequirements returns the list of supporting documents a
// worker must photograph for a given buyer. Accepts either:
//   - ?gstin=<gstin>  — look up by GSTIN (the normal case: worker just extracted
//     the GSTIN from the invoice photo or picked it from an autocomplete list)
//   - path param {buyer_id} — look up by UUID (when the buyer is already known)
//
// Returns an empty requirements array (not 404) when no requirements are
// configured — that just means the primary invoice photo is sufficient.
func (s *Server) handleMobileGetBuyerRequirements(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID

	var buyer *db.Buyer
	var err error

	gstin := strings.TrimSpace(r.URL.Query().Get("gstin"))
	buyerID := r.PathValue("buyer_id") // will be "" if called from the /by-gstin route

	switch {
	case buyerID != "":
		buyer, err = s.Repo.GetBuyerByID(r.Context(), tenantID, buyerID)
		if err != nil {
			writeError(w, http.StatusNotFound, "Buyer not found")
			return
		}
	case gstin != "":
		buyer, err = s.Repo.GetBuyerByGSTIN(r.Context(), tenantID, gstin)
		if err != nil {
			// Unknown buyer — return empty requirements rather than an error.
			// The mobile app will let the worker continue with no extra docs prompted.
			writeJSON(w, http.StatusOK, map[string]interface{}{
				"buyer":        nil,
				"requirements": []interface{}{},
			})
			return
		}
	default:
		writeError(w, http.StatusBadRequest, "Provide either ?gstin=<gstin> or buyer_id path param")
		return
	}

	reqs, err := s.Repo.ListBuyerDocRequirements(r.Context(), tenantID, buyer.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to load document requirements: "+err.Error())
		return
	}
	if reqs == nil {
		reqs = []*db.BuyerDocRequirement{}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"buyer":        buyer,
		"requirements": reqs,
	})
}

// UpsertBuyerRequirementRequest is the body for POST .../requirements
type UpsertBuyerRequirementRequest struct {
	DocumentType     string `json:"document_type"`
	Label            string `json:"label"`
	IsBuyerGenerated bool   `json:"is_buyer_generated"`
	SortOrder        int    `json:"sort_order"`
}

// handleMobileUpsertBuyerRequirement lets admins (or workers, by design — they
// know their buyers best) configure which extra docs a specific buyer requires.
// Example: configure Vishal Mega Mart (GSTIN 06AAAAA0013A1ZD) to require
// "GATE_ENTRY_NOTE" / "Gate Entry / Discrepancy Note" / is_buyer_generated=true.
func (s *Server) handleMobileUpsertBuyerRequirement(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	buyerID := r.PathValue("buyer_id")

	// Confirm buyer belongs to this tenant
	buyer, err := s.Repo.GetBuyerByID(r.Context(), tenantID, buyerID)
	if err != nil {
		writeError(w, http.StatusNotFound, "Buyer not found")
		return
	}

	var req UpsertBuyerRequirementRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if strings.TrimSpace(req.DocumentType) == "" || strings.TrimSpace(req.Label) == "" {
		writeError(w, http.StatusBadRequest, "document_type and label are required")
		return
	}

	docReq := &db.BuyerDocRequirement{
		BuyerID:          buyer.ID,
		DocumentType:     strings.ToUpper(strings.TrimSpace(req.DocumentType)),
		Label:            strings.TrimSpace(req.Label),
		IsBuyerGenerated: req.IsBuyerGenerated,
		SortOrder:        req.SortOrder,
	}
	if err := s.Repo.UpsertBuyerDocRequirement(r.Context(), tenantID, docReq); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to save requirement: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// handleMobileDeleteBuyerRequirement removes a buyer document requirement.
// ADMIN-only (enforced at route registration): requirements drive what
// workers must photograph, so removing one is a master-data decision.
func (s *Server) handleMobileDeleteBuyerRequirement(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	buyerID := r.PathValue("buyer_id")
	documentType := strings.ToUpper(strings.TrimSpace(r.PathValue("document_type")))

	if documentType == "" {
		writeError(w, http.StatusBadRequest, "document_type is required")
		return
	}
	// Confirm buyer belongs to this tenant before touching its config.
	if _, err := s.Repo.GetBuyerByID(r.Context(), tenantID, buyerID); err != nil {
		writeError(w, http.StatusNotFound, "Buyer not found")
		return
	}
	if err := s.Repo.DeleteBuyerDocRequirement(r.Context(), tenantID, buyerID, documentType); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to delete requirement: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
