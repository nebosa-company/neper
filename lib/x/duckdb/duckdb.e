// An `e.db` driver over the DuckDB C API. `open` answers a `db.Connection` whose table is
// this module's; everything after that goes through `e.db`. `detail` and `version` are the only
// calls a program makes here directly.
//
// Memory: the arena handed to `open` is retained and borrowed for the connection's life.
// Every statement, row reader and transaction context comes from it, and a reader's text and
// blob values are copied into a buffer of the reader's that is valid until its next row. Read
// with `db.reader_next_borrowed`, the bytes are the chunk's own instead, valid only until the
// next row: DuckDB frees a chunk when the reader steps past it. The caller marks and resets
// that arena around work whose results it no longer needs. Error text is kept in a fixed buffer
// the connection allocates once, so failures do not grow the arena.
//
// Values: a parameter binds in its own type -- `Bool` as BOOLEAN, `Time` as TIMESTAMP in UTC
// (microseconds, so the nanosecond digits past the sixth go), `U64` only while it fits an `i64`.
// A column's kind is its declared SQL type: integers and floats are exact, TIMESTAMP is `Time`,
// BLOB is `Bytes`, and DECIMAL, UUID, HUGEINT and the date and time types come back as their
// `Text` spelling, because `db.Value` has no case that holds them exactly. A `TIME` is a time of
// day, which is not an instant, so it is `Text` too; the nested types (`LIST`, `STRUCT`, `MAP`,
// `ARRAY`) are `Bytes`, their raw values, which a program should not parse.
//
// Parameters: positional, DuckDB's `$1`, `$2`, ... A named one is looked up by the name it is
// given and then with `$` in front. A statement must have exactly as many parameters as it is
// given. `execute` runs every statement in its text; `query` and `prepare` take one.
//
// Statements: the DuckDB C API has no statement splitter, so the driver reads one itself and
// compiles each statement on its own -- with its own parameter binding and its own chunked
// result. A text whose quotes or comments it cannot follow is refused rather than mailed on.
//
// Streaming: rows arrive in chunks of DuckDB's size; the reader holds one at a time and frees
// it before the next, so no result is buffered whole.
use e.mem
use e.str
use e.time
use e.db
use e.bytes as octets
use x.duckdb.capi

type Detail = struct { code: i32, message: str }
error CannotOpen
error Failed

// 1.1 is where `duckdb_result_error_type` appeared, the newest call bound here.
const MIN_VERSION: i32 = 10100i32

type Conn = struct { database: usize, handle: usize, arena: *mem.Arena, driver: *const db.Driver, in_transaction: bool, note: str, code: i32, message: []u8, message_len: usize }
type Stmt = struct { conn: *Conn, handle: usize, closed: bool }
type Reader = struct { conn: *Conn, statement: *Stmt, result: capi.Result, chunk: usize, rows: usize, at: usize, done: bool, closed: bool, types: []i32, scales: []i32, columns: []db.Column, buffer: []u8, used: usize, borrow: bool }
type Tx = struct { conn: *Conn }

const SUCCESS: i32 = 0i32

// `duckdb_error_type`, in duckdb.h's order.
const ERROR_PARSER: i32 = 14i32
const ERROR_BINDER: i32 = 24i32
const ERROR_PARAMETER_NOT_RESOLVED: i32 = 35i32
const ERROR_PARAMETER_NOT_ALLOWED: i32 = 36i32
const ERROR_CATALOG: i32 = 13i32
const ERROR_CONVERSION: i32 = 2i32
const ERROR_OUT_OF_RANGE: i32 = 1i32
const ERROR_DECIMAL: i32 = 4i32
const ERROR_INVALID_TYPE: i32 = 8i32
const ERROR_NOT_IMPLEMENTED: i32 = 11i32
const ERROR_INVALID_INPUT: i32 = 32i32
const ERROR_TRANSACTION: i32 = 10i32
const ERROR_INTERRUPT: i32 = 29i32
const ERROR_DATA_CORRUPTION: i32 = 43i32
const ERROR_RESOURCE_IN_USE: i32 = 44i32
const ERROR_CONSTRAINT_TYPE: i32 = 18i32

// `duckdb_type`, in duckdb.h's order.
const TYPE_BOOLEAN: i32 = 1i32
const TYPE_TINYINT: i32 = 2i32
const TYPE_SMALLINT: i32 = 3i32
const TYPE_INTEGER: i32 = 4i32
const TYPE_BIGINT: i32 = 5i32
const TYPE_UTINYINT: i32 = 6i32
const TYPE_USMALLINT: i32 = 7i32
const TYPE_UINTEGER: i32 = 8i32
const TYPE_UBIGINT: i32 = 9i32
const TYPE_FLOAT: i32 = 10i32
const TYPE_DOUBLE: i32 = 11i32
const TYPE_TIMESTAMP: i32 = 12i32
const TYPE_DATE: i32 = 13i32
const TYPE_TIME: i32 = 14i32
const TYPE_INTERVAL: i32 = 15i32
const TYPE_HUGEINT: i32 = 16i32
const TYPE_VARCHAR: i32 = 17i32
const TYPE_BLOB: i32 = 18i32
const TYPE_DECIMAL: i32 = 19i32
const TYPE_TIMESTAMP_S: i32 = 20i32
const TYPE_TIMESTAMP_MS: i32 = 21i32
const TYPE_TIMESTAMP_NS: i32 = 22i32
const TYPE_ENUM: i32 = 23i32
const TYPE_LIST: i32 = 24i32
const TYPE_STRUCT: i32 = 25i32
const TYPE_MAP: i32 = 26i32
const TYPE_UUID: i32 = 27i32
const TYPE_BIT: i32 = 29i32
const TYPE_TIME_TZ: i32 = 30i32
const TYPE_TIMESTAMP_TZ: i32 = 31i32
const TYPE_UHUGEINT: i32 = 32i32
const TYPE_ARRAY: i32 = 33i32
const TYPE_SQLNULL: i32 = 36i32

const DUCKDB_SUCCESS: usize = 0usize

// A `duckdb_string_t` keeps twelve characters inline; longer ones point elsewhere. A
// `duckdb_hugeint` and a `duckdb_timestamp` are one or two words.
const INLINE_CHARS: usize = 12usize
const WORD_BYTES: usize = 8usize
const I64_MAX: i64 = 9223372036854775807i64
const I64_MIN: i64 = -9223372036854775808i64
const MAX_C_STRING: usize = 65536usize
const MESSAGE_CAP: usize = 1024usize
const SIGN_BIT: u64 = 9223372036854775808u64
// The largest `DECIMAL`, which a 128-bit integer holds exactly.
const TIME_FRACTION: i64 = 1000000i64

// `v2.0.0` as 20000, `v1.1.3` as 10103: the major, minor and patch as one integer. The `v` in
// front is part of every release's spelling, and anything else after the patch is `0`, which
// every caller reads as "too old".
fn version() -> i32 {
    let text = capi.library_version()
    if mem.address_of(text) == 0usize { ret 0i32 }
    var numbers: [3]i32 = zero
    var field = 0usize
    var i = 0usize
    while i < MAX_C_STRING {
        let b = byte_at(text, i)
        if b == 0u8 { break }
        if b == 46u8 {
            field += 1usize
            if field > 2usize { ret 0i32 }
        } else if b >= 48u8 && b <= 57u8 {
            numbers[field] = numbers[field] * 10i32 + i32(b - 48u8)
        } else if i == 0usize && (b == 118u8 || b == 86u8) {
            // The `v` of `v2.0.0`.
        } else {
            ret 0i32
        }
        i += 1usize
    }
    ret numbers[0usize] * 10000i32 + numbers[1usize] * 100i32 + numbers[2usize]
}

// `path` is a database file, or empty for an in-memory database.
fn open(a: *mem.Arena, path: str) -> (db.Connection, err) {
    var connection: db.Connection = zero
    if version() < MIN_VERSION { ret (connection, db.Unsupported) }
    let mark = mem.mark(a)
    let (name, name_error) = c_copy(a, path)
    if name_error != ok { ret (connection, name_error) }
    var database = 0usize
    let opened = capi.open(&name[0usize], &database)
    mem.reset(a, mark)
    if opened != SUCCESS { ret (connection, CannotOpen) }
    var handle = 0usize
    let connected = capi.connect(database, &handle)
    if connected != SUCCESS {
        capi.close(&database)
        ret (connection, CannotOpen)
    }
    let (conns, conn_error) = mem.alloc[Conn](a, 1usize)
    let (drivers, driver_error) = mem.alloc[db.Driver](a, 1usize)
    let (message, message_error) = mem.alloc[u8](a, MESSAGE_CAP)
    if conn_error != ok || driver_error != ok || message_error != ok {
        capi.disconnect(&handle)
        capi.close(&database)
        ret (connection, db.Unsupported)
    }
    drivers[0usize] = db.Driver { close: d_close, prepare: d_prepare, execute: d_execute, query: d_query, begin: d_begin, statement_close: d_statement_close, statement_execute: d_statement_execute, statement_query: d_statement_query, rows_columns: d_rows_columns, rows_next: d_rows_next, rows_next_borrowed: d_rows_next_borrowed, rows_close: d_rows_close, transaction_execute: d_transaction_execute, transaction_query: d_transaction_query, transaction_commit: d_transaction_commit, transaction_rollback: d_transaction_rollback }
    // Arena memory is not cleared, so every field is written.
    conns[0usize] = Conn { database: database, handle: handle, arena: a, driver: &drivers[0usize], in_transaction: false, note: "", code: 0i32, message: message, message_len: 0usize }
    let c = &conns[0usize]
    connection.ctx = mem.cast[*void](c)
    connection.driver = c.driver
    ret (connection, ok)
}

// Why the connection's last call failed: DuckDB's error type and message, or -- when the driver
// refused before DuckDB was asked -- code 0 and the driver's reason. The message is copied
// into `a`.
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err) {
    var out: Detail = zero
    if connection.ctx == nil { ret (out, db.Closed) }
    let c = conn_of(connection.ctx)
    if c.note.len != 0usize {
        out.message = c.note
        ret (out, ok)
    }
    let (message, message_error) = copy_text(a, c.message[0usize..c.message_len])
    if message_error != ok { ret (out, message_error) }
    out = Detail { code: c.code, message: message }
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

// A C string's bytes, copied into `dst`; a null pointer is empty.
fn keep_c(dst: []u8, p: *u8) -> usize {
    if mem.address_of(p) == 0usize { ret 0usize }
    var n = c_length(p)
    if n > dst.len { n = dst.len }
    copy_foreign(dst[0usize..n], p, n)
    ret n
}

fn clear_detail(c: *Conn) {
    c.note = ""
    c.code = 0i32
    c.message_len = 0usize
}

fn refuse(c: *Conn, note: str, e: err) -> err {
    clear_detail(c)
    c.note = note
    ret e
}

// A failure DuckDB reported: its error type is kept as the detail's code, its message in the
// connection's fixed buffer.
fn failure(c: *Conn, code: i32, message: *u8) -> err {
    clear_detail(c)
    c.code = code
    c.message_len = keep_c(c.message, message)
    ret mapped(code)
}

// A failed result is read for its error and then destroyed.
fn fail_result(c: *Conn, result: *capi.Result) -> err {
    let code = capi.result_error_type(result)
    let message = capi.result_error(result)
    let failed = failure(c, code, message)
    capi.destroy_result(result)
    ret failed
}

// A statement that will not compile says so on the prepared statement, not on a result.
fn fail_prepare(c: *Conn, handle: usize) -> err {
    ret failure(c, ERROR_PARSER, capi.prepare_error(handle))
}

fn mapped(code: i32) -> err {
    if code == ERROR_PARSER { ret db.InvalidQuery }
    if code == ERROR_BINDER || code == ERROR_CATALOG { ret db.InvalidQuery }
    if code == ERROR_PARAMETER_NOT_RESOLVED || code == ERROR_PARAMETER_NOT_ALLOWED { ret db.InvalidQuery }
    if code == ERROR_CONVERSION || code == ERROR_DECIMAL || code == ERROR_INVALID_TYPE { ret db.InvalidQuery }
    if code == ERROR_OUT_OF_RANGE || code == ERROR_INVALID_INPUT { ret db.InvalidQuery }
    if code == ERROR_RESOURCE_IN_USE || code == ERROR_TRANSACTION || code == ERROR_INTERRUPT { ret db.Busy }
    if code == ERROR_NOT_IMPLEMENTED { ret db.Unsupported }
    if code == ERROR_CONSTRAINT_TYPE { ret db.Constraint }
    if code == ERROR_DATA_CORRUPTION { ret Failed }
    ret Failed
}

// --- foreign memory

// A NUL-terminated copy of `s` in `a`.
// A non-empty NUL-terminated copy of `s` in `a`. The bytes are pulled out one at a time by
// the arena copy below rather than by indexing `s`, because indexing a string literal is not
// a load this compiler emits correctly on Windows yet; the copy of a runtime `str` is.
fn c_copy(a: *mem.Arena, s: str) -> ([]u8, err) {
    let (bytes, allocation_error) = mem.alloc[u8](a, s.len + 1usize)
    if allocation_error != ok { ret (bytes, allocation_error) }
    mem.copy[u8](bytes[0usize..s.len], s)
    bytes[s.len] = 0u8
    ret (bytes, ok)
}

// A C string for a fixed word the driver spells itself (`s` is one of its own literals).
// Unlike an `@import` path, a literal here is written out with an explicit length rather than
// indexed, which is the same thing without a load through the literal's pointer.
fn c_word(a: *mem.Arena, s: str) -> ([]u8, err) {
    let (bytes, allocation_error) = mem.alloc[u8](a, s.len + 1usize)
    if allocation_error != ok { ret (bytes, allocation_error) }
    let n = keep(bytes, s)
    bytes[n] = 0u8
    ret (bytes, ok)
}

// `n` bytes at a foreign address, copied into `dst`. `mem.view` names the region without
// reading it, so nothing past `n` is touched.
fn copy_foreign(dst: []u8, p: *u8, n: usize) {
    var region: mem.Arena = zero
    region.base = p
    region.cap = n
    region.off = 0usize
    let copied = octets.copy(dst[0usize..n], mem.view(&region, 0usize, n))
}

// Byte `index` at a foreign address, which may be one past the end of what was read.
fn byte_at(p: *u8, index: usize) -> u8 {
    var region: mem.Arena = zero
    region.base = p
    region.cap = index + 1usize
    region.off = 0usize
    let bytes = mem.view(&region, index, 1usize)
    ret bytes[0usize]
}

// A C string copied into `a`; a null pointer is the empty string.
fn c_read(a: *mem.Arena, p: *u8) -> (str, err) {
    if mem.address_of(p) == 0usize { ret ("", ok) }
    let n = c_length(p)
    if n == 0usize { ret ("", ok) }
    let (bytes, allocation_error) = mem.alloc[u8](a, n)
    if allocation_error != ok { ret ("", allocation_error) }
    copy_foreign(bytes, p, n)
    ret (bytes, ok)
}

// A C string's length; the walk stops at the terminator, which DuckDB always writes.
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

// The `u64` at `offset` into a foreign region, read a byte at a time.
fn word_at(base: *u8, offset: usize) -> u64 {
    var value = 0u64
    var i = 0usize
    while i < WORD_BYTES {
        value = value | u64(byte_at(base, offset + i)) << u64(i * 8usize)
        i += 1usize
    }
    ret value
}

// The `u32` at `offset` into a foreign region.
fn half_word_at(base: *u8, offset: usize) -> u32 {
    var value = 0u32
    var i = 0usize
    while i < 4usize {
        value = value | u32(byte_at(base, offset + i)) << u32(i * 8usize)
        i += 1usize
    }
    ret value
}

// --- the statement splitter

// Compiles the first statement of `sql[from..]` and answers where the next one starts. A
// handle of zero with `ok` means the rest held only whitespace and comments.
fn compile(c: *Conn, sql: str, from: usize) -> (usize, usize, err) {
    let start = skip_space(sql, from)
    if start >= sql.len { ret (0usize, sql.len, ok) }
    let stop = end_of_statement(sql, start)
    if stop <= start { ret (0usize, sql.len, split_refusal(c)) }
    let mark = mem.mark(c.arena)
    let (text, text_error) = c_copy(c.arena, sql[start..stop])
    if text_error != ok {
        mem.reset(c.arena, mark)
        ret (0usize, sql.len, text_error)
    }
    var handle = 0usize
    let compiled = capi.prepare(c.handle, &text[0usize], &handle)
    mem.reset(c.arena, mark)
    if compiled != SUCCESS {
        if handle != 0usize { capi.destroy_prepare(&handle) }
        ret (0usize, sql.len, fail_prepare(c, handle))
    }
    ret (handle, stop, ok)
}

// A text with one statement and nothing after it but whitespace and comments.
fn compile_one(c: *Conn, sql: str) -> (usize, err) {
    let start = skip_space(sql, 0usize)
    if start >= sql.len { ret (0usize, refuse(c, "the SQL text holds no statement", db.InvalidQuery)) }
    let stop = end_of_statement(sql, start)
    if stop <= start { ret (0usize, split_refusal(c)) }
    if skip_space(sql, stop) < sql.len { ret (0usize, refuse(c, "the SQL text holds more than one statement", db.InvalidQuery)) }
    let (handle, next, compile_error) = compile(c, sql, start)
    ret (handle, compile_error)
}

// Counts the statements without compiling them, so a text that is one statement is known to be
// one before `compile_one` refuses it for being two.
fn count_statements(sql: str) -> usize {
    var count = 0usize
    var from = 0usize
    while from < sql.len {
        let start = skip_space(sql, from)
        if start >= sql.len { break }
        let stop = end_of_statement(sql, start)
        if stop <= start { break }
        count += 1usize
        from = stop
    }
    ret count
}

fn split_refusal(c: *Conn) -> err {
    ret refuse(c, "the SQL text has a quote or comment this driver cannot follow", db.InvalidQuery)
}

// The index of the first byte from `from` that is not whitespace or a comment. A comment that
// never closes is refused rather than read as code.
fn skip_space(sql: str, from: usize) -> usize {
    var i = from
    while i < sql.len {
        let b = sql[i]
        if b == 32u8 || b == 9u8 || b == 10u8 || b == 13u8 || b == 11u8 || b == 12u8 {
            i += 1usize
        } else if b == 45u8 && i + 1usize < sql.len && sql[i + 1usize] == 45u8 {
            i = skip_line(sql, i + 2usize)
        } else if b == 47u8 && i + 1usize < sql.len && sql[i + 1usize] == 42u8 {
            let past = skip_block_comment(sql, i + 2usize)
            if past > sql.len { ret sql.len }
            i = past
        } else {
            break
        }
    }
    ret i
}

fn skip_line(sql: str, from: usize) -> usize {
    var i = from
    while i < sql.len && sql[i] != 10u8 { i += 1usize }
    ret i
}

// Past the `*/` that closes a block comment; `len + 1` when there is none. DuckDB nests them,
// so a `/*` inside one is walked into rather than past.
fn skip_block_comment(sql: str, from: usize) -> usize {
    var depth = 1usize
    var i = from
    while i + 1usize < sql.len {
        if sql[i] == 47u8 && sql[i + 1usize] == 42u8 {
            depth += 1usize
            i += 2usize
        } else if sql[i] == 42u8 && sql[i + 1usize] == 47u8 {
            depth -= 1usize
            if depth == 0usize { ret i + 2usize }
            i += 2usize
        } else {
            i += 1usize
        }
    }
    ret sql.len + 1usize
}

// Where the statement that starts at `start` ends: at its `;` outside every quote, or at the
// end of the text. `len` when the text ends in an unterminated quote: the compile reports it.
fn end_of_statement(sql: str, start: usize) -> usize {
    var i = start
    while i < sql.len {
        let b = sql[i]
        if b == 59u8 {
            ret i + 1usize
        } else if b == 39u8 {
            i = skip_quoted(sql, i + 1usize, 39u8)
        } else if b == 34u8 {
            i = skip_quoted(sql, i + 1usize, 34u8)
        } else if b == 45u8 && i + 1usize < sql.len && sql[i + 1usize] == 45u8 {
            i = skip_line(sql, i + 2usize)
        } else if b == 47u8 && i + 1usize < sql.len && sql[i + 1usize] == 42u8 {
            let past = skip_block_comment(sql, i + 2usize)
            if past > sql.len { ret sql.len }
            i = past
        } else {
            i += 1usize
        }
    }
    ret sql.len
}

// Past the closing `quote`; a doubled quote is an escaped one. `len + 1` when unterminated.
fn skip_quoted(sql: str, from: usize, quote: u8) -> usize {
    var i = from
    while i < sql.len {
        if sql[i] == quote {
            if i + 1usize < sql.len && sql[i + 1usize] == quote {
                i += 2usize
            } else {
                ret i + 1usize
            }
        } else {
            i += 1usize
        }
    }
    ret sql.len + 1usize
}

// --- parameters

// DuckDB numbers its parameters `$1`, `$2`, ... in the order they first appear, and names one
// `$id` wherever that spelling is used again. A `db.Parameter` therefore binds in the order it
// is given; a named one is looked up only to check that the statement has that name at all, and
// a name it does not have is refused rather than bound to whichever slot it landed in.
fn bind_all(c: *Conn, handle: usize, params: []const db.Parameter) -> err {
    let cleared = capi.clear_bindings(handle)
    if capi.nparams(handle) != params.len {
        ret refuse(c, "the statement's parameter count differs from the parameters given", db.InvalidQuery)
    }
    var i = 0usize
    while i < params.len {
        if params[i].name.len != 0usize {
            let (found, find_error) = parameter_index(c, handle, params[i].name)
            if find_error != ok { ret find_error }
            if found == 0usize { ret refuse(c, "the statement has no parameter of that name", db.InvalidQuery) }
        }
        let bind_error = bind_value(c, handle, i + 1usize, params[i].value)
        if bind_error != ok { ret bind_error }
        i += 1usize
    }
    ret ok
}

// The index of a named parameter as written, else with `$` in front; zero when the statement
// has no parameter of that name. DuckDB can answer zero while reporting success, so the index
// itself decides rather than the state.
fn parameter_index(c: *Conn, handle: usize, name: str) -> (usize, err) {
    let mark = mem.mark(c.arena)
    let (plain, plain_error) = c_copy(c.arena, name)
    if plain_error != ok { ret (0usize, plain_error) }
    var index = 0usize
    let first = capi.bind_parameter_index(handle, &index, &plain[0usize])
    if index != 0usize {
        mem.reset(c.arena, mark)
        ret (index, ok)
    }
    let (prefixed, prefixed_error) = mem.alloc[u8](c.arena, name.len + 2usize)
    if prefixed_error != ok {
        mem.reset(c.arena, mark)
        ret (0usize, prefixed_error)
    }
    prefixed[0usize] = 36u8
    var i = 0usize
    while i < name.len {
        prefixed[i + 1usize] = name[i]
        i += 1usize
    }
    prefixed[name.len + 1usize] = 0u8
    index = 0usize
    let found = capi.bind_parameter_index(handle, &index, &prefixed[0usize])
    mem.reset(c.arena, mark)
    ret (index, ok)
}

fn bind_value(c: *Conn, handle: usize, index: usize, value: db.Value) -> err {
    var rc = SUCCESS
    var none: [1]u8 = zero
    switch value {
    case .Null:
        rc = capi.bind_null(handle, index)
    case .Bool as flag:
        var truth = 0u8
        if flag { truth = 1u8 }
        rc = capi.bind_boolean(handle, index, truth)
    case .I64 as signed:
        rc = capi.bind_int64(handle, index, signed)
    case .U64 as unsigned:
        if unsigned > u64(I64_MAX) { ret refuse(c, "an unsigned value does not fit an i64; bind it as Text for a UBIGINT or HUGEINT", db.Unsupported) }
        rc = capi.bind_int64(handle, index, i64(unsigned))
    case .F64 as real:
        rc = capi.bind_double(handle, index, real)
    case .Text as s:
        if s.len == 0usize {
            rc = capi.bind_varchar_length(handle, index, &none[0usize], 0usize)
        } else {
            rc = capi.bind_varchar_length(handle, index, &s[0usize], s.len)
        }
    case .Bytes as data:
        if data.len == 0usize {
            rc = capi.bind_blob(handle, index, &none[0usize], 0usize)
        } else {
            rc = capi.bind_blob(handle, index, &data[0usize], data.len)
        }
    case .Time as instant:
        rc = capi.raw_bind_timestamp(handle, index, instant.nanos / 1000i64)
    }
    if rc != SUCCESS { ret refuse(c, "DuckDB would not take that value in that parameter", db.Unsupported) }
    ret ok
}

// --- running statements

// Runs a compiled statement to its end, discarding the rows, and answers its result: 1 when it
// changed rows, 0 when it only answered them (DDL, PRAGMA, a SELECT).
fn run(c: *Conn, handle: usize) -> (u64, err) {
    var result: capi.Result = zero
    let ran = capi.execute_prepared(handle, &result)
    if ran != SUCCESS { ret (0u64, fail_result(c, &result)) }
    // DUCKDB_RESULT_TYPE_CHANGED_ROWS is 1.
    var changed = 0u64
    if capi.result_return_type(&result) == 1i32 { changed = 1u64 }
    capi.destroy_result(&result)
    clear_detail(c)
    ret (changed, ok)
}

// Every statement in the text, in order, the counts added up. A text with no statement at all
// (empty, or only comments) runs nothing. A text the splitter cannot follow is handed to
// DuckDB whole, which reports its own refusal rather than the splitter's guess.
fn execute_text(c: *Conn, sql: str, params: []const db.Parameter) -> (u64, err) {
    var affected = 0u64
    var from = 0usize
    while from < sql.len {
        let start = skip_space(sql, from)
        if start >= sql.len {
            from = sql.len
            break
        }
        let stop = end_of_statement(sql, start)
        if stop <= start {
            let mark = mem.mark(c.arena)
            let (text, text_error) = c_copy(c.arena, sql[start..])
            if text_error != ok {
                mem.reset(c.arena, mark)
                ret (affected, text_error)
            }
            var result: capi.Result = zero
            let ran = capi.query(c.handle, &text[0usize], &result)
            mem.reset(c.arena, mark)
            if ran != SUCCESS { ret (affected, fail_result(c, &result)) }
            capi.destroy_result(&result)
            clear_detail(c)
            ret (affected, ok)
        }
        let mark = mem.mark(c.arena)
        let (compiled, next, compile_error) = compile(c, sql, start)
        from = next
        if compile_error != ok {
            mem.reset(c.arena, mark)
            ret (affected, compile_error)
        }
        var handle = compiled
        let bind_error = bind_all(c, handle, params)
        var count = 0u64
        var run_error = bind_error
        if run_error == ok {
            let (changed, changed_error) = run(c, handle)
            count = changed
            run_error = changed_error
        }
        capi.destroy_prepare(&handle)
        mem.reset(c.arena, mark)
        if run_error != ok { ret (affected, run_error) }
        affected += count
    }
    ret (affected, ok)
}

// --- row readers

fn is_integer_type(t: i32) -> bool {
    ret t == TYPE_TINYINT || t == TYPE_SMALLINT || t == TYPE_INTEGER || t == TYPE_BIGINT || t == TYPE_UTINYINT || t == TYPE_USMALLINT || t == TYPE_UINTEGER || t == TYPE_UBIGINT
}

fn is_timestamp_type(t: i32) -> bool {
    ret t == TYPE_TIMESTAMP || t == TYPE_TIMESTAMP_S || t == TYPE_TIMESTAMP_MS || t == TYPE_TIMESTAMP_NS || t == TYPE_TIMESTAMP_TZ
}

fn is_nested_type(t: i32) -> bool {
    ret t == TYPE_LIST || t == TYPE_STRUCT || t == TYPE_MAP || t == TYPE_ARRAY || t == TYPE_BIT
}

// `bytes` is whether the column's logical type keeps its values as DuckDB's own bytes: an ENUM
// of BLOB values does, and arrives as `Bytes`.
fn kind_of(t: i32, bytes: bool) -> db.ValueKind {
    if t == TYPE_BOOLEAN { ret .Bool }
    if is_integer_type(t) { ret .I64 }
    if t == TYPE_FLOAT || t == TYPE_DOUBLE { ret .F64 }
    if is_timestamp_type(t) { ret .Time }
    if t == TYPE_VARCHAR || t == TYPE_UUID || t == TYPE_DECIMAL { ret .Text }
    if t == TYPE_ENUM {
        if bytes { ret .Bytes }
        ret .Text
    }
    if t == TYPE_HUGEINT || t == TYPE_UHUGEINT || t == TYPE_INTERVAL || t == TYPE_DATE || t == TYPE_TIME || t == TYPE_TIME_TZ { ret .Text }
    if t == TYPE_BLOB { ret .Bytes }
    if is_nested_type(t) { ret .Bytes }
    ret .Null
}

// The width and scale of a DECIMAL column, and whether an ENUM keeps BLOB values, read from
// the column's logical type: DuckDB stores a DECIMAL as a 128-bit integer carrying a scale, and
// an ENUM of BLOBs as a `duckdb_string_t` holding bytes.
fn decimal_scale(result: *capi.Result, column: usize) -> i32 {
    var logical: usize = capi.column_logical_type(result, column)
    let scale = capi.decimal_scale(logical)
    capi.destroy_logical_type(&logical)
    ret i32(scale)
}

fn enum_holds_bytes(result: *capi.Result, column: usize) -> bool {
    var logical: usize = capi.column_logical_type(result, column)
    let internal = capi.enum_internal_type(logical)
    capi.destroy_logical_type(&logical)
    ret internal == TYPE_BLOB
}

// Runs a compiled statement and takes its first chunk, so a failing query fails here rather
// than at its first row, and the columns are known before any row is read.
fn reader(c: *Conn, handle: usize, statement: *Stmt, owned: bool) -> (db.Rows, err) {
    var rows: db.Rows = zero
    var prepared = handle
    var result: capi.Result = zero
    let ran = capi.execute_prepared(prepared, &result)
    if ran != SUCCESS {
        let failed = fail_result(c, &result)
        if owned { capi.destroy_prepare(&prepared) }
        ret (rows, failed)
    }
    var chunk = capi.fetch_chunk(&result)
    let count = capi.column_count(&result)
    let (readers, reader_error) = mem.alloc[Reader](c.arena, 1usize)
    let (types, types_error) = mem.alloc[i32](c.arena, count)
    let (scales, scales_error) = mem.alloc[i32](c.arena, count)
    let (cols, cols_error) = mem.alloc[db.Column](c.arena, count)
    if reader_error != ok || types_error != ok || scales_error != ok || cols_error != ok {
        if chunk != 0usize { capi.destroy_data_chunk(&chunk) }
        capi.destroy_result(&result)
        if owned { capi.destroy_prepare(&prepared) }
        ret (rows, db.Unsupported)
    }
    var i = 0usize
    while i < count {
        types[i] = capi.column_type(&result, i)
        scales[i] = 0i32
        if types[i] == TYPE_DECIMAL { scales[i] = decimal_scale(&result, i) }
        let (name, name_error) = c_read(c.arena, capi.column_name(&result, i))
        if name_error != ok {
            if chunk != 0usize { capi.destroy_data_chunk(&chunk) }
            capi.destroy_result(&result)
            if owned { capi.destroy_prepare(&prepared) }
            ret (rows, name_error)
        }
        var bytes = types[i] == TYPE_BLOB
        if types[i] == TYPE_ENUM { bytes = enum_holds_bytes(&result, i) }
        cols[i] = db.Column { name: name, kind: kind_of(types[i], bytes), nullable: true }
        i += 1usize
    }
    var size = 0usize
    if chunk != 0usize { size = capi.data_chunk_get_size(chunk) }
    var no_buffer: []u8 = zero
    // Arena memory is not cleared, so every field is written.
    readers[0usize] = Reader { conn: c, statement: statement, result: result, chunk: chunk, rows: size, at: 0usize, done: false, closed: false, types: types, scales: scales, columns: cols, buffer: no_buffer, used: 0usize, borrow: false }
    let r = &readers[0usize]
    clear_detail(c)
    rows.ctx = mem.cast[*void](r)
    ret (rows, ok)
}

// Reads a whole query: one statement, and every row it answers streamed.
fn start_query(c: *Conn, sql: str, params: []const db.Parameter, statement: *Stmt) -> (db.Rows, err) {
    let start = skip_space(sql, 0usize)
    if start >= sql.len { ret (zero, refuse(c, "the SQL text holds no statement", db.InvalidQuery)) }
    let stop = end_of_statement(sql, start)
    if stop <= start { ret (zero, split_refusal(c)) }
    if skip_space(sql, stop) < sql.len { ret (zero, refuse(c, "the SQL text holds more than one statement", db.InvalidQuery)) }
    let (handle0, compile_error) = compile_one(c, sql)
    if compile_error != ok { ret (zero, compile_error) }
    var handle = handle0
    let bind_error = bind_all(c, handle, params)
    if bind_error != ok {
        capi.destroy_prepare(&handle)
        ret (zero, bind_error)
    }
    let (rows, rows_error) = reader(c, handle, statement, true)
    ret (rows, rows_error)
}

// --- values

// Room for `n` more bytes of this row. A grown buffer is a new one: the values already
// filled keep pointing at the old, which the arena still holds.
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

// `n` bytes of the reader's buffer for this row, taken from `take`.
fn room(r: *Reader, n: usize) -> ([]u8, err) {
    let reserve_error = reserve(r, n)
    if reserve_error != ok {
        var nothing: []u8 = zero
        ret (nothing, reserve_error)
    }
    let start = r.used
    r.used = start + n
    ret (r.buffer[start..start + n], ok)
}

fn take(r: *Reader, v: []const u8) -> ([]u8, err) {
    let (out, room_error) = room(r, v.len)
    if room_error != ok { ret (out, room_error) }
    let moved = octets.copy(out, v)
    ret (out, ok)
}

// A file copy of the chunk, valid until this reader's next row.
fn copy_bytes(r: *Reader, v: []const u8) -> ([]const u8, err) {
    let (out, out_error) = take(r, v)
    if out_error != ok {
        var nothing: []const u8 = zero
        ret (nothing, out_error)
    }
    ret (out, ok)
}

fn copy_text_of(r: *Reader, v: []const u8) -> (str, err) {
    let (out, out_error) = take(r, v)
    if out_error != ok { ret ("", out_error) }
    ret (out, ok)
}

// An address as a pointer. No intrinsic turns an integer back into one, so the bits are taken
// apart and put back: each byte is the same byte, and a view over them names the bytes the
// address names.
fn as_pointer(address: u64) -> *u8 {
    var bytes: [8]u8 = zero
    var i = 0usize
    while i < 8usize {
        bytes[i] = u8(address >> u64(i * 8usize) & 255u64)
        i += 1usize
    }
    ret mem.cast[*u8](&bytes[0usize])
}

// A `duckdb_string_t`'s bytes: inline when short, else at the pointer beside the length.
fn string_bytes(r: *Reader, data: *u8, at: usize) -> ([]const u8, err) {
    var nothing: []const u8 = zero
    let offset = at * 16usize
    let length = usize(word_at(data, offset) & 4294967295u64)
    if length == 0usize { ret (nothing, ok) }
    var region: mem.Arena = zero
    if length <= INLINE_CHARS {
        region.base = data
        region.cap = offset + 4usize + length
        region.off = 0usize
        ret (mem.view(&region, offset + 4usize, length), ok)
    }
    let pointer = word_at(data, offset + 8usize)
    if pointer == 0u64 { ret (nothing, ok) }
    region.base = as_pointer(pointer)
    region.cap = length
    region.off = 0usize
    ret (mem.view(&region, 0usize, length), ok)
}

// A text value at the current row of a vector: copied into the reader's buffer, or borrowed
// from the chunk when the reader was asked to borrow.
fn text_at(r: *Reader, vector: usize) -> (str, err) {
    let data = as_pointer(u64(capi.vector_get_data(vector)))
    let (bytes, bytes_error) = string_bytes(r, data, r.at)
    if bytes_error != ok { ret ("", bytes_error) }
    if r.borrow {
        let borrowed: str = bytes
        ret (borrowed, ok)
    }
    let (copied, copied_error) = copy_text_of(r, bytes)
    ret (copied, copied_error)
}

fn blob_at(r: *Reader, vector: usize) -> ([]const u8, err) {
    let data = as_pointer(u64(capi.vector_get_data(vector)))
    let (bytes, bytes_error) = string_bytes(r, data, r.at)
    if bytes_error != ok { ret (bytes, bytes_error) }
    if r.borrow {
        ret (bytes, ok)
    }
    let (copied, copied_error) = copy_bytes(r, bytes)
    ret (copied, copied_error)
}

// A fixed-width integer at the current row. A signed one is sign-extended from its own width
// through the top half of its word; the unsigned ones that fit an `i64` come back as `I64`, and
// a `UBIGINT` past it as `U64`.
fn integer_value(r: *Reader, t: i32, vector: usize) -> db.Value {
    let data = as_pointer(u64(capi.vector_get_data(vector)))
    let at = r.at
    if t == TYPE_BOOLEAN {
        ret db.Value{ Bool: byte_at(data, at) & 1u8 != 0u8 }
    }
    if t == TYPE_TINYINT {
        ret db.Value{ I64: signed_bits(word_at(data, at), 8u64) }
    }
    if t == TYPE_UTINYINT {
        ret db.Value{ I64: i64(word_at(data, at)) }
    }
    if t == TYPE_SMALLINT {
        ret db.Value{ I64: signed_bits(word_at(data, at * 2usize), 16u64) }
    }
    if t == TYPE_USMALLINT {
        ret db.Value{ I64: i64(word_at(data, at * 2usize) & 65535u64) }
    }
    if t == TYPE_INTEGER {
        ret db.Value{ I64: signed_bits(word_at(data, at * 4usize), 32u64) }
    }
    if t == TYPE_UINTEGER {
        ret db.Value{ I64: i64(word_at(data, at * 4usize) & 4294967295u64) }
    }
    let wide = word_at(data, at * 8usize)
    if t == TYPE_UBIGINT && wide > u64(I64_MAX) { ret db.Value{ U64: wide } }
    ret db.Value{ I64: mem.bitcast[i64](wide) }
}

// The low `bits` bits of `v` as a signed integer: the value shifted up so its sign bit lands
// on the top bit, then shifted back down arithmetically.
fn signed_bits(v: u64, bits: u64) -> i64 {
    let shift = 64u64 - bits
    let raised = mem.bitcast[i64](v << u64(shift))
    ret raised >> u64(shift)
}

fn float_value(r: *Reader, t: i32, vector: usize) -> db.Value {
    let data = as_pointer(u64(capi.vector_get_data(vector)))
    if t == TYPE_FLOAT {
        let word = word_at(data, r.at * 4usize)
        let bits = left_bits(word, 32u64)
        // A single-precision value is a double with the other half of the mantissa zero, so the
        // bit pattern widens exactly: sign, then eight exponent bits, then 23 mantissa bits.
        let sign = bits >> 63u64 & 1u64
        let exponent = bits >> 23u64 & 255u64
        let mantissa = bits & 8388607u64
        var widened = 0u64
        if exponent == 0u64 {
            // A subnormal single is a normal double, scaled down by 2^-126.
            if mantissa == 0u64 {
                widened = sign << 63u64
            } else {
                var top = 0u64
                var probe = mantissa
                while probe > 1u64 {
                    probe = probe >> 1u64
                    top += 1u64
                }
                let normal_exponent = 1023u64 - 127u64 - 127u64 + top
                let normal_mantissa = (mantissa << u64(52u64 - top)) & 4503599627370495u64
                widened = sign << 63u64 | normal_exponent << 52u64 | normal_mantissa
            }
        } else if exponent == 255u64 {
            widened = sign << 63u64 | 2047u64 << 52u64 | mantissa << 29u64
        } else {
            widened = sign << 63u64 | (exponent + 1023u64 - 127u64) << 52u64 | mantissa << 29u64
        }
        ret db.Value{ F64: mem.bitcast[f64](widened) }
    }
    ret db.Value{ F64: mem.bitcast[f64](word_at(data, r.at * 8usize)) }
}

fn left_bits(v: u64, bits: u64) -> u64 { ret v << u64(64u64 - bits) }

// The value of a timestamp of type `t` at the current row: an `Instant` in nanoseconds, or its
// text when the type keeps nanoseconds (an `e.time.Instant` counts them in an `i64` too, but a
// year outside 1678 to 2261 does not fit one, and that is DuckDB's own range for a nanosecond
// timestamp).
fn timestamp_value(r: *Reader, t: i32, vector: usize) -> (db.Value, err) {
    let data = as_pointer(u64(capi.vector_get_data(vector)))
    let raw = mem.bitcast[i64](word_at(data, r.at * 8usize))
    if t == TYPE_TIMESTAMP_NS {
        let (text, text_error) = decimal_text(r, raw)
        if text_error != ok { ret (.Null, text_error) }
        ret (db.Value{ Text: text }, ok)
    }
    var micros = raw
    if t == TYPE_TIMESTAMP_S { micros = saturating_mul(raw, 1000000i64) }
    if t == TYPE_TIMESTAMP_MS { micros = saturating_mul(raw, 1000i64) }
    ret (db.Value{ Time: time.Instant { nanos: saturating_mul(micros, 1000i64) } }, ok)
}

// `v * factor`, or the end of `i64` rather than a wrapped one: a timestamp past 2262 has no
// nanosecond count, and wrapping it would name a date in the past.
fn saturating_mul(v: i64, factor: i64) -> i64 {
    if v > 0i64 && v > I64_MAX / factor { ret I64_MAX }
    if v < 0i64 && v < I64_MIN / factor { ret I64_MIN }
    ret v * factor
}

// The decimal text of a `DECIMAL`, a `HUGEINT` or a `UHUGEINT` at the current row. `column`
// is the column's index, for its scale.
fn wide_value(r: *Reader, column: usize, t: i32, vector: usize) -> (str, err) {
    let data = as_pointer(u64(capi.vector_get_data(vector)))
    let lower = word_at(data, r.at * 16usize)
    let upper = word_at(data, r.at * 16usize + 8usize)
    let signed = t != TYPE_UHUGEINT
    var scale = 0usize
    if t == TYPE_DECIMAL { scale = usize(r.scales[column]) }
    let (spelled, spelled_error) = wide_text(r, lower, upper, signed, scale)
    ret (spelled, spelled_error)
}

// The decimal digits of `upper * 2^64 + lower`, least significant first, in `digits`.
fn push_wide(upper: u64, lower: u64, digits: []u8) -> (usize, err) {
    var high = upper
    var low = lower
    var count = 0usize
    if high == 0u64 && low == 0u64 {
        digits[0usize] = 48u8
        ret (1usize, ok)
    }
    while high != 0u64 || low != 0u64 {
        // The value in binary, one bit at a time from the top, divided by ten: the remainder
        // is this digit and what the shift kept is the quotient.
        var remainder = 0u64
        var quotient_high = 0u64
        var high_bit = 64usize
        while high_bit > 0usize {
            high_bit -= 1usize
            let carry = remainder * 2u64 + (high >> u64(high_bit) & 1u64)
            if carry >= 10u64 {
                quotient_high = quotient_high | 1u64 << u64(high_bit)
                remainder = carry - 10u64
            } else {
                remainder = carry
            }
        }
        var quotient_low = 0u64
        var low_bit = 64usize
        while low_bit > 0usize {
            low_bit -= 1usize
            let carry = remainder * 2u64 + (low >> u64(low_bit) & 1u64)
            if carry >= 10u64 {
                quotient_low = quotient_low | 1u64 << u64(low_bit)
                remainder = carry - 10u64
            } else {
                remainder = carry
            }
        }
        if count >= 39usize { ret (count, mem.Exhausted) }
        digits[count] = 48u8 + u8(remainder)
        count += 1usize
        high = quotient_high
        low = quotient_low
    }
    ret (count, ok)
}

// A 128-bit integer in decimal, `scale` digits of it after the point. A negative value is
// negated in two's complement before its digits are taken, so the most negative one works too.
fn wide_text(r: *Reader, lower: u64, upper: u64, signed: bool, scale: usize) -> (str, err) {
    var high = upper
    var low = lower
    var negative = false
    if signed && high >> 63u64 == 1u64 {
        negative = true
        low = ~low + 1u64
        high = ~high
        if low == 0u64 { high = high + 1u64 }
    }
    var digits: [40]u8 = zero
    var (b, builder_error) = str.builder(r.conn.arena, 48usize + scale)
    if builder_error != ok { ret ("", builder_error) }
    if negative {
        let minus = str.push(&b, "-")
        if minus != ok { ret ("", minus) }
    }
    let (count, digits_error) = push_wide(high, low, digits[0usize..])
    if digits_error != ok { ret ("", digits_error) }
    var whole = count
    if count > scale { whole = count - scale } else { whole = 0usize }
    var i = whole
    while i > 0usize {
        i -= 1usize
        let pushed = str.push(&b, digits[i..i + 1usize])
        if pushed != ok { ret ("", pushed) }
    }
    if scale > 0usize {
        let point = str.push(&b, ".")
        if point != ok { ret ("", point) }
        var written = count - whole
        var f = whole
        while f > 0usize {
            f -= 1usize
            let pushed = str.push(&b, digits[f..f + 1usize])
            if pushed != ok { ret ("", pushed) }
            written += 1usize
        }
        while written < scale {
            let filled = str.push(&b, "0")
            if filled != ok { ret ("", filled) }
            written += 1usize
        }
    }
    ret (str.done(&b), ok)
}

fn decimal_text(r: *Reader, v: i64) -> (str, err) {
    var (b, builder_error) = str.builder(r.conn.arena, 24usize)
    if builder_error != ok { ret ("", builder_error) }
    let pushed = str.push_i64(&b, v)
    if pushed != ok { ret ("", pushed) }
    ret (str.done(&b), ok)
}

// `YYYY-MM-DD` for a count of days from 1970-01-01.
fn date_text(r: *Reader, days: i64) -> (str, err) {
    let (year, month, day) = time.civil_from_days(days)
    var (b, builder_error) = str.builder(r.conn.arena, 32usize)
    if builder_error != ok { ret ("", builder_error) }
    let pushed_year = str.push_i64(&b, year)
    if pushed_year != ok { ret ("", pushed_year) }
    let pushed_month = push_field(&b, month)
    if pushed_month != ok { ret ("", pushed_month) }
    let pushed_day = push_field(&b, day)
    if pushed_day != ok { ret ("", pushed_day) }
    ret (str.done(&b), ok)
}

// `-MM-DD` for the fields after the year.
fn push_field(b: *str.Builder, value: i64) -> err {
    let dash = str.push(b, "-")
    if dash != ok { ret dash }
    ret push_two(b, value)
}

// `HH:MM:SS` for a count of microseconds since midnight, with `.ffffff` when it has a
// fraction.
fn time_text(r: *Reader, micros: i64) -> (str, err) {
    var (b, builder_error) = str.builder(r.conn.arena, 16usize)
    if builder_error != ok { ret ("", builder_error) }
    let seconds = micros / TIME_FRACTION
    let pushed = push_two(&b, seconds / 3600i64)
    if pushed != ok { ret ("", pushed) }
    let colon = str.push(&b, ":")
    if colon != ok { ret ("", colon) }
    let minutes = push_two(&b, seconds / 60i64 % 60i64)
    if minutes != ok { ret ("", minutes) }
    let colon2 = str.push(&b, ":")
    if colon2 != ok { ret ("", colon2) }
    let secs = push_two(&b, seconds % 60i64)
    if secs != ok { ret ("", secs) }
    let fraction = micros % TIME_FRACTION
    if fraction != 0i64 {
        let point = str.push(&b, ".")
        if point != ok { ret ("", point) }
        var scale = 100000i64
        var tail = fraction
        while scale > 0i64 {
            let pushed_digit = str.push(&b, digits_of(tail / scale))
            if pushed_digit != ok { ret ("", pushed_digit) }
            tail = tail % scale
            scale = scale / 10i64
        }
    }
    ret (str.done(&b), ok)
}

fn digits_of(digit: i64) -> str { ret "0123456789"[usize(digit % 10i64)..usize(digit % 10i64) + 1usize] }

// A field with a leading zero, `00` to `99`.
fn push_two(b: *str.Builder, v: i64) -> err {
    let tens = str.push(b, digits_of(v / 10i64))
    if tens != ok { ret tens }
    ret str.push(b, digits_of(v % 10i64))
}

fn hex(byte: u8) -> u8 {
    if byte < 10u8 { ret 48u8 + byte }
    ret 87u8 + byte
}

// `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` for a UUID, which DuckDB keeps as a 128-bit integer
// with the highest-order group in `upper`.
fn uuid_text(r: *Reader, lower: u64, upper: u64) -> (str, err) {
    var (b, builder_error) = str.builder(r.conn.arena, 36usize)
    if builder_error != ok { ret ("", builder_error) }
    var i = 0usize
    while i < 16usize {
        let pushed = push_hex_byte(&b, u8(upper >> u64(56u64 - u64(i) * 8u64)))
        if pushed != ok { ret ("", pushed) }
        if i == 3usize || i == 5usize || i == 7usize || i == 9usize {
            let dashed = str.push(&b, "-")
            if dashed != ok { ret ("", dashed) }
        }
        i += 1usize
    }
    var k = 0usize
    while k < 8usize {
        let pushed = push_hex_byte(&b, u8(lower >> u64(56u64 - u64(k) * 8u64)))
        if pushed != ok { ret ("", pushed) }
        if k == 1usize {
            let dashed = str.push(&b, "-")
            if dashed != ok { ret ("", dashed) }
        }
        k += 1usize
    }
    ret (str.done(&b), ok)
}

fn push_hex_byte(b: *str.Builder, v: u8) -> err {
    var pair: [2]u8 = zero
    pair[0usize] = hex(v >> 4u8)
    pair[1usize] = hex(v & 15u8)
    ret str.push(b, pair[0usize..])
}

// The canonical spelling of a UUID at the current row, copied or borrowed like a text.
fn uuid_value(r: *Reader, vector: usize) -> (str, err) {
    let data = as_pointer(u64(capi.vector_get_data(vector)))
    let lower = word_at(data, r.at * 16usize)
    let upper = word_at(data, r.at * 16usize + 8usize)
    let (spelled, spelled_error) = uuid_text(r, lower, upper)
    if spelled_error != ok { ret ("", spelled_error) }
    if r.borrow { ret (spelled, ok) }
    let (copied, copied_error) = copy_text_of(r, spelled)
    ret (copied, copied_error)
}

// The text spelling of a value whose type has no `db.Value` case of its own.
fn spelled_value(r: *Reader, column: usize, t: i32, vector: usize) -> (str, err) {
    let data = as_pointer(u64(capi.vector_get_data(vector)))
    if t == TYPE_DECIMAL || t == TYPE_HUGEINT || t == TYPE_UHUGEINT {
        let (spelled, spelled_error) = wide_value(r, column, t, vector)
        ret (spelled, spelled_error)
    }
    if t == TYPE_DATE {
        // A DATE is an `i32` count of days, two to a 64-bit word.
        let raw = word_at(data, r.at / 2usize * 8usize)
        let days = u32(raw >> u64(r.at % 2usize * 32usize) & 4294967295u64)
        let (spelled, spelled_error) = date_text(r, i64(mem.bitcast[i32](days)))
        ret (spelled, spelled_error)
    }
    if t == TYPE_TIME {
        let (spelled, spelled_error) = time_text(r, mem.bitcast[i64](word_at(data, r.at * 8usize)))
        ret (spelled, spelled_error)
    }
    if t == TYPE_TIME_TZ {
        let bits = word_at(data, r.at * 8usize)
        let (spelled, spelled_error) = time_text(r, mem.bitcast[i64](bits & 1099511627775u64))
        ret (spelled, spelled_error)
    }
    ret ("", ok)
}

fn fill(r: *Reader, dst: []db.Value) -> err {
    r.used = 0usize
    var i = 0usize
    while i < r.columns.len {
        let vector = capi.data_chunk_get_vector(r.chunk, i)
        let validity = capi.vector_get_validity(vector)
        if mem.address_of(validity) != 0usize {
            let word = word_at(as_pointer(u64(mem.address_of(validity))), r.at / 64usize * 8usize)
            if word >> u64(r.at % 64usize) & 1u64 == 0u64 {
                dst[i] = .Null
                i += 1usize
                continue
            }
        }
        let t = r.types[i]
        if t == TYPE_BOOLEAN || is_integer_type(t) {
            dst[i] = integer_value(r, t, vector)
        } else if t == TYPE_FLOAT || t == TYPE_DOUBLE {
            dst[i] = float_value(r, t, vector)
        } else if is_timestamp_type(t) {
            let (value, value_error) = timestamp_value(r, t, vector)
            if value_error != ok { ret value_error }
            dst[i] = value
        } else if t == TYPE_DATE || t == TYPE_TIME || t == TYPE_TIME_TZ {
            let (text, text_error) = spelled_value(r, i, t, vector)
            if text_error != ok { ret text_error }
            dst[i] = db.Value{ Text: text }
        } else if t == TYPE_VARCHAR || t == TYPE_UUID {
            if t == TYPE_UUID {
                let (text, text_error) = uuid_value(r, vector)
                if text_error != ok { ret text_error }
                dst[i] = db.Value{ Text: text }
            } else {
                let (text, text_error) = text_at(r, vector)
                if text_error != ok { ret text_error }
                dst[i] = db.Value{ Text: text }
            }
        } else if t == TYPE_ENUM {
            if r.columns[i].kind == .Bytes {
                let (data, blob_error) = blob_at(r, vector)
                if blob_error != ok { ret blob_error }
                dst[i] = db.Value{ Bytes: data }
            } else {
                let (text, text_error) = text_at(r, vector)
                if text_error != ok { ret text_error }
                dst[i] = db.Value{ Text: text }
            }
        } else if t == TYPE_BLOB {
            let (data, blob_error) = blob_at(r, vector)
            if blob_error != ok { ret blob_error }
            dst[i] = db.Value{ Bytes: data }
        } else if t == TYPE_DECIMAL || t == TYPE_HUGEINT || t == TYPE_UHUGEINT {
            let (text, text_error) = spelled_value(r, i, t, vector)
            if text_error != ok { ret text_error }
            dst[i] = db.Value{ Text: text }
        } else if t == TYPE_INTERVAL || is_nested_type(t) {
            let (data, nested_error) = blob_at(r, vector)
            if nested_error != ok { ret nested_error }
            dst[i] = db.Value{ Bytes: data }
        } else {
            dst[i] = .Null
        }
        i += 1usize
    }
    ret ok
}


fn next_row(r: *Reader, dst: []db.Value) -> (bool, err) {
    if r.closed { ret (false, db.Closed) }
    if dst.len < r.columns.len { ret (false, refuse(r.conn, "the row buffer is shorter than the row", db.InvalidQuery)) }
    if r.done { ret (false, ok) }
    if r.at >= r.rows {
        if r.chunk != 0usize { capi.destroy_data_chunk(&r.chunk) }
        r.chunk = capi.fetch_chunk(&r.result)
        r.at = 0usize
        r.rows = 0usize
        if r.chunk == 0usize {
            r.done = true
            ret (false, ok)
        }
        r.rows = capi.data_chunk_get_size(r.chunk)
        if r.rows == 0usize {
            r.done = true
            ret (false, ok)
        }
    }
    let fill_error = fill(r, dst)
    if fill_error != ok { ret (false, fill_error) }
    r.at += 1usize
    ret (true, ok)
}

// Ends a reader that has not reached its end: its chunk and its result go back to DuckDB.
fn finish_reader(r: *Reader) {
    if r.closed { ret }
    r.closed = true
    r.done = true
    if r.chunk != 0usize {
        capi.destroy_data_chunk(&r.chunk)
        r.chunk = 0usize
    }
    capi.destroy_result(&r.result)
}

// --- the driver table

fn d_close(ctx: *void) -> err {
    let c = conn_of(ctx)
    var handle = c.handle
    capi.disconnect(&handle)
    var database = c.database
    capi.close(&database)
    ret ok
}

fn d_prepare(ctx: *void, sql: str) -> (db.Statement, err) {
    let c = conn_of(ctx)
    var statement: db.Statement = zero
    if count_statements(sql) != 1usize { ret (statement, refuse(c, "a prepared statement takes exactly one statement", db.InvalidQuery)) }
    let (compiled, compile_error) = compile_one(c, sql)
    if compile_error != ok { ret (statement, compile_error) }
    var handle = compiled
    let (stmts, stmt_error) = mem.alloc[Stmt](c.arena, 1usize)
    if stmt_error != ok {
        capi.destroy_prepare(&handle)
        ret (statement, stmt_error)
    }
    stmts[0usize] = Stmt { conn: c, handle: handle, closed: false }
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

// One transaction at a time on a connection: DuckDB has no nesting under BEGIN.
fn d_begin(ctx: *void) -> (db.Transaction, err) {
    let c = conn_of(ctx)
    var transaction: db.Transaction = zero
    if c.in_transaction { ret (transaction, refuse(c, "a transaction is already open on this connection", db.Busy)) }
    let (txs, tx_error) = mem.alloc[Tx](c.arena, 1usize)
    if tx_error != ok { ret (transaction, tx_error) }
    let (ignored, begin_error) = execute_text(c, "BEGIN TRANSACTION", zero)
    if begin_error != ok { ret (transaction, begin_error) }
    c.in_transaction = true
    txs[0usize] = Tx { conn: c }
    transaction.ctx = mem.cast[*void](&txs[0usize])
    ret (transaction, ok)
}

// The statement stays compiled; a closed one's reader answers `Closed`.
fn d_statement_close(ctx: *void) -> err {
    let s = stmt_of(ctx)
    if s.handle != 0usize {
        capi.destroy_prepare(&s.handle)
        s.handle = 0usize
    }
    s.closed = true
    ret ok
}

fn d_statement_execute(ctx: *void, params: []const db.Parameter) -> (u64, err) {
    let s = stmt_of(ctx)
    if s.closed { ret (0u64, db.Closed) }
    let bind_error = bind_all(s.conn, s.handle, params)
    if bind_error != ok { ret (0u64, bind_error) }
    let (affected, run_error) = run(s.conn, s.handle)
    ret (affected, run_error)
}

fn d_statement_query(ctx: *void, params: []const db.Parameter) -> (db.Rows, err) {
    let s = stmt_of(ctx)
    if s.closed { ret (zero, db.Closed) }
    let bind_error = bind_all(s.conn, s.handle, params)
    if bind_error != ok { ret (zero, bind_error) }
    let (rows, rows_error) = reader(s.conn, s.handle, s, false)
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

// A COMMIT that fails is rolled back, because `e.db` has already closed the transaction's
// handle.
fn d_transaction_commit(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    let (ignored, commit_error) = execute_text(c, "COMMIT", zero)
    if commit_error != ok {
        let (undone, undo_error) = execute_text(c, "ROLLBACK", zero)
    }
    c.in_transaction = false
    ret commit_error
}

fn d_transaction_rollback(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    let (ignored, rollback_error) = execute_text(c, "ROLLBACK", zero)
    c.in_transaction = false
    ret rollback_error
}
