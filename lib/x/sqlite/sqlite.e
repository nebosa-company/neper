// An `e.db` driver over the SQLite 3 C library. `open` answers a `db.Connection` whose table
// is this module's; everything after that goes through `e.db`. `detail` and `version` are the
// only calls a program makes here directly.
//
// Memory: the arena handed to `open` is retained and borrowed for the connection's life.
// Every statement, row reader and transaction context comes from it, and a reader's text and
// blob values are copied into a buffer of the reader's that is valid until its next row. The
// caller marks and resets that arena around work whose results it no longer needs.
//
// Values: a parameter binds by its SQLite storage class -- `Bool` as 0/1, `Time` as the
// instant's nanoseconds, `U64` only while it fits an `i64`. A column's kind is its declared
// affinity (an expression column has none, so it takes the first row's storage class), and a
// value comes back as its own storage class, except that an integer in a `BOOL` column is a
// `Bool` and one in a `DATE`/`TIME` column is a `Time`.
//
// Parameters: an unnamed one is positional; a named one is looked up as written (`:id`,
// `@id`, `$id`) and then with `:` in front. A statement must have exactly as many parameters
// as it is given. `execute` runs every statement in its text; `query` and `prepare` take one.
use e.mem
use e.time
use e.db
use x.sqlite.capi

type Detail = struct { code: i32, extended: i32, message: str }
error CannotOpen
error Failed

// sqlite3_close_v2 is the newest call bound here.
const MIN_VERSION: i32 = 3007014i32

type Conn = struct { handle: usize, arena: *mem.Arena, driver: *const db.Driver, note: str }
type Stmt = struct { conn: *Conn, handle: usize }
type Reader = struct { conn: *Conn, handle: usize, statement: *Stmt, owned: bool, pending: i32, columns: []db.Column, buffer: []u8, used: usize }
type Tx = struct { conn: *Conn }

const SQLITE_OK: i32 = 0i32
const SQLITE_ERROR: i32 = 1i32
const SQLITE_BUSY: i32 = 5i32
const SQLITE_LOCKED: i32 = 6i32
const SQLITE_CONSTRAINT: i32 = 19i32
const SQLITE_MISMATCH: i32 = 20i32
const SQLITE_RANGE: i32 = 25i32
const SQLITE_ROW: i32 = 100i32
const SQLITE_DONE: i32 = 101i32
const SQLITE_INTEGER: i32 = 1i32
const SQLITE_FLOAT: i32 = 2i32
const SQLITE_TEXT: i32 = 3i32
const SQLITE_BLOB: i32 = 4i32
// READWRITE | CREATE | URI, so `file:...?mode=ro` and `:memory:` both work.
const OPEN_FLAGS: i32 = 70i32
const TRANSIENT: usize = 18446744073709551615usize
const I32_MAX: usize = 2147483647usize
const I64_MAX: u64 = 9223372036854775807u64
// No C string this module reads is near this long; the walk stops at the terminator.
const MAX_C_STRING: usize = 65536usize

fn version() -> i32 { ret capi.libversion_number() }

fn open(a: *mem.Arena, path: str) -> (db.Connection, err) {
    var connection: db.Connection = zero
    if version() < MIN_VERSION { ret (connection, db.Unsupported) }
    let mark = mem.mark(a)
    let (name, name_error) = c_copy(a, path)
    if name_error != ok { ret (connection, name_error) }
    var handle = 0usize
    let rc = capi.open_v2(&name[0usize], &handle, OPEN_FLAGS, 0usize)
    mem.reset(a, mark)
    // A failed open still hands back a handle that must be closed.
    if rc != SQLITE_OK {
        if handle != 0usize { let closed_failed = capi.close_v2(handle) }
        ret (connection, CannotOpen)
    }
    let (conns, conn_error) = mem.alloc[Conn](a, 1usize)
    if conn_error != ok {
        let closed = capi.close_v2(handle)
        ret (connection, conn_error)
    }
    let (drivers, driver_error) = mem.alloc[db.Driver](a, 1usize)
    if driver_error != ok {
        let closed_driver = capi.close_v2(handle)
        ret (connection, driver_error)
    }
    drivers[0usize] = db.Driver { close: d_close, prepare: d_prepare, execute: d_execute, query: d_query, begin: d_begin, statement_close: d_statement_close, statement_execute: d_statement_execute, statement_query: d_statement_query, rows_columns: d_rows_columns, rows_next: d_rows_next, rows_close: d_rows_close, transaction_execute: d_transaction_execute, transaction_query: d_transaction_query, transaction_commit: d_transaction_commit, transaction_rollback: d_transaction_rollback }
    conns[0usize] = Conn { handle: handle, arena: a, driver: &drivers[0usize], note: "" }
    let c = &conns[0usize]
    connection.ctx = mem.cast[*void](c)
    connection.driver = c.driver
    ret (connection, ok)
}

// Why the connection's last call failed: SQLite's own code and message, or -- when the driver
// refused before SQLite was asked -- code 0 and the driver's reason. The message is copied
// into `a`.
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err) {
    var out: Detail = zero
    if connection.ctx == nil { ret (out, db.Closed) }
    let c = conn_of(connection.ctx)
    if c.note.len != 0usize {
        out.message = c.note
        ret (out, ok)
    }
    out.extended = capi.extended_errcode(c.handle)
    out.code = out.extended & 255i32
    let (message, message_error) = c_read(a, capi.errmsg(c.handle))
    out.message = message
    ret (out, message_error)
}

fn conn_of(ctx: *void) -> *Conn { ret mem.cast[*Conn](ctx) }
fn stmt_of(ctx: *void) -> *Stmt { ret mem.cast[*Stmt](ctx) }
fn reader_of(ctx: *void) -> *Reader { ret mem.cast[*Reader](ctx) }
fn tx_of(ctx: *void) -> *Tx { ret mem.cast[*Tx](ctx) }

// --- errors

fn refuse(c: *Conn, note: str, e: err) -> err {
    c.note = note
    ret e
}

fn failure(c: *Conn, rc: i32) -> err {
    c.note = ""
    let primary = rc & 255i32
    if primary == SQLITE_ERROR || primary == SQLITE_RANGE { ret db.InvalidQuery }
    if primary == SQLITE_BUSY || primary == SQLITE_LOCKED { ret db.Busy }
    if primary == SQLITE_CONSTRAINT || primary == SQLITE_MISMATCH { ret db.Constraint }
    ret Failed
}

// --- foreign memory

// A NUL-terminated copy of `s` in `a`.
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

// `n` bytes at a foreign address, copied into `dst`. `mem.view` names the region without
// reading it, so nothing past `n` is touched.
fn copy_foreign(dst: []u8, p: *u8, n: usize) {
    var region: mem.Arena = zero
    region.base = p
    region.cap = n
    region.off = 0usize
    let bytes = mem.view(&region, 0usize, n)
    var i = 0usize
    while i < n {
        dst[i] = bytes[i]
        i += 1usize
    }
}

// A C string's length; the walk stops at the terminator, which SQLite always writes.
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

// --- statements

// Compiles the first statement of `sql[from..]`. A handle of zero with `ok` means the rest
// held only whitespace and comments; `next` is where the following statement starts.
fn compile(c: *Conn, sql: str, from: usize) -> (usize, usize, err) {
    if from >= sql.len { ret (0usize, sql.len, ok) }
    let rest = sql.len - from
    if rest > I32_MAX { ret (0usize, sql.len, refuse(c, "the SQL text is longer than SQLite accepts", db.Unsupported)) }
    var handle = 0usize
    var tail = 0usize
    let rc = capi.prepare_v2(c.handle, &sql[from], i32(rest), &handle, &tail)
    if rc != SQLITE_OK {
        if handle != 0usize { let finalized = capi.finalize(handle) }
        ret (0usize, sql.len, failure(c, rc))
    }
    var next = sql.len
    if tail != 0usize { next = from + (tail - mem.address_of(&sql[from])) }
    ret (handle, next, ok)
}

// One statement and nothing after it but whitespace and comments.
fn compile_one(c: *Conn, sql: str) -> (usize, err) {
    let (handle, next, compile_error) = compile(c, sql, 0usize)
    if compile_error != ok { ret (0usize, compile_error) }
    if handle == 0usize { ret (0usize, refuse(c, "the SQL text holds no statement", db.InvalidQuery)) }
    let (extra, extra_next, extra_error) = compile(c, sql, next)
    if extra_error != ok || extra != 0usize {
        if extra != 0usize { let finalized_extra = capi.finalize(extra) }
        let finalized = capi.finalize(handle)
        ret (0usize, refuse(c, "the SQL text holds more than one statement", db.InvalidQuery))
    }
    ret (handle, ok)
}

fn bind_all(c: *Conn, handle: usize, params: []const db.Parameter) -> err {
    let rc_clear = capi.clear_bindings(handle)
    if usize(capi.bind_parameter_count(handle)) != params.len {
        ret refuse(c, "the statement's parameter count differs from the parameters given", db.InvalidQuery)
    }
    var i = 0usize
    while i < params.len {
        var index = i32(i + 1usize)
        if params[i].name.len != 0usize {
            let (found, find_error) = parameter_index(c, handle, params[i].name)
            if find_error != ok { ret find_error }
            if found == 0i32 { ret refuse(c, "the statement has no parameter of that name", db.InvalidQuery) }
            index = found
        }
        let bind_error = bind_value(c, handle, index, params[i].value)
        if bind_error != ok { ret bind_error }
        i += 1usize
    }
    ret ok
}

// The index of a named parameter as written, else with `:` in front; zero when it has neither.
fn parameter_index(c: *Conn, handle: usize, name: str) -> (i32, err) {
    let mark = mem.mark(c.arena)
    let (plain, plain_error) = c_copy(c.arena, name)
    if plain_error != ok { ret (0i32, plain_error) }
    var index = capi.bind_parameter_index(handle, &plain[0usize])
    if index == 0i32 {
        let (prefixed, prefixed_error) = mem.alloc[u8](c.arena, name.len + 2usize)
        if prefixed_error != ok {
            mem.reset(c.arena, mark)
            ret (0i32, prefixed_error)
        }
        prefixed[0usize] = 58u8
        var i = 0usize
        while i < name.len {
            prefixed[i + 1usize] = name[i]
            i += 1usize
        }
        prefixed[name.len + 1usize] = 0u8
        index = capi.bind_parameter_index(handle, &prefixed[0usize])
    }
    mem.reset(c.arena, mark)
    ret (index, ok)
}

fn bind_value(c: *Conn, handle: usize, index: i32, value: db.Value) -> err {
    var rc = SQLITE_OK
    // A zero-length text or blob still needs an address: a null one would bind NULL.
    var none: [1]u8 = zero
    switch value {
    case .Null:
        rc = capi.bind_null(handle, index)
    case .Bool as flag:
        var truth = 0i64
        if flag { truth = 1i64 }
        rc = capi.bind_int64(handle, index, truth)
    case .I64 as signed:
        rc = capi.bind_int64(handle, index, signed)
    case .U64 as unsigned:
        if unsigned > I64_MAX { ret refuse(c, "an unsigned value does not fit SQLite's 64-bit integer", db.Unsupported) }
        rc = capi.bind_int64(handle, index, i64(unsigned))
    case .F64 as real:
        rc = capi.bind_double(handle, index, real)
    case .Text as s:
        if s.len > I32_MAX { ret refuse(c, "a text value is longer than SQLite accepts", db.Unsupported) }
        if s.len == 0usize {
            rc = capi.bind_text(handle, index, &none[0usize], 0i32, TRANSIENT)
        } else {
            rc = capi.bind_text(handle, index, &s[0usize], i32(s.len), TRANSIENT)
        }
    case .Bytes as data:
        if data.len > I32_MAX { ret refuse(c, "a blob value is longer than SQLite accepts", db.Unsupported) }
        if data.len == 0usize {
            rc = capi.bind_blob(handle, index, &none[0usize], 0i32, TRANSIENT)
        } else {
            rc = capi.bind_blob(handle, index, &data[0usize], i32(data.len), TRANSIENT)
        }
    case .Time as instant:
        rc = capi.bind_int64(handle, index, instant.nanos)
    }
    if rc != SQLITE_OK { ret failure(c, rc) }
    ret ok
}

// Steps to the end, discarding rows, and answers the rows this statement changed. A
// statement that changes nothing (DDL included) leaves the total alone, and `changes` would
// still answer for the one before it.
fn run(c: *Conn, handle: usize) -> (u64, err) {
    let before = capi.total_changes(c.handle)
    while true {
        let rc = capi.step(handle)
        if rc == SQLITE_DONE { break }
        if rc != SQLITE_ROW {
            let reset_rc = capi.reset(handle)
            ret (0u64, failure(c, rc))
        }
    }
    c.note = ""
    if capi.total_changes(c.handle) == before { ret (0u64, ok) }
    ret (u64(capi.changes(c.handle)), ok)
}

fn execute_text(c: *Conn, sql: str, params: []const db.Parameter) -> (u64, err) {
    var affected = 0u64
    var from = 0usize
    while from < sql.len {
        let (handle, next, compile_error) = compile(c, sql, from)
        if compile_error != ok { ret (affected, compile_error) }
        if handle == 0usize { break }
        from = next
        let bind_error = bind_all(c, handle, params)
        if bind_error != ok {
            let unbound = capi.finalize(handle)
            ret (affected, bind_error)
        }
        let (count, run_error) = run(c, handle)
        let finalized = capi.finalize(handle)
        if run_error != ok { ret (affected, run_error) }
        affected += count
    }
    c.note = ""
    ret (affected, ok)
}

// --- row readers

// Steps once so a failing query fails here rather than at its first row, and so an
// expression column can take its kind from that row.
fn reader(c: *Conn, handle: usize, statement: *Stmt, owned: bool) -> (db.Rows, err) {
    var rows: db.Rows = zero
    let rc = capi.step(handle)
    if rc != SQLITE_ROW && rc != SQLITE_DONE {
        if owned {
            let finalized = capi.finalize(handle)
        } else {
            let reset_rc = capi.reset(handle)
        }
        ret (rows, failure(c, rc))
    }
    let (readers, reader_error) = mem.alloc[Reader](c.arena, 1usize)
    if reader_error != ok {
        if owned { let finalized_early = capi.finalize(handle) }
        ret (rows, reader_error)
    }
    // Arena memory is not cleared, so every field is written.
    var no_buffer: []u8 = zero
    var no_columns: []db.Column = zero
    readers[0usize] = Reader { conn: c, handle: handle, statement: statement, owned: owned, pending: rc, columns: no_columns, buffer: no_buffer, used: 0usize }
    let r = &readers[0usize]
    let count = usize(capi.column_count(handle))
    let (cols, cols_error) = mem.alloc[db.Column](c.arena, count)
    if cols_error != ok {
        if owned { let finalized_cols = capi.finalize(handle) }
        ret (rows, cols_error)
    }
    var i = 0usize
    while i < count {
        let (name, name_error) = c_read(c.arena, capi.column_name(handle, i32(i)))
        if name_error != ok {
            if owned { let finalized_name = capi.finalize(handle) }
            ret (rows, name_error)
        }
        var kind = declared_kind(capi.column_decltype(handle, i32(i)))
        if kind == .Null && rc == SQLITE_ROW { kind = stored_kind(capi.column_type(handle, i32(i))) }
        cols[i] = db.Column { name: name, kind: kind, nullable: true }
        i += 1usize
    }
    r.columns = cols
    c.note = ""
    rows.ctx = mem.cast[*void](r)
    ret (rows, ok)
}

fn stored_kind(storage: i32) -> db.ValueKind {
    if storage == SQLITE_INTEGER { ret .I64 }
    if storage == SQLITE_FLOAT { ret .F64 }
    if storage == SQLITE_TEXT { ret .Text }
    if storage == SQLITE_BLOB { ret .Bytes }
    ret .Null
}

// SQLite's affinity rules (section 3.1 of its datatype page), with BOOL and DATE/TIME asked
// first because neither is an affinity of its own. No declared type is `Null`.
fn declared_kind(p: *u8) -> db.ValueKind {
    if mem.address_of(p) == 0usize { ret .Null }
    var spelled: [64]u8 = zero
    var n = c_length(p)
    if n == 0usize { ret .Null }
    if n > 64usize { n = 64usize }
    copy_foreign(spelled[0usize..n], p, n)
    let declared = spelled[0usize..n]
    if contains(declared, "BOOL") { ret .Bool }
    if contains(declared, "DATE") || contains(declared, "TIME") { ret .Time }
    if contains(declared, "INT") { ret .I64 }
    if contains(declared, "CHAR") || contains(declared, "CLOB") || contains(declared, "TEXT") { ret .Text }
    if contains(declared, "BLOB") { ret .Bytes }
    ret .F64
}

// Whether `upper` occurs in `s`, ignoring ASCII case.
fn contains(s: []const u8, upper: str) -> bool {
    if upper.len > s.len { ret false }
    var from = 0usize
    while from + upper.len <= s.len {
        var j = 0usize
        while j < upper.len {
            var b = s[from + j]
            if b >= 97u8 && b <= 122u8 { b -= 32u8 }
            if b != upper[j] { break }
            j += 1usize
        }
        if j == upper.len { ret true }
        from += 1usize
    }
    ret false
}

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

// The bytes of a text or blob column, copied into the reader's buffer.
fn column_copy(r: *Reader, column: i32, blob: bool) -> ([]u8, err) {
    var p = capi.column_text(r.handle, column)
    if blob { p = capi.column_blob(r.handle, column) }
    let n = usize(capi.column_bytes(r.handle, column))
    if n == 0usize || mem.address_of(p) == 0usize { ret (r.buffer[0usize..0usize], ok) }
    let reserve_error = reserve(r, n)
    if reserve_error != ok { ret (r.buffer[0usize..0usize], reserve_error) }
    let start = r.used
    copy_foreign(r.buffer[start..start + n], p, n)
    r.used = start + n
    ret (r.buffer[start..start + n], ok)
}

fn fill(r: *Reader, dst: []db.Value) -> err {
    r.used = 0usize
    var i = 0usize
    while i < r.columns.len {
        let column = i32(i)
        let storage = capi.column_type(r.handle, column)
        let kind = r.columns[i].kind
        if storage == SQLITE_INTEGER {
            let number = capi.column_int64(r.handle, column)
            if kind == .Bool {
                dst[i] = db.Value{ Bool: number != 0i64 }
            } else if kind == .Time {
                dst[i] = db.Value{ Time: time.Instant { nanos: number } }
            } else {
                dst[i] = db.Value{ I64: number }
            }
        } else if storage == SQLITE_FLOAT {
            dst[i] = db.Value{ F64: capi.column_double(r.handle, column) }
        } else if storage == SQLITE_TEXT {
            let (bytes, text_error) = column_copy(r, column, false)
            if text_error != ok { ret text_error }
            let s: str = bytes
            dst[i] = db.Value{ Text: s }
        } else if storage == SQLITE_BLOB {
            let (data, blob_error) = column_copy(r, column, true)
            if blob_error != ok { ret blob_error }
            dst[i] = db.Value{ Bytes: data }
        } else {
            dst[i] = .Null
        }
        i += 1usize
    }
    ret ok
}

// --- the driver table

fn d_close(ctx: *void) -> err {
    let c = conn_of(ctx)
    // close_v2 waits for statements still open, so none of them is cut off.
    let rc = capi.close_v2(c.handle)
    if rc != SQLITE_OK { ret failure(c, rc) }
    ret ok
}

fn d_prepare(ctx: *void, sql: str) -> (db.Statement, err) {
    let c = conn_of(ctx)
    var statement: db.Statement = zero
    let (handle, compile_error) = compile_one(c, sql)
    if compile_error != ok { ret (statement, compile_error) }
    let (stmts, stmt_error) = mem.alloc[Stmt](c.arena, 1usize)
    if stmt_error != ok {
        let finalized = capi.finalize(handle)
        ret (statement, stmt_error)
    }
    stmts[0usize] = Stmt { conn: c, handle: handle }
    c.note = ""
    statement.ctx = mem.cast[*void](&stmts[0usize])
    ret (statement, ok)
}

fn d_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = execute_text(conn_of(ctx), sql, params)
    ret (affected, execute_error)
}

fn d_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let c = conn_of(ctx)
    let (handle, compile_error) = compile_one(c, sql)
    if compile_error != ok { ret (zero, compile_error) }
    let bind_error = bind_all(c, handle, params)
    if bind_error != ok {
        let finalized = capi.finalize(handle)
        ret (zero, bind_error)
    }
    let (rows, rows_error) = reader(c, handle, nil, true)
    ret (rows, rows_error)
}

// One transaction at a time on a connection: SQLite has no nesting under BEGIN.
fn d_begin(ctx: *void) -> (db.Transaction, err) {
    let c = conn_of(ctx)
    var transaction: db.Transaction = zero
    if capi.get_autocommit(c.handle) == 0i32 { ret (transaction, refuse(c, "a transaction is already open on this connection", db.Busy)) }
    let (txs, tx_error) = mem.alloc[Tx](c.arena, 1usize)
    if tx_error != ok { ret (transaction, tx_error) }
    let (ignored, begin_error) = execute_text(c, "BEGIN", zero)
    if begin_error != ok { ret (transaction, begin_error) }
    txs[0usize] = Tx { conn: c }
    transaction.ctx = mem.cast[*void](&txs[0usize])
    ret (transaction, ok)
}

// The statement stays compiled; a closed one's reader answers `Closed`.
fn d_statement_close(ctx: *void) -> err {
    let s = stmt_of(ctx)
    let rc = capi.finalize(s.handle)
    s.handle = 0usize
    ret ok
}

fn d_statement_execute(ctx: *void, params: []const db.Parameter) -> (u64, err) {
    let s = stmt_of(ctx)
    let reset_rc = capi.reset(s.handle)
    let bind_error = bind_all(s.conn, s.handle, params)
    if bind_error != ok { ret (0u64, bind_error) }
    let (affected, run_error) = run(s.conn, s.handle)
    let after_rc = capi.reset(s.handle)
    ret (affected, run_error)
}

fn d_statement_query(ctx: *void, params: []const db.Parameter) -> (db.Rows, err) {
    let s = stmt_of(ctx)
    let reset_rc = capi.reset(s.handle)
    let bind_error = bind_all(s.conn, s.handle, params)
    if bind_error != ok { ret (zero, bind_error) }
    let (rows, rows_error) = reader(s.conn, s.handle, s, false)
    ret (rows, rows_error)
}

fn d_rows_columns(ctx: *void) -> []const db.Column { ret reader_of(ctx).columns }

fn d_rows_next(ctx: *void, dst: []db.Value) -> (bool, err) {
    let r = reader_of(ctx)
    if r.statement != nil && r.statement.handle == 0usize { ret (false, db.Closed) }
    if dst.len < r.columns.len { ret (false, refuse(r.conn, "the row buffer is shorter than the row", db.InvalidQuery)) }
    if r.pending == 0i32 { r.pending = capi.step(r.handle) }
    if r.pending == SQLITE_DONE { ret (false, ok) }
    if r.pending != SQLITE_ROW {
        let rc = r.pending
        r.pending = SQLITE_DONE
        ret (false, failure(r.conn, rc))
    }
    r.pending = 0i32
    let fill_error = fill(r, dst)
    if fill_error != ok { ret (false, fill_error) }
    ret (true, ok)
}

fn d_rows_close(ctx: *void) -> err {
    let r = reader_of(ctx)
    if r.owned {
        let finalized = capi.finalize(r.handle)
    } else if r.statement.handle != 0usize {
        let reset_rc = capi.reset(r.handle)
    }
    ret ok
}

fn d_transaction_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = execute_text(tx_of(ctx).conn, sql, params)
    ret (affected, execute_error)
}

fn d_transaction_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, rows_error) = d_query(mem.cast[*void](tx_of(ctx).conn), sql, params)
    ret (rows, rows_error)
}

// A COMMIT that fails (a busy database) leaves the transaction open under a handle `e.db`
// has already closed, so it is rolled back and the commit's error returned.
fn d_transaction_commit(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    let (ignored, commit_error) = execute_text(c, "COMMIT", zero)
    if commit_error != ok && capi.get_autocommit(c.handle) == 0i32 {
        let note = c.note
        let (undone, rollback_error) = execute_text(c, "ROLLBACK", zero)
        c.note = note
    }
    ret commit_error
}

fn d_transaction_rollback(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    if capi.get_autocommit(c.handle) != 0i32 { ret ok }
    let (ignored, rollback_error) = execute_text(c, "ROLLBACK", zero)
    ret rollback_error
}
