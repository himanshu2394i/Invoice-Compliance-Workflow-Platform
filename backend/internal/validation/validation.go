package validation

import (
	"fmt"
	"math"
	"regexp"
)

type InvoiceData struct {
	InvoiceNumber string
	VendorGSTIN   string
	BuyerGSTIN    string
	GrossAmount   float64
	NetAmount     float64
	TaxAmount     float64
}

type ValidationResult struct {
	IsValid bool
	Errors  []string
}

// gstinRegex matches the 15-character Indian GSTIN format (2-digit state code,
// 5 letters, 4 digits, 1 letter, 1 alphanumeric, literal 'Z', 1 alphanumeric checksum).
var gstinRegex = regexp.MustCompile(`^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$`)

// Validate applies business rules to the extracted invoice data
func Validate(data InvoiceData) ValidationResult {
	result := ValidationResult{
		IsValid: true,
		Errors:  []string{},
	}

	// Rule 1: GSTIN Pattern Check (15 chars, alphanumeric)
	if !gstinRegex.MatchString(data.VendorGSTIN) {
		result.IsValid = false
		result.Errors = append(result.Errors, fmt.Sprintf("Invalid Vendor GSTIN format: %s", data.VendorGSTIN))
	}

	// Rule 2: Math Check (Gross == Net + Tax)
	// We allow a small tolerance for floating point / rounding issues
	calculatedGross := data.NetAmount + data.TaxAmount
	if math.Abs(data.GrossAmount-calculatedGross) > 0.05 {
		result.IsValid = false
		result.Errors = append(result.Errors, fmt.Sprintf("Math mismatch: Net (%.2f) + Tax (%.2f) != Gross (%.2f)", data.NetAmount, data.TaxAmount, data.GrossAmount))
	}

	return result
}
