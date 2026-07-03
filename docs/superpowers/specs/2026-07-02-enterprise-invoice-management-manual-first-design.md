# Enterprise Invoice Management - Manual-First Design

Date: 2026-07-02

## Product Positioning

This product is an enterprise invoice management application for the Meridian
distribution business. OCR and AI are useful layers, but they are not the
product foundation.

The manual system must be reliable even when OCR/AI is disabled.

Founder-friendly statement:

> "This is the operating system for invoices: every invoice, document, issue,
> approval, payment, and follow-up in one reliable place."

## Goal

Build a world-class manual invoice-management workflow first. The system should
let staff capture, store, find, review, dispute, approve, reconcile, and collect
against invoices without depending on AI.

AI/OCR can then be added as an acceleration layer:

- autofill fields,
- classify documents,
- detect mismatches,
- summarize issues,
- prioritize alerts.

## Non-Goals

- Do not make OCR the main product promise.
- Do not require AI for invoice submission.
- Do not add line-item extraction before the manual workflow is stable.
- Do not revive the abandoned `frontend/` app.
- Do not build a generic SaaS product; this remains tailored to the Meridian
  pilot.

## Enterprise Layers

### Layer 1: Document Vault

Purpose: preserve the original invoice evidence.

Required capabilities:

- Store original invoice and supporting documents.
- Store multi-page invoices.
- Store credit notes and replacement versions.
- Keep immutable version history.
- Show who uploaded each version and when.
- Preview documents inside the app.
- Download documents when needed.
- Protect against path traversal and wrong-tenant access.
- Prepare for durable object storage such as S3.

Current state:

- Local filesystem storage exists.
- Document rows and document versions exist.
- Owner document viewing exists.
- Manager/admin version history exists.

Gaps:

- No S3/object storage yet.
- No backup/recovery story.
- OCR worker storage sharing must be verified when using local volumes.
- No storage health/checksum verification screen.

### Layer 2: Invoice Registry

Purpose: every invoice becomes a searchable, structured business record.

Required capabilities:

- Invoice number, seller entity, buyer, buyer GSTIN, date, amount, tax.
- Payment type, terms, due date.
- Buyer branch/store/warehouse.
- Principal and invoice series.
- Current status.
- Documents attached.
- Open exceptions/disputes.
- Payment summary.
- Powerful search and filters.
- Duplicate warning before submission.
- Clear status labels for non-technical users.

Current state:

- Invoice records exist.
- Seller entities, buyers, principals, series, branches, payment terms exist.
- Owner invoice search exists.
- Backend has upload idempotency around invoice number retries.

Gaps:

- No pre-submit duplicate warning in the worker flow.
- Status language is still system-like in places.
- Owner list search is client-side over current page, not a full server-side
  search/filter system.
- No saved filters.

### Layer 3: Capture and Upload Workflow

Purpose: field staff can submit good invoice records quickly and safely.

Required capabilities:

- Capture invoice image.
- Add multiple pages.
- Retake pages.
- Manual entry for required fields.
- Select buyer/entity/branch/payment terms.
- Capture buyer-required supporting documents.
- Work offline.
- Retry sync safely.
- Recover draft after app kill/restart.
- Warn about duplicate invoice before submit.
- Warn about low-quality photos.
- Show plain error messages.

Current state:

- Capture flow exists.
- Offline queue exists.
- Multi-page invoice capture exists.
- Buyer-specific supporting checklist exists.
- Sync retry is resumable.

Gaps:

- No draft recovery.
- No duplicate warning before submit.
- No photo quality checks.
- Some failure states are still technical.

### Layer 4: Master Data

Purpose: encode the real Meridian business so the app can guide users.

Required capabilities:

- Seller entities.
- Buyers and GSTINs.
- Buyer branches/warehouses.
- Buyer sales channels.
- Buyer credit terms.
- Buyer document requirements.
- Principals/brands.
- Invoice series registry.
- Approval rules.

Current state:

- Most of this exists.

Gaps:

- No delete endpoint for buyer document requirements.
- Master-data UI needs stronger guardrails and clearer non-technical copy.
- No import/export tool for master data.

### Layer 5: Workflow and Review

Purpose: make it obvious what stage each invoice is in and who must act.

Required capabilities:

- Submitted.
- Missing documents.
- Under review.
- Disputed.
- Pending manager approval.
- Pending finance approval.
- Approved.
- Rejected.
- Archived.
- Partially paid.
- Paid.
- Overdue.

Current state:

- Temporal workflow supports validation and approval states.
- Owner detail supports approval/rejection.
- Worker can see backend status.

Gaps:

- Statuses are not yet unified into founder/staff-friendly lifecycle labels.
- Manual review tasks are not assigned to a specific user/person.
- No SLA/aging on review work.

### Layer 6: Disputes and Exceptions

Purpose: turn invoice problems into trackable work, not lost conversations.

Required capabilities:

- Short receipt.
- Missing page.
- Wrong buyer.
- Amount mismatch.
- Missing gate entry.
- Credit note requested.
- Tax issue.
- Duplicate invoice.
- Other issue.
- Status, notes, resolution, credit note, audit trail.

Current state:

- Disputes exist.
- Exceptions exist.
- Gate-entry mismatch can auto-open short receipt dispute.
- Credit note upload exists.

Gaps:

- No task ownership/assignment.
- Alerts are not filterable.
- No aging/escalation.
- No bulk resolution/review queue.

### Layer 7: Receivables and Payments

Purpose: connect invoice capture to collections.

Required capabilities:

- Buyer-wise outstanding.
- Due date and overdue amount.
- Aging buckets.
- Partial payments.
- Payment mode/reference/date.
- Payment history.
- Credit-note impact.
- Prevent over-payment.

Current state:

- Receivables and payment recording exist.
- Over-balance payment rejection exists.
- Overdue invoices enter alerts.

Gaps:

- No export/report sharing.
- No payment reversal/correction workflow.
- No cash/credit reconciliation report.
- No reminder workflow outside the app.

### Layer 8: Alerts and Tasks

Purpose: make the system action-oriented.

Required capabilities:

- Alert feed by type.
- Task owner or role.
- Priority.
- Age.
- Due date.
- Status.
- Filters.
- Escalation.
- External delivery later: WhatsApp/SMS/email/push.

Current state:

- In-app alert feed exists.
- Alert badge exists.
- Alerts include open exceptions, disputes, and overdue invoices.

Gaps:

- Alerts are not real task records.
- No filters.
- No aging UI.
- No assignment.
- No external notifications.

### Layer 9: Audit and Compliance

Purpose: founder trust and operational accountability.

Required capabilities:

- Record every important change.
- Store old value and new value for manual edits.
- Store actor, timestamp, reason.
- Show audit trail in invoice detail.
- Protect tenant isolation.
- Define retention/backup policy.

Current state:

- Audit events exist.
- Invoice audit trail exists.
- Row-level security exists.

Gaps:

- Not every manual field update has old/new diff because not all edit flows
  exist yet.
- No formal data retention/security checklist.
- No backup verification.

### Layer 10: Security and Administration

Purpose: safe staff rollout.

Required capabilities:

- Password change.
- Password reset.
- Role management.
- Admin password rotation.
- MFA for admin/manager.
- Session expiry.
- Login rate limit.
- Device/server URL management.

Current state:

- Login exists.
- JWT auth exists.
- Login rate limit exists.
- Role-gated routes exist.

Gaps:

- No password change/reset.
- No MFA.
- No user/role admin UI.
- Pilot credentials must be rotated before real rollout.

### Layer 11: Reporting

Purpose: founder-level business visibility.

Required capabilities:

- Sales by buyer.
- Sales by principal.
- Sales by seller entity.
- Sales by channel.
- Sales by salesman/beat.
- Open disputes.
- Overdue receivables.
- Worker upload activity.
- Buyer issue frequency.
- Export/download.

Current state:

- Sales report endpoint exists.
- Dashboard sales section exists.
- Receivables exist.

Gaps:

- Limited filters.
- No export/share.
- No worker activity report.
- No issue-frequency report.

### Layer 12: AI/OCR Intelligence

Purpose: reduce manual effort after the manual system is dependable.

Required capabilities:

- Structured JSON extraction.
- Autofill with confidence.
- Supporting document matching.
- Duplicate/mismatch detection.
- Plain-language alert summaries.
- Optional later natural-language search.

Current state:

- OCR preview exists.
- Textract path exists.
- AI structured extraction v1 spec exists.

Gaps:

- AI JSON contract not implemented yet.
- Confidence not stored/displayed fully.
- No correction feedback loop.

## Priority Roadmap

### Milestone 1: Manual Reliability Foundation

Ship first:

- Draft recovery.
- Duplicate warning before submit.
- Better capture error states.
- Server-side invoice search/filter.
- Alert filters and aging.
- Buyer document requirement delete.

Why:

These make the current manual workflow less fragile and directly improve field
usage.

### Milestone 2: Durable Document Vault

Ship:

- S3/object storage adapter.
- Migration or compatibility plan for existing local files.
- Storage health checks.
- Backup/recovery checklist.
- Document checksum verification.

Why:

The founder must trust that invoices will not disappear.

### Milestone 3: Task-Based Review

Ship:

- Real task records for alerts.
- Assignment to role/person.
- Priority and age.
- Filters.
- Escalation rules.
- Reviewer queue.

Why:

Dashboards show information; task queues drive action.

### Milestone 4: Security and Staff Rollout

Ship:

- Password change/reset.
- User management.
- Admin/manager MFA.
- Session expiry settings.
- Pilot credential rotation.

Why:

This is required before real staff use.

### Milestone 5: Receivables and Reporting Polish

Ship:

- Payment correction/reversal flow.
- Collection notes.
- Export/share reports.
- Buyer issue frequency.
- Worker upload activity.

Why:

This makes the product useful to founder/finance beyond capture.

### Milestone 6: AI/OCR Pipeline

Ship after manual foundation:

- AI structured extraction v1.
- Confidence-driven autofill.
- Supporting document matching.
- Correction feedback loop.

Why:

AI should accelerate a stable process, not hide missing process reliability.

## Completion Definition

The enterprise manual app is "reliable" only when:

- A worker can submit invoices manually without AI.
- App restart does not lose in-progress capture.
- Duplicate risk is visible before submission.
- Uploaded documents are durable and recoverable.
- Owner can search/filter invoices and see clear status.
- Every issue appears in an actionable queue.
- Payments and receivables reconcile correctly.
- Admin can maintain required master data.
- Staff can manage credentials safely.
- Audit trail explains important actions.
- Tests cover each critical path.

