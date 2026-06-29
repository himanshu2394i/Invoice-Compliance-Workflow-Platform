package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/himanshu2394i/invoice-saas/internal/api"
	"github.com/himanshu2394i/invoice-saas/internal/auth"
	"github.com/himanshu2394i/invoice-saas/internal/db"
	"github.com/himanshu2394i/invoice-saas/internal/storage"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.temporal.io/sdk/client"
)

// databaseURL resolves the Postgres DSN from the environment. The default
// connects as the restricted app_user role (see
// backend/db/migrations/000001_initial_schema.up.sql) --
// NEVER connect application traffic as the 'admin' superuser, which Postgres
// always exempts from Row-Level Security regardless of policy configuration.
func databaseURL() string {
	if v := os.Getenv("DATABASE_URL"); v != "" {
		return v
	}
	return "postgres://app_user:app_user_dev_password@127.0.0.1:5432/invoice_saas"
}

// temporalHostPort resolves the Temporal frontend address from the
// environment, defaulting to the local dev address. Must be overridable
// because in docker-compose this server dials Temporal by service name
// (e.g. "temporal:7233"), not localhost.
func temporalHostPort() string {
	if v := os.Getenv("TEMPORAL_HOSTPORT"); v != "" {
		return v
	}
	return "127.0.0.1:7233"
}

// storageRoot resolves where uploaded document bytes are kept on disk. Swap
// internal/storage.Store for a real S3/GCS-backed implementation before
// running multiple API replicas -- a local directory only works as long as
// every request can land on the same machine/volume.
func storageRoot() string {
	if v := os.Getenv("STORAGE_ROOT"); v != "" {
		return v
	}
	return "./storage"
}

// corsAllowedOrigin resolves which origin the frontend is served from. The
// wildcard "*" default is fine for local dev but must never reach production
// -- ValidateSecretConfig-style enforcement isn't applied here because a
// missing origin degrades to "browsers reject cross-origin requests," not a
// security hole the way a missing signing key would.
func corsAllowedOrigin() string {
	if v := os.Getenv("CORS_ALLOWED_ORIGIN"); v != "" {
		return v
	}
	return "http://localhost:3000"
}

func corsMiddleware(allowedOrigin string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "*")
		w.Header().Set("Vary", "Origin")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	// Fail fast on missing/invalid secrets before connecting to anything else
	// -- a misconfigured production deploy should never bind a port.
	auth.ValidateSecretConfig()
	db.ValidateEncryptionConfig()

	temporalClient, err := client.Dial(client.Options{HostPort: temporalHostPort()})
	if err != nil {
		log.Fatalf("Unable to connect to Temporal: %v", err)
	}
	defer temporalClient.Close()
	log.Println("Connected to Temporal Cluster successfully.")

	pool, err := pgxpool.New(context.Background(), databaseURL())
	if err != nil {
		log.Fatalf("Unable to connect to PostgreSQL: %v", err)
	}
	defer pool.Close()
	repo := db.NewRepository(pool)
	log.Println("Connected to PostgreSQL successfully.")

	store, err := storage.NewLocalStore(storageRoot())
	if err != nil {
		log.Fatalf("Unable to initialize document storage: %v", err)
	}

	server := api.NewServer(repo, temporalClient, store)
	mux := http.NewServeMux()
	server.RegisterRoutes(mux)

	log.Println("Starting API server on :8000, allowing CORS from", corsAllowedOrigin())
	if err := http.ListenAndServe(":8000", corsMiddleware(corsAllowedOrigin(), mux)); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}
