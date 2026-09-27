# `x.oracle.mysql` — package specification

The MySQL driver for `e.db`, over MySQL's C client library (named for Oracle, which owns
MySQL). This is the separate package specification that `modules.md` requires of every `x.*`
package: upstream version, targets, ownership and licensing boundary. Decision D1592.

## Upstream

- **API:** the MySQL C API's text protocol (`mysql_real_connect`, `mysql_real_query`,
  `mysql_use_result`, `mysql_fetch_row`, `mysql_next_result`, `mysql_real_escape_string`). The
  prepared-statement API (`mysql_stmt_*` with `MYSQL_BIND`) is deliberately not used: its
  struct layout differs between client versions and forks, and nothing in this package
  depends on a struct the package fills in.
- **Floor:** client library **5.7** (`mysql_get_client_version() >= 50700`), for utf8mb4 and
  every call bound. A lower version fails `open` with `db.Unsupported`.
- **Library, not source:** the package binds the host's own client library. No MySQL source
  is vendored or compiled.

| Target | Library | Where it comes from |
|---|---|---|
| x64 Windows | `libmysql.dll` | MySQL's Windows archive: `lib\` on PATH, with `bin\` for the OpenSSL it needs |
| x64 Linux | `libmysqlclient.so.21` | the distribution's `libmysqlclient21` package (MySQL 8.0 and later) |

Verified when the package was delivered: client and server 8.4.9 LTS on Windows 11, and client
and server 8.0.46 on Ubuntu 24.04.

## Modules

- `x.oracle.mysqlclient` holds the raw `@import` declarations, one variant per OS. The two
  variants export the same surface but not the same declarations. C's `unsigned long` is
  32 bits on Windows and 64 on Linux, so every extern that takes or returns one is private to
  its variant and wrapped in a function over `usize`. The offsets into `MYSQL_FIELD`, which
  holds two such fields, are constants of each variant. This is the package's only foreign
  boundary.
- `x.oracle.mysql` is the driver. It is portable source over `mysqlclient`.

## Surface

```neper
type Options = struct { host: str, port: u16, user: str, password: str, database: str }
type Detail = struct { code: u32, sqlstate: str, message: str }
error CannotConnect
error Failed
const MIN_VERSION: usize = 50700usize

fn version() -> usize
fn open(a: *mem.Arena, options: Options) -> (db.Connection, err)
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err)
```

In `Options`, an empty string or a zero port leaves that setting to the library's default.
`open` asks for utf8mb4, enables multi-statement text, and sets the session `time_zone` to UTC,
so a `TIMESTAMP` reads back as the instant that was written.

## Ownership and memory

- The arena passed to `open` is retained and borrowed for the connection's lifetime.
  Contexts, column names and row buffers come from it. A statement's rendered text is
  allocated and reset around each call.
- A reader copies each value it keeps into its own buffer. The copy stays valid until the
  reader's next row.
- Error text lives in fixed buffers the connection allocates once.
- One connection belongs to one thread.

## Parameters

Placeholders are `?`, positional. A named `db.Parameter` is refused. Values are rendered into
the statement text on the client, the way drivers without a binding API do it:

| `db.Value` | Rendered as |
|---|---|
| `Null` | `NULL` |
| `Bool` | `TRUE` / `FALSE` |
| `I64`, `U64` | decimal |
| `F64` | the shortest text that reads back as the same double, with `e0` added when it has no exponent (without it MySQL reads `0.1` as a `DECIMAL`); infinities and NaN are `db.Unsupported`, since MySQL has none |
| `Text` | `'...'` through `mysql_real_escape_string` for the connection's character set |
| `Bytes` | `X'...'` hex |
| `Time` | `'YYYY-MM-DD HH:MM:SS.ffffff'` in UTC (MySQL keeps microseconds) |

The scanner that finds placeholders follows MySQL's lexer. A `?` inside `'...'`, `"..."`
(with backslash escapes and doubled quotes), a backquoted identifier, or a `#`, `-- ` or
`/* */` comment is not a placeholder. The same scan counts statements, so a `;` inside any of
those does not end one. The statement must take exactly as many parameters as it is given.

The text protocol keeps the binding free of `MYSQL_BIND`. The price is that the server sees
literals rather than bound values. Escaping is done by the client library for the
connection's character set; it assumes the server's default SQL mode, not
`NO_BACKSLASH_ESCAPES`.

## Values

| MySQL type | `db.Value` |
|---|---|
| `TINYINT(1)` / `BOOLEAN` | `Bool` |
| other integers, `YEAR` | `I64`; `BIGINT UNSIGNED` past `i64` is `U64` |
| `FLOAT`, `DOUBLE` | `F64`, read exactly |
| `DATE`, `DATETIME`, `TIMESTAMP` | `Time` (UTC); a zero date names no day and comes back as its text |
| `DECIMAL`, `TIME`, `JSON`, `ENUM`, `SET`, text types | `Text` |
| binary strings and blobs (charset `binary`), `BIT`, `GEOMETRY` | `Bytes` |

## Statements and streaming

- `execute` runs every statement in its text and sums the affected rows. A `SELECT` in it is
  read and discarded. A failure stops the text at that statement, keeping what ran before it.
- `query` and `prepare` take one statement.
- `prepare` has the server compile the text (`PREPARE ... FROM`, then `DEALLOCATE`), so a
  statement that cannot run fails at `prepare`. The text is then kept and rendered at each
  execution.
- A query streams (`mysql_use_result`): rows arrive one at a time. While a reader streams,
  the connection is busy, and any other call on it answers `db.Busy`. Closing a reader early
  reads and discards the rest. Closing its statement ends it and makes it answer `db.Closed`.

## Errors

| MySQL | `err` |
|---|---|
| SQLSTATE class `23`; error 3819 (CHECK, reported as `HY000`) | `db.Constraint` |
| SQLSTATE `40001`; errors 1205 (lock wait timeout), 1213 (deadlock), 3572 (`NOWAIT`) | `db.Busy` |
| SQLSTATE classes `42`, `22`, `3D`; error 1065 (empty query) | `db.InvalidQuery` |
| a failed `open` | `CannotConnect` |
| anything else | `Failed` |

`detail` reports the last failure's error number, SQLSTATE and message. A driver refusal is
code 0 with the driver's reason. After a success all three are empty. A second `begin` while
one is open is `db.Busy`: MySQL would otherwise commit the first silently. The flag is the
driver's own, so a transaction started by raw SQL is not seen.

## Licensing boundary

MySQL's client library is GPLv2 with the Universal FOSS Exception, which allows linking from
software under other licences. The package contains no MySQL code: it declares the symbols it
calls and binds, at run time, to a library the user installs. Distributing a program together
with `libmysql` is the distributor's concern under that licence. MariaDB's Connector/C is not
verified.

## Verification

- `tests/selfhost/fixtures/link/x_db_units` has no server and no library. It covers the
  scanner (strings, identifiers, comments, `--` without a space, unterminated strings, `;`
  counting), double, hex and datetime literals, datetime parsing including zero and invalid
  dates, column kinds and error mapping.
- `tests/selfhost/fixtures/link/x_mysql` runs against a live server, about 130 checks with one
  exit code each:
  - every type in the tables above, written and read back;
  - text with quotes, backslashes, a NUL and 4-byte UTF-8;
  - doubles at the edges (0.1, 1e300, the smallest subnormal);
  - placeholders inside literals and comments;
  - counts, errors and details, and a script that stops partway;
  - streaming, the busy connection, and a reader closed early;
  - server-checked prepared statements;
  - transactions and a 100 KB value;
  - a `NOWAIT` row lock refused as `Busy` across two connections.
- `tests/selfhost/db_servers.{ps1,sh}` starts a throwaway server for each suite run on
  127.0.0.1 (`root`, no password, database `neper`). The port is `$NEPER_MYSQL_PORT` if that
  is set; otherwise it is 53306, or the next free port above it when another server holds that
  one. The port chosen is written to `<dir>/ports` for the runners (D1596). On Windows the binaries come from
  `$NEPER_DB_TOOLS` (default `D:\tools`, the archive unpacked to `mysql\`); on Linux they come
  from the `mysql-server` package.
