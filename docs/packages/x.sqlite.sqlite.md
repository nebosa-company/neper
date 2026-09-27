# `x.sqlite.sqlite` — package specification

The SQLite driver for `e.db`. This is the separate package specification that
`modules.md` requires of every `x.*` package before it is written: upstream version,
targets, ownership and licensing boundary. Decision D1571.

## Upstream

- **API:** the SQLite 3 C interface, v2 entry points only (`sqlite3_open_v2`,
  `sqlite3_prepare_v2`, `sqlite3_close_v2`). The newest call bound is
  `sqlite3_close_v2`, so the floor is **3.7.14** (`sqlite3_libversion_number() >=
  3007014`). A lower version fails `open` with `db.Unsupported`.
- **Library, not source:** the package binds the host's own shared library. No SQLite
  source is vendored or compiled.

| Target | Library | Present because |
|---|---|---|
| x64 Windows | `winsqlite3.dll` (System32) | shipped with Windows 10 and later |
| x64 Linux | `libsqlite3.so.0` | the soname of every SQLite 3 distribution package |

Measured when the package was delivered: 3.51.1 on Windows 11 and 3.45.1 on Ubuntu 24.04.

## Modules

- `x.sqlite.capi` holds the raw `@import` declarations, one variant per OS
  (`capi.windows.e`, `capi.linux.e`). The two files differ only in the library name. It
  is the package's only foreign boundary.
- `x.sqlite.sqlite` is the driver. It is portable source over `capi`.

Binding is by `@import`, so the loader resolves every symbol eagerly at start-up. A
program that calls nothing in the package does not depend on the library (D128). A
program that does call it will not start on a host that lacks the library.

## Surface

```neper
type Detail = struct { code: i32, extended: i32, message: str }
error CannotOpen
error Failed
const MIN_VERSION: i32 = 3007014i32

fn version() -> i32
fn open(a: *mem.Arena, path: str) -> (db.Connection, err)
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err)
```

Everything after `open` goes through `e.db`. The other declarations in `sqlite.e` are the
driver table (`d_*`) and its private context types and helpers. The language has no
visibility (spec section 12), so they are reachable, but they are not the surface.

`open` uses `READWRITE | CREATE | URI`, so `:memory:` and `file:x.db?mode=ro` both work.

## Ownership and memory

- The arena passed to `open` is retained and borrowed for the connection's lifetime.
  Every connection, statement, reader and transaction context is allocated from it,
  along with the driver table, column names and row buffers. The caller marks and resets
  that arena around work whose results it no longer needs.
- A reader copies each text and blob value into a buffer that it owns. The copy stays
  valid until the reader's next row. A growing buffer is a fresh allocation, so values
  already returned for the current row stay intact.
- `db.reader_next_borrowed` skips the copy. Its text and blob values are SQLite's own
  bytes, valid until the reader's next row or its close (D1599).
- `db.close` uses `sqlite3_close_v2`, so statements that are still open are not cut off.
  Closing a statement finalizes it, and its reader then answers `db.Closed`.
- One connection belongs to one thread. The package adds no locking.

## Values

| `db.Value` | Bound as | Read back as |
|---|---|---|
| `Null` | NULL | `Null` |
| `Bool` | INTEGER 0/1 | `Bool` in a column whose declared type contains `BOOL` |
| `I64` | INTEGER | `I64` |
| `U64` | INTEGER, only when it fits `i64` (otherwise `db.Unsupported`) | `I64` |
| `F64` | REAL | `F64` |
| `Text` | TEXT (copied, `SQLITE_TRANSIENT`) | `Text` |
| `Bytes` | BLOB (copied; empty stays a blob, not NULL) | `Bytes` |
| `Time` | INTEGER nanoseconds | `Time` in a column whose declared type contains `DATE` or `TIME` |

`db.Column.kind` is the declared affinity. An expression column has no declared type, so
it takes the first row's storage class, or `Null` when there are no rows. `nullable` is
always true, because only SQLite's optional column metadata could say otherwise.

## Statements and parameters

- `execute` runs every statement in its text and returns the total number of rows the
  statements changed. DDL answers 0 rather than the previous statement's count.
- `query` and `prepare` accept one statement. A second statement is `db.InvalidQuery`;
  a trailing `;` or comment is not.
- An unnamed parameter is positional. A named parameter is looked up as written (`:id`,
  `@id`, `$id`) and then with `:` in front. Each statement must take exactly as many
  parameters as it is given.
- A query steps once before it returns, so a failing query fails at `query` rather than
  at its first row.

## Errors

| SQLite primary code | `err` |
|---|---|
| `SQLITE_ERROR`, `SQLITE_RANGE` | `db.InvalidQuery` |
| `SQLITE_BUSY`, `SQLITE_LOCKED` | `db.Busy` |
| `SQLITE_CONSTRAINT`, `SQLITE_MISMATCH` | `db.Constraint` |
| a failed `open` | `CannotOpen` |
| anything else | `Failed` |

`detail` reports why the connection's last call failed: SQLite's primary and extended
codes and its message, copied into the caller's arena. When the driver refused before
SQLite was asked (wrong parameter count, unknown parameter name, an out-of-range `U64`, a
short row buffer), `detail` reports code 0 and the driver's reason. `begin` inside an open
transaction is `db.Busy`. A `COMMIT` that fails is rolled back, because `e.db` has
already closed the transaction's handle.

## Licensing boundary

SQLite is in the public domain. The package contains no SQLite code: it declares the
symbols it calls and binds to a library that the host already ships.

## Verification

`tests/selfhost/fixtures/link/x_sqlite` runs in both suites against the real library on
each host. Every check has its own exit code.

## Not in this package

- User-defined SQL functions, which need a foreign callback (GP-08 territory).
- A busy timeout, which a program can already set with `PRAGMA busy_timeout`.
- Column metadata, which is optional in SQLite builds and unavailable in `winsqlite3`.
