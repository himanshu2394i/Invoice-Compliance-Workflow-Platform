DELETE FROM buyer_document_requirements
WHERE document_type IN (
    'GRN_SEAL',
    'SECURITY_INWARD_STAMP',
    'STOCK_RECEIVING_ACK'
);

UPDATE users SET role = 'MANAGER' WHERE role = 'REVIEWER';

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users
    ADD CONSTRAINT users_role_check
    CHECK (role IN ('ADMIN', 'WORKER', 'MANAGER', 'FINANCE'));
