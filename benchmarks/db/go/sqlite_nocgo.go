//go:build !cgo

package main

// Without cgo (Windows with no gcc), modernc.org/sqlite: SQLite's C source translated to Go, so
// the engine is SQLite's but its code is not the system library's.
import _ "modernc.org/sqlite"

const sqliteDriver = "sqlite"
