// The e.db driver benchmark's workload, written once against `e.db` and run unchanged by the
// three entry programs beside it (sqlite.e, postgresql.e, mysql.e), so the numbers compare
// drivers and databases rather than programs. One program per driver, because each links only
// the client library it uses.
//
// insert  <rows> rows (bigint, text, double) through one prepared statement in one transaction
// scan    every row back through one streaming reader, summing a column so nothing is skipped
// lookup  <lookups> primary-key reads through one prepared statement, each its own reader
//
// Each phase prints its elapsed nanoseconds; benchmarks/db/run.py repeats runs and reports
// medians. benchmarks/db/c/bench.c does the same work through each C API directly.
use e.mem
use e.str
use e.io
use e.time
use e.db

error Failed

fn names() -> [16]str {
    var out: [16]str = zero
    out[0] = "alpha"
    out[1] = "bravo"
    out[2] = "charlie"
    out[3] = "delta"
    out[4] = "echo"
    out[5] = "foxtrot"
    out[6] = "golf"
    out[7] = "hotel"
    out[8] = "india"
    out[9] = "juliett"
    out[10] = "kilo"
    out[11] = "lima"
    out[12] = "mike"
    out[13] = "november"
    out[14] = "oscar"
    out[15] = "papa"
    ret out
}

// `args` is the entry program's: the location it opened, then rows and lookups. `numbered`
// writes parameters as `$1`, `$2`, ... -- PostgreSQL's spelling -- rather than `?`.
fn run(a: *mem.Arena, c: *db.Connection, driver: str, args: []str, numbered: bool) -> err {
    if args.len < 4usize { ret Failed }
    let (rows, rows_error) = str.parse_u64(args[2])
    let (lookups, lookups_error) = str.parse_u64(args[3])
    if rows_error != ok || lookups_error != ok || rows == 0u64 { ret Failed }
    var insert_sql = "INSERT INTO bench VALUES (?, ?, ?)"
    var lookup_sql = "SELECT name, score FROM bench WHERE id = ?"
    if numbered {
        insert_sql = "INSERT INTO bench VALUES ($1, $2, $3)"
        lookup_sql = "SELECT name, score FROM bench WHERE id = $1"
    }
    let (dropped, drop_error) = db.execute(c, "DROP TABLE IF EXISTS bench", zero)
    if drop_error != ok { ret drop_error }
    let (created, create_error) = db.execute(c, "CREATE TABLE bench(id BIGINT PRIMARY KEY, name VARCHAR(32) NOT NULL, score DOUBLE PRECISION NOT NULL)", zero)
    if create_error != ok { ret create_error }
    let words = names()

    // --- insert
    let (insert_started, insert_clock) = time.monotonic()
    let (tx0, begin_error) = db.begin(c)
    if begin_error != ok { ret begin_error }
    var tx = tx0
    let (insert0, prepare_error) = db.prepare(c, insert_sql)
    if prepare_error != ok { ret prepare_error }
    var insert = insert0
    var p: [3]db.Parameter = zero
    var i = 0u64
    while i < rows {
        p[0] = db.Parameter { name: "", value: db.Value{ I64: i64(i) } }
        p[1] = db.Parameter { name: "", value: db.Value{ Text: words[usize(i % 16u64)] } }
        p[2] = db.Parameter { name: "", value: db.Value{ F64: f64(i) * 0.5f64 } }
        let (n, run_error) = db.execute_statement(&insert, p[0..])
        if run_error != ok || n != 1u64 { ret Failed }
        i += 1u64
    }
    if db.close_statement(&insert) != ok { ret Failed }
    if db.commit(&tx) != ok { ret Failed }
    let insert_ns = time.since(insert_started).nanos

    // --- scan
    let (scan_started, scan_clock) = time.monotonic()
    let (scan0, scan_error) = db.query(c, "SELECT id, name, score FROM bench", zero)
    if scan_error != ok { ret scan_error }
    var scan = scan0
    var row: [3]db.Value = zero
    var count = 0u64
    var id_sum = 0i64
    var text_bytes = 0usize
    while true {
        let (more, next_error) = db.reader_next_err(&scan, row[0..])
        if next_error != ok { ret next_error }
        if !more { break }
        switch row[0] {
        case .I64 as id:
            id_sum += id
        default:
            ret Failed
        }
        switch row[1] {
        case .Text as name:
            text_bytes += name.len
        default:
            ret Failed
        }
        count += 1u64
    }
    if db.close_rows(&scan) != ok { ret Failed }
    let scan_ns = time.since(scan_started).nanos
    if count != rows || id_sum != i64(rows * (rows - 1u64) / 2u64) || text_bytes == 0usize { ret Failed }

    // --- lookup: each reader's context comes from the connection's arena, so the caller marks
    // and resets around it, as the drivers document.
    let (lookup_started, lookup_clock) = time.monotonic()
    let (select0, select_error) = db.prepare(c, lookup_sql)
    if select_error != ok { ret select_error }
    var select = select0
    var key: [1]db.Parameter = zero
    var pair: [2]db.Value = zero
    var found = 0u64
    var j = 0u64
    while j < lookups {
        let mark = mem.mark(a)
        key[0] = db.Parameter { name: "", value: db.Value{ I64: i64(j * 7919u64 % rows) } }
        let (hit0, hit_error) = db.query_statement(&select, key[0..])
        if hit_error != ok { ret hit_error }
        var hit = hit0
        let (more, next_error) = db.reader_next_err(&hit, pair[0..])
        if next_error != ok { ret next_error }
        if more { found += 1u64 }
        if db.close_rows(&hit) != ok { ret Failed }
        mem.reset(a, mark)
        j += 1u64
    }
    if db.close_statement(&select) != ok { ret Failed }
    let lookup_ns = time.since(lookup_started).nanos
    if found != lookups { ret Failed }
    if db.close(c) != ok { ret Failed }
    try io.printf["{} insert_ns={} scan_ns={} lookup_ns={}\n"](driver, insert_ns, scan_ns, lookup_ns)
    ret ok
}
