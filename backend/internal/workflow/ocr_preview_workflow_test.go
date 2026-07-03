package workflow

import (
	"context"
	"testing"

	"github.com/himanshu2394i/invoice-saas/internal/validation"
	"github.com/stretchr/testify/mock"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/testsuite"
)

func TestInvoiceOCRPreviewWorkflowReturnsExtractedFields(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	expected := validation.InvoiceData{
		InvoiceNumber: "A260000218",
		VendorGSTIN:   "06AAAAA0003A1Z3",
		BuyerGSTIN:    "06AAAAA0013A1ZD",
		GrossAmount:   10913,
		NetAmount:     10393.45,
		TaxAmount:     519.55,
		Simulated:     false,
		Inconclusive:  false,
	}
	env.RegisterActivityWithOptions(
		func(context.Context, []string) (validation.InvoiceData, error) {
			return validation.InvoiceData{}, nil
		},
		activity.RegisterOptions{Name: "ExtractTextAndLayout"},
	)
	env.OnActivity("ExtractTextAndLayout", mock.Anything, []string{"temp/page-1.jpg", "temp/page-2.jpg"}).Return(expected, nil)

	env.ExecuteWorkflow(InvoiceOCRPreviewWorkflow, []string{"temp/page-1.jpg", "temp/page-2.jpg"})

	if !env.IsWorkflowCompleted() {
		t.Fatal("expected preview workflow to complete")
	}
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("preview workflow returned error: %v", err)
	}
	var actual validation.InvoiceData
	if err := env.GetWorkflowResult(&actual); err != nil {
		t.Fatalf("get workflow result: %v", err)
	}
	if actual.InvoiceNumber != expected.InvoiceNumber || actual.BuyerGSTIN != expected.BuyerGSTIN {
		t.Fatalf("unexpected preview result: %+v", actual)
	}
}
