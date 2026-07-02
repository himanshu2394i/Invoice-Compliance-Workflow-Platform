package workflow

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/himanshu2394i/invoice-saas/internal/validation"
)

// Repo is the database dependency for activities that need to persist workflow
// progress (state transitions, audit events). Set once by the worker process
// at startup, mirroring the package-level wiring already used by internal/api.
var Repo *db.Repository

// ExtractInvoiceDataActivity simulates the Go-side fallback for OCR extraction.
// In practice the workflow calls the Python worker's "ExtractTextAndLayout" activity
// (see backend/python_worker) on the ocr-tasks queue; this Go activity exists as a
// dependency-free fallback/test double and is registered under its own name.
func ExtractInvoiceDataActivity(ctx context.Context, s3URI string) (*validation.InvoiceData, error) {
	return &validation.InvoiceData{
		InvoiceNumber: "INV-1001",
		VendorGSTIN:   "06AAAAA0017A1ZH",
		BuyerGSTIN:    "06AAAAA0013A1ZD",
		GrossAmount:   15000.0,
		NetAmount:     12711.86,
		TaxAmount:     2288.14,
	}, nil
}

// ValidateInvoiceActivity performs business rules checks.
func ValidateInvoiceActivity(ctx context.Context, data validation.InvoiceData) (*validation.ValidationResult, error) {
	result := validation.Validate(data)
	return &result, nil
}

func ValidateInvoiceAgainstRecordActivity(ctx context.Context, tenantID, invoiceID string, data validation.InvoiceData) (*validation.ValidationResult, error) {
	if Repo == nil {
		return nil, fmt.Errorf("workflow.Repo not initialized")
	}
	inv, err := Repo.GetInvoice(ctx, tenantID, invoiceID)
	if err != nil {
		return nil, err
	}
	entity, err := Repo.GetEntityByID(ctx, tenantID, inv.EntityID)
	if err != nil {
		return nil, err
	}
	expected := validation.ExpectedInvoice{
		InvoiceNumber: inv.InvoiceNumber,
		SellerGSTIN:   entity.TaxIdentifier,
		GrossAmount:   inv.GrossAmount,
		TaxAmount:     inv.TaxAmount,
	}
	if inv.BuyerID != nil {
		if buyer, berr := Repo.GetBuyerByID(ctx, tenantID, *inv.BuyerID); berr == nil {
			expected.BuyerGSTIN = buyer.GSTIN
		}
	}

	result := validation.ValidateAgainstExpected(data, expected)
	return &result, nil
}

func RaiseValidationExceptionActivity(ctx context.Context, tenantID, invoiceID string, result validation.ValidationResult) error {
	if Repo == nil {
		return fmt.Errorf("workflow.Repo not initialized")
	}
	exceptionType := "validation_failed"
	if result.HasCode("ocr_inconclusive") {
		exceptionType = "ocr_inconclusive"
	} else if result.HasCode("invoice_data_mismatch") {
		exceptionType = "invoice_data_mismatch"
	}
	details, _ := json.Marshal(map[string]interface{}{
		"errors": result.Errors,
		"codes":  result.Codes,
	})
	return Repo.RaiseExceptionIfNotOpen(ctx, tenantID, invoiceID, exceptionType, details)
}

// UpdateInvoiceStateActivity persists the invoice's current lifecycle state so the
// dashboard reflects real Temporal progress instead of being stuck at INGESTED.
func UpdateInvoiceStateActivity(ctx context.Context, tenantID, invoiceID, newState string) error {
	if Repo == nil {
		return fmt.Errorf("workflow.Repo not initialized")
	}
	return Repo.UpdateInvoiceState(ctx, tenantID, invoiceID, newState)
}

// LogAuditEventActivity appends a hash-chained audit event for the invoice.
func LogAuditEventActivity(ctx context.Context, tenantID, invoiceID, eventType, actorID, description string, payload map[string]interface{}) error {
	if Repo == nil {
		return fmt.Errorf("workflow.Repo not initialized")
	}
	if payload == nil {
		payload = map[string]interface{}{}
	}
	return Repo.WriteAuditLog(ctx, tenantID, invoiceID, eventType, actorID, description, payload)
}

// defaultTenantRules is the dual-approval-above-threshold policy every tenant
// got before rules were configurable. Tenants who haven't added any rules of
// their own (the common case today) must see exactly this same behavior --
// only tenants who've actually called POST /api/v1/rules get something different.
var defaultTenantRules = []TenantRule{
	{Field: "GrossAmount", Operator: ">", Value: 0.0, Action: ActionRequireManagerApproval},
	{Field: "GrossAmount", Operator: ">", Value: 5000.0, Action: ActionRequireFinanceApproval},
}

// FetchTenantRulesActivity reads the tenant's configured rules from
// tenant_rules, falling back to defaultTenantRules if they haven't configured
// any -- see handleCreateRule/handleListRules in internal/api for how rules
// get persisted.
func FetchTenantRulesActivity(ctx context.Context, tenantID string) ([]TenantRule, error) {
	if Repo == nil {
		return nil, fmt.Errorf("workflow.Repo not initialized")
	}
	rows, err := Repo.ListTenantRules(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return defaultTenantRules, nil
	}
	rules := make([]TenantRule, len(rows))
	for i, row := range rows {
		rules[i] = TenantRule{
			Field:    row.Field,
			Operator: row.Operator,
			Value:    row.Value,
			Action:   RuleAction(row.Action),
		}
	}
	return rules, nil
}
