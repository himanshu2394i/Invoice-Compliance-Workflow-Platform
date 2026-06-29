-- The mobile ledger-upload flow retries on any network failure during sync
-- (see mobile/lib/features/capture/sync_service.dart). Without a server-side
-- constraint, a retry that re-sends the same bundle after a timeout (where
-- the first request actually succeeded) creates a second invoice row for
-- the same paper invoice. This constraint makes handleUploadLedgerInvoice's
-- create-or-reuse logic safe even if local device state (remoteInvoiceId)
-- is lost, e.g. after an app reinstall.
--
-- invoice_date must be part of the key because invoices is partitioned by
-- range on that column and Postgres requires the partition key in any
-- unique constraint on a partitioned table.
ALTER TABLE invoices
    ADD CONSTRAINT uq_invoice_ledger_dedup UNIQUE (organization_id, entity_id, invoice_number, invoice_date);
