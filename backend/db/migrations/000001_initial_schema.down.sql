-- Reverses 000001_initial_schema.up.sql. DROP ... CASCADE handles dependent
-- policies, indexes, and FKs, so explicit ordering beyond "children before
-- parents where CASCADE doesn't already cover it" isn't required.
--
-- Deliberately does NOT DROP ROLE app_user: Postgres roles are cluster-wide,
-- not per-database, so app_user may be granted privileges in other databases
-- on the same cluster. Dropping it here would be a global, irreversible
-- action far outside this migration's blast radius -- only this database's
-- grants are this migration's responsibility to revert.
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM app_user;
REVOKE USAGE ON SCHEMA public FROM app_user;
REVOKE CONNECT ON DATABASE invoice_saas FROM app_user;

DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS audit_events CASCADE;
DROP TABLE IF EXISTS document_versions CASCADE;
DROP TABLE IF EXISTS documents CASCADE;
DROP TABLE IF EXISTS invoices CASCADE;
DROP TABLE IF EXISTS vendors CASCADE;
DROP TABLE IF EXISTS entities CASCADE;
DROP TABLE IF EXISTS organizations CASCADE;
