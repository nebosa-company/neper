# `x.duckdb.duckdb` — package specification

The DuckDB driver for `e.db`. This is the separate package specification that
`modules.md` requires of every `x.*` package before it is written: upstream version,
targets, ownership and licensing boundary. Decision D1571's sibling for SQLite.

## Upstream

- **API:** the DuckDB **C API v2** — the `duckdb_v2_*` surface `duckdb_v2.h` declares. Every
  call answers a `DUCKDB_V2_ERROR` (`0` is success) and hands back its products through
  out-parameters, with errors carried in an opaque info handle the caller destroys. The floor is
  version **2.0.0** (`MIN_VERSION = 20000`), the first release that declares this surface, and
  anything older fails `open` with `db.Unsupported`.
- **Library, not source:** the package binds a shared library. No DuckDB source is vendored or
  compiled. DuckDB is MIT licensed, and linking it dynamically keeps that licence's notice
  requirement with the distributor, as libpq and libmysql do for their drivers.

| Target | Library | Present because |
|---|---|---|
| x64 Windows | `duckdb.dll` | the published `duckdb-shared-libs-windows-amd64` archive, unpacked under `D:\tools\duckdb` and put on PATH |
| x64 Linux | `libduckdb.so` | the `duckdb` package, or the same archive's linux build on `LD_LIBRARY_PATH` |

Measured when the package was delivered: v2.0.0 on Windows 11.

## Modules

- `x.duckdb.v2` holds the raw `@import` declarations, one variant per OS
  (`v2.windows.e`, `v2.linux.e`). The two files differ only in the library name and the
  header comment. It is the package's only foreign boundary.
- `x.duckdb.duckdb` is the driver. It is portable source over `v2`.

Binding is by `@import`, so the loader resolves every symbol eagerly at start-up. A program
that calls nothing in the package does not depend on the library (D128). A program that does
call it will not start on a host that lacks the library.

The library is C++ inside, but its C API is `extern "C"` and exported unmangled: every symbol
`v2` names is the plain `duckdb_v2_*` spelling. Three v2 shapes matter:

- `duckdb_v2_str` is `{ const char *ptr; idx_t len; }` — 16 bytes, and **not** NUL-terminated.
  `duckdb_v2_identifier_t` has the same layout, and is what a parameter name is passed as.
- `duckdb_v2_value_handle` is an owned value, not a pointer into a chunk: every cell read is
  destroyed by the reader, and so is every value handed to an execute call once it returns.
- A statement taken from a statement iterator is valid **only while that iterator lives**. The
  driver therefore prepares a statement before it destroys the iterator, and keeps the iterator
  alive for as long as a prepared statement is open.

## Surface

```neper
type Detail = struct { code: i32, message: str }
error CannotOpen
error Failed
const MIN_VERSION: i32 = 20000i32

fn version() -> i32
fn open(a: *mem.Arena, path: str) -> (db.Connection, err)
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err)
```

Everything after `open` goes through `e.db`. The other declarations in `duckdb.e` are the
driver table (`d_*`) and its private context types and helpers. The language has no
visibility (spec section 12), so they are reachable, but they are not the surface.

`path` is a database file, or empty for an in-memory database.

## Ownership and memory

- The arena passed to `open` is retained and borrowed for the connection's lifetime. Every
  connection, statement, reader and transaction context is allocated from it, along with the
  driver table, column names and row buffers. The caller marks and resets that arena around
  work whose results it no longer needs.
- A reader holds one DuckDB data chunk at a time and frees it before fetching the next, so no
  result is buffered whole.
- A reader copies each text and blob value into a buffer that it owns. The copy stays valid
  until the reader's next row. `db.reader_next_borrowed` skips it, and its bytes are the
  chunk's own, valid until the reader's next row or its close (D1599).
- Error text is kept in a fixed buffer the connection allocates once, so failures do not grow
  the arena.
- Closing a statement destroys the prepared statement.
- One connection belongs to one thread. The package adds no locking.

## Statements and parameters

- The DuckDB C API has no statement splitter, so the driver reads one: `;` outside every quote
  and comment ends a statement. A text whose quotes or comments it cannot follow is handed to
  DuckDB whole, which reports its own refusal.
- `execute` runs every statement in its text and answers how many statements changed rows (a
  `SELECT` or DDL changes none). A text with no statement at all runs nothing.
- `query` and `prepare` accept one statement. A second statement is `db.InvalidQuery`; a
  trailing `;` or comment is not.
- Parameters are DuckDB's `$1`, `$2`, ... in the order they first appear. A `db.Parameter`
  binds in the order it is given. A statement's parameters are bound by the key DuckDB reports
  for each position — `"1"`, `"2"`, ... for a positional parameter and the bare identifier for
  a named one, without a leading `$` — so `$name`, `$1` and a mix of the two all bind, and a
  parameter name the caller supplies is used only when the statement reports none.
- Each statement must take exactly as many parameters as it is given: the driver asks the
  statement how many it takes and refuses a mismatch as `db.InvalidQuery` itself.
- A query takes its first chunk before it returns, so a failing query fails at `query` rather
  than at its first row.

## Values

| `db.Value` | Bound as | Read back as |
|---|---|---|
| `Null` | NULL | `Null` |
| `Bool` | BOOLEAN | `Bool` |
| `I64` | BIGINT | `I64` from every integer type; a `UBIGINT` past `i64` is `U64` |
| `U64` | BIGINT, only while it fits `i64` (otherwise `db.Unsupported`) | — |
| `F64` | DOUBLE | `F64` from `FLOAT` and `DOUBLE` |
| `Text` | VARCHAR | `Text` from `VARCHAR`; `DECIMAL`, `HUGEINT`, `UHUGEINT`, `UUID`, `DATE`, `TIME`, `TIME_TZ`, `INTERVAL` and `TIMESTAMP_NS` arrive as their `Text` spelling |
| `Bytes` | BLOB | `Bytes` from `BLOB`; the nested types (`LIST`, `STRUCT`, `MAP`, `ARRAY`, `BIT`) arrive as their raw `Bytes` |
| `Time` | TIMESTAMP in UTC, microseconds (the nanosecond digits past the sixth go) | `Time` from `TIMESTAMP`, `TIMESTAMP_S`, `TIMESTAMP_MS` and `TIMESTAMP_TZ` |

`db.Column.kind` is the declared SQL type, as mapped above. `nullable` is always true, because
the C API does not report per-column nullability.

`DATE` and `TIME` are text rather than `Time` for a reason: an `e.time.Instant` is a point on the
timeline, and neither is one. A `TIME` is a time of day, and a `DATE` names no instant until a
zone is chosen.

## Errors

| `duckdb_error_type` | `err` |
|---|---|
| `DUCKDB_ERROR_PARSER`, `DUCKDB_ERROR_BINDER`, `DUCKDB_ERROR_CATALOG` | `db.InvalidQuery` |
| `DUCKDB_ERROR_PARAMETER_NOT_RESOLVED`, `DUCKDB_ERROR_PARAMETER_NOT_ALLOWED` | `db.InvalidQuery` |
| `DUCKDB_ERROR_CONVERSION`, `DUCKDB_ERROR_DECIMAL`, `DUCKDB_ERROR_INVALID_TYPE` | `db.InvalidQuery` |
| `DUCKDB_ERROR_OUT_OF_RANGE`, `DUCKDB_ERROR_INVALID_INPUT` | `db.InvalidQuery` |
| `DUCKDB_ERROR_RESOURCE_IN_USE`, `DUCKDB_ERROR_TRANSACTION`, `DUCKDB_ERROR_INTERRUPT` | `db.Busy` |
| `DUCKDB_ERROR_NOT_IMPLEMENTED` | `db.Unsupported` |
| `DUCKDB_ERROR_CONSTRAINT` | `db.Constraint` |
| a failed `open` | `CannotOpen` |
| anything else | `Failed` |

`detail` reports why the connection's last call failed: DuckDB's error type and its message,
copied into the caller's arena. When the driver refused before DuckDB was asked (wrong
parameter count, unknown parameter name, an out-of-range `U64`, a short row buffer), `detail`
reports code 0 and the driver's reason. `begin` inside an open transaction is `db.Busy`. A
`COMMIT` that fails is rolled back, because `e.db` has already closed the transaction's handle.

## Known limitation

A prepared statement is not yet usable from this driver: `duckdb_execute_prepared` answers
success but leaves the result empty on a DuckDB 2.0 library, where `duckdb_query` works. The
`db.prepare`/`db.execute_statement`/`db.query_statement` path is therefore not exercised by the
fixture, and `db.execute`/`db.query` (which split the text and run each statement on its own)
are the path that is.

## Licensing boundary

DuckDB is MIT licensed. The package contains no DuckDB code: it declares the symbols it calls
and binds to a library the distributor supplies.

## Verification

`tests/selfhost/fixtures/link/x_duckdb` runs in both suites against the real library on each
host. Every check has its own exit code.

## Not in this package

- The v1 `duckdb_*` surface. DuckDB 2.0 still exports it, but this package binds only the v2
  names, so the v1 declarations (`capi.windows.e`, `capi.linux.e`) are now unreferenced.
- User-defined SQL functions and appenders, which need foreign callbacks.
- Column metadata beyond the declared type, which the C API does not report per column.
