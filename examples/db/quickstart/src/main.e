// e.db in one screen: open SQLite, create a table, insert inside a transaction with
// parameters, then stream the rows back. Swap the `open` line for `libpq.open(a, "host=...")`
// or `mysql.open(a, options)` and the rest is unchanged, except PostgreSQL's `$1` placeholders.
//
//   neper run examples/db/quickstart/src/main.e
use e.io
use e.mem
use e.db
use x.sqlite.sqlite

fn main(a: *mem.Arena) -> err {
    var c = try sqlite.open(a, ":memory:")
    let created = try db.execute(&c, "CREATE TABLE lang(name TEXT NOT NULL, year INTEGER)", zero)

    var tx = try db.begin(&c)
    var p: [2]db.Parameter = zero
    p[0] = db.Parameter { name: "", value: db.Value{ Text: "Neper" } }
    p[1] = db.Parameter { name: "", value: db.Value{ I64: 2026i64 } }
    let inserted = try db.execute_transaction(&tx, "INSERT INTO lang VALUES (?, ?)", p[0..])
    try db.commit(&tx)

    var rows = try db.query(&c, "SELECT name, year FROM lang", zero)
    var row: [2]db.Value = zero
    while true {
        let more = try db.reader_next_err(&rows, row[0..])
        if !more { break }
        switch row[0] {
        case .Text as name:
            try io.printf["{}\n"](name)
        default:
            ret db.InvalidQuery
        }
    }
    try db.close_rows(&rows)
    ret db.close(&c)
}
