// Applies versioned SQL migrations from backend/db/migrations. Replaces the
// old apply-once backend/db/schema.sql (now deleted -- its content is
// migrations/000001_initial_schema.up.sql), which could bootstrap a fresh
// database but had no way to safely change one that already existed.
//
// Usage (run from the backend/ directory):
//
//	go run ./cmd/migrate up
//	go run ./cmd/migrate down 1
//	go run ./cmd/migrate version
//
// Migrations need DDL privileges (CREATE/ALTER/DROP TABLE), which the
// restricted app_user role deliberately does NOT have -- it only gets
// SELECT/INSERT/UPDATE/DELETE (see migrations/000001's own GRANT statements
// and migrations/000001's original comment on why app_user must never own anything
// or bypass RLS). So this tool defaults to a separate, privileged connection
// string (MIGRATIONS_DATABASE_URL), never the app_user one cmd/api and
// cmd/worker use.
package main

import (
	"errors"
	"fmt"
	"log"
	"os"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

func migrationsDatabaseURL() string {
	if v := os.Getenv("MIGRATIONS_DATABASE_URL"); v != "" {
		return v
	}
	return "postgres://admin:password@127.0.0.1:5432/invoice_saas?sslmode=disable"
}

func migrationsPath() string {
	if v := os.Getenv("MIGRATIONS_PATH"); v != "" {
		return v
	}
	return "file://db/migrations"
}

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Usage: migrate <up|down [n]|version|force <version>>")
	}

	m, err := migrate.New(migrationsPath(), migrationsDatabaseURL())
	if err != nil {
		log.Fatalf("Failed to initialize migrator: %v", err)
	}
	defer m.Close()

	switch os.Args[1] {
	case "up":
		err = m.Up()
	case "down":
		if len(os.Args) >= 3 {
			var n int
			fmt.Sscanf(os.Args[2], "%d", &n)
			err = m.Steps(-n)
		} else {
			err = m.Down()
		}
	case "version":
		version, dirty, vErr := m.Version()
		if vErr != nil {
			log.Fatalf("Failed to read version: %v", vErr)
		}
		fmt.Printf("version=%d dirty=%v\n", version, dirty)
		return
	case "force":
		if len(os.Args) < 3 {
			log.Fatal("Usage: migrate force <version>")
		}
		var version int
		fmt.Sscanf(os.Args[2], "%d", &version)
		err = m.Force(version)
	default:
		log.Fatalf("Unknown command: %s", os.Args[1])
	}

	if err != nil && !errors.Is(err, migrate.ErrNoChange) {
		log.Fatalf("Migration failed: %v", err)
	}
	log.Println("Done.")
}
