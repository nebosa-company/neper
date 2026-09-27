// An `e.db` driver over libpq, PostgreSQL's client library. `open` takes a libpq connection
// string (`host=... port=... user=... dbname=...` or a `postgresql://` URI) and answers a
// `db.Connection` whose table is this module's; everything after that goes through `e.db`.
//
// Memory: the arena handed to `open` is retained and borrowed for the connection's life.
// Contexts, column names and row buffers come from it; a reader's values are copied into a
// buffer of its own that is valid until its next row. Read with `db.reader_next_borrowed`,
// text and `bytea` values are libpq's own bytes instead: the row's result is kept until the
// next row or the reader's end rather than cleared once the row is filled. Error text is kept in fixed buffers the
// connection allocates once, so failures do not grow the arena.
//
// Wire format: results are asked for in binary, so integers, floats, booleans, `bytea` and
// timestamps arrive exact rather than as text to be re-parsed. `numeric` is rendered as its
// exact decimal text, `uuid` in its canonical spelling, and a type this module does not know
// arrives as its raw binary representation in `Bytes`.
//
// Streaming: a query runs in single-row mode, so rows arrive one at a time and nothing buffers
// the whole result. While a reader is open the connection is busy: another call on it answers
// `db.Busy`. Closing a reader early reads and discards the rows still to come.
//
// Parameters are positional (`$1`, `$2`, ...); a named `db.Parameter` is refused.
use e.mem
use e.str
use e.time
use e.db
use x.postgresql.capi

type Detail = struct { sqlstate: str, message: str, constraint: str }
error CannotConnect
error Aborted
error Failed

// PQsetSingleRowMode is the newest call bound here (9.2).
const MIN_VERSION: i32 = 90200i32

type Conn = struct { handle: usize, arena: *mem.Arena, driver: *const db.Driver, active: *Reader, statements: u64, state: []u8, state_len: usize, message: []u8, message_len: usize, constraint: []u8, constraint_len: usize }
type Stmt = struct { conn: *Conn, name: []u8, oids: []u32, closed: bool }
type Reader = struct { conn: *Conn, statement: *Stmt, result: usize, done: bool, closed: bool, oids: []u32, columns: []db.Column, buffer: []u8, used: usize, borrow: bool, held: usize }
type Tx = struct { conn: *Conn }
// `address` is where the value starts; an empty non-null value keeps a byte behind it, since a
// null address is SQL NULL.
type Piece = struct { bytes: []u8, address: usize, oid: u32, format: i32, null: bool }
type Encoded = struct { types: []u32, values: []usize, lengths: []i32, formats: []i32 }

const CONNECTION_OK: i32 = 0i32
const PGRES_EMPTY_QUERY: i32 = 0i32
const PGRES_COMMAND_OK: i32 = 1i32
const PGRES_TUPLES_OK: i32 = 2i32
const PGRES_COPY_OUT: i32 = 3i32
const PGRES_COPY_IN: i32 = 4i32
const PGRES_COPY_BOTH: i32 = 8i32
const PGRES_SINGLE_TUPLE: i32 = 9i32
const PQTRANS_IDLE: i32 = 0i32
const PQTRANS_INERROR: i32 = 3i32
const DIAG_SQLSTATE: i32 = 67i32
const DIAG_MESSAGE_PRIMARY: i32 = 77i32
const DIAG_CONSTRAINT_NAME: i32 = 110i32

const OID_BOOL: u32 = 16u32
const OID_BYTEA: u32 = 17u32
const OID_CHAR: u32 = 18u32
const OID_NAME: u32 = 19u32
const OID_INT8: u32 = 20u32
const OID_INT2: u32 = 21u32
const OID_INT4: u32 = 23u32
const OID_TEXT: u32 = 25u32
const OID_OID: u32 = 26u32
const OID_JSON: u32 = 114u32
const OID_XML: u32 = 142u32
const OID_FLOAT4: u32 = 700u32
const OID_FLOAT8: u32 = 701u32
const OID_UNKNOWN: u32 = 705u32
const OID_BPCHAR: u32 = 1042u32
const OID_VARCHAR: u32 = 1043u32
const OID_DATE: u32 = 1082u32
const OID_TIMESTAMP: u32 = 1114u32
const OID_TIMESTAMPTZ: u32 = 1184u32
const OID_NUMERIC: u32 = 1700u32
const OID_UUID: u32 = 2950u32
const OID_JSONB: u32 = 3802u32

// 2000-01-01, PostgreSQL's epoch, in Unix microseconds and days.
const EPOCH_MICROS: i64 = 946684800000000i64
const EPOCH_DAYS: i64 = 10957i64
const I64_MAX: i64 = 9223372036854775807i64
const I64_MIN: i64 = -9223372036854775808i64
const I32_MAX: i64 = 2147483647i64
const I32_MIN: i64 = -2147483648i64
const MAX_C_STRING: usize = 1048576usize
const STATE_CAP: usize = 8usize
const MESSAGE_CAP: usize = 1024usize
const CONSTRAINT_CAP: usize = 256usize

fn version() -> i32 { ret capi.lib_version() }

fn open(a: *mem.Arena, conninfo: str) -> (db.Connection, err) {
    var connection: db.Connection = zero
    if version() < MIN_VERSION { ret (connection, db.Unsupported) }
    let mark = mem.mark(a)
    let (info, info_error) = c_copy(a, conninfo)
    if info_error != ok { ret (connection, info_error) }
    let handle = capi.connectdb(&info[0usize])
    mem.reset(a, mark)
    if handle == 0usize { ret (connection, CannotConnect) }
    if capi.status(handle) != CONNECTION_OK {
        capi.finish(handle)
        ret (connection, CannotConnect)
    }
    let (conns, conn_error) = mem.alloc[Conn](a, 1usize)
    let (drivers, driver_error) = mem.alloc[db.Driver](a, 1usize)
    let (text_buffers, text_error) = mem.alloc[u8](a, STATE_CAP + MESSAGE_CAP + CONSTRAINT_CAP)
    if conn_error != ok || driver_error != ok || text_error != ok {
        capi.finish(handle)
        ret (connection, db.Unsupported)
    }
    drivers[0usize] = db.Driver { close: d_close, prepare: d_prepare, execute: d_execute, query: d_query, begin: d_begin, statement_close: d_statement_close, statement_execute: d_statement_execute, statement_query: d_statement_query, rows_columns: d_rows_columns, rows_next: d_rows_next, rows_next_borrowed: d_rows_next_borrowed, rows_close: d_rows_close, transaction_execute: d_transaction_execute, transaction_query: d_transaction_query, transaction_commit: d_transaction_commit, transaction_rollback: d_transaction_rollback }
    // Arena memory is not cleared, so every field is written.
    let state_end = STATE_CAP
    let message_end = STATE_CAP + MESSAGE_CAP
    conns[0usize] = Conn { handle: handle, arena: a, driver: &drivers[0usize], active: nil, statements: 0u64, state: text_buffers[0usize..state_end], state_len: 0usize, message: text_buffers[state_end..message_end], message_len: 0usize, constraint: text_buffers[message_end..], constraint_len: 0usize }
    let c = &conns[0usize]
    // Text columns are handed back as they arrive, so they must arrive as UTF-8.
    let (ignored, encoding_error) = execute_text(c, "SET client_encoding = 'UTF8'", zero)
    if encoding_error != ok {
        capi.finish(handle)
        ret (connection, encoding_error)
    }
    connection.ctx = mem.cast[*void](c)
    connection.driver = c.driver
    ret (connection, ok)
}

// Why the connection's last call failed: the server's SQLSTATE, primary message and violated
// constraint when it said, libpq's own message when the failure was local, or -- when the
// driver refused before sending anything -- an empty SQLSTATE and the driver's reason. The
// strings are copied into `a`.
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err) {
    var out: Detail = zero
    if connection.ctx == nil { ret (out, db.Closed) }
    let c = conn_of(connection.ctx)
    let (sqlstate, state_error) = copy_text(a, c.state[0usize..c.state_len])
    if state_error != ok { ret (out, state_error) }
    let (message, message_error) = copy_text(a, c.message[0usize..c.message_len])
    if message_error != ok { ret (out, message_error) }
    let (constraint, constraint_error) = copy_text(a, c.constraint[0usize..c.constraint_len])
    if constraint_error != ok { ret (out, constraint_error) }
    out.sqlstate = sqlstate
    out.message = message
    out.constraint = constraint
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

// Copies what fits of `s` into `dst` and answers how much that was.
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
    c.state_len = 0usize
    c.message_len = 0usize
    c.constraint_len = 0usize
}

fn refuse(c: *Conn, note: str, e: err) -> err {
    clear_detail(c)
    c.message_len = keep(c.message, note)
    ret e
}

// A failure the server reported in a result.
fn fail_result(c: *Conn, result: usize) -> err {
    clear_detail(c)
    c.state_len = keep_c(c.state, capi.result_error_field(result, DIAG_SQLSTATE))
    c.message_len = keep_c(c.message, capi.result_error_field(result, DIAG_MESSAGE_PRIMARY))
    if c.message_len == 0usize { c.message_len = keep_c(c.message, capi.result_error_message(result)) }
    c.constraint_len = keep_c(c.constraint, capi.result_error_field(result, DIAG_CONSTRAINT_NAME))
    ret mapped(c.state[0usize..c.state_len])
}

// A failure libpq reported on the connection: nothing reached the server, or it went away.
fn fail_connection(c: *Conn) -> err {
    clear_detail(c)
    c.message_len = keep_c(c.message, capi.error_message(c.handle))
    ret Failed
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

// SQLSTATE classes onto `e.db`'s errors (PostgreSQL's appendix A).
fn mapped(state: []const u8) -> err {
    if starts(state, "23") { ret db.Constraint }
    if starts(state, "40001") || starts(state, "40P01") || starts(state, "55P03") { ret db.Busy }
    if starts(state, "25P02") { ret Aborted }
    if starts(state, "0A") { ret db.Unsupported }
    if starts(state, "42") || starts(state, "22") || starts(state, "3D") || starts(state, "3F") || starts(state, "26") || starts(state, "08P01") { ret db.InvalidQuery }
    ret Failed
}

// --- foreign memory

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

// A C string's length; the walk stops at the terminator, which libpq always writes.
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

fn c_read(a: *mem.Arena, p: *u8) -> (str, err) {
    if mem.address_of(p) == 0usize { ret ("", ok) }
    let n = c_length(p)
    if n == 0usize { ret ("", ok) }
    let (bytes, allocation_error) = mem.alloc[u8](a, n)
    if allocation_error != ok { ret ("", allocation_error) }
    copy_foreign(bytes, p, n)
    ret (bytes, ok)
}

// --- parameters

fn put_be(dst: []u8, value: u64, width: usize) {
    var i = 0usize
    while i < width {
        let shift = u64((width - 1usize - i) * 8usize)
        dst[i] = u8.trunc(value >> shift)
        i += 1usize
    }
}

fn get_be(src: []const u8, width: usize) -> u64 {
    var value = 0u64
    var i = 0usize
    while i < width {
        value = value << 8u64 | u64(src[i])
        i += 1usize
    }
    ret value
}

// A signed big-endian integer of `width` bytes.
fn get_be_signed(src: []const u8, width: usize) -> i64 {
    let raw = get_be(src, width)
    if width == 8usize { ret mem.bitcast[i64](raw) }
    let bits = u64(width * 8usize)
    let sign = 1u64 << (bits - 1u64)
    if raw & sign == 0u64 { ret i64(raw) }
    let magnitude = (1u64 << bits) - raw
    ret 0i64 - i64(magnitude)
}

fn binary(a: *mem.Arena, width: usize, value: u64, oid: u32) -> (Piece, err) {
    var piece: Piece = zero
    let (bytes, allocation_error) = mem.alloc[u8](a, width)
    if allocation_error != ok { ret (piece, allocation_error) }
    put_be(bytes, value, width)
    piece = Piece { bytes: bytes, address: mem.address_of(&bytes[0usize]), oid: oid, format: 1i32, null: false }
    ret (piece, ok)
}

// Text-format parameters are read up to a terminator, so the copy carries one.
fn textual(a: *mem.Arena, s: []const u8, oid: u32) -> (Piece, err) {
    var piece: Piece = zero
    let (bytes, allocation_error) = mem.alloc[u8](a, s.len + 1usize)
    if allocation_error != ok { ret (piece, allocation_error) }
    mem.copy[u8](bytes[0usize..s.len], s)
    bytes[s.len] = 0u8
    piece = Piece { bytes: bytes, address: mem.address_of(&bytes[0usize]), oid: oid, format: 0i32, null: false }
    ret (piece, ok)
}

// Raw bytes in binary format. An empty value still needs an address: a null one is SQL NULL.
fn raw_piece(a: *mem.Arena, s: []const u8, oid: u32) -> (Piece, err) {
    var piece: Piece = zero
    var size = s.len
    if size == 0usize { size = 1usize }
    let (bytes, allocation_error) = mem.alloc[u8](a, size)
    if allocation_error != ok { ret (piece, allocation_error) }
    mem.copy[u8](bytes[0usize..s.len], s)
    piece = Piece { bytes: bytes[0usize..s.len], address: mem.address_of(&bytes[0usize]), oid: oid, format: 1i32, null: false }
    ret (piece, ok)
}

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

// The shortest text that reads back as `v`, in PostgreSQL's spelling of the non-finite ones.
fn decimal_f64(a: *mem.Arena, v: f64) -> (str, err) {
    var (b, builder_error) = str.builder(a, 40usize)
    if builder_error != ok { ret ("", builder_error) }
    let push_error = str.push_f64(&b, v)
    if push_error != ok { ret ("", push_error) }
    let spelled = str.done(&b)
    if str.eq(spelled, "inf") { ret ("Infinity", ok) }
    if str.eq(spelled, "-inf") { ret ("-Infinity", ok) }
    if str.eq(spelled, "nan") { ret ("NaN", ok) }
    ret (spelled, ok)
}

fn is_integer_oid(oid: u32) -> bool { ret oid == OID_INT2 || oid == OID_INT4 || oid == OID_INT8 }

fn integer_width(oid: u32) -> usize {
    if oid == OID_INT2 { ret 2usize }
    if oid == OID_INT4 { ret 4usize }
    ret 8usize
}

// An integer into a binary integer parameter of the wanted's width, or `Unsupported` when it
// does not fit.
fn sized_integer(c: *Conn, a: *mem.Arena, v: i64, oid: u32) -> (Piece, err) {
    var piece: Piece = zero
    let width = integer_width(oid)
    if width == 2usize && (v < -32768i64 || v > 32767i64) { ret (piece, refuse(c, "an integer does not fit the parameter's smallint", db.Unsupported)) }
    if width == 4usize && (v < I32_MIN || v > I32_MAX) { ret (piece, refuse(c, "an integer does not fit the parameter's integer", db.Unsupported)) }
    let (encoded, encode_error) = binary(a, width, mem.bitcast[u64](v), oid)
    ret (encoded, encode_error)
}

fn micros_of(instant: time.Instant) -> i64 {
    ret time.floor_div(instant.nanos, 1000i64) - EPOCH_MICROS
}

// One parameter. `wanted` is the type the server settled for a prepared statement's
// parameter, or 0 for an unprepared one, where each kind takes its natural type -- `Text` goes
// as `unknown`, so the server reads it as whatever the context wants.
fn encode(c: *Conn, a: *mem.Arena, value: db.Value, wanted: u32) -> (Piece, err) {
    var piece: Piece = zero
    switch value {
    case .Null:
        piece.null = true
        piece.oid = wanted
        ret (piece, ok)
    case .Bool as flag:
        var bit = 0u64
        if flag { bit = 1u64 }
        if wanted == 0u32 || wanted == OID_BOOL {
            let (bool_piece, bool_error) = binary(a, 1usize, bit, OID_BOOL)
            ret (bool_piece, bool_error)
        }
        if is_integer_oid(wanted) {
            let (flag_piece, flag_error) = sized_integer(c, a, i64(bit), wanted)
            ret (flag_piece, flag_error)
        }
        var spelled_flag = "false"
        if flag { spelled_flag = "true" }
        let (flag_text, flag_text_error) = textual(a, spelled_flag, wanted)
        ret (flag_text, flag_text_error)
    case .I64 as signed:
        if wanted == 0u32 || is_integer_oid(wanted) {
            var width_oid = wanted
            if width_oid == 0u32 { width_oid = OID_INT8 }
            let (signed_piece, signed_error) = sized_integer(c, a, signed, width_oid)
            ret (signed_piece, signed_error)
        }
        let (signed_text, signed_text_error) = decimal_i64(a, signed)
        if signed_text_error != ok { ret (piece, signed_text_error) }
        let (signed_textual, signed_textual_error) = textual(a, signed_text, wanted)
        ret (signed_textual, signed_textual_error)
    case .U64 as unsigned:
        if unsigned <= u64(I64_MAX) && (wanted == 0u32 || is_integer_oid(wanted)) {
            var unsigned_oid = wanted
            if unsigned_oid == 0u32 { unsigned_oid = OID_INT8 }
            let (unsigned_piece, unsigned_error) = sized_integer(c, a, i64(unsigned), unsigned_oid)
            ret (unsigned_piece, unsigned_error)
        }
        if is_integer_oid(wanted) { ret (piece, refuse(c, "an unsigned value does not fit the parameter's integer", db.Unsupported)) }
        // Past `bigint`, the natural type is `numeric`, which holds it exactly.
        var unsigned_target = wanted
        if unsigned_target == 0u32 { unsigned_target = OID_NUMERIC }
        let (unsigned_text, unsigned_text_error) = decimal_u64(a, unsigned)
        if unsigned_text_error != ok { ret (piece, unsigned_text_error) }
        let (unsigned_textual, unsigned_textual_error) = textual(a, unsigned_text, unsigned_target)
        ret (unsigned_textual, unsigned_textual_error)
    case .F64 as real:
        if wanted == 0u32 || wanted == OID_FLOAT8 {
            let (real_piece, real_error) = binary(a, 8usize, mem.bitcast[u64](real), OID_FLOAT8)
            ret (real_piece, real_error)
        }
        let (real_text, real_text_error) = decimal_f64(a, real)
        if real_text_error != ok { ret (piece, real_text_error) }
        let (real_textual, real_textual_error) = textual(a, real_text, wanted)
        ret (real_textual, real_textual_error)
    case .Text as s:
        if wanted == OID_BYTEA {
            let (text_raw, text_raw_error) = raw_piece(a, s, OID_BYTEA)
            ret (text_raw, text_raw_error)
        }
        let (text_piece, text_error) = textual(a, s, wanted)
        ret (text_piece, text_error)
    case .Bytes as data:
        var bytes_oid = wanted
        if bytes_oid == 0u32 { bytes_oid = OID_BYTEA }
        let (bytes_piece, bytes_error) = raw_piece(a, data, bytes_oid)
        ret (bytes_piece, bytes_error)
    case .Time as instant:
        if wanted == 0u32 || wanted == OID_TIMESTAMPTZ || wanted == OID_TIMESTAMP {
            var time_oid = wanted
            if time_oid == 0u32 { time_oid = OID_TIMESTAMPTZ }
            let (time_piece, time_error) = binary(a, 8usize, mem.bitcast[u64](micros_of(instant)), time_oid)
            ret (time_piece, time_error)
        }
        if wanted == OID_DATE {
            let day = time.floor_div(instant.nanos, 86400000000000i64) - EPOCH_DAYS
            let (date_piece, date_error) = sized_integer(c, a, day, OID_INT4)
            if date_error != ok { ret (date_piece, date_error) }
            var date_typed = date_piece
            date_typed.oid = OID_DATE
            ret (date_typed, ok)
        }
        ret (piece, refuse(c, "a time value cannot be sent as the parameter's type", db.Unsupported))
    }
}

// The parameter arrays libpq takes, built in `a`. `targets` is empty for an unprepared
// statement, else one type per parameter.
fn encode_all(c: *Conn, a: *mem.Arena, params: []const db.Parameter, targets: []const u32) -> (Encoded, err) {
    var out: Encoded = zero
    let n = params.len
    if n == 0usize { ret (out, ok) }
    let (types, types_error) = mem.alloc[u32](a, n)
    let (values, values_error) = mem.alloc[usize](a, n)
    let (lengths, lengths_error) = mem.alloc[i32](a, n)
    let (formats, formats_error) = mem.alloc[i32](a, n)
    if types_error != ok || values_error != ok || lengths_error != ok || formats_error != ok { ret (out, db.Unsupported) }
    var i = 0usize
    while i < n {
        if params[i].name.len != 0usize { ret (out, refuse(c, "named parameters are not supported; write $1, $2, ...", db.InvalidQuery)) }
        var wanted = 0u32
        if targets.len != 0usize { wanted = targets[i] }
        let (piece, piece_error) = encode(c, a, params[i].value, wanted)
        if piece_error != ok { ret (out, piece_error) }
        types[i] = piece.oid
        formats[i] = piece.format
        if piece.null {
            values[i] = 0usize
            lengths[i] = 0i32
        } else {
            if piece.bytes.len > usize(I32_MAX) { ret (out, refuse(c, "a parameter is longer than libpq accepts", db.Unsupported)) }
            lengths[i] = i32(piece.bytes.len)
            values[i] = piece.address
        }
        i += 1usize
    }
    out = Encoded { types: types, values: values, lengths: lengths, formats: formats }
    ret (out, ok)
}

fn address_or_zero_u32(v: []u32) -> usize {
    if v.len == 0usize { ret 0usize }
    ret mem.address_of(&v[0usize])
}

fn address_or_zero_usize(v: []usize) -> usize {
    if v.len == 0usize { ret 0usize }
    ret mem.address_of(&v[0usize])
}

fn address_or_zero_i32(v: []i32) -> usize {
    if v.len == 0usize { ret 0usize }
    ret mem.address_of(&v[0usize])
}

// --- results

// The rows a command tag says it changed; only DML changes rows (`SELECT n` counts reads).
fn changed(result: usize) -> u64 {
    var tag: [16]u8 = zero
    let tag_len = keep_c(tag[0..], capi.cmd_status(result))
    let spelled = tag[0usize..tag_len]
    if !starts(spelled, "INSERT") && !starts(spelled, "UPDATE") && !starts(spelled, "DELETE") && !starts(spelled, "MERGE") { ret 0u64 }
    var digits: [24]u8 = zero
    let n = keep_c(digits[0..], capi.cmd_tuples(result))
    var count = 0u64
    var i = 0usize
    while i < n {
        count = count * 10u64 + u64(digits[i] - 48u8)
        i += 1usize
    }
    ret count
}

// Reads every result the last command produced, up to libpq's null, summing the rows DML
// changed and keeping the first failure. A COPY is ended from this side: IN is refused with a
// message the server reports back, OUT is read and discarded.
fn collect(c: *Conn) -> (u64, err) {
    var affected = 0u64
    var first_error = ok
    while true {
        let result = capi.get_result(c.handle)
        if result == 0usize { break }
        let status = capi.result_status(result)
        if status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK || status == PGRES_SINGLE_TUPLE || status == PGRES_EMPTY_QUERY {
            affected += changed(result)
        } else if status == PGRES_COPY_IN {
            var refusal: [48]u8 = zero
            let refusal_len = keep(refusal[0usize..47usize], "COPY FROM STDIN is not supported by this driver")
            refusal[refusal_len] = 0u8
            let ended = capi.put_copy_end(c.handle, &refusal[0usize])
        } else if status == PGRES_COPY_OUT || status == PGRES_COPY_BOTH {
            var chunk = 0usize
            while capi.get_copy_data(c.handle, &chunk, 0i32) >= 0i32 {
                if chunk != 0usize { capi.freemem(chunk) }
                chunk = 0usize
            }
        } else if first_error == ok {
            first_error = fail_result(c, result)
        }
        capi.clear(result)
    }
    // A caller that succeeds clears the detail itself: a drain after a recorded failure must
    // not wipe it.
    ret (affected, first_error)
}

fn execute_text(c: *Conn, sql: str, params: []const db.Parameter) -> (u64, err) {
    if c.active != nil { ret (0u64, refuse(c, "a row reader is still open on this connection", db.Busy)) }
    let mark = mem.mark(c.arena)
    let (command, command_error) = c_copy(c.arena, sql)
    if command_error != ok { ret (0u64, command_error) }
    var sent = 0i32
    if params.len == 0usize {
        // The simple protocol runs every statement in the text.
        sent = capi.send_query(c.handle, &command[0usize])
    } else {
        let no_targets: []const u32 = zero
        let (encoded, encode_error) = encode_all(c, c.arena, params, no_targets)
        if encode_error != ok {
            mem.reset(c.arena, mark)
            ret (0u64, encode_error)
        }
        sent = capi.send_query_params(c.handle, &command[0usize], i32(params.len), address_or_zero_u32(encoded.types), address_or_zero_usize(encoded.values), address_or_zero_i32(encoded.lengths), address_or_zero_i32(encoded.formats), 1i32)
    }
    mem.reset(c.arena, mark)
    if sent == 0i32 { ret (0u64, fail_connection(c)) }
    let (affected, collect_error) = collect(c)
    if collect_error == ok { clear_detail(c) }
    ret (affected, collect_error)
}

// --- row readers

fn kind_of(oid: u32) -> db.ValueKind {
    if oid == OID_BOOL { ret .Bool }
    if oid == OID_INT2 || oid == OID_INT4 || oid == OID_INT8 || oid == OID_OID { ret .I64 }
    if oid == OID_FLOAT4 || oid == OID_FLOAT8 { ret .F64 }
    if oid == OID_BYTEA { ret .Bytes }
    if oid == OID_DATE || oid == OID_TIMESTAMP || oid == OID_TIMESTAMPTZ { ret .Time }
    if is_text_oid(oid) || oid == OID_NUMERIC || oid == OID_UUID { ret .Text }
    ret .Bytes
}

fn is_text_oid(oid: u32) -> bool {
    ret oid == OID_TEXT || oid == OID_VARCHAR || oid == OID_BPCHAR || oid == OID_NAME || oid == OID_CHAR || oid == OID_JSON || oid == OID_JSONB || oid == OID_XML || oid == OID_UNKNOWN
}

// Waits for the first result so a failing query fails here, and takes the columns from it.
fn start_reader(c: *Conn, statement: *Stmt) -> (db.Rows, err) {
    var rows: db.Rows = zero
    if capi.set_single_row_mode(c.handle) == 0i32 {
        let (ignored, drained_error) = collect(c)
        ret (rows, refuse(c, "libpq would not stream this query", Failed))
    }
    let first = capi.get_result(c.handle)
    var result = 0usize
    var done = true
    var count = 0usize
    if first != 0usize {
        let status = capi.result_status(first)
        if status == PGRES_SINGLE_TUPLE || status == PGRES_TUPLES_OK || status == PGRES_COMMAND_OK {
            count = usize(capi.nfields(first))
            if status == PGRES_SINGLE_TUPLE {
                result = first
                done = false
            }
        } else {
            let failed = fail_result(c, first)
            capi.clear(first)
            let (rest, rest_error) = collect(c)
            ret (rows, failed)
        }
    }
    let (readers, reader_error) = mem.alloc[Reader](c.arena, 1usize)
    let (oids, oids_error) = mem.alloc[u32](c.arena, count)
    let (cols, cols_error) = mem.alloc[db.Column](c.arena, count)
    if reader_error != ok || oids_error != ok || cols_error != ok {
        if first != 0usize { capi.clear(first) }
        let (discarded, discarded_error) = collect(c)
        ret (rows, db.Unsupported)
    }
    var i = 0usize
    while i < count {
        oids[i] = capi.ftype(first, i32(i))
        let (name, name_error) = c_read(c.arena, capi.fname(first, i32(i)))
        if name_error != ok { ret (rows, name_error) }
        cols[i] = db.Column { name: name, kind: kind_of(oids[i]), nullable: true }
        i += 1usize
    }
    if done {
        if first != 0usize { capi.clear(first) }
        let (after, after_error) = collect(c)
        if after_error != ok { ret (rows, after_error) }
    }
    var no_buffer: []u8 = zero
    readers[0usize] = Reader { conn: c, statement: statement, result: result, done: done, closed: false, oids: oids, columns: cols, buffer: no_buffer, used: 0usize, borrow: false, held: 0usize }
    let r = &readers[0usize]
    if !done { c.active = r }
    clear_detail(c)
    rows.ctx = mem.cast[*void](r)
    ret (rows, ok)
}

fn start_query(c: *Conn, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    if c.active != nil { ret (zero, refuse(c, "a row reader is still open on this connection", db.Busy)) }
    let mark = mem.mark(c.arena)
    let (command, command_error) = c_copy(c.arena, sql)
    if command_error != ok { ret (zero, command_error) }
    let no_targets: []const u32 = zero
    let (encoded, encode_error) = encode_all(c, c.arena, params, no_targets)
    if encode_error != ok {
        mem.reset(c.arena, mark)
        ret (zero, encode_error)
    }
    // The extended protocol takes one statement, which is what a query is.
    let sent = capi.send_query_params(c.handle, &command[0usize], i32(params.len), address_or_zero_u32(encoded.types), address_or_zero_usize(encoded.values), address_or_zero_i32(encoded.lengths), address_or_zero_i32(encoded.formats), 1i32)
    mem.reset(c.arena, mark)
    if sent == 0i32 { ret (zero, fail_connection(c)) }
    let (rows, rows_error) = start_reader(c, nil)
    ret (rows, rows_error)
}

// Ends a reader that has not reached its end, reading and discarding what is left.
fn finish_reader(r: *Reader) {
    release_held(r)
    if r.done { ret }
    if r.result != 0usize { capi.clear(r.result) }
    r.result = 0usize
    r.done = true
    let (ignored, drained_error) = collect(r.conn)
    if r.conn.active == r { r.conn.active = nil }
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

fn take(r: *Reader, n: usize) -> ([]u8, err) {
    let reserve_error = reserve(r, n)
    if reserve_error != ok { ret (r.buffer[0usize..0usize], reserve_error) }
    let start = r.used
    r.used = start + n
    ret (r.buffer[start..start + n], ok)
}

fn put_text(r: *Reader, s: str) -> ([]u8, err) {
    let (out, take_error) = take(r, s.len)
    if take_error != ok { ret (out, take_error) }
    mem.copy[u8](out, s)
    ret (out, ok)
}

// `numeric`'s binary form: digit count, weight, sign and display scale, then base-10000
// digits, the first worth 10000^weight. Rendered exactly, to the scale it was stored with.
fn numeric_text(r: *Reader, v: []const u8) -> ([]u8, err) {
    if v.len < 8usize { ret (r.buffer[0usize..0usize], Failed) }
    let ndigits = usize(get_be(v, 2usize))
    let weight = get_be_signed(v[2usize..], 2usize)
    let sign = get_be(v[4usize..], 2usize)
    let dscale = usize(get_be(v[6usize..], 2usize))
    var special = ""
    if sign == 49152u64 { special = "NaN" }
    if sign == 53248u64 { special = "Infinity" }
    if sign == 61440u64 { special = "-Infinity" }
    if special.len != 0usize {
        let (spelled, spelled_error) = put_text(r, special)
        ret (spelled, spelled_error)
    }
    if v.len < 8usize + ndigits * 2usize { ret (r.buffer[0usize..0usize], Failed) }
    var int_groups = 0usize
    if weight >= 0i64 { int_groups = usize(weight) + 1usize }
    let (out, take_error) = take(r, 1usize + int_groups * 4usize + 1usize + 1usize + dscale + 4usize)
    if take_error != ok { ret (out, take_error) }
    var n = 0usize
    if sign == 16384u64 {
        out[n] = 45u8
        n += 1usize
    }
    if int_groups == 0usize {
        out[n] = 48u8
        n += 1usize
    }
    var g = 0usize
    while g < int_groups {
        var group = 0u64
        if g < ndigits { group = get_be(v[8usize + g * 2usize..], 2usize) }
        var place = 1000u64
        var leading = g == 0usize
        while place > 0u64 {
            let d = group / place % 10u64
            if !leading || d != 0u64 || place == 1u64 {
                out[n] = u8.trunc(48u64 + d)
                n += 1usize
                leading = false
            }
            place = place / 10u64
        }
        g += 1usize
    }
    if dscale > 0usize {
        out[n] = 46u8
        n += 1usize
        // Group k (from the first) is worth 10000^(weight - k); the fraction starts at the group
        // worth 10000^-1.
        var written = 0usize
        var k = weight + 1i64
        while written < dscale {
            var group = 0u64
            if k >= 0i64 && usize(k) < ndigits { group = get_be(v[8usize + usize(k) * 2usize..], 2usize) }
            var place = 1000u64
            while place > 0u64 && written < dscale {
                out[n] = u8.trunc(48u64 + group / place % 10u64)
                n += 1usize
                written += 1usize
                place = place / 10u64
            }
            k += 1i64
        }
    }
    r.used = r.used - (out.len - n)
    ret (out[0usize..n], ok)
}

fn uuid_text(r: *Reader, v: []const u8) -> ([]u8, err) {
    let (out, take_error) = take(r, 36usize)
    if take_error != ok { ret (out, take_error) }
    let hex = "0123456789abcdef"
    var n = 0usize
    var i = 0usize
    while i < 16usize && i < v.len {
        if i == 4usize || i == 6usize || i == 8usize || i == 10usize {
            out[n] = 45u8
            n += 1usize
        }
        out[n] = hex[usize(v[i] >> 4u8)]
        out[n + 1usize] = hex[usize(v[i] & 15u8)]
        n += 2usize
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// A microsecond count from PostgreSQL's epoch as an instant, or the text PostgreSQL itself
// writes when it is infinite or past what nanoseconds in an `i64` reach.
fn timestamp_value(r: *Reader, micros: i64) -> (db.Value, err) {
    var value: db.Value = .Null
    if micros == I64_MAX || micros == I64_MIN {
        var spelled_stamp = "infinity"
        if micros == I64_MIN { spelled_stamp = "-infinity" }
        let (infinite, infinite_error) = put_text(r, spelled_stamp)
        let infinite_text: str = infinite
        value = db.Value{ Text: infinite_text }
        ret (value, infinite_error)
    }
    let limit = I64_MAX / 1000i64 - EPOCH_MICROS
    if micros > limit || micros < 0i64 - limit - 2i64 * EPOCH_MICROS { ret (value, refuse(r.conn, "a timestamp lies outside what time.Instant holds", db.Unsupported)) }
    value = db.Value{ Time: time.Instant { nanos: (micros + EPOCH_MICROS) * 1000i64 } }
    ret (value, ok)
}

fn decode(r: *Reader, oid: u32, v: []const u8) -> (db.Value, err) {
    var value: db.Value = .Null
    if oid == OID_BOOL && v.len == 1usize {
        value = db.Value{ Bool: v[0usize] != 0u8 }
        ret (value, ok)
    }
    if (oid == OID_INT2 && v.len == 2usize) || (oid == OID_INT4 && v.len == 4usize) || (oid == OID_INT8 && v.len == 8usize) {
        value = db.Value{ I64: get_be_signed(v, v.len) }
        ret (value, ok)
    }
    if oid == OID_OID && v.len == 4usize {
        value = db.Value{ I64: i64(get_be(v, 4usize)) }
        ret (value, ok)
    }
    if oid == OID_FLOAT8 && v.len == 8usize {
        value = db.Value{ F64: mem.bitcast[f64](get_be(v, 8usize)) }
        ret (value, ok)
    }
    if oid == OID_FLOAT4 && v.len == 4usize {
        let single = mem.bitcast[f32](u32.trunc(get_be(v, 4usize)))
        value = db.Value{ F64: f64(single) }
        ret (value, ok)
    }
    if (oid == OID_TIMESTAMP || oid == OID_TIMESTAMPTZ) && v.len == 8usize {
        let (stamp, stamp_error) = timestamp_value(r, get_be_signed(v, 8usize))
        ret (stamp, stamp_error)
    }
    if oid == OID_DATE && v.len == 4usize {
        let day = get_be_signed(v, 4usize)
        if day == I32_MAX || day == I32_MIN {
            var spelled_day = "infinity"
            if day == I32_MIN { spelled_day = "-infinity" }
            let (infinite_day, infinite_day_error) = put_text(r, spelled_day)
            let infinite_day_text: str = infinite_day
            value = db.Value{ Text: infinite_day_text }
            ret (value, infinite_day_error)
        }
        value = db.Value{ Time: time.Instant { nanos: (day + EPOCH_DAYS) * 86400000000000i64 } }
        ret (value, ok)
    }
    if oid == OID_NUMERIC {
        let (number, number_error) = numeric_text(r, v)
        let number_text: str = number
        value = db.Value{ Text: number_text }
        ret (value, number_error)
    }
    if oid == OID_UUID && v.len == 16usize {
        let (id, id_error) = uuid_text(r, v)
        let id_text: str = id
        value = db.Value{ Text: id_text }
        ret (value, id_error)
    }
    var body = v
    // `jsonb`'s binary form is a version byte ahead of the text.
    if oid == OID_JSONB && v.len > 0usize { body = v[1usize..] }
    if r.borrow {
        if is_text_oid(oid) {
            let borrowed_text: str = body
            value = db.Value{ Text: borrowed_text }
        } else {
            value = db.Value{ Bytes: body }
        }
        ret (value, ok)
    }
    let (copied, copy_error) = take(r, body.len)
    if copy_error != ok { ret (value, copy_error) }
    mem.copy[u8](copied, body)
    if is_text_oid(oid) {
        let copied_text: str = copied
        value = db.Value{ Text: copied_text }
    } else {
        value = db.Value{ Bytes: copied }
    }
    ret (value, ok)
}

fn fill(r: *Reader, dst: []db.Value) -> err {
    r.used = 0usize
    let result = r.result
    // Each value is read in place: libpq's bytes live until the result is cleared, which is
    // after this row is filled, and `decode` copies what it keeps into the reader's buffer.
    var region: mem.Arena = zero
    var i = 0usize
    while i < r.columns.len {
        let column = i32(i)
        if capi.getisnull(result, 0i32, column) != 0i32 {
            dst[i] = .Null
        } else {
            let n = usize(capi.getlength(result, 0i32, column))
            region.base = capi.getvalue(result, 0i32, column)
            region.cap = n
            region.off = 0usize
            let (value, decode_error) = decode(r, r.oids[i], mem.view(&region, 0usize, n))
            if decode_error != ok { ret decode_error }
            dst[i] = value
        }
        i += 1usize
    }
    ret ok
}

// --- prepared statements

fn statement_name(c: *Conn) -> ([]u8, err) {
    c.statements += 1u64
    let (digits, digits_error) = decimal_u64(c.arena, c.statements)
    if digits_error != ok { ret (zero, digits_error) }
    let (spelled, spelled_error) = str.concat(c.arena, "np_x_postgresql_", digits)
    if spelled_error != ok { ret (zero, spelled_error) }
    let (name, name_error) = c_copy(c.arena, spelled)
    ret (name, name_error)
}

fn run_prepared(s: *Stmt, params: []const db.Parameter) -> err {
    let c = s.conn
    if s.closed { ret db.Closed }
    if c.active != nil { ret refuse(c, "a row reader is still open on this connection", db.Busy) }
    if params.len != s.oids.len { ret refuse(c, "the statement's parameter count differs from the parameters given", db.InvalidQuery) }
    let mark = mem.mark(c.arena)
    let (encoded, encode_error) = encode_all(c, c.arena, params, s.oids)
    if encode_error != ok {
        mem.reset(c.arena, mark)
        ret encode_error
    }
    let sent = capi.send_query_prepared(c.handle, &s.name[0usize], i32(params.len), address_or_zero_usize(encoded.values), address_or_zero_i32(encoded.lengths), address_or_zero_i32(encoded.formats), 1i32)
    mem.reset(c.arena, mark)
    if sent == 0i32 { ret fail_connection(c) }
    ret ok
}

// --- the driver table

fn d_close(ctx: *void) -> err {
    let c = conn_of(ctx)
    if c.active != nil { finish_reader(c.active) }
    capi.finish(c.handle)
    ret ok
}

// The server compiles the statement and settles each parameter's type; the types are kept so
// every later execution sends its values in them.
fn d_prepare(ctx: *void, sql: str) -> (db.Statement, err) {
    let c = conn_of(ctx)
    var statement: db.Statement = zero
    if c.active != nil { ret (statement, refuse(c, "a row reader is still open on this connection", db.Busy)) }
    let (name, name_error) = statement_name(c)
    if name_error != ok { ret (statement, name_error) }
    let mark = mem.mark(c.arena)
    let (command, command_error) = c_copy(c.arena, sql)
    if command_error != ok { ret (statement, command_error) }
    let sent = capi.send_prepare(c.handle, &name[0usize], &command[0usize], 0i32, 0usize)
    mem.reset(c.arena, mark)
    if sent == 0i32 { ret (statement, fail_connection(c)) }
    let (prepared, prepare_error) = collect(c)
    if prepare_error != ok { ret (statement, prepare_error) }
    if capi.send_describe_prepared(c.handle, &name[0usize]) == 0i32 { ret (statement, fail_connection(c)) }
    let described = capi.get_result(c.handle)
    if described == 0usize { ret (statement, fail_connection(c)) }
    if capi.result_status(described) != PGRES_COMMAND_OK {
        let describe_failed = fail_result(c, described)
        capi.clear(described)
        let (rest, rest_error) = collect(c)
        ret (statement, describe_failed)
    }
    let count = usize(capi.nparams(described))
    let (oids, oids_error) = mem.alloc[u32](c.arena, count)
    let (stmts, stmt_error) = mem.alloc[Stmt](c.arena, 1usize)
    if oids_error != ok || stmt_error != ok {
        capi.clear(described)
        let (dropped, dropped_error) = collect(c)
        ret (statement, db.Unsupported)
    }
    var i = 0usize
    while i < count {
        oids[i] = capi.paramtype(described, i32(i))
        i += 1usize
    }
    capi.clear(described)
    let (tail, tail_error) = collect(c)
    if tail_error != ok { ret (statement, tail_error) }
    stmts[0usize] = Stmt { conn: c, name: name, oids: oids, closed: false }
    statement.ctx = mem.cast[*void](&stmts[0usize])
    ret (statement, ok)
}

fn d_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = execute_text(conn_of(ctx), sql, params)
    ret (affected, execute_error)
}

fn d_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, rows_error) = start_query(conn_of(ctx), sql, params)
    ret (rows, rows_error)
}

// One transaction at a time: PostgreSQL warns and carries on at a nested BEGIN, which would
// hand out a second handle for the same transaction.
fn d_begin(ctx: *void) -> (db.Transaction, err) {
    let c = conn_of(ctx)
    var transaction: db.Transaction = zero
    if c.active != nil { ret (transaction, refuse(c, "a row reader is still open on this connection", db.Busy)) }
    if capi.transaction_status(c.handle) != PQTRANS_IDLE { ret (transaction, refuse(c, "a transaction is already open on this connection", db.Busy)) }
    let (txs, tx_error) = mem.alloc[Tx](c.arena, 1usize)
    if tx_error != ok { ret (transaction, tx_error) }
    let (ignored, begin_error) = execute_text(c, "BEGIN", zero)
    if begin_error != ok { ret (transaction, begin_error) }
    txs[0usize] = Tx { conn: c }
    transaction.ctx = mem.cast[*void](&txs[0usize])
    ret (transaction, ok)
}

// A reader of this statement still streaming is ended first, and answers `Closed` after.
fn d_statement_close(ctx: *void) -> err {
    let s = stmt_of(ctx)
    let c = s.conn
    if c.active != nil {
        if c.active.statement != s { ret refuse(c, "a row reader of another statement is still open", db.Busy) }
        c.active.closed = true
        finish_reader(c.active)
    }
    s.closed = true
    let mark = mem.mark(c.arena)
    let (spelled, spelled_error) = str.concat(c.arena, "DEALLOCATE ", s.name[0usize..s.name.len - 1usize])
    if spelled_error != ok {
        mem.reset(c.arena, mark)
        ret spelled_error
    }
    let (ignored, deallocate_error) = execute_text(c, spelled, zero)
    mem.reset(c.arena, mark)
    ret deallocate_error
}

fn d_statement_execute(ctx: *void, params: []const db.Parameter) -> (u64, err) {
    let s = stmt_of(ctx)
    let run_error = run_prepared(s, params)
    if run_error != ok { ret (0u64, run_error) }
    let (affected, collect_error) = collect(s.conn)
    if collect_error == ok { clear_detail(s.conn) }
    ret (affected, collect_error)
}

fn d_statement_query(ctx: *void, params: []const db.Parameter) -> (db.Rows, err) {
    let s = stmt_of(ctx)
    let run_error = run_prepared(s, params)
    if run_error != ok { ret (zero, run_error) }
    let (rows, rows_error) = start_reader(s.conn, s)
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

fn release_held(r: *Reader) {
    if r.held != 0usize { capi.clear(r.held) }
    r.held = 0usize
}

fn next_row(r: *Reader, dst: []db.Value) -> (bool, err) {
    release_held(r)
    if r.closed { ret (false, db.Closed) }
    if r.done { ret (false, ok) }
    if dst.len < r.columns.len { ret (false, refuse(r.conn, "the row buffer is shorter than the row", db.InvalidQuery)) }
    if r.result == 0usize {
        let next = capi.get_result(r.conn.handle)
        if next == 0usize {
            r.done = true
            r.conn.active = nil
            ret (false, ok)
        }
        let status = capi.result_status(next)
        if status == PGRES_SINGLE_TUPLE {
            r.result = next
        } else if status == PGRES_TUPLES_OK {
            capi.clear(next)
            finish_reader(r)
            ret (false, ok)
        } else {
            let failed = fail_result(r.conn, next)
            capi.clear(next)
            finish_reader(r)
            ret (false, failed)
        }
    }
    let fill_error = fill(r, dst)
    // A borrowed row's values point into its result, so it is kept until the next row.
    if r.borrow && fill_error == ok {
        r.held = r.result
    } else {
        capi.clear(r.result)
    }
    r.result = 0usize
    if fill_error != ok { ret (false, fill_error) }
    ret (true, ok)
}

fn d_rows_close(ctx: *void) -> err {
    let r = reader_of(ctx)
    finish_reader(r)
    ret ok
}

fn d_transaction_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = execute_text(tx_of(ctx).conn, sql, params)
    ret (affected, execute_error)
}

fn d_transaction_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, rows_error) = start_query(tx_of(ctx).conn, sql, params)
    ret (rows, rows_error)
}

// A transaction a statement failed in cannot commit: PostgreSQL answers COMMIT with a
// rollback and no error, so that is caught here and reported as `Aborted`. A COMMIT that
// fails outright is rolled back, because `e.db` has already closed the handle.
fn d_transaction_commit(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    if c.active != nil { finish_reader(c.active) }
    if capi.transaction_status(c.handle) == PQTRANS_INERROR {
        let (undone, undo_error) = execute_text(c, "ROLLBACK", zero)
        ret refuse(c, "a statement failed in the transaction, so it was rolled back", Aborted)
    }
    let (ignored, commit_error) = execute_text(c, "COMMIT", zero)
    if commit_error != ok && capi.transaction_status(c.handle) != PQTRANS_IDLE {
        let (rolled, rolled_error) = execute_text(c, "ROLLBACK", zero)
    }
    ret commit_error
}

fn d_transaction_rollback(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    if c.active != nil { finish_reader(c.active) }
    if capi.transaction_status(c.handle) == PQTRANS_IDLE { ret ok }
    let (ignored, rollback_error) = execute_text(c, "ROLLBACK", zero)
    ret rollback_error
}
