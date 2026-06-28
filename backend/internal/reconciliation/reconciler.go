// reconciler.go
package reconciliation

import (
	"context"
	"log"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/himanshu2394i/invoice-saas/internal/workflow"
	"go.temporal.io/sdk/client"
)

// stuckStates mirrors the transient (non-terminal) states in
// internal/workflow/workflows.go. An invoice sitting in one of these for too
// long either means its workflow died, or is legitimately still waiting on a
// slow human approval -- DescribeWorkflowExecution below tells us which.
var stuckStates = []string{"INGESTED", "VALIDATING", "PENDING_MANAGER_APPROVAL", "PENDING_FINANCE_APPROVAL"}

const invoiceTaskQueue = "invoice-task-queue"

type Reconciler struct {
	Repo           *db.Repository
	TemporalClient client.Client
}

func NewReconciler(repo *db.Repository, tempClient client.Client) *Reconciler {
	return &Reconciler{
		Repo:           repo,
		TemporalClient: tempClient,
	}
}

// ReconcileOrphanedWorkflows scans every tenant for invoices stuck in a
// transient state and restarts the Temporal workflow if it's no longer running.
// Runs per-tenant deliberately rather than with one global query, so RLS keeps
// enforcing tenant isolation even for this background job (see
// backend/db/migrations/000001_initial_schema.up.sql / the
// app_user role -- nothing in this codebase should ever query with RLS bypassed).
func (r *Reconciler) ReconcileOrphanedWorkflows(ctx context.Context) {
	orgs, err := r.Repo.ListOrganizations(ctx)
	if err != nil {
		log.Printf("[RECONCILE ERROR] Failed to list organizations: %v", err)
		return
	}

	cutoff := time.Now().Add(-2 * time.Hour)
	for _, org := range orgs {
		stuck, err := r.Repo.ListStuckInvoices(ctx, org.ID, stuckStates, cutoff)
		if err != nil {
			log.Printf("[RECONCILE ERROR] org %s: failed to fetch stuck invoices: %v", org.ID, err)
			continue
		}
		for _, inv := range stuck {
			r.reconcileOne(ctx, org.ID, inv)
		}
	}
}

func (r *Reconciler) reconcileOne(ctx context.Context, tenantID string, inv db.StuckInvoice) {
	workflowID := "tenant-" + tenantID + "-invoice-" + inv.ID

	desc, err := r.TemporalClient.DescribeWorkflowExecution(ctx, workflowID, "")
	if err == nil {
		log.Printf("[RECONCILE INFO] Invoice %s is healthy. Temporal state is %s", inv.InvoiceNumber, desc.WorkflowExecutionInfo.Status.String())
		return
	}

	log.Printf("[RECONCILE ALERT] Invoice %s is in state %s but missing from Temporal. Restarting workflow...", inv.InvoiceNumber, inv.State)

	s3Key, _ := r.Repo.GetLatestDocumentS3Key(ctx, tenantID, inv.ID)

	options := client.StartWorkflowOptions{
		ID:        workflowID,
		TaskQueue: invoiceTaskQueue,
	}
	input := workflow.InvoiceProcessInput{
		InvoiceID: inv.ID,
		TenantID:  tenantID,
		S3URI:     s3Key,
	}

	_, startErr := r.TemporalClient.ExecuteWorkflow(ctx, options, workflow.InvoiceWorkflow, input)
	if startErr != nil {
		log.Printf("[RECONCILE ERROR] Failed to restart workflow for invoice %s: %v", inv.InvoiceNumber, startErr)
	} else {
		log.Printf("[RECONCILE SUCCESS] Bootstrapped workflow instance for invoice %s.", inv.InvoiceNumber)
	}
}
