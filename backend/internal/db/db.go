// db.go
package db

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/himanshu2394i/invoice-saas/internal/security"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// devOnlyBankDetailsDEK is a fixed 32-byte AES-256 key used ONLY when
// BANK_DETAILS_DEK_HEX is not configured. Never rely on this outside local dev --
// production must supply a real per-tenant DEK sourced from KMS envelope encryption.
var devOnlyBankDetailsDEK = []byte("dev-only-32-byte-key-do-not-ship")

func bankDetailsDEK() []byte {
	hexKey := os.Getenv("BANK_DETAILS_DEK_HEX")
	if hexKey == "" {
		failIfProduction("BANK_DETAILS_DEK_HEX is not set")
		log.Println("WARNING: BANK_DETAILS_DEK_HEX not set; using a fixed development-only encryption key. Do not use this in production.")
		return devOnlyBankDetailsDEK
	}
	key, err := hex.DecodeString(hexKey)
	if err != nil || len(key) != 32 {
		failIfProduction("BANK_DETAILS_DEK_HEX is set but invalid (must be 64 hex chars / 32 bytes)")
		log.Println("WARNING: BANK_DETAILS_DEK_HEX is set but invalid (must be 64 hex chars / 32 bytes); falling back to dev key.")
		return devOnlyBankDetailsDEK
	}
	return key
}

// failIfProduction terminates the process if APP_ENV=production, used for
// secrets that must never silently fall back to a guessable dev value.
func failIfProduction(reason string) {
	if os.Getenv("APP_ENV") == "production" {
		log.Fatalf("FATAL: %s. Refusing to start in production with a guessable secret.", reason)
	}
}

// ValidateEncryptionConfig forces the BANK_DETAILS_DEK_HEX check above to run
// immediately. Call this once at process startup (both api and worker link
// this package) so a misconfigured production deploy fails before it binds a
// port or starts processing workflows, instead of on the first vendor read/write.
func ValidateEncryptionConfig() {
	_ = bankDetailsDEK()
}

type Repository struct {
	Pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{Pool: pool}
}

// WithTx wraps execution in a transaction and sets the active tenant RLS context.
func (r *Repository) WithTx(ctx context.Context, tenantID string, fn func(pgx.Tx) error) error {
	tx, err := r.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Set tenant context for PostgreSQL Row-Level Security (RLS).
	// Must use SET LOCAL to isolate this session variable to this transaction only.
	_, err = tx.Exec(ctx, "SELECT set_config('app.current_tenant_id', $1, true)", tenantID)
	if err != nil {
		return fmt.Errorf("failed to set tenant context: %w", err)
	}

	if err := fn(tx); err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// Models
type Organization struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type Entity struct {
	ID             string          `json:"id"`
	OrganizationID string          `json:"organization_id"`
	LegalName      string          `json:"legal_name"`
	TaxIdentifier  string          `json:"tax_identifier"`
	Address        json.RawMessage `json:"address"`
	CreatedAt      time.Time       `json:"created_at"`
}

type Vendor struct {
	ID             string          `json:"id"`
	OrganizationID string          `json:"organization_id"`
	Name           string          `json:"name"`
	TaxIdentifier  string          `json:"tax_identifier"`
	BankDetails    json.RawMessage `json:"bank_details"`
	Status         string          `json:"status"`
	CreatedAt      time.Time       `json:"created_at"`
}

type Invoice struct {
	ID             string    `json:"id"`
	OrganizationID string    `json:"organization_id"`
	EntityID       string    `json:"entity_id"`
	VendorID       string    `json:"vendor_id"`
	BuyerID        *string   `json:"buyer_id,omitempty"`
	InvoiceSeries  *string   `json:"invoice_series,omitempty"`
	InvoiceNumber  string    `json:"invoice_number"`
	InvoiceDate    time.Time `json:"invoice_date"`
	GrossAmount    float64   `json:"gross_amount"`
	TaxAmount      float64   `json:"tax_amount"`
	Currency       string    `json:"currency"`
	CurrentState   string    `json:"current_state"`
	// Distributor-domain fields (migration 000009). All nullable: legacy
	// invoices predate them, and receivables math skips NULL payment_type.
	PrincipalID      *string    `json:"principal_id,omitempty"`
	BuyerBranchID    *string    `json:"buyer_branch_id,omitempty"`
	PaymentType      *string    `json:"payment_type,omitempty"` // CASH | CREDIT
	PaymentTermsDays *int       `json:"payment_terms_days,omitempty"`
	DueDate          *time.Time `json:"due_date,omitempty"`
	Salesman         *string    `json:"salesman,omitempty"`
	Beat             *string    `json:"beat,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

type DuplicateInvoiceMatch struct {
	ID            string    `json:"id"`
	InvoiceNumber string    `json:"invoice_number"`
	BuyerName     *string   `json:"buyer_name,omitempty"`
	InvoiceDate   time.Time `json:"invoice_date"`
	TotalAmount   float64   `json:"total_amount"`
	Status        string    `json:"status"`
}

// Buyer is who an invoice is issued TO -- distinct from Vendor, which models
// an AP-style external supplier billing the tenant. See
// backend/db/migrations/000003_buyer_ledger.up.sql for why this is a separate
// table rather than a repoint of vendors. Identified by GSTIN, never name
// alone (see migration comment for the real-world name-collision cases this
// guards against).
type Buyer struct {
	ID             string          `json:"id"`
	OrganizationID string          `json:"organization_id"`
	Name           string          `json:"name"`
	GSTIN          string          `json:"gstin"`
	Address        json.RawMessage `json:"address"`
	// GT | MT | ECOM | HOSPITALITY | INDUSTRIAL — the sales channel named in
	// Meridian's own systems (confirmed by invoice_extraction.md entry 19).
	SalesChannel            *string   `json:"sales_channel,omitempty"`
	DefaultPaymentTermsDays *int      `json:"default_payment_terms_days,omitempty"`
	CreatedAt               time.Time `json:"created_at"`
}

type Document struct {
	ID             string    `json:"id"`
	OrganizationID string    `json:"organization_id"`
	InvoiceID      string    `json:"invoice_id"`
	DocumentType   string    `json:"document_type"`
	IsPrimary      bool      `json:"is_primary"`
	CreatedAt      time.Time `json:"created_at"`
}

type DocumentVersion struct {
	ID             string          `json:"id"`
	OrganizationID string          `json:"organization_id"`
	DocumentID     string          `json:"document_id"`
	VersionNumber  int             `json:"version_number"`
	S3Key          string          `json:"s3_key"`
	SHA256Hash     string          `json:"sha256_hash"`
	Metadata       json.RawMessage `json:"metadata"`
	CreatedBy      string          `json:"created_by"`
	CreatedAt      time.Time       `json:"created_at"`
}

type AuditEvent struct {
	ID             string          `json:"id"`
	OrganizationID string          `json:"organization_id"`
	InvoiceID      string          `json:"invoice_id"`
	EventType      string          `json:"event_type"`
	ActorID        string          `json:"actor_id"`
	Description    string          `json:"description"`
	Payload        json.RawMessage `json:"payload"`
	PreviousHash   string          `json:"previous_hash"`
	CurrentHash    string          `json:"current_hash"`
	CreatedAt      time.Time       `json:"created_at"`
}

// User is an identity/control-plane record, not tenant data -- the users table
// has no RLS (see backend/db/migrations/000001_initial_schema.up.sql), so
// these queries run unscoped like CreateOrganization.
type User struct {
	ID             string    `json:"id"`
	OrganizationID string    `json:"organization_id"`
	Email          string    `json:"email"`
	PasswordHash   string    `json:"-"`
	FullName       string    `json:"full_name"`
	Role           string    `json:"role"`
	CreatedAt      time.Time `json:"created_at"`
}

func (r *Repository) CreateUser(ctx context.Context, orgID, email, passwordHash, fullName, role string) (*User, error) {
	u := &User{
		ID:             uuid.New().String(),
		OrganizationID: orgID,
		Email:          email,
		PasswordHash:   passwordHash,
		FullName:       fullName,
		Role:           role,
	}
	err := r.Pool.QueryRow(ctx,
		"INSERT INTO users (id, organization_id, email, password_hash, full_name, role) VALUES ($1, $2, $3, $4, $5, $6) RETURNING created_at",
		u.ID, u.OrganizationID, u.Email, u.PasswordHash, u.FullName, u.Role).Scan(&u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return u, nil
}

func (r *Repository) GetUserByEmail(ctx context.Context, email string) (*User, error) {
	var u User
	err := r.Pool.QueryRow(ctx,
		"SELECT id, organization_id, email, password_hash, full_name, role, created_at FROM users WHERE email = $1",
		email).Scan(&u.ID, &u.OrganizationID, &u.Email, &u.PasswordHash, &u.FullName, &u.Role, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (r *Repository) GetUserByID(ctx context.Context, orgID, userID string) (*User, error) {
	var u User
	err := r.Pool.QueryRow(ctx,
		"SELECT id, organization_id, email, password_hash, full_name, role, created_at FROM users WHERE id = $1 AND organization_id = $2",
		userID, orgID).Scan(&u.ID, &u.OrganizationID, &u.Email, &u.PasswordHash, &u.FullName, &u.Role, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (r *Repository) UpdateUserPassword(ctx context.Context, orgID, userID, passwordHash string) error {
	tag, err := r.Pool.Exec(ctx,
		"UPDATE users SET password_hash = $1 WHERE id = $2 AND organization_id = $3",
		passwordHash, userID, orgID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// Global administration functions (not constrained by tenant RLS for creation)
func (r *Repository) CreateOrganization(ctx context.Context, name string) (*Organization, error) {
	org := &Organization{
		ID:     uuid.New().String(),
		Name:   name,
		Status: "ACTIVE",
	}
	err := r.Pool.QueryRow(ctx,
		"INSERT INTO organizations (id, name, status) VALUES ($1, $2, $3) RETURNING created_at",
		org.ID, org.Name, org.Status).Scan(&org.CreatedAt)
	if err != nil {
		return nil, err
	}
	return org, nil
}

// ListOrganizations returns every tenant. Used only by cross-tenant background
// jobs (e.g. the workflow reconciler) -- request-serving code must always be
// scoped to a single tenant via WithTx instead.
func (r *Repository) ListOrganizations(ctx context.Context) ([]*Organization, error) {
	rows, err := r.Pool.Query(ctx, "SELECT id, name, status, created_at FROM organizations")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var orgs []*Organization
	for rows.Next() {
		var o Organization
		if err := rows.Scan(&o.ID, &o.Name, &o.Status, &o.CreatedAt); err != nil {
			return nil, err
		}
		orgs = append(orgs, &o)
	}
	return orgs, nil
}

func (r *Repository) CreateEntity(ctx context.Context, orgID, legalName, taxId string, address []byte) (*Entity, error) {
	ent := &Entity{
		ID:             uuid.New().String(),
		OrganizationID: orgID,
		LegalName:      legalName,
		TaxIdentifier:  taxId,
		Address:        json.RawMessage(address),
	}
	// Organizations bypass RLS since this is administrative, but we set tenant session just in case RLS checks it.
	tx, err := r.Pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	_, _ = tx.Exec(ctx, "SELECT set_config('app.current_tenant_id', $1, true)", orgID)
	err = tx.QueryRow(ctx,
		"INSERT INTO entities (id, organization_id, legal_name, tax_identifier, address) VALUES ($1, $2, $3, $4, $5) RETURNING created_at",
		ent.ID, ent.OrganizationID, ent.LegalName, ent.TaxIdentifier, ent.Address).Scan(&ent.CreatedAt)
	if err != nil {
		return nil, err
	}
	return ent, tx.Commit(ctx)
}

func (r *Repository) CreateVendor(ctx context.Context, orgID, name, taxId string, bankDetails []byte) (*Vendor, error) {
	// Bank details are sensitive PII -- envelope-encrypt before they ever reach the DB.
	ciphertext, err := security.EncryptField(string(bankDetails), bankDetailsDEK())
	if err != nil {
		return nil, fmt.Errorf("failed to encrypt bank details: %w", err)
	}
	encryptedPayload, err := json.Marshal(map[string]string{"ciphertext": ciphertext})
	if err != nil {
		return nil, err
	}

	vend := &Vendor{
		ID:             uuid.New().String(),
		OrganizationID: orgID,
		Name:           name,
		TaxIdentifier:  taxId,
		BankDetails:    json.RawMessage(encryptedPayload),
		Status:         "APPROVED",
	}
	tx, err := r.Pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	_, _ = tx.Exec(ctx, "SELECT set_config('app.current_tenant_id', $1, true)", orgID)
	err = tx.QueryRow(ctx,
		"INSERT INTO vendors (id, organization_id, legal_name, tax_identifier, bank_details, status) VALUES ($1, $2, $3, $4, $5, $6) RETURNING created_at",
		vend.ID, vend.OrganizationID, vend.Name, vend.TaxIdentifier, vend.BankDetails, vend.Status).Scan(&vend.CreatedAt)
	if err != nil {
		return nil, err
	}
	return vend, tx.Commit(ctx)
}

// GetEntityByGSTIN looks up a seller entity by its GST identification number.
func (r *Repository) GetEntityByGSTIN(ctx context.Context, tenantID, gstin string) (*Entity, error) {
	var e Entity
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"SELECT id, organization_id, legal_name, tax_identifier, address, created_at FROM entities WHERE tax_identifier = $1",
			gstin).Scan(&e.ID, &e.OrganizationID, &e.LegalName, &e.TaxIdentifier, &e.Address, &e.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &e, nil
}

func (r *Repository) GetEntityByID(ctx context.Context, tenantID, entityID string) (*Entity, error) {
	var e Entity
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"SELECT id, organization_id, legal_name, tax_identifier, address, created_at FROM entities WHERE id = $1",
			entityID).Scan(&e.ID, &e.OrganizationID, &e.LegalName, &e.TaxIdentifier, &e.Address, &e.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &e, nil
}

// GetFirstEntity returns the tenant's earliest-created entity. Used by lightweight
// ingestion flows (e.g. the worker upload simulator) that don't yet collect a real
// entity selection from the caller.
func (r *Repository) GetFirstEntity(ctx context.Context, tenantID string) (*Entity, error) {
	var ent Entity
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"SELECT id, organization_id, legal_name, tax_identifier, address, created_at FROM entities ORDER BY created_at ASC LIMIT 1").
			Scan(&ent.ID, &ent.OrganizationID, &ent.LegalName, &ent.TaxIdentifier, &ent.Address, &ent.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &ent, nil
}

// CreateBuyer inserts a new buyer for the tenant. Callers should check
// GetBuyerByGSTIN first when a GSTIN is already known -- uq_buyer_gstin will
// reject a duplicate, but a friendlier "use the existing one" flow belongs in
// the API layer, not here.
func (r *Repository) CreateBuyer(ctx context.Context, tenantID, name, gstin string, address []byte) (*Buyer, error) {
	b := &Buyer{
		ID:             uuid.New().String(),
		OrganizationID: tenantID,
		Name:           name,
		GSTIN:          gstin,
		Address:        json.RawMessage(address),
	}
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"INSERT INTO buyers (id, organization_id, name, gstin, address) VALUES ($1, $2, $3, $4, $5) RETURNING created_at",
			b.ID, b.OrganizationID, b.Name, b.GSTIN, b.Address).Scan(&b.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return b, nil
}

// GetBuyerByGSTIN looks up a buyer by its tax identifier, the only reliable
// join key for this entity (see Buyer's doc comment).
func (r *Repository) GetBuyerByGSTIN(ctx context.Context, tenantID, gstin string) (*Buyer, error) {
	var b Buyer
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"SELECT id, organization_id, name, gstin, address, sales_channel, default_payment_terms_days, created_at FROM buyers WHERE gstin = $1",
			gstin).Scan(&b.ID, &b.OrganizationID, &b.Name, &b.GSTIN, &b.Address, &b.SalesChannel, &b.DefaultPaymentTermsDays, &b.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &b, nil
}

func (r *Repository) GetBuyerByID(ctx context.Context, tenantID, buyerID string) (*Buyer, error) {
	var b Buyer
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"SELECT id, organization_id, name, gstin, address, sales_channel, default_payment_terms_days, created_at FROM buyers WHERE id = $1",
			buyerID).Scan(&b.ID, &b.OrganizationID, &b.Name, &b.GSTIN, &b.Address, &b.SalesChannel, &b.DefaultPaymentTermsDays, &b.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &b, nil
}

func (r *Repository) ListBuyers(ctx context.Context, tenantID string) ([]*Buyer, error) {
	var list []*Buyer
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, "SELECT id, organization_id, name, gstin, address, sales_channel, default_payment_terms_days, created_at FROM buyers ORDER BY name ASC")
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var b Buyer
			if err := rows.Scan(&b.ID, &b.OrganizationID, &b.Name, &b.GSTIN, &b.Address, &b.SalesChannel, &b.DefaultPaymentTermsDays, &b.CreatedAt); err != nil {
				return err
			}
			list = append(list, &b)
		}
		return nil
	})
	return list, err
}

// ListEntities returns every legal entity for the tenant (e.g. Meridian's
// three GSTINs) so the upload UI can let a worker pick which one issued a
// given invoice, rather than always defaulting to the first one created.
func (r *Repository) ListEntities(ctx context.Context, tenantID string) ([]*Entity, error) {
	var list []*Entity
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, "SELECT id, organization_id, legal_name, tax_identifier, address, created_at FROM entities ORDER BY legal_name ASC")
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var e Entity
			if err := rows.Scan(&e.ID, &e.OrganizationID, &e.LegalName, &e.TaxIdentifier, &e.Address, &e.CreatedAt); err != nil {
				return err
			}
			list = append(list, &e)
		}
		return nil
	})
	return list, err
}

// GetFirstVendor returns the tenant's earliest-created vendor. See GetFirstEntity.
func (r *Repository) GetFirstVendor(ctx context.Context, tenantID string) (*Vendor, error) {
	var v Vendor
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"SELECT id, organization_id, legal_name, tax_identifier, bank_details, status, created_at FROM vendors ORDER BY created_at ASC LIMIT 1").
			Scan(&v.ID, &v.OrganizationID, &v.Name, &v.TaxIdentifier, &v.BankDetails, &v.Status, &v.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &v, nil
}

// Transaction-scoped Tenant Queries (Enforced by RLS)

func (r *Repository) CreateInvoice(ctx context.Context, tenantID string, inv *Invoice) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		inv.ID = uuid.New().String()
		inv.OrganizationID = tenantID
		inv.CurrentState = "INGESTED"
		err := tx.QueryRow(ctx,
			`INSERT INTO invoices (id, organization_id, entity_id, vendor_id, buyer_id, invoice_series, invoice_number, invoice_date, gross_amount, tax_amount, currency, current_state, principal_id, buyer_branch_id, payment_type, payment_terms_days, due_date, salesman, beat)
			 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19) RETURNING created_at, updated_at`,
			inv.ID, inv.OrganizationID, inv.EntityID, inv.VendorID, inv.BuyerID, inv.InvoiceSeries, inv.InvoiceNumber, inv.InvoiceDate, inv.GrossAmount, inv.TaxAmount, inv.Currency, inv.CurrentState, inv.PrincipalID, inv.BuyerBranchID, inv.PaymentType, inv.PaymentTermsDays, inv.DueDate, inv.Salesman, inv.Beat).
			Scan(&inv.CreatedAt, &inv.UpdatedAt)
		return err
	})
}

const invoiceColumns = "id, organization_id, entity_id, vendor_id, buyer_id, invoice_series, invoice_number, invoice_date, gross_amount, tax_amount, currency, current_state, principal_id, buyer_branch_id, payment_type, payment_terms_days, due_date, salesman, beat, created_at, updated_at"

func scanInvoice(row pgx.Row, inv *Invoice) error {
	return row.Scan(&inv.ID, &inv.OrganizationID, &inv.EntityID, &inv.VendorID, &inv.BuyerID, &inv.InvoiceSeries, &inv.InvoiceNumber, &inv.InvoiceDate, &inv.GrossAmount, &inv.TaxAmount, &inv.Currency, &inv.CurrentState, &inv.PrincipalID, &inv.BuyerBranchID, &inv.PaymentType, &inv.PaymentTermsDays, &inv.DueDate, &inv.Salesman, &inv.Beat, &inv.CreatedAt, &inv.UpdatedAt)
}

func (r *Repository) GetInvoice(ctx context.Context, tenantID, invoiceID string) (*Invoice, error) {
	var inv Invoice
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return scanInvoice(tx.QueryRow(ctx, "SELECT "+invoiceColumns+" FROM invoices WHERE id = $1", invoiceID), &inv)
	})
	if err != nil {
		return nil, err
	}
	return &inv, nil
}

// GetInvoiceByLedgerKey looks up an invoice by the natural key the mobile
// ledger-upload flow retries on (entity + invoice number + invoice date).
// Used to make handleUploadLedgerInvoice idempotent: a retried upload after
// a network timeout — where the first attempt actually succeeded — reuses
// the existing invoice instead of violating uq_invoice_ledger_dedup.
func (r *Repository) GetInvoiceByLedgerKey(ctx context.Context, tenantID, entityID, invoiceNumber string, invoiceDate time.Time) (*Invoice, error) {
	var inv Invoice
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return scanInvoice(tx.QueryRow(ctx,
			"SELECT "+invoiceColumns+" FROM invoices WHERE entity_id = $1 AND invoice_number = $2 AND invoice_date = $3",
			entityID, invoiceNumber, invoiceDate), &inv)
	})
	if err != nil {
		return nil, err
	}
	return &inv, nil
}

// GetInvoiceByNumber looks up an invoice by its business number rather than
// its UUID -- used by the supporting-document upload flow, where the worker
// identifies the invoice by what's printed on the paper, not its internal id.
func (r *Repository) GetInvoiceByNumber(ctx context.Context, tenantID, invoiceNumber string) (*Invoice, error) {
	var inv Invoice
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return scanInvoice(tx.QueryRow(ctx, "SELECT "+invoiceColumns+" FROM invoices WHERE invoice_number = $1 ORDER BY created_at DESC LIMIT 1", invoiceNumber), &inv)
	})
	if err != nil {
		return nil, err
	}
	return &inv, nil
}

func (r *Repository) FindDuplicateInvoice(ctx context.Context, tenantID, invoiceNumber, sellerGSTIN, buyerGSTIN string) (*DuplicateInvoiceMatch, error) {
	var match DuplicateInvoiceMatch
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT i.id, i.invoice_number, b.name, i.invoice_date, i.gross_amount, i.current_state
			FROM invoices i
			JOIN entities e ON e.id = i.entity_id
			LEFT JOIN buyers b ON b.id = i.buyer_id
			WHERE UPPER(i.invoice_number) = UPPER($1)
			  AND UPPER(e.tax_identifier) = UPPER($2)
			  AND ($3 = '' OR UPPER(COALESCE(b.gstin, '')) = UPPER($3))
			ORDER BY i.created_at DESC
			LIMIT 1`,
			strings.TrimSpace(invoiceNumber),
			strings.TrimSpace(sellerGSTIN),
			strings.TrimSpace(buyerGSTIN),
		).Scan(&match.ID, &match.InvoiceNumber, &match.BuyerName, &match.InvoiceDate, &match.TotalAmount, &match.Status)
	})
	if err != nil {
		return nil, err
	}
	return &match, nil
}

// ListInvoices returns at most limit invoices, newest first, skipping the
// first offset rows, optionally filtered to invoice numbers containing
// search (case-insensitive substring -- the owner-facing ledger dashboard's
// "look through invoices when needed" search box). Callers should clamp
// limit themselves (see api.go) -- this method trusts whatever it's given.
func (r *Repository) ListInvoices(ctx context.Context, tenantID string, limit, offset int, search string) ([]*Invoice, error) {
	var list []*Invoice
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		query := "SELECT " + invoiceColumns + " FROM invoices"
		args := []interface{}{}
		if search != "" {
			query += " WHERE invoice_number ILIKE $1"
			args = append(args, "%"+search+"%")
		}
		query += fmt.Sprintf(" ORDER BY created_at DESC LIMIT $%d OFFSET $%d", len(args)+1, len(args)+2)
		args = append(args, limit, offset)

		rows, err := tx.Query(ctx, query, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var inv Invoice
			if err := scanInvoice(rows, &inv); err != nil {
				return err
			}
			list = append(list, &inv)
		}
		return nil
	})
	return list, err
}

// ListInvoicesByEntitySeries returns every invoice for one (entity, series)
// pair, ordered by invoice_number -- the input the missing-invoice-number gap
// scan needs. Unbounded deliberately: gap detection has to see the whole
// sequence, not a page of it.
func (r *Repository) ListInvoicesByEntitySeries(ctx context.Context, tenantID, entityID, invoiceSeries string) ([]*Invoice, error) {
	var list []*Invoice
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			"SELECT "+invoiceColumns+" FROM invoices WHERE entity_id = $1 AND invoice_series = $2",
			entityID, invoiceSeries)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var inv Invoice
			if err := scanInvoice(rows, &inv); err != nil {
				return err
			}
			list = append(list, &inv)
		}
		return nil
	})
	return list, err
}

// ListDistinctEntitySeries returns every (entity_id, invoice_series) pair that
// has at least one invoice on file, for the gap scan to iterate over.
func (r *Repository) ListDistinctEntitySeries(ctx context.Context, tenantID string) ([][2]string, error) {
	var pairs [][2]string
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			"SELECT DISTINCT entity_id, invoice_series FROM invoices WHERE invoice_series IS NOT NULL AND invoice_series != ''")
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var entityID, series string
			if err := rows.Scan(&entityID, &series); err != nil {
				return err
			}
			pairs = append(pairs, [2]string{entityID, series})
		}
		return nil
	})
	return pairs, err
}

// CountDocumentsForInvoice is a cheap existence check for the missing-document
// scan -- it doesn't need the documents themselves, just whether any exist.
func (r *Repository) CountDocumentsForInvoice(ctx context.Context, tenantID, invoiceID string) (int, error) {
	var count int
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, "SELECT count(*) FROM documents WHERE invoice_id = $1", invoiceID).Scan(&count)
	})
	return count, err
}

// ListInvoicesOlderThan returns invoices created before the cutoff, for the
// missing-document grace-period scan. Unbounded like ListInvoicesByEntitySeries
// -- background scans need the full set, not a UI page of it.
func (r *Repository) ListInvoicesOlderThan(ctx context.Context, tenantID string, cutoff time.Time) ([]*Invoice, error) {
	var list []*Invoice
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, "SELECT "+invoiceColumns+" FROM invoices WHERE created_at < $1", cutoff)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var inv Invoice
			if err := scanInvoice(rows, &inv); err != nil {
				return err
			}
			list = append(list, &inv)
		}
		return nil
	})
	return list, err
}

// CountInvoices returns the tenant's total invoice count (optionally
// filtered by the same search as ListInvoices), for pagination metadata.
func (r *Repository) CountInvoices(ctx context.Context, tenantID, search string) (int, error) {
	var count int
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		if search == "" {
			return tx.QueryRow(ctx, "SELECT count(*) FROM invoices").Scan(&count)
		}
		return tx.QueryRow(ctx, "SELECT count(*) FROM invoices WHERE invoice_number ILIKE $1", "%"+search+"%").Scan(&count)
	})
	return count, err
}

// StuckInvoice is a minimal projection used by the workflow reconciler to spot
// invoices that have been sitting in a transient state for too long.
type StuckInvoice struct {
	ID            string
	InvoiceNumber string
	State         string
}

// ListStuckInvoices finds invoices in one of the given states that haven't been
// updated since the cutoff, scoped to a single tenant (RLS-enforced like every
// other tenant query -- callers needing a cross-tenant view must loop over
// ListOrganizations and call this once per tenant, never bypass RLS instead).
func (r *Repository) ListStuckInvoices(ctx context.Context, tenantID string, states []string, updatedBefore time.Time) ([]StuckInvoice, error) {
	var list []StuckInvoice
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			"SELECT id, invoice_number, current_state FROM invoices WHERE current_state = ANY($1) AND updated_at < $2",
			states, updatedBefore)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var si StuckInvoice
			if err := rows.Scan(&si.ID, &si.InvoiceNumber, &si.State); err != nil {
				return err
			}
			list = append(list, si)
		}
		return nil
	})
	return list, err
}

// GetLatestDocumentS3Key returns the most recent document version's storage key
// for an invoice, if any -- used to re-derive the workflow input when restarting
// a lost/orphaned execution.
func (r *Repository) GetLatestDocumentS3Key(ctx context.Context, tenantID, invoiceID string) (string, error) {
	var s3Key string
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT dv.s3_key FROM document_versions dv
			 JOIN documents d ON d.id = dv.document_id
			 WHERE d.invoice_id = $1
			 ORDER BY dv.version_number DESC LIMIT 1`,
			invoiceID).Scan(&s3Key)
	})
	if err != nil {
		return "", err
	}
	return s3Key, nil
}

func (r *Repository) UpdateInvoiceState(ctx context.Context, tenantID, invoiceID, newState string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, "UPDATE invoices SET current_state = $1, updated_at = NOW() WHERE id = $2", newState, invoiceID)
		return err
	})
}

func (r *Repository) CreateDocument(ctx context.Context, tenantID string, doc *Document) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		doc.ID = uuid.New().String()
		doc.OrganizationID = tenantID
		err := tx.QueryRow(ctx,
			"INSERT INTO documents (id, organization_id, invoice_id, document_type, is_primary) VALUES ($1, $2, $3, $4, $5) RETURNING created_at",
			doc.ID, doc.OrganizationID, doc.InvoiceID, doc.DocumentType, doc.IsPrimary).Scan(&doc.CreatedAt)
		return err
	})
}

func (r *Repository) GetDocumentsForInvoice(ctx context.Context, tenantID, invoiceID string) ([]*Document, error) {
	var list []*Document
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, "SELECT id, organization_id, invoice_id, document_type, is_primary, created_at FROM documents WHERE invoice_id = $1", invoiceID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var doc Document
			if err := rows.Scan(&doc.ID, &doc.OrganizationID, &doc.InvoiceID, &doc.DocumentType, &doc.IsPrimary, &doc.CreatedAt); err != nil {
				return err
			}
			list = append(list, &doc)
		}
		return nil
	})
	return list, err
}

func (r *Repository) GetDocument(ctx context.Context, tenantID, documentID string) (*Document, error) {
	var d Document
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"SELECT id, organization_id, invoice_id, document_type, is_primary, created_at FROM documents WHERE id = $1",
			documentID).Scan(&d.ID, &d.OrganizationID, &d.InvoiceID, &d.DocumentType, &d.IsPrimary, &d.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &d, nil
}

func (r *Repository) GetDocumentByInvoiceAndType(ctx context.Context, tenantID, invoiceID, documentType string) (*Document, error) {
	var d Document
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT id, organization_id, invoice_id, document_type, is_primary, created_at
			 FROM documents
			 WHERE invoice_id = $1 AND document_type = $2
			 ORDER BY created_at ASC
			 LIMIT 1`,
			invoiceID, documentType).Scan(&d.ID, &d.OrganizationID, &d.InvoiceID, &d.DocumentType, &d.IsPrimary, &d.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// GetLatestDocumentVersion returns the most recent version row for a specific
// document (not invoice) -- used to serve back the stored file's content.
func (r *Repository) GetLatestDocumentVersion(ctx context.Context, tenantID, documentID string) (*DocumentVersion, error) {
	var ver DocumentVersion
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT id, organization_id, document_id, version_number, s3_key, sha256_hash, metadata, created_by, created_at
			 FROM document_versions WHERE document_id = $1 ORDER BY version_number DESC LIMIT 1`,
			documentID).Scan(&ver.ID, &ver.OrganizationID, &ver.DocumentID, &ver.VersionNumber, &ver.S3Key, &ver.SHA256Hash, &ver.Metadata, &ver.CreatedBy, &ver.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &ver, nil
}

func (r *Repository) GetDocumentVersion(ctx context.Context, tenantID, documentID string, versionNumber int) (*DocumentVersion, error) {
	var ver DocumentVersion
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT id, organization_id, document_id, version_number, s3_key, sha256_hash, metadata, created_by, created_at
			 FROM document_versions WHERE document_id = $1 AND version_number = $2`,
			documentID, versionNumber).Scan(&ver.ID, &ver.OrganizationID, &ver.DocumentID, &ver.VersionNumber, &ver.S3Key, &ver.SHA256Hash, &ver.Metadata, &ver.CreatedBy, &ver.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &ver, nil
}

func (r *Repository) ListDocumentVersions(ctx context.Context, tenantID, documentID string) ([]*DocumentVersion, error) {
	var list []*DocumentVersion
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			`SELECT id, organization_id, document_id, version_number, s3_key, sha256_hash, metadata, created_by, created_at
			 FROM document_versions WHERE document_id = $1 ORDER BY version_number ASC`,
			documentID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var ver DocumentVersion
			if err := rows.Scan(&ver.ID, &ver.OrganizationID, &ver.DocumentID, &ver.VersionNumber, &ver.S3Key, &ver.SHA256Hash, &ver.Metadata, &ver.CreatedBy, &ver.CreatedAt); err != nil {
				return err
			}
			list = append(list, &ver)
		}
		return rows.Err()
	})
	return list, err
}

func (r *Repository) CreateDocumentVersion(ctx context.Context, tenantID string, ver *DocumentVersion) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		ver.ID = uuid.New().String()
		ver.OrganizationID = tenantID
		err := tx.QueryRow(ctx,
			"INSERT INTO document_versions (id, organization_id, document_id, version_number, s3_key, sha256_hash, metadata, created_by) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING created_at",
			ver.ID, ver.OrganizationID, ver.DocumentID, ver.VersionNumber, ver.S3Key, ver.SHA256Hash, ver.Metadata, ver.CreatedBy).Scan(&ver.CreatedAt)
		return err
	})
}

func (r *Repository) AppendDocumentVersion(ctx context.Context, tenantID string, ver *DocumentVersion) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		ver.ID = uuid.New().String()
		ver.OrganizationID = tenantID
		err := tx.QueryRow(ctx,
			`INSERT INTO document_versions
			   (id, organization_id, document_id, version_number, s3_key, sha256_hash, metadata, created_by)
			 VALUES (
			   $1, $2, $3,
			   (SELECT COALESCE(MAX(version_number), 0) + 1 FROM document_versions WHERE document_id = $3),
			   $4, $5, $6, $7
			 )
			 RETURNING version_number, created_at`,
			ver.ID, ver.OrganizationID, ver.DocumentID, ver.S3Key, ver.SHA256Hash, ver.Metadata, ver.CreatedBy).Scan(&ver.VersionNumber, &ver.CreatedAt)
		return err
	})
}

// Immutable Audit Log Implementation
func (r *Repository) WriteAuditLog(ctx context.Context, tenantID, invoiceID, eventType, actorID, description string, payloadMap map[string]interface{}) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		// 1. Fetch the last event's hash for this invoice to link the chain.
		// Genesis placeholder must be exactly 64 hex chars to match a real SHA-256 digest length.
		const genesisHash = "0000000000000000000000000000000000000000000000000000000000000000"
		var prevHash string = genesisHash[:64]
		err := tx.QueryRow(ctx,
			"SELECT current_hash FROM audit_events WHERE invoice_id = $1 ORDER BY created_at DESC LIMIT 1",
			invoiceID).Scan(&prevHash)
		if err != nil && err != pgx.ErrNoRows {
			return err
		}

		payloadBytes, err := json.Marshal(payloadMap)
		if err != nil {
			return err
		}

		// 2. Compute the current block hash: SHA256(prevHash + eventType + payload)
		hashInput := fmt.Sprintf("%s:%s:%s", prevHash, eventType, string(payloadBytes))
		hasher := sha256.New()
		hasher.Write([]byte(hashInput))
		currentHash := hex.EncodeToString(hasher.Sum(nil))

		// 3. Insert the new linked audit event.
		_, err = tx.Exec(ctx,
			`INSERT INTO audit_events (id, organization_id, invoice_id, event_type, actor_id, description, payload, previous_hash, current_hash)
			 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
			uuid.New().String(), tenantID, invoiceID, eventType, actorID, description, payloadBytes, prevHash, currentHash)
		return err
	})
}

func (r *Repository) GetAuditTrail(ctx context.Context, tenantID, invoiceID string) ([]*AuditEvent, error) {
	var list []*AuditEvent
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			"SELECT id, organization_id, invoice_id, event_type, actor_id, description, payload, previous_hash, current_hash, created_at FROM audit_events WHERE invoice_id = $1 ORDER BY created_at ASC",
			invoiceID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var ae AuditEvent
			if err := rows.Scan(&ae.ID, &ae.OrganizationID, &ae.InvoiceID, &ae.EventType, &ae.ActorID, &ae.Description, &ae.Payload, &ae.PreviousHash, &ae.CurrentHash, &ae.CreatedAt); err != nil {
				return err
			}
			list = append(list, &ae)
		}
		return nil
	})
	return list, err
}

// InvoiceException is an open (or resolved) problem raised against a real,
// on-file invoice: a missing supporting document, or a supporting document
// that doesn't match the invoice it was filed under. See
// backend/db/migrations/000003_buyer_ledger.up.sql.
type InvoiceException struct {
	ID             string          `json:"id"`
	OrganizationID string          `json:"organization_id"`
	InvoiceID      string          `json:"invoice_id"`
	ExceptionType  string          `json:"exception_type"`
	Details        json.RawMessage `json:"details"`
	Status         string          `json:"status"`
	RaisedAt       time.Time       `json:"raised_at"`
	ResolvedAt     *time.Time      `json:"resolved_at,omitempty"`
}

// RaiseExceptionIfNotOpen inserts a new open exception for (invoiceID, exceptionType)
// unless one is already open -- batch scans run repeatedly and must be
// idempotent, not pile up duplicate alerts for the same unresolved problem.
func (r *Repository) RaiseExceptionIfNotOpen(ctx context.Context, tenantID, invoiceID, exceptionType string, details []byte) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		var existing int
		err := tx.QueryRow(ctx,
			"SELECT count(*) FROM invoice_exceptions WHERE invoice_id = $1 AND exception_type = $2 AND status = 'open'",
			invoiceID, exceptionType).Scan(&existing)
		if err != nil {
			return err
		}
		if existing > 0 {
			return nil
		}
		_, err = tx.Exec(ctx,
			"INSERT INTO invoice_exceptions (id, organization_id, invoice_id, exception_type, details) VALUES ($1, $2, $3, $4, $5)",
			uuid.New().String(), tenantID, invoiceID, exceptionType, json.RawMessage(details))
		return err
	})
}

func (r *Repository) ListOpenInvoiceExceptions(ctx context.Context, tenantID string) ([]*InvoiceException, error) {
	var list []*InvoiceException
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			"SELECT id, organization_id, invoice_id, exception_type, details, status, raised_at, resolved_at FROM invoice_exceptions WHERE status = 'open' ORDER BY raised_at DESC")
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var e InvoiceException
			if err := rows.Scan(&e.ID, &e.OrganizationID, &e.InvoiceID, &e.ExceptionType, &e.Details, &e.Status, &e.RaisedAt, &e.ResolvedAt); err != nil {
				return err
			}
			list = append(list, &e)
		}
		return nil
	})
	return list, err
}

// ResolveInvoiceException marks an exception resolved or not_applicable --
// the latter exists because an owner reviewing an alert may determine it was
// never a real problem (see the open question in product_brainstorm.md about
// sequence gaps that were never actually issued).
func (r *Repository) ResolveInvoiceException(ctx context.Context, tenantID, exceptionID, status string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			"UPDATE invoice_exceptions SET status = $1, resolved_at = NOW() WHERE id = $2",
			status, exceptionID)
		return err
	})
}

// MissingInvoiceNumber records a gap detected in an entity+series numbering
// sequence -- see CreateInvoiceException's doc comment for why this is a
// separate table that doesn't reference invoices.id.
type MissingInvoiceNumber struct {
	ID             string     `json:"id"`
	OrganizationID string     `json:"organization_id"`
	EntityID       string     `json:"entity_id"`
	InvoiceSeries  string     `json:"invoice_series"`
	MissingNumber  string     `json:"missing_number"`
	DetectedAt     time.Time  `json:"detected_at"`
	Status         string     `json:"status"`
	ResolvedAt     *time.Time `json:"resolved_at,omitempty"`
}

// RaiseMissingInvoiceNumber records a gap, doing nothing if it's already on
// file (uq_missing_invoice_number) -- ON CONFLICT DO NOTHING rather than a
// pre-check, since the unique constraint already makes this safe to call
// every scan cycle.
func (r *Repository) RaiseMissingInvoiceNumber(ctx context.Context, tenantID, entityID, invoiceSeries, missingNumber string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`INSERT INTO missing_invoice_numbers (id, organization_id, entity_id, invoice_series, missing_number)
			 VALUES ($1, $2, $3, $4, $5) ON CONFLICT (organization_id, entity_id, invoice_series, missing_number) DO NOTHING`,
			uuid.New().String(), tenantID, entityID, invoiceSeries, missingNumber)
		return err
	})
}

// ResolveMissingInvoiceNumberIfFiled clears an open gap record once the
// number it names actually shows up on file -- a worker filing a previously
// missing invoice late shouldn't leave a stale alert behind.
func (r *Repository) ResolveMissingInvoiceNumberIfFiled(ctx context.Context, tenantID, entityID, invoiceSeries, missingNumber string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`UPDATE missing_invoice_numbers SET status = 'resolved', resolved_at = NOW()
			 WHERE entity_id = $1 AND invoice_series = $2 AND missing_number = $3 AND status = 'open'`,
			entityID, invoiceSeries, missingNumber)
		return err
	})
}

func (r *Repository) ListOpenMissingInvoiceNumbers(ctx context.Context, tenantID string) ([]*MissingInvoiceNumber, error) {
	var list []*MissingInvoiceNumber
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			"SELECT id, organization_id, entity_id, invoice_series, missing_number, detected_at, status, resolved_at FROM missing_invoice_numbers WHERE status = 'open' ORDER BY detected_at DESC")
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var m MissingInvoiceNumber
			if err := rows.Scan(&m.ID, &m.OrganizationID, &m.EntityID, &m.InvoiceSeries, &m.MissingNumber, &m.DetectedAt, &m.Status, &m.ResolvedAt); err != nil {
				return err
			}
			list = append(list, &m)
		}
		return nil
	})
	return list, err
}

func (r *Repository) ResolveMissingInvoiceNumber(ctx context.Context, tenantID, id, status string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, "UPDATE missing_invoice_numbers SET status = $1, resolved_at = NOW() WHERE id = $2", status, id)
		return err
	})
}

// TenantRule is the persisted form of internal/workflow's TenantRule DSL
// (field/operator/value/action). Kept as a separate struct rather than
// importing the workflow package's type directly: internal/workflow already
// imports internal/db (workflow.Repo is a *db.Repository), so the reverse
// import would be a cycle. The workflow package converts between the two.
type TenantRule struct {
	ID             string    `json:"id"`
	OrganizationID string    `json:"organization_id"`
	Field          string    `json:"field"`
	Operator       string    `json:"operator"`
	Value          float64   `json:"value"`
	Action         string    `json:"action"`
	CreatedAt      time.Time `json:"created_at"`
}

func (r *Repository) CreateTenantRule(ctx context.Context, tenantID, field, operator string, value float64, action string) (*TenantRule, error) {
	rule := &TenantRule{
		ID:             uuid.New().String(),
		OrganizationID: tenantID,
		Field:          field,
		Operator:       operator,
		Value:          value,
		Action:         action,
	}
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			"INSERT INTO tenant_rules (id, organization_id, field, operator, value, action) VALUES ($1, $2, $3, $4, $5, $6) RETURNING created_at",
			rule.ID, rule.OrganizationID, rule.Field, rule.Operator, rule.Value, rule.Action).Scan(&rule.CreatedAt)
	})
	if err != nil {
		return nil, err
	}
	return rule, nil
}

func (r *Repository) ListTenantRules(ctx context.Context, tenantID string) ([]*TenantRule, error) {
	var list []*TenantRule
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			"SELECT id, organization_id, field, operator, value, action, created_at FROM tenant_rules ORDER BY created_at ASC")
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var tr TenantRule
			if err := rows.Scan(&tr.ID, &tr.OrganizationID, &tr.Field, &tr.Operator, &tr.Value, &tr.Action, &tr.CreatedAt); err != nil {
				return err
			}
			list = append(list, &tr)
		}
		return nil
	})
	return list, err
}

func (r *Repository) DeleteTenantRule(ctx context.Context, tenantID, ruleID string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, "DELETE FROM tenant_rules WHERE id = $1", ruleID)
		return err
	})
}

// BuyerDocRequirement is a supporting document type that workers must photograph
// when filing an invoice for a specific buyer. is_buyer_generated=true means the
// buyer produces this document and hands it to the worker (e.g. Vishal Mega Mart's
// Gate Entry/Discrepancy Note); is_buyer_generated=false means the vendor/worker
// must produce and attach the doc.
type BuyerDocRequirement struct {
	ID               string    `json:"id"`
	OrganizationID   string    `json:"organization_id"`
	BuyerID          string    `json:"buyer_id"`
	DocumentType     string    `json:"document_type"`
	Label            string    `json:"label"`
	IsBuyerGenerated bool      `json:"is_buyer_generated"`
	SortOrder        int       `json:"sort_order"`
	CreatedAt        time.Time `json:"created_at"`
}

// ListBuyerDocRequirements returns all required supporting documents for a buyer,
// ordered by sort_order. Returns an empty slice (not an error) when no requirements
// are configured — that just means the primary tax invoice is sufficient.
func (r *Repository) ListBuyerDocRequirements(ctx context.Context, tenantID, buyerID string) ([]*BuyerDocRequirement, error) {
	var results []*BuyerDocRequirement
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			`SELECT id, organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order, created_at
			 FROM buyer_document_requirements
			 WHERE buyer_id = $1
			 ORDER BY sort_order ASC, created_at ASC`,
			buyerID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var req BuyerDocRequirement
			if err := rows.Scan(&req.ID, &req.OrganizationID, &req.BuyerID, &req.DocumentType, &req.Label, &req.IsBuyerGenerated, &req.SortOrder, &req.CreatedAt); err != nil {
				return err
			}
			results = append(results, &req)
		}
		return rows.Err()
	})
	return results, err
}

// UpsertBuyerDocRequirement inserts or updates a document requirement for a buyer.
// Uses ON CONFLICT on the (organization_id, buyer_id, document_type) unique key.
// DeleteBuyerDocRequirement removes one buyer document requirement.
// Idempotent: deleting a requirement that doesn't exist is not an error,
// so retried deletes and stale UIs converge on the same end state.
func (r *Repository) DeleteBuyerDocRequirement(ctx context.Context, tenantID, buyerID, documentType string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			"DELETE FROM buyer_document_requirements WHERE buyer_id = $1 AND document_type = $2",
			buyerID, documentType)
		return err
	})
}

func (r *Repository) UpsertBuyerDocRequirement(ctx context.Context, tenantID string, req *BuyerDocRequirement) error {
	if req.ID == "" {
		req.ID = uuid.New().String()
	}
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`INSERT INTO buyer_document_requirements
			   (id, organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)
			 ON CONFLICT (organization_id, buyer_id, document_type)
			 DO UPDATE SET label = EXCLUDED.label,
			               is_buyer_generated = EXCLUDED.is_buyer_generated,
			               sort_order = EXCLUDED.sort_order`,
			req.ID, tenantID, req.BuyerID, req.DocumentType, req.Label, req.IsBuyerGenerated, req.SortOrder)
		return err
	})
}

// ─── Gate Entry Metadata ─────────────────────────────────────────────────────

type GateEntryMetadata struct {
	ID                string    `json:"id"`
	OrganizationID    string    `json:"organization_id"`
	DocumentID        string    `json:"document_id"`
	InvoiceID         string    `json:"invoice_id"`
	GateEntryNumber   *string   `json:"gate_entry_number"`
	GateEntryDate     *string   `json:"gate_entry_date"` // ISO date string
	AcceptedQty       *float64  `json:"accepted_qty"`
	InvoiceQty        *float64  `json:"invoice_qty"`
	DiscrepancyAmount *float64  `json:"discrepancy_amount"`
	IsShortReceipt    bool      `json:"is_short_receipt"`
	Notes             *string   `json:"notes"`
	EnteredBy         *string   `json:"entered_by"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

func (r *Repository) UpsertGateEntryMetadata(ctx context.Context, tenantID string, m *GateEntryMetadata) error {
	if m.ID == "" {
		m.ID = uuid.New().String()
	}
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO gate_entry_metadata
			  (id, organization_id, document_id, invoice_id, gate_entry_number, gate_entry_date,
			   accepted_qty, invoice_qty, discrepancy_amount, is_short_receipt, notes, entered_by)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
			ON CONFLICT (document_id) DO UPDATE SET
			  gate_entry_number   = EXCLUDED.gate_entry_number,
			  gate_entry_date     = EXCLUDED.gate_entry_date,
			  accepted_qty        = EXCLUDED.accepted_qty,
			  invoice_qty         = EXCLUDED.invoice_qty,
			  discrepancy_amount  = EXCLUDED.discrepancy_amount,
			  is_short_receipt    = EXCLUDED.is_short_receipt,
			  notes               = EXCLUDED.notes,
			  updated_at          = NOW()`,
			m.ID, tenantID, m.DocumentID, m.InvoiceID, m.GateEntryNumber, m.GateEntryDate,
			m.AcceptedQty, m.InvoiceQty, m.DiscrepancyAmount, m.IsShortReceipt, m.Notes, m.EnteredBy)
		return err
	})
}

func (r *Repository) ListGateEntriesByInvoice(ctx context.Context, tenantID, invoiceID string) ([]*GateEntryMetadata, error) {
	var out []*GateEntryMetadata
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, organization_id, document_id, invoice_id, gate_entry_number,
			       gate_entry_date::text, accepted_qty, invoice_qty, discrepancy_amount,
			       is_short_receipt, notes, entered_by::text, created_at, updated_at
			FROM gate_entry_metadata WHERE invoice_id = $1 ORDER BY created_at`, invoiceID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var m GateEntryMetadata
			if err := rows.Scan(&m.ID, &m.OrganizationID, &m.DocumentID, &m.InvoiceID,
				&m.GateEntryNumber, &m.GateEntryDate, &m.AcceptedQty, &m.InvoiceQty,
				&m.DiscrepancyAmount, &m.IsShortReceipt, &m.Notes, &m.EnteredBy,
				&m.CreatedAt, &m.UpdatedAt); err != nil {
				return err
			}
			out = append(out, &m)
		}
		return rows.Err()
	})
	return out, err
}

// ─── Invoice Disputes ─────────────────────────────────────────────────────────

type InvoiceDispute struct {
	ID                   string     `json:"id"`
	OrganizationID       string     `json:"organization_id"`
	InvoiceID            string     `json:"invoice_id"`
	DisputeType          string     `json:"dispute_type"`
	Description          string     `json:"description"`
	RaisedBy             *string    `json:"raised_by"`
	Status               string     `json:"status"`
	ResolutionNotes      *string    `json:"resolution_notes"`
	ResolvedBy           *string    `json:"resolved_by"`
	ResolvedAt           *time.Time `json:"resolved_at"`
	CreditNoteDocumentID *string    `json:"credit_note_document_id"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`
}

func (r *Repository) CreateDispute(ctx context.Context, tenantID string, d *InvoiceDispute) error {
	d.ID = uuid.New().String()
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO invoice_disputes
			  (id, organization_id, invoice_id, dispute_type, description, raised_by, status)
			VALUES ($1,$2,$3,$4,$5,$6,'OPEN')`,
			d.ID, tenantID, d.InvoiceID, d.DisputeType, d.Description, d.RaisedBy)
		return err
	})
}

func (r *Repository) ListDisputes(ctx context.Context, tenantID, status string) ([]*InvoiceDispute, error) {
	var out []*InvoiceDispute
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		query := `SELECT id, organization_id, invoice_id, dispute_type, description,
		                 raised_by::text, status, resolution_notes, resolved_by::text,
		                 resolved_at, credit_note_document_id::text, created_at, updated_at
		          FROM invoice_disputes`
		var args []interface{}
		if status != "" {
			query += ` WHERE status = $1 ORDER BY created_at DESC`
			args = append(args, status)
		} else {
			query += ` ORDER BY created_at DESC`
		}
		rows, err := tx.Query(ctx, query, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var d InvoiceDispute
			if err := rows.Scan(&d.ID, &d.OrganizationID, &d.InvoiceID, &d.DisputeType,
				&d.Description, &d.RaisedBy, &d.Status, &d.ResolutionNotes, &d.ResolvedBy,
				&d.ResolvedAt, &d.CreditNoteDocumentID, &d.CreatedAt, &d.UpdatedAt); err != nil {
				return err
			}
			out = append(out, &d)
		}
		return rows.Err()
	})
	return out, err
}

func (r *Repository) GetDispute(ctx context.Context, tenantID, id string) (*InvoiceDispute, error) {
	var d InvoiceDispute
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT id, organization_id, invoice_id, dispute_type, description,
			       raised_by::text, status, resolution_notes, resolved_by::text,
			       resolved_at, credit_note_document_id::text, created_at, updated_at
			FROM invoice_disputes WHERE id = $1`, id).
			Scan(&d.ID, &d.OrganizationID, &d.InvoiceID, &d.DisputeType, &d.Description,
				&d.RaisedBy, &d.Status, &d.ResolutionNotes, &d.ResolvedBy, &d.ResolvedAt,
				&d.CreditNoteDocumentID, &d.CreatedAt, &d.UpdatedAt)
	})
	if err != nil {
		return nil, err
	}
	return &d, nil
}

func (r *Repository) UpdateDisputeStatus(ctx context.Context, tenantID, id, status, resolvedByID, notes string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		var resolvedBy interface{} = resolvedByID
		if resolvedByID == "" {
			resolvedBy = nil
		}
		var resolvedAt interface{}
		if status == "RESOLVED" || status == "REJECTED" {
			resolvedAt = time.Now()
		}
		_, err := tx.Exec(ctx, `
			UPDATE invoice_disputes SET
			  status = $2, resolution_notes = NULLIF($3,''), resolved_by = $4,
			  resolved_at = $5, updated_at = NOW()
			WHERE id = $1`, id, status, notes, resolvedBy, resolvedAt)
		return err
	})
}

func (r *Repository) SetDisputeCreditNote(ctx context.Context, tenantID, disputeID, documentID string) error {
	return r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`UPDATE invoice_disputes SET credit_note_document_id = $2, updated_at = NOW() WHERE id = $1`,
			disputeID, documentID)
		return err
	})
}

// ─── Alerts ───────────────────────────────────────────────────────────────────
// Surfaces open exceptions and open disputes as a single feed so an
// admin/manager can see what needs attention without having to remember to
// open the dashboard and check both lists separately.

type AlertItem struct {
	Type          string    `json:"type"` // "exception" | "dispute" | "overdue_invoice"
	InvoiceID     string    `json:"invoice_id"`
	InvoiceNumber string    `json:"invoice_number"`
	Subtype       string    `json:"subtype"` // exception_type or dispute_type
	Description   string    `json:"description"`
	RaisedAt      time.Time `json:"raised_at"`
	AgeDays       int       `json:"age_days"`
	Priority      string    `json:"priority"` // "critical" | "warning"
}

// AlertFilter narrows the alert feed. Zero values mean "no filter".
type AlertFilter struct {
	Type       string // exception | dispute | overdue_invoice
	MinAgeDays int
	Limit      int // 0 = server default
	Offset     int
}

func (r *Repository) GetOpenAlerts(ctx context.Context, tenantID string, f AlertFilter) ([]*AlertItem, error) {
	if f.Limit <= 0 || f.Limit > 500 {
		f.Limit = 200
	}
	var out []*AlertItem
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		// age_days counts from when the alert became actionable: raised_at
		// for exceptions, created_at for disputes, due_date for overdue
		// invoices (i.e. days overdue). Priority: critical when an overdue
		// invoice is 30+ days past due or a dispute has sat open 7+ days.
		rows, err := tx.Query(ctx, `
			SELECT type, invoice_id, invoice_number, subtype, description, raised_at,
			       GREATEST(0, CURRENT_DATE - raised_at::date)::int AS age_days,
			       CASE
			         WHEN type = 'overdue_invoice' AND CURRENT_DATE - raised_at::date >= 30 THEN 'critical'
			         WHEN type = 'dispute' AND CURRENT_DATE - raised_at::date >= 7 THEN 'critical'
			         ELSE 'warning'
			       END AS priority
			FROM (
				SELECT 'exception' AS type, e.invoice_id, i.invoice_number, e.exception_type AS subtype, e.details::text AS description, e.raised_at
				FROM invoice_exceptions e JOIN invoices i ON i.id = e.invoice_id
				WHERE e.status = 'open'
				UNION ALL
				SELECT 'dispute', d.invoice_id, i.invoice_number, d.dispute_type, d.description, d.created_at
				FROM invoice_disputes d JOIN invoices i ON i.id = d.invoice_id
				WHERE d.status IN ('OPEN', 'OWNER_REVIEWING')
				UNION ALL
				SELECT 'overdue_invoice', i.id, i.invoice_number, 'OVERDUE_INVOICE',
				       'Payment overdue: balance ' || ROUND((i.gross_amount - COALESCE(p.paid, 0))::numeric, 2)::text ||
				       ' was due ' || i.due_date::text,
				       i.due_date::timestamptz
				FROM invoices i
				LEFT JOIN (SELECT invoice_id, SUM(amount) AS paid FROM invoice_payments GROUP BY invoice_id) p
				  ON p.invoice_id = i.id
				WHERE i.payment_type = 'CREDIT'
				  AND i.due_date IS NOT NULL AND i.due_date < CURRENT_DATE
				  AND i.gross_amount - COALESCE(p.paid, 0) > 0.005
			) alerts
			WHERE ($1 = '' OR type = $1)
			  AND GREATEST(0, CURRENT_DATE - raised_at::date) >= $2
			ORDER BY raised_at DESC
			LIMIT $3 OFFSET $4`, f.Type, f.MinAgeDays, f.Limit, f.Offset)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var a AlertItem
			if err := rows.Scan(&a.Type, &a.InvoiceID, &a.InvoiceNumber, &a.Subtype, &a.Description, &a.RaisedAt, &a.AgeDays, &a.Priority); err != nil {
				return err
			}
			out = append(out, &a)
		}
		return rows.Err()
	})
	return out, err
}

// ─── Owner Dashboard ──────────────────────────────────────────────────────────

type OwnerDashboard struct {
	TotalInvoices  int     `json:"total_invoices"`
	TodayAmount    float64 `json:"today_amount"`
	OpenExceptions int     `json:"open_exceptions"`
	OpenDisputes   int     `json:"open_disputes"`
	PendingReview  int     `json:"pending_review"`
}

func (r *Repository) GetOwnerDashboard(ctx context.Context, tenantID string) (*OwnerDashboard, error) {
	var d OwnerDashboard
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT
			  (SELECT COUNT(*) FROM invoices)::int,
			  COALESCE((SELECT SUM(gross_amount) FROM invoices WHERE DATE(invoice_date) = CURRENT_DATE), 0),
			  (SELECT COUNT(*) FROM invoice_exceptions WHERE status = 'open')::int,
			  (SELECT COUNT(*) FROM invoice_disputes WHERE status IN ('OPEN','OWNER_REVIEWING'))::int,
			  (SELECT COUNT(*) FROM invoices WHERE current_state = 'INGESTED')::int`).
			Scan(&d.TotalInvoices, &d.TodayAmount, &d.OpenExceptions, &d.OpenDisputes, &d.PendingReview)
	})
	return &d, err
}

// ─── Owner Invoice List ───────────────────────────────────────────────────────

type OwnerInvoiceRow struct {
	ID             string    `json:"id"`
	InvoiceNumber  string    `json:"invoice_number"`
	InvoiceDate    time.Time `json:"invoice_date"`
	GrossAmount    float64   `json:"gross_amount"`
	TaxAmount      float64   `json:"tax_amount"`
	CurrentState   string    `json:"current_state"`
	CreatedAt      time.Time `json:"created_at"`
	BuyerName      *string   `json:"buyer_name"`
	BuyerGSTIN     *string   `json:"buyer_gstin"`
	EntityName     *string   `json:"entity_name"`
	OpenExceptions int       `json:"open_exceptions"`
	OpenDisputes   int       `json:"open_disputes"`
	DocumentCount  int       `json:"document_count"`
	// Distributor-domain fields so list/detail rows can show payment status
	// (Open/Paid/Overdue) without a second request. gross_amount is the bill
	// total; PaidAmount sums invoice_payments.
	PaymentType *string    `json:"payment_type,omitempty"`
	DueDate     *time.Time `json:"due_date,omitempty"`
	PaidAmount  float64    `json:"paid_amount"`
}

// OwnerInvoiceFilter narrows the owner invoice list server-side, so search
// works across the whole ledger rather than only the page the app already
// loaded. Zero values mean "no filter".
type OwnerInvoiceFilter struct {
	Query         string // ILIKE match on invoice number, buyer name, buyer GSTIN
	Status        string // exact current_state
	BuyerID       string
	From          *time.Time // invoice_date >=
	To            *time.Time // invoice_date <=
	HasOpenIssues *bool      // true: only invoices with open exceptions/disputes; false: only without
	Limit         int
	Offset        int
}

func (r *Repository) ListInvoicesForOwner(ctx context.Context, tenantID string, f OwnerInvoiceFilter) ([]*OwnerInvoiceRow, error) {
	query := `
		SELECT i.id, i.invoice_number, i.invoice_date, i.gross_amount, i.tax_amount,
		       i.current_state, i.created_at,
		       b.name, b.gstin, e.legal_name,
		       COALESCE(exc.cnt,0)::int, COALESCE(disp.cnt,0)::int, COALESCE(doc.cnt,0)::int,
		       i.payment_type, i.due_date, COALESCE(pay.paid, 0)
		FROM invoices i
		LEFT JOIN buyers b ON b.id = i.buyer_id
		LEFT JOIN entities e ON e.id = i.entity_id
		LEFT JOIN (
		  SELECT invoice_id, COUNT(*) AS cnt FROM invoice_exceptions WHERE status = 'open' GROUP BY invoice_id
		) exc ON exc.invoice_id = i.id
		LEFT JOIN (
		  SELECT invoice_id, COUNT(*) AS cnt FROM invoice_disputes WHERE status IN ('OPEN','OWNER_REVIEWING') GROUP BY invoice_id
		) disp ON disp.invoice_id = i.id
		LEFT JOIN (
		  SELECT invoice_id, COUNT(*) AS cnt FROM documents GROUP BY invoice_id
		) doc ON doc.invoice_id = i.id
		LEFT JOIN (
		  SELECT invoice_id, SUM(amount) AS paid FROM invoice_payments GROUP BY invoice_id
		) pay ON pay.invoice_id = i.id`

	where := []string{}
	args := []interface{}{}
	arg := func(v interface{}) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}
	if f.Query != "" {
		p := arg("%" + f.Query + "%")
		where = append(where, fmt.Sprintf("(i.invoice_number ILIKE %s OR b.name ILIKE %s OR b.gstin ILIKE %s)", p, p, p))
	}
	if f.Status != "" {
		where = append(where, "i.current_state = "+arg(f.Status))
	}
	if f.BuyerID != "" {
		where = append(where, "i.buyer_id = "+arg(f.BuyerID))
	}
	if f.From != nil {
		where = append(where, "i.invoice_date >= "+arg(*f.From))
	}
	if f.To != nil {
		where = append(where, "i.invoice_date <= "+arg(*f.To))
	}
	if f.HasOpenIssues != nil {
		if *f.HasOpenIssues {
			where = append(where, "(COALESCE(exc.cnt,0) + COALESCE(disp.cnt,0)) > 0")
		} else {
			where = append(where, "(COALESCE(exc.cnt,0) + COALESCE(disp.cnt,0)) = 0")
		}
	}
	if len(where) > 0 {
		query += "\n\t\tWHERE " + strings.Join(where, " AND ")
	}
	query += "\n\t\tORDER BY i.created_at DESC\n\t\tLIMIT " + arg(f.Limit) + " OFFSET " + arg(f.Offset)

	var out []*OwnerInvoiceRow
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, query, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var row OwnerInvoiceRow
			if err := rows.Scan(&row.ID, &row.InvoiceNumber, &row.InvoiceDate, &row.GrossAmount,
				&row.TaxAmount, &row.CurrentState, &row.CreatedAt, &row.BuyerName, &row.BuyerGSTIN,
				&row.EntityName, &row.OpenExceptions, &row.OpenDisputes, &row.DocumentCount,
				&row.PaymentType, &row.DueDate, &row.PaidAmount); err != nil {
				return err
			}
			out = append(out, &row)
		}
		return rows.Err()
	})
	return out, err
}

// ─── Invoice Detail (for owner) ───────────────────────────────────────────────

type DocumentRow struct {
	ID           string    `json:"id"`
	DocumentType string    `json:"document_type"`
	IsPrimary    bool      `json:"is_primary"`
	CreatedAt    time.Time `json:"created_at"`
}

type InvoiceDetail struct {
	Invoice    OwnerInvoiceRow      `json:"invoice"`
	Documents  []DocumentRow        `json:"documents"`
	Exceptions []*InvoiceException  `json:"exceptions"`
	Disputes   []*InvoiceDispute    `json:"disputes"`
	GateEntry  []*GateEntryMetadata `json:"gate_entries"`
}

func (r *Repository) GetInvoiceDetail(ctx context.Context, tenantID, invoiceID string) (*InvoiceDetail, error) {
	var detail InvoiceDetail

	// Invoice row
	err := r.WithTx(ctx, tenantID, func(tx pgx.Tx) error {
		inv := &detail.Invoice
		err := tx.QueryRow(ctx, `
			SELECT i.id, i.invoice_number, i.invoice_date, i.gross_amount, i.tax_amount,
			       i.current_state, i.created_at,
			       b.name, b.gstin, e.legal_name,
			       0::int, 0::int, 0::int,
			       i.payment_type, i.due_date, COALESCE(pay.paid, 0)
			FROM invoices i
			LEFT JOIN buyers b ON b.id = i.buyer_id
			LEFT JOIN entities e ON e.id = i.entity_id
			LEFT JOIN (
			  SELECT invoice_id, SUM(amount) AS paid FROM invoice_payments GROUP BY invoice_id
			) pay ON pay.invoice_id = i.id
			WHERE i.id = $1`, invoiceID).
			Scan(&inv.ID, &inv.InvoiceNumber, &inv.InvoiceDate, &inv.GrossAmount,
				&inv.TaxAmount, &inv.CurrentState, &inv.CreatedAt,
				&inv.BuyerName, &inv.BuyerGSTIN, &inv.EntityName,
				&inv.OpenExceptions, &inv.OpenDisputes, &inv.DocumentCount,
				&inv.PaymentType, &inv.DueDate, &inv.PaidAmount)
		if err != nil {
			return err
		}

		// Documents
		docRows, err := tx.Query(ctx, `
			SELECT id, document_type, is_primary, created_at
			FROM documents WHERE invoice_id = $1
			ORDER BY is_primary DESC, document_type, created_at`, invoiceID)
		if err != nil {
			return err
		}
		defer docRows.Close()
		for docRows.Next() {
			var d DocumentRow
			if err := docRows.Scan(&d.ID, &d.DocumentType, &d.IsPrimary, &d.CreatedAt); err != nil {
				return err
			}
			detail.Documents = append(detail.Documents, d)
		}

		// Exceptions
		excRows, err := tx.Query(ctx, `
			SELECT id, organization_id, invoice_id, exception_type, details, status, raised_at, resolved_at
			FROM invoice_exceptions WHERE invoice_id = $1 ORDER BY raised_at DESC`, invoiceID)
		if err != nil {
			return err
		}
		defer excRows.Close()
		for excRows.Next() {
			var e InvoiceException
			if err := excRows.Scan(&e.ID, &e.OrganizationID, &e.InvoiceID, &e.ExceptionType,
				&e.Details, &e.Status, &e.RaisedAt, &e.ResolvedAt); err != nil {
				return err
			}
			detail.Exceptions = append(detail.Exceptions, &e)
		}

		// Disputes
		dispRows, err := tx.Query(ctx, `
			SELECT id, organization_id, invoice_id, dispute_type, description,
			       raised_by::text, status, resolution_notes, resolved_by::text,
			       resolved_at, credit_note_document_id::text, created_at, updated_at
			FROM invoice_disputes WHERE invoice_id = $1 ORDER BY created_at DESC`, invoiceID)
		if err != nil {
			return err
		}
		defer dispRows.Close()
		for dispRows.Next() {
			var d InvoiceDispute
			if err := dispRows.Scan(&d.ID, &d.OrganizationID, &d.InvoiceID, &d.DisputeType,
				&d.Description, &d.RaisedBy, &d.Status, &d.ResolutionNotes, &d.ResolvedBy,
				&d.ResolvedAt, &d.CreditNoteDocumentID, &d.CreatedAt, &d.UpdatedAt); err != nil {
				return err
			}
			detail.Disputes = append(detail.Disputes, &d)
		}

		return nil
	})
	if err != nil {
		return nil, err
	}

	// Gate entry metadata (separate query, may reference doc IDs from above)
	gateEntries, err := r.ListGateEntriesByInvoice(ctx, tenantID, invoiceID)
	if err == nil {
		detail.GateEntry = gateEntries
	}

	return &detail, nil
}
