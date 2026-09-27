# `x.postgresql.libpq` — package specification

The PostgreSQL driver for `e.db`, over libpq, PostgreSQL's official client library. This is
the separate package specification that `modules.md` requires of every `x.*` package: upstream
version, targets, ownership and licensing boundary. Decision D1591.

## Upstream

- **API:** libpq's asynchronous query interface (`PQsendQuery`, `PQsendQueryParams`,
  `PQsendPrepare`, `PQsendDescribePrepared`, `PQsendQueryPrepared`, `PQgetResult`) in single-row
  mode. The newest call bound is `PQsetSingleRowMode`, so the floor is **libpq 9.2**
  (`PQlibVersion() >= 90200`). A lower version fails `open` with `db.Unsupported`. The server
  may be any version libpq itself can talk to.
- **Library, not source:** the package binds the host's own libpq. No PostgreSQL source is
  vendored or compiled.

| Target | Library | Where it comes from |
|---|---|---|
| x64 Windows | `libpq.dll` | PostgreSQL's Windows binaries (EDB): `pgsql\bin`, with the OpenSSL it needs, on PATH |
| x64 Linux | `libpq.so.5` | the distribution's `libpq5` package |

Verified when the package was delivered: libpq and server 18.6 on Windows 11, and libpq and
server 16 on Ubuntu 24.04.

## Modules

- `x.postgresql.capi` holds the raw `@import` declarations, one variant per OS. The two differ
  only in the library name. It is the package's only foreign boundary.
- `x.postgresql.libpq` is the driver. It is portable source over `capi`.

Binding is by `@import`: a program that calls nothing in the package does not depend on the
library, and one that does will not start without it.

## Surface

```neper
type Detail = struct { sqlstate: str, message: str, constraint: str }
error CannotConnect
error Aborted
error Failed
const MIN_VERSION: i32 = 90200i32

fn version() -> i32
fn open(a: *mem.Arena, conninfo: str) -> (db.Connection, err)
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err)
```

`conninfo` is a libpq connection string (`host=... port=... user=... dbname=...`) or a
`postgresql://` URI. `open` sets `client_encoding` to UTF-8, because text is handed back as it
arrives. Everything after `open` goes through `e.db`. The other declarations in `libpq.e` are
the driver table (`d_*`), its context types and its codecs. The language has no visibility,
so they are reachable, and the unit fixture calls them, but they are not the surface.

## Ownership and memory

- The arena passed to `open` is retained and borrowed for the connection's lifetime.
  Contexts, column names, prepared-statement names and row buffers come from it. Parameter
  encodings are allocated and reset around each call.
- A reader copies each value it keeps into its own buffer. The copy stays valid until the
  reader's next row.
- `db.reader_next_borrowed` skips the copy for text and `bytea`. Its values point into
  libpq's result and are valid until the next row or the reader's end (D1599).
- A reader streams 256 rows per result where libpq has `PQsetChunkedRowsMode` (17 and
  later), looked up at run time so an older libpq still loads the program, and one row per
  result otherwise (D1606). A result is cleared by the call after its last row. A query that
  fails partway drops its unfinished chunk: rows before the failure arrive in whole chunks,
  and a failure within the first 256 rows fails `query` itself.
- Error text lives in fixed buffers the connection allocates once, so failures do not grow
  the arena.
- One connection belongs to one thread.

## Wire format and values

Results are requested in **binary**, so nothing is re-parsed from text:

| PostgreSQL type | `db.Value` |
|---|---|
| `bool` | `Bool` |
| `int2`, `int4`, `int8`, `oid` | `I64` |
| `float4`, `float8` | `F64` (a `float4` is widened exactly) |
| `bytea` | `Bytes` |
| `text`, `varchar`, `bpchar`, `name`, `char`, `json`, `jsonb`, `xml` | `Text` |
| `numeric` | `Text`: its exact decimal at its stored scale, or `NaN`/`Infinity`/`-Infinity` |
| `uuid` | `Text`, canonical lower-case spelling |
| `timestamp`, `timestamptz`, `date` | `Time`; `infinity`/`-infinity` as `Text` |
| anything else | `Bytes`: the type's binary representation |

Parameters are positional (`$1`, `$2`, ...). A named `db.Parameter` is refused.

- **Unprepared statements:** each value takes its natural type. `I64` is `int8`, `U64` is
  `int8` or, past its range, `numeric` text. `F64` is `float8`, `Bool` is `bool`, `Bytes` is
  `bytea`, and `Time` is `timestamptz` in microseconds. `Text` is sent as `unknown`, so the
  server reads it as whatever the context wants: a date, a uuid, a numeric, jsonb.
- **Prepared statements:** the server settles each parameter's type at `prepare`, and every
  execution sends each value in that type. An `I64` narrows to `int2`/`int4` with a range
  check (`db.Unsupported` when it does not fit). A `Time` goes to `date` as a day count. A
  number into `numeric` or text goes as its shortest exact decimal. Any other type receives
  `Text` as text and `Bytes` as its binary form.
- `Time` has nanoseconds, while PostgreSQL keeps microseconds. The value is floored on the way
  in.

## Statements and streaming

- `execute` without parameters uses the simple protocol, so it runs every statement in its
  text. With parameters it takes one statement. The count is the rows `INSERT`, `UPDATE`,
  `DELETE` and `MERGE` changed; `SELECT` and DDL count 0.
- `query` and `prepare` take one statement, since the extended protocol refuses more.
- A query runs in single-row mode: rows arrive one at a time and nothing buffers the whole
  result. While a reader streams, the connection is busy, and any other call on it answers
  `db.Busy`. Closing a reader early reads and discards the remaining rows. Committing,
  rolling back or closing the connection ends a streaming reader first.
- Closing a statement ends a reader of that statement, which then answers `db.Closed`, and
  sends `DEALLOCATE`.
- `COPY` is not supported. `FROM STDIN` is refused back to the server, and `TO STDOUT` is read
  and discarded.

## Errors

| SQLSTATE | `err` |
|---|---|
| class `23` (integrity) | `db.Constraint` |
| `40001`, `40P01`, `55P03` (serialization, deadlock, `NOWAIT`) | `db.Busy` |
| `25P02` (in a failed transaction) | `Aborted` |
| class `0A` (feature not supported) | `db.Unsupported` |
| classes `42`, `22`, `3D`, `3F`, `26`; `08P01` (wrong parameter count) | `db.InvalidQuery` |
| a failed `open` | `CannotConnect` |
| anything else | `Failed` |

`detail` reports the last failure's SQLSTATE, primary message and violated constraint (such
as `item_pkey`). A local libpq failure has an empty SQLSTATE and libpq's message. A driver
refusal has an empty SQLSTATE and the driver's reason. After a success all three are empty.

**Transactions.** A second `begin` while one is open is `db.Busy`. PostgreSQL answers `COMMIT`
of a transaction that a statement failed in with a silent rollback; the driver reports that
case as `Aborted`. A `COMMIT` that fails outright is rolled back, because `e.db` has already
closed the handle.

## Licensing boundary

libpq is under the PostgreSQL License, a permissive BSD/MIT-style licence. The package contains
no PostgreSQL code: it declares the symbols it calls and binds to a library the user installs.

## Verification

- `tests/selfhost/fixtures/link/x_db_units` has no server and no library. It covers numeric
  rendering on hand-built binary values, uuid spelling, parameter encoding for natural and
  settled types, SQLSTATE mapping and column kinds.
- `tests/selfhost/fixtures/link/x_postgresql` runs against a live server, about 140 checks with
  one exit code each:
  - every type in the table above, written and read back;
  - numeric edge cases;
  - counts, errors and details;
  - streaming, the busy connection, and a failure in the middle of a stream;
  - prepared statements with settled types;
  - commit, rollback, nested and aborted transactions;
  - a 100 KB value;
  - a `NOWAIT` row lock refused as `Busy` across two connections.
- `tests/selfhost/db_servers.{ps1,sh}` starts a throwaway server for each suite run on
  127.0.0.1 (user `neper`, trust authentication). The port is `$NEPER_PG_PORT` if that is
  set; otherwise it is 55432, or the next free port above it when another server holds that
  one. The port chosen is written to `<dir>/ports` for the runners (D1596). On Windows the binaries come from
  `$NEPER_DB_TOOLS` (default `D:\tools`, the EDB archive unpacked to `postgresql\`); on Linux
  they come from the `postgresql` package.
