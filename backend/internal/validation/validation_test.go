// validation_test.go
package validation

import (
	"testing"
)

func TestGSTINRegex(t *testing.T) {
	tests := []struct {
		gstin string
		valid bool
	}{
		{"27AAAAA1111A1Z1", true},  // Valid format
		{"27BBBBB2222B2Z2", true},  // Valid format
		{"invalid-gstin", false},   // Too short / wrong format
		{"27AAAAA1111A1A1", false}, // Letter instead of Z in 14th pos
		{"123456789012345", false}, // All digits
	}

	for _, tt := range tests {
		t.Run(tt.gstin, func(t *testing.T) {
			got := gstinRegex.MatchString(tt.gstin)
			if got != tt.valid {
				t.Errorf("gstinRegex.MatchString(%q) = %v; want %v", tt.gstin, got, tt.valid)
			}
		})
	}
}

func TestValidateRejectsSimulatedExtraction(t *testing.T) {
	result := Validate(InvoiceData{
		Simulated:   true,
		GrossAmount: 15000,
		NetAmount:   13500,
		TaxAmount:   1500,
		VendorGSTIN: "06AAAAA0017A1ZH",
	})

	if result.IsValid {
		t.Fatal("expected simulated OCR extraction to be invalid")
	}
	if !result.HasCode("ocr_inconclusive") {
		t.Fatalf("expected ocr_inconclusive code, got %#v", result.Codes)
	}
}

func TestValidateAgainstExpectedRejectsWorkerAmountMismatch(t *testing.T) {
	result := ValidateAgainstExpected(InvoiceData{
		InvoiceNumber: "A260000218",
		VendorGSTIN:   "06AAAAA0003A1Z3",
		GrossAmount:   15000,
		NetAmount:     13500,
		TaxAmount:     1500,
	}, ExpectedInvoice{
		InvoiceNumber: "A260000218",
		SellerGSTIN:   "06AAAAA0003A1Z3",
		GrossAmount:   10913,
		TaxAmount:     519.55,
	})

	if result.IsValid {
		t.Fatal("expected OCR-vs-submitted amount mismatch to be invalid")
	}
	if !result.HasCode("invoice_data_mismatch") {
		t.Fatalf("expected invoice_data_mismatch code, got %#v", result.Codes)
	}
}

func TestValidateAgainstExpectedSkipsAmountsWhenOCRSawNoTotal(t *testing.T) {
	// A multi-page invoice photographed without its last page yields a
	// partial extraction: header fields present, amounts zeroed. That must
	// not read as "the total is zero and disagrees with the worker".
	result := ValidateAgainstExpected(InvoiceData{
		InvoiceNumber: "A260000218",
		VendorGSTIN:   "06AAAAA0003A1Z3",
		GrossAmount:   0,
		NetAmount:     0,
		TaxAmount:     0,
	}, ExpectedInvoice{
		InvoiceNumber: "A260000218",
		SellerGSTIN:   "06AAAAA0003A1Z3",
		GrossAmount:   10913,
		TaxAmount:     519.55,
	})

	if result.HasCode("invoice_data_mismatch") {
		t.Fatalf("partial extraction must not raise amount mismatches, got %#v", result.Errors)
	}
}

func TestValidateAgainstExpectedAcceptsMatchingInvoice(t *testing.T) {
	result := ValidateAgainstExpected(InvoiceData{
		InvoiceNumber: "A260000218",
		VendorGSTIN:   "06AAAAA0003A1Z3",
		BuyerGSTIN:    "06AAAAA0013A1ZD",
		GrossAmount:   10913,
		NetAmount:     10393.45,
		TaxAmount:     519.55,
	}, ExpectedInvoice{
		InvoiceNumber: "A260000218",
		SellerGSTIN:   "06AAAAA0003A1Z3",
		BuyerGSTIN:    "06AAAAA0013A1ZD",
		GrossAmount:   10913,
		TaxAmount:     519.55,
	})

	if !result.IsValid {
		t.Fatalf("expected matching OCR/submitted invoice to be valid, got errors %#v", result.Errors)
	}
}
