package api

import "testing"

func TestLoginRateLimiter_AllowsManySuccessfulAttempts(t *testing.T) {
	l := newLoginRateLimiter()
	// 15 successive "successful" checks for the same key must never themselves
	// exhaust the limiter -- only recordFailure should count toward the cap.
	for i := 0; i < 15; i++ {
		if !l.allow("1.2.3.4") {
			t.Fatalf("attempt %d: allow() returned false; allow() must not be consumed by successful logins", i)
		}
	}
}

func TestLoginRateLimiter_BlocksAfterTenFailures(t *testing.T) {
	l := newLoginRateLimiter()
	for i := 0; i < loginRateLimitMaxAttempts; i++ {
		l.recordFailure("5.6.7.8")
	}
	if l.allow("5.6.7.8") {
		t.Fatal("allow() returned true after 10 recorded failures; expected false")
	}
}
