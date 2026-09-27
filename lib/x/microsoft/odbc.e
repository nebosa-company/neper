// An `e.db` driver over ODBC 3, through the host's driver manager: `odbc32.dll` on Windows,
// unixODBC on Linux. `open` takes an ODBC connection string and answers a `db.Connection` whose
// table is this module's; everything after that goes through `e.db`. `detail` is the only
// other call a program makes here.
//
// Memory: the arena handed to `open` is retained and borrowed for the connection's life.
// Every statement, row reader and transaction context comes from it. Text crosses as UTF-16
// through the wide entry points, and a reader's text and binary values are copied into a buffer
// of the reader's that is valid until its next row -- ODBC has no borrowed form, so
// `db.reader_next_borrowed` answers the same copies. Parameter buffers are allocated and reset
// around each execution.
//
// Values: a parameter binds as its natural ODBC type -- `Bool` as `SQL_BIT`, `I64`/`U64` as
// `SQL_BIGINT`, `F64` as `SQL_DOUBLE`, `Text` as `SQL_WVARCHAR`, `Bytes` as `SQL_VARBINARY`,
// `Time` as `SQL_TYPE_TIMESTAMP` in UTC -- and the driver converts it to the column's type. A
// column's kind is its ODBC type: `SQL_BIT` is `Bool`, the integers are `I64`, `REAL`, `FLOAT`
// and `DOUBLE` are `F64`, binary types are `Bytes`, `DATE` and `TIMESTAMP` are `Time` read as
// UTC, and everything else, `DECIMAL`, `NUMERIC` and `TIME` included, is `Text`.
//
// Parameters: `?`, positional; a named one is refused. Every statement is prepared, and must
// take exactly as many parameters as it is given, numbered across the whole text.
use e.mem
use e.time
use e.db
use e.text.utf8
use e.bytes as octets
use x.microsoft.capi

type Detail = struct { native: i32, sqlstate: str, message: str }
error CannotConnect
error Failed

type Conn = struct { env: usize, dbc: usize, arena: *mem.Arena, driver: *const db.Driver, in_transaction: bool, note: str, native: i32, state: []u8, state_len: usize, message: []u8, message_len: usize, wide: []u16 }
type Stmt = struct { conn: *Conn, handle: usize, params: usize, closed: bool }
type Reader = struct { conn: *Conn, handle: usize, statement: *Stmt, owned: bool, done: bool, columns: []db.Column, buffer: []u8, used: usize, scratch: []u8 }
type Tx = struct { conn: *Conn }
// What one parameter's value points at while its statement executes.
type Slot = struct { length: i64, integer: i64, unsigned: u64, real: f64, flag: u8, stamp: [16]u8 }

const SQL_SUCCESS: i16 = 0i16
const SQL_SUCCESS_WITH_INFO: i16 = 1i16
const SQL_NO_DATA: i16 = 100i16
const SQL_HANDLE_ENV: i16 = 1i16
const SQL_HANDLE_DBC: i16 = 2i16
const SQL_HANDLE_STMT: i16 = 3i16
const SQL_ATTR_ODBC_VERSION: i32 = 200i32
const SQL_OV_ODBC3: usize = 3usize
const SQL_ATTR_AUTOCOMMIT: i32 = 102i32
const SQL_AUTOCOMMIT_OFF: usize = 0usize
const SQL_AUTOCOMMIT_ON: usize = 1usize
const SQL_COMMIT: i16 = 0i16
const SQL_ROLLBACK: i16 = 1i16
const SQL_DRIVER_NOPROMPT: u16 = 0u16
const SQL_CLOSE: u16 = 0u16
const SQL_RESET_PARAMS: u16 = 3u16
const SQL_PARAM_INPUT: i16 = 1i16
const SQL_NULL_DATA: i64 = -1i64
const SQL_NO_TOTAL: i64 = -4i64
const SQL_NO_NULLS: i16 = 0i16

const SQL_C_CHAR: i16 = 1i16
const SQL_C_WCHAR: i16 = -8i16
const SQL_C_BIT: i16 = -7i16
const SQL_C_SBIGINT: i16 = -25i16
const SQL_C_UBIGINT: i16 = -27i16
const SQL_C_DOUBLE: i16 = 8i16
const SQL_C_BINARY: i16 = -2i16
const SQL_C_TYPE_TIMESTAMP: i16 = 93i16

const SQL_CHAR: i16 = 1i16
const SQL_INTEGER: i16 = 4i16
const SQL_SMALLINT: i16 = 5i16
const SQL_FLOAT: i16 = 6i16
const SQL_REAL: i16 = 7i16
const SQL_DOUBLE: i16 = 8i16
const SQL_VARCHAR: i16 = 12i16
const SQL_TYPE_DATE: i16 = 91i16
const SQL_TYPE_TIMESTAMP: i16 = 93i16
const SQL_BINARY: i16 = -2i16
const SQL_VARBINARY: i16 = -3i16
const SQL_LONGVARBINARY: i16 = -4i16
const SQL_BIGINT: i16 = -5i16
const SQL_TINYINT: i16 = -6i16
const SQL_BIT: i16 = -7i16
const SQL_WVARCHAR: i16 = -9i16

const I16_MAX: usize = 32767usize
const I32_MAX: usize = 2147483647usize
const NANOS_PER_DAY: i64 = 86400000000000i64
const NANOS_PER_SECOND: i64 = 1000000000i64
// SQL_MAX_MESSAGE_LENGTH is 512 units; each is at most three UTF-8 bytes.
const WIDE_CAP: usize = 512usize
const MESSAGE_CAP: usize = 1536usize
const STATE_CAP: usize = 8usize
// The first read of a long value, before its length is known.
const FIRST_READ: usize = 256usize

// Connects with `SQLDriverConnectW` and no prompt. A failure is `CannotConnect`; the driver
// manager's reason is not kept, since no connection exists to ask.
fn open(a: *mem.Arena, connection_string: str) -> (db.Connection, err) {
    var connection: db.Connection = zero
    var env = 0usize
    if !succeeded(capi.alloc_handle(SQL_HANDLE_ENV, 0usize, &env)) { ret (connection, CannotConnect) }
    // ODBC 3 behaviour: five-character SQLSTATEs, SQL_NO_DATA, and the TYPE_ date codes.
    if !succeeded(capi.set_env_attr(env, SQL_ATTR_ODBC_VERSION, SQL_OV_ODBC3, 0i32)) {
        let freed_version = capi.free_handle(SQL_HANDLE_ENV, env)
        ret (connection, db.Unsupported)
    }
    var dbc = 0usize
    if !succeeded(capi.alloc_handle(SQL_HANDLE_DBC, env, &dbc)) {
        let freed_env = capi.free_handle(SQL_HANDLE_ENV, env)
        ret (connection, CannotConnect)
    }
    let mark = mem.mark(a)
    let (text, text_len, text_error) = wide(a, connection_string)
    if text_error != ok || text_len > I16_MAX {
        mem.reset(a, mark)
        release_connection(env, dbc, false)
        ret (connection, db.Unsupported)
    }
    var sink: [4]u16 = zero
    var sink_len = 0i16
    let rc = capi.driver_connect(dbc, 0usize, &text[0usize], i16(text_len), &sink[0usize], 4i16, &sink_len, SQL_DRIVER_NOPROMPT)
    mem.reset(a, mark)
    if !succeeded(rc) {
        release_connection(env, dbc, false)
        ret (connection, CannotConnect)
    }
    let (conns, conn_error) = mem.alloc[Conn](a, 1usize)
    let (drivers, driver_error) = mem.alloc[db.Driver](a, 1usize)
    let (text_buffers, text_buffers_error) = mem.alloc[u8](a, STATE_CAP + MESSAGE_CAP)
    let (wide_buffer, wide_error) = mem.alloc[u16](a, WIDE_CAP)
    if conn_error != ok || driver_error != ok || text_buffers_error != ok || wide_error != ok {
        release_connection(env, dbc, true)
        ret (connection, mem.Exhausted)
    }
    drivers[0usize] = db.Driver { close: d_close, prepare: d_prepare, execute: d_execute, query: d_query, begin: d_begin, statement_close: d_statement_close, statement_execute: d_statement_execute, statement_query: d_statement_query, rows_columns: d_rows_columns, rows_next: d_rows_next, rows_next_borrowed: d_rows_next, rows_close: d_rows_close, transaction_execute: d_transaction_execute, transaction_query: d_transaction_query, transaction_commit: d_transaction_commit, transaction_rollback: d_transaction_rollback }
    // Arena memory is not cleared, so every field is written.
    conns[0usize] = Conn { env: env, dbc: dbc, arena: a, driver: &drivers[0usize], in_transaction: false, note: "", native: 0i32, state: text_buffers[0usize..STATE_CAP], state_len: 0usize, message: text_buffers[STATE_CAP..], message_len: 0usize, wide: wide_buffer }
    let c = &conns[0usize]
    connection.ctx = mem.cast[*void](c)
    connection.driver = c.driver
    ret (connection, ok)
}

// Why the connection's last call failed: the first diagnostic record's SQLSTATE, native error
// and message, or -- when the driver refused before ODBC was asked -- an empty state, native 0
// and the driver's reason. After a success all three are empty. The text is copied into `a`.
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err) {
    var out: Detail = zero
    if connection.ctx == nil { ret (out, db.Closed) }
    let c = conn_of(connection.ctx)
    if c.note.len != 0usize {
        out.message = c.note
        ret (out, ok)
    }
    out.native = c.native
    let (state, state_error) = keep(a, c.state[0usize..c.state_len])
    if state_error != ok { ret (out, state_error) }
    out.sqlstate = state
    let (message, message_error) = keep(a, c.message[0usize..c.message_len])
    out.message = message
    ret (out, message_error)
}

fn conn_of(ctx: *void) -> *Conn { ret mem.cast[*Conn](ctx) }
fn stmt_of(ctx: *void) -> *Stmt { ret mem.cast[*Stmt](ctx) }
fn reader_of(ctx: *void) -> *Reader { ret mem.cast[*Reader](ctx) }
fn tx_of(ctx: *void) -> *Tx { ret mem.cast[*Tx](ctx) }

fn succeeded(rc: i16) -> bool { ret rc == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO }

fn release_connection(env: usize, dbc: usize, connected: bool) {
    if connected { let disconnected = capi.disconnect(dbc) }
    let freed_dbc = capi.free_handle(SQL_HANDLE_DBC, dbc)
    let freed_env = capi.free_handle(SQL_HANDLE_ENV, env)
}

// --- errors

fn clear(c: *Conn) {
    c.note = ""
    c.native = 0i32
    c.state_len = 0usize
    c.message_len = 0usize
}

fn refuse(c: *Conn, note: str, e: err) -> err {
    clear(c)
    c.note = note
    ret e
}

// Keeps the handle's first diagnostic record and maps its SQLSTATE. It must be asked before
// anything else is called on the handle, which would clear the record.
fn failure(c: *Conn, kind: i16, handle: usize) -> err {
    clear(c)
    var state: [6]u16 = zero
    var native = 0i32
    var length = 0i16
    let rc = capi.get_diag_rec(kind, handle, 1i16, &state[0usize], &native, &c.wide[0usize], i16(c.wide.len), &length)
    if !succeeded(rc) { ret Failed }
    c.native = native
    var i = 0usize
    while i < 5usize {
        c.state[i] = u8(state[i] & 127u16)
        i += 1usize
    }
    c.state_len = 5usize
    var units = 0usize
    if length > 0i16 { units = usize(length) }
    if units >= c.wide.len { units = c.wide.len - 1usize }
    if units != 0usize {
        let (written, decode_error) = narrow(bytes_of(c.wide[0usize..units]), c.message)
        c.message_len = written
    }
    ret classify(c.state[0usize..5usize])
}

// SQLSTATE onto `e.db`: class 23 is a constraint; class 40, a timeout and PostgreSQL's
// `lock_not_available` (55P03, which psqlODBC passes through) are `Busy`; syntax, access,
// data, count and catalog classes are `InvalidQuery`; anything else is `Failed`.
fn classify(state: []const u8) -> err {
    if state.len != 5usize { ret Failed }
    if in_class(state, "23") { ret db.Constraint }
    if in_class(state, "40") || same(state, "HYT00") || same(state, "HYT01") || same(state, "55P03") { ret db.Busy }
    if in_class(state, "42") || in_class(state, "22") || in_class(state, "07") || in_class(state, "21") || in_class(state, "3D") || same(state, "37000") { ret db.InvalidQuery }
    ret Failed
}

fn in_class(state: []const u8, class: str) -> bool { ret state[0usize] == class[0usize] && state[1usize] == class[1usize] }

fn same(x: []const u8, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// --- text

fn keep(a: *mem.Arena, bytes: []const u8) -> (str, err) {
    if bytes.len == 0usize { ret ("", ok) }
    let (copy, allocation_error) = mem.alloc[u8](a, bytes.len)
    if allocation_error != ok { ret ("", allocation_error) }
    let copied = octets.copy(copy, bytes)
    ret (copy, ok)
}

// The bytes under a run of UTF-16 units.
fn bytes_of(units: []u16) -> []u8 {
    var region: mem.Arena = zero
    region.base = mem.cast[*u8](&units[0usize])
    region.cap = units.len * 2usize
    region.off = 0usize
    ret mem.view(&region, 0usize, units.len * 2usize)
}

// `s` as UTF-16 units in `a`, and how many there are. A zero unit follows them inside the
// slice, so even empty text has an address to hand over. A UTF-8 string never has more units
// than bytes.
fn wide(a: *mem.Arena, s: str) -> ([]u16, usize, err) {
    let (units, allocation_error) = mem.alloc[u16](a, s.len + 1usize)
    if allocation_error != ok { ret (units, 0usize, allocation_error) }
    let (written, encode_error) = utf8.encode_utf16(s, false, bytes_of(units))
    if encode_error != ok { ret (units, 0usize, encode_error) }
    let n = written / 2usize
    units[n] = 0u16
    ret (units[0usize..n + 1usize], n, ok)
}

// UTF-16LE bytes as UTF-8 in `out`, which needs three bytes for every two. A leading U+FEFF
// is text here, not a byte-order mark, so `utf8.decode_utf16` is not used. An unpaired
// surrogate is `utf8.Invalid`.
fn narrow(src: []const u8, out: []u8) -> (usize, err) {
    var at = 0usize
    var used = 0usize
    while at + 1usize < src.len {
        var scalar = u32(src[at]) | (u32(src[at + 1usize]) << 8u32)
        at += 2usize
        if scalar >= 55296u32 && scalar <= 57343u32 {
            if scalar > 56319u32 || at + 1usize >= src.len { ret (used, utf8.Invalid) }
            let low = u32(src[at]) | (u32(src[at + 1usize]) << 8u32)
            if low < 56320u32 || low > 57343u32 { ret (used, utf8.Invalid) }
            at += 2usize
            scalar = 65536u32 + ((scalar - 55296u32) << 10u32) + (low - 56320u32)
        }
        let (width, width_error) = utf8.encode(scalar, out[used..])
        if width_error != ok { ret (used, width_error) }
        used += usize(width)
    }
    ret (used, ok)
}

// --- timestamps

// An instant as ODBC's TIMESTAMP_STRUCT in UTC: year, month, day, hour, minute and second as
// 16-bit fields, then the fraction in nanoseconds as 32 bits. Every `i64` instant falls in
// years 1677 to 2262, so every one fits.
fn put_stamp(instant: time.Instant, stamp: []u8) {
    let day = time.floor_div(instant.nanos, NANOS_PER_DAY)
    let within = instant.nanos - day * NANOS_PER_DAY
    let (year, month, date) = time.civil_from_days(day)
    let second = within / NANOS_PER_SECOND
    put16(stamp, 0usize, u64(year))
    put16(stamp, 2usize, u64(month))
    put16(stamp, 4usize, u64(date))
    put16(stamp, 6usize, u64(second / 3600i64))
    put16(stamp, 8usize, u64((second / 60i64) % 60i64))
    put16(stamp, 10usize, u64(second % 60i64))
    let fraction = u64(within % NANOS_PER_SECOND)
    put16(stamp, 12usize, fraction & 65535u64)
    put16(stamp, 14usize, fraction >> 16u64)
}

fn put16(stamp: []u8, at: usize, value: u64) {
    stamp[at] = u8(value & 255u64)
    stamp[at + 1usize] = u8((value >> 8u64) & 255u64)
}

fn get16(stamp: []const u8, at: usize) -> i64 { ret i64(u32(stamp[at]) | (u32(stamp[at + 1usize]) << 8u32)) }

// A TIMESTAMP_STRUCT read as UTC nanoseconds; `false` when its fields name no instant.
fn read_stamp(stamp: []const u8) -> (i64, bool) {
    var year = get16(stamp, 0usize)
    if year >= 32768i64 { year -= 65536i64 }
    let month = get16(stamp, 2usize)
    let day = get16(stamp, 4usize)
    let hour = get16(stamp, 6usize)
    let minute = get16(stamp, 8usize)
    let second = get16(stamp, 10usize)
    let fraction = get16(stamp, 12usize) + get16(stamp, 14usize) * 65536i64
    if month < 1i64 || month > 12i64 || day < 1i64 || day > time.days_in_month(year, month) { ret (0i64, false) }
    if hour > 23i64 || minute > 59i64 || second > 60i64 || fraction >= NANOS_PER_SECOND { ret (0i64, false) }
    // Outside what an `i64` of nanoseconds reaches.
    if year < 1678i64 || year > 2261i64 { ret (0i64, false) }
    let seconds = time.days_from_civil(year, month, day) * 86400i64 + hour * 3600i64 + minute * 60i64 + second
    ret (seconds * NANOS_PER_SECOND + fraction, true)
}

// --- statements

fn new_statement(c: *Conn) -> (usize, err) {
    var handle = 0usize
    if !succeeded(capi.alloc_handle(SQL_HANDLE_STMT, c.dbc, &handle)) { ret (0usize, failure(c, SQL_HANDLE_DBC, c.dbc)) }
    ret (handle, ok)
}

fn free_statement(handle: usize) { let freed = capi.free_handle(SQL_HANDLE_STMT, handle) }

// Prepares `sql` on `handle` and answers how many parameters it takes.
fn compile(c: *Conn, handle: usize, sql: str) -> (usize, err) {
    if sql.len >= I32_MAX { ret (0usize, refuse(c, "the SQL text is longer than ODBC accepts", db.Unsupported)) }
    let mark = mem.mark(c.arena)
    let (text, text_len, text_error) = wide(c.arena, sql)
    if text_error != ok {
        mem.reset(c.arena, mark)
        if text_error == utf8.Invalid { ret (0usize, refuse(c, "the SQL text is not UTF-8", db.InvalidQuery)) }
        ret (0usize, text_error)
    }
    let rc = capi.prepare(handle, &text[0usize], i32(text_len))
    mem.reset(c.arena, mark)
    if !succeeded(rc) { ret (0usize, failure(c, SQL_HANDLE_STMT, handle)) }
    var declared = 0i16
    if !succeeded(capi.num_params(handle, &declared)) { ret (0usize, failure(c, SQL_HANDLE_STMT, handle)) }
    ret (usize(declared), ok)
}

// Binds `params` and executes the prepared statement, leaving its first result open. The
// parameter buffers live only until `SQLExecute` returns, since every one is input.
fn launch(c: *Conn, handle: usize, declared: usize, params: []const db.Parameter) -> err {
    if declared != params.len { ret refuse(c, "the statement's parameter count differs from the parameters given", db.InvalidQuery) }
    let mark = mem.mark(c.arena)
    let bind_error = bind_all(c, handle, params)
    if bind_error != ok {
        let unbound = capi.free_stmt(handle, SQL_RESET_PARAMS)
        mem.reset(c.arena, mark)
        ret bind_error
    }
    let rc = capi.execute(handle)
    // SQL_NO_DATA: a searched UPDATE or DELETE that matched no row.
    var run_error = ok
    if rc != SQL_NO_DATA && !succeeded(rc) { run_error = failure(c, SQL_HANDLE_STMT, handle) }
    let reset_params = capi.free_stmt(handle, SQL_RESET_PARAMS)
    mem.reset(c.arena, mark)
    if run_error == ok { clear(c) }
    ret run_error
}

fn bind_all(c: *Conn, handle: usize, params: []const db.Parameter) -> err {
    if params.len == 0usize { ret ok }
    let (slots, slots_error) = mem.alloc[Slot](c.arena, params.len)
    if slots_error != ok { ret slots_error }
    var i = 0usize
    while i < params.len {
        if params[i].name.len != 0usize { ret refuse(c, "ODBC parameters are positional (`?`); a named one is refused", db.InvalidQuery) }
        let bind_error = bind_value(c, handle, u16(i + 1usize), params[i].value, &slots[i])
        if bind_error != ok { ret bind_error }
        i += 1usize
    }
    ret ok
}

fn bind_value(c: *Conn, handle: usize, number: u16, value: db.Value, slot: *Slot) -> err {
    slot.length = 0i64
    var c_type = SQL_C_CHAR
    var sql_type = SQL_VARCHAR
    var size = 1usize
    var digits = 0i16
    var cap = 0i64
    var data = mem.cast[*const void](&slot.flag)
    switch value {
    case .Null:
        slot.length = SQL_NULL_DATA
    case .Bool as truth:
        slot.flag = 0u8
        if truth { slot.flag = 1u8 }
        c_type = SQL_C_BIT
        sql_type = SQL_BIT
        cap = 1i64
    case .I64 as signed:
        slot.integer = signed
        data = mem.cast[*const void](&slot.integer)
        c_type = SQL_C_SBIGINT
        sql_type = SQL_BIGINT
        size = 19usize
        cap = 8i64
    case .U64 as unsigned:
        slot.unsigned = unsigned
        data = mem.cast[*const void](&slot.unsigned)
        c_type = SQL_C_UBIGINT
        sql_type = SQL_BIGINT
        size = 20usize
        cap = 8i64
    case .F64 as real:
        slot.real = real
        data = mem.cast[*const void](&slot.real)
        c_type = SQL_C_DOUBLE
        sql_type = SQL_DOUBLE
        size = 15usize
        cap = 8i64
    case .Text as s:
        let (units, count, text_error) = wide(c.arena, s)
        if text_error == utf8.Invalid { ret refuse(c, "a text value is not UTF-8", db.InvalidQuery) }
        if text_error != ok { ret text_error }
        data = mem.cast[*const void](&units[0usize])
        c_type = SQL_C_WCHAR
        sql_type = SQL_WVARCHAR
        if count > size { size = count }
        cap = i64(count * 2usize)
        slot.length = cap
    case .Bytes as bytes:
        if bytes.len != 0usize { data = mem.cast[*const void](&bytes[0usize]) }
        c_type = SQL_C_BINARY
        sql_type = SQL_VARBINARY
        if bytes.len > size { size = bytes.len }
        cap = i64(bytes.len)
        slot.length = cap
    case .Time as instant:
        put_stamp(instant, slot.stamp[0usize..16usize])
        data = mem.cast[*const void](&slot.stamp[0usize])
        c_type = SQL_C_TYPE_TIMESTAMP
        sql_type = SQL_TYPE_TIMESTAMP
        size = 29usize
        digits = 9i16
        cap = 16i64
    }
    let rc = capi.bind_parameter(handle, number, SQL_PARAM_INPUT, c_type, sql_type, size, digits, data, cap, &slot.length)
    if !succeeded(rc) { ret failure(c, SQL_HANDLE_STMT, handle) }
    ret ok
}

// Sums the rows each statement of the text changed, reading past every result set. A
// statement that returns rows is not counted.
fn count_results(c: *Conn, handle: usize) -> (u64, err) {
    var affected = 0u64
    while true {
        var columns = 0i16
        if succeeded(capi.num_result_cols(handle, &columns)) && columns == 0i16 {
            var changed = 0i64
            if succeeded(capi.row_count(handle, &changed)) && changed > 0i64 { affected += u64(changed) }
        }
        let rc = capi.more_results(handle)
        if rc == SQL_NO_DATA { break }
        if !succeeded(rc) { ret (affected, failure(c, SQL_HANDLE_STMT, handle)) }
    }
    clear(c)
    ret (affected, ok)
}

fn execute_text(c: *Conn, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (handle, handle_error) = new_statement(c)
    if handle_error != ok { ret (0u64, handle_error) }
    let (declared, compile_error) = compile(c, handle, sql)
    if compile_error != ok {
        free_statement(handle)
        ret (0u64, compile_error)
    }
    let launch_error = launch(c, handle, declared, params)
    if launch_error != ok {
        free_statement(handle)
        ret (0u64, launch_error)
    }
    let (affected, count_error) = count_results(c, handle)
    free_statement(handle)
    ret (affected, count_error)
}

// --- row readers

fn kind_of(sql_type: i16) -> db.ValueKind {
    if sql_type == SQL_BIT { ret .Bool }
    if sql_type == SQL_TINYINT || sql_type == SQL_SMALLINT || sql_type == SQL_INTEGER || sql_type == SQL_BIGINT { ret .I64 }
    if sql_type == SQL_REAL || sql_type == SQL_FLOAT || sql_type == SQL_DOUBLE { ret .F64 }
    if sql_type == SQL_BINARY || sql_type == SQL_VARBINARY || sql_type == SQL_LONGVARBINARY { ret .Bytes }
    if sql_type == SQL_TYPE_DATE || sql_type == SQL_TYPE_TIMESTAMP { ret .Time }
    ret .Text
}

fn reader(c: *Conn, handle: usize, statement: *Stmt, owned: bool) -> (db.Rows, err) {
    var rows: db.Rows = zero
    var count = 0i16
    if !succeeded(capi.num_result_cols(handle, &count)) {
        let columns_error = failure(c, SQL_HANDLE_STMT, handle)
        if owned { free_statement(handle) }
        ret (rows, columns_error)
    }
    let n = usize(count)
    let (readers, reader_error) = mem.alloc[Reader](c.arena, 1usize)
    let (cols, cols_error) = mem.alloc[db.Column](c.arena, n)
    if reader_error != ok || cols_error != ok {
        if owned { free_statement(handle) }
        ret (rows, mem.Exhausted)
    }
    var no_bytes: []u8 = zero
    readers[0usize] = Reader { conn: c, handle: handle, statement: statement, owned: owned, done: n == 0usize, columns: cols, buffer: no_bytes, used: 0usize, scratch: no_bytes }
    let r = &readers[0usize]
    var i = 0usize
    while i < n {
        var name_len = 0i16
        var sql_type = 0i16
        var size = 0usize
        var digits = 0i16
        var nullable = 0i16
        let rc = capi.describe_col(handle, u16(i + 1usize), &c.wide[0usize], i16(c.wide.len), &name_len, &sql_type, &size, &digits, &nullable)
        if !succeeded(rc) {
            let describe_error = failure(c, SQL_HANDLE_STMT, handle)
            if owned { free_statement(handle) }
            ret (rows, describe_error)
        }
        var units = 0usize
        if name_len > 0i16 { units = usize(name_len) }
        if units >= c.wide.len { units = c.wide.len - 1usize }
        var name = ""
        if units != 0usize {
            let (spelled, spelled_error) = mem.alloc[u8](c.arena, units * 3usize)
            if spelled_error != ok {
                if owned { free_statement(handle) }
                ret (rows, spelled_error)
            }
            let (written, name_error) = narrow(bytes_of(c.wide[0usize..units]), spelled)
            name = spelled[0usize..written]
        }
        cols[i] = db.Column { name: name, kind: kind_of(sql_type), nullable: nullable != SQL_NO_NULLS }
        i += 1usize
    }
    clear(c)
    rows.ctx = mem.cast[*void](r)
    ret (rows, ok)
}

// A buffer of at least `n` bytes that keeps the first `kept` of `old`.
fn grown(a: *mem.Arena, old: []u8, kept: usize, n: usize) -> ([]u8, err) {
    var size = old.len * 2usize
    if size < n { size = n }
    let (bytes, grow_error) = mem.alloc[u8](a, size)
    if grow_error != ok { ret (old, grow_error) }
    if kept != 0usize { let copied = octets.copy(bytes[0usize..kept], old[0usize..kept]) }
    ret (bytes, ok)
}

// Reads a text or binary column whole into the reader's scratch buffer with as many
// `SQLGetData` calls as its length needs, and answers its length in bytes and whether it was
// NULL. A text read ends each piece with a two-byte terminator that is not data.
fn read_long(r: *Reader, column: u16, c_type: i16, terminator: usize) -> (usize, bool, err) {
    var got = 0usize
    var need = FIRST_READ + terminator
    while true {
        if r.scratch.len < got + need {
            let (bigger, grow_error) = grown(r.conn.arena, r.scratch, got, got + need)
            if grow_error != ok { ret (0usize, false, grow_error) }
            r.scratch = bigger
        }
        let room = r.scratch.len - got
        var length = 0i64
        let rc = capi.get_data(r.handle, column, c_type, mem.cast[*void](&r.scratch[got]), i64(room), &length)
        if rc == SQL_NO_DATA { ret (got, false, ok) }
        if !succeeded(rc) { ret (0usize, false, failure(r.conn, SQL_HANDLE_STMT, r.handle)) }
        if length == SQL_NULL_DATA { ret (0usize, true, ok) }
        let fits = room - terminator
        if length != SQL_NO_TOTAL && length >= 0i64 && usize(length) <= fits { ret (got + usize(length), false, ok) }
        // Truncated (01004): this piece filled the room less its terminator, in whole units.
        var piece = fits
        if terminator != 0usize { piece -= piece % 2usize }
        got += piece
        need = room * 2usize
        if length != SQL_NO_TOTAL && length >= 0i64 { need = usize(length) - piece + terminator }
    }
    ret (got, false, ok)
}

// Room for `n` more bytes of this row. A grown buffer is a new one: the values already
// filled keep pointing at the old, which the arena still holds.
fn reserve(r: *Reader, n: usize) -> err {
    if r.used + n <= r.buffer.len { ret ok }
    var size = r.buffer.len * 2usize
    if size < 256usize { size = 256usize }
    if size < n { size = n }
    let (bytes, grow_error) = mem.alloc[u8](r.conn.arena, size)
    if grow_error != ok { ret grow_error }
    r.buffer = bytes
    r.used = 0usize
    ret ok
}

fn fixed(r: *Reader, column: u16, c_type: i16, into: *void, cap: i64) -> (bool, err) {
    var length = 0i64
    let rc = capi.get_data(r.handle, column, c_type, into, cap, &length)
    if !succeeded(rc) { ret (false, failure(r.conn, SQL_HANDLE_STMT, r.handle)) }
    ret (length == SQL_NULL_DATA, ok)
}

fn fill(r: *Reader, dst: []db.Value) -> err {
    r.used = 0usize
    var i = 0usize
    while i < r.columns.len {
        let column = u16(i + 1usize)
        switch r.columns[i].kind {
        case .Bool:
            var flag: [1]u8 = zero
            let (is_null, bool_error) = fixed(r, column, SQL_C_BIT, mem.cast[*void](&flag[0usize]), 1i64)
            if bool_error != ok { ret bool_error }
            dst[i] = db.Value{ Bool: flag[0usize] != 0u8 }
            if is_null { dst[i] = .Null }
        case .I64:
            var number = 0i64
            let (is_null, number_error) = fixed(r, column, SQL_C_SBIGINT, mem.cast[*void](&number), 8i64)
            if number_error != ok { ret number_error }
            dst[i] = db.Value{ I64: number }
            if is_null { dst[i] = .Null }
        case .F64:
            var real = 0.0f64
            let (is_null, real_error) = fixed(r, column, SQL_C_DOUBLE, mem.cast[*void](&real), 8i64)
            if real_error != ok { ret real_error }
            dst[i] = db.Value{ F64: real }
            if is_null { dst[i] = .Null }
        case .Time:
            var stamp: [16]u8 = zero
            let (is_null, stamp_error) = fixed(r, column, SQL_C_TYPE_TIMESTAMP, mem.cast[*void](&stamp[0usize]), 16i64)
            if stamp_error != ok { ret stamp_error }
            let (nanos, valid) = read_stamp(stamp[0usize..16usize])
            if !is_null && !valid { ret refuse(r.conn, "a date or timestamp names no instant an i64 of nanoseconds holds", Failed) }
            dst[i] = db.Value{ Time: time.Instant { nanos: nanos } }
            if is_null { dst[i] = .Null }
        case .Bytes:
            let (n, is_null, bytes_error) = read_long(r, column, SQL_C_BINARY, 0usize)
            if bytes_error != ok { ret bytes_error }
            let reserve_error = reserve(r, n)
            if reserve_error != ok { ret reserve_error }
            let start = r.used
            if n != 0usize { let copied = octets.copy(r.buffer[start..start + n], r.scratch[0usize..n]) }
            r.used = start + n
            dst[i] = db.Value{ Bytes: r.buffer[start..start + n] }
            if is_null { dst[i] = .Null }
        default:
            let (n, is_null, text_error) = read_long(r, column, SQL_C_WCHAR, 2usize)
            if text_error != ok { ret text_error }
            let most = n / 2usize * 3usize
            let reserve_error = reserve(r, most)
            if reserve_error != ok { ret reserve_error }
            let start = r.used
            let (written, narrow_error) = narrow(r.scratch[0usize..n], r.buffer[start..start + most])
            if narrow_error != ok { ret refuse(r.conn, "the driver answered text that is not UTF-16", Failed) }
            r.used = start + written
            let s: str = r.buffer[start..start + written]
            dst[i] = db.Value{ Text: s }
            if is_null { dst[i] = .Null }
        }
        i += 1usize
    }
    ret ok
}

fn next_row(r: *Reader, dst: []db.Value) -> (bool, err) {
    if r.statement != nil && r.statement.closed { ret (false, db.Closed) }
    if dst.len < r.columns.len { ret (false, refuse(r.conn, "the row buffer is shorter than the row", db.InvalidQuery)) }
    if r.done { ret (false, ok) }
    let rc = capi.fetch(r.handle)
    if rc == SQL_NO_DATA {
        r.done = true
        ret (false, ok)
    }
    if !succeeded(rc) {
        r.done = true
        ret (false, failure(r.conn, SQL_HANDLE_STMT, r.handle))
    }
    let fill_error = fill(r, dst)
    if fill_error != ok { ret (false, fill_error) }
    ret (true, ok)
}

// --- the driver table

// A transaction still open is rolled back: `SQLDisconnect` refuses a connection inside one.
// Disconnecting frees every statement on the connection.
fn d_close(ctx: *void) -> err {
    let c = conn_of(ctx)
    if c.in_transaction {
        let rolled_back = capi.end_tran(SQL_HANDLE_DBC, c.dbc, SQL_ROLLBACK)
        c.in_transaction = false
    }
    let rc = capi.disconnect(c.dbc)
    var close_error = ok
    if !succeeded(rc) { close_error = failure(c, SQL_HANDLE_DBC, c.dbc) }
    let freed_dbc = capi.free_handle(SQL_HANDLE_DBC, c.dbc)
    let freed_env = capi.free_handle(SQL_HANDLE_ENV, c.env)
    ret close_error
}

// Asking the result's shape after preparing makes a driver that defers preparing check the
// text now, so SQL that cannot run fails here with most drivers.
fn d_prepare(ctx: *void, sql: str) -> (db.Statement, err) {
    let c = conn_of(ctx)
    var statement: db.Statement = zero
    let (handle, handle_error) = new_statement(c)
    if handle_error != ok { ret (statement, handle_error) }
    let (declared, compile_error) = compile(c, handle, sql)
    if compile_error != ok {
        free_statement(handle)
        ret (statement, compile_error)
    }
    var columns = 0i16
    if !succeeded(capi.num_result_cols(handle, &columns)) {
        let shape_error = failure(c, SQL_HANDLE_STMT, handle)
        free_statement(handle)
        ret (statement, shape_error)
    }
    let (stmts, stmt_error) = mem.alloc[Stmt](c.arena, 1usize)
    if stmt_error != ok {
        free_statement(handle)
        ret (statement, stmt_error)
    }
    stmts[0usize] = Stmt { conn: c, handle: handle, params: declared, closed: false }
    clear(c)
    statement.ctx = mem.cast[*void](&stmts[0usize])
    ret (statement, ok)
}

fn d_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = execute_text(conn_of(ctx), sql, params)
    ret (affected, execute_error)
}

fn d_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let c = conn_of(ctx)
    let (handle, handle_error) = new_statement(c)
    if handle_error != ok { ret (zero, handle_error) }
    let (declared, compile_error) = compile(c, handle, sql)
    if compile_error != ok {
        free_statement(handle)
        ret (zero, compile_error)
    }
    let launch_error = launch(c, handle, declared, params)
    if launch_error != ok {
        free_statement(handle)
        ret (zero, launch_error)
    }
    let (rows, rows_error) = reader(c, handle, nil, true)
    ret (rows, rows_error)
}

// One transaction at a time: a second `begin` is `Busy`. Autocommit is switched off for the
// transaction's life and back on when it ends.
fn d_begin(ctx: *void) -> (db.Transaction, err) {
    let c = conn_of(ctx)
    var transaction: db.Transaction = zero
    if c.in_transaction { ret (transaction, refuse(c, "a transaction is already open on this connection", db.Busy)) }
    let (txs, tx_error) = mem.alloc[Tx](c.arena, 1usize)
    if tx_error != ok { ret (transaction, tx_error) }
    if !succeeded(capi.set_connect_attr(c.dbc, SQL_ATTR_AUTOCOMMIT, SQL_AUTOCOMMIT_OFF, 0i32)) { ret (transaction, failure(c, SQL_HANDLE_DBC, c.dbc)) }
    c.in_transaction = true
    clear(c)
    txs[0usize] = Tx { conn: c }
    transaction.ctx = mem.cast[*void](&txs[0usize])
    ret (transaction, ok)
}

fn d_statement_close(ctx: *void) -> err {
    let s = stmt_of(ctx)
    free_statement(s.handle)
    s.closed = true
    ret ok
}

fn d_statement_execute(ctx: *void, params: []const db.Parameter) -> (u64, err) {
    let s = stmt_of(ctx)
    // A reader still open on this statement holds its cursor.
    let closed_cursor = capi.free_stmt(s.handle, SQL_CLOSE)
    let launch_error = launch(s.conn, s.handle, s.params, params)
    if launch_error != ok { ret (0u64, launch_error) }
    let (affected, count_error) = count_results(s.conn, s.handle)
    ret (affected, count_error)
}

fn d_statement_query(ctx: *void, params: []const db.Parameter) -> (db.Rows, err) {
    let s = stmt_of(ctx)
    let closed_cursor = capi.free_stmt(s.handle, SQL_CLOSE)
    let launch_error = launch(s.conn, s.handle, s.params, params)
    if launch_error != ok { ret (zero, launch_error) }
    let (rows, rows_error) = reader(s.conn, s.handle, s, false)
    ret (rows, rows_error)
}

fn d_rows_columns(ctx: *void) -> []const db.Column { ret reader_of(ctx).columns }

// ODBC copies every value out with `SQLGetData`, so there is no borrowed form: this is the
// table's entry for both readers.
fn d_rows_next(ctx: *void, dst: []db.Value) -> (bool, err) {
    let (more, next_error) = next_row(reader_of(ctx), dst)
    ret (more, next_error)
}

fn d_rows_close(ctx: *void) -> err {
    let r = reader_of(ctx)
    if r.owned {
        free_statement(r.handle)
    } else if !r.statement.closed {
        let closed_cursor = capi.free_stmt(r.handle, SQL_CLOSE)
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

// A failed commit is rolled back, since `e.db` has already closed the handle that could have
// retried it; the commit's diagnostic is the one kept.
fn d_transaction_commit(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    var commit_error = ok
    if !succeeded(capi.end_tran(SQL_HANDLE_DBC, c.dbc, SQL_COMMIT)) {
        commit_error = failure(c, SQL_HANDLE_DBC, c.dbc)
        let rolled_back = capi.end_tran(SQL_HANDLE_DBC, c.dbc, SQL_ROLLBACK)
    }
    let autocommit_error = end_transaction(c)
    if commit_error != ok { ret commit_error }
    if autocommit_error == ok { clear(c) }
    ret autocommit_error
}

fn d_transaction_rollback(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    var rollback_error = ok
    if !succeeded(capi.end_tran(SQL_HANDLE_DBC, c.dbc, SQL_ROLLBACK)) { rollback_error = failure(c, SQL_HANDLE_DBC, c.dbc) }
    let autocommit_error = end_transaction(c)
    if rollback_error != ok { ret rollback_error }
    if autocommit_error == ok { clear(c) }
    ret autocommit_error
}

fn end_transaction(c: *Conn) -> err {
    c.in_transaction = false
    if !succeeded(capi.set_connect_attr(c.dbc, SQL_ATTR_AUTOCOMMIT, SQL_AUTOCOMMIT_ON, 0i32)) { ret failure(c, SQL_HANDLE_DBC, c.dbc) }
    ret ok
}
