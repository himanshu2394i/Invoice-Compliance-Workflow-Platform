-- Distributor domain: principals, invoice-series registry, buyer branches,
-- payment terms, and payments. The extraction log (invoice_extraction.md)
-- established that each Meridian entity distributes for multiple principals,
-- each principal gets its own invoice series, buyers operate multiple
-- branches under one GSTIN, and most sales are on CREDIT terms that nothing
-- in the schema could previously express. Everything here is additive;
-- legacy rows keep NULLs and are excluded from receivables math.

CREATE TABLE IF NOT EXISTS principals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_principal_name UNIQUE (organization_id, name)
);
CREATE INDEX IF NOT EXISTS idx_principals_org ON principals(organization_id);

-- Series prefix -> (entity, principal). principal_id is nullable on purpose:
-- the mapping is loose in reality (REHIN covers both Harpic and Mortein;
-- BIB's principal is still unconfirmed). Longest-prefix match wins at
-- ingest time.
CREATE TABLE IF NOT EXISTS invoice_series_registry (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    series_prefix VARCHAR(20) NOT NULL,
    entity_id UUID REFERENCES entities(id),
    principal_id UUID REFERENCES principals(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_series_prefix UNIQUE (organization_id, series_prefix)
);

-- One buyer GSTIN, many physical receiving locations (Vishal Mega Mart
-- stores, Flipkart/Zepto warehouses, Superwell manufacturing units).
CREATE TABLE IF NOT EXISTS buyer_branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    buyer_id UUID NOT NULL REFERENCES buyers(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50),
    address JSONB,
    gate_entry_prefix VARCHAR(20),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_buyer_branch UNIQUE (organization_id, buyer_id, name)
);
CREATE INDEX IF NOT EXISTS idx_buyer_branches_buyer ON buyer_branches(buyer_id);

ALTER TABLE buyers ADD COLUMN IF NOT EXISTS sales_channel VARCHAR(20);
ALTER TABLE buyers DROP CONSTRAINT IF EXISTS buyers_sales_channel_check;
ALTER TABLE buyers ADD CONSTRAINT buyers_sales_channel_check
    CHECK (sales_channel IS NULL OR sales_channel IN ('GT','MT','ECOM','HOSPITALITY','INDUSTRIAL'));
ALTER TABLE buyers ADD COLUMN IF NOT EXISTS default_payment_terms_days INT;

ALTER TABLE invoices ADD COLUMN IF NOT EXISTS principal_id UUID;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS buyer_branch_id UUID;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_type VARCHAR(10);
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_payment_type_check;
ALTER TABLE invoices ADD CONSTRAINT invoices_payment_type_check
    CHECK (payment_type IS NULL OR payment_type IN ('CASH','CREDIT'));
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_terms_days INT;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS salesman VARCHAR(255);
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS beat VARCHAR(255);
CREATE INDEX IF NOT EXISTS idx_invoices_receivable
    ON invoices(organization_id, payment_type, due_date);

CREATE TABLE IF NOT EXISTS invoice_payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL,
    amount NUMERIC(15,4) NOT NULL CHECK (amount > 0),
    paid_on DATE NOT NULL,
    mode VARCHAR(20) NOT NULL CHECK (mode IN ('CASH','UPI','CHEQUE','NEFT','OTHER')),
    reference VARCHAR(255),
    notes TEXT,
    recorded_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_invoice_payments_invoice ON invoice_payments(invoice_id);

ALTER TABLE principals ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_series_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE buyer_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_principals_policy ON principals
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
CREATE POLICY tenant_series_registry_policy ON invoice_series_registry
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
CREATE POLICY tenant_buyer_branches_policy ON buyer_branches
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
CREATE POLICY tenant_invoice_payments_policy ON invoice_payments
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

GRANT SELECT, INSERT, UPDATE, DELETE ON principals TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON invoice_series_registry TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON buyer_branches TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON invoice_payments TO app_user;

-- Seed principals for any org that owns the Meridian Brothers entity (the
-- real pilot org), keyed by GSTIN the same way 000008 seeds requirements.
INSERT INTO principals (organization_id, name, code)
SELECT e.organization_id, p.name, p.code
FROM entities e
CROSS JOIN (VALUES
    ('Mondelez', 'CAD'), ('Nestle', 'DBR'), ('HUL', 'HUL'),
    ('Britannia', 'BRIT'), ('Reckitt', 'RB'), ('Haleon', 'HAL'),
    ('Nivea', 'NIV'), ('HELL Energy', 'HELL'), ('Morde', 'MORDE')
) AS p(name, code)
WHERE e.tax_identifier = '06AAAAA0003A1Z3'
ON CONFLICT (organization_id, name) DO NOTHING;

-- Series mappings confirmed by the extraction log. Entity GSTINs:
-- Meridian Brothers 06AAAAA0003A1Z3, Meridian Distributors 06AAAAA0015A1ZF,
-- Meridian Gurgaon 06AAAAA0017A1ZH.
INSERT INTO invoice_series_registry (organization_id, series_prefix, entity_id, principal_id)
SELECT e.organization_id, m.prefix, e.id, pr.id
FROM (VALUES
    ('CAD',   '06AAAAA0003A1Z3', 'Mondelez'),
    ('DBR',   '06AAAAA0003A1Z3', 'Nestle'),
    ('MORDE', '06AAAAA0003A1Z3', 'Morde'),
    ('A26',   '06AAAAA0003A1Z3', 'Britannia'),
    ('NIV',   '06AAAAA0003A1Z3', 'Nivea'),
    ('GST',   '06AAAAA0015A1ZF', 'HUL'),
    ('HAL',   '06AAAAA0017A1ZH', 'Haleon'),
    ('HELL',  '06AAAAA0017A1ZH', 'HELL Energy'),
    ('HYGIN', '06AAAAA0017A1ZH', 'Reckitt'),
    ('REHIN', '06AAAAA0017A1ZH', 'Reckitt')
) AS m(prefix, gstin, principal_name)
JOIN entities e ON e.tax_identifier = m.gstin
LEFT JOIN principals pr
    ON pr.organization_id = e.organization_id AND pr.name = m.principal_name
ON CONFLICT (organization_id, series_prefix) DO NOTHING;

-- BIB series belongs to Meridian Gurgaon but its principal is unconfirmed
-- (entry [33] contradicted the earlier Bru hypothesis) — leave unmapped.
INSERT INTO invoice_series_registry (organization_id, series_prefix, entity_id, principal_id)
SELECT e.organization_id, 'BIB', e.id, NULL
FROM entities e WHERE e.tax_identifier = '06AAAAA0017A1ZH'
ON CONFLICT (organization_id, series_prefix) DO NOTHING;
