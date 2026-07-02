package db

// Distributor-domain repository: principals, invoice-series registry, buyer
// branches, payments, receivables, and sales reports (migration 000009).
// Split from db.go to keep that file from growing further; same package and
// conventions (WithTx tenant scoping, uuid PKs, RETURNING scans).

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type Principal struct {
	ID             string    `json:"id"`
	OrganizationID string    `json:"organization_id"`
	Name           string    `json:"name"`
	Code           *string   `json:"code,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

func (r *Repository) CreatePrincipal(ctx context.Context, tenantID, name string, code *string) (*Principal, error) {
	p := &Principal{ID: uuid.New().String(), OrganizationID: tenantID, Name: name, Code: code}
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"INSERT INTO principals (id, organization_id, name, code) VALUES ($1, $2, $3, $4) RETURNING created_at",
			p.ID, p.OrganizationID, p.Name, p.Code).Scan(&p.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return p, nil
}

func (r *Repository) ListPrincipals(ctx context.Context, tenantID string) ([]*Principal, error) {
	var list []*Principal
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			"SELECT id, organization_id, name, code, created_at FROM principals ORDER BY name ASC")
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var p Principal
			if err := rows.Scan(&p.ID, &p.OrganizationID, &p.Name, &p.Code, &p.CreatedAt); err != nil {
				return err
			}
			list = append(list, &p)
		}
		return rows.Err()
	})
	return list, err
}

func (r *Repository) DeletePrincipal(ctx context.Context, tenantID, id string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, "DELETE FROM principals WHERE id = $1", id)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return pgx.ErrNoRows
		}
		return nil
	})
}

// SeriesRegistryEntry maps an invoice-number prefix to the issuing entity and
// (loosely) the principal whose portfolio that series covers. principal_id
// stays nullable: the real-world mapping is not one-to-one.
type SeriesRegistryEntry struct {
	ID             string  `json:"id"`
	OrganizationID string  `json:"organization_id"`
	SeriesPrefix   string  `json:"series_prefix"`
	EntityID       *string `json:"entity_id,omitempty"`
	EntityName     *string `json:"entity_name,omitempty"`
	PrincipalID    *string `json:"principal_id,omitempty"`
	PrincipalName  *string `json:"principal_name,omitempty"`
}

func (r *Repository) UpsertSeriesEntry(ctx context.Context, tenantID, prefix string, entityID, principalID *string) (*SeriesRegistryEntry, error) {
	e := &SeriesRegistryEntry{OrganizationID: tenantID, SeriesPrefix: prefix, EntityID: entityID, PrincipalID: principalID}
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			INSERT INTO invoice_series_registry (id, organization_id, series_prefix, entity_id, principal_id)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (organization_id, series_prefix)
			DO UPDATE SET entity_id = EXCLUDED.entity_id, principal_id = EXCLUDED.principal_id
			RETURNING id`,
			uuid.New().String(), tenantID, prefix, entityID, principalID).Scan(&e.ID)
	})
	if err != nil {
		return nil, err
	}
	return e, nil
}

func (r *Repository) ListSeriesRegistry(ctx context.Context, tenantID string) ([]*SeriesRegistryEntry, error) {
	var list []*SeriesRegistryEntry
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT s.id, s.organization_id, s.series_prefix, s.entity_id, e.legal_name, s.principal_id, p.name
			FROM invoice_series_registry s
			LEFT JOIN entities e ON e.id = s.entity_id
			LEFT JOIN principals p ON p.id = s.principal_id
			ORDER BY s.series_prefix ASC`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var e SeriesRegistryEntry
			if err := rows.Scan(&e.ID, &e.OrganizationID, &e.SeriesPrefix, &e.EntityID, &e.EntityName, &e.PrincipalID, &e.PrincipalName); err != nil {
				return err
			}
			list = append(list, &e)
		}
		return rows.Err()
	})
	return list, err
}

func (r *Repository) DeleteSeriesEntry(ctx context.Context, tenantID, id string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, "DELETE FROM invoice_series_registry WHERE id = $1", id)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return pgx.ErrNoRows
		}
		return nil
	})
}

// ResolveSeriesForInvoiceNumber returns the registry entry whose prefix is the
// longest case-insensitive prefix of the given invoice number, or nil when no
// prefix matches. Used at ledger-upload time to stamp principal/series.
func (r *Repository) ResolveSeriesForInvoiceNumber(ctx context.Context, tenantID, invoiceNumber string) (*SeriesRegistryEntry, error) {
	var e SeriesRegistryEntry
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT s.id, s.organization_id, s.series_prefix, s.entity_id, ent.legal_name, s.principal_id, p.name
			FROM invoice_series_registry s
			LEFT JOIN entities ent ON ent.id = s.entity_id
			LEFT JOIN principals p ON p.id = s.principal_id
			WHERE UPPER($1) LIKE UPPER(s.series_prefix) || '%'
			ORDER BY LENGTH(s.series_prefix) DESC
			LIMIT 1`, invoiceNumber).
			Scan(&e.ID, &e.OrganizationID, &e.SeriesPrefix, &e.EntityID, &e.EntityName, &e.PrincipalID, &e.PrincipalName)
	})
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &e, nil
}

type BuyerBranch struct {
	ID              string          `json:"id"`
	OrganizationID  string          `json:"organization_id"`
	BuyerID         string          `json:"buyer_id"`
	Name            string          `json:"name"`
	Code            *string         `json:"code,omitempty"`
	Address         json.RawMessage `json:"address,omitempty"`
	GateEntryPrefix *string         `json:"gate_entry_prefix,omitempty"`
	CreatedAt       time.Time       `json:"created_at"`
}

func (r *Repository) CreateBuyerBranch(ctx context.Context, tenantID string, b *BuyerBranch) error {
	b.ID = uuid.New().String()
	b.OrganizationID = tenantID
	if len(b.Address) == 0 {
		b.Address = json.RawMessage(`{}`)
	}
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			INSERT INTO buyer_branches (id, organization_id, buyer_id, name, code, address, gate_entry_prefix)
			VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING created_at`,
			b.ID, b.OrganizationID, b.BuyerID, b.Name, b.Code, b.Address, b.GateEntryPrefix).Scan(&b.CreatedAt)
	})
}

// ListBuyerBranches returns branches for one buyer, or for every buyer when
// buyerID is empty (the mobile capture flow caches the full list offline).
func (r *Repository) ListBuyerBranches(ctx context.Context, tenantID, buyerID string) ([]*BuyerBranch, error) {
	query := "SELECT id, organization_id, buyer_id, name, code, address, gate_entry_prefix, created_at FROM buyer_branches"
	args := []interface{}{}
	if buyerID != "" {
		query += " WHERE buyer_id = $1"
		args = append(args, buyerID)
	}
	query += " ORDER BY name ASC"

	var list []*BuyerBranch
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, query, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var b BuyerBranch
			if err := rows.Scan(&b.ID, &b.OrganizationID, &b.BuyerID, &b.Name, &b.Code, &b.Address, &b.GateEntryPrefix, &b.CreatedAt); err != nil {
				return err
			}
			list = append(list, &b)
		}
		return rows.Err()
	})
	return list, err
}

func (r *Repository) DeleteBuyerBranch(ctx context.Context, tenantID, id string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, "DELETE FROM buyer_branches WHERE id = $1", id)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return pgx.ErrNoRows
		}
		return nil
	})
}

// UpdateBuyerMeta patches the distributor-domain buyer fields. Nil pointers
// leave the current value untouched (PATCH semantics).
func (r *Repository) UpdateBuyerMeta(ctx context.Context, tenantID, buyerID string, salesChannel *string, defaultTermsDays *int) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE buyers SET
				sales_channel = COALESCE($2, sales_channel),
				default_payment_terms_days = COALESCE($3, default_payment_terms_days)
			WHERE id = $1`, buyerID, salesChannel, defaultTermsDays)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return pgx.ErrNoRows
		}
		return nil
	})
}

type InvoicePayment struct {
	ID             string    `json:"id"`
	OrganizationID string    `json:"organization_id"`
	InvoiceID      string    `json:"invoice_id"`
	Amount         float64   `json:"amount"`
	PaidOn         time.Time `json:"paid_on"`
	Mode           string    `json:"mode"` // CASH | UPI | CHEQUE | NEFT | OTHER
	Reference      *string   `json:"reference,omitempty"`
	Notes          *string   `json:"notes,omitempty"`
	RecordedBy     *string   `json:"recorded_by,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

// ErrPaymentExceedsBalance is returned when a recorded payment would push the
// invoice's paid total past its bill total. Matched by the handler to a 400.
var ErrPaymentExceedsBalance = fmt.Errorf("payment exceeds invoice balance")

// CreatePayment records a (possibly partial) payment after checking, inside
// the same transaction, that it doesn't exceed the remaining balance.
// gross_amount holds the bill total (see handleUploadLedgerInvoice).
func (r *Repository) CreatePayment(ctx context.Context, tenantID string, p *InvoicePayment) error {
	p.ID = uuid.New().String()
	p.OrganizationID = tenantID
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		var total, paid float64
		err := tx.QueryRow(ctx, `
			SELECT i.gross_amount, COALESCE(SUM(pay.amount), 0)
			FROM invoices i
			LEFT JOIN invoice_payments pay ON pay.invoice_id = i.id
			WHERE i.id = $1
			GROUP BY i.gross_amount`, p.InvoiceID).Scan(&total, &paid)
		if err != nil {
			return err
		}
		if p.Amount > total-paid+0.005 {
			return ErrPaymentExceedsBalance
		}
		return tx.QueryRow(ctx, `
			INSERT INTO invoice_payments (id, organization_id, invoice_id, amount, paid_on, mode, reference, notes, recorded_by)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING created_at`,
			p.ID, p.OrganizationID, p.InvoiceID, p.Amount, p.PaidOn, p.Mode, p.Reference, p.Notes, p.RecordedBy).
			Scan(&p.CreatedAt)
	})
}

func (r *Repository) ListPaymentsByInvoice(ctx context.Context, tenantID, invoiceID string) ([]*InvoicePayment, error) {
	var list []*InvoicePayment
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, organization_id, invoice_id, amount, paid_on, mode, reference, notes, recorded_by, created_at
			FROM invoice_payments WHERE invoice_id = $1 ORDER BY paid_on DESC, created_at DESC`, invoiceID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var p InvoicePayment
			if err := rows.Scan(&p.ID, &p.OrganizationID, &p.InvoiceID, &p.Amount, &p.PaidOn, &p.Mode, &p.Reference, &p.Notes, &p.RecordedBy, &p.CreatedAt); err != nil {
				return err
			}
			list = append(list, &p)
		}
		return rows.Err()
	})
	return list, err
}

// HasOpenDisputeForInvoice reports whether the invoice already has a dispute
// in a non-terminal state — used to keep gate-entry auto-disputes idempotent
// (a re-submitted gate entry must not stack a second SHORT_RECEIPT dispute).
func (r *Repository) HasOpenDisputeForInvoice(ctx context.Context, tenantID, invoiceID string) (bool, error) {
	var count int
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"SELECT COUNT(*) FROM invoice_disputes WHERE invoice_id = $1 AND status IN ('OPEN', 'OWNER_REVIEWING')",
			invoiceID).Scan(&count)
	})
	return count > 0, err
}

// BuyerReceivable is one buyer's outstanding credit position with standard
// aging buckets (days past due). Amounts are bill-total minus payments over
// CREDIT invoices only; legacy invoices (payment_type NULL) never count.
type BuyerReceivable struct {
	BuyerID       string  `json:"buyer_id"`
	BuyerName     string  `json:"buyer_name"`
	BuyerGstin    string  `json:"buyer_gstin"`
	Outstanding   float64 `json:"outstanding"`
	Overdue       float64 `json:"overdue"`
	BucketCurrent float64 `json:"bucket_current"`
	Bucket1To30   float64 `json:"bucket_1_30"`
	Bucket31To60  float64 `json:"bucket_31_60"`
	Bucket60Plus  float64 `json:"bucket_60_plus"`
	OpenInvoices  int     `json:"open_invoices"`
}

func (r *Repository) GetReceivablesSummary(ctx context.Context, tenantID string) ([]*BuyerReceivable, error) {
	var list []*BuyerReceivable
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT b.id, b.name, b.gstin,
			  COALESCE(SUM(i.gross_amount - COALESCE(p.paid, 0)), 0) AS outstanding,
			  COALESCE(SUM(CASE WHEN i.due_date IS NOT NULL AND i.due_date < CURRENT_DATE
			      THEN i.gross_amount - COALESCE(p.paid, 0) ELSE 0 END), 0) AS overdue,
			  COALESCE(SUM(CASE WHEN i.due_date IS NULL OR i.due_date >= CURRENT_DATE
			      THEN i.gross_amount - COALESCE(p.paid, 0) ELSE 0 END), 0) AS bucket_current,
			  COALESCE(SUM(CASE WHEN CURRENT_DATE - i.due_date BETWEEN 1 AND 30
			      THEN i.gross_amount - COALESCE(p.paid, 0) ELSE 0 END), 0) AS bucket_1_30,
			  COALESCE(SUM(CASE WHEN CURRENT_DATE - i.due_date BETWEEN 31 AND 60
			      THEN i.gross_amount - COALESCE(p.paid, 0) ELSE 0 END), 0) AS bucket_31_60,
			  COALESCE(SUM(CASE WHEN CURRENT_DATE - i.due_date > 60
			      THEN i.gross_amount - COALESCE(p.paid, 0) ELSE 0 END), 0) AS bucket_60_plus,
			  COUNT(*)::int AS open_invoices
			FROM invoices i
			JOIN buyers b ON b.id = i.buyer_id
			LEFT JOIN (SELECT invoice_id, SUM(amount) AS paid FROM invoice_payments GROUP BY invoice_id) p
			  ON p.invoice_id = i.id
			WHERE i.payment_type = 'CREDIT'
			  AND i.gross_amount - COALESCE(p.paid, 0) > 0.005
			GROUP BY b.id, b.name, b.gstin
			ORDER BY outstanding DESC`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var br BuyerReceivable
			if err := rows.Scan(&br.BuyerID, &br.BuyerName, &br.BuyerGstin, &br.Outstanding, &br.Overdue,
				&br.BucketCurrent, &br.Bucket1To30, &br.Bucket31To60, &br.Bucket60Plus, &br.OpenInvoices); err != nil {
				return err
			}
			list = append(list, &br)
		}
		return rows.Err()
	})
	return list, err
}

type ReceivableInvoice struct {
	InvoiceID     string     `json:"invoice_id"`
	InvoiceNumber string     `json:"invoice_number"`
	InvoiceDate   time.Time  `json:"invoice_date"`
	DueDate       *time.Time `json:"due_date,omitempty"`
	Total         float64    `json:"total"`
	Paid          float64    `json:"paid"`
	Balance       float64    `json:"balance"`
	DaysOverdue   int        `json:"days_overdue"`
}

func (r *Repository) ListReceivableInvoices(ctx context.Context, tenantID, buyerID string) ([]*ReceivableInvoice, error) {
	var list []*ReceivableInvoice
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT i.id, i.invoice_number, i.invoice_date, i.due_date,
			  i.gross_amount, COALESCE(p.paid, 0),
			  i.gross_amount - COALESCE(p.paid, 0),
			  CASE WHEN i.due_date IS NOT NULL AND i.due_date < CURRENT_DATE
			       THEN (CURRENT_DATE - i.due_date)::int ELSE 0 END
			FROM invoices i
			LEFT JOIN (SELECT invoice_id, SUM(amount) AS paid FROM invoice_payments GROUP BY invoice_id) p
			  ON p.invoice_id = i.id
			WHERE i.payment_type = 'CREDIT'
			  AND i.buyer_id = $1
			  AND i.gross_amount - COALESCE(p.paid, 0) > 0.005
			ORDER BY i.due_date ASC NULLS LAST, i.invoice_date ASC`, buyerID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var ri ReceivableInvoice
			if err := rows.Scan(&ri.InvoiceID, &ri.InvoiceNumber, &ri.InvoiceDate, &ri.DueDate,
				&ri.Total, &ri.Paid, &ri.Balance, &ri.DaysOverdue); err != nil {
				return err
			}
			list = append(list, &ri)
		}
		return rows.Err()
	})
	return list, err
}

// SalesReportRow is one grouped aggregate over the invoice ledger. Gross is
// the summed bill total (what "sales" means to the owner), Tax the summed
// GST portion.
type SalesReportRow struct {
	KeyID        string  `json:"key_id"`
	KeyLabel     string  `json:"key_label"`
	InvoiceCount int     `json:"invoice_count"`
	Gross        float64 `json:"gross"`
	Tax          float64 `json:"tax"`
}

// GetSalesReport groups ledger invoices in [from, to] (inclusive, by
// invoice_date) by one of: principal, buyer, channel, entity, salesman.
// Any other groupBy value is rejected — the value is interpolated into SQL,
// so the whitelist is also the injection guard.
func (r *Repository) GetSalesReport(ctx context.Context, tenantID string, from, to time.Time, groupBy string) ([]*SalesReportRow, error) {
	type grouping struct{ keyExpr, labelExpr, join string }
	groupings := map[string]grouping{
		"principal": {"COALESCE(p.id::text, '')", "COALESCE(p.name, 'Unassigned')", "LEFT JOIN principals p ON p.id = i.principal_id"},
		"buyer":     {"COALESCE(b.id::text, '')", "COALESCE(b.name, 'Unassigned')", "LEFT JOIN buyers b ON b.id = i.buyer_id"},
		"channel":   {"COALESCE(b.sales_channel, '')", "COALESCE(b.sales_channel, 'Unassigned')", "LEFT JOIN buyers b ON b.id = i.buyer_id"},
		"entity":    {"COALESCE(e.id::text, '')", "COALESCE(e.legal_name, 'Unassigned')", "LEFT JOIN entities e ON e.id = i.entity_id"},
		"salesman":  {"COALESCE(i.salesman, '')", "COALESCE(i.salesman, 'Unassigned')", ""},
	}
	g, ok := groupings[groupBy]
	if !ok {
		return nil, fmt.Errorf("unsupported group_by %q", groupBy)
	}

	query := fmt.Sprintf(`
		SELECT %s AS key_id, %s AS key_label,
		  COUNT(*)::int, COALESCE(SUM(i.gross_amount), 0), COALESCE(SUM(i.tax_amount), 0)
		FROM invoices i
		%s
		WHERE i.invoice_date BETWEEN $1 AND $2
		GROUP BY 1, 2
		ORDER BY 4 DESC`, g.keyExpr, g.labelExpr, g.join)

	var list []*SalesReportRow
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, query, from, to)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var row SalesReportRow
			if err := rows.Scan(&row.KeyID, &row.KeyLabel, &row.InvoiceCount, &row.Gross, &row.Tax); err != nil {
				return err
			}
			list = append(list, &row)
		}
		return rows.Err()
	})
	return list, err
}
