// `e.db`: an in-memory driver behind the contract -- rows of (id, name) appended by
// `execute` with parameters, read back through `query`, its columns and the row
// reader; a prepared statement executed and queried; a transaction whose rows land
// on commit and vanish on rollback; the driver's own refusals passing through -- and
// `Closed` from every handle after its close, commit or rollback. Every check has
// its own exit code.
use e.os
use e.mem
use e.str
use e.time
use e.db

// One open row set at a time: the cursor and its columns live in the store.
type Store = struct { ids: [8]i64, names: [8]str, count: usize, committed: usize, tx_open: bool, closed: bool, cursor: usize, cols: [2]db.Column, statements_closed: u32, rows_closed: u32 }

fn store_of(ctx: *void) -> *Store { ret mem.cast[*Store](ctx) }

fn d_close(ctx: *void) -> err {
    store_of(ctx).closed = true
    ret ok
}

fn insert(s: *Store, params: []const db.Parameter) -> (u64, err) {
    if params.len != 2usize { ret (0u64, db.InvalidQuery) }
    if s.count == 8usize { ret (0u64, db.Constraint) }
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
    if !s.tx_open { s.committed = s.count }
    ret (1u64, ok)
}

fn open_rows(s: *Store) -> (db.Rows, err) {
    s.cursor = 0usize
    var rows: db.Rows = zero
    rows.ctx = mem.cast[*void](s)
    ret (rows, ok)
}

fn d_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    if !str.eq(sql, "insert") { ret (0u64, db.InvalidQuery) }
    let (affected, insert_error) = insert(store_of(ctx), params)
    ret (affected, insert_error)
}

fn d_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    if !str.eq(sql, "select") { ret (zero, db.InvalidQuery) }
    let (rows, rows_error) = open_rows(store_of(ctx))
    ret (rows, rows_error)
}

fn d_prepare(ctx: *void, sql: str) -> (db.Statement, err) {
    if !str.eq(sql, "insert") { ret (zero, db.InvalidQuery) }
    var statement: db.Statement = zero
    statement.ctx = ctx
    ret (statement, ok)
}

fn d_begin(ctx: *void) -> (db.Transaction, err) {
    let s = store_of(ctx)
    if s.tx_open { ret (zero, db.Busy) }
    s.tx_open = true
    var transaction: db.Transaction = zero
    transaction.ctx = ctx
    ret (transaction, ok)
}

fn d_statement_close(ctx: *void) -> err {
    store_of(ctx).statements_closed += 1u32
    ret ok
}

fn d_statement_execute(ctx: *void, params: []const db.Parameter) -> (u64, err) {
    let (affected, insert_error) = insert(store_of(ctx), params)
    ret (affected, insert_error)
}

fn d_statement_query(ctx: *void, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, rows_error) = open_rows(store_of(ctx))
    ret (rows, rows_error)
}

fn d_rows_columns(ctx: *void) -> []const db.Column {
    let s = store_of(ctx)
    ret s.cols[0..]
}

// Only committed rows are visible outside a transaction; inside one, all of them.
fn d_rows_next(ctx: *void, dst: []db.Value) -> (bool, err) {
    let s = store_of(ctx)
    if dst.len < 2usize { ret (false, db.InvalidQuery) }
    var visible = s.committed
    if s.tx_open { visible = s.count }
    if s.cursor >= visible { ret (false, ok) }
    dst[0] = db.Value{ I64: s.ids[s.cursor] }
    dst[1] = db.Value{ Text: s.names[s.cursor] }
    s.cursor += 1usize
    ret (true, ok)
}

fn d_rows_close(ctx: *void) -> err {
    store_of(ctx).rows_closed += 1u32
    ret ok
}

fn d_transaction_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = d_execute(ctx, sql, params)
    ret (affected, execute_error)
}

fn d_transaction_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, rows_error) = d_query(ctx, sql, params)
    ret (rows, rows_error)
}

fn d_transaction_commit(ctx: *void) -> err {
    let s = store_of(ctx)
    s.committed = s.count
    s.tx_open = false
    ret ok
}

fn d_transaction_rollback(ctx: *void) -> err {
    let s = store_of(ctx)
    s.count = s.committed
    s.tx_open = false
    ret ok
}

fn params_of(id: i64, name: str) -> [2]db.Parameter {
    var params: [2]db.Parameter = zero
    params[0] = db.Parameter { name: "id", value: db.Value{ I64: id } }
    params[1] = db.Parameter { name: "name", value: db.Value{ Text: name } }
    ret params
}

// Reads every row of `rows` into `ids`/`names`, returning the count.
fn drain(rows: *db.Rows, ids: []i64, names: []str) -> (usize, err) {
    var count = 0usize
    var row: [2]db.Value = zero
    while true {
        let (more, next_error) = db.reader_next_err(rows, row[0..])
        if next_error != ok { ret (count, next_error) }
        if !more { ret (count, ok) }
        switch row[0] {
        case .I64 as id:
            ids[count] = id
        default:
            ret (count, db.InvalidQuery)
        }
        switch row[1] {
        case .Text as name:
            names[count] = name
        default:
            ret (count, db.InvalidQuery)
        }
        count += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var store: Store = zero
    store.cols[0] = db.Column { name: "id", kind: .I64, nullable: false }
    store.cols[1] = db.Column { name: "name", kind: .Text, nullable: true }
    let driver = db.Driver { close: d_close, prepare: d_prepare, execute: d_execute, query: d_query, begin: d_begin, statement_close: d_statement_close, statement_execute: d_statement_execute, statement_query: d_statement_query, rows_columns: d_rows_columns, rows_next: d_rows_next, rows_close: d_rows_close, transaction_execute: d_transaction_execute, transaction_query: d_transaction_query, transaction_commit: d_transaction_commit, transaction_rollback: d_transaction_rollback }
    var connection = db.Connection { ctx: mem.cast[*void](&store), driver: &driver }
    var ids: [8]i64 = zero
    var names: [8]str = zero
    // Execute and query.
    let p1 = params_of(1i64, "one")
    let (n1, e1) = db.execute(&connection, "insert", p1[0..])
    if e1 != ok || n1 != 1u64 { os.exit(1) }
    let (n2, e2) = db.execute(&connection, "delete", p1[0..])
    if e2 != db.InvalidQuery { os.exit(2) }
    let (rows0, e3) = db.query(&connection, "select", zero)
    if e3 != ok { os.exit(3) }
    var rows = rows0
    let cols = db.columns(&rows)
    if cols.len != 2usize || !str.eq(cols[1].name, "name") || cols[1].kind != .Text || !cols[1].nullable { os.exit(4) }
    let (c1, e4) = drain(&rows, ids[0..], names[0..])
    if e4 != ok || c1 != 1usize || ids[0] != 1i64 || !str.eq(names[0], "one") { os.exit(5) }
    if db.close_rows(&rows) != ok || store.rows_closed != 1u32 { os.exit(6) }
    if db.close_rows(&rows) != db.Closed { os.exit(7) }
    let (more, e5) = db.reader_next_err(&rows, zero)
    if e5 != db.Closed || db.columns(&rows).len != 0usize { os.exit(8) }
    // A prepared statement.
    let (statement0, e6) = db.prepare(&connection, "insert")
    if e6 != ok { os.exit(9) }
    var statement = statement0
    let p2 = params_of(2i64, "two")
    let (n3, e7) = db.execute_statement(&statement, p2[0..])
    if e7 != ok || n3 != 1u64 { os.exit(10) }
    let (rows1, e8) = db.query_statement(&statement, zero)
    if e8 != ok { os.exit(11) }
    var rows_b = rows1
    let (c2, e9) = drain(&rows_b, ids[0..], names[0..])
    if e9 != ok || c2 != 2usize || ids[1] != 2i64 { os.exit(12) }
    if db.close_statement(&statement) != ok || store.statements_closed != 1u32 { os.exit(13) }
    if db.close_statement(&statement) != db.Closed { os.exit(14) }
    let (n4, e10) = db.execute_statement(&statement, p2[0..])
    if e10 != db.Closed { os.exit(15) }
    let (bad_statement, e11) = db.prepare(&connection, "drop")
    if e11 != db.InvalidQuery { os.exit(16) }
    // A transaction rolled back, then one committed.
    let (tx0, e12) = db.begin(&connection)
    if e12 != ok { os.exit(17) }
    var tx = tx0
    let (tx_again, e13) = db.begin(&connection)
    if e13 != db.Busy { os.exit(18) }
    let p3 = params_of(3i64, "three")
    let (n5, e14) = db.execute_transaction(&tx, "insert", p3[0..])
    if e14 != ok || n5 != 1u64 { os.exit(19) }
    let (rows2, e15) = db.query_transaction(&tx, "select", zero)
    if e15 != ok { os.exit(20) }
    var rows_c = rows2
    let (c3, e16) = drain(&rows_c, ids[0..], names[0..])
    if e16 != ok || c3 != 3usize { os.exit(21) }
    if db.rollback(&tx) != ok { os.exit(22) }
    if db.rollback(&tx) != db.Closed || db.commit(&tx) != db.Closed { os.exit(23) }
    let (n6, e17) = db.execute_transaction(&tx, "insert", p3[0..])
    if e17 != db.Closed { os.exit(24) }
    let (rows3, e18) = db.query(&connection, "select", zero)
    if e18 != ok { os.exit(25) }
    var rows_d = rows3
    let (c4, e19) = drain(&rows_d, ids[0..], names[0..])
    if e19 != ok || c4 != 2usize { os.exit(26) }
    let (tx1, e20) = db.begin(&connection)
    if e20 != ok { os.exit(27) }
    var tx_b = tx1
    let (n7, e21) = db.execute_transaction(&tx_b, "insert", p3[0..])
    if e21 != ok { os.exit(28) }
    if db.commit(&tx_b) != ok { os.exit(29) }
    let (rows4, e22) = db.query(&connection, "select", zero)
    if e22 != ok { os.exit(30) }
    var rows_e = rows4
    let (c5, e23) = drain(&rows_e, ids[0..], names[0..])
    if e23 != ok || c5 != 3usize || !str.eq(names[2], "three") { os.exit(31) }
    // The connection closed.
    if db.close(&connection) != ok || !store.closed { os.exit(32) }
    if db.close(&connection) != db.Closed { os.exit(33) }
    let (n8, e24) = db.execute(&connection, "insert", p1[0..])
    if e24 != db.Closed { os.exit(34) }
    let (rows5, e25) = db.query(&connection, "select", zero)
    if e25 != db.Closed { os.exit(35) }
    let (statement1, e26) = db.prepare(&connection, "insert")
    if e26 != db.Closed { os.exit(36) }
    let (tx2, e27) = db.begin(&connection)
    if e27 != db.Closed { os.exit(37) }
    ret ok
}
