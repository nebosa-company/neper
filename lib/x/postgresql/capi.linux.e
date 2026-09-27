// libpq as `x.postgresql.libpq` uses it, bound to the distribution's `libpq.so.5` (the soname
// every libpq since PostgreSQL 8.x has kept). The Windows variant differs only in the library
// name; every declaration below must stay identical to it.
//
// Connections and results are addresses (`usize`). A C string argument that is never null
// crosses as `*const u8` to a NUL-terminated copy; an array argument, which may be null when
// it is empty, crosses as the `usize` address of its first element. `Oid` is `u32`.

@import("libpq.so.5", "PQlibVersion")
extern fn lib_version() -> i32

@import("libpq.so.5", "PQconnectdb")
extern fn connectdb(conninfo: *const u8) -> usize

@import("libpq.so.5", "PQstatus")
extern fn status(conn: usize) -> i32

@import("libpq.so.5", "PQerrorMessage")
extern fn error_message(conn: usize) -> *u8

@import("libpq.so.5", "PQfinish")
extern fn finish(conn: usize)

@import("libpq.so.5", "PQserverVersion")
extern fn server_version(conn: usize) -> i32

@import("libpq.so.5", "PQtransactionStatus")
extern fn transaction_status(conn: usize) -> i32

@import("libpq.so.5", "PQsendQuery")
extern fn send_query(conn: usize, command: *const u8) -> i32

@import("libpq.so.5", "PQsendQueryParams")
extern fn send_query_params(conn: usize, command: *const u8, count: i32, types: usize, values: usize, lengths: usize, formats: usize, result_format: i32) -> i32

@import("libpq.so.5", "PQsendPrepare")
extern fn send_prepare(conn: usize, name: *const u8, query: *const u8, count: i32, types: usize) -> i32

@import("libpq.so.5", "PQsendDescribePrepared")
extern fn send_describe_prepared(conn: usize, name: *const u8) -> i32

@import("libpq.so.5", "PQsendQueryPrepared")
extern fn send_query_prepared(conn: usize, name: *const u8, count: i32, values: usize, lengths: usize, formats: usize, result_format: i32) -> i32

@import("libpq.so.5", "PQsetSingleRowMode")
extern fn set_single_row_mode(conn: usize) -> i32

@import("libpq.so.5", "PQgetResult")
extern fn get_result(conn: usize) -> usize

@import("libpq.so.5", "PQputCopyEnd")
extern fn put_copy_end(conn: usize, error_text: *const u8) -> i32

@import("libpq.so.5", "PQgetCopyData")
extern fn get_copy_data(conn: usize, buffer: *usize, asynchronous: i32) -> i32

@import("libpq.so.5", "PQfreemem")
extern fn freemem(p: usize)

@import("libpq.so.5", "PQresultStatus")
extern fn result_status(result: usize) -> i32

@import("libpq.so.5", "PQresultErrorMessage")
extern fn result_error_message(result: usize) -> *u8

@import("libpq.so.5", "PQresultErrorField")
extern fn result_error_field(result: usize, code: i32) -> *u8

@import("libpq.so.5", "PQcmdStatus")
extern fn cmd_status(result: usize) -> *u8

@import("libpq.so.5", "PQcmdTuples")
extern fn cmd_tuples(result: usize) -> *u8

@import("libpq.so.5", "PQntuples")
extern fn ntuples(result: usize) -> i32

@import("libpq.so.5", "PQnfields")
extern fn nfields(result: usize) -> i32

@import("libpq.so.5", "PQfname")
extern fn fname(result: usize, column: i32) -> *u8

@import("libpq.so.5", "PQftype")
extern fn ftype(result: usize, column: i32) -> u32

@import("libpq.so.5", "PQnparams")
extern fn nparams(result: usize) -> i32

@import("libpq.so.5", "PQparamtype")
extern fn paramtype(result: usize, index: i32) -> u32

@import("libpq.so.5", "PQgetvalue")
extern fn getvalue(result: usize, row: i32, column: i32) -> *u8

@import("libpq.so.5", "PQgetlength")
extern fn getlength(result: usize, row: i32, column: i32) -> i32

@import("libpq.so.5", "PQgetisnull")
extern fn getisnull(result: usize, row: i32, column: i32) -> i32

@import("libpq.so.5", "PQclear")
extern fn clear(result: usize)
