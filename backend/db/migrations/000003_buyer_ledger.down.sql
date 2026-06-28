REVOKE ALL PRIVILEGES ON missing_invoice_numbers FROM app_user;
REVOKE ALL PRIVILEGES ON invoice_exceptions FROM app_user;
REVOKE ALL PRIVILEGES ON buyers FROM app_user;

DROP TABLE IF EXISTS missing_invoice_numbers CASCADE;
DROP TABLE IF EXISTS invoice_exceptions CASCADE;

ALTER TABLE invoices DROP COLUMN IF EXISTS invoice_series;
ALTER TABLE invoices DROP COLUMN IF EXISTS buyer_id;

DROP TABLE IF EXISTS buyers CASCADE;
