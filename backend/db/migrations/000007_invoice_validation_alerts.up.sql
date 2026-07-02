ALTER TABLE invoice_exceptions
    DROP CONSTRAINT IF EXISTS invoice_exceptions_exception_type_check;

ALTER TABLE invoice_exceptions
    ADD CONSTRAINT invoice_exceptions_exception_type_check CHECK (
        exception_type IN (
            'missing_document',
            'document_mismatch',
            'ocr_inconclusive',
            'invoice_data_mismatch',
            'validation_failed'
        )
    );
