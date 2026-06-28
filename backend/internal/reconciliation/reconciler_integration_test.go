// reconciler_integration_test.go
package reconciliation

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.temporal.io/sdk/client"
)

func testDatabaseURL() string {
	if v := os.Getenv("TEST_DATABASE_URL"); v != "" {
		return v
	}
	return "postgres://app_user:app_user_dev_password@127.0.0.1:5432/invoice_saas"
}

func testTemporalHostPort() string {
	if v := os.Getenv("TEST_TEMPORAL_HOSTPORT"); v != "" {
		return v
	}
	return "127.0.0.1:7233"
}

// TestReconcileOrphanedWorkflows_RestartsAWorkflowMissingFromTemporal proves
// the reconciler correctly identifies an invoice stuck in a transient state
// with no matching Temporal execution, and restarts it using the right
// workflow ID ("tenant-<org>-invoice-<id>") and task queue
// ("invoice-task-queue") -- the exact two fields a previous bug got wrong.
func TestReconcileOrphanedWorkflows_RestartsAWorkflowMissingFromTemporal(t *testing.T) {
	ctx := context.Background()

	pool, err := pgxpool.New(ctx, testDatabaseURL())
	if err != nil {
		t.Fatalf("connect to postgres: %v", err)
	}
	defer pool.Close()
	repo := db.NewRepository(pool)

	temporalClient, err := client.Dial(client.Options{HostPort: testTemporalHostPort()})
	if err != nil {
		t.Fatalf("connect to temporal: %v", err)
	}
	defer temporalClient.Close()

	org, err := repo.CreateOrganization(ctx, "Reconciler Test Org")
	if err != nil {
		t.Fatalf("create organization: %v", err)
	}
	entity, err := repo.CreateEntity(ctx, org.ID, "Test Entity", "06AAAAA0003A1Z3",
		[]byte(`{"city":"Gurgaon"}`))
	if err != nil {
		t.Fatalf("create entity: %v", err)
	}

	invoice := &db.Invoice{
		EntityID:      entity.ID,
		VendorID:      entity.ID,
		InvoiceNumber: "RECONCILE-TEST-001",
		InvoiceDate:   time.Now(),
		GrossAmount:   10913.00,
		TaxAmount:     519.66,
		Currency:      "INR",
	}
	if err := repo.CreateInvoice(ctx, org.ID, invoice); err != nil {
		t.Fatalf("create invoice: %v", err)
	}
	// Force it into a "stuck" state -- no Temporal workflow was ever started
	// for this invoice ID, simulating a workflow that died or never launched.
	if err := repo.UpdateInvoiceState(ctx, org.ID, invoice.ID, "PENDING_MANAGER_APPROVAL"); err != nil {
		t.Fatalf("force invoice into stuck state: %v", err)
	}
	// ListStuckInvoices filters on updated_at < cutoff; backdate it directly.
	// invoices is RLS-protected (policy: organization_id = current_setting
	// ('app.current_tenant_id')), so a raw pool.Exec with no tenant context
	// set silently matches zero rows instead of erroring -- set the tenant
	// context in the same transaction as the UPDATE, the same way
	// Repository.WithTx does it for every other tenant-scoped query.
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin backdate tx: %v", err)
	}
	if _, err := tx.Exec(ctx, "SELECT set_config('app.current_tenant_id', $1, true)", org.ID); err != nil {
		t.Fatalf("set tenant context for backdate: %v", err)
	}
	tag, err := tx.Exec(ctx,
		"UPDATE invoices SET updated_at = NOW() - INTERVAL '3 hours' WHERE id = $1", invoice.ID)
	if err != nil {
		t.Fatalf("backdate updated_at: %v", err)
	}
	if tag.RowsAffected() != 1 {
		t.Fatalf("expected backdate to affect 1 row, affected %d", tag.RowsAffected())
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatalf("commit backdate tx: %v", err)
	}

	expectedWorkflowID := "tenant-" + org.ID + "-invoice-" + invoice.ID
	if _, err := temporalClient.DescribeWorkflowExecution(ctx, expectedWorkflowID, ""); err == nil {
		t.Fatal("expected no workflow execution to exist yet for this invoice")
	}

	r := NewReconciler(repo, temporalClient)
	r.ReconcileOrphanedWorkflows(ctx)

	desc, err := temporalClient.DescribeWorkflowExecution(ctx, expectedWorkflowID, "")
	if err != nil {
		t.Fatalf("expected reconciler to start workflow %q, but DescribeWorkflowExecution failed: %v", expectedWorkflowID, err)
	}
	if desc.WorkflowExecutionInfo.TaskQueue != "invoice-task-queue" {
		t.Fatalf("expected task queue %q, got %q", "invoice-task-queue", desc.WorkflowExecutionInfo.TaskQueue)
	}
}
