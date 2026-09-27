// The MySQL C API as `x.oracle.mysql` uses it, bound to `libmysql.dll` (the client library the
// MySQL Windows archive puts in `lib/`, with the OpenSSL it needs in `bin/`; both on PATH).
//
// This variant and the Linux one export the same surface, but not the same declarations:
// C's `unsigned long` is 32 bits on Windows and 64 on Linux, so the raw externs that take or
// answer one are private to each variant, wrapped in functions that speak `usize`, and the
// offsets into `MYSQL_FIELD` (which holds two of them) are constants of each variant.
use e.mem

// `MYSQL_FIELD`: seven pointers, then `length` and `max_length` (4 bytes each here), then
// seven `unsigned int` lengths, then `flags`, `decimals`, `charsetnr` and `type`.
const FIELD_NAME: usize = 0usize
const FIELD_LENGTH: usize = 56usize
const FIELD_NAME_LENGTH: usize = 64usize
const FIELD_FLAGS: usize = 92usize
const FIELD_CHARSETNR: usize = 100usize
const FIELD_TYPE: usize = 104usize
const ULONG_BYTES: usize = 4usize

@import("libmysql.dll", "mysql_get_client_version")
extern fn raw_client_version() -> u32

@import("libmysql.dll", "mysql_init")
extern fn init(mysql: usize) -> usize

@import("libmysql.dll", "mysql_options")
extern fn options(mysql: usize, option: i32, arg: *const u8) -> i32

@import("libmysql.dll", "mysql_real_connect")
extern fn raw_real_connect(mysql: usize, host: usize, user: usize, password: usize, database: usize, port: u32, socket: usize, flags: u32) -> usize

@import("libmysql.dll", "mysql_close")
extern fn close(mysql: usize)

@import("libmysql.dll", "mysql_errno")
extern fn errno(mysql: usize) -> u32

@import("libmysql.dll", "mysql_error")
extern fn error_text(mysql: usize) -> *u8

@import("libmysql.dll", "mysql_sqlstate")
extern fn sqlstate(mysql: usize) -> *u8

@import("libmysql.dll", "mysql_real_query")
extern fn raw_real_query(mysql: usize, query: *const u8, length: u32) -> i32

@import("libmysql.dll", "mysql_use_result")
extern fn use_result(mysql: usize) -> usize

@import("libmysql.dll", "mysql_field_count")
extern fn field_count(mysql: usize) -> u32

@import("libmysql.dll", "mysql_affected_rows")
extern fn affected_rows(mysql: usize) -> u64

@import("libmysql.dll", "mysql_next_result")
extern fn next_result(mysql: usize) -> i32

@import("libmysql.dll", "mysql_num_fields")
extern fn num_fields(result: usize) -> u32

@import("libmysql.dll", "mysql_fetch_field_direct")
extern fn fetch_field_direct(result: usize, index: u32) -> *u8

@import("libmysql.dll", "mysql_fetch_row")
extern fn fetch_row(result: usize) -> *u8

@import("libmysql.dll", "mysql_fetch_lengths")
extern fn fetch_lengths(result: usize) -> *u8

@import("libmysql.dll", "mysql_free_result")
extern fn free_result(result: usize)

@import("libmysql.dll", "mysql_real_escape_string")
extern fn raw_real_escape_string(mysql: usize, to: *u8, from: *const u8, length: u32) -> u32

fn client_version() -> usize { ret usize(raw_client_version()) }

fn real_connect(mysql: usize, host: usize, user: usize, password: usize, database: usize, port: u32, socket: usize, flags: usize) -> usize {
    ret raw_real_connect(mysql, host, user, password, database, port, socket, u32.trunc(flags))
}

// Lengths past what an `unsigned long` holds here never reach the library: callers check.
fn real_query(mysql: usize, query: *const u8, length: usize) -> i32 {
    ret raw_real_query(mysql, query, u32.trunc(length))
}

fn real_escape_string(mysql: usize, to: *u8, from: *const u8, length: usize) -> usize {
    ret usize(raw_real_escape_string(mysql, to, from, u32.trunc(length)))
}

// The largest length a call here accepts.
fn max_length() -> usize { ret 4294967295usize }

// Element `index` of the `unsigned long` array `mysql_fetch_lengths` answers.
fn length_at(lengths: *u8, index: usize) -> usize {
    ret length_at_offset(lengths, index * ULONG_BYTES)
}

// `MYSQL_FIELD.length`, the column's declared display width.
fn field_length(field: *u8) -> usize { ret length_at_offset(field, FIELD_LENGTH) }

fn length_at_offset(base: *u8, offset: usize) -> usize {
    var region: mem.Arena = zero
    region.base = base
    region.cap = offset + ULONG_BYTES
    region.off = 0usize
    let bytes = mem.view(&region, offset, ULONG_BYTES)
    ret usize(bytes[0usize]) | usize(bytes[1usize]) << 8usize | usize(bytes[2usize]) << 16usize | usize(bytes[3usize]) << 24usize
}
