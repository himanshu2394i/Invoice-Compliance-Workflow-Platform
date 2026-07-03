package workflow

import (
	"testing"

	"github.com/himanshu2394i/invoice-saas/internal/validation"
)

func TestDocumentHeaderExtractionInconclusiveWhenNoFieldsExtracted(t *testing.T) {
	extracted := DocumentHeaderExtraction{Simulated: false}

	if !extracted.IsInconclusive() {
		t.Fatal("expected a real OCR response with no extracted fields to be inconclusive")
	}
}

func TestDocumentHeaderExtractionHasSignalWhenAnyFieldExtracted(t *testing.T) {
	amount := 10913.0
	qty := 48.0
	tests := []DocumentHeaderExtraction{
		{InvoiceNumber: "A260000218"},
		{BuyerGSTIN: "06AAAAA0013A1ZD"},
		{Amount: &amount},
		// A gate entry note whose invoice number smudged still carries
		// signal: the accepted quantity is worth recording.
		{AcceptedQty: &qty},
		{InvoiceQty: &qty},
	}

	for _, tt := range tests {
		if tt.IsInconclusive() {
			t.Fatalf("expected %#v to carry match signal", tt)
		}
	}
}

func TestHasReceivingDataDetectsGateEntryQuantities(t *testing.T) {
	qty := 48.0
	disc := 250.0
	if (DocumentHeaderExtraction{InvoiceNumber: "A260000218"}).hasReceivingData() {
		t.Fatal("header-only extraction should not look like a receiving document")
	}
	for _, tt := range []DocumentHeaderExtraction{
		{AcceptedQty: &qty},
		{InvoiceQty: &qty},
		{DiscrepancyAmount: &disc},
	} {
		if !tt.hasReceivingData() {
			t.Fatalf("expected %#v to carry receiving data", tt)
		}
	}
}

func TestRequiresHumanValidationReviewForOCRMismatchCodes(t *testing.T) {
	for _, code := range []string{"ocr_inconclusive", "invoice_data_mismatch"} {
		result := validation.ValidationResult{IsValid: false, Codes: []string{code}}
		if !requiresHumanValidationReview(result) {
			t.Fatalf("expected %s to require human validation review", code)
		}
	}
}
