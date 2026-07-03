# Founder Walkthrough Guide - Meridian Ops / Invoice Capture

Last reviewed from code: 2026-07-02

This guide is written for a non-technical founder demo. It explains what the
app is, what each screen does, how the founder or staff would use it, what is
currently working, what is not yet connected, and where uploaded invoices are
stored today.

Use this as your presentation script and as a quick memory reset before the
meeting.

## 1. One-minute explanation

This is an internal operations app for Meridian Brothers / Meridian Distributors.
It started as an invoice capture app, but now it also covers the daily
distributor operations around invoices:

- Field workers photograph invoices and required buyer documents.
- The app stores captures offline first, so bad network does not block field
  work.
- When online, captures sync to the backend.
- Managers/owners can see every invoice, document image, dispute, alert,
  approval status, audit trail, receivable, and payment.
- Admin users can maintain buyers, branches, principals, invoice series, buyer
  document requirements, and approval rules.

Plain-English positioning:

> "This is not just a scanning app. It is a digital invoice control room for
> the distributor business: capture the bill, prove the delivery documents,
> catch mismatches, track approvals, and know who still owes money."

## 2. Current pilot status

What is currently built:

- Android Flutter app with login, worker capture flow, owner dashboard, invoice
  list/search, invoice detail, alerts, receivables, payments, and admin/master
  data screens.
- Go backend API with Postgres, Temporal workflows, local document storage, JWT
  login, role-based routes, and audit logs.
- Python OCR worker with AWS Textract code path.
- Production deployment stack on one EC2 instance behind Caddy HTTPS.
- Default mobile server URL points to:
  `https://203-0-113-10.sslip.io`
- Latest release APK has been built at:
  `mobile/build/app/outputs/flutter-apk/app-release.apk`

Important current caveats:

- S3 is not connected as the live document store.
- Uploaded invoice images are currently stored on the server's local Docker
  volume, not in an S3 bucket.
- The APK still needs to be sideloaded onto the pilot device according to the
  latest `task.md` note.
- Alerts are in-app only. There is no push notification, SMS, WhatsApp, or
  email alerting yet.
- OCR exists, but should be presented as "assistive / verify before relying",
  not as fully hands-free automation.
- Password reset/change is not built yet.
- MFA is not built yet.
- Photo quality checks, duplicate invoice warning, draft recovery, alert
  filters, and buyer-requirement delete are not built yet.

## 3. The main users and what each one can do

### Worker

The worker is the person in the field or at the receiving point capturing
documents.

Main tabs:

- Capture
- Queue
- My Invoices

Worker can:

- Take invoice photos.
- Add multiple invoice pages.
- Review and enter invoice details.
- Select seller entity.
- Search buyer by name or GSTIN.
- Capture buyer-required supporting documents.
- Save offline and sync later.
- See uploaded invoice status in "My Invoices".

Worker cannot:

- Use the owner dashboard.
- Manage approval rules.
- Record payments.
- See all admin/master-data controls.

### Admin

Admin is the highest-control role.

Admin can:

- Use the owner dashboard.
- Capture invoices.
- See all invoices and alerts.
- Approve or reject pending invoices.
- Record payments.
- Manage principals and invoice series.
- Edit buyers, branches, sales channels, and credit terms.
- Configure buyer document requirements.
- Configure approval rules.
- View document version history.

### Manager

Manager can:

- Use the owner dashboard.
- Capture invoices.
- See all invoices and alerts.
- Approve/reject invoices when manager approval is required.
- Resolve exceptions and disputes.
- Record payments.
- View document version history.

Manager generally cannot:

- Add/delete admin-only master data such as rules and some registry items.

### Finance

Finance can:

- Use the owner dashboard.
- See invoices, receivables, reports, and alerts.
- Approve/reject invoices when finance approval is required.
- Record payments.

Finance generally cannot:

- Resolve disputes in the current mobile UI.
- Manage admin settings.

### Reviewer

Reviewer can:

- Use the owner dashboard.
- See invoices and alerts.
- Review exceptions/disputes.

Reviewer is mainly a visibility/review role, not a data-admin role.

## 4. Important business terms

### Seller entity

This is which Meridian legal entity issued the invoice.

Current entities in the capture screen:

- Meridian Brothers
- Meridian Distributors
- Meridian Gurgaon

The worker selects this during capture. The GSTIN identifies the entity.

### Buyer

The customer/buyer receiving goods. Examples include Flipkart, Max
Hypermarket, Airplaza/Vishal Mega Mart, Innovative Retail Concepts, Zepto, and
V-Mart.

The app stores buyer name, GSTIN, sales channel, default credit terms, and
optional buyer branches/stores.

### Principal

The brand/principal whose goods are being distributed, such as Britannia,
Mondelez, Nestle, Haleon/GSK, etc.

### Invoice series

Invoice numbers often start with a prefix that tells us the entity/principal.
The app has a series registry. During capture, typing an invoice number can
show a chip identifying the detected series/principal/entity.

Example concept:

- Prefix `CAD` might map to a particular principal/entity.
- Prefix `A26` might map to another.

### Payment type

The invoice can be marked:

- Cash
- Credit

Credit invoices can have payment terms in days. The backend calculates a due
date and includes the invoice in receivables if unpaid.

### Supporting document

Any extra document needed to prove receipt/acceptance by a buyer. Examples:

- Gate Entry Note
- GRN Seal
- Security Inward Stamp
- Stock Receiving Acknowledgement
- Credit Note

Different buyers can require different supporting documents.

### Exception

An exception is an open issue raised by the system. Examples:

- OCR could not confidently read a document.
- Extracted invoice data does not match the submitted invoice.
- Supporting document appears to mismatch the invoice.
- A required document has been missing too long.

### Dispute

A dispute is a business issue raised by a person or by gate-entry mismatch.
Supported dispute types include:

- Short receipt
- Credit note requested
- Arithmetic error
- Missing page
- Tax structure error
- Other

### Receivable

Money still owed by buyers on credit invoices. The app groups outstanding
amount by buyer and aging bucket.

## 5. Login and navigation

The app starts at Login.

After login:

- Worker lands on the worker shell: Capture, Queue, My Invoices.
- Admin/Manager/Finance/Reviewer land on the owner shell: Dashboard, Invoices,
  Receivables, Alerts, More.

There is a Server Settings screen where the backend URL can be changed. The
default URL in the code is:

`https://203-0-113-10.sslip.io`

Presentation note:

- If the login fails during demo, first check server URL in Settings.
- If already logged in and changing URL, the app says to restart if needed.

Current pilot login note:

- `task.md` records temporary pilot logins using
  `himanshu{worker,manager,admin,finance}@gmail.com` with password
  `Pilot@2026`.
- Treat these as demo-only credentials. They should be rotated before real
  staff rollout.

## 6. Worker workflow: how to capture an invoice

### Step 1: Open Capture

Worker sees a simple Capture tab with a "Capture Invoice" button.

What to say:

> "The worker does not need to understand the whole system. Their job starts
> here: photograph the invoice and submit it."

### Step 2: Take invoice photo

The camera opens with crop guides. The app asks for camera permission if needed.

After taking the photo:

- The raw camera temp file is deleted.
- A compressed JPEG is saved inside the app's private documents area.
- The worker is taken to Review Invoice.

### Step 3: Add more invoice pages if needed

On Review Invoice:

- The first photo is shown as Page 1.
- The worker can tap a page to retake it.
- The worker can tap "Add page" if the invoice has multiple pages.
- Extra pages become `INVOICE_PAGE` supporting documents on upload.

### Step 4: OCR preview tries to help

When the review screen opens, the app sends the first invoice photo to the
backend OCR preview endpoint.

If OCR succeeds, it may fill empty fields like:

- Invoice number
- Seller GSTIN
- Buyer GSTIN
- Taxable amount
- Total amount

Important:

- OCR only fills empty fields.
- The UI marks fields as "Filled by OCR - verify".
- The worker must still verify all values.
- If OCR fails or times out, the worker just fills fields manually.

What to say:

> "OCR is assistance, not blind automation. We still keep the worker in the
> loop so a wrong read does not become a wrong ledger entry."

### Step 5: Select seller entity

Worker chooses one of:

- Meridian Brothers
- Meridian Distributors
- Meridian Gurgaon

This maps the invoice to the right legal entity/GSTIN.

### Step 6: Enter invoice number

The worker types invoice number.

If the prefix matches the series registry, the app shows a chip with detected
series/principal/entity information.

### Step 7: Select buyer

Worker can:

- Search buyer by name or GSTIN.
- Select a known buyer.
- Or manually type buyer GSTIN/name if needed.

When buyer GSTIN is known, the app fetches that buyer's required supporting
documents.

### Step 8: Select branch/store if configured

For buyers with branches or store/warehouse locations, the app can show a
delivery branch picker.

Useful for:

- Store-level delivery tracking.
- Vishal/Flipkart/Zepto style branch or warehouse entries.

### Step 9: Select Cash or Credit

Worker marks the invoice as:

- Cash
- Credit

If Credit:

- Terms in days can be entered.
- If buyer default terms exist, the app can prefill them.
- Backend calculates due date.
- The invoice later appears in Receivables until paid.

### Step 10: Enter date and amounts

Worker enters:

- Invoice date
- Taxable amount
- Total amount

Validation in the form prevents impossible totals, such as taxable amount being
greater than total amount.

### Step 11: Capture required supporting documents

The Supporting Documents screen shows what is required for that buyer.

Examples:

- "Gate Entry / Discrepancy Note"
- "GRN Seal"
- "Security Inward Stamp"
- "Stock Receiving Acknowledgement"

For buyer-generated documents, the UI tells the worker to ask the store/buyer
for it.

If no documents are configured for that buyer, the screen says no additional
documents are required.

### Step 12: Submit bundle

When submitted:

1. The capture bundle is saved locally in Hive.
2. The app tries to sync immediately.
3. If upload succeeds, it goes to the server.
4. If upload fails, the app keeps it offline and shows that it will sync when
   connection is restored.

## 7. Offline queue: what happens when network is bad

The Queue tab shows every local capture bundle and status:

- Pending
- Synced
- Failed
- Syncing

The worker can tap Sync.

The sync process is resumable:

- First it uploads the primary invoice and creates the server invoice.
- Then it uploads each supporting document.
- If the first upload worked but supporting document upload failed, retry does
  not create a duplicate invoice.
- Already uploaded supporting documents are skipped on retry.

Business value:

> "A field worker can continue capturing even without stable internet. The
> phone becomes a safe temporary queue."

## 8. Worker "My Invoices"

The My Invoices tab lets a worker see backend status after sync.

It shows:

- Invoice number
- Invoice date
- Amount
- Current state

Possible states include:

- INGESTED
- VALIDATING
- VALIDATION_FAILED
- PENDING_MANAGER_APPROVAL
- PENDING_FINANCE_APPROVAL
- APPROVED
- REJECTED
- ARCHIVED

Presentation note:

- The local Queue only tells whether upload happened.
- My Invoices tells what happened after the server received it.

## 9. Owner dashboard: what the founder sees

Owner-side users see five tabs:

- Dashboard
- Invoices
- Receivables
- Alerts
- More

### Dashboard

Dashboard shows:

- Total invoices
- Today's invoice value
- Open exceptions
- Open disputes
- Sales report section
- Recent invoices

Admin/Manager also have a camera icon to capture an invoice from the dashboard.

### Sales report section

The dashboard includes sales reporting. Backend supports grouping by:

- Principal
- Buyer
- Channel
- Entity
- Salesman

Default date range is current month if dates are not supplied.

Business value:

> "The founder can see not just documents, but how sales are split by brand,
> buyer/channel, entity, and team."

## 10. Invoice list and search

The Invoices tab shows all invoices.

Search can match:

- Invoice number
- Buyer name
- Buyer GSTIN
- Seller/entity name
- Amount
- Status
- Invoice date

Each row shows:

- Invoice number
- Buyer
- Date
- Document count
- Amount
- Whether there are open issues/disputes

Tapping an invoice opens Invoice Detail.

## 11. Invoice detail screen

This is the most important owner screen.

It shows:

- Invoice number
- Buyer
- Seller
- Date
- Gross amount
- Tax
- Payment type and due date if credit
- Current status
- Documents
- Disputes
- Exceptions
- Payment history if credit
- Audit trail button

### Document viewing

Documents are grouped by document type:

- Tax Invoice
- Tax Invoice page
- Gate Entry / Discrepancy Note
- Credit Note
- GRN or other supporting docs

Owner can tap View:

- App downloads the image from the backend.
- Image opens in a full-screen zoomable viewer.

Manager/Admin can also view document version history.

### Document version history

If a manager/admin replaces an existing supporting document type, the backend
does not overwrite the old file. It appends a new immutable version.

This gives:

- History of changes.
- Who uploaded the newer version.
- Ability to view older versions.

### Exceptions

Open exceptions appear in the invoice detail screen.

Users can mark an exception:

- Resolved
- Not applicable

Examples of exception types:

- OCR inconclusive
- Invoice data mismatch
- Document mismatch
- Missing document

### Disputes

The user can raise a dispute/note issue from the invoice detail screen.

Supported dispute types:

- Short receipt
- Credit note requested
- Arithmetic error
- Missing page
- Tax structure error
- Other

Dispute statuses:

- Open
- Owner reviewing
- Resolved
- Rejected

For credit-note disputes, the UI supports uploading a credit note via camera or
gallery.

### Gate entry details

For Gate Entry Note documents, the detail screen has a gate-entry action.

User can enter:

- Gate entry number
- Invoice quantity
- Accepted quantity
- Short receipt yes/no
- Notes

If accepted quantity is less than invoice quantity, or a discrepancy is
entered, the backend automatically raises a short-receipt dispute.

Business value:

> "If a buyer accepts less quantity than billed, it is captured immediately and
> becomes a receivable/dispute item instead of getting lost in WhatsApp or
> memory."

### Approval buttons

If an invoice is waiting for approval, Manager/Finance/Admin can approve or
reject from invoice detail.

Approval depends on the workflow state:

- Manager approval stage waits for manager/admin.
- Finance approval stage waits for finance/admin.
- Rejection can stop the workflow.

### Audit trail

The audit trail records events on the invoice, such as:

- Ingested
- Workflow started
- OCR extraction completed
- Validation failed
- Document uploaded
- Document matched/mismatched
- Gate entry set
- Dispute updated
- Credit note uploaded
- Payment recorded
- Approved/rejected/archived

This is important for accountability.

## 12. Alerts: what alerts the founder will get

Current alerts are in-app only.

Where alerts appear:

- Owner shell bottom tab badge on Alerts.
- Alerts screen.
- Dashboard open exception/open dispute counts.
- Invoice list issue/dispute indicators.

Current alert feed includes:

- Open invoice exceptions.
- Open or reviewing disputes.
- Overdue credit invoices with unpaid balance.

Examples:

- OCR could not confidently read invoice/supporting document.
- Supporting document does not match invoice.
- Missing supporting document after grace period.
- Short receipt dispute is open.
- Credit note requested but not resolved.
- Credit invoice is overdue and still unpaid.

What is not built yet:

- No push notification.
- No SMS.
- No WhatsApp.
- No email.
- No alert filters/aging UI yet.

What to say:

> "Today alerts are inside the app. The next step for proactive alerts would be
> WhatsApp/SMS/email or Firebase push, depending on what channel the team
> actually wants staff to respond on."

## 13. Receivables and payment collection

The Receivables tab is for credit invoices.

It shows:

- Total outstanding
- Total overdue
- Buyer-wise outstanding amount
- Number of open invoices
- GSTIN
- Aging buckets:
  - Current
  - 1-30 days
  - 31-60 days
  - 60+ days

Tapping a buyer opens that buyer's receivable invoices.

Payments:

- Finance/Manager/Admin can record payment.
- Payment modes: CASH, UPI, CHEQUE, NEFT, OTHER.
- Payment amount cannot exceed remaining invoice balance.
- Payment can include date and reference number/UTR/cheque number.
- Payment history appears in invoice detail.

Important nuance:

- Receivables only include CREDIT invoices.
- Legacy invoices without payment type do not appear in receivables.
- Short-receipt disputes can mean final receivable may change when credit note
  is issued.

## 14. More tab and admin/master data

The More tab includes:

- User identity/role
- Capture invoice
- Sync queue
- Principals & series
- Buyers
- Buyer document requirements (admin)
- Approval rules (admin)
- Server settings
- Sign out

### Principals & series

Shows:

- Principals/brands distributed.
- Invoice series mappings.

Admin can:

- Add principal.
- Delete principal.
- Add series mapping.
- Delete series mapping.

Why it matters:

- Series mapping helps identify which principal/entity an invoice belongs to
  based on invoice-number prefix.

### Buyers

Shows all buyers and GSTINs.

Admin can edit:

- Sales channel: GT, MT, ECOM, HOSPITALITY, INDUSTRIAL.
- Default credit terms in days.
- Branch/store/warehouse list.

Branch data is used during capture.

### Buyer document requirements

Admin can configure what extra documents each buyer requires.

Fields:

- Document type, e.g. `GATE_ENTRY_NOTE`
- Label, e.g. `Gate Entry / Discrepancy Note`
- Buyer-generated yes/no
- Sort order

Current limitation:

- There is an upsert/add/update endpoint.
- There is no delete endpoint for buyer document requirements yet.

### Approval rules

Admin can configure rules that determine when manager or finance approval is
required.

Supported fields:

- GrossAmount
- NetAmount
- TaxAmount

Supported operators:

- >
- <
- ==
- >=
- <=

Supported actions:

- REQUIRE_MANAGER_APPROVAL
- REQUIRE_FINANCE_APPROVAL

Default policy when there are no custom rules:

- Manager approval above Rs 0.
- Finance approval above Rs 5,000.

Important nuance:

- Adding custom rules replaces the default policy for that tenant.
- Auto-approve and auto-reject are not wired into the mobile UI/backend flow
  yet.

## 15. Where invoices are stored today

This is the exact answer to "S3 is not connected, so where are invoices
currently being stored?"

### Before upload: on the phone

When a worker takes a photo:

- The photo is compressed to max dimension 2048 px and JPEG quality 80.
- It is saved inside the Android app's private documents directory:
  `.../invoices/<uuid>.jpg`
- The capture metadata is stored in local Hive boxes.
- The Queue tab reads from this local Hive storage.

This means the phone can hold unsynced captures offline.

### After upload: on the server

The backend has a local storage layer, not S3.

In code:

- `backend/internal/storage/storage.go` implements local filesystem storage.
- It uses logical keys such as:
  `uploads/<tenant_id>/<invoice_id>/<filename>`
- The code still calls this variable `s3Key` in several places, but it is not
  actually S3 today.

In production compose:

- API container has `STORAGE_ROOT=/data/storage`.
- Docker volume `storage_data` is mounted at `/data/storage`.
- So uploaded files live in the EC2 Docker volume backing `/data/storage`.

The database stores:

- Invoice metadata.
- Document rows.
- Document version rows.
- Logical storage key.
- SHA-256 hash.
- File size/original filename metadata.
- Audit trail events.

The actual image bytes are on disk in the storage volume, not inside Postgres.

### When owner views a document

Owner app downloads the image from backend and stores a local copy in the app's
private documents area:

`.../downloads/<invoice_id>_<document_id>_latest.jpg`

### What this means operationally

Pros:

- Simple.
- Works on one EC2 instance.
- No S3 bill/setup needed yet.

Risks:

- Needs server backup plan.
- Not ideal for multiple API servers.
- If the Docker volume/EC2 disk is lost without backup, document images are at
  risk.
- S3/GCS should be added before scaling or treating this as production-grade
  long-term archive.

Founder-friendly version:

> "Right now the invoice images are saved on the pilot server's disk volume,
> with metadata in Postgres. S3 is the natural next step for durable, backed-up
> document storage."

## 16. OCR and AI status

What exists:

- Python worker has AWS Textract AnalyzeExpense integration.
- OCR preview endpoint exists for the mobile review screen.
- Backend workflow can run OCR after upload.
- Supporting documents can be OCR-matched against the invoice.
- If OCR is unavailable/inconclusive, the system raises an exception instead
  of pretending it matched.

What to be careful about:

- OCR should not be positioned as perfect.
- Worker must verify any OCR-filled fields.
- OCR preview only reads the first invoice page in the mobile flow.
- Current production compose shows the API storage volume mounted into the API
  container, but not visibly mounted into the `ocr-worker` container. Because
  the OCR worker reads files from local storage path, verify the live deployment
  before demoing OCR as fully working. It may have Textract credentials but
  still fail to see local files unless storage is shared with the worker.
- OpenAI-based AI discrepancy resolution is coded, but it depends on OpenAI
  package/key availability and should be treated as optional/fail-closed.

Best demo phrasing:

> "OCR is already integrated as an assistive layer, but the product is designed
> to remain usable even when OCR fails. Manual verification is still the source
> of truth in the pilot."

## 17. Backend workflow: what happens after upload

After an invoice is uploaded:

1. Backend creates invoice row.
2. Backend stores the primary document image.
3. Backend creates document and document version rows.
4. Backend writes audit event.
5. Backend starts Temporal workflow.
6. OCR extracts invoice data if available.
7. Validation compares extracted data against submitted invoice data.
8. If validation fails, exception is raised.
9. Approval rules determine whether manager/finance approval is required.
10. Approved invoice eventually becomes archived.

Supporting documents:

1. Supporting document is uploaded against existing invoice.
2. Backend stores file and document/version row.
3. For non-invoice-page documents, backend starts document matching workflow.
4. OCR extracts lightweight header fields.
5. Matching checks invoice number, buyer GSTIN, and amount where available.
6. Mismatch or inconclusive OCR raises an exception.

Periodic ledger scan:

- Flags invoices that are too old and still have no supporting document.
- Detects missing invoice numbers in numeric sequences.
- Creates reviewable exceptions/missing-number rows rather than silently
  failing.

## 18. What is currently working

Based on code and `task.md`, these are built:

- Login with JWT.
- Role-based navigation.
- Worker capture flow.
- Multi-page invoice capture.
- Buyer search/autocomplete.
- OCR preview endpoint and UI cues.
- Manual invoice detail entry.
- Cash/Credit and payment terms.
- Branch/store picker for buyers with branches.
- Buyer-specific supporting document checklist.
- Offline queue with retry/resume.
- Upload of primary invoice and supporting documents.
- Document storage on backend local volume.
- Owner dashboard.
- Invoice list/search.
- Invoice detail view.
- In-app document viewer.
- Document version history for manager/admin.
- Exceptions.
- Disputes.
- Credit note upload.
- Gate entry metadata and automatic short-receipt dispute.
- Alerts tab and badge.
- Overdue credit invoices in alerts.
- Invoice approval/rejection flow.
- Audit trail.
- Receivables summary.
- Buyer receivables drill-down.
- Payment recording and over-balance rejection.
- Payment history in invoice detail.
- Sales report endpoint/section.
- Principals and series management.
- Buyers, sales channel, credit terms, branch management.
- Buyer document requirement management.
- Approval rule management.
- Production Docker deployment stack.
- Release APK built.

## 19. What is not done / not production-ready yet

Be transparent about these:

- S3 is not connected for document storage.
- No push/SMS/WhatsApp/email alerts.
- No password change/reset.
- No MFA.
- No photo quality checks for blur/darkness/cut-off edges.
- No duplicate invoice warning before submit.
- No capture draft recovery if the app is killed mid-capture.
- No alert filters or alert aging UI.
- No delete endpoint for buyer document requirements.
- OCR should be verified end-to-end on the live server before positioning it as
  reliable.
- APK still needs to be sideloaded onto the actual pilot device if not already
  done.
- The old `frontend/` dashboard is abandoned and should not be demoed as the
  current product.
- iOS/web/desktop builds exist only as Flutter scaffolding; the pilot target is
  Android only.
- Local filesystem document storage is fine for single-server pilot, but not
  the right long-term archive/storage design.

## 20. Suggested founder demo script

### Opening, 2 minutes

Say:

> "The problem is that invoices, gate entries, GRNs, disputes, and credit
> notes are spread across paper, WhatsApp, memory, and delayed follow-up. This
> app makes the invoice a central record: photo, data, supporting proof,
> alerts, approval, receivable, and payment trail."

Show:

- App login.
- Role-based home.

### Worker flow, 8 minutes

Show:

1. Worker Capture tab.
2. Capture invoice photo.
3. Review invoice page.
4. Add another page.
5. Buyer search/GSTIN lookup.
6. Cash/Credit + terms.
7. Supporting document checklist.
8. Submit.
9. Queue status.
10. My Invoices status.

Say:

> "Even if the worker is offline, the capture is not lost. It sits in the
> queue and syncs later."

### Owner flow, 10 minutes

Show:

1. Dashboard.
2. Sales section.
3. Recent invoices.
4. All Invoices search.
5. Invoice Detail.
6. Document viewer.
7. Exceptions.
8. Raise dispute.
9. Gate entry details.
10. Audit trail.

Say:

> "This is where the founder/manager sees what needs attention, not just what
> was uploaded."

### Receivables, 5 minutes

Show:

1. Receivables tab.
2. Outstanding and overdue totals.
3. Buyer drill-down.
4. Record payment.
5. Payment history in invoice detail.

Say:

> "For credit sales, the app does not stop at capture. It becomes a collection
> tracker."

### Admin setup, 5 minutes

Show More tab:

1. Principals & series.
2. Buyers.
3. Buyer document requirements.
4. Approval rules.

Say:

> "The app is configurable around the real distributor business: brands,
> series, buyer branches, buyer-specific document proofs, and approval rules."

### Close, 2 minutes

Say:

> "The pilot is usable now for internal testing on one server. The next
> hardening steps are S3 storage, proactive notifications, password/MFA, photo
> quality checks, duplicate detection, and field testing on the actual device."

## 21. Founder FAQ

### Is this a public SaaS product?

No. It is built for one internal Meridian pilot.

### Does it replace accounting software?

No. It does not replace Tally/ERP/accounting. It creates a controlled digital
invoice/document/receivable workflow that could later integrate with accounting.

### Are invoices stored in S3?

No. Today they are stored on the pilot server's local Docker storage volume at
`/data/storage`, with metadata in Postgres. S3 should be added for durable
production storage.

### What happens if the worker has no internet?

The phone saves the capture locally. The Queue tab syncs later.

### Does OCR fill the invoice automatically?

It tries to fill some fields, but the worker must verify everything. The app
works manually even if OCR fails.

### Will the founder receive WhatsApp/SMS alerts?

Not today. Alerts are inside the app. WhatsApp/SMS/email/push would be a next
integration.

### Can managers see the actual invoice image?

Yes. Invoice detail has document viewing. Images download from the backend and
open in a zoomable viewer.

### Can someone see who changed or uploaded what?

Yes. The audit trail records invoice events, uploads, approvals, disputes,
payments, and gate-entry metadata.

### Can duplicate invoice uploads happen?

The backend has some idempotency around invoice number during retry, but there
is no friendly duplicate-warning screen before submit yet.

### Can a payment above balance be recorded?

No. The backend rejects payments that exceed remaining invoice balance.

### Can old document versions be seen?

Manager/Admin can view document version history. New versions are appended
instead of overwriting previous versions.

### Can buyer document requirements be removed?

Not yet. They can be added/updated, but delete is a known gap.

### What should be built next?

Suggested next priorities:

1. S3 document storage with backups/lifecycle policy.
2. Push/WhatsApp/SMS alerts for exceptions, disputes, and overdue invoices.
3. Password reset/change and MFA.
4. Photo quality checks.
5. Duplicate invoice warning.
6. Capture draft recovery.
7. Alert filters and aging.
8. Field test with real workers and real buyer documents.

## 22. If the demo breaks

Quick troubleshooting:

- Login fails: check Server Settings URL.
- Camera fails: check Android camera permission.
- Upload fails: check Queue tab and network.
- Owner screen fails: check user role and token.
- Documents fail to open: server file may not exist in storage volume or API
  cannot read it.
- OCR does not fill fields: continue manually; this is expected fallback.
- Alerts are empty: there may simply be no open exceptions/disputes/overdue
  invoices.
- Receivables empty: only CREDIT invoices with unpaid balances appear.

## 23. Code map for your memory

Mobile:

- App routes: `mobile/lib/app.dart`
- Worker shell / owner shell: `mobile/lib/core/navigation/app_shell.dart`
- Capture home: `mobile/lib/features/home/home_screen.dart`
- Camera: `mobile/lib/features/capture/camera_screen.dart`
- Review invoice: `mobile/lib/features/capture/review_screen.dart`
- Supporting docs: `mobile/lib/features/capture/checklist_screen.dart`
- Offline queue sync: `mobile/lib/features/capture/sync_service.dart`
- Local bundle model: `mobile/lib/core/models/bundle.dart`
- Local image compression: `mobile/lib/core/storage/image_store.dart`
- My Invoices: `mobile/lib/features/capture/my_invoices_screen.dart`
- Owner dashboard: `mobile/lib/features/owner/owner_dashboard_screen.dart`
- Owner invoices/search: `mobile/lib/features/owner/owner_invoices_screen.dart`
- Invoice detail: `mobile/lib/features/owner/invoice_detail_screen.dart`
- Alerts: `mobile/lib/features/owner/alerts_screen.dart`
- Receivables: `mobile/lib/features/receivables/receivables_screen.dart`
- Record payment: `mobile/lib/features/receivables/record_payment_sheet.dart`
- More/admin entry: `mobile/lib/features/owner/more_screen.dart`
- Buyers: `mobile/lib/features/admin/buyers_screen.dart`
- Principals/series: `mobile/lib/features/admin/principals_screen.dart`
- Buyer requirements: `mobile/lib/features/admin/buyer_requirements_screen.dart`
- Approval rules: `mobile/lib/features/admin/rules_screen.dart`
- Server URL config: `mobile/lib/core/config/server_config.dart`

Backend:

- Route table: `backend/internal/api/api.go`
- Mobile handlers: `backend/internal/api/mobile_handlers.go`
- Owner/dispute/gate entry handlers: `backend/internal/api/owner_handlers.go`
- Receivables/payment/report handlers:
  `backend/internal/api/receivables_handlers.go`
- Master data handlers: `backend/internal/api/master_data_handlers.go`
- Storage layer: `backend/internal/storage/storage.go`
- Database repository: `backend/internal/db/db.go`
- Invoice workflow: `backend/internal/workflow/workflows.go`
- Supporting document workflow: `backend/internal/workflow/ledger_workflow.go`
- Document matching: `backend/internal/workflow/ledger_activities.go`
- Ledger scans: `backend/internal/ledgerscan/scanner.go`
- OCR worker: `backend/python_worker/activities.py`
- Production deploy: `deploy/docker-compose.prod.yml`

