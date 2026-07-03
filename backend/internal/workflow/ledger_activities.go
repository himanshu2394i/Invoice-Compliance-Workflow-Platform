package workflow

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/db"
)

// DocumentHeaderExtraction is the lightweight extraction target for a
// supporting document -- deliberately just enough to match it back to an
// invoice, not the full validation.InvoiceData shape InvoiceWorkflow uses.
// Field names match the Python "ExtractDocumentHeader" activity's return dict
// keys exactly (PascalCase), the same convention ExtractTextAndLayout already
// uses -- see backend/python_worker/activities.py.
type DocumentHeaderExtraction struct {
	InvoiceNumber string
	BuyerGSTIN    string
	Amount        *float64
	// Receiving fields, present when the document is a gate entry note /
	// GRN / stock receiving acknowledgement. The matcher records these on
	// the invoice's gate entry metadata so the owner doesn't re-type what
	// the photo already says. Only the Claude extractor fills them; the
	// Textract fallback leaves them at their zero values.
	DocumentType      string
	GateEntryNumber   string
	DocumentDate      string // ISO YYYY-MM-DD, or "" when not printed/legible
	AcceptedQty       *float64
	InvoiceQty        *float64
	DiscrepancyAmount *float64
	// Simulated is true when no real OCR backend (AWS Textract, etc.) is
	// configured. A simulated result carries no real signal, so
	// MatchDocumentToInvoiceActivity must NOT treat it as a confirmed
	// mismatch -- doing so would flag every single upload as wrong on any
	// deployment without OCR credentials configured, which is worse than
	// useless.
	Simulated    bool
	Inconclusive bool
}

func (e DocumentHeaderExtraction) IsInconclusive() bool {
	return e.Inconclusive ||
		(strings.TrimSpace(e.InvoiceNumber) == "" &&
			strings.TrimSpace(e.BuyerGSTIN) == "" &&
			e.Amount == nil &&
			e.AcceptedQty == nil && e.InvoiceQty == nil)
}

// hasReceivingData reports whether the extraction carried any gate-entry
// quantity worth recording -- the presence of these fields is itself the
// signal that the photo was a receiving document.
func (e DocumentHeaderExtraction) hasReceivingData() bool {
	return e.AcceptedQty != nil || e.InvoiceQty != nil || e.DiscrepancyAmount != nil
}

type MatchDocumentInput struct {
	TenantID   string
	InvoiceID  string
	DocumentID string
	Extracted  DocumentHeaderExtraction
}

// MatchDocumentToInvoiceActivity compares a supporting document's extracted
// header against the invoice it was filed under and raises a
// 'document_mismatch' exception if they disagree. A clean match writes an
// audit event but no exception -- exceptions represent open problems, not a
// running log of every check performed.
func MatchDocumentToInvoiceActivity(ctx context.Context, input MatchDocumentInput) error {
	if Repo == nil {
		return fmt.Errorf("workflow.Repo not initialized")
	}

	if input.Extracted.Simulated || input.Extracted.IsInconclusive() {
		_ = Repo.WriteAuditLog(ctx, input.TenantID, input.InvoiceID, "DOCUMENT_MATCH_SKIPPED", "system",
			"Supporting document OCR was unavailable or inconclusive; automatic matching was skipped",
			map[string]interface{}{"document_id": input.DocumentID, "simulated": input.Extracted.Simulated})
		details, _ := json.Marshal(map[string]interface{}{
			"document_id": input.DocumentID,
			"reasons":     []string{"supporting document OCR produced no matchable fields"},
		})
		return Repo.RaiseExceptionIfNotOpen(ctx, input.TenantID, input.InvoiceID, "ocr_inconclusive", details)
	}

	inv, err := Repo.GetInvoice(ctx, input.TenantID, input.InvoiceID)
	if err != nil {
		return err
	}

	var mismatches []string

	if num := strings.TrimSpace(input.Extracted.InvoiceNumber); num != "" &&
		!strings.EqualFold(num, strings.TrimSpace(inv.InvoiceNumber)) {
		mismatches = append(mismatches, fmt.Sprintf(
			"invoice number on document (%s) does not match the invoice it was filed under (%s)",
			num, inv.InvoiceNumber))
	}

	if gstin := strings.TrimSpace(input.Extracted.BuyerGSTIN); gstin != "" && inv.BuyerID != nil {
		buyer, berr := Repo.GetBuyerByID(ctx, input.TenantID, *inv.BuyerID)
		if berr == nil && !strings.EqualFold(gstin, buyer.GSTIN) {
			mismatches = append(mismatches, fmt.Sprintf(
				"buyer GSTIN on document (%s) does not match the invoice's buyer (%s)",
				gstin, buyer.GSTIN))
		}
	}

	if input.Extracted.Amount != nil {
		// Tolerance absorbs rounding/OCR noise (see invoice_extraction.md's
		// repeated note on small reconciliation gaps being normal) without
		// masking a real mismatch: the larger of ₹1 or 1% of the invoice.
		tolerance := math.Max(1.0, inv.GrossAmount*0.01)
		if math.Abs(*input.Extracted.Amount-inv.GrossAmount) > tolerance {
			mismatches = append(mismatches, fmt.Sprintf(
				"amount on document (%.2f) does not match the invoice's gross amount (%.2f)",
				*input.Extracted.Amount, inv.GrossAmount))
		}
	}

	// Record receiving quantities regardless of the match outcome -- a gate
	// entry note whose invoice number smudged still tells us what quantity
	// the buyer accepted.
	if input.Extracted.hasReceivingData() {
		if err := recordGateEntryFromExtraction(ctx, input); err != nil {
			return err
		}
	}

	if len(mismatches) == 0 {
		return Repo.WriteAuditLog(ctx, input.TenantID, input.InvoiceID, "DOCUMENT_MATCHED", "system",
			"Supporting document matched the invoice", map[string]interface{}{"document_id": input.DocumentID})
	}

	details, _ := json.Marshal(map[string]interface{}{
		"document_id": input.DocumentID,
		"reasons":     mismatches,
	})
	if err := Repo.RaiseExceptionIfNotOpen(ctx, input.TenantID, input.InvoiceID, "document_mismatch", details); err != nil {
		return err
	}
	return Repo.WriteAuditLog(ctx, input.TenantID, input.InvoiceID, "DOCUMENT_MISMATCH_DETECTED", "system",
		strings.Join(mismatches, "; "), map[string]interface{}{"document_id": input.DocumentID})
}

// recordGateEntryFromExtraction writes the quantities Claude read off a
// receiving document into the invoice's gate entry metadata and, when they
// show a shortage, raises the same idempotent SHORT_RECEIPT dispute the
// owner's manual gate-entry form would (see api.handleSetGateEntry). A row a
// human already entered for this document always wins over the AI's read.
func recordGateEntryFromExtraction(ctx context.Context, input MatchDocumentInput) error {
	existing, err := Repo.ListGateEntriesByInvoice(ctx, input.TenantID, input.InvoiceID)
	if err != nil {
		return err
	}
	for _, entry := range existing {
		if entry.DocumentID == input.DocumentID && entry.EnteredBy != nil {
			return nil
		}
	}

	ex := input.Extracted
	shortReceipt := (ex.AcceptedQty != nil && ex.InvoiceQty != nil && *ex.AcceptedQty < *ex.InvoiceQty) ||
		(ex.DiscrepancyAmount != nil && *ex.DiscrepancyAmount > 0)

	notes := "Extracted automatically from the uploaded document photo by AI"
	meta := &db.GateEntryMetadata{
		DocumentID:        input.DocumentID,
		InvoiceID:         input.InvoiceID,
		AcceptedQty:       ex.AcceptedQty,
		InvoiceQty:        ex.InvoiceQty,
		DiscrepancyAmount: ex.DiscrepancyAmount,
		IsShortReceipt:    shortReceipt,
		Notes:             &notes,
	}
	if num := strings.TrimSpace(ex.GateEntryNumber); num != "" {
		meta.GateEntryNumber = &num
	}
	if date := strings.TrimSpace(ex.DocumentDate); date != "" {
		if _, perr := time.Parse("2006-01-02", date); perr == nil {
			meta.GateEntryDate = &date
		}
	}
	if err := Repo.UpsertGateEntryMetadata(ctx, input.TenantID, meta); err != nil {
		return err
	}

	if shortReceipt {
		hasOpen, derr := Repo.HasOpenDisputeForInvoice(ctx, input.TenantID, input.InvoiceID)
		if derr == nil && !hasOpen {
			desc := "Receiving mismatch detected on the uploaded gate entry document"
			if ex.AcceptedQty != nil && ex.InvoiceQty != nil && *ex.AcceptedQty < *ex.InvoiceQty {
				desc = fmt.Sprintf("Short receipt: accepted %.2f of %.2f invoiced (read from the document photo)",
					*ex.AcceptedQty, *ex.InvoiceQty)
			}
			_ = Repo.CreateDispute(ctx, input.TenantID, &db.InvoiceDispute{
				InvoiceID:   input.InvoiceID,
				DisputeType: "SHORT_RECEIPT",
				Description: desc,
			})
		}
	}

	return Repo.WriteAuditLog(ctx, input.TenantID, input.InvoiceID, "GATE_ENTRY_AUTO_EXTRACTED", "system",
		"Gate entry quantities extracted from the uploaded document",
		map[string]interface{}{
			"document_id":      input.DocumentID,
			"document_type":    ex.DocumentType,
			"is_short_receipt": shortReceipt,
		})
}
