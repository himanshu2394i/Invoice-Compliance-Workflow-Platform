package workflow

import (
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/validation"
	"go.temporal.io/sdk/workflow"
)

// Workflow states, persisted to Postgres via UpdateInvoiceStateActivity so the
// dashboard reflects real progress instead of being stuck at INGESTED.
const (
	StateValidating     = "VALIDATING"
	StateValidationFail = "VALIDATION_FAILED"
	StatePendingManager = "PENDING_MANAGER_APPROVAL"
	StatePendingFinance = "PENDING_FINANCE_APPROVAL"
	StateApproved       = "APPROVED"
	StateRejected       = "REJECTED"
	StateArchived       = "ARCHIVED"
)

// Signal channels for human-in-the-loop decisions. Separate channels per role
// so the API can signal the correct one instead of one generic "approve" signal
// that can't distinguish who approved or whether it was actually a rejection.
const (
	SignalManagerApproval = "ManagerApprovalSignal"
	SignalFinanceApproval = "FinanceApprovalSignal"
	SignalRejection       = "RejectionSignal"
)

type ApprovalPayload struct {
	ActorID  string
	Comments string
}

type InvoiceProcessInput struct {
	InvoiceID string
	TenantID  string
	S3URI     string
}

type InvoiceProcessResult struct {
	FinalState string
	Message    string
}

// InvoiceOCRPreviewWorkflow extracts fields from every page photo of one
// invoice (in page order) so the capture screen can autofill before the
// worker types anything. Multi-page matters: Meridian invoices print the
// grand total on the LAST page, so extraction that only saw page 1 could
// never fill the amounts.
func InvoiceOCRPreviewWorkflow(ctx workflow.Context, s3URIs []string) (validation.InvoiceData, error) {
	ocrCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		// Multi-image Claude calls run longer than the single-page 20s
		// budget did; the API handler stops waiting before this expires.
		StartToCloseTimeout: time.Second * 40,
		TaskQueue:           "ocr-tasks",
	})
	var extractedData validation.InvoiceData
	if err := workflow.ExecuteActivity(ocrCtx, "ExtractTextAndLayout", s3URIs).Get(ocrCtx, &extractedData); err != nil {
		return validation.InvoiceData{}, err
	}
	return extractedData, nil
}

// InvoiceWorkflowName is the registered name used to start this workflow from the API.
const InvoiceWorkflowName = "InvoiceWorkflow"

// InvoiceWorkflow orchestrates the compliance and approval steps for an invoice.
func InvoiceWorkflow(ctx workflow.Context, input InvoiceProcessInput) (*InvoiceProcessResult, error) {
	logger := workflow.GetLogger(ctx)
	logger.Info("InvoiceWorkflow started", "InvoiceID", input.InvoiceID)

	setState := func(state string) {
		if err := workflow.ExecuteActivity(ctx, UpdateInvoiceStateActivity, input.TenantID, input.InvoiceID, state).Get(ctx, nil); err != nil {
			logger.Warn("Failed to persist invoice state", "State", state, "Error", err)
		}
	}
	logAudit := func(eventType, actorID, description string, payload map[string]interface{}) {
		if err := workflow.ExecuteActivity(ctx, LogAuditEventActivity, input.TenantID, input.InvoiceID, eventType, actorID, description, payload).Get(ctx, nil); err != nil {
			logger.Warn("Failed to write audit event", "EventType", eventType, "Error", err)
		}
	}

	// Go-side activities (validation, state persistence, audit logging) run on this
	// workflow's own task queue, where the Go worker (cmd/worker) listens.
	ctx = workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		StartToCloseTimeout: time.Minute,
	})

	// OCR/AI activities are handled by the separate Python worker on its own queue --
	// they must NOT share ctx with the Go activities above, or they'd be dispatched
	// to a queue nothing is listening on (and vice versa).
	ocrCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		StartToCloseTimeout: time.Minute * 5,
		TaskQueue:           "ocr-tasks",
	})

	// Step 1: Extraction (Python LayoutLMv3 worker; falls back to simulation if ML deps aren't installed).
	var extractedData validation.InvoiceData
	if err := workflow.ExecuteActivity(ocrCtx, "ExtractTextAndLayout", input.S3URI).Get(ocrCtx, &extractedData); err != nil {
		return nil, err
	}
	logAudit("DOCUMENT_EXTRACTED", "system", "OCR extraction completed", map[string]interface{}{"vendor_gstin": extractedData.VendorGSTIN})

	// Step 2: Deterministic validation + reconciliation against the submitted invoice row.
	setState(StateValidating)
	var validationResult validation.ValidationResult
	if err := workflow.ExecuteActivity(ctx, ValidateInvoiceAgainstRecordActivity, input.TenantID, input.InvoiceID, extractedData).Get(ctx, &validationResult); err != nil {
		return nil, err
	}

	rejectCh := workflow.GetSignalChannel(ctx, SignalRejection)

	if !validationResult.IsValid {
		logger.Warn("Deterministic validation failed", "Errors", validationResult.Errors)
		setState(StateValidationFail)
		logAudit("VALIDATION_FAILED", "system", "Deterministic validation failed", map[string]interface{}{"errors": validationResult.Errors})
		if err := workflow.ExecuteActivity(ctx, RaiseValidationExceptionActivity, input.TenantID, input.InvoiceID, validationResult).Get(ctx, nil); err != nil {
			logger.Warn("Failed to raise validation exception", "Error", err)
		}

		aiResolved := false
		if !requiresHumanValidationReview(validationResult) {
			// V2 Feature: Delegate minor arithmetic-only discrepancies to an AI
			// agent before escalating. OCR-inconclusive and submitted-data
			// mismatches are evidence problems, so they require human review.
			var aiDecision map[string]interface{}
			err := workflow.ExecuteActivity(ocrCtx, "AIResolveDiscrepancy", validationResult).Get(ocrCtx, &aiDecision)
			if err == nil && aiDecision["resolved"] == true {
				aiResolved = true
				logger.Info("AI Agent automatically resolved the discrepancy", "Reasoning", aiDecision["reasoning"])
				logAudit("AI_AUTO_RESOLVED", "ai-agent", "AI agent resolved validation discrepancy", aiDecision)
			}
		}

		if !aiResolved {
			logger.Info("AI Agent escalated to human reviewer")
			setState(StatePendingManager)
			// A manager override-approves to continue the pipeline despite the validation
			// failure, or rejects outright. Reuses the manager channel rather than adding
			// a third signal type just for this escalation path.
			overrideCh := workflow.GetSignalChannel(ctx, SignalManagerApproval)
			approved, payload := waitForDecision(ctx, overrideCh, rejectCh)
			if !approved {
				setState(StateRejected)
				logAudit("REJECTED", payload.ActorID, payload.Comments, nil)
				return &InvoiceProcessResult{FinalState: StateRejected, Message: "Rejected after AI escalation"}, nil
			}
			logAudit("VALIDATION_OVERRIDE_APPROVED", payload.ActorID, payload.Comments, nil)
		}
	}

	// Step 3: Dynamic approval rule evaluation. Reads the tenant's configured
	// rules (POST /api/v1/rules), falling back to the original fixed
	// dual-approval-above-threshold policy if they haven't configured any.
	var tenantRules []TenantRule
	if err := workflow.ExecuteActivity(ctx, FetchTenantRulesActivity, input.TenantID).Get(ctx, &tenantRules); err != nil {
		return nil, err
	}
	triggeredActions := EvaluateAllRules(tenantRules, extractedData)

	requiresManager := false
	requiresFinance := false
	for _, action := range triggeredActions {
		if action == ActionRequireManagerApproval {
			requiresManager = true
		}
		if action == ActionRequireFinanceApproval {
			requiresFinance = true
		}
	}

	// Step 4: Execute approval flow, listening for rejection at every stage.
	if requiresManager {
		setState(StatePendingManager)
		logger.Info("Rule Engine: Waiting for Manager Approval")
		approveCh := workflow.GetSignalChannel(ctx, SignalManagerApproval)
		approved, payload := waitForDecision(ctx, approveCh, rejectCh)
		if !approved {
			setState(StateRejected)
			logAudit("REJECTED", payload.ActorID, payload.Comments, nil)
			return &InvoiceProcessResult{FinalState: StateRejected, Message: "Manager rejected"}, nil
		}
		logAudit("MANAGER_APPROVED", payload.ActorID, payload.Comments, nil)
	}

	if requiresFinance {
		setState(StatePendingFinance)
		logger.Info("Rule Engine: Waiting for Finance Approval")
		approveCh := workflow.GetSignalChannel(ctx, SignalFinanceApproval)
		approved, payload := waitForDecision(ctx, approveCh, rejectCh)
		if !approved {
			setState(StateRejected)
			logAudit("REJECTED", payload.ActorID, payload.Comments, nil)
			return &InvoiceProcessResult{FinalState: StateRejected, Message: "Finance rejected"}, nil
		}
		logAudit("FINANCE_APPROVED", payload.ActorID, payload.Comments, nil)
	}

	setState(StateApproved)
	logAudit("APPROVED", "system", "Invoice fully approved", nil)

	setState(StateArchived)
	logAudit("ARCHIVED", "system", "Invoice archived after approval cycle", nil)

	logger.Info("InvoiceWorkflow completed successfully via Rule Engine")
	return &InvoiceProcessResult{FinalState: StateArchived, Message: "Fully approved and archived"}, nil
}

// waitForDecision blocks until either the approval or rejection channel receives a signal,
// returning whether it was an approval and the payload that came with it.
func waitForDecision(ctx workflow.Context, approveCh, rejectCh workflow.ReceiveChannel) (bool, ApprovalPayload) {
	var payload ApprovalPayload
	approved := false
	selector := workflow.NewSelector(ctx)
	selector.AddReceive(approveCh, func(c workflow.ReceiveChannel, more bool) {
		c.Receive(ctx, &payload)
		approved = true
	})
	if rejectCh != approveCh {
		selector.AddReceive(rejectCh, func(c workflow.ReceiveChannel, more bool) {
			c.Receive(ctx, &payload)
			approved = false
		})
	}
	selector.Select(ctx)
	return approved, payload
}

func requiresHumanValidationReview(result validation.ValidationResult) bool {
	return result.HasCode("ocr_inconclusive") || result.HasCode("invoice_data_mismatch")
}
