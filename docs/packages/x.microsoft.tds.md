# `x.microsoft.tds` — package specification

The SQL Server driver for `e.db`. It speaks Microsoft's Tabular Data Stream itself, inside TLS
1.3, with no client library. This is the separate package specification that `modules.md`
requires of every `x.*` package: upstream version, targets, ownership and licensing boundary.
Decision D1643.

## Name

`x.*` names the owner of the API a package programs against (D1650, reading D78). Microsoft
defines TDS ([MS-TDS]) and SQL Server, so the package is `x.microsoft.tds`, next to
`x.microsoft.odbc`. It is named for the protocol rather than the product because the protocol
is what it implements: Azure SQL, Azure Synapse and Fabric's SQL endpoints speak the same TDS.

## Upstream

- **Protocol:** TDS 7.4 messages ([MS-TDS] 2.2) carried the way TDS 8.0 carries them. The TLS
  1.3 handshake, with ALPN `tds/8.0`, comes before the first TDS byte, so PRELOGIN, LOGIN7 and
  everything after them are only ever inside TLS. This is SQL Server's "strict" encryption
  (`Encrypt=Strict` in Microsoft's own drivers).
- **Source, not library:** the package is portable Neper over `e.net` and `e.net.tls`. It binds
  no foreign code on any target, so it has no per-OS variant.
- **Reference:** celvyx's Dart TDS client (`src/lib/core/dataflow/extract/tds`) was read for
  LOGIN7's field table, `sp_executesql`'s layout and the token grammar.

| Target | Needs |
|---|---|
| x64 Windows | nothing beyond `e.net` (Winsock) |
| x64 Linux | nothing beyond `e.net` (the kernel's sockets) |

Verified when the package was delivered: SQL Server 2025 (17.0.1000.7) Developer on Windows 11,
and the `mssql-server` 2025 package on Ubuntu 24.04 under WSL.

## Surface

```neper
type Options = struct { host: str, port: u16, user: str, password: str, database: str, trust_roots: []const u8 }
type Detail = struct { number: i32, state: u8, severity: u8, message: str }
error CannotConnect
error Failed
error Aborted
error Protocol

fn open(a: *mem.Arena, options: Options) -> (db.Connection, err)
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err)
```

`open` resolves `host` (IPv4 first), connects, and completes TLS. The server's certificate must
chain to `trust_roots`, which is DER certificates as `e.net.tls` takes them, and must name
`host`. Nothing skips that check, and empty `trust_roots` is `CannotConnect` before anything is
sent. Then comes PRELOGIN, with ENCRYPTION `NOT_SUP` because TLS is already the outer layer, and
then LOGIN7 with a SQL login. Errors:

- A failed handshake is `e.net.tls`'s error, such as `tls.InvalidCertificate`.
- A login SQL Server refuses, which is an ERROR token and no LOGINACK, is `CannotConnect`.

LOGIN7 carries TDS version 7.4, a requested packet size of 16384, `fODBC` (which turns on the
ANSI session options ODBC drivers use), and application name `neper`.

## Ownership and memory

- The arena passed to `open` is retained and borrowed for the connection's lifetime.
  Contexts, column names and buffers come from it. The request, packet, PLP and scratch buffers
  grow geometrically and are reused, so a long-lived connection's arena stops growing once
  its largest request and value have been seen.
- A reader copies each value into its own buffer. The copy stays valid until the reader's next
  row. Packets are overwritten as the reply arrives, so there is no borrowed form, and
  `db.reader_next_borrowed` answers the same copies (D1599 allows this).
- Error text lives in a fixed buffer the connection allocates once.
- One connection belongs to one thread.

## Framing

- Requests are split into packets of the size the server chose in LOGINACK's ENVCHANGE. Each
  packet is written as a TLS record of its own. Under TDS 8.0, SQL Server caps the packet size
  at 16192, under TLS's 16384-byte record, and drops a connection whose packet spans two records.
- Replies are read packet by packet. Tokens and values are parsed across packet boundaries, with
  a copy only for a value that straddles one.

## Parameters

Placeholders are `?`, positional; a named `db.Parameter` is refused. The driver rewrites them to
`@p1`…`@pN` and runs the text through `sp_executesql` (RPC, procedure id 10). A `?` inside a
string (`'...'`, with `''`), a quoted identifier (`"..."`, `[...]`) or a comment (`--`, and
`/* */`, which nests in T-SQL) is not a placeholder. Text with no parameters goes as a plain
SQL batch.

| `db.Value` | Declared as |
|---|---|
| `Null` | the literal `NULL` in the text (a typed NULL would not convert to every column) |
| `Bool` | `bit` |
| `I64`, `U64` up to `i64`'s max | `bigint` |
| `U64` past it | `decimal(38,0)` |
| `F64` | `float` |
| `Text` | `nvarchar(4000)`, or `nvarchar(max)` past 4000 UTF-16 units |
| `Bytes` | `varbinary(8000)`, or `varbinary(max)` past 8000 bytes |
| `Time` | `datetime2(7)`, UTC, to 100 ns |

SQL Server converts each value to its column's type. The statement text and the declarations
travel as `nvarchar(max)`.

## Values

| SQL Server type | `db.Value` |
|---|---|
| `bit` | `Bool` |
| `tinyint`, `smallint`, `int`, `bigint` | `I64` |
| `real`, `float` | `F64` |
| `binary`, `varbinary`, `image`, `rowversion`, CLR types | `Bytes` |
| `date`, `datetime`, `smalldatetime`, `datetime2` | `Time`, the stored value read as UTC |
| `datetimeoffset` | `Time`, the instant it names |
| `decimal`, `numeric`, `money`, `smallmoney` | `Text`, every digit of the stored scale |
| `time` | `Text`, `hh:mm:ss` and the column's scale of fraction digits |
| `uniqueidentifier` | `Text`, upper-case, SQL Server's byte order |
| `nchar`, `nvarchar`, `ntext`, `xml` | `Text` from UTF-16 |
| `char`, `varchar`, `text` | `Text`: as UTF-8 under a UTF-8 collation, from Windows-1252 under a Latin-1 one |
| `sql_variant` | the value of its base type |

Notes:

- A column is nullable when its metadata says so.
- A `datetime` value is rounded to SQL Server's own milliseconds (ticks of 1/300 s).
- A date outside what an `i64` of nanoseconds holds (1677 to 2262) is `Failed`, and so is
  non-ASCII `varchar` in any other code page. The row is still read to its end, so the
  connection stays in step.

## Statements

- `execute` sends the whole text and sums the rows that each DONE or DONEINPROC token counts
  for a statement other than a `SELECT`. It reads past any result set.
- `query` streams the first result set as its packets arrive. While a reader is open the
  connection is busy: any other call on it, including running the reader's own statement
  again, is `db.Busy`. Reaching the end of the rows, or closing the reader, reads and discards
  the rest of the reply.
- `prepare` keeps the text and counts its placeholders. Nothing reaches the server until the
  statement runs, which is where SQL that cannot run fails. Closing the statement ends its
  streaming reader, which then answers `db.Closed`.

## Transactions

`begin` sends `BEGIN TRANSACTION`, and SQL Server's ENVCHANGE hands back the transaction
descriptor that every later request carries in its ALL_HEADERS. Commit and rollback are
`COMMIT TRANSACTION` and `ROLLBACK TRANSACTION` batches.

- A second `begin` is `db.Busy`.
- Committing or rolling back ends an open reader first.
- A failed commit is rolled back.
- With `XACT_ABORT` off (the default), a failed statement leaves the transaction open.
- When SQL Server ends the transaction itself, reported by ENVCHANGE 10 or 17, every later
  call on the transaction answers `Aborted`, including a commit, until it is committed or
  rolled back. This happens to a deadlock victim, or to any error under `XACT_ABORT`.
- Closing a connection with a transaction open leaves SQL Server to roll it back.

## Errors

| SQL Server error | `err` |
|---|---|
| 2627, 2601 (unique), 547 (foreign key, `CHECK`), 515 (NOT NULL) | `db.Constraint` |
| 1205 (deadlock victim), 1222 (lock timeout) | `db.Busy` |
| severity 15 (syntax); 102, 105, 137, 156, 201, 207, 208, 2812, 8144; conversions and arithmetic (8134, 245, 8114, 8115, 241, 242, 2628, 8152, 206, 257) | `db.InvalidQuery` |
| a login SQL Server refuses | `CannotConnect` |
| a reply this client cannot parse | `Protocol`; the connection is then broken |
| anything else, including a lost connection | `Failed` |

`detail` reports the first ERROR token of the last call's reply: its number, state, severity
and message. The message is not the "statement has been terminated" that follows. A driver
refusal (a named parameter, a count that differs, text that is not UTF-8, a busy connection) is
number 0 and the driver's reason. After a success every field is empty.

## Licensing boundary

The package is original Neper written from the published [MS-TDS] specification. It links
nothing and redistributes nothing. The SQL Server it talks to is the user's, under its own
licence.

## Verification

- `tests/selfhost/fixtures/link/x_tds` runs against a live SQL Server over TDS 8.0 strict,
  about 150 checks with one exit code each:
  - every value kind bound and read back: bigint, smallint, int, tinyint, float, real, bit,
    varbinary with NULs, and nvarchar with 4-byte UTF-8 and a leading U+FEFF;
  - datetime2 to 100 ns and date as UTC;
  - money, datetime, datetimeoffset, time, uniqueidentifier, nchar and a Latin-1 varchar read
    back;
  - NULL into a varbinary column, and a `U64` past `i64`;
  - a column name outside ASCII;
  - counts summed over a script;
  - `?` left alone inside strings, bracketed and quoted identifiers, and nested comments;
  - error numbers onto `e.db`, with `detail`, and the driver's refusals;
  - prepared statements;
  - 1000 rows with the connection busy meanwhile, and a reader closed one row into a million;
  - 100 KB of text and bytes each way, as `nvarchar(max)` and `varbinary(max)` over many packets;
  - transactions committed, rolled back, refused when nested, surviving a failed statement,
    and ended by the server under `XACT_ABORT`;
  - a lock timeout as `Busy` across two connections;
  - a wrong password, and no trust root.

  Three deliberate driver defects were each caught at their own check: an NBCROW null bitmap
  read most-significant bit first (45), a bracketed identifier's `?` taken for a placeholder
  (78), and a `SELECT`'s row count summed as affected rows (60).
- On Linux the suite runs `tests/selfhost/sqlserver.sh`. Its `setup` is run once, with sudo. It
  configures the `mssql-server` package's Developer edition on 127.0.0.1:14331 with a self-signed
  certificate and creates the `neper` login and database. Its `start` and `stop` bracket the
  fixture; `stop` signals `sqlservr` directly, because systemd's stop waits up to 30 minutes in
  WSL.
- On Windows the suite runs `tests/selfhost/sqlserver.ps1` against the CELVYX instance on TCP
  14330. It creates the `neper` login and database through Windows authentication.
  `tests/selfhost/sqlserver_tls.ps1`, run once in an elevated Windows PowerShell, gives that
  instance the certificate strict connections need, and exports it to
  `D:\tools\mssql\neper-tls.cer`.
