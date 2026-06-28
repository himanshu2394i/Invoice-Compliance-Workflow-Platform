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
