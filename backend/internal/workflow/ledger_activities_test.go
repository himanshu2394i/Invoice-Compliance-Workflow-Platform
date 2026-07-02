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
	tests := []DocumentHeaderExtraction{
		{InvoiceNumber: "A260000218"},
		{BuyerGSTIN: "06AAAAA0013A1ZD"},
		{Amount: &amount},
	}

	for _, tt := range tests {
		if tt.IsInconclusive() {
			t.Fatalf("expected %#v to carry match signal", tt)
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
