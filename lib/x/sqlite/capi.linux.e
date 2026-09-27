// The SQLite 3 C API as `x.sqlite.sqlite` uses it, bound to the distribution's shared library
// (`libsqlite3.so.0`, the soname every SQLite 3 release has kept). The Windows variant differs
// only in the library name; every declaration below must stay identical to it.
//
// Handles are addresses (`usize`); a C string crosses as `*const u8` to a NUL-terminated
// copy; an out parameter is a pointer to a caller local; the destructor argument of the bind
// calls is always `SQLITE_TRANSIENT` (-1), passed as `usize` because nothing here makes a
// function pointer.

@import("libsqlite3.so.0", "sqlite3_libversion_number")
extern fn libversion_number() -> i32

@import("libsqlite3.so.0", "sqlite3_open_v2")
extern fn open_v2(filename: *const u8, handle: *usize, flags: i32, vfs: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_close_v2")
extern fn close_v2(handle: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_errmsg")
extern fn errmsg(handle: usize) -> *u8

@import("libsqlite3.so.0", "sqlite3_extended_errcode")
extern fn extended_errcode(handle: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_changes")
extern fn changes(handle: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_get_autocommit")
extern fn get_autocommit(handle: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_total_changes")
extern fn total_changes(handle: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_prepare_v2")
extern fn prepare_v2(handle: usize, sql: *const u8, bytes: i32, statement: *usize, tail: *usize) -> i32

@import("libsqlite3.so.0", "sqlite3_finalize")
extern fn finalize(statement: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_reset")
extern fn reset(statement: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_clear_bindings")
extern fn clear_bindings(statement: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_step")
extern fn step(statement: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_bind_parameter_count")
extern fn bind_parameter_count(statement: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_bind_parameter_index")
extern fn bind_parameter_index(statement: usize, name: *const u8) -> i32

@import("libsqlite3.so.0", "sqlite3_bind_null")
extern fn bind_null(statement: usize, index: i32) -> i32

@import("libsqlite3.so.0", "sqlite3_bind_int64")
extern fn bind_int64(statement: usize, index: i32, value: i64) -> i32

@import("libsqlite3.so.0", "sqlite3_bind_double")
extern fn bind_double(statement: usize, index: i32, value: f64) -> i32

@import("libsqlite3.so.0", "sqlite3_bind_text")
extern fn bind_text(statement: usize, index: i32, text: *const u8, bytes: i32, destructor: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_bind_blob")
extern fn bind_blob(statement: usize, index: i32, data: *const u8, bytes: i32, destructor: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_column_count")
extern fn column_count(statement: usize) -> i32

@import("libsqlite3.so.0", "sqlite3_column_name")
extern fn column_name(statement: usize, column: i32) -> *u8

@import("libsqlite3.so.0", "sqlite3_column_decltype")
extern fn column_decltype(statement: usize, column: i32) -> *u8

@import("libsqlite3.so.0", "sqlite3_column_type")
extern fn column_type(statement: usize, column: i32) -> i32

@import("libsqlite3.so.0", "sqlite3_column_int64")
extern fn column_int64(statement: usize, column: i32) -> i64

@import("libsqlite3.so.0", "sqlite3_column_double")
extern fn column_double(statement: usize, column: i32) -> f64

@import("libsqlite3.so.0", "sqlite3_column_text")
extern fn column_text(statement: usize, column: i32) -> *u8

@import("libsqlite3.so.0", "sqlite3_column_blob")
extern fn column_blob(statement: usize, column: i32) -> *u8

@import("libsqlite3.so.0", "sqlite3_column_bytes")
extern fn column_bytes(statement: usize, column: i32) -> i32
