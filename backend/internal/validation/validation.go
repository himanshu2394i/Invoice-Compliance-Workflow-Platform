package validation

import (
	"fmt"
	"math"
	"regexp"
	"strings"
)

type InvoiceData struct {
	InvoiceNumber string
	VendorGSTIN   string
	BuyerGSTIN    string
	GrossAmount   float64
	NetAmount     float64
	TaxAmount     float64
	Simulated     bool
	Inconclusive  bool
	// Per-field extraction confidence (0..1) keyed by API field name
	// (invoice_number, gross_amount, taxable_amount, tax_amount,
	// seller_gstin, buyer_gstin). Nil/empty when the extractor predates
	// confidence reporting; missing keys mean low confidence.
	Confidence map[string]float64
}

type ExpectedInvoice struct {
	InvoiceNumber string
	SellerGSTIN   string
	BuyerGSTIN    string
	GrossAmount   float64
	TaxAmount     float64
}

type ValidationResult struct {
	IsValid bool
	Errors  []string
	Codes   []string
}

func (r *ValidationResult) add(code, message string) {
	r.IsValid = false
	r.Codes = append(r.Codes, code)
	r.Errors = append(r.Errors, message)
}

func (r ValidationResult) HasCode(code string) bool {
	for _, c := range r.Codes {
		if c == code {
			return true
		}
	}
	return false
}

// gstinRegex matches the 15-character Indian GSTIN format (2-digit state code,
// 5 letters, 4 digits, 1 letter, 1 alphanumeric, literal 'Z', 1 alphanumeric checksum).
var gstinRegex = regexp.MustCompile(`^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$`)

// Validate applies business rules to the extracted invoice data
func Validate(data InvoiceData) ValidationResult {
	result := ValidationResult{
		IsValid: true,
		Errors:  []string{},
		Codes:   []string{},
	}

	if data.Simulated || data.Inconclusive {
		result.add("ocr_inconclusive", "OCR extraction was simulated or inconclusive; human review is required")
		return result
	}

	// Rule 1: GSTIN Pattern Check (15 chars, alphanumeric)
	if !gstinRegex.MatchString(data.VendorGSTIN) {
		result.add("validation_failed", fmt.Sprintf("Invalid Vendor GSTIN format: %s", data.VendorGSTIN))
	}

	// Rule 2: Math Check (Gross == Net + Tax)
	// We allow a small tolerance for floating point / rounding issues
	calculatedGross := data.NetAmount + data.TaxAmount
	if math.Abs(data.GrossAmount-calculatedGross) > 0.05 {
		result.add("validation_failed", fmt.Sprintf("Math mismatch: Net (%.2f) + Tax (%.2f) != Gross (%.2f)", data.NetAmount, data.TaxAmount, data.GrossAmount))
	}

	return result
}

func ValidateAgainstExpected(data InvoiceData, expected ExpectedInvoice) ValidationResult {
	result := Validate(data)
	if data.Simulated || data.Inconclusive {
		return result
	}

	if data.InvoiceNumber != "" && expected.InvoiceNumber != "" &&
		!strings.EqualFold(strings.TrimSpace(data.InvoiceNumber), strings.TrimSpace(expected.InvoiceNumber)) {
		result.add("invoice_data_mismatch", fmt.Sprintf("OCR invoice number (%s) does not match submitted invoice number (%s)", data.InvoiceNumber, expected.InvoiceNumber))
	}
	if data.VendorGSTIN != "" && expected.SellerGSTIN != "" &&
		!strings.EqualFold(strings.TrimSpace(data.VendorGSTIN), strings.TrimSpace(expected.SellerGSTIN)) {
		result.add("invoice_data_mismatch", fmt.Sprintf("OCR seller GSTIN (%s) does not match selected seller GSTIN (%s)", data.VendorGSTIN, expected.SellerGSTIN))
	}
	if data.BuyerGSTIN != "" && expected.BuyerGSTIN != "" &&
		!strings.EqualFold(strings.TrimSpace(data.BuyerGSTIN), strings.TrimSpace(expected.BuyerGSTIN)) {
		result.add("invoice_data_mismatch", fmt.Sprintf("OCR buyer GSTIN (%s) does not match selected buyer GSTIN (%s)", data.BuyerGSTIN, expected.BuyerGSTIN))
	}
	if expected.GrossAmount > 0 && math.Abs(data.GrossAmount-expected.GrossAmount) > amountTolerance(expected.GrossAmount) {
		result.add("invoice_data_mismatch", fmt.Sprintf("OCR gross amount (%.2f) does not match submitted total amount (%.2f)", data.GrossAmount, expected.GrossAmount))
	}
	if expected.TaxAmount > 0 && math.Abs(data.TaxAmount-expected.TaxAmount) > amountTolerance(expected.GrossAmount) {
		result.add("invoice_data_mismatch", fmt.Sprintf("OCR tax amount (%.2f) does not match submitted tax amount (%.2f)", data.TaxAmount, expected.TaxAmount))
	}

	return result
}

func amountTolerance(amount float64) float64 {
	return math.Max(1.0, amount*0.01)
}
