//go:build cgo

package main

// With cgo, mattn/go-sqlite3 built with the `libsqlite3` tag binds the system SQLite -- the
// same library the Neper and C benchmarks use.
import _ "github.com/mattn/go-sqlite3"

const sqliteDriver = "sqlite3"
