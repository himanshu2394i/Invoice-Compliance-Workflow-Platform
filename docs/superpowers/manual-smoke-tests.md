# Manual Smoke Tests (camera-dependent, not automatable in CI)

Run these on a real device or emulator with camera support before each release.
Auth, settings persistence, and offline-sync have automated widget-test coverage
— see `docs/superpowers/plans/2026-06-28-e2e-testing-cicd.md`. The screens below
need manual checks because they're either camera-dependent or not yet covered:

## Review screen, owner dashboard, gate-entry form, and dispute screens

These have **no automated widget tests yet** (the equivalent backend API routes
are covered by Go integration tests, but the Flutter UI for them isn't). Sanity-
check manually until they're added:

- [ ] Review screen: invoice fields editable, validation errors shown for bad GSTIN/amounts.
- [ ] Owner dashboard: stats and recent invoices render for an ADMIN/MANAGER login.
- [ ] Gate-entry form: submitting a short-receipt entry surfaces the resulting dispute in the UI.
- [ ] Dispute screens: list/detail/credit-note upload render and submit correctly.

## Camera capture (`mobile/lib/features/capture/camera_screen.dart`)

- [ ] Launch the app, log in, navigate to Home -> Capture.
- [ ] Camera preview renders live video (not a frozen/black frame).
- [ ] Crop guide overlay is visible and positioned over the preview.
- [ ] Tapping capture takes a photo and transitions to the Review screen.
- [ ] Captured photo is right-side-up regardless of device orientation at
      capture time (front/landscape/portrait).
- [ ] Retake works and replaces the previous photo, not appends to it.

## Document checklist (multi-page) (`mobile/lib/features/capture/checklist_screen.dart`)

- [ ] After capturing a primary invoice photo, the checklist shows the
      buyer's configured required document types (e.g. "Gate Entry /
      Discrepancy Note" for Vishal Mega Mart, per the seeded buyer doc
      requirements).
- [ ] Capturing a second page of the same document type shows "Add page 2"
      and both pages attach to the same `QueuedPhoto.documentType` group.

## Offline queue -> auto-sync (`mobile/lib/features/queue/queue_screen.dart`)

- [ ] Turn off WiFi/mobile data before capturing; complete a full
      capture+checklist flow. Bundle appears in the Queue screen as "pending."
- [ ] Re-enable connectivity. Bundle auto-transitions to "synced" within a
      few seconds (driven by `connectivity_plus`), without manually opening
      the Queue screen.
- [ ] Force a sync failure (e.g. point Settings at an unreachable server URL)
      and confirm the bundle shows "failed" with a visible error, not a silent
      drop.
