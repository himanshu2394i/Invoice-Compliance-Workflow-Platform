package auth

import (
	"errors"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const tokenTTL = 8 * time.Hour

// Claims carries the identity the rest of the backend trusts once a token has
// been verified: which organization (tenant), which user, and which role.
// Nothing downstream should ever trust a client-supplied tenant ID or role again.
type Claims struct {
	UserID         string `json:"user_id"`
	OrganizationID string `json:"organization_id"`
	Email          string `json:"email"`
	Role           string `json:"role"`
	jwt.RegisteredClaims
}

var (
	secretOnce sync.Once
	secret     []byte
)

func secretKey() []byte {
	secretOnce.Do(func() {
		if v := os.Getenv("JWT_SECRET"); v != "" {
			secret = []byte(v)
			return
		}
		if os.Getenv("APP_ENV") == "production" {
			log.Fatal("FATAL: JWT_SECRET is not set. Refusing to start in production with a guessable signing key.")
		}
		log.Println("WARNING: JWT_SECRET not set; using a fixed development-only signing key. Do not use this in production.")
		secret = []byte("dev-only-jwt-signing-key-do-not-ship-to-prod")
	})
	return secret
}

// ValidateSecretConfig forces the JWT_SECRET check above to run immediately.
// Call this once at process startup so a misconfigured production deploy
// fails before it ever binds a port, instead of on whichever request happens
// to trigger the first login or token verification.
func ValidateSecretConfig() {
	_ = secretKey()
}

// GenerateToken issues a signed JWT encoding the user's identity and role.
func GenerateToken(userID, organizationID, email, role string) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID:         userID,
		OrganizationID: organizationID,
		Email:          email,
		Role:           role,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(secretKey())
}

// ParseToken verifies signature and expiry and returns the embedded claims.
func ParseToken(tokenString string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return secretKey(), nil
	})
	if err != nil {
		return nil, err
	}
	if !token.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}
