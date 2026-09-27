// A complete `e.db` driver in one file: a table of (id, name) rows kept in memory. It answers
// one INSERT and one SELECT, which is enough to show every part a real driver has -- a context
// behind each handle, the driver table, a streaming reader, and a transaction that can be undone.
//
//   neper run examples/db/memory_driver/src/main.e
use e.io
use e.mem
use e.str
use e.db

// The driver's state. A real driver keeps its library handle here; this one keeps the rows.
// One reader at a time, so its cursor lives in the store too.
type Store = struct { ids: [64]i64, names: [64]str, count: usize, committed: usize, in_transaction: bool, cursor: usize, columns: [2]db.Column }

fn store_of(ctx: *void) -> *Store { ret mem.cast[*Store](ctx) }

// --- the connection

fn m_close(ctx: *void) -> err { ret ok }

fn m_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    if !str.eq(sql, "INSERT INTO t VALUES (?, ?)") || params.len != 2usize { ret (0u64, db.InvalidQuery) }
    let s = store_of(ctx)
    if s.count == s.ids.len { ret (0u64, db.Constraint) }
    switch params[0].value {
    case .I64 as id:
        s.ids[s.count] = id
    default:
        ret (0u64, db.InvalidQuery)
    }
    switch params[1].value {
    case .Text as name:
        s.names[s.count] = name
    default:
        ret (0u64, db.InvalidQuery)
    }
    s.count += 1usize
    if !s.in_transaction { s.committed = s.count }
    ret (1u64, ok)
}

fn m_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    var rows: db.Rows = zero
    if !str.eq(sql, "SELECT id, name FROM t") { ret (rows, db.InvalidQuery) }
    let s = store_of(ctx)
    s.cursor = 0usize
    // A handle carries only the context: `e.db` fills in the table from the connection.
    rows.ctx = ctx
    ret (rows, ok)
}

fn m_prepare(ctx: *void, sql: str) -> (db.Statement, err) { ret (zero, db.Unsupported) }

fn m_begin(ctx: *void) -> (db.Transaction, err) {
    var transaction: db.Transaction = zero
    let s = store_of(ctx)
    if s.in_transaction { ret (transaction, db.Busy) }
    s.in_transaction = true
    transaction.ctx = ctx
    ret (transaction, ok)
}

// --- statements: this driver has none, so these are never reached

fn m_statement_close(ctx: *void) -> err { ret db.Unsupported }
fn m_statement_execute(ctx: *void, params: []const db.Parameter) -> (u64, err) { ret (0u64, db.Unsupported) }
fn m_statement_query(ctx: *void, params: []const db.Parameter) -> (db.Rows, err) { ret (zero, db.Unsupported) }

// --- the row reader

fn m_rows_columns(ctx: *void) -> []const db.Column { ret store_of(ctx).columns[0..] }

// Committed rows are visible outside a transaction; inside one, all of them.
fn m_rows_next(ctx: *void, dst: []db.Value) -> (bool, err) {
    let s = store_of(ctx)
    if dst.len < 2usize { ret (false, db.InvalidQuery) }
    var visible = s.committed
    if s.in_transaction { visible = s.count }
    if s.cursor >= visible { ret (false, ok) }
    dst[0] = db.Value{ I64: s.ids[s.cursor] }
    dst[1] = db.Value{ Text: s.names[s.cursor] }
    s.cursor += 1usize
    ret (true, ok)
}

fn m_rows_close(ctx: *void) -> err { ret ok }

// --- transactions

fn m_transaction_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = m_execute(ctx, sql, params)
    ret (affected, execute_error)
}

fn m_transaction_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, query_error) = m_query(ctx, sql, params)
    ret (rows, query_error)
}

fn m_commit(ctx: *void) -> err {
    let s = store_of(ctx)
    s.committed = s.count
    s.in_transaction = false
    ret ok
}

fn m_rollback(ctx: *void) -> err {
    let s = store_of(ctx)
    s.count = s.committed
    s.in_transaction = false
    ret ok
}

// --- opening: fill the table once, hand out the connection

fn open(s: *Store, driver: *db.Driver) -> db.Connection {
    driver.close = m_close
    driver.prepare = m_prepare
    driver.execute = m_execute
    driver.query = m_query
    driver.begin = m_begin
    driver.statement_close = m_statement_close
    driver.statement_execute = m_statement_execute
    driver.statement_query = m_statement_query
    driver.rows_columns = m_rows_columns
    driver.rows_next = m_rows_next
    driver.rows_next_borrowed = m_rows_next
    driver.rows_close = m_rows_close
    driver.transaction_execute = m_transaction_execute
    driver.transaction_query = m_transaction_query
    driver.transaction_commit = m_commit
    driver.transaction_rollback = m_rollback
    s.columns[0] = db.Column { name: "id", kind: .I64, nullable: false }
    s.columns[1] = db.Column { name: "name", kind: .Text, nullable: false }
    ret db.Connection { ctx: mem.cast[*void](s), driver: driver }
}

// --- a program that only knows `e.db`

fn insert(c: *db.Connection, id: i64, name: str) -> err {
    var p: [2]db.Parameter = zero
    p[0] = db.Parameter { name: "", value: db.Value{ I64: id } }
    p[1] = db.Parameter { name: "", value: db.Value{ Text: name } }
    let (affected, insert_error) = db.execute(c, "INSERT INTO t VALUES (?, ?)", p[0..])
    ret insert_error
}

fn count(c: *db.Connection) -> (usize, err) {
    let (rows0, query_error) = db.query(c, "SELECT id, name FROM t", zero)
    if query_error != ok { ret (0usize, query_error) }
    var rows = rows0
    var row: [2]db.Value = zero
    var n = 0usize
    while true {
        let (more, next_error) = db.reader_next_err(&rows, row[0..])
        if next_error != ok { ret (n, next_error) }
        if !more { break }
        n += 1usize
    }
    let close_error = db.close_rows(&rows)
    ret (n, close_error)
}

fn main(a: *mem.Arena) -> err {
    var store: Store = zero
    var driver: db.Driver = zero
    var c = open(&store, &driver)
    try insert(&c, 1i64, "ada")
    let (tx0, begin_error) = db.begin(&c)
    if begin_error != ok { ret begin_error }
    var tx = tx0
    try insert(&c, 2i64, "grace")
    try db.rollback(&tx)
    let (n, count_error) = count(&c)
    if count_error != ok { ret count_error }
    try io.printf["{} row after the rollback\n"](n)
    try db.close(&c)
    // Every handle answers `Closed` once it is closed, without reaching the driver.
    let (late, late_error) = count(&c)
    if late_error == db.Closed { try io.printf["closed connection: {}\n"]("db.Closed") }
    ret ok
}
