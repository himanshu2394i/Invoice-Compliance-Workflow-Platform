# Password Management Design

**Goal:** add the minimum reliable password-management layer needed before real staff use: users can change their own password, and an ADMIN can reset a staff password.

## Current Reality

- Login exists through `POST /api/v1/auth/login`.
- Users are seeded and stored in Postgres with bcrypt password hashes.
- There is no password change endpoint, no reset endpoint, and no mobile UI for changing a password.
- JWT tokens are stateless. For this pilot, changing a password will not invalidate already-issued tokens; staff continue using the current session and the new password applies to the next login.

## Scope

### Self-Service Change Password

- Route: `POST /api/v1/auth/change-password`
- Auth: any logged-in user.
- Body:

```json
{
  "current_password": "old-password",
  "new_password": "new-password"
}
```

- Behavior:
  - Verify the current password against the caller's stored bcrypt hash.
  - Reject weak passwords.
  - Reject a new password that is the same as the current password.
  - Store only a bcrypt hash.
  - Never return or log password values.

### Admin Staff Reset

- Route: `POST /api/v1/auth/users/reset-password`
- Auth: ADMIN only.
- Body:

```json
{
  "email": "worker@example.com",
  "new_password": "new-password"
}
```

- Behavior:
  - Find the user by email.
  - Ensure the target user belongs to the admin's organization.
  - Reject weak passwords.
  - Store only a bcrypt hash.
  - Return a small success payload with the target email and role.

## Password Policy

Pilot policy is intentionally simple and explainable:

- At least 10 characters.
- Must include at least one letter.
- Must include at least one number.

This accepts current pilot-style passwords like `Pilot@2026` while still blocking obvious short/default values.

## Mobile UX

- Add account security controls to the existing Settings screen.
- Logged-in users see a "Change Password" action.
- ADMIN users additionally see "Reset Staff Password".
- Forms use password fields and require confirmation before submitting.
- Success/failure is shown through snackbars.

## Non-Goals

- No email/SMS reset links.
- No forgot-password flow.
- No automatic token/session revocation yet.
- No MFA yet; it remains a later Phase 8 item.
