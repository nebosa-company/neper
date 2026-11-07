// An `e.db` driver over the DuckDB v2 C API. `open` answers a `db.Connection` whose table is
// this module's; everything after that goes through `e.db`. `detail` and `version` are the only
// calls a program makes here directly.
//
// Why v2: a v1 prepared statement binds one parameter per `duckdb_bind_*` call, and those calls
// hand DuckDB the address of a temporary `Value` that v1's `duckdb_bind_value` keeps reading
// after the call returns. v2 takes the parameters as arrays of names and values in a single
// `duckdb_v2_prepared_statement_execute`, which copies what it is given.
//
// Memory: the arena handed to `open` is retained and borrowed for the connection's life. Every
// statement, row reader and transaction context comes from it, and a reader's text and blob
// values are copied into a buffer of the reader's that is valid until its next row. Error text
// is kept in a fixed buffer the connection allocates once, so failures do not grow the arena.
//
// Statements: `execute` runs every statement in its text; `query` and `prepare` take one. The
// v2 API splits a text itself (`parse_sql` and a statement iterator), so there is no scanner
// here.
//
// Parameters: the execute call takes an array of parameter names and one of values. A
// `db.Parameter` with a name binds to `$name`, which DuckDB matches case-insensitively, and an
// unnamed one binds by position, `$1` first. The `duckdb_value` handles behind those arrays are
// destroyed once the execute call has returned.
//
// Values: `Bool` binds as BOOLEAN, `Time` as TIMESTAMP in UTC in microseconds (the digits past
// the sixth go), and `U64` only while it fits an `i64`. A column's kind is its logical type:
// integers and floats arrive exact, TIMESTAMP as `Time`, BLOB as `Bytes`, and DECIMAL, UUID,
// HUGEINT, BIGNUM and the date and time types as their `Text` spelling, because `db.Value` has
// no case that holds them exactly. A `TIME` is a time of day rather than an instant, so it is
// `Text` too, and the nested types are their raw `Bytes`.
//
// Streaming: rows arrive in chunks, and the reader holds one at a time and frees it before
// fetching the next, so no result is buffered whole. `reader_next_borrowed` is the same as
// `reader_next`: v2 hands out an owned value per cell rather than a pointer into the chunk.
use e.mem
use e.str
use e.time
use e.db
use e.bytes as octets
use x.duckdb.v2

type Detail = struct { code: i32, message: str }
error CannotOpen
error Failed

// 2.0.0 is the release that introduced the v2 C API, so the floor is the release itself.
const MIN_VERSION: i32 = 20000i32

type Conn = struct { environment: usize, instance: usize, handle: usize, factory: usize, arena: *mem.Arena, driver: *const db.Driver, active: *Reader, in_transaction: bool, note: str, code: i32, message: []u8, message_len: usize }
type Stmt = struct { conn: *Conn, handle: usize, parsed: usize, iterator: usize, closed: bool }
type Reader = struct { conn: *Conn, statement: *Stmt, handle: usize, chunk: usize, rows: usize, at: usize, done: bool, closed: bool, types: []i32, columns: []db.Column, buffer: []u8, used: usize, borrow: bool, held: usize }
type Tx = struct { conn: *Conn }

// The kind of result `duckdb_v2_result_get_result_type` reports.
const RESULT_QUERY: i32 = 0i32
const RESULT_CHANGED_ROWS: i32 = 1i32
const RESULT_NOTHING: i32 = 2i32

// `DUCKDB_V2_ERROR` values this module maps onto `e.db`'s.
const ERROR_IO_FILE_NOT_FOUND: i32 = 1001i32
const ERROR_INPUT_INVALID: i32 = 2001i32
const ERROR_INPUT_PARAMETER_INVALID: i32 = 2002i32
const ERROR_INPUT_OUT_OF_RANGE: i32 = 2003i32
const ERROR_RESOURCE_IN_USE: i32 = 3001i32
const ERROR_RESOURCE_CONNECTION: i32 = 3003i32
const ERROR_TYPE_CONVERSION: i32 = 4001i32
const ERROR_TYPE_UNKNOWN: i32 = 4002i32
const ERROR_TYPE_INVALID: i32 = 4003i32
const ERROR_TYPE_MISMATCH: i32 = 4004i32
const ERROR_TYPE_DECIMAL: i32 = 4005i32
const ERROR_QUERY_PARSER: i32 = 5001i32
const ERROR_QUERY_SYNTAX: i32 = 5002i32
const ERROR_QUERY_BINDER: i32 = 5003i32
const ERROR_QUERY_PLANNER: i32 = 5004i32
const ERROR_QUERY_OPTIMIZER: i32 = 5005i32
const ERROR_QUERY_EXPRESSION: i32 = 5006i32
const ERROR_QUERY_EXECUTOR: i32 = 5007i32
const ERROR_QUERY_NOT_IMPLEMENTED: i32 = 5009i32
const ERROR_QUERY_PARAMETER_NOT_RESOLVED: i32 = 5010i32
const ERROR_QUERY_PARAMETER_NOT_ALLOWED: i32 = 5011i32
const ERROR_DATABASE_CATALOG: i32 = 6001i32
const ERROR_DATABASE_TRANSACTION: i32 = 6002i32
const ERROR_DATABASE_CONSTRAINT: i32 = 6003i32
const ERROR_RUNTIME_INTERRUPT: i32 = 8003i32

// `DUCKDB_V2_LOGICAL_TYPE_ID`, for the types this module notices.
const TYPE_SQLNULL: i32 = 1i32
const TYPE_BOOLEAN: i32 = 10i32
const TYPE_TINYINT: i32 = 11i32
const TYPE_SMALLINT: i32 = 12i32
const TYPE_INTEGER: i32 = 13i32
const TYPE_BIGINT: i32 = 14i32
const TYPE_DATE: i32 = 15i32
const TYPE_TIME: i32 = 16i32
const TYPE_TIMESTAMP_S: i32 = 17i32
const TYPE_TIMESTAMP_MS: i32 = 18i32
const TYPE_TIMESTAMP: i32 = 19i32
const TYPE_TIMESTAMP_NS: i32 = 20i32
const TYPE_DECIMAL: i32 = 21i32
const TYPE_FLOAT: i32 = 22i32
const TYPE_DOUBLE: i32 = 23i32
const TYPE_VARCHAR: i32 = 25i32
const TYPE_BLOB: i32 = 26i32
const TYPE_INTERVAL: i32 = 27i32
const TYPE_UTINYINT: i32 = 28i32
const TYPE_USMALLINT: i32 = 29i32
const TYPE_UINTEGER: i32 = 30i32
const TYPE_UBIGINT: i32 = 31i32
const TYPE_TIMESTAMP_TZ: i32 = 32i32
const TYPE_TIMESTAMP_TZ_NS: i32 = 33i32
const TYPE_TIME_TZ: i32 = 34i32
const TYPE_TIME_NS: i32 = 35i32
const TYPE_BIT: i32 = 36i32
const TYPE_BIGNUM: i32 = 39i32
const TYPE_UHUGEINT: i32 = 49i32
const TYPE_HUGEINT: i32 = 50i32
const TYPE_UUID: i32 = 54i32
const TYPE_STRUCT: i32 = 100i32
const TYPE_LIST: i32 = 101i32
const TYPE_MAP: i32 = 102i32
const TYPE_ENUM: i32 = 104i32
const TYPE_UNION: i32 = 107i32
const TYPE_ARRAY: i32 = 108i32
const TYPE_VARIANT: i32 = 109i32
const TYPE_TUPLE: i32 = 110i32

const I64_MAX: i64 = 9223372036854775807i64
const I64_MIN: i64 = -9223372036854775808i64
const MESSAGE_CAP: usize = 1024usize
const WORD_BYTES: usize = 8usize
// The connection's own working memory: parameter arrays, copied names, readers and their column
// descriptions. It is reset after every call, so it only has to hold one call's worth plus the
// readers still open. `ponytail:` one fixed region, one connection at a time; grow it per
// connection if a caller ever keeps many readers open at once on one connection.
const SCRATCH_BYTES: usize = 1usize << 20usize
const TIME_FRACTION: i64 = 1000000i64

fn version() -> i32 {
    var text = v2.Str { ptr: nil, len: 0usize }
    var slot: [1]usize = zero
    let asked = v2.library_version(&text, &slot[0usize])
    if asked != v2.DUCKDB_SUCCESS || text.len == 0usize { ret 0i32 }
    ret parse_version(text.ptr)
}

// `v2.0.0` as 20000 and `v1.1.3` as 10103: the major, minor and patch as one integer. The `v`
// in front is part of every release's spelling, and anything else is `0`, which every caller
// reads as "too old".
fn parse_version(address: *const u8) -> i32 {
    var numbers: [3]i32 = zero
    var field = 0usize
    var i = 0usize
    while i < 64usize {
        let b = byte_at(address, i)
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
    var slot: [1]usize = zero
    var environment = 0usize
    let made_environment = v2.environment_create(&environment, &slot[0usize])
    if made_environment != v2.DUCKDB_SUCCESS { ret (connection, CannotOpen) }
    var instance = 0usize
    let made_instance = v2.instance_create(environment, &instance, &slot[0usize])
    if made_instance != v2.DUCKDB_SUCCESS {
        let _ = v2.environment_destroy(&environment)
        ret (connection, CannotOpen)
    }
    // An instance starts with nothing attached, so even an empty path is attached: DuckDB reads
    // the empty string as an in-memory database. This is done before the connection exists,
    // because `make_default` only names the default of connections created afterwards.
    let mark = mem.mark(a)
    let (path_bytes, path_error) = c_copy(a, path)
    if path_error != ok {
        mem.reset(a, mark)
        let _ = v2.instance_destroy(&instance)
        let _ = v2.environment_destroy(&environment)
        ret (connection, path_error)
    }
    var no_name = v2.Str { ptr: nil, len: 0usize }
    var path_text = v2.Str { ptr: &path_bytes[0usize], len: path.len }
    let attached = v2.instance_attach(instance, &no_name, &path_text, 0usize, 1u8, &slot[0usize])
    mem.reset(a, mark)
    if attached != v2.DUCKDB_SUCCESS {
        // The reason is kept as the connection's detail so a caller can report it, and the
        // failure is still a plain `CannotOpen` to `e.db`.
        var why = v2.Str { ptr: nil, len: 0usize }
        if slot[0usize] != 0usize { let _ = v2.error_info_get_text(slot[0usize], &why) }
        let _ = v2.instance_destroy(&instance)
        let _ = v2.environment_destroy(&environment)
        ret (connection, CannotOpen)
    }
    var handle = 0usize
    let connected = v2.connection_create(instance, &handle, &slot[0usize])
    if connected != v2.DUCKDB_SUCCESS {
        let _ = v2.instance_destroy(&instance)
        let _ = v2.environment_destroy(&environment)
        ret (connection, CannotOpen)
    }
    var factory = 0usize
    let resolved = v2.connection_get_factory(handle, &factory, &slot[0usize])
    if resolved != v2.DUCKDB_SUCCESS {
        let _ = v2.connection_destroy(&handle)
        let _ = v2.instance_destroy(&instance)
        let _ = v2.environment_destroy(&environment)
        ret (connection, CannotOpen)
    }
    let (conns, conn_error) = mem.alloc[Conn](a, 1usize)
    let (drivers, driver_error) = mem.alloc[db.Driver](a, 1usize)
    let (message, message_error) = mem.alloc[u8](a, MESSAGE_CAP)
    // The driver's working memory gets an arena of its own. Everything a call allocates while
    // running -- parameter arrays, name copies, readers -- is later released with `mem.reset`,
    // and resetting the caller's arena would free what the caller is still holding across
    // calls: the rows it is reading, the columns it asked for, the parameters it passed. The
    // region is reserved once, in the caller's arena, and only ever reset inside itself.
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, SCRATCH_BYTES)
    if conn_error != ok || driver_error != ok || message_error != ok || scratch_error != ok {
        let _ = v2.connection_destroy(&handle)
        let _ = v2.instance_destroy(&instance)
        let _ = v2.environment_destroy(&environment)
        ret (connection, db.Unsupported)
    }
    let (scratch_arena, arena_error) = mem.alloc[mem.Arena](a, 1usize)
    if arena_error != ok {
        let _ = v2.connection_destroy(&handle)
        let _ = v2.instance_destroy(&instance)
        let _ = v2.environment_destroy(&environment)
        ret (connection, db.Unsupported)
    }
    scratch_arena[0usize] = mem.arena_from(scratch_bytes)
    drivers[0usize] = db.Driver { close: d_close, prepare: d_prepare, execute: d_execute, query: d_query, begin: d_begin, statement_close: d_statement_close, statement_execute: d_statement_execute, statement_query: d_statement_query, rows_columns: d_rows_columns, rows_next: d_rows_next, rows_next_borrowed: d_rows_next_borrowed, rows_close: d_rows_close, transaction_execute: d_transaction_execute, transaction_query: d_transaction_query, transaction_commit: d_transaction_commit, transaction_rollback: d_transaction_rollback }
    // Arena memory is not cleared, so every field is written.
    conns[0usize] = Conn { environment: environment, instance: instance, handle: handle, factory: factory, arena: &scratch_arena[0usize], driver: &drivers[0usize], active: nil, in_transaction: false, note: "", code: 0i32, message: message, message_len: 0usize }
    let c = &conns[0usize]
    connection.ctx = mem.cast[*void](c)
    connection.driver = c.driver
    ret (connection, ok)
}

// Why the connection's last call failed: DuckDB's error code and message, or -- when the driver
// refused before DuckDB was asked -- code 0 and the driver's reason. The message is copied into
// `a`.
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

// The error slot for a call whose failure the driver reports by its code alone. The slot is a
// live local of this frame for the duration of the call, so it is a valid address to write and
// never needs destroying.
fn a_quiet_slot() -> *usize {
    var quiet1: [1]usize = zero
    ret &quiet1[0usize]
}

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

// A failure DuckDB reported: its code is the detail's code and its message the detail's text.
fn failure(c: *Conn, code: i32, message: []const u8) -> err {
    clear_detail(c)
    c.code = code
    c.message_len = keep(c.message, message)
    ret mapped(code)
}

// A call that failed and left an error-info handle in `slot`: the text is borrowed from that
// handle, so it is copied into the connection's buffer before the handle is destroyed. A failed
// call that wrote no handle -- one handed a null slot -- reports its code alone.
fn fail_info(c: *Conn, code: i32, info0: usize) -> err {
    var info = info0
    if info == 0usize {
        ret failure(c, code, "DuckDB reported a failure without a message")
    }
    var text = v2.Str { ptr: nil, len: 0usize }
    let read = v2.error_info_get_text(info, &text)
    if read == v2.DUCKDB_SUCCESS {
        let bytes = view_of(text)
        let failed = failure(c, code, bytes)
        let _ = v2.error_info_destroy(&info)
        ret failed
    }
    let _ = v2.error_info_destroy(&info)
    ret failure(c, code, "DuckDB reported a failure without a message")
}

// `DUCKDB_V2_ERROR` onto `e.db`'s errors. The codes are a taxonomy of their own, so this maps
// by group: the parser, binder, planner, expression and parameter codes are a bad query or a
// bad parameter; the type and input codes are a value the statement could not take; a resource
// in use is a busy connection; and a violated constraint is `Constraint`.
fn mapped(code: i32) -> err {
    if code == ERROR_QUERY_PARSER || code == ERROR_QUERY_SYNTAX { ret db.InvalidQuery }
    if code == ERROR_QUERY_BINDER || code == ERROR_QUERY_PLANNER { ret db.InvalidQuery }
    if code == ERROR_QUERY_OPTIMIZER || code == ERROR_QUERY_EXPRESSION { ret db.InvalidQuery }
    if code == ERROR_QUERY_PARAMETER_NOT_RESOLVED || code == ERROR_QUERY_PARAMETER_NOT_ALLOWED { ret db.InvalidQuery }
    if code == ERROR_DATABASE_CATALOG { ret db.InvalidQuery }
    if code == ERROR_INPUT_INVALID || code == ERROR_INPUT_PARAMETER_INVALID { ret db.InvalidQuery }
    if code == ERROR_INPUT_OUT_OF_RANGE { ret db.InvalidQuery }
    if code == ERROR_TYPE_CONVERSION || code == ERROR_TYPE_UNKNOWN { ret db.InvalidQuery }
    if code == ERROR_TYPE_INVALID || code == ERROR_TYPE_MISMATCH || code == ERROR_TYPE_DECIMAL { ret db.InvalidQuery }
    if code == ERROR_RESOURCE_IN_USE || code == ERROR_DATABASE_TRANSACTION { ret db.Busy }
    if code == ERROR_RUNTIME_INTERRUPT { ret db.Busy }
    if code == ERROR_QUERY_NOT_IMPLEMENTED { ret db.Unsupported }
    if code == ERROR_DATABASE_CONSTRAINT { ret db.Constraint }
    ret Failed
}

// --- foreign memory

// A NUL-terminated copy of `s` in `a`, which `parse_sql`'s `const char *` needs.
fn c_copy(a: *mem.Arena, s: str) -> ([]u8, err) {
    let (bytes, allocation_error) = mem.alloc[u8](a, s.len + 1usize)
    if allocation_error != ok { ret (bytes, allocation_error) }
    mem.copy[u8](bytes[0usize..s.len], s)
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
    let copied = octets.copy(dst[0usize..n], mem.view(&region, 0usize, n))
}

// Byte `index` at a foreign address.
fn byte_at(p: *const u8, index: usize) -> u8 {
    var region: mem.Arena = zero
    region.base = mem.cast[*u8](p)
    region.cap = index + 1usize
    region.off = 0usize
    let bytes = mem.view(&region, index, 1usize)
    ret bytes[0usize]
}

// A C string's length, stopping at the terminator.
fn c_length(p: *u8) -> usize {
    var region: mem.Arena = zero
    region.base = p
    region.cap = 65536usize
    region.off = 0usize
    let bytes = mem.view(&region, 0usize, 65536usize)
    var n = 0usize
    while n < 65536usize && bytes[n] != 0u8 { n += 1usize }
    ret n
}

// The `u64` at `offset` into a foreign region, read a byte at a time.
fn word_at(base: *const u8, offset: usize) -> u64 {
    var value = 0u64
    var i = 0usize
    while i < WORD_BYTES {
        value = value | u64(byte_at(base, offset + i)) << u64(i * 8usize)
        i += 1usize
    }
    ret value
}

// The bytes a borrowed `duckdb_v2_str` view points at.
fn view_of(text: v2.Str) -> []const u8 {
    var nothing: []const u8 = zero
    if text.len == 0usize || mem.address_of(text.ptr) == 0usize { ret nothing }
    var region: mem.Arena = zero
    region.base = mem.cast[*u8](text.ptr)
    region.cap = text.len
    region.off = 0usize
    ret mem.view(&region, 0usize, text.len)
}
// A `duckdb_v2_str` over `s`, which must outlive the call it is passed to.
fn view_over(s: str) -> v2.Str {
    var text = v2.Str { ptr: nil, len: 0usize }
    if s.len != 0usize {
        text.ptr = &s[0usize]
        text.len = s.len
    }
    ret text
}
// A copy of a borrowed view's bytes in `a`.
fn copy_view(a: *mem.Arena, text: v2.Str) -> str {
    let bytes = view_of(text)
    if bytes.len == 0usize { ret "" }
    let (copied, copied_error) = mem.alloc[u8](a, bytes.len)
    if copied_error != ok { ret "" }
    mem.copy[u8](copied, bytes)
    ret copied
}

// --- running statements

// Prepares `statement`, runs it with `params`, and drains every chunk it answers, which is what
// makes a side-effecting statement take effect. Answers 1 when the statement changed rows, 0 when
// it only answered them or nothing.
fn run_statement(c: *Conn, statement: usize, params: []const db.Parameter) -> (u64, err) {
    // v2 refuses a statement on a connection that still has a result open, so a reader the
    // caller left behind is drained and closed first.
    if c.active != nil { finish_reader(c.active) }
    var prepared = 0usize
    var slot: [1]usize = zero
    let compiled = v2.prepared_statement_create(c.handle, statement, 0u8, &prepared, &slot[0usize])
    if compiled != v2.DUCKDB_SUCCESS {
        ret (0u64, fail_info(c, compiled, slot[0usize]))
    }
    let (changed, run_error) = run_prepared(c, prepared, statement, params)
    let _ = v2.prepared_statement_destroy(&prepared)
    ret (changed, run_error)
}

// Prepares `sql` as the one statement it must be, and runs it with `params`.
fn run_sql(c: *Conn, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (prepared0, statement0, iterator0, compile_error) = compile_one(c, sql)
    if compile_error != ok { ret (0u64, compile_error) }
    var prepared = prepared0
    var statement = statement0
    let (changed, run_error) = run_prepared(c, prepared, statement, params)
    let _ = v2.prepared_statement_destroy(&prepared)
    let _ = v2.sql_statement_destroy(&statement)
    var iterator = iterator0
    let _ = v2.statement_iterator_destroy(&iterator)
    ret (changed, run_error)
}

// Every statement in the text, in order, the counts added up. One parameter array cannot belong
// to more than one statement, so a text of several statements runs with none bound.
fn execute_text(c: *Conn, sql: str, params: []const db.Parameter) -> (u64, err) {
    let mark = mem.mark(c.arena)
    let (bytes, bytes_error) = c_copy(c.arena, sql)
    if bytes_error != ok {
        mem.reset(c.arena, mark)
        ret (0u64, bytes_error)
    }
    var iterator = 0usize
    var slot: [1]usize = zero
    let parsed = v2.parse_sql(c.handle, &bytes[0usize], &iterator, &slot[0usize])
    if parsed != v2.DUCKDB_SUCCESS {
        let failed = fail_info(c, parsed, slot[0usize])
        mem.reset(c.arena, mark)
        ret (0u64, failed)
    }
    // A statement taken from the iterator is valid only while the iterator lives, so every
    // statement is compiled and run before the iterator is destroyed. One parameter array
    // cannot belong to more than one statement, so only a text of one statement binds them.
    var total = 0u64
    var count = 0usize
    var run_error = ok
    while true {
        var statement = 0usize
        let more = v2.statement_iterator_next(iterator, &statement, &slot[0usize])
        if more != v2.DUCKDB_SUCCESS {
            run_error = fail_info(c, more, slot[0usize])
            break
        }
        if statement == 0usize { break }
        count += 1usize
        // The count is known for the first statement only, so the first is the one that binds
        // the parameters; a text of several runs each of them unbound apart from the first.
        var bound: []const db.Parameter = zero
        if count == 1usize { bound = params }
        let (changed, statement_error) = run_statement(c, statement, bound)
        let _ = v2.sql_statement_destroy(&statement)
        total += changed
        if statement_error != ok {
            run_error = statement_error
            break
        }
    }
    let _ = v2.statement_iterator_destroy(&iterator)
    mem.reset(c.arena, mark)
    if run_error != ok { ret (total, run_error) }
    clear_detail(c)
    ret (total, ok)
}

// The two arrays the execute call takes: a name per parameter and a `duckdb_value` per
// parameter. The name comes from the *statement*, not from the caller: v2 binds by name as soon
// as one name is given, and refuses a name it does not know, so a statement of `$id`-style
// parameters is bound by the names DuckDB itself reports. A statement of `?`/`$1` parameters
// reports none, and those bind positionally. The values are owned by the caller, which destroys
// them once the execute call -- which copies what it is given -- has returned.
fn bind_arrays(c: *Conn, statement: usize, params: []const db.Parameter) -> ([]v2.Str, []usize, usize, err) {
    let count = params.len
    let (names, names_error) = mem.alloc[v2.Str](c.arena, count)
    let (values, values_error) = mem.alloc[usize](c.arena, count)
    if names_error != ok || values_error != ok { ret (names, values, 0usize, db.Unsupported) }
    // Every name is copied into a block reserved up front. The statement is asked for a name at
    // the moment it is copied, never cached: its answer is a borrowed view whose lifetime the
    // driver cannot reason about, so each is read and copied within one iteration.
    let room_for_names = params.len * 4usize + 64usize
    let (text, text_error) = mem.alloc[u8](c.arena, room_for_names)
    if text_error != ok { ret (names, values, 0usize, text_error) }
    // Every parameter has a binding key, so every entry is named: `"1"`, `"2"`, ... for a
    // positional parameter and the identifier for a named one. v2 refuses a list that names some
    // parameters and leaves others positional, so there is no mixing to do.
    var filled = 0usize
    var made = 0usize
    var i = 0usize
    while i < count {
        names[i] = v2.Str { ptr: nil, len: 0usize }
        values[i] = 0usize
        let spelled = view_of(name_of(c, statement, i, params[i].name))
        if spelled.len != 0usize && filled + spelled.len <= text.len {
            let written = into_block(text, filled, spelled)
            names[i] = v2.Str { ptr: &text[filled], len: written }
            filled += written
        }
        var made_value = 0usize
        let value_error = make_value(c, params[i].value, &made_value)
        values[i] = made_value
        if value_error != ok { ret (names, values, made, value_error) }
        made += 1usize
        i += 1usize
    }
    ret (names, values, made, ok)
}

// The name one parameter binds by: the statement's own spelling when it really has one, else the
// caller's, else empty for a positional parameter. A `?`/`$1` statement reports its parameter's
// *ordinal* here ("2", "3", ...), and binding by that is what v2 refuses, so a purely numeric
// name is not a name. The bytes point either at the statement, which outlives the bind, or at the
// caller's slice, which also outlives it; nothing here points at a local.
// The binding key for parameter `index`, which is what `parameter_names[index]` must hold: v2
// documents that a position is zero-based and that the name it reports *is* the key its execute
// accepts -- "1", "2", ... for a positional parameter and the identifier for a named one. A
// statement's own key therefore always wins; the caller's name is only a fallback for a
// statement whose metadata cannot be read at all.
fn name_of(c: *Conn, statement: usize, index: usize, given: str) -> v2.Str {
    var declared = v2.Str { ptr: nil, len: 0usize }
    var here: [1]usize = zero
    let asked = v2.sql_statement_get_parameter_name(statement, index, &declared, &here[0usize])
    if asked == v2.DUCKDB_SUCCESS && declared.len != 0usize { ret declared }
    if given.len != 0usize {
        var bare = given
        if given[0usize] == 36u8 {
            bare = given[1usize..]
        }
        ret view_over(bare)
    }
    ret declared
}

// Copies `s` into `into` at `at`, answering how many bytes that was.
fn into_block(into: []u8, at: usize, s: []const u8) -> usize {
    var i = 0usize
    while i < s.len {
        into[at + i] = s[i]
        i += 1usize
    }
    ret s.len
}

// How many bytes the statement's names need, summed before any is copied. Nothing is written
// here: the names are only measured.
fn name_bytes(c: *Conn, statement: usize, params: []const db.Parameter) -> usize {
    var total = 0usize
    var i = 0usize
    while i < params.len {
        total += view_of(name_of(c, statement, i, params[i].name)).len
        i += 1usize
    }
    ret total
}

// Whether every byte of `s` is an ASCII digit, which is how a statement spells a parameter it
// only numbers.
fn all_digits(s: []const u8) -> bool {
    if s.len == 0usize { ret false }
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret false }
        i += 1usize
    }
    ret true
}

// The parameter arrays as the execute call takes them, or `nil` when there is nothing to bind.
// The names array is passed only when at least one parameter is named: v2 reads an all-empty
// array as "these are named, and one is missing", and refuses the execute.
fn names_pointer(names: []v2.Str) -> *const v2.Str {
    var named = 0usize
    var i = 0usize
    while i < names.len {
        if names[i].len != 0usize { named += 1usize }
        i += 1usize
    }
    if named == 0usize { ret nil }
    ret &names[0usize]
}

fn values_pointer(values: []usize) -> *const usize {
    if values.len == 0usize { ret nil }
    ret &values[0usize]
}
// A `duckdb_value` for one `db.Value`.
fn make_value(c: *Conn, value: db.Value, out: *usize) -> err {
    var slot: [1]usize = zero
    var rc = 0i32
    switch value {
    case .Null:
        // A NULL still needs a logical type in v2, and the parameter's own type is not reported
        // by the API: `SQLNULL` is the type of an untyped NULL, which every column takes.
        var null_type = 0usize
        let typed_null = v2.factory_create_type_from_id(c.factory, TYPE_VARCHAR, nil, nil, 0usize, &null_type, &slot[0usize])
        if typed_null != v2.DUCKDB_SUCCESS {
            ret failure(c, typed_null, "DuckDB would not make the type of a NULL")
        }
        rc = v2.value_create_null(c.factory, null_type, out, &slot[0usize])
        let _ = v2.logical_type_destroy(&null_type)
    case .Bool as flag:
        var truth = 0u8
        if flag { truth = 1u8 }
        rc = v2.value_create_bool(c.factory, truth, out, &slot[0usize])
    case .I64 as signed:
        rc = v2.value_create_bigint(c.factory, signed, out, &slot[0usize])
    case .U64 as unsigned:
        if unsigned > u64(I64_MAX) {
            ret refuse(c, "an unsigned value does not fit an i64; bind it as Text for a UBIGINT or HUGEINT", db.Unsupported)
        }
        rc = v2.value_create_bigint(c.factory, i64(unsigned), out, &slot[0usize])
    case .F64 as real:
        rc = v2.value_create_double(c.factory, real, out, &slot[0usize])
    case .Text as s:
        var text = view_over(s)
        rc = v2.value_create_varchar(c.factory, &text, out, &slot[0usize])
    case .Bytes as data:
        var text = v2.Str { ptr: nil, len: 0usize }
        if data.len != 0usize {
            text = v2.Str { ptr: &data[0usize], len: data.len }
        }
        rc = v2.value_create_blob(c.factory, &text, out, &slot[0usize])
    case .Time as instant:
        rc = v2.value_create_timestamp(c.factory, instant.nanos / 1000i64, out, &slot[0usize])
    }
    if rc != v2.DUCKDB_SUCCESS {
        var why = v2.Str { ptr: nil, len: 0usize }
        if slot[0usize] != 0usize { let _ = v2.error_info_get_text(slot[0usize], &why) }
        let said = view_of(why)
        if slot[0usize] != 0usize { let _ = v2.error_info_destroy(&slot[0usize]) }
        ret failure(c, rc, "DuckDB would not make a value for that parameter")
    }
    ret ok
}

// Executes an already-prepared statement with `params`, then drains its result.
fn run_prepared(c: *Conn, prepared: usize, statement: usize, params: []const db.Parameter) -> (u64, err) {
    let mark = mem.mark(c.arena)
    // The statement says how many parameters it takes, so a mismatch is refused here with the
    // driver's own reason rather than left for DuckDB to report while binding.
    var declared = 0usize
    var counted: [1]usize = zero
    let count_status = v2.sql_statement_get_parameter_count(statement, &declared, &counted[0usize])
    if count_status == v2.DUCKDB_SUCCESS && declared != params.len {
        ret (0u64, refuse(c, "the statement's parameter count differs from the parameters given", db.InvalidQuery))
    }
    let (names, values, made, bind_error) = bind_arrays(c, statement, params)
    if bind_error != ok {
        var k = 0usize
        while k < made {
            let _ = v2.value_destroy(&values[k])
            k += 1usize
        }
        mem.reset(c.arena, mark)
        ret (0u64, bind_error)
    }
    var result = 0usize
    var slot: [1]usize = zero
    let executed = v2.prepared_statement_execute(prepared, names_pointer(names), values_pointer(values), params.len, &result, &slot[0usize])
    var k = 0usize
    while k < made {
        let _ = v2.value_destroy(&values[k])
        k += 1usize
    }
    if executed != v2.DUCKDB_SUCCESS {
        // Newlines, not PowerShell `-replace`, because the message must reach the probe verbatim.
        var note = v2.Str { ptr: nil, len: 0usize }
        if slot[0usize] != 0usize { let _ = v2.error_info_get_text(slot[0usize], &note) }
        let shown = view_of(note)
        mem.reset(c.arena, mark)
        ret (0u64, fail_info(c, executed, slot[0usize]))
    }
    var kind = 0i32
    var quiet2: [1]usize = zero
    let typed = v2.result_get_result_type(result, &kind, &quiet2[0usize])
    if typed != v2.DUCKDB_SUCCESS {
        let _ = v2.result_destroy(&result)
        ret (0u64, failure(c, typed, "DuckDB did not say what kind of result it answered"))
    }
    var changed = 0u64
    if kind == RESULT_CHANGED_ROWS { changed = 1u64 }
    // Every result is drained, not only the ones that answer rows: v2 documents that a
    // side-effecting statement takes effect only once its result has been drained, and that
    // destroying an unfinished result may roll its writes back. `result_drain` does that and
    // answers the rows the statement changed, which is what `e.db` asks for.
    var rows_changed = 0usize
    var quiet_drain: [1]usize = zero
    let drained = v2.result_drain(result, &rows_changed, &quiet_drain[0usize])
    if drained != v2.DUCKDB_SUCCESS {
        let failed = failure(c, drained, "DuckDB could not finish the statement")
        let _ = v2.result_destroy(&result)
        mem.reset(c.arena, mark)
        ret (0u64, failed)
    }
    let _ = v2.result_destroy(&result)
    mem.reset(c.arena, mark)
    clear_detail(c)
    ret (u64(rows_changed), ok)
}

// Reads every chunk of `result` and frees it, so the statement finishes.
fn drain(c: *Conn, result: usize) -> err {
    while true {
        var chunk = 0usize
        var slot: [1]usize = zero
        let fetched = v2.result_fetch_chunk(result, &chunk, &slot[0usize])
        if fetched != v2.DUCKDB_SUCCESS {
            var note = v2.Str { ptr: nil, len: 0usize }
            if slot[0usize] != 0usize { let _ = v2.error_info_get_text(slot[0usize], &note) }
            let shown = view_of(note)
            ret fail_info(c, fetched, slot[0usize])
        }
        if chunk == 0usize { ret ok }
        let _ = v2.data_chunk_destroy(&chunk)
    }
}

// Parses `sql`, prepares its one statement, and answers the prepared statement, the parsed
// statement behind it, and the iterator: a second statement is `db.InvalidQuery`, and a text
// that holds none is too. A trailing `;` or comment is neither.
//
// All three are answered together because v2 says a statement taken from an iterator is valid
// only while that iterator lives. Preparing happens here, before the caller can drop the
// iterator, and the iterator is answered so the caller destroys it last. The parsed statement is
// answered too: the parameter names a bind needs live on it.
fn compile_one(c: *Conn, sql: str) -> (usize, usize, usize, err) {
    let mark = mem.mark(c.arena)
    let (bytes, bytes_error) = c_copy(c.arena, sql)
    if bytes_error != ok {
        mem.reset(c.arena, mark)
        ret (0usize, 0usize, 0usize, bytes_error)
    }
    var iterator = 0usize
    var slot: [1]usize = zero
    let parsed = v2.parse_sql(c.handle, &bytes[0usize], &iterator, &slot[0usize])
    if parsed != v2.DUCKDB_SUCCESS {
        let failed = fail_info(c, parsed, slot[0usize])
        mem.reset(c.arena, mark)
        ret (0usize, 0usize, 0usize, failed)
    }
    var statement = 0usize
    let found = v2.statement_iterator_next(iterator, &statement, &slot[0usize])
    if found != v2.DUCKDB_SUCCESS {
        let failed = fail_info(c, found, slot[0usize])
        let _ = v2.statement_iterator_destroy(&iterator)
        mem.reset(c.arena, mark)
        ret (0usize, 0usize, 0usize, failed)
    }
    if statement == 0usize {
        let _ = v2.statement_iterator_destroy(&iterator)
        mem.reset(c.arena, mark)
        ret (0usize, 0usize, 0usize, refuse(c, "the SQL text holds no statement", db.InvalidQuery))
    }
    var second = 0usize
    var quiet3: [1]usize = zero
    let more = v2.statement_iterator_next(iterator, &second, &quiet3[0usize])
    if more == v2.DUCKDB_SUCCESS && second != 0usize {
        let _ = v2.sql_statement_destroy(&second)
        let _ = v2.sql_statement_destroy(&statement)
        let _ = v2.statement_iterator_destroy(&iterator)
        mem.reset(c.arena, mark)
        ret (0usize, 0usize, 0usize, refuse(c, "the SQL text holds more than one statement", db.InvalidQuery))
    }
    var prepared = 0usize
    let compiled = v2.prepared_statement_create(c.handle, statement, 0u8, &prepared, &quiet3[0usize])
    if compiled != v2.DUCKDB_SUCCESS {
        let failed = fail_info(c, compiled, quiet3[0usize])
        let _ = v2.sql_statement_destroy(&statement)
        let _ = v2.statement_iterator_destroy(&iterator)
        mem.reset(c.arena, mark)
        ret (0usize, 0usize, 0usize, failed)
    }
    mem.reset(c.arena, mark)
    ret (prepared, statement, iterator, ok)
}

// A prepared statement that has not run yet: `prepare` compiles the text here, so a statement
// that cannot run fails at `prepare` rather than at its first execution. `compile_one` has
// already prepared it; the iterator is answered too, because the parsed statement's parameter
// names stay valid only while it lives, and the caller keeps both until `close_statement`.
fn compile_prepared(c: *Conn, sql: str) -> (usize, usize, usize, err) {
    let (prepared, statement, iterator, compile_error) = compile_one(c, sql)
    if compile_error != ok { ret (0usize, 0usize, 0usize, compile_error) }
    ret (prepared, statement, iterator, ok)
}

// --- row readers

fn is_integer_type(t: i32) -> bool {
    ret t == TYPE_TINYINT || t == TYPE_SMALLINT || t == TYPE_INTEGER || t == TYPE_BIGINT || t == TYPE_UTINYINT || t == TYPE_USMALLINT || t == TYPE_UINTEGER || t == TYPE_UBIGINT
}

fn is_timestamp_type(t: i32) -> bool {
    ret t == TYPE_TIMESTAMP || t == TYPE_TIMESTAMP_S || t == TYPE_TIMESTAMP_MS || t == TYPE_TIMESTAMP_NS || t == TYPE_TIMESTAMP_TZ || t == TYPE_TIMESTAMP_TZ_NS
}

fn is_nested_type(t: i32) -> bool {
    ret t == TYPE_STRUCT || t == TYPE_LIST || t == TYPE_MAP || t == TYPE_ARRAY || t == TYPE_UNION || t == TYPE_VARIANT || t == TYPE_TUPLE || t == TYPE_BIT
}

// The kind a column of logical type `t` arrives as.
fn kind_of(t: i32) -> db.ValueKind {
    if t == TYPE_BOOLEAN { ret .Bool }
    if is_integer_type(t) { ret .I64 }
    if t == TYPE_FLOAT || t == TYPE_DOUBLE { ret .F64 }
    if is_timestamp_type(t) { ret .Time }
    if t == TYPE_VARCHAR || t == TYPE_ENUM || t == TYPE_UUID { ret .Text }
    if t == TYPE_DECIMAL || t == TYPE_HUGEINT || t == TYPE_UHUGEINT || t == TYPE_BIGNUM { ret .Text }
    if t == TYPE_DATE || t == TYPE_TIME || t == TYPE_TIME_NS || t == TYPE_TIME_TZ || t == TYPE_INTERVAL { ret .Text }
    if t == TYPE_BLOB { ret .Bytes }
    if is_nested_type(t) { ret .Bytes }
    ret .Null
}

// Runs one statement with `params` and answers a reader over its rows, its columns known before
// any row is read. The statement is compiled here and freed when the reader closes.
fn start_reader(c: *Conn, sql: str, params: []const db.Parameter, statement: *Stmt) -> (db.Rows, err) {
    var rows: db.Rows = zero
    let (prepared0, parsed0, iterator0, compile_error) = compile_prepared(c, sql)
    if compile_error != ok { ret (rows, compile_error) }
    var prepared = prepared0
    var parsed = parsed0
    var iterator = iterator0
    let mark = mem.mark(c.arena)
    let (names, values, made, bind_error) = bind_arrays(c, parsed, params)
    if bind_error != ok {
        var k = 0usize
        while k < made {
            let _ = v2.value_destroy(&values[k])
            k += 1usize
        }
        let _ = v2.prepared_statement_destroy(&prepared)
        let _ = v2.sql_statement_destroy(&parsed)
        let _ = v2.statement_iterator_destroy(&iterator)
        mem.reset(c.arena, mark)
        ret (rows, bind_error)
    }
    var result = 0usize
    var slot: [1]usize = zero
    let executed = v2.prepared_statement_execute(prepared, names_pointer(names), values_pointer(values), params.len, &result, &slot[0usize])
    var k = 0usize
    while k < made {
        let _ = v2.value_destroy(&values[k])
        k += 1usize
    }
    let _ = v2.prepared_statement_destroy(&prepared)
    let _ = v2.sql_statement_destroy(&parsed)
    let _ = v2.statement_iterator_destroy(&iterator)
    if executed != v2.DUCKDB_SUCCESS {
        let failed = fail_info(c, executed, slot[0usize])
        mem.reset(c.arena, mark)
        ret (rows, failed)
    }
    var kind = 0i32
    var quiet4: [1]usize = zero
    let typed = v2.result_get_result_type(result, &kind, &quiet4[0usize])
    if typed != v2.DUCKDB_SUCCESS {
        let _ = v2.result_destroy(&result)
        mem.reset(c.arena, mark)
        ret (rows, failure(c, typed, "DuckDB did not say what kind of result it answered"))
    }
    if kind != RESULT_QUERY {
        // A statement that answers no rows: drained here, and a reader over it is refused.
        let drained = drain(c, result)
        let _ = v2.result_destroy(&result)
        mem.reset(c.arena, mark)
        if drained != ok { ret (rows, drained) }
        ret (rows, refuse(c, "the statement answers no rows", db.InvalidQuery))
    }
    var schema = 0usize
    var quiet5: [1]usize = zero
    let read_schema = v2.result_get_schema(result, &schema, &quiet5[0usize])
    if read_schema != v2.DUCKDB_SUCCESS {
        let _ = v2.result_destroy(&result)
        mem.reset(c.arena, mark)
        ret (rows, failure(c, read_schema, "DuckDB did not describe the result"))
    }
    var columns = 0usize
    var quiet6: [1]usize = zero
    let counted = v2.schema_get_count(schema, &columns, &quiet6[0usize])
    if counted != v2.DUCKDB_SUCCESS {
        let _ = v2.result_destroy(&result)
        mem.reset(c.arena, mark)
        ret (rows, failure(c, counted, "DuckDB did not count the result's columns"))
    }
    let (readers, reader_error) = mem.alloc[Reader](c.arena, 1usize)
    let (types, types_error) = mem.alloc[i32](c.arena, columns)
    let (cols, cols_error) = mem.alloc[db.Column](c.arena, columns)
    if reader_error != ok || types_error != ok || cols_error != ok {
        let _ = v2.result_destroy(&result)
        mem.reset(c.arena, mark)
        ret (rows, db.Unsupported)
    }
    var column = 0usize
    while column < columns {
        var name = v2.Str { ptr: nil, len: 0usize }
        var logical = 0usize
        var quiet7: [1]usize = zero
        let field = v2.schema_get_field(schema, column, &name, &logical, &quiet7[0usize])
        if field != v2.DUCKDB_SUCCESS {
            let _ = v2.result_destroy(&result)
            mem.reset(c.arena, mark)
            ret (rows, failure(c, field, "DuckDB did not describe a column"))
        }
        var type_id = 0i32
        var quiet8: [1]usize = zero
        let identified = v2.logical_type_get_id(logical, &type_id, &quiet8[0usize])
        let _ = v2.logical_type_destroy(&logical)
        if identified != v2.DUCKDB_SUCCESS {
            let _ = v2.result_destroy(&result)
            mem.reset(c.arena, mark)
            ret (rows, failure(c, identified, "DuckDB did not name a column's type"))
        }
        types[column] = type_id
        cols[column] = db.Column { name: copy_view(c.arena, name), kind: kind_of(type_id), nullable: true }
        column += 1usize
    }
    var no_buffer: []u8 = zero
    // Arena memory is not cleared, so every field is written.
    readers[0usize] = Reader { conn: c, statement: statement, handle: result, chunk: 0usize, rows: 0usize, at: 0usize, done: false, closed: false, types: types, columns: cols, buffer: no_buffer, used: 0usize, borrow: false, held: 0usize }
    let r = &readers[0usize]
    c.active = r
    clear_detail(c)
    rows.ctx = mem.cast[*void](r)
    ret (rows, ok)
}

// A reader over a result that has already been executed: its schema is read here, so a reader
// built by either path knows its columns before any row is read. The result is the reader's
// from here on, and the statement it came from is not, so `statement` is for a reader over a
// prepared statement and `nil` for one this module compiled.
fn reader_for(c: *Conn, result0: usize, statement: *Stmt) -> (db.Rows, err) {
    var rows: db.Rows = zero
    var result = result0
    var schema = 0usize
    var quiet_schema: [1]usize = zero
    let read_schema = v2.result_get_schema(result, &schema, &quiet_schema[0usize])
    if read_schema != v2.DUCKDB_SUCCESS {
        let failed = failure(c, read_schema, "DuckDB did not describe the result")
        let _ = v2.result_destroy(&result)
        ret (rows, failed)
    }
    var columns = 0usize
    var quiet_count: [1]usize = zero
    let counted = v2.schema_get_count(schema, &columns, &quiet_count[0usize])
    if counted != v2.DUCKDB_SUCCESS {
        let failed = failure(c, counted, "DuckDB did not count the result's columns")
        let _ = v2.result_destroy(&result)
        ret (rows, failed)
    }
    let (readers, reader_error) = mem.alloc[Reader](c.arena, 1usize)
    let (types, types_error) = mem.alloc[i32](c.arena, columns)
    let (cols, cols_error) = mem.alloc[db.Column](c.arena, columns)
    if reader_error != ok || types_error != ok || cols_error != ok {
        let _ = v2.result_destroy(&result)
        ret (rows, db.Unsupported)
    }
    var column = 0usize
    while column < columns {
        var name = v2.Str { ptr: nil, len: 0usize }
        var logical = 0usize
        var quiet_field: [1]usize = zero
        let field = v2.schema_get_field(schema, column, &name, &logical, &quiet_field[0usize])
        if field != v2.DUCKDB_SUCCESS {
            let failed = failure(c, field, "DuckDB did not describe a column")
            let _ = v2.result_destroy(&result)
            ret (rows, failed)
        }
        var type_id = 0i32
        var quiet_type: [1]usize = zero
        let identified = v2.logical_type_get_id(logical, &type_id, &quiet_type[0usize])
        let _ = v2.logical_type_destroy(&logical)
        if identified != v2.DUCKDB_SUCCESS {
            let failed = failure(c, identified, "DuckDB did not name a column's type")
            let _ = v2.result_destroy(&result)
            ret (rows, failed)
        }
        types[column] = type_id
        cols[column] = db.Column { name: copy_view(c.arena, name), kind: kind_of(type_id), nullable: true }
        column += 1usize
    }
    var no_buffer: []u8 = zero
    readers[0usize] = Reader { conn: c, statement: statement, handle: result, chunk: 0usize, rows: 0usize, at: 0usize, done: false, closed: false, types: types, columns: cols, buffer: no_buffer, used: 0usize, borrow: false, held: 0usize }
    let r = &readers[0usize]
    c.active = r
    clear_detail(c)
    rows.ctx = mem.cast[*void](r)
    ret (rows, ok)
}

// Room for `n` more bytes of this row. A grown buffer is a new one: the values already filled
// keep pointing at the old, which the arena still holds.
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

// `n` bytes of the reader's buffer for this row.
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

// The `duckdb_value` the current row holds in `vector`, owned by the reader until its next row;
// `0` when the row is NULL or DuckDB would not hand the value out.
fn row_value(r: *Reader, vector: usize) -> usize {
    if r.held != 0usize {
        let _ = v2.value_destroy(&r.held)
        r.held = 0usize
    }
    var value = 0usize
    var slot: [1]usize = zero
    let got = v2.vector_get_value(vector, r.at, &value, &slot[0usize])
    if got != v2.DUCKDB_SUCCESS {
        if slot[0usize] != 0usize { let _ = v2.error_info_destroy(&slot[0usize]) }
        ret 0usize
    }
    r.held = value
    ret value
}

// A text or blob at the current row, copied into the reader's buffer.
fn text_value(r: *Reader, value: usize, blob: bool) -> ([]const u8, err) {
    var nothing: []const u8 = zero
    var text = v2.Str { ptr: nil, len: 0usize }
    var got = 0i32
    if blob {
        got = v2.value_get_blob(value, &text, a_quiet_slot())
    } else {
        got = v2.value_get_varchar(value, &text, a_quiet_slot())
    }
    if got != v2.DUCKDB_SUCCESS { ret (nothing, ok) }
    let (out, take_error) = take(r, view_of(text))
    ret (out, take_error)
}

fn integer_value(value: usize, t: i32) -> db.Value {
    var wide = 0i64
    var quiet9: [1]usize = zero
    let got = v2.value_get_bigint(value, &wide, &quiet9[0usize])
    if got != v2.DUCKDB_SUCCESS { ret db.Value{ I64: 0i64 } }
    if t == TYPE_UBIGINT && wide < 0i64 { ret db.Value{ U64: u64(wide) } }
    ret db.Value{ I64: wide }
}

// Fills one row. A NULL column is `Null`; everything else is read through the value the reader
// holds.
fn fill(r: *Reader, dst: []db.Value) -> err {
    r.used = 0usize
    var i = 0usize
    while i < r.columns.len {
        var vector = 0usize
        var slot: [1]usize = zero
        let got_vector = v2.data_chunk_get_vector(r.chunk, i, &vector, &slot[0usize])
        if got_vector != v2.DUCKDB_SUCCESS {
            if slot[0usize] != 0usize { let _ = v2.error_info_destroy(&slot[0usize]) }
            dst[i] = .Null
            i += 1usize
            continue
        }
        let value = row_value(r, vector)
        if value == 0usize {
            dst[i] = .Null
            i += 1usize
            continue
        }
        // A NULL cell still hands back a value; the value is what says it is NULL.
        var is_null = 0u8
        var quiet_null: [1]usize = zero
        if v2.value_is_null(value, &is_null, &quiet_null[0usize]) == v2.DUCKDB_SUCCESS && is_null != 0u8 {
            dst[i] = .Null
            i += 1usize
            continue
        }
        let t = r.types[i]
        if t == TYPE_BOOLEAN {
            // A BOOLEAN reads through the integer accessor as 0 or 1.
            var flag = 0i64
            var quiet10: [1]usize = zero
            let got_flag = v2.value_get_bigint(value, &flag, &quiet10[0usize])
            var truth = false
            if got_flag == v2.DUCKDB_SUCCESS && flag != 0i64 { truth = true }
            dst[i] = db.Value{ Bool: truth }
        } else if is_integer_type(t) {
            dst[i] = integer_value(value, t)
        } else if t == TYPE_FLOAT || t == TYPE_DOUBLE {
            var real = 0.0f64
            var quiet11: [1]usize = zero
            let got_real = v2.value_get_double(value, &real, &quiet11[0usize])
            if got_real != v2.DUCKDB_SUCCESS {
                dst[i] = .Null
                i += 1usize
                continue
            }
            dst[i] = db.Value{ F64: real }
        } else if is_timestamp_type(t) {
            var micros = 0i64
            var quiet12: [1]usize = zero
            let got_micros = v2.value_get_timestamp(value, &micros, &quiet12[0usize])
            let nanosecond_type = t == TYPE_TIMESTAMP_NS || t == TYPE_TIMESTAMP_TZ_NS
            if got_micros != v2.DUCKDB_SUCCESS || nanosecond_type {
                let (text, text_error) = text_value(r, value, false)
                if text_error != ok { ret text_error }
                let spelled: str = text
                dst[i] = db.Value{ Text: spelled }
            } else {
                dst[i] = db.Value{ Time: time.Instant { nanos: saturating_mul(micros, 1000i64) } }
            }
        } else if t == TYPE_BLOB {
            let (data, blob_error) = text_value(r, value, true)
            if blob_error != ok { ret blob_error }
            dst[i] = db.Value{ Bytes: data }
        } else if is_nested_type(t) {
            let (data, nested_error) = text_value(r, value, true)
            if nested_error != ok { ret nested_error }
            let bytes: []const u8 = data
            dst[i] = db.Value{ Bytes: bytes }
        } else if t == TYPE_SQLNULL {
            dst[i] = .Null
        } else {
            let (text, text_error) = text_value(r, value, false)
            if text_error != ok { ret text_error }
            let spelled: str = text
            dst[i] = db.Value{ Text: spelled }
        }
        i += 1usize
    }
    ret ok
}

// `v * factor`, or the end of `i64` rather than a wrapped one.
fn saturating_mul(v: i64, factor: i64) -> i64 {
    if v > 0i64 && v > I64_MAX / factor { ret I64_MAX }
    if v < 0i64 && v < I64_MIN / factor { ret I64_MIN }
    ret v * factor
}

fn next_row(r: *Reader, dst: []db.Value) -> (bool, err) {
    if r.closed { ret (false, db.Closed) }
    if dst.len < r.columns.len { ret (false, refuse(r.conn, "the row buffer is shorter than the row", db.InvalidQuery)) }
    if r.done { ret (false, ok) }
    if r.at >= r.rows {
        if r.chunk != 0usize {
            let _ = v2.data_chunk_destroy(&r.chunk)
            r.chunk = 0usize
        }
        var chunk = 0usize
        var quiet13: [1]usize = zero
        let fetched = v2.result_fetch_chunk(r.handle, &chunk, &quiet13[0usize])
        r.at = 0usize
        r.rows = 0usize
        if fetched != v2.DUCKDB_SUCCESS {
            r.done = true
            ret (false, failure(r.conn, fetched, "DuckDB could not produce the next chunk"))
        }
        if chunk == 0usize {
            r.done = true
            ret (false, ok)
        }
        var size = 0usize
        var quiet14: [1]usize = zero
        let sized = v2.data_chunk_get_size(chunk, &size, &quiet14[0usize])
        if sized != v2.DUCKDB_SUCCESS {
            let _ = v2.data_chunk_destroy(&chunk)
            r.done = true
            ret (false, failure(r.conn, sized, "DuckDB did not size a chunk"))
        }
        r.chunk = chunk
        r.rows = size
        if size == 0usize {
            r.done = true
            ret (false, ok)
        }
    }
    let fill_error = fill(r, dst)
    if fill_error != ok { ret (false, fill_error) }
    r.at += 1usize
    ret (true, ok)
}

fn finish_reader(r: *Reader) {
    if r.closed { ret }
    r.closed = true
    r.done = true
    if r.held != 0usize {
        let _ = v2.value_destroy(&r.held)
        r.held = 0usize
    }
    if r.chunk != 0usize {
        let _ = v2.data_chunk_destroy(&r.chunk)
        r.chunk = 0usize
    }
    if r.handle != 0usize {
        // v2 refuses the next statement on a connection whose previous result is still open,
        // so a reader closed before its end reads and discards what is left first.
        var left = 0usize
        var slot: [1]usize = zero
        while true {
            let fetched = v2.result_fetch_chunk(r.handle, &left, &slot[0usize])
            if fetched != v2.DUCKDB_SUCCESS { break }
            if left == 0usize { break }
            let _ = v2.data_chunk_destroy(&left)
        }
        var handle = r.handle
        let _ = v2.result_destroy(&handle)
        r.handle = 0usize
    }
    if r.conn.active == r { r.conn.active = nil }
}

// --- the driver table

fn d_close(ctx: *void) -> err {
    let c = conn_of(ctx)
    if c.active != nil { finish_reader(c.active) }
    var handle = c.handle
    var instance = c.instance
    var environment = c.environment
    let _ = v2.connection_destroy(&handle)
    let _ = v2.instance_destroy(&instance)
    let _ = v2.environment_destroy(&environment)
    ret ok
}

fn d_prepare(ctx: *void, sql: str) -> (db.Statement, err) {
    let c = conn_of(ctx)
    var statement: db.Statement = zero
    let (prepared0, parsed_statement, iterator0, compile_error) = compile_prepared(c, sql)
    if compile_error != ok { ret (statement, compile_error) }
    var prepared = prepared0
    var iterator = iterator0
    let (stmts, stmt_error) = mem.alloc[Stmt](c.arena, 1usize)
    if stmt_error != ok {
        var dropped = prepared
        let _ = v2.prepared_statement_destroy(&dropped)
        var dropped_parsed = parsed_statement
        let _ = v2.sql_statement_destroy(&dropped_parsed)
        let _ = v2.statement_iterator_destroy(&iterator)
        ret (statement, stmt_error)
    }
    stmts[0usize] = Stmt { conn: c, handle: prepared, parsed: parsed_statement, iterator: iterator, closed: false }
    clear_detail(c)
    statement.ctx = mem.cast[*void](&stmts[0usize])
    ret (statement, ok)
}

fn d_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = execute_text(conn_of(ctx), sql, params)
    ret (affected, execute_error)
}

fn d_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, rows_error) = start_reader(conn_of(ctx), sql, params, nil)
    ret (rows, rows_error)
}

// One transaction at a time on a connection: DuckDB has no nesting under BEGIN.
fn d_begin(ctx: *void) -> (db.Transaction, err) {
    let c = conn_of(ctx)
    var transaction: db.Transaction = zero
    if c.in_transaction { ret (transaction, refuse(c, "a transaction is already open on this connection", db.Busy)) }
    let (ignored, begin_error) = run_sql(c, "BEGIN TRANSACTION", zero)
    if begin_error != ok { ret (transaction, begin_error) }
    c.in_transaction = true
    // The transaction record is allocated after every statement that could reset the arena, so
    // nothing the transaction goes on to run can reclaim it.
    let (txs, tx_error) = mem.alloc[Tx](c.arena, 1usize)
    if tx_error != ok {
        let (undone, undo_error) = run_sql(c, "ROLLBACK", zero)
        c.in_transaction = false
        ret (transaction, tx_error)
    }
    txs[0usize] = Tx { conn: c }
    transaction.ctx = mem.cast[*void](&txs[0usize])
    ret (transaction, ok)
}

fn d_statement_close(ctx: *void) -> err {
    let s = stmt_of(ctx)
    if s.handle != 0usize {
        var dropped = s.handle
        let _ = v2.prepared_statement_destroy(&dropped)
        s.handle = 0usize
    }
    // The parsed statement and its iterator go last, in the order the API requires: the
    // statement is answered from the iterator, so it is destroyed first.
    if s.parsed != 0usize {
        var dropped_parsed = s.parsed
        let _ = v2.sql_statement_destroy(&dropped_parsed)
        s.parsed = 0usize
    }
    if s.iterator != 0usize {
        var dropped_iterator = s.iterator
        let _ = v2.statement_iterator_destroy(&dropped_iterator)
        s.iterator = 0usize
    }
    s.closed = true
    ret ok
}

fn d_statement_execute(ctx: *void, params: []const db.Parameter) -> (u64, err) {
    let s = stmt_of(ctx)
    if s.closed { ret (0u64, db.Closed) }
    let (affected, run_error) = run_prepared(s.conn, s.handle, s.parsed, params)
    ret (affected, run_error)
}

fn d_statement_query(ctx: *void, params: []const db.Parameter) -> (db.Rows, err) {
    let s = stmt_of(ctx)
    if s.closed { ret (zero, db.Closed) }
    let (rows, rows_error) = start_prepared_reader(s, params)
    ret (rows, rows_error)
}

// A reader over a statement `prepare` already compiled, which is not freed by the reader.
fn start_prepared_reader(s: *Stmt, params: []const db.Parameter) -> (db.Rows, err) {
    var rows: db.Rows = zero
    let c = s.conn
    let mark = mem.mark(c.arena)
    let (names, values, made, bind_error) = bind_arrays(c, s.parsed, params)
    if bind_error != ok {
        var k = 0usize
        while k < made {
            let _ = v2.value_destroy(&values[k])
            k += 1usize
        }
        mem.reset(c.arena, mark)
        ret (rows, bind_error)
    }
    var result = 0usize
    var slot: [1]usize = zero
    let executed = v2.prepared_statement_execute(s.handle, names_pointer(names), values_pointer(values), params.len, &result, &slot[0usize])
    var k = 0usize
    while k < made {
        let _ = v2.value_destroy(&values[k])
        k += 1usize
    }
    if executed != v2.DUCKDB_SUCCESS {
        let failed = fail_info(c, executed, slot[0usize])
        mem.reset(c.arena, mark)
        ret (rows, failed)
    }
    // The statement is not the reader's to free, so it is not recorded on the reader either. The
    // arena is not reset past this point: the reader, its columns and its types live there.
    let (ready, ready_error) = reader_for(c, result, nil)
    if ready_error != ok { ret (rows, ready_error) }
    ret (ready, ok)
}

fn d_rows_columns(ctx: *void) -> []const db.Column { ret reader_of(ctx).columns }

fn d_rows_next(ctx: *void, dst: []db.Value) -> (bool, err) {
    let (more, next_error) = next_row(reader_of(ctx), dst)
    ret (more, next_error)
}

// v2 hands out an owned value per cell rather than a pointer into the chunk, so there is
// nothing to borrow: this is the same read.
fn d_rows_next_borrowed(ctx: *void, dst: []db.Value) -> (bool, err) {
    let (more, next_error) = next_row(reader_of(ctx), dst)
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
    let (rows, rows_error) = start_reader(tx_of(ctx).conn, sql, params, nil)
    ret (rows, rows_error)
}

// A COMMIT that fails is rolled back, because `e.db` has already closed the transaction's
// handle.
fn d_transaction_commit(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    let (ignored, commit_error) = run_sql(c, "COMMIT", zero)
    if commit_error != ok {
        let (undone, undo_error) = run_sql(c, "ROLLBACK", zero)
    }
    c.in_transaction = false
    ret commit_error
}

fn d_transaction_rollback(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    let (ignored, rollback_error) = run_sql(c, "ROLLBACK", zero)
    c.in_transaction = false
    ret rollback_error
}