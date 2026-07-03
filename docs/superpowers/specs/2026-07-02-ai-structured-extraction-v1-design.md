# AI Structured Extraction v1 Design

Date: 2026-07-02

## Goal

Improve OCR reliability by adding a strict AI extraction contract for Meridian
invoice documents. The AI must return machine-usable JSON, not prose. Version 1
focuses on the fields needed for capture autofill, validation, supporting
document matching, alerts, and receivables.

Line-item extraction is intentionally out of scope for v1.

## Founder-Level Promise

The app should not say "AI has read everything perfectly." It should say:

> "AI reads the important invoice fields, fills what it is confident about,
> warns where it is unsure, and asks staff to verify before final submission."

AI is an assistant and verifier. The worker or reviewer remains the final
business authority.

## Scope

### In Scope

- Tax invoice header extraction.
- Tax invoice amount/tax extraction.
- Payment type and payment terms extraction when visible.
- Buyer/seller GSTIN and name extraction.
- PO number extraction when visible.
- Invoice series/principal/entity hints.
- Supporting document extraction for:
  - Gate Entry Note
  - GRN / receiving seal / inward stamp
  - Credit note
  - Other buyer receipt proof
- Confidence scores per important field.
- Warnings for missing, unclear, conflicting, or suspicious values.
- Backend validation of the AI JSON before using it.
- Comparison between AI output and worker-entered/backend data.
- Exceptions/alerts when mismatches or low confidence matter.

### Out of Scope

- Product line-item extraction.
- SKU-level reconciliation.
- Inventory deductions.
- Automatic final approval by AI.
- Model fine-tuning.
- Training pipeline.
- Chatbot-style founder Q&A.

## How Larger Document Systems Usually Work

Enterprise document systems normally separate the workflow into clear stages:

1. Store the original document safely.
2. Run OCR/layout extraction.
3. Convert raw OCR into structured fields.
4. Validate the structured fields with business rules.
5. Ask humans to verify uncertain fields.
6. Save final verified data.
7. Store the original extraction, corrections, and audit trail.
8. Improve rules/prompts/models using correction history.

The important pattern is that AI output is not treated as truth by itself. It is
treated as evidence with confidence.

## Existing Project Context

Today the app already has:

- Worker capture flow.
- OCR preview endpoint.
- Backend invoice workflow.
- Supporting document workflow.
- Validation against submitted invoice data.
- Exceptions and alerts.
- Audit trail.

Current extraction is too small. `backend/internal/validation/validation.go`
uses:

- InvoiceNumber
- VendorGSTIN
- BuyerGSTIN
- GrossAmount
- NetAmount
- TaxAmount
- Simulated
- Inconclusive

v1 keeps compatibility with this shape but introduces a richer JSON envelope so
the app can use confidence, warnings, document type, and supporting-document
fields.

## Design Principles

- Return strict JSON only.
- Validate all JSON server-side.
- Prefer `null` over guessed values.
- Use ISO dates: `YYYY-MM-DD`.
- Use uppercase GSTINs and document types.
- Use decimal numbers for money and quantities.
- Store confidence per field.
- Do not autofill low-confidence fields.
- Do not silently resolve mismatches.
- Preserve raw AI response, normalized JSON, and human corrections.
- Every AI-assisted decision should be explainable in the audit trail.

## Document Types

Allowed v1 document types:

- `TAX_INVOICE`
- `GATE_ENTRY_NOTE`
- `GRN_RECEIPT`
- `SECURITY_INWARD_STAMP`
- `STOCK_RECEIVING_ACK`
- `CREDIT_NOTE`
- `OTHER_SUPPORTING_DOCUMENT`
- `UNKNOWN`

The AI may classify a document as `UNKNOWN`, but the backend must then mark the
result as needing human review.

## Tax Invoice JSON Schema

This is the v1 target output for a tax invoice.

```json
{
  "schema_version": "ai_extraction_v1",
  "document_type": "TAX_INVOICE",
  "extraction_status": "SUCCESS",
  "invoice": {
    "invoice_number": "A260000218",
    "invoice_date": "2026-06-09",
    "seller_name": "Meridian Brothers",
    "seller_gstin": "06AAAAA0003A1Z3",
    "buyer_name": "Airplaza Retail Holdings Pvt Ltd",
    "buyer_gstin": "06AAAAA0013A1ZD",
    "po_number": "6906994991",
    "payment_type": "CASH",
    "payment_terms_days": null,
    "due_date": null,
    "taxable_amount": 10393.45,
    "tax_amount": 519.66,
    "total_amount": 10913.0
  },
  "business_hints": {
    "invoice_series": "A26",
    "principal_hint": "Britannia / Dairy",
    "seller_entity_hint": "Meridian Brothers",
    "buyer_branch_hint": "Gurgaon-4-Badshahpur",
    "sales_channel_hint": "MT",
    "salesman_hint": "Anup Nanda Goswami",
    "beat_hint": "22112"
  },
  "confidence": {
    "document_type": 0.98,
    "invoice.invoice_number": 0.96,
    "invoice.invoice_date": 0.92,
    "invoice.seller_gstin": 0.99,
    "invoice.buyer_gstin": 0.94,
    "invoice.taxable_amount": 0.9,
    "invoice.tax_amount": 0.88,
    "invoice.total_amount": 0.97,
    "invoice.payment_type": 0.75
  },
  "warnings": [],
  "needs_human_review": false
}
```

## Supporting Document JSON Schema

This is the v1 target output for a gate entry / GRN / receiving proof.

```json
{
  "schema_version": "ai_extraction_v1",
  "document_type": "GATE_ENTRY_NOTE",
  "extraction_status": "SUCCESS",
  "supporting_document": {
    "linked_invoice_number": "A260000218",
    "po_number": "6906994991",
    "gate_entry_number": "HH26260000014286",
    "gate_entry_date": "2026-06-09",
    "received_date": "2026-06-09",
    "buyer_name": "Airplaza Retail Holdings Private Limited",
    "buyer_gstin": "06AAAAA0013A1ZD",
    "buyer_branch_hint": "Gurgaon-4-Badshahpur",
    "invoice_quantity": 92,
    "accepted_quantity": 92,
    "invoice_amount": 10913.0,
    "discrepancy_amount": 0.0,
    "is_short_receipt": false,
    "receiver_name_hint": null,
    "vehicle_number": null
  },
  "confidence": {
    "document_type": 0.96,
    "supporting_document.linked_invoice_number": 0.95,
    "supporting_document.gate_entry_number": 0.93,
    "supporting_document.accepted_quantity": 0.9,
    "supporting_document.invoice_amount": 0.91,
    "supporting_document.is_short_receipt": 0.87
  },
  "warnings": [],
  "needs_human_review": false
}
```

## Extraction Status Values

Allowed values:

- `SUCCESS`: Enough important fields were extracted.
- `PARTIAL`: Some useful fields were extracted, but important fields are
  missing or low confidence.
- `INCONCLUSIVE`: The document could not be reliably understood.
- `UNSUPPORTED_DOCUMENT`: The document does not look like a supported invoice
  or supporting proof.
- `ERROR`: AI/OCR failed unexpectedly.

`PARTIAL`, `INCONCLUSIVE`, `UNSUPPORTED_DOCUMENT`, and `ERROR` must set
`needs_human_review` to true.

## Confidence Rules

Recommended thresholds:

- `>= 0.90`: high confidence. Can autofill.
- `0.70 - 0.89`: medium confidence. Can autofill only with visible "verify"
  cue.
- `< 0.70`: low confidence. Do not autofill. Show as suggestion or warning.
- Missing confidence for a field is treated as low confidence.

Important fields:

- document type
- invoice number
- invoice date
- seller GSTIN
- buyer GSTIN
- taxable amount
- tax amount
- total amount
- linked invoice number for supporting documents
- accepted quantity / invoice quantity
- discrepancy amount

Any low-confidence important field should add a warning and set
`needs_human_review` to true.

## Warning Format

Warnings should be structured, not only free text.

```json
{
  "code": "LOW_CONFIDENCE_FIELD",
  "field": "invoice.total_amount",
  "message": "Total amount is unclear; verify manually.",
  "severity": "warning"
}
```

Allowed severities:

- `info`
- `warning`
- `critical`

Recommended warning codes:

- `LOW_CONFIDENCE_FIELD`
- `MISSING_REQUIRED_FIELD`
- `INVALID_GSTIN_FORMAT`
- `AMOUNT_MATH_MISMATCH`
- `DOCUMENT_TYPE_UNCLEAR`
- `POSSIBLE_MISSING_PAGE`
- `POSSIBLE_DUPLICATE`
- `SUPPORTING_DOC_MISMATCH`
- `SHORT_RECEIPT_DETECTED`
- `PAYMENT_TERMS_UNCLEAR`
- `DATE_UNCLEAR`

## Backend Validation

The backend must validate the AI JSON before using it.

Tax invoice checks:

- `schema_version` must equal `ai_extraction_v1`.
- `document_type` must be allowed.
- GSTINs must match Indian GSTIN format if present.
- Dates must parse as `YYYY-MM-DD` if present.
- Amounts must be non-negative if present.
- `taxable_amount + tax_amount` should approximately equal `total_amount`.
- AI invoice number should match worker-entered invoice number when both exist.
- AI seller GSTIN should match selected seller entity when both exist.
- AI buyer GSTIN should match selected buyer when both exist.
- AI total amount should match worker-entered amount within tolerance.

Supporting document checks:

- `linked_invoice_number` should match the invoice it is attached to.
- `buyer_gstin` should match invoice buyer when present.
- `invoice_amount` should match invoice total when present.
- If `accepted_quantity < invoice_quantity`, raise or maintain a
  `SHORT_RECEIPT` dispute.
- If `discrepancy_amount > 0`, raise or maintain a `SHORT_RECEIPT` dispute.
- If extraction is inconclusive, raise an `ocr_inconclusive` exception.

## Mobile UX

### Worker Review Screen

The worker should see AI results as suggestions:

- High confidence: field is filled.
- Medium confidence: field is filled with "AI filled - verify".
- Low confidence: field remains empty or shows a warning.
- Mismatch: worker sees a clear warning, not a technical error.

Example worker-facing copy:

- "AI filled this. Please verify."
- "AI could not read total amount clearly."
- "Buyer GSTIN from photo differs from selected buyer."

### Owner / Reviewer Screens

The owner should see plain-language issue summaries:

- "Invoice total from OCR does not match the amount entered by worker."
- "Gate entry shows accepted quantity lower than invoice quantity."
- "Supporting document could not be matched to this invoice."

Avoid showing raw model text to non-technical users.

## Data Storage

Store three layers:

1. Original document file.
2. Raw OCR/AI extraction payload.
3. Normalized extraction JSON used by backend.

When a human edits/verifies fields, store:

- field name
- AI value
- human value
- user id
- timestamp
- reason if provided

This makes future improvement possible without pretending AI was perfect.

## Suggested Backend Types

Add a normalized extraction model separate from current
`validation.InvoiceData`.

```go
type AIExtractionEnvelope struct {
    SchemaVersion    string                 `json:"schema_version"`
    DocumentType     string                 `json:"document_type"`
    ExtractionStatus string                 `json:"extraction_status"`
    Invoice          *AIInvoiceFields       `json:"invoice,omitempty"`
    SupportingDoc    *AISupportingDocFields `json:"supporting_document,omitempty"`
    BusinessHints    AIBusinessHints        `json:"business_hints,omitempty"`
    Confidence       map[string]float64     `json:"confidence"`
    Warnings         []AIExtractionWarning  `json:"warnings"`
    NeedsHumanReview bool                   `json:"needs_human_review"`
}
```

Keep an adapter that converts successful tax invoice extraction into existing
`validation.InvoiceData` so existing workflow validation can continue while the
richer system is introduced.

## AI Prompt Contract

The AI prompt should instruct:

- Return only valid JSON.
- Use the exact schema.
- Never invent values.
- Use `null` when a value is not visible.
- Use uppercase GSTINs.
- Use ISO dates.
- Include confidence for every important field.
- Add warnings for unclear/missing/conflicting values.
- Do not include line items.

## Failure Handling

If AI call fails:

- Return `extraction_status: "ERROR"`.
- Set `needs_human_review: true`.
- Keep the app usable with manual entry.
- Write audit event.
- Raise `ocr_inconclusive` only where the document was expected to be checked.

If AI returns invalid JSON:

- Do not attempt fuzzy parsing in the production path.
- Mark extraction as invalid.
- Store raw response for debugging if safe.
- Raise human review.

If AI returns unsupported document type:

- Store result.
- Ask user to classify manually.
- Do not block invoice upload unless that document is required.

## Implementation Phases

### Phase 1: Schema and Parser

- Add Go structs for the v1 envelope.
- Add JSON validation.
- Add adapter to current `validation.InvoiceData`.
- Add tests for valid/invalid payloads.

### Phase 2: AI Extraction Activity

- Add Python activity that receives image path/storage key and document mode.
- Use OCR/Textract output plus AI structured extraction.
- Return strict JSON envelope.
- Keep current Textract-only path as fallback.

### Phase 3: Mobile Autofill

- Change OCR preview response to include confidence and warnings.
- Show "AI filled - verify" only for medium/high confidence.
- Avoid autofilling low-confidence fields.

### Phase 4: Supporting Document Matching

- Use v1 supporting document schema in `LedgerDocumentWorkflow`.
- Raise better exceptions for mismatch, short receipt, and inconclusive OCR.
- Store warnings in audit/extraction tables.

### Phase 5: Review Feedback Loop

- Store human corrections.
- Add extraction quality report:
  - field accuracy
  - low-confidence frequency
  - mismatch frequency
  - document types failing most often

## Testing Strategy

Use real sample documents from the existing Meridian dataset and new founder
sample invoices.

Test groups:

- Cash tax invoice.
- Credit tax invoice.
- Multi-page invoice.
- Rotated/low-quality invoice.
- Gate entry note with no discrepancy.
- Gate entry note with short receipt.
- Receiving stamp/GRN style document.
- Credit note.
- Unknown/unsupported document.

Assertions:

- JSON is valid.
- Required fields are present or warned.
- Dates normalize correctly.
- GSTIN validation works.
- Amount math validates.
- Confidence thresholds drive autofill decisions.
- Mismatches create exceptions.
- Short receipt creates or maintains dispute.
- Manual flow still works when AI fails.

## Success Criteria

v1 is successful when:

- Workers can autofill most common invoice header fields from real documents.
- Low-confidence fields are not silently accepted.
- Supporting documents can be matched to invoices when the fields are visible.
- Short receipt / discrepancy cases become clear alerts.
- AI failures do not block manual capture.
- Founder can understand AI issues in plain language.

## V1 Decisions

- Use a provider adapter instead of hard-coding extraction logic directly into
  workflow code. The first adapter can call whichever AI provider is configured
  by environment, but the rest of the app should only depend on the v1 JSON
  envelope.
- Store normalized extraction JSON permanently with the invoice/document audit
  trail. Store raw provider responses only for debugging behind a retention
  policy, because they can be verbose and may contain sensitive document text.
- Do not autofill low-confidence fields. Show them as warnings or suggestions
  only. Medium-confidence fields may be autofilled with a visible verification
  cue.
- S3 is not required to build and test the v1 extraction contract locally, but
  durable object storage should be treated as a production hardening
  prerequisite before expanding AI extraction to daily staff usage.
