-- Gate Entry Metadata: structured data from Gate Entry Notes issued by buyers.
-- A gate entry records actual quantities accepted at the buyer's receiving dock.
-- Short receipt (accepted < invoiced) creates a financial exposure that requires
-- owner action — either a credit note or a claim against the buyer.
CREATE TABLE IF NOT EXISTS gate_entry_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL,
    gate_entry_number VARCHAR(100),
    gate_entry_date DATE,
    accepted_qty NUMERIC(15,4),
    invoice_qty NUMERIC(15,4),
    discrepancy_amount NUMERIC(15,4),
    is_short_receipt BOOLEAN NOT NULL DEFAULT false,
    notes TEXT,
    entered_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_gate_entry_document UNIQUE (document_id)
);
CREATE INDEX IF NOT EXISTS idx_gate_entry_invoice ON gate_entry_metadata(invoice_id);
ALTER TABLE gate_entry_metadata ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_gate_entry_metadata_policy ON gate_entry_metadata
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON gate_entry_metadata TO app_user;

-- Invoice Disputes: credit note requests, short receipt claims, tax errors.
-- Raised by workers or reviewers; the owner reviews and resolves each one.
-- Keeping disputes separate from invoice_exceptions (which are system-detected
-- anomalies from OCR/workflow) avoids confusion: disputes are human-initiated,
-- exceptions are machine-raised.
CREATE TABLE IF NOT EXISTS invoice_disputes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL,
    dispute_type VARCHAR(50) NOT NULL CHECK (
        dispute_type IN (
            'SHORT_RECEIPT', 'CREDIT_NOTE_REQUESTED', 'ARITHMETIC_ERROR',
            'MISSING_PAGE', 'TAX_STRUCTURE_ERROR', 'OTHER'
        )
    ),
    description TEXT NOT NULL DEFAULT '',
    raised_by UUID REFERENCES users(id),
    status VARCHAR(30) NOT NULL DEFAULT 'OPEN' CHECK (
        status IN ('OPEN', 'OWNER_REVIEWING', 'RESOLVED', 'REJECTED')
    ),
    resolution_notes TEXT,
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,
    credit_note_document_id UUID REFERENCES documents(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_invoice_disputes_invoice ON invoice_disputes(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_disputes_status ON invoice_disputes(organization_id, status);
ALTER TABLE invoice_disputes ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_invoice_disputes_policy ON invoice_disputes
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON invoice_disputes TO app_user;
