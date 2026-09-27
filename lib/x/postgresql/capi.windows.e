// libpq as `x.postgresql.libpq` uses it, bound to `libpq.dll` (the PostgreSQL client library,
// found on PATH -- the EDB binaries put it in `bin/` beside the OpenSSL it needs). The Linux
// variant differs only in the library name; every declaration below must stay identical to it.
//
// Connections and results are addresses (`usize`). A C string argument that is never null
// crosses as `*const u8` to a NUL-terminated copy; an array argument, which may be null when
// it is empty, crosses as the `usize` address of its first element. `Oid` is `u32`.

@import("libpq.dll", "PQlibVersion")
extern fn lib_version() -> i32

@import("libpq.dll", "PQconnectdb")
extern fn connectdb(conninfo: *const u8) -> usize

@import("libpq.dll", "PQstatus")
extern fn status(conn: usize) -> i32

@import("libpq.dll", "PQerrorMessage")
extern fn error_message(conn: usize) -> *u8

@import("libpq.dll", "PQfinish")
extern fn finish(conn: usize)

@import("libpq.dll", "PQserverVersion")
extern fn server_version(conn: usize) -> i32

@import("libpq.dll", "PQtransactionStatus")
extern fn transaction_status(conn: usize) -> i32

@import("libpq.dll", "PQsendQuery")
extern fn send_query(conn: usize, command: *const u8) -> i32

@import("libpq.dll", "PQsendQueryParams")
extern fn send_query_params(conn: usize, command: *const u8, count: i32, types: usize, values: usize, lengths: usize, formats: usize, result_format: i32) -> i32

@import("libpq.dll", "PQsendPrepare")
extern fn send_prepare(conn: usize, name: *const u8, query: *const u8, count: i32, types: usize) -> i32

@import("libpq.dll", "PQsendDescribePrepared")
extern fn send_describe_prepared(conn: usize, name: *const u8) -> i32

@import("libpq.dll", "PQsendQueryPrepared")
extern fn send_query_prepared(conn: usize, name: *const u8, count: i32, values: usize, lengths: usize, formats: usize, result_format: i32) -> i32

@import("libpq.dll", "PQsetSingleRowMode")
extern fn set_single_row_mode(conn: usize) -> i32

@import("libpq.dll", "PQgetResult")
extern fn get_result(conn: usize) -> usize

@import("libpq.dll", "PQputCopyEnd")
extern fn put_copy_end(conn: usize, error_text: *const u8) -> i32

@import("libpq.dll", "PQgetCopyData")
extern fn get_copy_data(conn: usize, buffer: *usize, asynchronous: i32) -> i32

@import("libpq.dll", "PQfreemem")
extern fn freemem(p: usize)

@import("libpq.dll", "PQresultStatus")
extern fn result_status(result: usize) -> i32

@import("libpq.dll", "PQresultErrorMessage")
extern fn result_error_message(result: usize) -> *u8

@import("libpq.dll", "PQresultErrorField")
extern fn result_error_field(result: usize, code: i32) -> *u8

@import("libpq.dll", "PQcmdStatus")
extern fn cmd_status(result: usize) -> *u8

@import("libpq.dll", "PQcmdTuples")
extern fn cmd_tuples(result: usize) -> *u8

@import("libpq.dll", "PQntuples")
extern fn ntuples(result: usize) -> i32

@import("libpq.dll", "PQnfields")
extern fn nfields(result: usize) -> i32

@import("libpq.dll", "PQfname")
extern fn fname(result: usize, column: i32) -> *u8

@import("libpq.dll", "PQftype")
extern fn ftype(result: usize, column: i32) -> u32

@import("libpq.dll", "PQnparams")
extern fn nparams(result: usize) -> i32

@import("libpq.dll", "PQparamtype")
extern fn paramtype(result: usize, index: i32) -> u32

@import("libpq.dll", "PQgetvalue")
extern fn getvalue(result: usize, row: i32, column: i32) -> *u8

@import("libpq.dll", "PQgetlength")
extern fn getlength(result: usize, row: i32, column: i32) -> i32

@import("libpq.dll", "PQgetisnull")
extern fn getisnull(result: usize, row: i32, column: i32) -> i32

@import("libpq.dll", "PQclear")
extern fn clear(result: usize)
