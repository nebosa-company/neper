// The DuckDB C API as `x.duckdb.duckdb` uses it, bound to `duckdb.dll` (the published
// `duckdb-shared-libs-*` archive; unpacked under `D:\tools\duckdb` on this host). The library is
// C++ inside but its C API is `extern "C"` and exported unmangled. The Linux variant differs
// only in the library name; every declaration below must stay identical to it.
//
// Handles cross as addresses (`usize`): a database, a connection, a prepared statement, a
// data chunk, a vector. `idx_t`, `uint64_t` and `size_t` are all 64 bits here, so every length
// and index crosses as `usize`.
//
// `duckdb_result` is a 48-byte C struct: the three deprecated column and row counters, the
// deprecated columns and error message, and -- the one field a v2 library really uses -- the
// address of the result's own state. Every call that takes a result takes a pointer to these
// 48 bytes; nothing here reads past the first three, which only ever need to be zero.
//
// `duckdb_string_t` is 16 bytes: a length and then either twelve inline characters or a prefix
// and a pointer. `duckdb_hugeint` and `duckdb_timestamp` are 16 and 8, and a one-field C struct
// crosses as its field, so a timestamp is a plain `i64` here.

@import("duckdb.dll", "duckdb_library_version")
extern fn library_version() -> *u8

@import("duckdb.dll", "duckdb_open")
extern fn open(path: *const u8, database: *usize) -> i32

@import("duckdb.dll", "duckdb_close")
extern fn close(database: *usize) -> void

@import("duckdb.dll", "duckdb_connect")
extern fn connect(database: usize, connection: *usize) -> i32

@import("duckdb.dll", "duckdb_disconnect")
extern fn disconnect(connection: *usize) -> void

@import("duckdb.dll", "duckdb_query")
extern fn query(connection: usize, sql: *const u8, result: *Result) -> i32

@import("duckdb.dll", "duckdb_destroy_result")
extern fn destroy_result(result: *Result) -> void

@import("duckdb.dll", "duckdb_result_error")
extern fn result_error(result: *Result) -> *u8

@import("duckdb.dll", "duckdb_result_error_type")
extern fn result_error_type(result: *Result) -> i32

@import("duckdb.dll", "duckdb_result_return_type")
extern fn result_return_type(result: *const Result) -> i32

@import("duckdb.dll", "duckdb_column_count")
extern fn column_count(result: *Result) -> usize

@import("duckdb.dll", "duckdb_column_name")
extern fn column_name(result: *Result, column: usize) -> *u8

@import("duckdb.dll", "duckdb_column_type")
extern fn column_type(result: *Result, column: usize) -> i32

@import("duckdb.dll", "duckdb_column_logical_type")
extern fn column_logical_type(result: *Result, column: usize) -> usize

@import("duckdb.dll", "duckdb_decimal_scale")
extern fn decimal_scale(logical: usize) -> u8

@import("duckdb.dll", "duckdb_enum_internal_type")
extern fn enum_internal_type(logical: usize) -> i32

@import("duckdb.dll", "duckdb_destroy_logical_type")
extern fn destroy_logical_type(logical: *usize) -> void

@import("duckdb.dll", "duckdb_fetch_chunk")
extern fn fetch_chunk(result: *Result) -> usize

@import("duckdb.dll", "duckdb_destroy_data_chunk")
extern fn destroy_data_chunk(chunk: *usize) -> void

@import("duckdb.dll", "duckdb_data_chunk_get_size")
extern fn data_chunk_get_size(chunk: usize) -> usize

@import("duckdb.dll", "duckdb_data_chunk_get_column_count")
extern fn data_chunk_get_column_count(chunk: usize) -> usize

@import("duckdb.dll", "duckdb_data_chunk_get_vector")
extern fn data_chunk_get_vector(chunk: usize, column: usize) -> usize

@import("duckdb.dll", "duckdb_vector_get_data")
extern fn vector_get_data(vector: usize) -> usize

@import("duckdb.dll", "duckdb_vector_get_validity")
extern fn vector_get_validity(vector: usize) -> *u64

@import("duckdb.dll", "duckdb_prepare")
extern fn prepare(connection: usize, sql: *const u8, statement: *usize) -> i32

@import("duckdb.dll", "duckdb_destroy_prepare")
extern fn destroy_prepare(statement: *usize) -> void

@import("duckdb.dll", "duckdb_prepare_error")
extern fn prepare_error(statement: usize) -> *u8

@import("duckdb.dll", "duckdb_nparams")
extern fn nparams(statement: usize) -> usize

@import("duckdb.dll", "duckdb_bind_parameter_index")
extern fn bind_parameter_index(statement: usize, index: *usize, name: *const u8) -> i32

@import("duckdb.dll", "duckdb_parameter_name")
extern fn parameter_name(statement: usize, index: usize) -> *u8

@import("duckdb.dll", "duckdb_clear_bindings")
extern fn clear_bindings(statement: usize) -> i32

@import("duckdb.dll", "duckdb_bind_null")
extern fn bind_null(statement: usize, index: usize) -> i32

@import("duckdb.dll", "duckdb_bind_boolean")
extern fn bind_boolean(statement: usize, index: usize, value: u8) -> i32

@import("duckdb.dll", "duckdb_bind_int64")
extern fn bind_int64(statement: usize, index: usize, value: i64) -> i32

@import("duckdb.dll", "duckdb_bind_double")
extern fn bind_double(statement: usize, index: usize, value: f64) -> i32

@import("duckdb.dll", "duckdb_bind_varchar_length")
extern fn bind_varchar_length(statement: usize, index: usize, text: *const u8, length: usize) -> i32

@import("duckdb.dll", "duckdb_bind_blob")
extern fn bind_blob(statement: usize, index: usize, data: *const u8, length: usize) -> i32

// A `duckdb_hugeint` is two `uint64_t` passed as one 16-byte aggregate; the upper half carries
// the sign, so it crosses as `u64` and the driver reads the sign from its top bit.
@import("duckdb.dll", "duckdb_bind_hugeint")
extern fn raw_bind_hugeint(statement: usize, index: usize, lower: u64, upper: u64) -> i32

// A `duckdb_timestamp` is one `int64_t` microsecond count, passed as a one-field aggregate.
@import("duckdb.dll", "duckdb_bind_timestamp")
extern fn raw_bind_timestamp(statement: usize, index: usize, micros: i64) -> i32

@import("duckdb.dll", "duckdb_execute_prepared")
extern fn execute_prepared(statement: usize, result: *Result) -> i32



// duckdb_result is private to the library: it crosses as a pointer to these 192 bytes, which
// the library alone interprets. It is 152 bytes in C, and the rest is the slack a struct-by-value
// return needs, since C returns one in memory and copies it whole.
type Result = struct { columns: u64, rows: u64, changed: u64, column_data: usize, error_message: usize, state: usize }

// The library this file binds, for `os.dlopen` at run time; the import above is the same file.
fn library() -> str { ret "duckdb.dll" }
