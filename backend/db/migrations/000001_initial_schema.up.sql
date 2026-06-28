-- Enable Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Organizations (Tenants)
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'ACTIVE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Entities (Legal entities belonging to a tenant)
CREATE TABLE IF NOT EXISTS entities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    legal_name VARCHAR(255) NOT NULL,
    tax_identifier VARCHAR(15) NOT NULL,
    address JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_entity_gstin UNIQUE (organization_id, tax_identifier)
);

-- 3. Vendors
CREATE TABLE IF NOT EXISTS vendors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    legal_name VARCHAR(255) NOT NULL,
    tax_identifier VARCHAR(15) NOT NULL,
    bank_details JSONB, -- Stores AES-GCM envelope-encrypted ciphertext (hex), not plaintext. See internal/security.
    status VARCHAR(50) DEFAULT 'APPROVED',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_vendor_gstin UNIQUE (organization_id, tax_identifier)
);

-- 4. Invoices
CREATE TABLE IF NOT EXISTS invoices (
    id UUID NOT NULL,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    entity_id UUID NOT NULL,
    vendor_id UUID NOT NULL,
    invoice_number VARCHAR(100) NOT NULL,
    invoice_date DATE NOT NULL,
    gross_amount NUMERIC(15, 4) NOT NULL,
    tax_amount NUMERIC(15, 4) NOT NULL,
    currency CHAR(3) NOT NULL,
    current_state VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, invoice_date)
) PARTITION BY RANGE (invoice_date);

-- Partitions
CREATE TABLE IF NOT EXISTS invoices_y2026m06 PARTITION OF invoices
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE IF NOT EXISTS invoices_y2026m07 PARTITION OF invoices
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE IF NOT EXISTS invoices_default PARTITION OF invoices DEFAULT;

-- 5. Documents (one row per logical document attached to an invoice; immutable versions live in document_versions)
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL,
    document_type VARCHAR(50) NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_documents_invoice ON documents(invoice_id);

-- 6. Document Versions (immutable; every re-upload creates a new row, never overwrites)
CREATE TABLE IF NOT EXISTS document_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    version_number INT NOT NULL,
    s3_key VARCHAR(1024) NOT NULL,
    sha256_hash VARCHAR(64) NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_document_version UNIQUE (document_id, version_number)
);
CREATE INDEX IF NOT EXISTS idx_document_versions_document ON document_versions(document_id);

-- 7. Audit Events (append-only hash chain per invoice)
CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL,
    invoice_id UUID NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    actor_id VARCHAR(100) NOT NULL DEFAULT 'system',
    description TEXT NOT NULL DEFAULT '',
    previous_hash VARCHAR(64) NOT NULL,
    current_hash VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_audit_events_invoice ON audit_events(invoice_id, created_at);

-- 8. Users (identity/control-plane table -- intentionally NOT row-level-secured,
-- same as organizations. A user must be looked up by email alone, before any
-- tenant context is known, to authenticate in the first place. Isolation here
-- comes from the password check, not RLS.)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('ADMIN', 'WORKER', 'MANAGER', 'FINANCE')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_users_organization ON users(organization_id);

-- RLS Configuration
ALTER TABLE entities ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_entities_policy ON entities
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

CREATE POLICY tenant_vendors_policy ON vendors
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

CREATE POLICY tenant_invoices_policy ON invoices
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

CREATE POLICY tenant_documents_policy ON documents
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

CREATE POLICY tenant_document_versions_policy ON document_versions
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

CREATE POLICY tenant_audit_events_policy ON audit_events
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

-- Restricted application role. The Go services connect as THIS role, never as
-- the bootstrap superuser ('admin') -- Postgres always exempts superusers and
-- table owners from their own RLS policies, so connecting as a superuser makes
-- every RLS policy above a silent no-op. app_user owns nothing and has no
-- superuser/bypassrls attribute, so RLS is actually enforced for it.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'app_user_dev_password';
    END IF;
END
$$;

GRANT CONNECT ON DATABASE invoice_saas TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
