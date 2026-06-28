// api.go
package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/auth"
	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/himanshu2394i/invoice-saas/internal/storage"
	workflowpkg "github.com/himanshu2394i/invoice-saas/internal/workflow"
	"go.temporal.io/sdk/client"
)

// TaskQueue must match the queue the Go Temporal worker (cmd/worker) listens on.
const invoiceTaskQueue = "invoice-task-queue"

type Server struct {
	Repo           *db.Repository
	TemporalClient client.Client
	Store          *storage.Store
	loginLimiter   *loginRateLimiter
}

func NewServer(repo *db.Repository, temporalClient client.Client, store *storage.Store) *Server {
	return &Server{Repo: repo, TemporalClient: temporalClient, Store: store, loginLimiter: newLoginRateLimiter()}
}

func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	// Public: there's no session yet, so these can't require a bearer token.
	mux.HandleFunc("POST /api/v1/auth/login", s.handleLogin)
	// Seeding has no JWT (it's how the very first organization/users get
	// created -- there's no other bootstrap path), but it's gated by
	// requireSeedToken: open in dev, hard-disabled in production unless
	// SEED_SETUP_TOKEN is explicitly configured. See requireSeedToken.
	mux.HandleFunc("POST /api/v1/admin/seed", requireSeedToken(s.handleSeedAdminData))

	// Everything else requires a verified JWT. Tenant ID and role come ONLY from
	// the token from here on -- never from a client-supplied header or field.
	mux.HandleFunc("POST /api/v1/invoices", requireAuth(requireRole("WORKER", "ADMIN")(s.handleIngestInvoice)))
	mux.HandleFunc("POST /api/v1/invoices/upload", requireAuth(requireRole("WORKER", "ADMIN")(s.handleUploadSimulated)))
	mux.HandleFunc("POST /api/v1/invoices/ledger-upload", requireAuth(requireRole("WORKER", "ADMIN")(s.handleUploadLedgerInvoice)))
	mux.HandleFunc("GET /api/v1/entities", requireAuth(s.handleListEntities))
	mux.HandleFunc("GET /api/v1/invoices", requireAuth(s.handleListInvoices))
	mux.HandleFunc("GET /api/v1/invoices/{id}", requireAuth(s.handleGetInvoice))
	mux.HandleFunc("POST /api/v1/invoices/{id}/documents", requireAuth(requireRole("WORKER", "ADMIN")(s.handleUploadSupportingDocument)))
	mux.HandleFunc("GET /api/v1/documents/{id}/content", requireAuth(s.handleGetDocumentContent))
	mux.HandleFunc("POST /api/v1/buyers", requireAuth(requireRole("WORKER", "ADMIN")(s.handleCreateBuyer)))
	mux.HandleFunc("GET /api/v1/buyers", requireAuth(s.handleListBuyers))
	mux.HandleFunc("GET /api/v1/exceptions", requireAuth(s.handleListExceptions))
	mux.HandleFunc("POST /api/v1/exceptions/{id}/resolve", requireAuth(requireRole("WORKER", "ADMIN", "MANAGER")(s.handleResolveException)))
	mux.HandleFunc("POST /api/v1/missing-invoice-numbers/{id}/resolve", requireAuth(requireRole("WORKER", "ADMIN", "MANAGER")(s.handleResolveMissingInvoiceNumber)))
	mux.HandleFunc("POST /api/v1/invoices/{id}/approve", requireAuth(requireRole("MANAGER", "FINANCE", "ADMIN")(s.handleApproveInvoice)))
	mux.HandleFunc("GET /api/v1/invoices/{id}/audit-trail", requireAuth(s.handleGetAuditTrail))
	mux.HandleFunc("POST /api/v1/rules", requireAuth(requireRole("ADMIN")(s.handleCreateRule)))
	mux.HandleFunc("GET /api/v1/rules", requireAuth(requireRole("ADMIN")(s.handleListRules)))
	mux.HandleFunc("DELETE /api/v1/rules/{id}", requireAuth(requireRole("ADMIN")(s.handleDeleteRule)))

	// Mobile-specific endpoints — document requirement lookup and configuration
	mux.HandleFunc("GET /api/v1/mobile/buyers/requirements", requireAuth(s.handleMobileGetBuyerRequirements))
	mux.HandleFunc("GET /api/v1/mobile/buyers/{buyer_id}/requirements", requireAuth(s.handleMobileGetBuyerRequirements))
	mux.HandleFunc("POST /api/v1/mobile/buyers/{buyer_id}/requirements", requireAuth(requireRole("WORKER", "ADMIN")(s.handleMobileUpsertBuyerRequirement)))
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

// startInvoiceWorkflow starts the Temporal lifecycle workflow for a freshly created invoice.
func (s *Server) startInvoiceWorkflow(ctx context.Context, tenantID, invoiceID, s3Key string) (client.WorkflowRun, error) {
	workflowID := "tenant-" + tenantID + "-invoice-" + invoiceID
	options := client.StartWorkflowOptions{
		ID:        workflowID,
		TaskQueue: invoiceTaskQueue,
	}
	input := workflowpkg.InvoiceProcessInput{
		InvoiceID: invoiceID,
		TenantID:  tenantID,
		S3URI:     s3Key,
	}
	return s.TemporalClient.ExecuteWorkflow(ctx, options, workflowpkg.InvoiceWorkflow, input)
}

// Ingestion request payload
type IngestRequest struct {
	EntityID      string  `json:"entity_id"`
	VendorID      string  `json:"vendor_id"`
	BuyerID       string  `json:"buyer_id"`       // optional: who this invoice was issued to (the ledger use case)
	BuyerGSTIN    string  `json:"buyer_gstin"`    // optional alternative to buyer_id -- resolved server-side via GetBuyerByGSTIN
	InvoiceSeries string  `json:"invoice_series"` // optional: e.g. "A26", "NIV", "HYGIN" -- see db.Invoice doc comment on why this isn't auto-derived
	InvoiceNumber string  `json:"invoice_number"`
	InvoiceDate   string  `json:"invoice_date"`
	GrossAmount   float64 `json:"gross_amount"`
	TaxAmount     float64 `json:"tax_amount"`
	Currency      string  `json:"currency"`
	DocumentType  string  `json:"document_type"` // "INVOICE", "PO", etc.
	FileName      string  `json:"file_name"`
	FileHash      string  `json:"file_hash"`
}

func (s *Server) handleIngestInvoice(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID

	var req IngestRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	parsedDate, err := time.Parse("2006-01-02", req.InvoiceDate)
	if err != nil {
		parsedDate = time.Now()
	}

	invoice := &db.Invoice{
		EntityID:      req.EntityID,
		VendorID:      req.VendorID,
		InvoiceNumber: req.InvoiceNumber,
		InvoiceDate:   parsedDate,
		GrossAmount:   req.GrossAmount,
		TaxAmount:     req.TaxAmount,
		Currency:      req.Currency,
	}

	buyerID := strings.TrimSpace(req.BuyerID)
	if buyerID == "" && strings.TrimSpace(req.BuyerGSTIN) != "" {
		if buyer, err := s.Repo.GetBuyerByGSTIN(r.Context(), tenantID, strings.TrimSpace(req.BuyerGSTIN)); err == nil {
			buyerID = buyer.ID
		} else {
			writeError(w, http.StatusBadRequest, "No buyer found for buyer_gstin "+req.BuyerGSTIN+" -- create it first via POST /api/v1/buyers")
			return
		}
	}
	if buyerID != "" {
		invoice.BuyerID = &buyerID
	}
	if series := strings.TrimSpace(req.InvoiceSeries); series != "" {
		invoice.InvoiceSeries = &series
	}

	// Create invoice in PostgreSQL (enforced by RLS tenantID)
	if err := s.Repo.CreateInvoice(r.Context(), tenantID, invoice); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create invoice record: "+err.Error())
		return
	}

	s3Key := "uploads/" + tenantID + "/" + invoice.ID + "/" + req.FileName

	// Create supporting envelope document record + its first immutable version.
	doc := &db.Document{
		InvoiceID:    invoice.ID,
		DocumentType: req.DocumentType,
		IsPrimary:    true,
	}
	if err := s.Repo.CreateDocument(r.Context(), tenantID, doc); err != nil {
		log.Printf("WARNING: failed to create document record for invoice %s: %v", invoice.ID, err)
	} else {
		ver := &db.DocumentVersion{
			DocumentID:    doc.ID,
			VersionNumber: 1,
			S3Key:         s3Key,
			SHA256Hash:    req.FileHash,
			Metadata:      json.RawMessage(`{}`),
			CreatedBy:     claimsFromContext(r.Context()).UserID,
		}
		if err := s.Repo.CreateDocumentVersion(r.Context(), tenantID, ver); err != nil {
			log.Printf("WARNING: failed to create document version for invoice %s: %v", invoice.ID, err)
		}
	}

	_ = s.Repo.WriteAuditLog(r.Context(), tenantID, invoice.ID, "INGESTED", "system", "Invoice ingested", map[string]interface{}{"file_name": req.FileName})

	we, err := s.startInvoiceWorkflow(context.Background(), tenantID, invoice.ID, s3Key)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to start Temporal lifecycle workflow: "+err.Error())
		return
	}

	writeJSON(w, http.StatusAccepted, map[string]string{
		"invoice_id":    invoice.ID,
		"workflow_id":   we.GetID(),
		"run_id":        we.GetRunID(),
		"status":        "INGESTED",
		"s3_upload_url": "https://mock-s3-bucket.s3.amazonaws.com/" + s3Key,
	})
}

// handleUploadSimulated ingests an invoice tied to the tenant's real seeded
// entity/vendor (rather than inventing random ids), so the demo upload flow
// produces data that's actually queryable and consistent. "Simulated" now
// only refers to the invoice metadata (amounts are fixed demo values) --
// the uploaded file itself is real: multipart/form-data with a "file" part,
// stored to disk via s.Store and hashed server-side.
func (s *Server) handleUploadSimulated(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID

	if err := r.ParseMultipartForm(32 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "Expected multipart/form-data with a 'file' part: "+err.Error())
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "Missing 'file' part: "+err.Error())
		return
	}
	defer file.Close()
	fileName := header.Filename

	entity, err := s.Repo.GetFirstEntity(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "No entity found for tenant -- seed the database first")
		return
	}
	vendor, err := s.Repo.GetFirstVendor(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "No vendor found for tenant -- seed the database first")
		return
	}

	invoice := &db.Invoice{
		EntityID:      entity.ID,
		VendorID:      vendor.ID,
		InvoiceNumber: "INV-" + time.Now().Format("20060102150405"),
		InvoiceDate:   time.Now(),
		GrossAmount:   15000.0,
		TaxAmount:     2288.14,
		Currency:      "INR",
	}
	if err := s.Repo.CreateInvoice(r.Context(), tenantID, invoice); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create invoice record: "+err.Error())
		return
	}

	s3Key := "uploads/" + tenantID + "/" + invoice.ID + "/" + fileName
	hash, size, err := s.Store.Save(s3Key, file)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to store uploaded file: "+err.Error())
		return
	}

	doc := &db.Document{InvoiceID: invoice.ID, DocumentType: "INVOICE_IMAGE", IsPrimary: true}
	if err := s.Repo.CreateDocument(r.Context(), tenantID, doc); err != nil {
		log.Printf("WARNING: failed to create document record for invoice %s: %v", invoice.ID, err)
	} else {
		ver := &db.DocumentVersion{
			DocumentID:    doc.ID,
			VersionNumber: 1,
			S3Key:         s3Key,
			SHA256Hash:    hash,
			Metadata:      json.RawMessage(fmt.Sprintf(`{"size_bytes":%d,"original_filename":%q}`, size, fileName)),
			CreatedBy:     claims.UserID, // document_versions.created_by is UUID -- must be a real user id, not an email
		}
		if err := s.Repo.CreateDocumentVersion(r.Context(), tenantID, ver); err != nil {
			log.Printf("WARNING: failed to create document version for invoice %s: %v", invoice.ID, err)
		}
	}

	_ = s.Repo.WriteAuditLog(r.Context(), tenantID, invoice.ID, "INGESTED", "system", "Invoice uploaded via worker dashboard", map[string]interface{}{"file_name": fileName, "size_bytes": size})

	we, err := s.startInvoiceWorkflow(context.Background(), tenantID, invoice.ID, s3Key)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to start Temporal lifecycle workflow: "+err.Error())
		return
	}

	writeJSON(w, http.StatusAccepted, map[string]string{
		"workflow_id": we.GetID(),
		"invoice_id":  invoice.ID,
		"file_name":   fileName,
		"status":      "UPLOAD_ACCEPTED_WORKFLOW_STARTED",
	})
}

// startLedgerDocumentWorkflow starts the matching workflow for a freshly
// uploaded supporting document. Runs on the same invoiceTaskQueue as
// InvoiceWorkflow -- both are hosted by the same cmd/worker process, sharing
// infra deliberately rather than standing up a second worker.
func (s *Server) startLedgerDocumentWorkflow(ctx context.Context, tenantID, invoiceID, documentID, s3Key string) (client.WorkflowRun, error) {
	workflowID := "tenant-" + tenantID + "-ledgerdoc-" + documentID
	options := client.StartWorkflowOptions{
		ID:        workflowID,
		TaskQueue: invoiceTaskQueue,
	}
	input := workflowpkg.LedgerDocumentInput{
		TenantID:   tenantID,
		InvoiceID:  invoiceID,
		DocumentID: documentID,
		S3URI:      s3Key,
	}
	return s.TemporalClient.ExecuteWorkflow(ctx, options, workflowpkg.LedgerDocumentWorkflow, input)
}

// handleUploadSupportingDocument attaches an additional document (a stamped/
// signed receipt, Gate Entry Note, GRN, etc.) to an already-filed invoice --
// the core of the digital ledger workflow: workers don't just upload the
// invoice once, they keep adding proof-of-delivery documents as they come
// back from the buyer. Each upload kicks off LedgerDocumentWorkflow, which
// OCRs the new document and flags a document_mismatch exception if it
// doesn't agree with the invoice it was filed under.
func (s *Server) handleUploadSupportingDocument(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID
	invoiceID := r.PathValue("id")

	inv, err := s.Repo.GetInvoice(r.Context(), tenantID, invoiceID)
	if err != nil {
		writeError(w, http.StatusNotFound, "Invoice not found")
		return
	}

	if err := r.ParseMultipartForm(32 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "Expected multipart/form-data with a 'file' part: "+err.Error())
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "Missing 'file' part: "+err.Error())
		return
	}
	defer file.Close()

	docType := r.FormValue("document_type")
	if docType == "" {
		docType = "SUPPORTING_DOCUMENT"
	}

	s3Key := "uploads/" + tenantID + "/" + inv.ID + "/" + header.Filename
	hash, size, err := s.Store.Save(s3Key, file)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to store uploaded file: "+err.Error())
		return
	}

	// is_primary stays false here -- the primary document is whichever was
	// attached at ingestion time (handleIngestInvoice/handleUploadSimulated);
	// everything filed afterward is supporting evidence, not a replacement.
	doc := &db.Document{InvoiceID: inv.ID, DocumentType: docType, IsPrimary: false}
	if err := s.Repo.CreateDocument(r.Context(), tenantID, doc); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create document record: "+err.Error())
		return
	}
	ver := &db.DocumentVersion{
		DocumentID:    doc.ID,
		VersionNumber: 1,
		S3Key:         s3Key,
		SHA256Hash:    hash,
		Metadata:      json.RawMessage(fmt.Sprintf(`{"size_bytes":%d,"original_filename":%q}`, size, header.Filename)),
		CreatedBy:     claims.UserID,
	}
	if err := s.Repo.CreateDocumentVersion(r.Context(), tenantID, ver); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create document version: "+err.Error())
		return
	}

	_ = s.Repo.WriteAuditLog(r.Context(), tenantID, inv.ID, "SUPPORTING_DOCUMENT_UPLOADED", claims.Email, "Supporting document uploaded: "+docType, map[string]interface{}{"document_id": doc.ID, "file_name": header.Filename})

	we, err := s.startLedgerDocumentWorkflow(context.Background(), tenantID, inv.ID, doc.ID, s3Key)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Document stored, but failed to start matching workflow: "+err.Error())
		return
	}

	writeJSON(w, http.StatusAccepted, map[string]string{
		"document_id": doc.ID,
		"invoice_id":  inv.ID,
		"workflow_id": we.GetID(),
		"status":      "DOCUMENT_STORED_MATCHING_STARTED",
	})
}

// ExceptionView adds the invoice's human-readable number to an
// InvoiceException -- the dashboard shouldn't have to make a second round
// trip per row just to show what an exception is about.
type ExceptionView struct {
	*db.InvoiceException
	InvoiceNumber string `json:"invoice_number,omitempty"`
}

func (s *Server) handleListExceptions(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID

	rawExceptions, err := s.Repo.ListOpenInvoiceExceptions(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list invoice exceptions: "+err.Error())
		return
	}
	enriched := make([]ExceptionView, 0, len(rawExceptions))
	for _, e := range rawExceptions {
		view := ExceptionView{InvoiceException: e}
		if inv, ierr := s.Repo.GetInvoice(r.Context(), tenantID, e.InvoiceID); ierr == nil {
			view.InvoiceNumber = inv.InvoiceNumber
		}
		enriched = append(enriched, view)
	}

	missingNumbers, err := s.Repo.ListOpenMissingInvoiceNumbers(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list missing invoice numbers: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"invoice_exceptions":      enriched,
		"missing_invoice_numbers": missingNumbers,
	})
}

type ResolveExceptionRequest struct {
	Status string `json:"status"` // "resolved" or "not_applicable"
}

func (s *Server) handleResolveException(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	id := r.PathValue("id")
	var req ResolveExceptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || (req.Status != "resolved" && req.Status != "not_applicable") {
		writeError(w, http.StatusBadRequest, "status must be 'resolved' or 'not_applicable'")
		return
	}
	if err := s.Repo.ResolveInvoiceException(r.Context(), tenantID, id, req.Status); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to resolve exception: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": req.Status})
}

func (s *Server) handleResolveMissingInvoiceNumber(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	id := r.PathValue("id")
	var req ResolveExceptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || (req.Status != "resolved" && req.Status != "not_applicable") {
		writeError(w, http.StatusBadRequest, "status must be 'resolved' or 'not_applicable'")
		return
	}
	if err := s.Repo.ResolveMissingInvoiceNumber(r.Context(), tenantID, id, req.Status); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to resolve missing invoice number: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": req.Status})
}

func (s *Server) handleListEntities(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	entities, err := s.Repo.ListEntities(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list entities: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"entities": entities})
}

// handleUploadLedgerInvoice is the real ingestion path for the digital
// ledger: unlike handleUploadSimulated (fixed demo amounts, no real
// metadata) this takes the worker's actual typed-in invoice number, entity,
// buyer, series, date, and amounts alongside the real uploaded file. It
// deliberately does NOT start InvoiceWorkflow -- that pipeline's
// validate/approve/reject states are an AP concept (decide whether to pay a
// vendor) that doesn't apply here. A ledger invoice just needs to exist on
// file; the batch scans (internal/ledgerscan) and the per-document
// LedgerDocumentWorkflow (triggered separately by
// handleUploadSupportingDocument) are this flow's only Temporal usage.
type LedgerUploadFields struct {
	EntityID      string
	BuyerID       string
	InvoiceNumber string
	InvoiceSeries string
	InvoiceDate   string
	GrossAmount   float64
	TaxAmount     float64
	Currency      string
}

func (s *Server) handleUploadLedgerInvoice(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID

	if err := r.ParseMultipartForm(32 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "Expected multipart/form-data with a 'file' part: "+err.Error())
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "Missing 'file' part: "+err.Error())
		return
	}
	defer file.Close()

	invoiceNumber := strings.TrimSpace(r.FormValue("invoice_number"))
	entityID := strings.TrimSpace(r.FormValue("entity_id"))
	buyerID := strings.TrimSpace(r.FormValue("buyer_id"))
	if invoiceNumber == "" || entityID == "" || buyerID == "" {
		writeError(w, http.StatusBadRequest, "invoice_number, entity_id, and buyer_id are required")
		return
	}
	grossAmount, _ := strconv.ParseFloat(r.FormValue("gross_amount"), 64)
	taxAmount, _ := strconv.ParseFloat(r.FormValue("tax_amount"), 64)
	currency := strings.TrimSpace(r.FormValue("currency"))
	if currency == "" {
		currency = "INR"
	}
	invoiceDate := time.Now()
	if d, err := time.Parse("2006-01-02", r.FormValue("invoice_date")); err == nil {
		invoiceDate = d
	}

	invoice := &db.Invoice{
		EntityID:      entityID,
		VendorID:      entityID, // vendor_id is NOT NULL (the AP-direction column) -- harmless self-reference for ledger invoices, which use buyer_id instead. See db.Invoice doc comment.
		BuyerID:       &buyerID,
		InvoiceNumber: invoiceNumber,
		InvoiceDate:   invoiceDate,
		GrossAmount:   grossAmount,
		TaxAmount:     taxAmount,
		Currency:      currency,
	}
	if series := strings.TrimSpace(r.FormValue("invoice_series")); series != "" {
		invoice.InvoiceSeries = &series
	}
	if err := s.Repo.CreateInvoice(r.Context(), tenantID, invoice); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create invoice record: "+err.Error())
		return
	}

	s3Key := "uploads/" + tenantID + "/" + invoice.ID + "/" + header.Filename
	hash, size, err := s.Store.Save(s3Key, file)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to store uploaded file: "+err.Error())
		return
	}

	doc := &db.Document{InvoiceID: invoice.ID, DocumentType: "INVOICE_IMAGE", IsPrimary: true}
	if err := s.Repo.CreateDocument(r.Context(), tenantID, doc); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create document record: "+err.Error())
		return
	}
	ver := &db.DocumentVersion{
		DocumentID:    doc.ID,
		VersionNumber: 1,
		S3Key:         s3Key,
		SHA256Hash:    hash,
		Metadata:      json.RawMessage(fmt.Sprintf(`{"size_bytes":%d,"original_filename":%q}`, size, header.Filename)),
		CreatedBy:     claims.UserID,
	}
	if err := s.Repo.CreateDocumentVersion(r.Context(), tenantID, ver); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create document version: "+err.Error())
		return
	}

	_ = s.Repo.WriteAuditLog(r.Context(), tenantID, invoice.ID, "INGESTED", claims.Email, "Invoice filed via ledger upload", map[string]interface{}{"file_name": header.Filename})

	writeJSON(w, http.StatusCreated, map[string]string{
		"invoice_id": invoice.ID,
		"status":     "INGESTED",
	})
}

const (
	defaultInvoicePageSize = 25
	maxInvoicePageSize     = 100
)

func (s *Server) handleListInvoices(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID

	limit := defaultInvoicePageSize
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 {
		limit = v
	}
	if limit > maxInvoicePageSize {
		limit = maxInvoicePageSize
	}
	offset := 0
	if v, err := strconv.Atoi(r.URL.Query().Get("offset")); err == nil && v >= 0 {
		offset = v
	}
	search := strings.TrimSpace(r.URL.Query().Get("q"))

	list, err := s.Repo.ListInvoices(r.Context(), tenantID, limit, offset, search)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list invoices: "+err.Error())
		return
	}
	total, err := s.Repo.CountInvoices(r.Context(), tenantID, search)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to count invoices: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"tenant_id": tenantID,
		"invoices":  list,
		"total":     total,
		"limit":     limit,
		"offset":    offset,
	})
}

func (s *Server) handleGetInvoice(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	invoiceID := r.PathValue("id")

	inv, err := s.Repo.GetInvoice(r.Context(), tenantID, invoiceID)
	if err != nil {
		writeError(w, http.StatusNotFound, "Invoice not found")
		return
	}

	docs, _ := s.Repo.GetDocumentsForInvoice(r.Context(), tenantID, invoiceID)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"invoice":   inv,
		"documents": docs,
	})
}

// handleGetDocumentContent streams back the actual uploaded file bytes for a
// document. Scoped by tenant via GetLatestDocumentVersion's WithTx -- a
// document belonging to another tenant resolves to "not found", same as
// every other cross-tenant lookup in this API.
func (s *Server) handleGetDocumentContent(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	documentID := r.PathValue("id")

	ver, err := s.Repo.GetLatestDocumentVersion(r.Context(), tenantID, documentID)
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

	contentType := mime.TypeByExtension(filepath.Ext(ver.S3Key))
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	w.Header().Set("Content-Type", contentType)
	_, _ = io.Copy(w, f)
}

type CreateBuyerRequest struct {
	Name    string          `json:"name"`
	GSTIN   string          `json:"gstin"`
	Address json.RawMessage `json:"address"`
}

func (s *Server) handleCreateBuyer(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID

	var req CreateBuyerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if strings.TrimSpace(req.Name) == "" || strings.TrimSpace(req.GSTIN) == "" {
		writeError(w, http.StatusBadRequest, "name and gstin are required")
		return
	}
	addr := req.Address
	if len(addr) == 0 {
		addr = json.RawMessage(`{}`)
	}

	if existing, err := s.Repo.GetBuyerByGSTIN(r.Context(), tenantID, req.GSTIN); err == nil {
		writeJSON(w, http.StatusOK, existing)
		return
	}

	buyer, err := s.Repo.CreateBuyer(r.Context(), tenantID, req.Name, req.GSTIN, addr)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to create buyer: "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, buyer)
}

func (s *Server) handleListBuyers(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	buyers, err := s.Repo.ListBuyers(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list buyers: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"buyers": buyers})
}

type ApproveRequest struct {
	Approved bool   `json:"approved"`
	Comments string `json:"comments"`
}

func (s *Server) handleApproveInvoice(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	tenantID := claims.OrganizationID
	invoiceID := r.PathValue("id")

	var req ApproveRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	// Confirm the invoice exists and belongs to this tenant before signaling.
	if _, err := s.Repo.GetInvoice(r.Context(), tenantID, invoiceID); err != nil {
		writeError(w, http.StatusNotFound, "Invoice not found")
		return
	}

	workflowID := "tenant-" + tenantID + "-invoice-" + invoiceID

	// ActorID comes from the verified token, never from the request body --
	// otherwise any caller could claim to be anyone in the audit trail.
	payload := workflowpkg.ApprovalPayload{
		ActorID:  claims.Email,
		Comments: req.Comments,
	}

	if !req.Approved {
		if err := s.TemporalClient.SignalWorkflow(r.Context(), workflowID, "", workflowpkg.SignalRejection, payload); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to submit rejection signal: "+err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "SIGNAL_SENT"})
		return
	}

	// The signal sent is derived from the authenticated role, never a
	// client-submitted field -- that's what made "Reject" able to silently
	// approve in the pre-auth version of this endpoint.
	switch claims.Role {
	case "MANAGER":
		if err := s.TemporalClient.SignalWorkflow(r.Context(), workflowID, "", workflowpkg.SignalManagerApproval, payload); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to submit approval signal: "+err.Error())
			return
		}
	case "FINANCE":
		if err := s.TemporalClient.SignalWorkflow(r.Context(), workflowID, "", workflowpkg.SignalFinanceApproval, payload); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to submit approval signal: "+err.Error())
			return
		}
	case "ADMIN":
		// Admin override: the workflow is waiting on exactly one of these two
		// channels at a time, so signal both -- whichever isn't currently
		// awaited just sits buffered, harmlessly, until its stage is reached.
		_ = s.TemporalClient.SignalWorkflow(r.Context(), workflowID, "", workflowpkg.SignalManagerApproval, payload)
		_ = s.TemporalClient.SignalWorkflow(r.Context(), workflowID, "", workflowpkg.SignalFinanceApproval, payload)
	default:
		writeError(w, http.StatusForbidden, "Your role cannot approve invoices")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "SIGNAL_SENT"})
}

func (s *Server) handleGetAuditTrail(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	invoiceID := r.PathValue("id")

	trail, err := s.Repo.GetAuditTrail(r.Context(), tenantID, invoiceID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to load audit trail: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, trail)
}

// Only fields/operators/actions internal/workflow/rules.go's EvaluateRule
// actually understands -- anything else would persist successfully but
// silently never match or never do anything, which is worse than rejecting
// it up front. AUTO_APPROVE/AUTO_REJECT exist as RuleAction constants but
// workflows.go's rule-evaluation step doesn't act on them yet, so they're
// deliberately excluded here too until that's wired up.
var (
	allowedRuleFields    = map[string]bool{"GrossAmount": true, "NetAmount": true, "TaxAmount": true}
	allowedRuleOperators = map[string]bool{">": true, "<": true, "==": true, ">=": true, "<=": true}
	allowedRuleActions   = map[string]bool{
		string(workflowpkg.ActionRequireManagerApproval): true,
		string(workflowpkg.ActionRequireFinanceApproval): true,
	}
)

// handleCreateRule persists a tenant-specific rule that the next invoice's
// workflow execution will pick up via FetchTenantRulesActivity. Configuring
// at least one rule replaces ALL of a tenant's default rules (see
// FetchTenantRulesActivity) -- there's no partial-override/merge semantics.
func (s *Server) handleCreateRule(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID

	var rule workflowpkg.TenantRule
	if err := json.NewDecoder(r.Body).Decode(&rule); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid rule payload")
		return
	}
	if !allowedRuleFields[rule.Field] {
		writeError(w, http.StatusBadRequest, "field must be one of GrossAmount, NetAmount, TaxAmount")
		return
	}
	if !allowedRuleOperators[rule.Operator] {
		writeError(w, http.StatusBadRequest, "operator must be one of >, <, ==, >=, <=")
		return
	}
	if !allowedRuleActions[string(rule.Action)] {
		writeError(w, http.StatusBadRequest, "action must be one of REQUIRE_MANAGER_APPROVAL, REQUIRE_FINANCE_APPROVAL")
		return
	}

	created, err := s.Repo.CreateTenantRule(r.Context(), tenantID, rule.Field, rule.Operator, rule.Value, string(rule.Action))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to save rule: "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, created)
}

func (s *Server) handleListRules(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	rules, err := s.Repo.ListTenantRules(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list rules: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"rules": rules,
		"note":  "An empty list means this tenant uses the default policy (manager approval above 0, finance approval above 5000).",
	})
}

func (s *Server) handleDeleteRule(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	ruleID := r.PathValue("id")
	if err := s.Repo.DeleteTenantRule(r.Context(), tenantID, ruleID); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to delete rule: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// Admin Seeder to initialize Organizations, Entities, and Vendors for testing.
func (s *Server) handleSeedAdminData(w http.ResponseWriter, r *http.Request) {
	org, err := s.Repo.CreateOrganization(r.Context(), "Enterprise Corp A")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Org seeding failed: "+err.Error())
		return
	}

	ent, err := s.Repo.CreateEntity(r.Context(), org.ID, "Enterprise Corp A India Ltd", "27AAAAA1111A1Z1", []byte(`{"city": "Mumbai", "country": "IN"}`))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Entity seeding failed: "+err.Error())
		return
	}

	ven, err := s.Repo.CreateVendor(r.Context(), org.ID, "Acme Industrial Supplies", "27BBBBB2222B2Z2", []byte(`{"bank_name": "State Bank of India", "account": "123456789"}`))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Vendor seeding failed: "+err.Error())
		return
	}

	// Seed one demo login per role so the app is usable immediately after seeding.
	// Shared password is fine for a fresh demo tenant -- rotate before real use.
	const demoPassword = "ChangeMe123!"
	passwordHash, err := auth.HashPassword(demoPassword)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to hash demo password: "+err.Error())
		return
	}

	// users.email is globally unique (logins are looked up by email alone, before
	// any tenant is known), so repeated seeding needs a per-org suffix to avoid
	// colliding with a previously seeded demo tenant's accounts.
	orgSuffix := strings.SplitN(org.ID, "-", 2)[0]
	demoUsers := []struct {
		email    string
		fullName string
		role     string
	}{
		{"admin+" + orgSuffix + "@demo.local", "Demo Admin", "ADMIN"},
		{"worker+" + orgSuffix + "@demo.local", "Demo Worker", "WORKER"},
		{"manager+" + orgSuffix + "@demo.local", "Demo Manager", "MANAGER"},
		{"finance+" + orgSuffix + "@demo.local", "Demo Finance", "FINANCE"},
	}
	createdUsers := make([]map[string]string, 0, len(demoUsers))
	for _, du := range demoUsers {
		u, err := s.Repo.CreateUser(r.Context(), org.ID, du.email, passwordHash, du.fullName, du.role)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "User seeding failed for "+du.email+": "+err.Error())
			return
		}
		createdUsers = append(createdUsers, map[string]string{
			"email": u.Email,
			"role":  u.Role,
		})
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"organization_id": org.ID,
		"entity_id":       ent.ID,
		"vendor_id":       ven.ID,
		"users":           createdUsers,
		"demo_password":   demoPassword,
		"message":         "Seed successful. Log in at /login with any of the seeded emails and the demo_password.",
	})
}
