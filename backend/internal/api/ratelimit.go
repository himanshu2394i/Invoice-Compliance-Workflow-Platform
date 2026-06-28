// ratelimit.go
package api

import (
	"sync"
	"time"
)

const (
	loginRateLimitWindow      = 5 * time.Minute
	loginRateLimitMaxAttempts = 10
)

// loginRateLimiter is a simple in-memory sliding-window limiter keyed by
// client IP. In-memory is fine as long as the API runs as a single instance
// (see internal/storage's local-disk comment -- the same constraint applies
// here); a multi-replica deploy would need this backed by something shared
// like Redis instead.
type loginRateLimiter struct {
	mu       sync.Mutex
	attempts map[string][]time.Time
}

func newLoginRateLimiter() *loginRateLimiter {
	return &loginRateLimiter{attempts: make(map[string][]time.Time)}
}

// allow records an attempt for key and reports whether it's still within the
// limit. Only failed/attempted logins should call this -- it's a brute-force
// guard, not a general API throttle.
func (l *loginRateLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-loginRateLimitWindow)

	kept := l.attempts[key][:0]
	for _, t := range l.attempts[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}

	if len(kept) >= loginRateLimitMaxAttempts {
		l.attempts[key] = kept
		return false
	}
	l.attempts[key] = append(kept, now)
	return true
}
