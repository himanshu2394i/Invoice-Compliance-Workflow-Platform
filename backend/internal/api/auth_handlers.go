// auth_handlers.go
package api

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"net"
	"net/http"
	"os"
	"strings"
	"unicode"

	"github.com/himanshu2394i/invoice-saas/internal/auth"
)

type contextKey string

const claimsContextKey contextKey = "claims"

// requireAuth verifies the Authorization: Bearer <token> header and injects the
// verified claims into the request context. This is the ONLY source of truth
// for tenant ID and role from here on -- nothing should trust a client-supplied
// X-Tenant-ID header or a client-supplied "role" field again.
func requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		token := strings.TrimPrefix(header, "Bearer ")
		if token == "" || token == header {
			writeError(w, http.StatusUnauthorized, "Missing or malformed Authorization header")
			return
		}

		claims, err := auth.ParseToken(token)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "Invalid or expired token")
			return
		}

		ctx := context.WithValue(r.Context(), claimsContextKey, claims)
		next(w, r.WithContext(ctx))
	}
}

// requireRole further restricts a route to a fixed set of roles, beyond just
// being authenticated. Must be applied after requireAuth has populated claims.
func requireRole(roles ...string) func(http.HandlerFunc) http.HandlerFunc {
	allowed := make(map[string]bool, len(roles))
	for _, role := range roles {
		allowed[role] = true
	}
	return func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			claims := claimsFromContext(r.Context())
			if claims == nil || !allowed[claims.Role] {
				writeError(w, http.StatusForbidden, "Your role is not permitted to perform this action")
				return
			}
			next(w, r)
		}
	}
}

func claimsFromContext(ctx context.Context) *auth.Claims {
	claims, _ := ctx.Value(claimsContextKey).(*auth.Claims)
	return claims
}

// requireSeedToken gates the admin bootstrap endpoint. With no SEED_SETUP_TOKEN
// configured it stays open in dev (today's frictionless seed-and-go workflow)
// but is hard-disabled once APP_ENV=production -- there's no safe default that
// keeps it open in production. Configuring a token lets a real deploy still use
// it once, deliberately, by supplying X-Setup-Token.
func requireSeedToken(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		configured := os.Getenv("SEED_SETUP_TOKEN")
		if configured == "" {
			if os.Getenv("APP_ENV") == "production" {
				writeError(w, http.StatusForbidden, "Admin seeding is disabled in production")
				return
			}
			next(w, r)
			return
		}
		supplied := r.Header.Get("X-Setup-Token")
		if subtle.ConstantTimeCompare([]byte(supplied), []byte(configured)) != 1 {
			writeError(w, http.StatusForbidden, "Invalid or missing setup token")
			return
		}
		next(w, r)
	}
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

type AdminResetPasswordRequest struct {
	Email       string `json:"email"`
	NewPassword string `json:"new_password"`
}

func validatePilotPassword(password string) string {
	if len([]rune(password)) < 10 {
		return "New password must be at least 10 characters long"
	}
	hasLetter := false
	hasDigit := false
	for _, r := range password {
		if unicode.IsLetter(r) {
			hasLetter = true
		}
		if unicode.IsDigit(r) {
			hasDigit = true
		}
	}
	if !hasLetter || !hasDigit {
		return "New password must include at least one letter and one number"
	}
	return ""
}

// clientIP extracts the request's IP, dropping the port. There's no reverse
// proxy in front of this API yet -- if one is added, this must start reading
// X-Forwarded-For instead, but only because the proxy can be trusted to set
// it; trusting that header straight from the client would let an attacker
// fake a fresh IP on every request and bypass the limiter entirely.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	ip := clientIP(r)
	if !s.loginLimiter.allow(ip) {
		writeError(w, http.StatusTooManyRequests, "Too many login attempts. Try again later.")
		return
	}

	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	user, err := s.Repo.GetUserByEmail(r.Context(), req.Email)
	if err != nil {
		s.loginLimiter.recordFailure(ip)
		writeError(w, http.StatusUnauthorized, "Invalid email or password")
		return
	}
	if !auth.CheckPassword(user.PasswordHash, req.Password) {
		s.loginLimiter.recordFailure(ip)
		writeError(w, http.StatusUnauthorized, "Invalid email or password")
		return
	}

	token, err := auth.GenerateToken(user.ID, user.OrganizationID, user.Email, user.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to issue token")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"token": token,
		"user": map[string]string{
			"id":              user.ID,
			"email":           user.Email,
			"full_name":       user.FullName,
			"role":            user.Role,
			"organization_id": user.OrganizationID,
		},
	})
}

func (s *Server) handleChangePassword(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "Invalid or expired token")
		return
	}

	var req ChangePasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	req.CurrentPassword = strings.TrimSpace(req.CurrentPassword)
	req.NewPassword = strings.TrimSpace(req.NewPassword)
	if req.CurrentPassword == "" || req.NewPassword == "" {
		writeError(w, http.StatusBadRequest, "current_password and new_password are required")
		return
	}
	if msg := validatePilotPassword(req.NewPassword); msg != "" {
		writeError(w, http.StatusBadRequest, msg)
		return
	}
	if req.CurrentPassword == req.NewPassword {
		writeError(w, http.StatusBadRequest, "New password must be different from the current password")
		return
	}

	user, err := s.Repo.GetUserByID(r.Context(), claims.OrganizationID, claims.UserID)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "Invalid or expired token")
		return
	}
	if !auth.CheckPassword(user.PasswordHash, req.CurrentPassword) {
		writeError(w, http.StatusUnauthorized, "Current password is incorrect")
		return
	}
	hash, err := auth.HashPassword(req.NewPassword)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to update password")
		return
	}
	if err := s.Repo.UpdateUserPassword(r.Context(), claims.OrganizationID, user.ID, hash); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to update password")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status": "password_changed",
	})
}

func (s *Server) handleAdminResetPassword(w http.ResponseWriter, r *http.Request) {
	claims := claimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "Invalid or expired token")
		return
	}

	var req AdminResetPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	email := strings.TrimSpace(req.Email)
	newPassword := strings.TrimSpace(req.NewPassword)
	if email == "" || newPassword == "" {
		writeError(w, http.StatusBadRequest, "email and new_password are required")
		return
	}
	if msg := validatePilotPassword(newPassword); msg != "" {
		writeError(w, http.StatusBadRequest, msg)
		return
	}

	target, err := s.Repo.GetUserByEmail(r.Context(), email)
	if err != nil || target.OrganizationID != claims.OrganizationID {
		writeError(w, http.StatusNotFound, "User not found")
		return
	}
	hash, err := auth.HashPassword(newPassword)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to reset password")
		return
	}
	if err := s.Repo.UpdateUserPassword(r.Context(), claims.OrganizationID, target.ID, hash); err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to reset password")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status": "password_reset",
		"email":  target.Email,
		"role":   target.Role,
	})
}
