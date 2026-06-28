// Package ledgerscan implements the two periodic checks the digital ledger
// needs that can't run at upload time: "has this invoice sat too long with
// no supporting document attached" and "is there a gap in this entity's
// invoice-number sequence that nothing was ever filed for." Both write into
// the exception tables added by
// backend/db/migrations/000003_buyer_ledger.up.sql.
package ledgerscan

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"regexp"
	"sort"
	"strconv"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/db"
)

// DocumentGracePeriod is how long an invoice can sit with zero supporting
// documents attached before it's flagged. A var (not a const) so tests can
// shrink it instead of waiting on a real clock.
var DocumentGracePeriod = 7 * 24 * time.Hour

type Scanner struct {
	Repo *db.Repository
}

func NewScanner(repo *db.Repository) *Scanner {
	return &Scanner{Repo: repo}
}

// ScanAllTenants runs both checks for every organization. Mirrors
// internal/reconciliation's per-tenant loop so RLS keeps enforcing isolation
// even for this background job -- nothing here queries with RLS bypassed.
func (s *Scanner) ScanAllTenants(ctx context.Context) {
	orgs, err := s.Repo.ListOrganizations(ctx)
	if err != nil {
		log.Printf("[LEDGERSCAN ERROR] failed to list organizations: %v", err)
		return
	}
	for _, org := range orgs {
		s.scanMissingDocuments(ctx, org.ID)
		s.scanMissingInvoiceNumbers(ctx, org.ID)
	}
}

// scanMissingDocuments flags invoices past the grace period that have no
// supporting document attached at all -- only the original primary document
// from ingestion (or nothing), no stamped receipt / Gate Entry Note / GRN
// ever uploaded against them.
func (s *Scanner) scanMissingDocuments(ctx context.Context, tenantID string) {
	cutoff := time.Now().Add(-DocumentGracePeriod)
	invoices, err := s.Repo.ListInvoicesOlderThan(ctx, tenantID, cutoff)
	if err != nil {
		log.Printf("[LEDGERSCAN ERROR] org %s: failed to list invoices: %v", tenantID, err)
		return
	}
	for _, inv := range invoices {
		docs, err := s.Repo.GetDocumentsForInvoice(ctx, tenantID, inv.ID)
		if err != nil {
			log.Printf("[LEDGERSCAN ERROR] org %s invoice %s: failed to list documents: %v", tenantID, inv.ID, err)
			continue
		}
		hasSupporting := false
		for _, d := range docs {
			if !d.IsPrimary {
				hasSupporting = true
				break
			}
		}
		if hasSupporting {
			continue
		}
		details, _ := json.Marshal(map[string]interface{}{
			"invoice_number": inv.InvoiceNumber,
			"invoice_date":   inv.InvoiceDate,
		})
		if err := s.Repo.RaiseExceptionIfNotOpen(ctx, tenantID, inv.ID, "missing_document", details); err != nil {
			log.Printf("[LEDGERSCAN ERROR] org %s invoice %s: failed to raise missing_document exception: %v", tenantID, inv.ID, err)
		}
	}
}

var trailingDigitsRegex = regexp.MustCompile(`\d+$`)

// splitSequence pulls the trailing numeric run off an invoice number (e.g.
// "A260000218" -> prefix "A26", number 218, width 7; "CAD/15442" -> prefix
// "CAD/", number 15442, width 5) so gaps can be detected purely numerically
// regardless of how each series formats its prefix.
func splitSequence(invoiceNumber string) (prefix string, number int, width int, ok bool) {
	match := trailingDigitsRegex.FindString(invoiceNumber)
	if match == "" {
		return "", 0, 0, false
	}
	n, err := strconv.Atoi(match)
	if err != nil {
		return "", 0, 0, false
	}
	return invoiceNumber[:len(invoiceNumber)-len(match)], n, len(match), true
}

// scanMissingInvoiceNumbers detects numeric gaps within each (entity,
// invoice_series) pair's invoice numbers on file. A gap means a number that,
// going by the surrounding sequence, should exist but was never filed --
// see the open question in product_brainstorm.md about distinguishing "we
// forgot to file it" from "that number was never issued to us"; this scan
// can't tell the difference, which is why missing_invoice_numbers rows are
// reviewable (resolved/not_applicable), not an automatic hard failure.
func (s *Scanner) scanMissingInvoiceNumbers(ctx context.Context, tenantID string) {
	pairs, err := s.Repo.ListDistinctEntitySeries(ctx, tenantID)
	if err != nil {
		log.Printf("[LEDGERSCAN ERROR] org %s: failed to list entity/series pairs: %v", tenantID, err)
		return
	}
	for _, pair := range pairs {
		entityID, series := pair[0], pair[1]
		invoices, err := s.Repo.ListInvoicesByEntitySeries(ctx, tenantID, entityID, series)
		if err != nil {
			log.Printf("[LEDGERSCAN ERROR] org %s entity %s series %s: failed to list invoices: %v", tenantID, entityID, series, err)
			continue
		}

		type seq struct {
			prefix string
			number int
			width  int
		}
		var seqs []seq
		present := map[int]bool{}
		for _, inv := range invoices {
			prefix, n, width, ok := splitSequence(inv.InvoiceNumber)
			if !ok {
				continue
			}
			seqs = append(seqs, seq{prefix, n, width})
			present[n] = true
		}
		// Fewer than 2 numeric data points means there's nothing to compare
		// against yet -- a single invoice in a series isn't evidence of a gap.
		if len(seqs) < 2 {
			continue
		}
		sort.Slice(seqs, func(i, j int) bool { return seqs[i].number < seqs[j].number })
		minN, maxN := seqs[0].number, seqs[len(seqs)-1].number

		for n := minN; n <= maxN; n++ {
			if present[n] {
				continue
			}
			// Reconstruct the textual number using the nearest lower known
			// neighbor's prefix/padding -- a cosmetic best-effort, since the
			// real point is recording which sequence number is missing, not
			// guaranteeing the exact printed format of an invoice that, by
			// definition, isn't on file to check.
			nearest := seqs[0]
			for _, sq := range seqs {
				if sq.number <= n {
					nearest = sq
				}
			}
			missingNumber := fmt.Sprintf("%s%0*d", nearest.prefix, nearest.width, n)
			if err := s.Repo.RaiseMissingInvoiceNumber(ctx, tenantID, entityID, series, missingNumber); err != nil {
				log.Printf("[LEDGERSCAN ERROR] org %s entity %s series %s number %d: failed to raise: %v", tenantID, entityID, series, n, err)
			}
		}

		// Clear any previously-flagged gap that's since been filed (late
		// filing is normal, not a reason to leave a stale alert open).
		for _, inv := range invoices {
			_ = s.Repo.ResolveMissingInvoiceNumberIfFiled(ctx, tenantID, entityID, series, inv.InvoiceNumber)
		}
	}
}
