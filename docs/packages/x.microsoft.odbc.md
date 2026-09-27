# `x.microsoft.odbc` — package specification

The ODBC driver for `e.db`: one package that reaches any database with an ODBC driver, through
the host's driver manager. This is the separate package specification that `modules.md`
requires of every `x.*` package: upstream version, targets, ownership and licensing boundary.
Decision D1650.

## Name

`x.*` names the owner of the API a package programs against (D1650, reading D78). Microsoft
defines ODBC: the `SQL*` functions, their handles, return codes and SQLSTATEs. unixODBC and
iODBC are third-party driver managers that implement that same API, down to the same
`sql.h`/`sqlext.h` signatures. So the package is `x.microsoft.odbc` on every host. Which library
answers is a per-OS variant, as with `x.oracle.mysqlclient` and the existing `x.khronos.*`
reservations. It is not `e.db.odbc`: `e.*` binds host libraries only through `e.os` (D63), and
`e.db` is the contract this package implements.

## Upstream

- **API:** ODBC 3.x through its wide (`W`) entry points: `SQLAllocHandle`, `SQLSetEnvAttr`,
  `SQLDriverConnectW`, `SQLPrepareW`, `SQLNumParams`, `SQLBindParameter`, `SQLExecute`,
  `SQLNumResultCols`, `SQLDescribeColW`, `SQLFetch`, `SQLGetData`, `SQLRowCount`,
  `SQLMoreResults`, `SQLFreeStmt`, `SQLSetConnectAttrW`, `SQLEndTran`, `SQLGetDiagRecW`,
  `SQLDisconnect`, `SQLFreeHandle`. The environment asks for ODBC 3 behaviour
  (`SQL_OV_ODBC3`). Text crosses as UTF-16 because the narrow entry points go through the
  process code page on Windows and the locale on Linux, while `SQLWCHAR` is a UTF-16 unit on
  both.
- **Library, not source:** the package binds the host's driver manager. No ODBC source is
  vendored or compiled. The database's own ODBC driver is the user's to install.

| Target | Driver manager | Where it comes from |
|---|---|---|
| x64 Windows | `odbc32.dll` | Windows, in System32 |
| x64 Linux | `libodbc.so.2` | unixODBC, the distribution's `unixodbc` package |

On both hosts `SQLLEN`/`SQLULEN` are 64 bits, `SQLINTEGER` is 32 and `SQLWCHAR` is 16, so the
two variants are identical but for the library name.

Verified when the package was delivered: psqlODBC 17.00.0010 over PostgreSQL 18.6 on Windows 11,
and unixODBC 2.3.12 with psqlODBC 16.00 over PostgreSQL 16 on Ubuntu 24.04.

## Modules

- `x.microsoft.capi` holds the raw `@import` declarations, one variant per OS. This is the
  package's only foreign boundary.
- `x.microsoft.odbc` is the driver. It is portable source over `capi`.

## Surface

```neper
type Detail = struct { native: i32, sqlstate: str, message: str }
error CannotConnect
error Failed

fn open(a: *mem.Arena, connection_string: str) -> (db.Connection, err)
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err)
```

`open` takes an ODBC connection string (`DSN=...`, or `Driver=...` with the driver's own
keywords) and connects with `SQLDriverConnectW` without a prompt. A failure is `CannotConnect`.
The driver manager's reason is not kept, since no connection exists to ask for it.

## Ownership and memory

- The arena passed to `open` is retained and borrowed for the connection's lifetime.
  Contexts, column names and row buffers come from it. The UTF-16 copies of SQL text and
  parameter values are allocated and reset around each call.
- A reader copies each value into its own buffer with `SQLGetData`. The copy stays valid until
  the reader's next row. ODBC has no borrowed form, so `db.reader_next_borrowed` answers the
  same copies (D1599 allows this).
- A long value is read in pieces: 256 bytes first, then exactly what `SQLGetData` says is
  left, or twice the room when the driver answers `SQL_NO_TOTAL`.
- Error text lives in fixed buffers the connection allocates once.
- One connection belongs to one thread.

## Parameters

Placeholders are `?`, positional; a named `db.Parameter` is refused. Every statement is
prepared (`SQLPrepareW`), and it must take exactly as many parameters as it is given
(`SQLNumParams`), numbered across the whole text. Each value binds as its natural ODBC type and
the driver converts it to the column's:

| `db.Value` | C type | SQL type |
|---|---|---|
| `Null` | `SQL_C_CHAR`, `SQL_NULL_DATA` | `SQL_VARCHAR` |
| `Bool` | `SQL_C_BIT` | `SQL_BIT` |
| `I64` | `SQL_C_SBIGINT` | `SQL_BIGINT` |
| `U64` | `SQL_C_UBIGINT` | `SQL_BIGINT` |
| `F64` | `SQL_C_DOUBLE` | `SQL_DOUBLE` |
| `Text` | `SQL_C_WCHAR` (UTF-16) | `SQL_WVARCHAR` |
| `Bytes` | `SQL_C_BINARY` | `SQL_VARBINARY` |
| `Time` | `SQL_C_TYPE_TIMESTAMP`, UTC, nanoseconds | `SQL_TYPE_TIMESTAMP` (29, 9) |

## Values

| ODBC type | `db.Value` |
|---|---|
| `SQL_BIT` | `Bool` |
| `SQL_TINYINT`, `SMALLINT`, `INTEGER`, `BIGINT` | `I64` |
| `SQL_REAL`, `FLOAT`, `DOUBLE` | `F64` |
| `SQL_BINARY`, `VARBINARY`, `LONGVARBINARY` | `Bytes` |
| `SQL_TYPE_DATE`, `TYPE_TIMESTAMP` | `Time`, the wall time read as UTC |
| everything else: character types, `DECIMAL`, `NUMERIC`, `TYPE_TIME`, `GUID`, intervals | `Text` |

A column is nullable unless the driver says `SQL_NO_NULLS`. An unsigned `BIGINT` past `i64` is
the driver's conversion error, not a `U64`. A timestamp carries no zone in ODBC. A zone-aware
column arrives in the session's zone, and that zone is the connection string's to set.

## Statements

- `execute` runs every statement in its text and sums the affected rows, reading past any
  result set without counting it. A searched `UPDATE` or `DELETE` that matches nothing
  (`SQL_NO_DATA`) is 0.
- `query` leaves the first result open as the reader.
- `prepare` also asks for the result's shape (`SQLNumResultCols`). That makes a driver that
  defers preparing check the text there, so SQL that cannot run fails at `prepare` with most
  drivers.
- Running a statement again closes any cursor its previous reader held. Closing the statement
  makes that reader answer `db.Closed`.
- Whether rows stream or arrive whole, and whether a connection can hold two open results,
  are the driver's settings (psqlODBC: `UseDeclareFetch`).

## Transactions

`begin` switches autocommit off and the end of the transaction switches it back on, with
`SQLEndTran` committing or rolling back. A second `begin` is `db.Busy`. A failed commit is rolled
back, keeping the commit's diagnostic. Closing a connection with a transaction open rolls it
back, since `SQLDisconnect` refuses one inside a transaction. Whether a failed statement aborts
the transaction is the driver's choice: psqlODBC's default rolls back only that statement.

## Errors

| SQLSTATE | `err` |
|---|---|
| class `23` | `db.Constraint` |
| class `40`, `HYT00`, `HYT01`, `55P03` (PostgreSQL's `lock_not_available`, passed through by psqlODBC) | `db.Busy` |
| classes `42`, `22`, `07`, `21`, `3D`; `37000` | `db.InvalidQuery` |
| a failed `open` | `CannotConnect` |
| anything else | `Failed` |

`detail` reports the first diagnostic record's SQLSTATE, native error and message. A driver
refusal (a named parameter, a count that differs, text that is not UTF-8) is an empty state,
native 0, and the driver's reason. After a success all three are empty.

## Licensing boundary

The package contains no ODBC code. It declares the symbols it calls and binds, at run time,
to the driver manager the host has: `odbc32.dll` is part of Windows, and unixODBC is LGPL-2.1.
Each database's ODBC driver carries its own licence, which is the distributor's concern.

## Verification

- `tests/selfhost/fixtures/link/x_db_units` has no server and no library. It covers SQLSTATE
  mapping, UTF-16 conversion (a leading U+FEFF kept as text, surrogate pairs, an unpaired
  surrogate refused, empty text), `TIMESTAMP_STRUCT` both ways including before the epoch,
  and type codes onto kinds.
- `tests/selfhost/fixtures/link/x_odbc` runs against a live PostgreSQL through psqlODBC, about
  150 checks with one exit code each:
  - every value kind bound and read back, including 4-byte UTF-8 and a leading U+FEFF;
  - a column name outside ASCII;
  - counts summed over a script, and an `UPDATE` that matched nothing;
  - SQLSTATEs and `detail`, and the driver's refusals;
  - prepared statements reused, closed under their reader, and refused at `prepare`;
  - 1000 rows, and a reader closed early;
  - 100 KB of text and of bytes, read in pieces;
  - transactions committed, rolled back, refused when nested, and closed while open;
  - a `NOWAIT` row lock refused as `Busy` across two connections;
  - a data source that does not exist.

  Three deliberate driver defects were each caught at their own check: U+FEFF taken for a
  byte-order mark, an off-by-two in the piece arithmetic, and `SQL_BIGINT` left unmapped.
- The suites start the server with `tests/selfhost/db_servers.{ps1,sh}`. On Windows the psqlODBC
  MSI is unpacked with `msiexec /a` to `$NEPER_DB_TOOLS\psqlodbc` (default `D:\tools`), with no
  installation and no system registration. The runner writes a per-user DSN,
  `HKCU\Software\ODBC\ODBC.INI\neper_psqlodbc`, whose `Driver` value is that DLL, and removes
  it afterwards. On Linux the driver is named by its path,
  `Driver=/usr/lib/x86_64-linux-gnu/odbc/psqlodbcw.so`, from the `odbc-postgresql` package.
  The connection string sets `BoolsAsChar=0` so that psqlODBC reports `boolean` as `SQL_BIT`.
