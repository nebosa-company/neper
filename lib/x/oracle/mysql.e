// An `e.db` driver over MySQL's C client library. `open` takes an `Options` and answers a
// `db.Connection` whose table is this module's; everything after that goes through `e.db`.
//
// Memory: the arena handed to `open` is retained and borrowed for the connection's life.
// Contexts, column names and row buffers come from it; a reader's values are copied into a
// buffer of its own that is valid until its next row. Read with `db.reader_next_borrowed`,
// text and binary values are the client library's row instead, valid until the next row or
// the reader's end. Error text is kept in fixed buffers the
// connection allocates once, so failures do not grow the arena.
//
// Parameters: `?` placeholders, positional. Values are rendered into the statement on this
// side -- text through `mysql_real_escape_string` for the connection's character set, blobs as
// hex literals, floats as the shortest double literal that reads back exactly -- which keeps
// the binding to plain calls rather than `MYSQL_BIND`, whose layout differs between client
// versions. A placeholder inside a string, identifier or comment is not one. A named
// `db.Parameter` is refused.
//
// Statements: `execute` runs every statement in its text; `query` and `prepare` take one.
// `prepare` has the server compile the text (`PREPARE ... FROM`) so a statement that cannot
// run fails there, then keeps it and renders the parameters at each execution.
//
// Values come back from the text protocol and are converted by column type: integers (with
// `UNSIGNED` past `i64` as `U64`), `TINYINT(1)` as `Bool`, `FLOAT`/`DOUBLE` read exactly,
// `DATE`/`DATETIME`/`TIMESTAMP` as `Time` in UTC (the session's time zone is set to UTC at
// `open`), binary strings and blobs as `Bytes`, and `DECIMAL`, `TIME`, `JSON`, `ENUM`, `SET`
// and the text types as `Text`. A zero date has no instant, so it comes back as its text.
//
// Streaming: a query reads rows from the server one at a time (`mysql_use_result`). While a
// reader is open the connection is busy: another call on it answers `db.Busy`. Closing a
// reader early reads and discards the rows still to come.
use e.mem
use e.str
use e.time
use e.db
use e.bytes as octets
use x.oracle.mysqlclient

type Options = struct { host: str, port: u16, user: str, password: str, database: str }
type Detail = struct { code: u32, sqlstate: str, message: str }
error CannotConnect
error Failed

// 5.7: every call bound here, and utf8mb4.
const MIN_VERSION: usize = 50700usize

type Conn = struct { handle: usize, arena: *mem.Arena, driver: *const db.Driver, active: *Reader, in_transaction: bool, statements: u64, code: u32, state: []u8, state_len: usize, message: []u8, message_len: usize }
type Stmt = struct { conn: *Conn, sql: str, placeholders: usize, closed: bool }
type Reader = struct { conn: *Conn, statement: *Stmt, result: usize, done: bool, closed: bool, types: []u32, flags: []u32, binary: []bool, widths: []usize, columns: []db.Column, buffer: []u8, used: usize, borrow: bool }
type Tx = struct { conn: *Conn }
type Scan = struct { placeholders: usize, statements: usize }

const MYSQL_SET_CHARSET_NAME: i32 = 7i32
// CLIENT_MULTI_STATEMENTS | CLIENT_MULTI_RESULTS
const CLIENT_FLAGS: usize = 196608usize
const UNSIGNED_FLAG: u32 = 32u32
const BINARY_CHARSET: u32 = 63u32

const TYPE_DECIMAL: u32 = 0u32
const TYPE_TINY: u32 = 1u32
const TYPE_SHORT: u32 = 2u32
const TYPE_LONG: u32 = 3u32
const TYPE_FLOAT: u32 = 4u32
const TYPE_DOUBLE: u32 = 5u32
const TYPE_NULL: u32 = 6u32
const TYPE_TIMESTAMP: u32 = 7u32
const TYPE_LONGLONG: u32 = 8u32
const TYPE_INT24: u32 = 9u32
const TYPE_DATE: u32 = 10u32
const TYPE_TIME: u32 = 11u32
const TYPE_DATETIME: u32 = 12u32
const TYPE_YEAR: u32 = 13u32
const TYPE_NEWDATE: u32 = 14u32
const TYPE_VARCHAR: u32 = 15u32
const TYPE_BIT: u32 = 16u32
const TYPE_JSON: u32 = 245u32
const TYPE_NEWDECIMAL: u32 = 246u32
const TYPE_ENUM: u32 = 247u32
const TYPE_SET: u32 = 248u32
const TYPE_TINY_BLOB: u32 = 249u32
const TYPE_MEDIUM_BLOB: u32 = 250u32
const TYPE_LONG_BLOB: u32 = 251u32
const TYPE_BLOB: u32 = 252u32
const TYPE_VAR_STRING: u32 = 253u32
const TYPE_STRING: u32 = 254u32

const I64_MAX: u64 = 9223372036854775807u64
const MAX_C_STRING: usize = 1048576usize
const STATE_CAP: usize = 8usize
const MESSAGE_CAP: usize = 1024usize

fn version() -> usize { ret mysqlclient.client_version() }

fn open(a: *mem.Arena, options: Options) -> (db.Connection, err) {
    var connection: db.Connection = zero
    if version() < MIN_VERSION { ret (connection, db.Unsupported) }
    let handle = mysqlclient.init(0usize)
    if handle == 0usize { ret (connection, CannotConnect) }
    var charset: [8]u8 = zero
    let charset_len = keep(charset[0usize..7usize], "utf8mb4")
    let charset_set = mysqlclient.options(handle, MYSQL_SET_CHARSET_NAME, &charset[0usize])
    let mark = mem.mark(a)
    let (host, host_error) = c_optional(a, options.host)
    let (user, user_error) = c_optional(a, options.user)
    let (password, password_error) = c_optional(a, options.password)
    let (database, database_error) = c_optional(a, options.database)
    if host_error != ok || user_error != ok || password_error != ok || database_error != ok {
        mem.reset(a, mark)
        mysqlclient.close(handle)
        ret (connection, db.Unsupported)
    }
    let connected = mysqlclient.real_connect(handle, host, user, password, database, u32(options.port), 0usize, CLIENT_FLAGS)
    mem.reset(a, mark)
    if connected == 0usize {
        mysqlclient.close(handle)
        ret (connection, CannotConnect)
    }
    let (conns, conn_error) = mem.alloc[Conn](a, 1usize)
    let (drivers, driver_error) = mem.alloc[db.Driver](a, 1usize)
    let (text_buffers, text_error) = mem.alloc[u8](a, STATE_CAP + MESSAGE_CAP)
    if conn_error != ok || driver_error != ok || text_error != ok {
        mysqlclient.close(handle)
        ret (connection, db.Unsupported)
    }
    drivers[0usize] = db.Driver { close: d_close, prepare: d_prepare, execute: d_execute, query: d_query, begin: d_begin, statement_close: d_statement_close, statement_execute: d_statement_execute, statement_query: d_statement_query, rows_columns: d_rows_columns, rows_next: d_rows_next, rows_next_borrowed: d_rows_next_borrowed, rows_close: d_rows_close, transaction_execute: d_transaction_execute, transaction_query: d_transaction_query, transaction_commit: d_transaction_commit, transaction_rollback: d_transaction_rollback }
    // Arena memory is not cleared, so every field is written.
    conns[0usize] = Conn { handle: handle, arena: a, driver: &drivers[0usize], active: nil, in_transaction: false, statements: 0u64, code: 0u32, state: text_buffers[0usize..STATE_CAP], state_len: 0usize, message: text_buffers[STATE_CAP..], message_len: 0usize }
    let c = &conns[0usize]
    // `TIMESTAMP` values are converted to the session's zone; UTC makes an instant read back as
    // the instant written.
    let (ignored, zone_error) = execute_text(c, "SET time_zone = '+00:00'", zero)
    if zone_error != ok {
        mysqlclient.close(handle)
        ret (connection, zone_error)
    }
    connection.ctx = mem.cast[*void](c)
    connection.driver = c.driver
    ret (connection, ok)
}

// Why the connection's last call failed: the server's error number, SQLSTATE and message, or
// -- when the driver refused before sending anything -- code 0 and the driver's reason. The
// strings are copied into `a`.
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err) {
    var out: Detail = zero
    if connection.ctx == nil { ret (out, db.Closed) }
    let c = conn_of(connection.ctx)
    let (sqlstate, state_error) = copy_text(a, c.state[0usize..c.state_len])
    if state_error != ok { ret (out, state_error) }
    let (message, message_error) = copy_text(a, c.message[0usize..c.message_len])
    if message_error != ok { ret (out, message_error) }
    out = Detail { code: c.code, sqlstate: sqlstate, message: message }
    ret (out, ok)
}

fn conn_of(ctx: *void) -> *Conn { ret mem.cast[*Conn](ctx) }
fn stmt_of(ctx: *void) -> *Stmt { ret mem.cast[*Stmt](ctx) }
fn reader_of(ctx: *void) -> *Reader { ret mem.cast[*Reader](ctx) }
fn tx_of(ctx: *void) -> *Tx { ret mem.cast[*Tx](ctx) }

fn copy_text(a: *mem.Arena, s: []const u8) -> (str, err) {
    if s.len == 0usize { ret ("", ok) }
    let (bytes, allocation_error) = mem.alloc[u8](a, s.len)
    if allocation_error != ok { ret ("", allocation_error) }
    mem.copy[u8](bytes, s)
    ret (bytes, ok)
}

// --- errors

fn keep(dst: []u8, s: []const u8) -> usize {
    var n = s.len
    if n > dst.len { n = dst.len }
    var i = 0usize
    while i < n {
        dst[i] = s[i]
        i += 1usize
    }
    ret n
}

fn keep_c(dst: []u8, p: *u8) -> usize {
    if mem.address_of(p) == 0usize { ret 0usize }
    var n = c_length(p)
    if n > dst.len { n = dst.len }
    copy_foreign(dst[0usize..n], p, n)
    ret n
}

fn clear_detail(c: *Conn) {
    c.code = 0u32
    c.state_len = 0usize
    c.message_len = 0usize
}

fn refuse(c: *Conn, note: str, e: err) -> err {
    clear_detail(c)
    c.message_len = keep(c.message, note)
    ret e
}

// The connection's last error, recorded and mapped.
fn failure(c: *Conn) -> err {
    c.code = mysqlclient.errno(c.handle)
    c.state_len = keep_c(c.state, mysqlclient.sqlstate(c.handle))
    c.message_len = keep_c(c.message, mysqlclient.error_text(c.handle))
    ret mapped(c.code, c.state[0usize..c.state_len])
}

fn starts(s: []const u8, prefix: str) -> bool {
    if s.len < prefix.len { ret false }
    var i = 0usize
    while i < prefix.len {
        if s[i] != prefix[i] { ret false }
        i += 1usize
    }
    ret true
}

// SQLSTATE classes first. MySQL reports some under the catch-all `HY000`, so those are known by
// number: a CHECK violation (3819) is a constraint, and a lock wait timeout (1205), a deadlock
// (1213) and a NOWAIT lock (3572) are busy.
fn mapped(code: u32, state: []const u8) -> err {
    if starts(state, "23") || code == 3819u32 { ret db.Constraint }
    if starts(state, "40001") || code == 1205u32 || code == 1213u32 || code == 3572u32 { ret db.Busy }
    if starts(state, "42") || starts(state, "22") || starts(state, "3D") || code == 1065u32 { ret db.InvalidQuery }
    ret Failed
}

// --- foreign memory

// A NUL-terminated copy's address, or 0 for an empty string (the library's default).
fn c_optional(a: *mem.Arena, s: str) -> (usize, err) {
    if s.len == 0usize { ret (0usize, ok) }
    let (bytes, bytes_error) = c_copy(a, s)
    if bytes_error != ok { ret (0usize, bytes_error) }
    ret (mem.address_of(&bytes[0usize]), ok)
}

fn c_copy(a: *mem.Arena, s: str) -> ([]u8, err) {
    let (bytes, allocation_error) = mem.alloc[u8](a, s.len + 1usize)
    if allocation_error != ok { ret (bytes, allocation_error) }
    var i = 0usize
    while i < s.len {
        bytes[i] = s[i]
        i += 1usize
    }
    bytes[s.len] = 0u8
    ret (bytes, ok)
}

fn copy_foreign(dst: []u8, p: *u8, n: usize) {
    var region: mem.Arena = zero
    region.base = p
    region.cap = n
    region.off = 0usize
    let copied = octets.copy(dst[0usize..n], mem.view(&region, 0usize, n))
}

fn c_length(p: *u8) -> usize {
    var region: mem.Arena = zero
    region.base = p
    region.cap = MAX_C_STRING
    region.off = 0usize
    let bytes = mem.view(&region, 0usize, MAX_C_STRING)
    var n = 0usize
    while n < MAX_C_STRING && bytes[n] != 0u8 { n += 1usize }
    ret n
}

// The pointer stored at `base[index]` of a C array of pointers.
fn pointer_at(base: *u8, index: usize) -> *u8 {
    var region: mem.Arena = zero
    region.base = base
    region.cap = (index + 1usize) * 8usize
    region.off = 0usize
    let bytes = mem.view(&region, 0usize, (index + 1usize) * 8usize)
    let slot = mem.cast[**u8](&bytes[index * 8usize])
    ret *slot
}

// The `unsigned int` at `offset` into a foreign struct.
fn u32_at(base: *u8, offset: usize) -> u32 {
    var region: mem.Arena = zero
    region.base = base
    region.cap = offset + 4usize
    region.off = 0usize
    let bytes = mem.view(&region, offset, 4usize)
    ret u32(bytes[0usize]) | u32(bytes[1usize]) << 8u32 | u32(bytes[2usize]) << 16u32 | u32(bytes[3usize]) << 24u32
}

// --- rendering parameters

fn decimal_i64(a: *mem.Arena, v: i64) -> (str, err) {
    var (b, builder_error) = str.builder(a, 24usize)
    if builder_error != ok { ret ("", builder_error) }
    let push_error = str.push_i64(&b, v)
    if push_error != ok { ret ("", push_error) }
    ret (str.done(&b), ok)
}

fn decimal_u64(a: *mem.Arena, v: u64) -> (str, err) {
    var (b, builder_error) = str.builder(a, 24usize)
    if builder_error != ok { ret ("", builder_error) }
    let push_error = str.push_u64(&b, v)
    if push_error != ok { ret ("", push_error) }
    ret (str.done(&b), ok)
}

// The shortest text that reads back as `v`, made a double literal: without an exponent MySQL
// reads `0.1` as a DECIMAL.
fn double_literal(c: *Conn, a: *mem.Arena, v: f64) -> (str, err) {
    var (b, builder_error) = str.builder(a, 40usize)
    if builder_error != ok { ret ("", builder_error) }
    let push_error = str.push_f64(&b, v)
    if push_error != ok { ret ("", push_error) }
    let spelled = str.done(&b)
    if str.eq(spelled, "inf") || str.eq(spelled, "-inf") || str.eq(spelled, "nan") { ret ("", refuse(c, "MySQL has no infinite or NaN double", db.Unsupported)) }
    var has_exponent = false
    var i = 0usize
    while i < spelled.len {
        if spelled[i] == 101u8 || spelled[i] == 69u8 { has_exponent = true }
        i += 1usize
    }
    if has_exponent { ret (spelled, ok) }
    let (literal, literal_error) = str.concat(a, spelled, "e0")
    ret (literal, literal_error)
}

fn digits_into(out: []u8, at: usize, value: i64, width: usize) {
    var v = value
    var i = width
    while i > 0usize {
        i -= 1usize
        out[at + i] = u8.trunc(48i64 + v % 10i64)
        v = v / 10i64
    }
}

// `'YYYY-MM-DD HH:MM:SS.ffffff'` in UTC; MySQL keeps microseconds at most.
fn datetime_literal(c: *Conn, a: *mem.Arena, instant: time.Instant) -> (str, err) {
    let micros = time.floor_div(instant.nanos, 1000i64)
    let day = time.floor_div(micros, 86400000000i64)
    let within = micros - day * 86400000000i64
    // Nanoseconds in an `i64` span 1677 to 2262, inside MySQL's 1000 to 9999.
    let (year, month, date) = time.civil_from_days(day)
    let (out, out_error) = mem.alloc[u8](a, 28usize)
    if out_error != ok { ret ("", out_error) }
    out[0usize] = 39u8
    digits_into(out, 1usize, year, 4usize)
    out[5usize] = 45u8
    digits_into(out, 6usize, month, 2usize)
    out[8usize] = 45u8
    digits_into(out, 9usize, date, 2usize)
    out[11usize] = 32u8
    digits_into(out, 12usize, within / 3600000000i64, 2usize)
    out[14usize] = 58u8
    digits_into(out, 15usize, within / 60000000i64 % 60i64, 2usize)
    out[17usize] = 58u8
    digits_into(out, 18usize, within / 1000000i64 % 60i64, 2usize)
    out[20usize] = 46u8
    digits_into(out, 21usize, within % 1000000i64, 6usize)
    out[27usize] = 39u8
    ret (out, ok)
}

fn quoted_text(c: *Conn, a: *mem.Arena, s: str) -> (str, err) {
    if s.len > (mysqlclient.max_length() - 1usize) / 2usize { ret ("", refuse(c, "a text value is longer than the client library accepts", db.Unsupported)) }
    let (out, out_error) = mem.alloc[u8](a, s.len * 2usize + 3usize)
    if out_error != ok { ret ("", out_error) }
    out[0usize] = 39u8
    var n = 0usize
    if s.len != 0usize { n = mysqlclient.real_escape_string(c.handle, &out[1usize], &s[0usize], s.len) }
    out[n + 1usize] = 39u8
    ret (out[0usize..n + 2usize], ok)
}

fn hex_literal(a: *mem.Arena, data: []const u8) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, data.len * 2usize + 3usize)
    if out_error != ok { ret ("", out_error) }
    let hex = "0123456789ABCDEF"
    out[0usize] = 88u8
    out[1usize] = 39u8
    var i = 0usize
    while i < data.len {
        out[2usize + i * 2usize] = hex[usize(data[i] >> 4u8)]
        out[3usize + i * 2usize] = hex[usize(data[i] & 15u8)]
        i += 1usize
    }
    out[2usize + data.len * 2usize] = 39u8
    ret (out, ok)
}

fn render(c: *Conn, a: *mem.Arena, value: db.Value) -> (str, err) {
    switch value {
    case .Null:
        ret ("NULL", ok)
    case .Bool as flag:
        if flag { ret ("TRUE", ok) }
        ret ("FALSE", ok)
    case .I64 as signed:
        let (signed_text, signed_error) = decimal_i64(a, signed)
        ret (signed_text, signed_error)
    case .U64 as unsigned:
        let (unsigned_text, unsigned_error) = decimal_u64(a, unsigned)
        ret (unsigned_text, unsigned_error)
    case .F64 as real:
        let (real_text, real_error) = double_literal(c, a, real)
        ret (real_text, real_error)
    case .Text as s:
        let (quoted, quoted_error) = quoted_text(c, a, s)
        ret (quoted, quoted_error)
    case .Bytes as data:
        let (hexed, hexed_error) = hex_literal(a, data)
        ret (hexed, hexed_error)
    case .Time as instant:
        let (stamp, stamp_error) = datetime_literal(c, a, instant)
        ret (stamp, stamp_error)
    }
}

// --- the statement scanner

fn is_space(b: u8) -> bool { ret b == 32u8 || b == 9u8 || b == 10u8 || b == 13u8 || b == 12u8 || b == 11u8 }

// Walks `sql` as MySQL's lexer would, counting `?` placeholders and statements. With `out`
// long enough it also copies the text into it with the `k`th placeholder replaced by
// `rendered[k]`, answering the length written. Strings (`'...'`, `"..."`, with backslash
// escapes and doubled quotes), quoted identifiers and comments (`#`, `-- `, `/* */`) carry
// no placeholders and no statement ends.
fn walk(sql: str, rendered: []const str, out: []u8) -> (Scan, usize) {
    var scan: Scan = zero
    let writing = out.len != 0usize
    var n = 0usize
    var i = 0usize
    var in_statement = false
    while i < sql.len {
        let b = sql[i]
        var skip_to = i + 1usize
        var significant = true
        if b == 39u8 || b == 34u8 || b == 96u8 {
            var j = i + 1usize
            while j < sql.len {
                if sql[j] == 92u8 && b != 96u8 {
                    j += 2usize
                } else if sql[j] == b {
                    if j + 1usize < sql.len && sql[j + 1usize] == b {
                        j += 2usize
                    } else {
                        j += 1usize
                        break
                    }
                } else {
                    j += 1usize
                }
            }
            if j > sql.len { j = sql.len }
            skip_to = j
        } else if b == 35u8 || (b == 45u8 && i + 2usize < sql.len + 1usize && i + 1usize < sql.len && sql[i + 1usize] == 45u8 && (i + 2usize == sql.len || is_space(sql[i + 2usize]))) {
            var k = i
            while k < sql.len && sql[k] != 10u8 { k += 1usize }
            skip_to = k
            significant = false
        } else if b == 47u8 && i + 1usize < sql.len && sql[i + 1usize] == 42u8 {
            var m = i + 2usize
            while m + 1usize < sql.len && !(sql[m] == 42u8 && sql[m + 1usize] == 47u8) { m += 1usize }
            skip_to = m + 2usize
            if skip_to > sql.len { skip_to = sql.len }
            significant = false
        } else if is_space(b) {
            significant = false
        } else if b == 59u8 {
            in_statement = false
            significant = false
        }
        if significant && !in_statement {
            in_statement = true
            scan.statements += 1usize
        }
        if b == 63u8 {
            if writing && scan.placeholders < rendered.len {
                let piece = rendered[scan.placeholders]
                var p = 0usize
                while p < piece.len {
                    out[n] = piece[p]
                    n += 1usize
                    p += 1usize
                }
            }
            scan.placeholders += 1usize
        } else if writing {
            var q = i
            while q < skip_to {
                out[n] = sql[q]
                n += 1usize
                q += 1usize
            }
        }
        i = skip_to
    }
    ret (scan, n)
}

// The statement with its parameters rendered in, NUL-terminated, and what the scan found.
fn interpolate(c: *Conn, sql: str, params: []const db.Parameter) -> (str, Scan, err) {
    var nothing: []u8 = zero
    let (scan, unused) = walk(sql, zero, nothing)
    if scan.placeholders != params.len { ret ("", scan, refuse(c, "the statement's parameter count differs from the parameters given", db.InvalidQuery)) }
    let (rendered, rendered_error) = mem.alloc[str](c.arena, params.len)
    if rendered_error != ok { ret ("", scan, rendered_error) }
    var total = sql.len + 1usize
    var i = 0usize
    while i < params.len {
        if params[i].name.len != 0usize { ret ("", scan, refuse(c, "named parameters are not supported; write ?", db.InvalidQuery)) }
        let (piece, piece_error) = render(c, c.arena, params[i].value)
        if piece_error != ok { ret ("", scan, piece_error) }
        rendered[i] = piece
        total += piece.len
        i += 1usize
    }
    let (out, out_error) = mem.alloc[u8](c.arena, total)
    if out_error != ok { ret ("", scan, out_error) }
    let (again, written) = walk(sql, rendered, out)
    out[written] = 0u8
    ret (out[0usize..written], scan, ok)
}

// --- running statements

// Reads every result the last query produced, summing affected rows; a result set is read and
// discarded. The first failure (the text stops at it) is kept.
fn collect(c: *Conn) -> (u64, err) {
    var affected = 0u64
    while true {
        if mysqlclient.field_count(c.handle) > 0u32 {
            let result = mysqlclient.use_result(c.handle)
            if result != 0usize { mysqlclient.free_result(result) }
        } else {
            affected += mysqlclient.affected_rows(c.handle)
        }
        let more = mysqlclient.next_result(c.handle)
        if more == -1i32 { break }
        if more > 0i32 { ret (affected, failure(c)) }
    }
    ret (affected, ok)
}

// Sends a statement text; answers false with the error recorded when it did not run. An empty
// text (whitespace and comments) runs nothing.
fn send(c: *Conn, text: str) -> err {
    if text.len > mysqlclient.max_length() { ret refuse(c, "the statement is longer than the client library accepts", db.Unsupported) }
    if mysqlclient.real_query(c.handle, &text[0usize], text.len) != 0i32 { ret failure(c) }
    ret ok
}

fn execute_text(c: *Conn, sql: str, params: []const db.Parameter) -> (u64, err) {
    if c.active != nil { ret (0u64, refuse(c, "a row reader is still open on this connection", db.Busy)) }
    let mark = mem.mark(c.arena)
    let (text, scan, interpolate_error) = interpolate(c, sql, params)
    if interpolate_error != ok {
        mem.reset(c.arena, mark)
        ret (0u64, interpolate_error)
    }
    if scan.statements == 0usize {
        mem.reset(c.arena, mark)
        clear_detail(c)
        ret (0u64, ok)
    }
    let send_error = send(c, text)
    mem.reset(c.arena, mark)
    if send_error != ok { ret (0u64, send_error) }
    let (affected, collect_error) = collect(c)
    if collect_error == ok { clear_detail(c) }
    ret (affected, collect_error)
}

// --- row readers

fn is_integer_type(t: u32) -> bool {
    ret t == TYPE_TINY || t == TYPE_SHORT || t == TYPE_LONG || t == TYPE_LONGLONG || t == TYPE_INT24 || t == TYPE_YEAR
}

fn is_date_type(t: u32) -> bool { ret t == TYPE_DATE || t == TYPE_DATETIME || t == TYPE_TIMESTAMP || t == TYPE_NEWDATE }

fn is_string_type(t: u32) -> bool {
    ret t == TYPE_VARCHAR || t == TYPE_VAR_STRING || t == TYPE_STRING || t == TYPE_TINY_BLOB || t == TYPE_MEDIUM_BLOB || t == TYPE_LONG_BLOB || t == TYPE_BLOB
}

fn kind_of(t: u32, flags: u32, binary: bool, width: usize) -> db.ValueKind {
    if t == TYPE_TINY && width == 1usize { ret .Bool }
    if is_integer_type(t) {
        if flags & UNSIGNED_FLAG != 0u32 && t == TYPE_LONGLONG { ret .U64 }
        ret .I64
    }
    if t == TYPE_FLOAT || t == TYPE_DOUBLE { ret .F64 }
    if is_date_type(t) { ret .Time }
    if t == TYPE_NULL { ret .Null }
    if is_string_type(t) {
        if binary { ret .Bytes }
        ret .Text
    }
    if t == TYPE_DECIMAL || t == TYPE_NEWDECIMAL || t == TYPE_TIME || t == TYPE_JSON || t == TYPE_ENUM || t == TYPE_SET { ret .Text }
    ret .Bytes
}

fn start_reader(c: *Conn, statement: *Stmt) -> (db.Rows, err) {
    var rows: db.Rows = zero
    var result = 0usize
    var count = 0usize
    if mysqlclient.field_count(c.handle) > 0u32 {
        result = mysqlclient.use_result(c.handle)
        if result == 0usize { ret (rows, failure(c)) }
        count = usize(mysqlclient.num_fields(result))
    }
    let (readers, reader_error) = mem.alloc[Reader](c.arena, 1usize)
    let (types, types_error) = mem.alloc[u32](c.arena, count)
    let (flags, flags_error) = mem.alloc[u32](c.arena, count)
    let (binary, binary_error) = mem.alloc[bool](c.arena, count)
    let (widths, widths_error) = mem.alloc[usize](c.arena, count)
    let (cols, cols_error) = mem.alloc[db.Column](c.arena, count)
    if reader_error != ok || types_error != ok || flags_error != ok || binary_error != ok || widths_error != ok || cols_error != ok {
        if result != 0usize { mysqlclient.free_result(result) }
        let (dropped, dropped_error) = collect(c)
        ret (rows, db.Unsupported)
    }
    var i = 0usize
    while i < count {
        let field = mysqlclient.fetch_field_direct(result, u32(i))
        types[i] = u32_at(field, mysqlclient.FIELD_TYPE)
        flags[i] = u32_at(field, mysqlclient.FIELD_FLAGS)
        binary[i] = u32_at(field, mysqlclient.FIELD_CHARSETNR) == BINARY_CHARSET
        widths[i] = mysqlclient.field_length(field)
        let name_len = usize(u32_at(field, mysqlclient.FIELD_NAME_LENGTH))
        let (name, name_error) = mem.alloc[u8](c.arena, name_len)
        if name_error != ok { ret (rows, name_error) }
        copy_foreign(name, pointer_at(field, 0usize), name_len)
        let name_text: str = name
        cols[i] = db.Column { name: name_text, kind: kind_of(types[i], flags[i], binary[i], widths[i]), nullable: true }
        i += 1usize
    }
    var no_buffer: []u8 = zero
    readers[0usize] = Reader { conn: c, statement: statement, result: result, done: result == 0usize, closed: false, types: types, flags: flags, binary: binary, widths: widths, columns: cols, buffer: no_buffer, used: 0usize, borrow: false }
    let r = &readers[0usize]
    if result == 0usize {
        let (after, after_error) = collect(c)
        if after_error != ok { ret (rows, after_error) }
    } else {
        c.active = r
    }
    clear_detail(c)
    rows.ctx = mem.cast[*void](r)
    ret (rows, ok)
}

fn start_query(c: *Conn, sql: str, params: []const db.Parameter, statement: *Stmt) -> (db.Rows, err) {
    if c.active != nil { ret (zero, refuse(c, "a row reader is still open on this connection", db.Busy)) }
    let mark = mem.mark(c.arena)
    let (text, scan, interpolate_error) = interpolate(c, sql, params)
    if interpolate_error != ok {
        mem.reset(c.arena, mark)
        ret (zero, interpolate_error)
    }
    if scan.statements != 1usize {
        mem.reset(c.arena, mark)
        ret (zero, refuse(c, "a query takes exactly one statement", db.InvalidQuery))
    }
    let send_error = send(c, text)
    mem.reset(c.arena, mark)
    if send_error != ok { ret (zero, send_error) }
    let (rows, rows_error) = start_reader(c, statement)
    ret (rows, rows_error)
}

// Ends a reader that has not reached its end: freeing a streamed result reads what is left.
fn finish_reader(r: *Reader) {
    if r.done { ret }
    r.done = true
    mysqlclient.free_result(r.result)
    r.result = 0usize
    while mysqlclient.next_result(r.conn.handle) == 0i32 {
        if mysqlclient.field_count(r.conn.handle) > 0u32 {
            let extra = mysqlclient.use_result(r.conn.handle)
            if extra != 0usize { mysqlclient.free_result(extra) }
        }
    }
    if r.conn.active == r { r.conn.active = nil }
}

fn reserve(r: *Reader, n: usize) -> err {
    if r.used + n <= r.buffer.len { ret ok }
    var size = r.buffer.len * 2usize
    if size < 256usize { size = 256usize }
    if size < n { size = n }
    let (grown, grow_error) = mem.alloc[u8](r.conn.arena, size)
    if grow_error != ok { ret grow_error }
    r.buffer = grown
    r.used = 0usize
    ret ok
}

fn take(r: *Reader, v: []const u8) -> ([]u8, err) {
    let reserve_error = reserve(r, v.len)
    if reserve_error != ok { ret (r.buffer[0usize..0usize], reserve_error) }
    let start = r.used
    r.used = start + v.len
    let out = r.buffer[start..start + v.len]
    let moved = octets.copy(out, v)
    ret (out, ok)
}

fn digits_at(v: []const u8, at: usize, width: usize) -> (i64, bool) {
    if at + width > v.len { ret (0i64, false) }
    var value = 0i64
    var i = 0usize
    while i < width {
        let d = v[at + i]
        if d < 48u8 || d > 57u8 { ret (0i64, false) }
        value = value * 10i64 + i64(d - 48u8)
        i += 1usize
    }
    ret (value, true)
}

// `YYYY-MM-DD[ HH:MM:SS[.f...]]` in UTC as an instant; false for anything else, including
// MySQL's zero dates, which name no day.
fn parse_datetime(v: []const u8) -> (i64, bool) {
    let (year, year_ok) = digits_at(v, 0usize, 4usize)
    let (month, month_ok) = digits_at(v, 5usize, 2usize)
    let (day, day_ok) = digits_at(v, 8usize, 2usize)
    if !year_ok || !month_ok || !day_ok || v[4usize] != 45u8 || v[7usize] != 45u8 { ret (0i64, false) }
    if month < 1i64 || month > 12i64 || day < 1i64 || day > time.days_in_month(year, month) { ret (0i64, false) }
    var nanos = time.days_from_civil(year, month, day) * 86400000000000i64
    if v.len == 10usize { ret (nanos, true) }
    let (hour, hour_ok) = digits_at(v, 11usize, 2usize)
    let (minute, minute_ok) = digits_at(v, 14usize, 2usize)
    let (second, second_ok) = digits_at(v, 17usize, 2usize)
    if !hour_ok || !minute_ok || !second_ok { ret (0i64, false) }
    nanos += ((hour * 60i64 + minute) * 60i64 + second) * 1000000000i64
    if v.len > 20usize && v[19usize] == 46u8 {
        var scale = 100000000i64
        var f = 20usize
        while f < v.len && scale > 0i64 {
            let d = v[f]
            if d < 48u8 || d > 57u8 { ret (0i64, false) }
            nanos += i64(d - 48u8) * scale
            scale = scale / 10i64
            f += 1usize
        }
    }
    ret (nanos, true)
}

fn decode(r: *Reader, i: usize, v: []const u8) -> (db.Value, err) {
    var value: db.Value = .Null
    let t = r.types[i]
    let kind = r.columns[i].kind
    if kind == .Bool {
        value = db.Value{ Bool: v.len != 0usize && v[0usize] != 48u8 }
        ret (value, ok)
    }
    if is_integer_type(t) {
        if r.flags[i] & UNSIGNED_FLAG != 0u32 {
            let (unsigned, unsigned_error) = str.parse_u64(v)
            if unsigned_error != ok { ret (value, unsigned_error) }
            if unsigned > I64_MAX {
                value = db.Value{ U64: unsigned }
            } else {
                value = db.Value{ I64: i64(unsigned) }
            }
            ret (value, ok)
        }
        let (signed, signed_error) = str.parse_i64(v)
        if signed_error != ok { ret (value, signed_error) }
        value = db.Value{ I64: signed }
        ret (value, ok)
    }
    if t == TYPE_FLOAT || t == TYPE_DOUBLE {
        let (real, real_error) = str.parse_f64(v)
        if real_error != ok { ret (value, real_error) }
        value = db.Value{ F64: real }
        ret (value, ok)
    }
    if is_date_type(t) {
        let (nanos, parsed) = parse_datetime(v)
        if parsed {
            value = db.Value{ Time: time.Instant { nanos: nanos } }
            ret (value, ok)
        }
    }
    if r.borrow {
        if kind == .Bytes {
            value = db.Value{ Bytes: v }
        } else {
            let borrowed_text: str = v
            value = db.Value{ Text: borrowed_text }
        }
        ret (value, ok)
    }
    let (copied, copy_error) = take(r, v)
    if copy_error != ok { ret (value, copy_error) }
    if kind == .Bytes {
        value = db.Value{ Bytes: copied }
    } else {
        let copied_text: str = copied
        value = db.Value{ Text: copied_text }
    }
    ret (value, ok)
}

fn fill(r: *Reader, row: *u8, dst: []db.Value) -> err {
    r.used = 0usize
    let lengths = mysqlclient.fetch_lengths(r.result)
    var region: mem.Arena = zero
    var i = 0usize
    while i < r.columns.len {
        let cell = pointer_at(row, i)
        if mem.address_of(cell) == 0usize {
            dst[i] = .Null
        } else {
            let n = mysqlclient.length_at(lengths, i)
            region.base = cell
            region.cap = n
            region.off = 0usize
            let (value, decode_error) = decode(r, i, mem.view(&region, 0usize, n))
            if decode_error != ok { ret decode_error }
            dst[i] = value
        }
        i += 1usize
    }
    ret ok
}

// --- the driver table

fn d_close(ctx: *void) -> err {
    let c = conn_of(ctx)
    if c.active != nil { finish_reader(c.active) }
    mysqlclient.close(c.handle)
    ret ok
}

// The server compiles the text once, so a statement that cannot run fails here; the compiled
// form is dropped again and the text kept, since parameters are rendered at each execution.
fn d_prepare(ctx: *void, sql: str) -> (db.Statement, err) {
    let c = conn_of(ctx)
    var statement: db.Statement = zero
    if c.active != nil { ret (statement, refuse(c, "a row reader is still open on this connection", db.Busy)) }
    var nothing: []u8 = zero
    let (scan, unused) = walk(sql, zero, nothing)
    if scan.statements != 1usize { ret (statement, refuse(c, "a prepared statement takes exactly one statement", db.InvalidQuery)) }
    let mark = mem.mark(c.arena)
    let (quoted, quoted_error) = quoted_text(c, c.arena, sql)
    if quoted_error != ok {
        mem.reset(c.arena, mark)
        ret (statement, quoted_error)
    }
    let (check, check_error) = str.concat(c.arena, "PREPARE np_x_oracle_mysql_check FROM ", quoted)
    if check_error != ok {
        mem.reset(c.arena, mark)
        ret (statement, check_error)
    }
    let send_error = send(c, check)
    mem.reset(c.arena, mark)
    if send_error != ok { ret (statement, send_error) }
    let (prepared, prepared_error) = collect(c)
    if prepared_error != ok { ret (statement, prepared_error) }
    let (dropped, drop_error) = execute_text(c, "DEALLOCATE PREPARE np_x_oracle_mysql_check", zero)
    if drop_error != ok { ret (statement, drop_error) }
    let (kept, kept_error) = copy_text(c.arena, sql)
    let (stmts, stmt_error) = mem.alloc[Stmt](c.arena, 1usize)
    if kept_error != ok || stmt_error != ok { ret (statement, db.Unsupported) }
    stmts[0usize] = Stmt { conn: c, sql: kept, placeholders: scan.placeholders, closed: false }
    clear_detail(c)
    statement.ctx = mem.cast[*void](&stmts[0usize])
    ret (statement, ok)
}

fn d_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = execute_text(conn_of(ctx), sql, params)
    ret (affected, execute_error)
}

fn d_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, rows_error) = start_query(conn_of(ctx), sql, params, nil)
    ret (rows, rows_error)
}

// One transaction at a time: a second START TRANSACTION would silently commit the first.
fn d_begin(ctx: *void) -> (db.Transaction, err) {
    let c = conn_of(ctx)
    var transaction: db.Transaction = zero
    if c.active != nil { ret (transaction, refuse(c, "a row reader is still open on this connection", db.Busy)) }
    if c.in_transaction { ret (transaction, refuse(c, "a transaction is already open on this connection", db.Busy)) }
    let (txs, tx_error) = mem.alloc[Tx](c.arena, 1usize)
    if tx_error != ok { ret (transaction, tx_error) }
    let (ignored, begin_error) = execute_text(c, "START TRANSACTION", zero)
    if begin_error != ok { ret (transaction, begin_error) }
    c.in_transaction = true
    txs[0usize] = Tx { conn: c }
    transaction.ctx = mem.cast[*void](&txs[0usize])
    ret (transaction, ok)
}

// A reader of this statement still streaming is ended first, and answers `Closed` after.
fn d_statement_close(ctx: *void) -> err {
    let s = stmt_of(ctx)
    let c = s.conn
    if c.active != nil && c.active.statement == s {
        c.active.closed = true
        finish_reader(c.active)
    }
    s.closed = true
    ret ok
}

fn d_statement_execute(ctx: *void, params: []const db.Parameter) -> (u64, err) {
    let s = stmt_of(ctx)
    if s.closed { ret (0u64, db.Closed) }
    let (affected, execute_error) = execute_text(s.conn, s.sql, params)
    ret (affected, execute_error)
}

fn d_statement_query(ctx: *void, params: []const db.Parameter) -> (db.Rows, err) {
    let s = stmt_of(ctx)
    if s.closed { ret (zero, db.Closed) }
    let (rows, rows_error) = start_query(s.conn, s.sql, params, s)
    ret (rows, rows_error)
}

fn d_rows_columns(ctx: *void) -> []const db.Column { ret reader_of(ctx).columns }

fn d_rows_next(ctx: *void, dst: []db.Value) -> (bool, err) {
    let r = reader_of(ctx)
    r.borrow = false
    let (more, next_error) = next_row(r, dst)
    ret (more, next_error)
}

fn d_rows_next_borrowed(ctx: *void, dst: []db.Value) -> (bool, err) {
    let r = reader_of(ctx)
    r.borrow = true
    let (more, next_error) = next_row(r, dst)
    ret (more, next_error)
}

fn next_row(r: *Reader, dst: []db.Value) -> (bool, err) {
    if r.closed { ret (false, db.Closed) }
    if r.done { ret (false, ok) }
    if dst.len < r.columns.len { ret (false, refuse(r.conn, "the row buffer is shorter than the row", db.InvalidQuery)) }
    let row = mysqlclient.fetch_row(r.result)
    if mem.address_of(row) == 0usize {
        // The end of the rows, or an error that ended them.
        var failed = ok
        if mysqlclient.errno(r.conn.handle) != 0u32 { failed = failure(r.conn) }
        finish_reader(r)
        ret (false, failed)
    }
    let fill_error = fill(r, row, dst)
    if fill_error != ok { ret (false, fill_error) }
    ret (true, ok)
}

fn d_rows_close(ctx: *void) -> err {
    finish_reader(reader_of(ctx))
    ret ok
}

fn d_transaction_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = execute_text(tx_of(ctx).conn, sql, params)
    ret (affected, execute_error)
}

fn d_transaction_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, rows_error) = start_query(tx_of(ctx).conn, sql, params, nil)
    ret (rows, rows_error)
}

// A COMMIT that fails is rolled back, because `e.db` has already closed the handle.
fn d_transaction_commit(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    if c.active != nil { finish_reader(c.active) }
    let (ignored, commit_error) = execute_text(c, "COMMIT", zero)
    if commit_error != ok {
        let (undone, undo_error) = execute_text(c, "ROLLBACK", zero)
    }
    c.in_transaction = false
    ret commit_error
}

fn d_transaction_rollback(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    if c.active != nil { finish_reader(c.active) }
    let (ignored, rollback_error) = execute_text(c, "ROLLBACK", zero)
    c.in_transaction = false
    ret rollback_error
}
