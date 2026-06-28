package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/himanshu2394i/invoice-saas/internal/ledgerscan"
	"github.com/himanshu2394i/invoice-saas/internal/reconciliation"
	"github.com/himanshu2394i/invoice-saas/internal/workflow"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/worker"
)

const reconcileInterval = 15 * time.Minute
const ledgerScanInterval = 1 * time.Hour

// databaseURL resolves the Postgres DSN from the environment, defaulting to
// the restricted app_user role rather than the 'admin' superuser (see
// backend/db/migrations/000001_initial_schema.up.sql -- superusers always
// bypass Row-Level Security).
func databaseURL() string {
	if v := os.Getenv("DATABASE_URL"); v != "" {
		return v
	}
	return "postgres://app_user:app_user_dev_password@127.0.0.1:5432/invoice_saas"
}

func main() {
	// Fail fast on a missing/invalid encryption key before connecting to
	// anything else -- a misconfigured production deploy should never start
	// processing workflows that touch vendor bank_details.
	db.ValidateEncryptionConfig()

	// Create the client object just once per process
	c, err := client.Dial(client.Options{
		HostPort: "127.0.0.1:7233",
	})
	if err != nil {
		log.Fatalln("Unable to create Temporal client", err)
	}
	defer c.Close()

	// The worker needs its own DB connection so UpdateInvoiceStateActivity and
	// LogAuditEventActivity can persist real workflow progress.
	pool, err := pgxpool.New(context.Background(), databaseURL())
	if err != nil {
		log.Fatalln("Unable to connect to PostgreSQL", err)
	}
	defer pool.Close()
	workflow.Repo = db.NewRepository(pool)

	// This worker hosts both Workflow and Activity functions
	w := worker.New(c, "invoice-task-queue", worker.Options{})

	w.RegisterWorkflow(workflow.InvoiceWorkflow)
	w.RegisterActivity(workflow.ExtractInvoiceDataActivity)
	w.RegisterActivity(workflow.ValidateInvoiceActivity)
	w.RegisterActivity(workflow.UpdateInvoiceStateActivity)
	w.RegisterActivity(workflow.LogAuditEventActivity)
	w.RegisterActivity(workflow.FetchTenantRulesActivity)

	// Ledger document-matching pipeline (see ledger_workflow.go/ledger_activities.go) --
	// hosted by the same worker process/task queue, sharing infra with the AP
	// approve/reject pipeline above rather than standing up a second worker.
	w.RegisterWorkflow(workflow.LedgerDocumentWorkflow)
	w.RegisterActivity(workflow.MatchDocumentToInvoiceActivity)

	reconciler := reconciliation.NewReconciler(workflow.Repo, c)
	go runReconciliationLoop(reconciler)

	scanner := ledgerscan.NewScanner(workflow.Repo)
	go runLedgerScanLoop(scanner)

	// Start listening to the Task Queue
	log.Println("Starting Temporal Worker for Invoice SaaS...")
	err = w.Run(worker.InterruptCh())
	if err != nil {
		log.Fatalln("Unable to start Worker", err)
	}
}

// runReconciliationLoop periodically restarts any workflow that's gone missing
// while an invoice is still sitting in a transient state. Runs once immediately
// at startup (covers anything orphaned by the worker process being down) and
// then every reconcileInterval.
func runReconciliationLoop(r *reconciliation.Reconciler) {
	ctx := context.Background()
	r.ReconcileOrphanedWorkflows(ctx)

	ticker := time.NewTicker(reconcileInterval)
	defer ticker.Stop()
	for range ticker.C {
		r.ReconcileOrphanedWorkflows(ctx)
	}
}

// runLedgerScanLoop periodically runs the missing-document and
// missing-invoice-number checks (internal/ledgerscan). Same pattern as
// runReconciliationLoop: run once immediately at startup, then on a ticker.
func runLedgerScanLoop(s *ledgerscan.Scanner) {
	ctx := context.Background()
	s.ScanAllTenants(ctx)

	ticker := time.NewTicker(ledgerScanInterval)
	defer ticker.Stop()
	for range ticker.C {
		s.ScanAllTenants(ctx)
	}
}
