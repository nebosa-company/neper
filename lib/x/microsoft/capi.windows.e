// The ODBC 3 C API as `x.microsoft.odbc` uses it, bound to the driver manager Windows ships in
// System32 (`odbc32.dll`). The Linux variant binds unixODBC's `libodbc.so.2` and differs only in
// the library name; every declaration below must stay identical to it.
//
// Only the wide (`W`) entry points take text: the driver manager converts the narrow ones
// through the process code page on Windows and the locale on Linux, while `SQLWCHAR` is a UTF-16
// unit on both. Handles are addresses (`usize`). `SQLRETURN` and `SQLSMALLINT` are `i16`,
// `SQLUSMALLINT` is `u16`, `SQLINTEGER` is `i32`, and `SQLLEN`/`SQLULEN` are 64 bits on both
// hosts (`i64`/`usize`). A `SQLPOINTER` that carries an integer attribute value is `usize`.

@import("odbc32.dll", "SQLAllocHandle")
extern fn alloc_handle(kind: i16, input: usize, output: *usize) -> i16

@import("odbc32.dll", "SQLFreeHandle")
extern fn free_handle(kind: i16, handle: usize) -> i16

@import("odbc32.dll", "SQLSetEnvAttr")
extern fn set_env_attr(env: usize, attribute: i32, value: usize, length: i32) -> i16

@import("odbc32.dll", "SQLDriverConnectW")
extern fn driver_connect(dbc: usize, window: usize, text: *const u16, text_len: i16, out: *u16, out_cap: i16, out_len: *i16, completion: u16) -> i16

@import("odbc32.dll", "SQLDisconnect")
extern fn disconnect(dbc: usize) -> i16

@import("odbc32.dll", "SQLSetConnectAttrW")
extern fn set_connect_attr(dbc: usize, attribute: i32, value: usize, length: i32) -> i16

@import("odbc32.dll", "SQLEndTran")
extern fn end_tran(kind: i16, handle: usize, completion: i16) -> i16

@import("odbc32.dll", "SQLGetDiagRecW")
extern fn get_diag_rec(kind: i16, handle: usize, record: i16, state: *u16, native: *i32, message: *u16, message_cap: i16, message_len: *i16) -> i16

@import("odbc32.dll", "SQLExecDirectW")
extern fn exec_direct(stmt: usize, text: *const u16, text_len: i32) -> i16

@import("odbc32.dll", "SQLPrepareW")
extern fn prepare(stmt: usize, text: *const u16, text_len: i32) -> i16

@import("odbc32.dll", "SQLExecute")
extern fn execute(stmt: usize) -> i16

@import("odbc32.dll", "SQLNumParams")
extern fn num_params(stmt: usize, count: *i16) -> i16

@import("odbc32.dll", "SQLBindParameter")
extern fn bind_parameter(stmt: usize, number: u16, io: i16, c_type: i16, sql_type: i16, column_size: usize, digits: i16, value: *const void, value_cap: i64, length: *i64) -> i16

@import("odbc32.dll", "SQLNumResultCols")
extern fn num_result_cols(stmt: usize, count: *i16) -> i16

@import("odbc32.dll", "SQLDescribeColW")
extern fn describe_col(stmt: usize, column: u16, name: *u16, name_cap: i16, name_len: *i16, sql_type: *i16, column_size: *usize, digits: *i16, nullable: *i16) -> i16

@import("odbc32.dll", "SQLFetch")
extern fn fetch(stmt: usize) -> i16

@import("odbc32.dll", "SQLGetData")
extern fn get_data(stmt: usize, column: u16, c_type: i16, value: *void, value_cap: i64, length: *i64) -> i16

@import("odbc32.dll", "SQLRowCount")
extern fn row_count(stmt: usize, count: *i64) -> i16

@import("odbc32.dll", "SQLMoreResults")
extern fn more_results(stmt: usize) -> i16

@import("odbc32.dll", "SQLFreeStmt")
extern fn free_stmt(stmt: usize, option: u16) -> i16
