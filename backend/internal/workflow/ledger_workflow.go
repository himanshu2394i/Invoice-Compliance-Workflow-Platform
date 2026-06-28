package workflow

import (
	"time"

	"go.temporal.io/sdk/workflow"
)

// LedgerDocumentWorkflowName is the registered name used to start this
// workflow from the API (see internal/api's handleUploadSupportingDocument).
const LedgerDocumentWorkflowName = "LedgerDocumentWorkflow"

type LedgerDocumentInput struct {
	TenantID   string
	InvoiceID  string
	DocumentID string
	S3URI      string
}

// LedgerDocumentWorkflow runs whenever a supporting document (a stamped/
// signed receipt, Gate Entry Note, GRN, etc.) is uploaded against an
// already-filed invoice. Unlike InvoiceWorkflow (the AP-direction approve/
// reject pipeline), this one has no human-approval steps -- it just extracts
// the new document's header fields and checks they agree with the invoice it
// was attached to, raising an exception if not.
func LedgerDocumentWorkflow(ctx workflow.Context, input LedgerDocumentInput) error {
	logger := workflow.GetLogger(ctx)
	logger.Info("LedgerDocumentWorkflow started", "InvoiceID", input.InvoiceID, "DocumentID", input.DocumentID)

	// Same queue-separation rule as InvoiceWorkflow: OCR runs on the Python
	// worker's "ocr-tasks" queue, the matching activity runs on this
	// workflow's own queue where the Go worker (cmd/worker) listens.
	ocrCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		StartToCloseTimeout: time.Minute * 5,
		TaskQueue:           "ocr-tasks",
	})
	goCtx := workflow.WithActivityOptions(ctx, workflow.ActivityOptions{
		StartToCloseTimeout: time.Minute,
	})

	var extracted DocumentHeaderExtraction
	if err := workflow.ExecuteActivity(ocrCtx, "ExtractDocumentHeader", input.S3URI).Get(ocrCtx, &extracted); err != nil {
		return err
	}

	matchInput := MatchDocumentInput{
		TenantID:   input.TenantID,
		InvoiceID:  input.InvoiceID,
		DocumentID: input.DocumentID,
		Extracted:  extracted,
	}
	return workflow.ExecuteActivity(goCtx, MatchDocumentToInvoiceActivity, matchInput).Get(goCtx, nil)
}
