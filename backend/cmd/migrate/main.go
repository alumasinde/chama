// Command migrate applies the embedded forward-only migrations.
package main

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"strconv"

	"github.com/golang-migrate/migrate/v4"
	pgxv5 "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/chama/chama/backend/migrations"
)

const defaultDSN = "postgres://postgres@localhost:5434/chama?sslmode=disable"

func main() {
	command := "up"
	if len(os.Args) > 1 {
		command = os.Args[1]
	}
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = defaultDSN
	}

	source, err := iofs.New(migrations.FS, ".")
	if err != nil {
		fail(err)
	}
	conn, err := sql.Open("pgx", dsn)
	if err != nil {
		fail(err)
	}
	driver, err := pgxv5.WithInstance(conn, &pgxv5.Config{})
	if err != nil {
		fail(err)
	}
	m, err := migrate.NewWithInstance("iofs", source, "pgx5", driver)
	if err != nil {
		fail(err)
	}

	switch command {
	case "up":
		if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
			fail(err)
		}
		fmt.Println("migrations: up to date")
	case "down":
		steps := 1
		if len(os.Args) > 2 {
			n, err := strconv.Atoi(os.Args[2])
			if err != nil || n < 1 {
				fail(fmt.Errorf("down takes a positive step count"))
			}
			steps = n
		}
		if err := m.Steps(-steps); err != nil && !errors.Is(err, migrate.ErrNoChange) {
			fail(err)
		}
		fmt.Printf("migrations: rolled back %d\n", steps)
	case "version":
		version, dirty, err := m.Version()
		if err != nil {
			fail(err)
		}
		fmt.Printf("version=%d dirty=%t\n", version, dirty)
	default:
		fail(fmt.Errorf("usage: migrate [up|down [n]|version]"))
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "migrate:", err)
	os.Exit(1)
}
