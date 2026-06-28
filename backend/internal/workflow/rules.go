package workflow

import (
	"github.com/himanshu2394i/invoice-saas/internal/validation"
)

// RuleAction defines what to do if a rule evaluates to true
type RuleAction string

const (
	ActionRequireManagerApproval RuleAction = "REQUIRE_MANAGER_APPROVAL"
	ActionRequireFinanceApproval RuleAction = "REQUIRE_FINANCE_APPROVAL"
	ActionAutoApprove            RuleAction = "AUTO_APPROVE"
	ActionAutoReject             RuleAction = "AUTO_REJECT"
)

type TenantRule struct {
	Field    string     `json:"field"`
	Operator string     `json:"operator"`
	Value    float64    `json:"value"` // Simplified to float64 for MVP (e.g. GrossAmount)
	Action   RuleAction `json:"action"`
}

// EvaluateRule dynamically evaluates a DSL rule against the invoice data
func EvaluateRule(rule TenantRule, data validation.InvoiceData) bool {
	var fieldValue float64

	switch rule.Field {
	case "GrossAmount":
		fieldValue = data.GrossAmount
	case "NetAmount":
		fieldValue = data.NetAmount
	case "TaxAmount":
		fieldValue = data.TaxAmount
	default:
		return false
	}

	switch rule.Operator {
	case ">":
		return fieldValue > rule.Value
	case "<":
		return fieldValue < rule.Value
	case "==":
		return fieldValue == rule.Value
	case ">=":
		return fieldValue >= rule.Value
	case "<=":
		return fieldValue <= rule.Value
	}

	return false
}

// EvaluateAllRules takes a list of DSL rules and returns the set of actions that were triggered
func EvaluateAllRules(rules []TenantRule, data validation.InvoiceData) []RuleAction {
	var triggeredActions []RuleAction
	for _, rule := range rules {
		if EvaluateRule(rule, data) {
			triggeredActions = append(triggeredActions, rule.Action)
		}
	}
	return triggeredActions
}
