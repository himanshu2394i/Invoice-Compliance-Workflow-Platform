# Mobile Navigation, Product Features, and Security Design

Date: 2026-07-01

## Approved Scope

This design covers the next mobile-app pass for Meridian Invoice Capture. The user approved the product and security suggestions with these changes:

- Do not add worker batch mode.
- Add an admin/manager search bar for finding a specific invoice.
- Do not delete old data yet. Retention remains "keep everything" until the policy is revisited.

## Goals

1. Stop accidental app exits when users press the Android hardware back button.
2. Add consistent visible back buttons across mobile screens.
3. Improve invoice lookup for admin/manager users.
4. Prepare the product roadmap for worker efficiency, alerts, approvals, and security compliance without overbuilding this pass.

## Navigation Design

The app will use a shared back-navigation policy instead of page-by-page custom behavior.

Every non-root screen should have a visible back affordance in the app bar. Android hardware back should follow the same logical route:

- Capture review and checklist follow the existing capture-step flow.
- Queue returns to home.
- My invoices returns to home.
- Alerts returns to home.
- Owner dashboard returns to home.
- Owner invoices returns to owner dashboard.
- Invoice detail returns to the previous route when available, otherwise owner invoices.
- Admin buyer requirements returns to owner dashboard.
- Admin rules returns to owner dashboard.
- Settings returns to the previous route when available, otherwise home.

Home is the only authenticated root. Pressing Android back once on home should show a short "Press back again to exit" message. Pressing back again within a short window exits the app. Login may keep normal platform behavior.

## Product Feature Design

### Worker Experience

The worker flow should stay focused on fast, accurate capture:

- Keep live OCR autofill for invoice fields.
- Show clear confidence or review cues for fields filled by OCR.
- Add image quality checks later for blur, dark photos, and missing document corners.
- Warn before submit when an invoice looks duplicated by invoice number, buyer, GSTIN, amount, or date.
- Preserve draft recovery if the app closes during capture.
- Keep buyer-specific document requirements so workers only see proofs that matter for that buyer.

Worker batch mode is explicitly out of scope.

### Admin and Manager Experience

Admin/manager users need faster exception handling and lookup:

- Add a search bar on invoice-list style screens for invoice number, buyer name, GSTIN, amount, or status.
- Keep alert inbox for OCR mismatch, missing proof, GST mismatch, duplicate, approval pending, and dispute events.
- Add filters and aging later so urgent exceptions are easier to spot.
- Keep buyer master-data management for GSTIN and required receiving proofs.
- Keep document version history and manager/admin-only replacement behavior.

## Security and Compliance Design

The security direction is to harden the pilot toward a private internal business app, not a public SaaS product.

Immediate priorities:

- Keep role-based access control tight across worker, reviewer, manager, finance, and admin.
- Add password-change/reset support before handing devices to real staff.
- Add MFA for admin/manager users when the pilot moves beyond solo testing.
- Store mobile tokens securely and avoid exposing sensitive invoice or buyer data in logs.
- Keep approval, upload, document replacement, dispute, and exception actions in audit history.
- Keep all data for now. No purge/delete workflow will be implemented until the retention policy is decided.

Compliance alignment:

- DPDP: document what personal data is processed, why it is needed, who can access it, and how breach handling will work.
- CERT-In: preserve useful logs, maintain time sync, define a security point of contact, and prepare an incident-reporting process.
- OWASP MASVS/ASVS: use these as practical checklists for mobile and API security controls.

## Error Handling

Back-navigation should never lose in-progress invoice data silently. Capture screens with unsaved work should continue using their existing confirmations or route-specific flow. On non-capture screens, back navigation should be immediate and predictable.

Search should handle empty, partial, and no-result states. It should not crash when offline; if a screen has cached data, search the cached list. If data requires the server, show the normal loading/error state.

## Testing

Mobile verification will include:

- `puro flutter analyze`, compared against `mobile/analysis_baseline.txt`.
- Widget tests or focused route/back helper tests where practical.
- Manual smoke checklist for Android hardware back behavior on home, queue, my invoices, alerts, owner screens, invoice detail, admin screens, settings, and capture screens.

Backend verification is not required for the navigation-only part. If invoice search requires backend query changes, run the relevant Go build/vet checks and focused tests.

## Out of Scope

- Worker batch mode.
- Data deletion, archival, or retention expiry.
- Push notifications, SMS, or email alerts.
- Public dashboard or abandoned `frontend/` work.
- Full legal/compliance certification.
