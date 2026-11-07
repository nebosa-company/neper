// The DuckDB v2 C API as `x.duckdb.duckdb` uses it, bound to the `duckdb` library: `@import`
// names a library with no prefix or suffix, and the loader resolves it to `duckdb.dll` on
// Windows and `libduckdb.so` on Linux. The two variants differ only in the name in this
// comment; every declaration below is identical between them.
//
// Every call answers a `DUCKDB_V2_ERROR` (0 is success) and writes its product through an out
// parameter, so no handle is a sentinel. A handle crosses as an address (`usize`) and `0` is
// null. `err` is an optional error-info slot: pass `0` to ask for the code alone, or the
// address of a `usize` to receive a handle the caller destroys with `error_info_destroy`.
//
// `duckdb_v2_str` is a borrowed view, a pointer and a length, and is not NUL-terminated. The
// header's `duckdb_v2_identifier_t` has the same layout, and its `duckdb_v2_*_handle` types
// are all addresses.
use e.mem

// `duckdb_v2_str.ptr` is a `const char *`; keeping it as a pointer is what lets the driver read
// through it, since the language has no integer-to-pointer conversion.
type Str = struct { ptr: *const u8, len: usize }

const DUCKDB_SUCCESS: i32 = 0i32

@import("duckdb", "duckdb_v2_library_version")
@cc(c)
extern fn library_version(out_version: *Str, info: *usize) -> i32

@import("duckdb", "duckdb_v2_environment_create")
@cc(c)
extern fn environment_create(out_env: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_environment_destroy")
@cc(c)
extern fn environment_destroy(env: *usize) -> i32

@import("duckdb", "duckdb_v2_instance_create")
@cc(c)
extern fn instance_create(env: usize, out_instance: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_instance_attach")
@cc(c)
extern fn instance_attach(instance: usize, name: *const Str, path: *const Str, options: usize, make_default: u8, info: *usize) -> i32

@import("duckdb", "duckdb_v2_instance_destroy")
@cc(c)
extern fn instance_destroy(instance: *usize) -> i32

@import("duckdb", "duckdb_v2_connection_create")
@cc(c)
extern fn connection_create(instance: usize, out_conn: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_connection_destroy")
@cc(c)
extern fn connection_destroy(conn: *usize) -> i32

@import("duckdb", "duckdb_v2_connection_get_factory")
@cc(c)
extern fn connection_get_factory(conn: usize, out_factory: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_parse_sql")
@cc(c)
extern fn parse_sql(conn: usize, sql: *const u8, out_iterator: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_statement_iterator_next")
@cc(c)
extern fn statement_iterator_next(iterator: usize, out_statement: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_statement_iterator_destroy")
@cc(c)
extern fn statement_iterator_destroy(iterator: *usize) -> i32

@import("duckdb", "duckdb_v2_sql_statement_destroy")
@cc(c)
extern fn sql_statement_destroy(statement: *usize) -> i32

@import("duckdb", "duckdb_v2_sql_statement_get_text")
@cc(c)
extern fn sql_statement_get_text(statement: usize, out_text: *Str, info: *usize) -> i32

@import("duckdb", "duckdb_v2_sql_statement_get_parameter_name")
@cc(c)
extern fn sql_statement_get_parameter_name(statement: usize, index: usize, out_name: *Str, info: *usize) -> i32

@import("duckdb", "duckdb_v2_sql_statement_get_parameter_count")
@cc(c)
extern fn sql_statement_get_parameter_count(statement: usize, out_count: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_prepared_statement_create")
@cc(c)
extern fn prepared_statement_create(conn: usize, statement: usize, require_cacheable: u8, out_prepared: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_prepared_statement_destroy")
@cc(c)
extern fn prepared_statement_destroy(prepared: *usize) -> i32

@import("duckdb", "duckdb_v2_prepared_statement_execute")
@cc(c)
extern fn prepared_statement_execute(prepared: usize, parameter_names: *const Str, parameter_values: *const usize, parameter_count: usize, out_result: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_result_drain")
@cc(c)
extern fn result_drain(result: usize, out_rows_changed: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_result_get_schema")
@cc(c)
extern fn result_get_schema(result: usize, out_schema: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_result_get_result_type")
@cc(c)
extern fn result_get_result_type(result: usize, out_type: *i32, info: *usize) -> i32

@import("duckdb", "duckdb_v2_result_fetch_chunk")
@cc(c)
extern fn result_fetch_chunk(result: usize, out_chunk: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_result_destroy")
@cc(c)
extern fn result_destroy(result: *usize) -> i32

@import("duckdb", "duckdb_v2_schema_get_count")
@cc(c)
extern fn schema_get_count(schema: usize, out_count: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_schema_get_field")
@cc(c)
extern fn schema_get_field(schema: usize, index: usize, out_name: *Str, out_type: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_logical_type_get_id")
@cc(c)
extern fn logical_type_get_id(logical: usize, out_id: *i32, info: *usize) -> i32

@import("duckdb", "duckdb_v2_logical_type_destroy")
@cc(c)
extern fn logical_type_destroy(logical: *usize) -> i32

@import("duckdb", "duckdb_v2_data_chunk_get_size")
@cc(c)
extern fn data_chunk_get_size(chunk: usize, out_size: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_data_chunk_get_vector")
@cc(c)
extern fn data_chunk_get_vector(chunk: usize, index: usize, out_vector: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_data_chunk_destroy")
@cc(c)
extern fn data_chunk_destroy(chunk: *usize) -> i32

@import("duckdb", "duckdb_v2_vector_get_value")
@cc(c)
extern fn vector_get_value(vector: usize, row: usize, out_value: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_create_bool")
@cc(c)
extern fn value_create_bool(factory: usize, in_value: u8, out_value: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_create_bigint")
@cc(c)
extern fn value_create_bigint(factory: usize, in_value: i64, out_value: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_create_double")
@cc(c)
extern fn value_create_double(factory: usize, in_value: f64, out_value: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_create_varchar")
@cc(c)
extern fn value_create_varchar(factory: usize, in_value: *const Str, out_value: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_create_blob")
@cc(c)
extern fn value_create_blob(factory: usize, in_value: *const Str, out_value: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_create_timestamp")
@cc(c)
extern fn value_create_timestamp(factory: usize, in_value: i64, out_value: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_factory_create_type_from_id")
@cc(c)
extern fn factory_create_type_from_id(factory: usize, type_id: i32, param_names: *Str, param_values: *usize, param_count: usize, out_type: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_create_null")
@cc(c)
extern fn value_create_null(factory: usize, logical: usize, out_value: *usize, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_destroy")
@cc(c)
extern fn value_destroy(value: *usize) -> i32

@import("duckdb", "duckdb_v2_value_is_null")
@cc(c)
extern fn value_is_null(value: usize, out_is_null: *u8, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_get_timestamp")
@cc(c)
extern fn value_get_timestamp(value: usize, out: *i64, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_get_bigint")
@cc(c)
extern fn value_get_bigint(value: usize, out: *i64, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_get_double")
@cc(c)
extern fn value_get_double(value: usize, out: *f64, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_get_varchar")
@cc(c)
extern fn value_get_varchar(value: usize, out: *Str, info: *usize) -> i32

@import("duckdb", "duckdb_v2_value_get_blob")
@cc(c)
extern fn value_get_blob(value: usize, out: *Str, info: *usize) -> i32

@import("duckdb", "duckdb_v2_error_info_get_text")
@cc(c)
extern fn error_info_get_text(info: usize, out_text: *Str) -> i32

@import("duckdb", "duckdb_v2_error_info_destroy")
@cc(c)
extern fn error_info_destroy(info: *usize) -> i32
