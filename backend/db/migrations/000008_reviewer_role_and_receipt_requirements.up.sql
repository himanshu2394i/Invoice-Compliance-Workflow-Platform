ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users
    ADD CONSTRAINT users_role_check
    CHECK (role IN ('ADMIN', 'WORKER', 'MANAGER', 'FINANCE', 'REVIEWER'));

-- Buyer receipt-proof requirements observed in invoice_extraction.md and
-- dataset_registry.md. These are buyer-generated receiving proofs that the
-- worker should photograph along with the tax invoice.
INSERT INTO buyer_document_requirements
    (organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order)
SELECT b.organization_id, b.id, 'GATE_ENTRY_NOTE', 'Gate Entry / Discrepancy Note', true, 1
FROM buyers b
WHERE b.gstin = '06AAAAA0013A1ZD'
ON CONFLICT (organization_id, buyer_id, document_type)
DO UPDATE SET label = EXCLUDED.label,
              is_buyer_generated = EXCLUDED.is_buyer_generated,
              sort_order = EXCLUDED.sort_order;

INSERT INTO buyer_document_requirements
    (organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order)
SELECT b.organization_id, b.id, 'GRN_SEAL', 'GRN Seal', true, 1
FROM buyers b
WHERE b.gstin = '06AAAAA0004A1Z4'
ON CONFLICT (organization_id, buyer_id, document_type)
DO UPDATE SET label = EXCLUDED.label,
              is_buyer_generated = EXCLUDED.is_buyer_generated,
              sort_order = EXCLUDED.sort_order;

INSERT INTO buyer_document_requirements
    (organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order)
SELECT b.organization_id, b.id, 'SECURITY_INWARD_STAMP', 'Security Inward Stamp', true, 1
FROM buyers b
WHERE b.gstin = '06AAAAA0009A1Z9'
ON CONFLICT (organization_id, buyer_id, document_type)
DO UPDATE SET label = EXCLUDED.label,
              is_buyer_generated = EXCLUDED.is_buyer_generated,
              sort_order = EXCLUDED.sort_order;

INSERT INTO buyer_document_requirements
    (organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order)
SELECT b.organization_id, b.id, 'STOCK_RECEIVING_ACK', 'BB Stock Receiving Acknowledgement', true, 1
FROM buyers b
WHERE b.gstin = '09AAAAA0018A1ZI'
ON CONFLICT (organization_id, buyer_id, document_type)
DO UPDATE SET label = EXCLUDED.label,
              is_buyer_generated = EXCLUDED.is_buyer_generated,
              sort_order = EXCLUDED.sort_order;

INSERT INTO buyer_document_requirements
    (organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order)
SELECT b.organization_id, b.id, 'GATE_ENTRY_NOTE', 'Gate / Inward Receipt', true, 1
FROM buyers b
WHERE b.gstin = '06AAAAA0014A1ZE'
ON CONFLICT (organization_id, buyer_id, document_type)
DO UPDATE SET label = EXCLUDED.label,
              is_buyer_generated = EXCLUDED.is_buyer_generated,
              sort_order = EXCLUDED.sort_order;

INSERT INTO buyer_document_requirements
    (organization_id, buyer_id, document_type, label, is_buyer_generated, sort_order)
SELECT b.organization_id, b.id, 'GATE_ENTRY_NOTE', 'Gate Entry / Receiving Note', true, 1
FROM buyers b
WHERE b.gstin = '06AAAAA0006A1Z6'
ON CONFLICT (organization_id, buyer_id, document_type)
DO UPDATE SET label = EXCLUDED.label,
              is_buyer_generated = EXCLUDED.is_buyer_generated,
              sort_order = EXCLUDED.sort_order;
