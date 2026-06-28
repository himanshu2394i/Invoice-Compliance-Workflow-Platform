-- Persists the dynamic rule DSL that internal/workflow/rules.go already knows
-- how to evaluate (TenantRule: field/operator/value/action) but, until now,
-- only ever read from a hardcoded slice in workflows.go.
CREATE TABLE IF NOT EXISTS tenant_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    field VARCHAR(50) NOT NULL,
    operator VARCHAR(5) NOT NULL,
    value NUMERIC(15, 4) NOT NULL,
    action VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_tenant_rules_organization ON tenant_rules(organization_id);

ALTER TABLE tenant_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_rules_policy ON tenant_rules
    USING (organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);

GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_rules TO app_user;
