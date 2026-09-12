// The SQL contract: a connection, statement, row reader and transaction are each a
// driver context and the driver's function table, and every call here dispatches to
// the table. A handle whose context is `nil` -- after its close, commit or rollback --
// answers `Closed` without reaching the driver. A handle a driver hands back carries
// only its context; the table is filled in here from the handle it came from.
// Nothing is discovered or pooled; a driver package fills the table and hands out
// the connection.
use e.time

type Connection = struct { ctx: *void, driver: *const Driver }
type Statement = struct { ctx: *void, driver: *const Driver }
type Rows = struct { ctx: *void, driver: *const Driver }
type Transaction = struct { ctx: *void, driver: *const Driver }
type Value = union enum u8 { Null, Bool: bool, I64: i64, U64: u64, F64: f64, Text: str, Bytes: []const u8, Time: time.Instant }
type Parameter = struct { name: str, value: Value }
type Column = struct { name: str, kind: ValueKind, nullable: bool }
type ValueKind = enum u8 { Null, Bool, I64, U64, F64, Text, Bytes, Time }
type Driver = struct { close: fn(ctx: *void) -> err, prepare: fn(ctx: *void, sql: str) -> (Statement, err), execute: fn(ctx: *void, sql: str, params: []const Parameter) -> (u64, err), query: fn(ctx: *void, sql: str, params: []const Parameter) -> (Rows, err), begin: fn(ctx: *void) -> (Transaction, err), statement_close: fn(ctx: *void) -> err, statement_execute: fn(ctx: *void, params: []const Parameter) -> (u64, err), statement_query: fn(ctx: *void, params: []const Parameter) -> (Rows, err), rows_columns: fn(ctx: *void) -> []const Column, rows_next: fn(ctx: *void, dst: []Value) -> (bool, err), rows_close: fn(ctx: *void) -> err, transaction_execute: fn(ctx: *void, sql: str, params: []const Parameter) -> (u64, err), transaction_query: fn(ctx: *void, sql: str, params: []const Parameter) -> (Rows, err), transaction_commit: fn(ctx: *void) -> err, transaction_rollback: fn(ctx: *void) -> err }
error Closed
error InvalidQuery
error Constraint
error Busy
error Unsupported

fn close(connection: *Connection) -> err {
    if connection.ctx == nil { ret Closed }
    let close_error = connection.driver.close(connection.ctx)
    connection.ctx = nil
    ret close_error
}

fn prepare(connection: *Connection, sql: str) -> (Statement, err) {
    if connection.ctx == nil { ret (zero, Closed) }
    let (statement0, prepare_error) = connection.driver.prepare(connection.ctx, sql)
    var statement = statement0
    statement.driver = connection.driver
    ret (statement, prepare_error)
}

fn execute(connection: *Connection, sql: str, params: []const Parameter) -> (u64, err) {
    if connection.ctx == nil { ret (0u64, Closed) }
    let (affected, execute_error) = connection.driver.execute(connection.ctx, sql, params)
    ret (affected, execute_error)
}

fn query(connection: *Connection, sql: str, params: []const Parameter) -> (Rows, err) {
    if connection.ctx == nil { ret (zero, Closed) }
    let (rows0, query_error) = connection.driver.query(connection.ctx, sql, params)
    var rows = rows0
    rows.driver = connection.driver
    ret (rows, query_error)
}

fn close_statement(statement: *Statement) -> err {
    if statement.ctx == nil { ret Closed }
    let close_error = statement.driver.statement_close(statement.ctx)
    statement.ctx = nil
    ret close_error
}

fn execute_statement(statement: *Statement, params: []const Parameter) -> (u64, err) {
    if statement.ctx == nil { ret (0u64, Closed) }
    let (affected, execute_error) = statement.driver.statement_execute(statement.ctx, params)
    ret (affected, execute_error)
}

fn query_statement(statement: *Statement, params: []const Parameter) -> (Rows, err) {
    if statement.ctx == nil { ret (zero, Closed) }
    let (rows0, query_error) = statement.driver.statement_query(statement.ctx, params)
    var rows = rows0
    rows.driver = statement.driver
    ret (rows, query_error)
}

fn columns(rows: *Rows) -> []const Column {
    if rows.ctx == nil { ret zero }
    ret rows.driver.rows_columns(rows.ctx)
}

fn reader_next_err(rows: *Rows, dst: []Value) -> (bool, err) {
    if rows.ctx == nil { ret (false, Closed) }
    let (more, next_error) = rows.driver.rows_next(rows.ctx, dst)
    ret (more, next_error)
}

fn close_rows(rows: *Rows) -> err {
    if rows.ctx == nil { ret Closed }
    let close_error = rows.driver.rows_close(rows.ctx)
    rows.ctx = nil
    ret close_error
}

fn begin(connection: *Connection) -> (Transaction, err) {
    if connection.ctx == nil { ret (zero, Closed) }
    let (transaction0, begin_error) = connection.driver.begin(connection.ctx)
    var transaction = transaction0
    transaction.driver = connection.driver
    ret (transaction, begin_error)
}

fn execute_transaction(transaction: *Transaction, sql: str, params: []const Parameter) -> (u64, err) {
    if transaction.ctx == nil { ret (0u64, Closed) }
    let (affected, execute_error) = transaction.driver.transaction_execute(transaction.ctx, sql, params)
    ret (affected, execute_error)
}

fn query_transaction(transaction: *Transaction, sql: str, params: []const Parameter) -> (Rows, err) {
    if transaction.ctx == nil { ret (zero, Closed) }
    let (rows0, query_error) = transaction.driver.transaction_query(transaction.ctx, sql, params)
    var rows = rows0
    rows.driver = transaction.driver
    ret (rows, query_error)
}

fn commit(transaction: *Transaction) -> err {
    if transaction.ctx == nil { ret Closed }
    let commit_error = transaction.driver.transaction_commit(transaction.ctx)
    transaction.ctx = nil
    ret commit_error
}

fn rollback(transaction: *Transaction) -> err {
    if transaction.ctx == nil { ret Closed }
    let rollback_error = transaction.driver.transaction_rollback(transaction.ctx)
    transaction.ctx = nil
    ret rollback_error
}
