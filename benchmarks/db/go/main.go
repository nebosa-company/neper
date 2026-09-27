// The e.db benchmark's workload in Go, with each database's standard Go driver: pgx for
// PostgreSQL, go-sql-driver/mysql, and for SQLite mattn/go-sqlite3 against the system library
// where cgo is available (Linux) or modernc.org/sqlite, a translation of SQLite to Go, where it
// is not (Windows without gcc).
//
//	bench-go sqlite <file> <rows> <lookups>
//	bench-go postgresql <conninfo> <rows> <lookups>
//	bench-go mysql <port> <rows> <lookups>
//
// Same phases, table and output line as benchmarks/db/src/workload.e and c/bench.c.
package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strconv"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/jackc/pgx/v5"
)

var names = []string{"alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
	"india", "juliett", "kilo", "lima", "mike", "november", "oscar", "papa"}

const create = "CREATE TABLE bench(id BIGINT PRIMARY KEY, name VARCHAR(32) NOT NULL, score DOUBLE PRECISION NOT NULL)"

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "bench-go:", err)
		os.Exit(1)
	}
}

// database/sql drivers: SQLite and MySQL.
func runSQL(driver, dsn, placeholder string, rows, lookups int64) (int64, int64, int64) {
	db, err := sql.Open(driver, dsn)
	check(err)
	db.SetMaxOpenConns(1)
	defer db.Close()
	_, err = db.Exec("DROP TABLE IF EXISTS bench")
	check(err)
	_, err = db.Exec(create)
	check(err)

	t0 := time.Now()
	tx, err := db.Begin()
	check(err)
	insert, err := tx.Prepare(fmt.Sprintf("INSERT INTO bench VALUES (%s, %s, %s)", placeholder, placeholder, placeholder))
	check(err)
	for i := int64(0); i < rows; i++ {
		_, err = insert.Exec(i, names[i%16], float64(i)*0.5)
		check(err)
	}
	check(insert.Close())
	check(tx.Commit())
	insertNs := time.Since(t0).Nanoseconds()

	t0 = time.Now()
	result, err := db.Query("SELECT id, name, score FROM bench")
	check(err)
	var count, sum, bytes int64
	for result.Next() {
		var id int64
		var name string
		var score float64
		check(result.Scan(&id, &name, &score))
		sum += id
		bytes += int64(len(name))
		count++
	}
	check(result.Err())
	scanNs := time.Since(t0).Nanoseconds()
	if count != rows || sum != rows*(rows-1)/2 {
		check(fmt.Errorf("scan read %d rows", count))
	}

	t0 = time.Now()
	lookup, err := db.Prepare("SELECT name, score FROM bench WHERE id = " + placeholder)
	check(err)
	found := int64(0)
	for j := int64(0); j < lookups; j++ {
		var name string
		var score float64
		if lookup.QueryRow(j*7919%rows).Scan(&name, &score) == nil {
			found++
		}
	}
	check(lookup.Close())
	lookupNs := time.Since(t0).Nanoseconds()
	if found != lookups {
		check(fmt.Errorf("found %d of %d", found, lookups))
	}
	return insertNs, scanNs, lookupNs
}

// PostgreSQL through pgx's own API: binary protocol and prepared statements, rows read as they
// arrive.
func runPostgres(conninfo string, rows, lookups int64) (int64, int64, int64) {
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, conninfo)
	check(err)
	defer conn.Close(ctx)
	_, err = conn.Exec(ctx, "DROP TABLE IF EXISTS bench")
	check(err)
	_, err = conn.Exec(ctx, create)
	check(err)

	t0 := time.Now()
	tx, err := conn.Begin(ctx)
	check(err)
	_, err = tx.Prepare(ctx, "ins", "INSERT INTO bench VALUES ($1, $2, $3)")
	check(err)
	for i := int64(0); i < rows; i++ {
		_, err = tx.Exec(ctx, "ins", i, names[i%16], float64(i)*0.5)
		check(err)
	}
	check(tx.Commit(ctx))
	insertNs := time.Since(t0).Nanoseconds()

	t0 = time.Now()
	result, err := conn.Query(ctx, "SELECT id, name, score FROM bench")
	check(err)
	var count, sum, bytes int64
	for result.Next() {
		var id int64
		var name string
		var score float64
		check(result.Scan(&id, &name, &score))
		sum += id
		bytes += int64(len(name))
		count++
	}
	check(result.Err())
	scanNs := time.Since(t0).Nanoseconds()
	if count != rows || sum != rows*(rows-1)/2 {
		check(fmt.Errorf("scan read %d rows", count))
	}

	t0 = time.Now()
	_, err = conn.Prepare(ctx, "sel", "SELECT name, score FROM bench WHERE id = $1")
	check(err)
	found := int64(0)
	for j := int64(0); j < lookups; j++ {
		var name string
		var score float64
		if conn.QueryRow(ctx, "sel", j*7919%rows).Scan(&name, &score) == nil {
			found++
		}
	}
	lookupNs := time.Since(t0).Nanoseconds()
	if found != lookups {
		check(fmt.Errorf("found %d of %d", found, lookups))
	}
	return insertNs, scanNs, lookupNs
}

func main() {
	if len(os.Args) < 5 {
		check(fmt.Errorf("usage: bench-go sqlite|postgresql|mysql <location> <rows> <lookups>"))
	}
	driver, location := os.Args[1], os.Args[2]
	rows, err := strconv.ParseInt(os.Args[3], 10, 64)
	check(err)
	lookups, err := strconv.ParseInt(os.Args[4], 10, 64)
	check(err)
	var insertNs, scanNs, lookupNs int64
	switch driver {
	case "sqlite":
		insertNs, scanNs, lookupNs = runSQL(sqliteDriver, location, "?", rows, lookups)
	case "postgresql":
		insertNs, scanNs, lookupNs = runPostgres(location, rows, lookups)
	default:
		insertNs, scanNs, lookupNs = runSQL("mysql", "root@tcp(127.0.0.1:"+location+")/neper", "?", rows, lookups)
	}
	fmt.Printf("%s insert_ns=%d scan_ns=%d lookup_ns=%d\n", driver, insertNs, scanNs, lookupNs)
}
