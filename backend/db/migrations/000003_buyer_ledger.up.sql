-- Adds the buyer-side ledger model needed for Meridian's actual workflow:
-- Meridian's `entities` ISSUE invoices to outside buyers, which is the
-- opposite direction from `vendors` (an AP-style external supplier billing
-- the tenant). Rather than repoint/rename `vendors` in place -- it's
-- referenced as NOT NULL throughout internal/api and internal/db -- this
-- migration is purely additive: a new `buyers` table, a new nullable
-- `buyer_id` column on `invoices`, and the exception-tracking tables for the
-- three reconciliation alerts (missing invoice, missing document, mismatched
-- document). Nothing existing is altered or dropped.

-- 9. Buyers (who an invoice is issued TO). Identified by GSTIN, never by name
-- alone: the source ledger has confirmed cases of unrelated companies with
-- near-identical names ("Vishal Mega Mart" vs "Value Mart" vs "V-Mart Retail
-- Limited"), and at least one invoice where the billed-to name and the
-- receiving stamp's name didn't match. GSTIN is the only reliable join key.
CREATE TABLE IF NOT EXISTS buyers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    gstin VARCHAR(15) NOT NULL,
    address JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_buyer_gstin UNIQUE (organization_id, gstin)
);
CREATE INDEX IF NOT EXISTS idx_buyers_organization ON buyers(organization_id);

-- 10. Issuer-side buyer link on invoices. Nullable and additive -- the
-- existing AP-direction `vendor_id` (NOT NULL) is left exactly as-is so the
-- current approve/reject workflow keeps working unchanged.
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS buyer_id UUID REFERENCES buyers(id);
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS invoice_series VARCHAR(20);
CREATE INDEX IF NOT EXISTS idx_invoices_buyer ON invoices(buyer_id);

-- 11. Open exceptions raised against a real, on-file invoice: a missing
-- supporting document, or a supporting document that doesn't match the
-- invoice it was filed under. A separate table rather than a status column
-- because more than one exception type can be open on the same invoice at
-- once, and resolution history (when/whether it was cleared) matters for an
-- owner reviewing what happened, not just the current state.
CREATE TABLE IF NOT EXISTS invoice_exceptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL,
    exception_type VARCHAR(50) NOT NULL CHECK (exception_type IN ('missing_document', 'document_mismatch')),
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    status VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved', 'not_applicable')),
    raised_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_invoice_exceptions_invoice ON invoice_exceptions(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_exceptions_status ON invoice_exceptions(organization_id, status);

-- 12. Missing invoice numbers: gaps detected in an entity+series numbering
-- sequence. Deliberately does NOT reference invoices.id -- by definition the
-- invoice row doesn't exist; this table records the absence itself, so it
-- can be reviewed and marked resolved (filed late) or not_applicable (that
-- number was simply never issued to this entity) independently.
CREATE TABLE IF NOT EXISTS missing_invoice_numbers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    entity_id UUID NOT NULL,
    invoice_series VARCHAR(20) NOT NULL,
    missing_number VARCHAR(100) NOT NULL,
    detected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved', 'not_applicable')),
    resolved_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_missing_invoice_number UNIQUE (organization_id, entity_id, invoice_series, missing_number)
);
CREATE INDEX IF NOT EXISTS idx_missing_invoice_numbers_status ON missing_invoice_numbers(organization_id, status);

-- RLS, same pattern as every other tenant-scoped table.
ALTER TABLE buyers ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE missing_invoice_numbers ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_buyers_policy ON buyers
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

CREATE POLICY tenant_invoice_exceptions_policy ON invoice_exceptions
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

CREATE POLICY tenant_missing_invoice_numbers_policy ON missing_invoice_numbers
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

GRANT SELECT, INSERT, UPDATE, DELETE ON buyers TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON invoice_exceptions TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON missing_invoice_numbers TO app_user;
