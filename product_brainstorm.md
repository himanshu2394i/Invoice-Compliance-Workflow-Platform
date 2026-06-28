# Product Brainstorm: Digital Invoice Ledger & Reconciliation Alerts for Meridian

Source data: 61 invoices/documents logged in [invoice_extraction.md](invoice_extraction.md), entries [1]-[38]+.
Source code reviewed: `backend/db/migrations/000001_initial_schema.up.sql`, `backend/internal/workflow/*`, [project memory](../../../../.claude/projects/D--MeridianDist/memory/project_invoice_saas_overview.md).

## What this product actually is

Not a distributor-ops/sales-analytics platform. The real job: **replace the paper filing cabinet with a digital one that watches itself.**

Today: workers print invoices, get them stamped/signed on delivery, and physically file the invoice + its supporting documents (partly because GST compliance requires ~3 years of retained records). The owner has no way to check "is anything missing or wrong" without manually digging through paper.

Wanted: workers upload photos of the invoice and its supporting documents. The system files them, and automatically flags:
1. **A missing invoice** — an invoice number that should exist (it falls inside a known numbering sequence) but was never uploaded/filed.
2. **A missing supporting document** — an invoice with no stamped/signed receipt, Gate Entry Note, GRN, etc. attached.
3. **A mismatched document** — a supporting document that's clearly for a *different* invoice (wrong invoice number, wrong buyer, wrong amount) but got filed under the wrong one.

The owner gets a list of these exceptions and can search/browse any invoice and its attached documents on demand, going back years.

## Why this is a smaller, more buildable target than my first pass

I'd over-scoped this toward a full distributor-ops platform (buyer branches, principal-wise reporting, scheme/payout tracking, sales-rep/beat management, AR aging). None of that is needed for "digitize the filing + alert on gaps." Drop all of it from the build.

It also turns out the existing schema is **closer to fitting** than I first argued, once trimmed to this scope:
- `entities` already = Meridian's 3 legal entities (issuer side) — no change needed.
- `documents` / `document_versions` already model "one or more documents attached to an invoice," already **immutable** (every re-upload is a new version row, nothing is ever overwritten) — which is exactly the property you want for a 3-year retention requirement. This table just needs to be used for "supporting documents" (Gate Entry Note, GRN stamp, receiving stamp, signed copy) rather than AP attachments.
- `invoices` already has `invoice_number`, `invoice_date`, `entity_id`, `gross_amount` — the header fields needed for matching.
- `vendors` is the one piece pointing the wrong way (it means "outside supplier who bills the tenant"). For this scope, just repoint/rename it to mean **the buyer named on the invoice** — Meridian still issues the invoice, `entities` is the issuer, this table becomes who it was issued *to*. Identify buyers by GSTIN, not name — entries [31]/[32] in invoice_extraction.md found three different "Mart"-named buyers that are legally unrelated companies, and one case where the billing name and the receiving stamp's name didn't match. Name-matching will silently misfile documents; GSTIN won't.

So this is a trim-and-repoint of the existing schema, not a rebuild.

## The three checks, concretely

**1. Missing invoice (sequence gap)**
Every series you've seen (A26..., NIV..., CAD/..., DBR..., HAL..., HELL..., HYGIN..., REHIN..., BIB..., MORDE..., GST...) is a numeric sequence per entity. If Meridian Brothers' "A26" series has invoices ...218, ...223, ...225 on file, numbers 219-222 and 224 were presumably issued (the principal's billing system generated them) but never filed/uploaded here. A periodic job scans each (entity, series-prefix) for gaps in the numbers actually on file and raises an alert per missing number. This needs nothing about buyers or principals — it's pure number-sequence bookkeeping per entity+series.

**2. Missing supporting document**
After some grace period (e.g. 7-14 days from invoice date, configurable), any invoice with zero attached documents of a "proof of receipt" type (stamp, signed copy, Gate Entry Note, GRN, BR-Stock Acknowledgement — all the formats already catalogued in invoice_extraction.md's "Document types seen") gets flagged. Simple existence check, no OCR needed for this one.

**3. Mismatched document**
This one does need OCR on the supporting document itself, not just the invoice: extract whatever invoice number / buyer name / amount appears on the stamp or Gate Entry Note, and compare it against the invoice it's filed under. If they don't agree, flag it rather than silently filing it. (Note from invoice_extraction.md entry [32]: even a *correctly filed* document can have a buyer-name mismatch between the invoice and its own receiving stamp — e.g. "SVH Realty Estates" billed, "Eighty Three Haven Essentials LLP" stamped as receiver. Treat that as a softer "name differs, GSTIN/invoice number agrees" case vs. a hard mismatch, so the alert doesn't cry wolf on legitimate edge cases.)

## Minimal schema changes

Building on the existing migration, additive:

```
buyers                  -- repoint/rename of `vendors`: name, GSTIN (unique), address. Identity key = GSTIN.
invoices.buyer_id        -- new FK, replaces the AP-direction vendor_id usage
invoices.invoice_series  -- parsed prefix (e.g. "A26", "NIV", "HYGIN") — or compute on the fly from invoice_number, doesn't strictly need to be stored
document_versions.metadata -- already JSONB; store OCR-extracted {invoice_number, buyer_name, buyer_gstin, amount, doc_date} per supporting doc here, no new table needed
reconciliation_status     -- new table or a status column on invoices: 'ok' | 'missing_document' | 'document_mismatch' | (separately) a list of 'missing_invoice_number' rows per entity+series, since those don't correspond to a real invoice row at all
```

That's the whole schema delta. No principals, no buyer branches, no schemes, no sales-reps/beats, no line items — none of that is needed to answer "is anything missing or wrong."

## Workflow

1. Worker uploads invoice photo(s) + supporting document photo(s) together (or supporting docs can be added later to an already-filed invoice).
2. OCR extracts invoice number + buyer + amount + date from the invoice (existing OCR worker, just needs the extraction target simplified to this header-only shape — much lighter than full line-item extraction).
3. OCR extracts the same fields from each supporting document.
4. System auto-links the supporting doc to the invoice it names; if OCR can't confidently match, the worker is prompted to pick the invoice manually rather than the system guessing wrong.
5. Mismatch check runs immediately on upload (cheap, no need to wait for a batch job).
6. A periodic job (daily is plenty) does the two batch checks: sequence-gap scan per entity+series, and missing-document scan over invoices past their grace period.
7. Owner dashboard: an exceptions list (the three alert types), each linking straight to the invoice record with all attached documents visible.
8. Search/browse for the owner: by invoice number, buyer (GSTIN-backed, so name variants don't cause misses), entity, date range — opens the invoice and every document filed under it.

The existing Temporal setup is a good fit for steps 4-6 (OCR-then-match as one workflow per upload, the two periodic scans as separate scheduled workflows) — no need for new infrastructure, just new workflow definitions replacing the current approve/reject one.

## Suggested build order

1. Schema: add `buyers`, repoint `invoices.buyer_id`, drop/ignore the approve-reject workflow's now-irrelevant states.
2. Upload flow: invoice + supporting-doc photo upload (mobile-friendly, since these are phone photos in practice), simplified OCR extraction (header fields only — no line items needed for this scope).
3. Mismatch check on upload (the cheapest, highest-signal check — catches misfiling at the moment it happens).
4. Missing-document batch scan.
5. Missing-invoice-number (sequence gap) batch scan.
6. Owner dashboard: exceptions list + search/browse.

## One thing worth flagging, not deciding for you

The sequence-gap check (#1) assumes invoice numbers are issued by a system Meridian doesn't control (the principal's billing software, going by the series-per-principal pattern). That means "missing" could mean either "we never filed the paper" (the real problem you're solving) or "that number was genuinely never issued to us" (not a problem at all — e.g., a series might legitimately skip numbers across different distributors sharing one principal's numbering pool). Worth a quick gut-check with whoever currently reconciles this by hand: do they already know how to tell the difference, or would the alert need a "mark as not applicable" action so false positives don't get noisy fast.