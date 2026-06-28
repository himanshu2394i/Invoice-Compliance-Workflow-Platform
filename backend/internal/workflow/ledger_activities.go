package workflow

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"
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
	// Simulated is true when no real OCR backend (AWS Textract, etc.) is
	// configured. A simulated result carries no real signal, so
	// MatchDocumentToInvoiceActivity must NOT treat it as a confirmed
	// mismatch -- doing so would flag every single upload as wrong on any
	// deployment without OCR credentials configured, which is worse than
	// useless.
	Simulated bool
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

	if input.Extracted.Simulated {
		_ = Repo.WriteAuditLog(ctx, input.TenantID, input.InvoiceID, "DOCUMENT_MATCH_SKIPPED", "system",
			"No OCR backend configured; supporting document could not be automatically matched",
			map[string]interface{}{"document_id": input.DocumentID})
		return nil
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
