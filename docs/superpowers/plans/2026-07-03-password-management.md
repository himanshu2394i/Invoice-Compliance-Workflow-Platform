# Password Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** add pilot-ready self-service password change and admin staff password reset.

**Architecture:** Keep auth behavior in the existing Go API and repository layer. Mobile calls the same endpoints from `AuthNotifier` and exposes simple dialogs from Settings.

**Tech Stack:** Go `net/http`, Postgres/pgx repository, bcrypt helper in `internal/auth`, Flutter/Riverpod/Dio.

## Global Constraints

- No plaintext passwords in responses, logs, audit payloads, or tests.
- Password changes update existing `users.password_hash`; no schema migration is needed.
- Admin reset is scoped to the admin's own organization.
- Mobile services keep the established `Dio?` constructor dependency injection pattern.
- Verify backend with `go test ./internal/api -run 'Test(ChangePassword|AdminResetPassword)' -count=1`, `go build ./...`, and `go vet ./...`.
- Verify mobile with targeted Flutter tests and analyzer baseline.

---

### Task 1: Backend Auth Endpoints

**Files:**
- Modify: `backend/internal/api/auth_integration_test.go`
- Modify: `backend/internal/api/auth_handlers.go`
- Modify: `backend/internal/api/api.go`
- Modify: `backend/internal/db/db.go`

**Interfaces:**
- Produces: `POST /api/v1/auth/change-password`
- Produces: `POST /api/v1/auth/users/reset-password`
- Produces: `Repository.GetUserByID(ctx, orgID, userID)` and `Repository.UpdateUserPassword(ctx, orgID, userID, passwordHash)`

- [x] Write failing integration tests proving current-password rejection, successful password change, admin reset by staff email, and worker reset denial.
- [x] Run the targeted backend test and confirm it fails because the routes do not exist.
- [x] Add repository helpers for tenant-scoped user lookup and password hash update.
- [x] Add request handlers with password policy validation and bcrypt hashing.
- [x] Register routes with correct auth/role gates.
- [x] Re-run the targeted backend test until it passes.

### Task 2: Mobile Auth Service + Settings UI

**Files:**
- Modify: `mobile/lib/core/api/endpoints.dart`
- Modify: `mobile/lib/features/auth/auth_provider.dart`
- Modify: `mobile/lib/features/settings/settings_screen.dart`
- Modify: `mobile/test/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: `AuthNotifier.changePassword(currentPassword, newPassword)`
- Consumes: `AuthNotifier.resetStaffPassword(email, newPassword)`

- [x] Add failing AuthNotifier tests for the two API calls.
- [x] Run the targeted auth test and confirm it fails because methods/endpoints do not exist.
- [x] Add endpoint constants.
- [x] Add AuthNotifier methods that post the exact JSON payloads.
- [x] Convert Settings screen to a Riverpod consumer and add change/reset dialogs.
- [x] Re-run targeted mobile tests until they pass.

### Task 3: Documentation + Verification

**Files:**
- Modify: `task.md`

- [x] Mark the Phase 8 password-change/reset item complete only after verification.
- [x] Run backend build/vet.
- [x] Run mobile analyzer baseline check.
- [x] Summarize remaining security gaps: MFA and token revocation are still future work.
