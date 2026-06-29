package api

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/himanshu2394i/invoice-saas/internal/db"
)

// ─── Owner Dashboard ──────────────────────────────────────────────────────────

func (s *Server) handleOwnerDashboard(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	dash, err := s.Repo.GetOwnerDashboard(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to load dashboard: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, dash)
}

// ─── Owner Invoice List ───────────────────────────────────────────────────────

func (s *Server) handleOwnerListInvoices(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID

	limit := 30
	offset := 0
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 100 {
			limit = n
		}
	}
	if v := r.URL.Query().Get("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			offset = n
		}
	}

	rows, err := s.Repo.ListInvoicesForOwner(r.Context(), tenantID, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list invoices: "+err.Error())
		return
	}
	if rows == nil {
		rows = []*db.OwnerInvoiceRow{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"invoices": rows, "limit": limit, "offset": offset})
}

// ─── Owner Invoice Detail ─────────────────────────────────────────────────────

func (s *Server) handleOwnerGetInvoice(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	invoiceID := r.PathValue("id")

	detail, err := s.Repo.GetInvoiceDetail(r.Context(), tenantID, invoiceID)
	if err != nil {
		writeError(w, http.StatusNotFound, "Invoice not found")
		return
	}
	writeJSON(w, http.StatusOK, detail)
}

// ─── Document Page Download (by page index within doc type) ──────────────────
// GET /api/v1/owner/invoices/{id}/documents/{doc_id}/content
// Same as the existing GET /api/v1/documents/{doc_id}/content but reachable
// from the owner route so the mobile app can build a consistent URL pattern.

func (s *Server) handleOwnerDocumentContent(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	docID := r.PathValue("doc_id")

	ver, err := s.Repo.GetLatestDocumentVersion(r.Context(), tenantID, docID)
	if err != nil {
		writeError(w, http.StatusNotFound, "Document not found")
		return
	}

	f, err := s.Store.Open(ver.S3Key)
	if err != nil {
		writeError(w, http.StatusNotFound, "Stored file content not found")
		return
	}
	defer f.Close()

	// Suggest a download filename from the S3 key
	base := filepath.Base(ver.S3Key)
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, base))

	contentType := "image/jpeg"
	if ext := filepath.Ext(ver.S3Key); ext != "" {
		if ct := mimeByExt(ext); ct != "" {
			contentType = ct
		}
	}
	w.Header().Set("Content-Type", contentType)
	_, _ = io.Copy(w, f)
}

func mimeByExt(ext string) string {
	switch strings.ToLower(ext) {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".pdf":
		return "application/pdf"
	default:
		return "application/octet-stream"
	}
}

// ─── Disputes ─────────────────────────────────────────────────────────────────

// allowedDisputeTypes mirrors the dispute_type CHECK constraint on
// invoice_disputes (see db/migrations/000005_gate_entry_disputes.up.sql) so a
// bad value is rejected with a 400 at the API layer instead of surfacing as
// an opaque 500 from the database constraint violation.
var allowedDisputeTypes = map[string]bool{
	"SHORT_RECEIPT":         true,
	"CREDIT_NOTE_REQUESTED": true,
	"ARITHMETIC_ERROR":      true,
	"MISSING_PAGE":          true,
	"TAX_STRUCTURE_ERROR":   true,
	"OTHER":                 true,
}

type CreateDisputeRequest struct {
	InvoiceID   string `json:"invoice_id"`
	DisputeType string `json:"dispute_type"`
	Description string `json:"description"`
}

func (s *Server) handleCreateDispute(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID

	var req CreateDisputeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if req.InvoiceID == "" || req.DisputeType == "" {
		writeError(w, http.StatusBadRequest, "invoice_id and dispute_type are required")
		return
	}
	disputeType := strings.ToUpper(req.DisputeType)
	if !allowedDisputeTypes[disputeType] {
		writeError(w, http.StatusBadRequest, "dispute_type must be one of SHORT_RECEIPT | CREDIT_NOTE_REQUESTED | ARITHMETIC_ERROR | MISSING_PAGE | TAX_STRUCTURE_ERROR | OTHER")
		return
	}

	// GetInvoice is RLS-scoped to tenantID, so this both confirms the invoice
	// exists and that it belongs to the caller's tenant before we let a
	// dispute row reference it -- without this check a worker could create a
	// dispute pointing at another tenant's invoice ID.
	if _, err := s.Repo.GetInvoice(r.Context(), tenantID, req.InvoiceID); err != nil {
		writeError(w, http.StatusNotFound, "Invoice not found")
		return
	}

	d := &db.InvoiceDispute{
		InvoiceID:   req.InvoiceID,
		DisputeType: disputeType,
		Description: req.Description,
		RaisedBy:    &claims.UserID,
	}
	if err := s.Repo.CreateDispute(r.Context(), tenantID, d); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create dispute: "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, d)
}

type UpdateDisputeRequest struct {
	Status string `json:"status"` // OPEN | OWNER_REVIEWING | RESOLVED | REJECTED
	Notes  string `json:"notes"`
}

func (s *Server) handleUpdateDispute(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID
	id := r.PathValue("id")

	var req UpdateDisputeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	allowed := map[string]bool{"OPEN": true, "OWNER_REVIEWING": true, "RESOLVED": true, "REJECTED": true}
	if !allowed[req.Status] {
		writeError(w, http.StatusBadRequest, "status must be OPEN | OWNER_REVIEWING | RESOLVED | REJECTED")
		return
	}

	if err := s.Repo.UpdateDisputeStatus(r.Context(), tenantID, id, req.Status, claims.UserID, req.Notes); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to update dispute: "+err.Error())
		return
	}
	d, _ := s.Repo.GetDispute(r.Context(), tenantID, id)
	writeJSON(w, http.StatusOK, d)
}

func (s *Server) handleListDisputes(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	status := r.URL.Query().Get("status")
	disputes, err := s.Repo.ListDisputes(r.Context(), tenantID, status)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list disputes: "+err.Error())
		return
	}
	if disputes == nil {
		disputes = []*db.InvoiceDispute{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"disputes": disputes})
}

// handleUploadCreditNote attaches a credit note document to an existing dispute.
// The owner photographed or scanned the issued credit note; this stores it
// and links it so it appears in the invoice's document timeline.
func (s *Server) handleUploadCreditNote(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID
	disputeID := r.PathValue("id")

	dispute, err := s.Repo.GetDispute(r.Context(), tenantID, disputeID)
	if err != nil {
		writeError(w, http.StatusNotFound, "Dispute not found")
		return
	}

	if err := r.ParseMultipartForm(32 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "Expected multipart/form-data with a 'file' part")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "Missing 'file' part")
		return
	}
	defer file.Close()

	s3Key := "uploads/" + tenantID + "/" + dispute.InvoiceID + "/credit_note_" + header.Filename
	hash, size, err := s.Store.Save(s3Key, file)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to store credit note: "+err.Error())
		return
	}

	doc := &db.Document{InvoiceID: dispute.InvoiceID, DocumentType: "CREDIT_NOTE", IsPrimary: false}
	if err := s.Repo.CreateDocument(r.Context(), tenantID, doc); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create document record: "+err.Error())
		return
	}
	ver := &db.DocumentVersion{
		DocumentID:    doc.ID,
		VersionNumber: 1,
		S3Key:         s3Key,
		SHA256Hash:    hash,
		Metadata:      json.RawMessage(fmt.Sprintf(`{"size_bytes":%d,"original_filename":%q,"dispute_id":%q}`, size, header.Filename, disputeID)),
		CreatedBy:     claims.UserID,
	}
	if err := s.Repo.CreateDocumentVersion(r.Context(), tenantID, ver); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create document version: "+err.Error())
		return
	}

	if err := s.Repo.SetDisputeCreditNote(r.Context(), tenantID, disputeID, doc.ID); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to link credit note to dispute: "+err.Error())
		return
	}

	_ = s.Repo.WriteAuditLog(r.Context(), tenantID, dispute.InvoiceID, "CREDIT_NOTE_UPLOADED",
		claims.Email, "Credit note uploaded for dispute "+disputeID,
		map[string]interface{}{"document_id": doc.ID, "dispute_id": disputeID})

	writeJSON(w, http.StatusCreated, map[string]string{
		"document_id": doc.ID,
		"dispute_id":  disputeID,
		"status":      "CREDIT_NOTE_ATTACHED",
	})
}

// ─── Gate Entry Metadata ──────────────────────────────────────────────────────

type SetGateEntryRequest struct {
	DocumentID        string   `json:"document_id"`
	GateEntryNumber   *string  `json:"gate_entry_number"`
	GateEntryDate     *string  `json:"gate_entry_date"` // YYYY-MM-DD
	AcceptedQty       *float64 `json:"accepted_qty"`
	InvoiceQty        *float64 `json:"invoice_qty"`
	DiscrepancyAmount *float64 `json:"discrepancy_amount"`
	IsShortReceipt    bool     `json:"is_short_receipt"`
	Notes             *string  `json:"notes"`
}

func (s *Server) handleSetGateEntry(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID
	invoiceID := r.PathValue("id")

	var req SetGateEntryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if req.DocumentID == "" {
		writeError(w, http.StatusBadRequest, "document_id is required")
		return
	}

	// Same tenant-ownership check as handleCreateDispute: confirm the
	// path-supplied invoice belongs to this tenant before attaching gate
	// entry metadata (and potentially auto-raising a dispute) against it.
	if _, err := s.Repo.GetInvoice(r.Context(), tenantID, invoiceID); err != nil {
		writeError(w, http.StatusNotFound, "Invoice not found")
		return
	}

	userID := claims.UserID
	m := &db.GateEntryMetadata{
		DocumentID:        req.DocumentID,
		InvoiceID:         invoiceID,
		GateEntryNumber:   req.GateEntryNumber,
		GateEntryDate:     req.GateEntryDate,
		AcceptedQty:       req.AcceptedQty,
		InvoiceQty:        req.InvoiceQty,
		DiscrepancyAmount: req.DiscrepancyAmount,
		IsShortReceipt:    req.IsShortReceipt,
		Notes:             req.Notes,
		EnteredBy:         &userID,
	}

	if err := s.Repo.UpsertGateEntryMetadata(r.Context(), tenantID, m); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to save gate entry: "+err.Error())
		return
	}

	// Auto-raise a dispute if this is a short receipt
	if req.IsShortReceipt {
		desc := "Short receipt detected at gate entry"
		if req.Notes != nil && *req.Notes != "" {
			desc = *req.Notes
		}
		dispute := &db.InvoiceDispute{
			InvoiceID:   invoiceID,
			DisputeType: "SHORT_RECEIPT",
			Description: desc,
			RaisedBy:    &userID,
		}
		_ = s.Repo.CreateDispute(r.Context(), tenantID, dispute)
	}

	_ = s.Repo.WriteAuditLog(r.Context(), tenantID, invoiceID, "GATE_ENTRY_SET",
		claims.Email, "Gate entry metadata entered",
		map[string]interface{}{"document_id": req.DocumentID, "is_short_receipt": req.IsShortReceipt})

	writeJSON(w, http.StatusOK, m)
}

func (s *Server) handleGetGateEntries(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	invoiceID := r.PathValue("id")
	entries, err := s.Repo.ListGateEntriesByInvoice(r.Context(), tenantID, invoiceID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list gate entries: "+err.Error())
		return
	}
	if entries == nil {
		entries = []*db.GateEntryMetadata{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"gate_entries": entries})
}

// ─── Entity Management ────────────────────────────────────────────────────────

type CreateEntityRequest struct {
	LegalName     string          `json:"legal_name"`
	TaxIdentifier string          `json:"tax_identifier"` // GSTIN
	Address       json.RawMessage `json:"address"`
}

func (s *Server) handleCreateEntity(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID

	var req CreateEntityRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if req.LegalName == "" || req.TaxIdentifier == "" {
		writeError(w, http.StatusBadRequest, "legal_name and tax_identifier are required")
		return
	}
	addr := req.Address
	if len(addr) == 0 {
		addr = json.RawMessage(`{}`)
	}

	ent, err := s.Repo.CreateEntity(r.Context(), tenantID, req.LegalName, strings.ToUpper(req.TaxIdentifier), addr)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create entity: "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, ent)
}
