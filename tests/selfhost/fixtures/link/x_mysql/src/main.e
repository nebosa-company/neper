// `x.oracle.mysql`: an `e.db` driver over MySQL's C client library, run against a live server
// at 127.0.0.1 on the port given as the first argument, as `root` with no password, in database
// `neper` (the suites start a throwaway one with tests/selfhost/db_servers.*). Every check has
// its own exit code; each section is a function answering the first failing code, or 0.
//
// Covered: a multi-statement script; every `db.Value` kind rendered into the statement and read
// back exactly -- text with quotes, backslashes, a NUL and 4-byte UTF-8; blobs; the shortest
// double literals (0.1, 1e300, the smallest subnormal); `BIGINT UNSIGNED` past `i64`;
// microsecond datetimes; `BOOLEAN`, `DECIMAL`, `JSON`, `DATE`, `TIME`, binary strings -- and
// NULL; placeholders inside strings, identifiers and comments left alone; affected-row counts;
// server errors mapped with error number, SQLSTATE and message; the driver's refusals;
// streaming, a busy connection while it streams, a reader closed early; server-checked
// prepared statements; transactions; a 100 KB value; and a row lock refused as `Busy` across two
// connections.
use e.os
use e.mem
use e.str
use e.time
use e.db
use x.oracle.mysql

fn same_bytes(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn as_i64(v: db.Value) -> (i64, bool) {
    switch v {
    case .I64 as n:
        ret (n, true)
    default:
        ret (0i64, false)
    }
}

fn as_u64(v: db.Value) -> (u64, bool) {
    switch v {
    case .U64 as n:
        ret (n, true)
    default:
        ret (0u64, false)
    }
}

fn as_text(v: db.Value) -> (str, bool) {
    switch v {
    case .Text as s:
        ret (s, true)
    default:
        ret ("", false)
    }
}

fn as_f64(v: db.Value) -> (f64, bool) {
    switch v {
    case .F64 as x:
        ret (x, true)
    default:
        ret (0.0f64, false)
    }
}

fn as_bytes(v: db.Value) -> ([]const u8, bool) {
    var nothing: []const u8 = zero
    switch v {
    case .Bytes as data:
        ret (data, true)
    default:
        ret (nothing, false)
    }
}

fn as_bool(v: db.Value) -> (bool, bool) {
    switch v {
    case .Bool as flag:
        ret (flag, true)
    default:
        ret (false, false)
    }
}

fn as_time(v: db.Value) -> (i64, bool) {
    switch v {
    case .Time as instant:
        ret (instant.nanos, true)
    default:
        ret (0i64, false)
    }
}

fn is_null(v: db.Value) -> bool {
    switch v {
    case .Null:
        ret true
    default:
        ret false
    }
}

fn positional(value: db.Value) -> db.Parameter { ret db.Parameter { name: "", value: value } }

fn scalar(c: *db.Connection, sql: str, params: []const db.Parameter) -> (db.Value, err) {
    var nothing: db.Value = .Null
    let (rows0, query_error) = db.query(c, sql, params)
    if query_error != ok { ret (nothing, query_error) }
    var rows = rows0
    var row: [1]db.Value = zero
    let (more, next_error) = db.reader_next_err(&rows, row[0..])
    let close_error = db.close_rows(&rows)
    if next_error != ok { ret (nothing, next_error) }
    if !more { ret (nothing, db.InvalidQuery) }
    ret (row[0], ok)
}

fn scalar_i64(c: *db.Connection, sql: str) -> (i64, err) {
    let (value, value_error) = scalar(c, sql, zero)
    if value_error != ok { ret (0i64, value_error) }
    let (n, is_int) = as_i64(value)
    if !is_int { ret (0i64, db.InvalidQuery) }
    ret (n, ok)
}

fn schema() -> str {
    ret "DROP TABLE IF EXISTS item, other;\nCREATE TABLE item(id BIGINT PRIMARY KEY, name VARCHAR(100) NOT NULL, score DOUBLE, data BLOB, flag BOOLEAN, seen DATETIME(6), big BIGINT UNSIGNED, price DECIMAL(10,4), doc JSON, day DATE, span TIME, bin VARBINARY(8), label VARCHAR(20), CHECK (label <> 'bad')) ENGINE=InnoDB;\n# a comment between statements\nCREATE TABLE other(x BIGINT) ENGINE=InnoDB;"
}

fn tricky() -> str { ret "it's a \\ \"test\"\n\x00 \xf0\x9f\x98\x80 ?" }

fn values(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (schema_changed, schema_error) = db.execute(c, schema(), zero)
    if schema_error != ok { ret 10i32 }
    if schema_changed != 0u64 { ret 11i32 }

    var blob: [5]u8 = zero
    blob[0] = 1u8
    blob[2] = 255u8
    blob[4] = 39u8
    var p: [13]db.Parameter = zero
    p[0] = positional(db.Value{ I64: 1i64 })
    p[1] = positional(db.Value{ Text: tricky() })
    p[2] = positional(db.Value{ F64: 0.1f64 })
    p[3] = positional(db.Value{ Bytes: blob[0..] })
    p[4] = positional(db.Value{ Bool: true })
    p[5] = positional(db.Value{ Time: time.Instant { nanos: 1700000000123456000i64 } })
    p[6] = positional(db.Value{ U64: 18446744073709551615u64 })
    p[7] = positional(db.Value{ Text: "12345.6789" })
    p[8] = positional(db.Value{ Text: "{\"a\": 1}" })
    p[9] = positional(db.Value{ Time: time.Instant { nanos: 19782i64 * 86400000000000i64 } })
    p[10] = positional(db.Value{ Text: "12:34:56" })
    p[11] = positional(db.Value{ Bytes: blob[0usize..2usize] })
    p[12] = positional(db.Value{ Text: "tag" })
    let (inserted, insert_error) = db.execute(c, "INSERT INTO item VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", p[0..])
    if insert_error != ok { ret 12i32 }
    if inserted != 1u64 { ret 13i32 }

    var empty: [1]u8 = zero
    var q: [5]db.Parameter = zero
    q[0] = positional(db.Value{ I64: 2i64 })
    q[1] = positional(db.Value{ Text: "" })
    q[2] = positional(db.Value{ Bytes: empty[0usize..0usize] })
    q[3] = positional(db.Value{ Bool: false })
    q[4] = positional(.Null)
    let (second, second_error) = db.execute(c, "INSERT INTO item(id, name, data, flag, score) VALUES (?, ?, ?, ?, ?)", q[0..])
    if second_error != ok || second != 1u64 { ret 14i32 }

    let (rows0, query_error) = db.query(c, "SELECT id, name, score, data, flag, seen, big, price, doc, day, span, bin, label FROM item ORDER BY id", zero)
    if query_error != ok { ret 15i32 }
    var rows = rows0
    let cols = db.columns(&rows)
    if cols.len != 13usize { ret 16i32 }
    if !str.eq(cols[0].name, "id") || cols[0].kind != .I64 || cols[1].kind != .Text || cols[2].kind != .F64 || cols[3].kind != .Bytes { ret 17i32 }
    if cols[4].kind != .Bool || cols[5].kind != .Time || cols[6].kind != .U64 || cols[7].kind != .Text || cols[8].kind != .Text { ret 18i32 }
    if cols[9].kind != .Time || cols[10].kind != .Text || cols[11].kind != .Bytes || !str.eq(cols[12].name, "label") { ret 19i32 }

    var row: [13]db.Value = zero
    let (first, first_error) = db.reader_next_err(&rows, row[0..])
    if first_error != ok || !first { ret 20i32 }
    let (id1, id1_ok) = as_i64(row[0])
    if !id1_ok || id1 != 1i64 { ret 21i32 }
    let (name1, name1_ok) = as_text(row[1])
    if !name1_ok || !same_bytes(name1, tricky()) { ret 22i32 }
    let (score1, score1_ok) = as_f64(row[2])
    if !score1_ok || score1 != 0.1f64 { ret 23i32 }
    let (data1, data1_ok) = as_bytes(row[3])
    if !data1_ok || !same_bytes(data1, blob[0..]) { ret 24i32 }
    let (flag1, flag1_ok) = as_bool(row[4])
    if !flag1_ok || !flag1 { ret 25i32 }
    let (seen1, seen1_ok) = as_time(row[5])
    if !seen1_ok || seen1 != 1700000000123456000i64 { ret 26i32 }
    let (big1, big1_ok) = as_u64(row[6])
    if !big1_ok || big1 != 18446744073709551615u64 { ret 27i32 }
    let (price1, price1_ok) = as_text(row[7])
    if !price1_ok || !str.eq(price1, "12345.6789") { ret 28i32 }
    let (doc1, doc1_ok) = as_text(row[8])
    if !doc1_ok || !str.eq(doc1, "{\"a\": 1}") { ret 29i32 }
    let (day1, day1_ok) = as_time(row[9])
    if !day1_ok || day1 != 19782i64 * 86400000000000i64 { ret 30i32 }
    let (span1, span1_ok) = as_text(row[10])
    if !span1_ok || !str.eq(span1, "12:34:56") { ret 31i32 }
    let (bin1, bin1_ok) = as_bytes(row[11])
    if !bin1_ok || !same_bytes(bin1, blob[0usize..2usize]) { ret 32i32 }

    let (more2, second_row_error) = db.reader_next_err(&rows, row[0..])
    if second_row_error != ok || !more2 { ret 33i32 }
    let (name2, name2_ok) = as_text(row[1])
    if !name2_ok || name2.len != 0usize { ret 34i32 }
    let (data2, data2_ok) = as_bytes(row[3])
    if !data2_ok || data2.len != 0usize { ret 35i32 }
    let (flag2, flag2_ok) = as_bool(row[4])
    if !flag2_ok || flag2 { ret 36i32 }
    if !is_null(row[2]) || !is_null(row[5]) || !is_null(row[6]) || !is_null(row[12]) { ret 37i32 }
    let (more3, third_error) = db.reader_next_err(&rows, row[0..])
    if third_error != ok || more3 { ret 38i32 }
    if db.close_rows(&rows) != ok { ret 39i32 }

    // Doubles at the edges come back bit for bit.
    var d: [1]db.Parameter = zero
    d[0] = positional(db.Value{ F64: 1e300f64 })
    let (d1, d1_error) = scalar(c, "SELECT ? + 0", d[0..])
    let (d1v, d1_ok) = as_f64(d1)
    if d1_error != ok || !d1_ok || d1v != 1e300f64 { ret 40i32 }
    let smallest = mem.bitcast[f64](1u64)
    d[0] = positional(db.Value{ F64: smallest })
    let (d2, d2_error) = scalar(c, "SELECT ?", d[0..])
    let (d2v, d2_ok) = as_f64(d2)
    if d2_error != ok || !d2_ok || mem.bitcast[u64](d2v) != 1u64 { ret 41i32 }
    // `0.1` alone would be a DECIMAL literal; a double parameter is a double.
    d[0] = positional(db.Value{ F64: 0.1f64 })
    let (d3, d3_error) = scalar(c, "SELECT ?", d[0..])
    let (d3v, d3_ok) = as_f64(d3)
    if d3_error != ok || !d3_ok || d3v != 0.1f64 { ret 44i32 }
    // Placeholders inside a string, a quoted identifier and comments are not placeholders.
    var one: [1]db.Parameter = zero
    one[0] = positional(db.Value{ Text: "x" })
    let (lit, lit_error) = scalar(c, "SELECT CONCAT('?', ? /* ? */, \"?\") -- ?\n", one[0..])
    let (lit_text, lit_ok) = as_text(lit)
    if lit_error != ok || !lit_ok || !str.eq(lit_text, "?x?") { ret 42i32 }
    let (quoted_id, quoted_error) = scalar(c, "SELECT 5 AS `a?b`", zero)
    if quoted_error != ok { ret 43i32 }
    ret 0i32
}

fn counts_and_errors(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (updated, update_error) = db.execute(c, "UPDATE item SET score = 2.5", zero)
    if update_error != ok || updated != 2u64 { ret 50i32 }
    let (ddl, ddl_error) = db.execute(c, "CREATE INDEX item_name ON item(name)", zero)
    if ddl_error != ok || ddl != 0u64 { ret 51i32 }
    let (selected, selected_error) = db.execute(c, "SELECT * FROM item", zero)
    if selected_error != ok || selected != 0u64 { ret 52i32 }
    let (script, script_error) = db.execute(c, "INSERT INTO other VALUES (1); INSERT INTO other VALUES (2), (3);", zero)
    if script_error != ok || script != 3u64 { ret 53i32 }

    let (bad, bad_error) = db.execute(c, "SELEKT 1", zero)
    if bad_error != db.InvalidQuery { ret 54i32 }
    let (why, why_error) = mysql.detail(a, c)
    if why_error != ok || why.code != 1064u32 || !str.eq(why.sqlstate, "42000") || !str.contains(why.message, "syntax") { ret 55i32 }
    let (missing, missing_error) = db.query(c, "SELECT * FROM nowhere", zero)
    if missing_error != db.InvalidQuery { ret 56i32 }
    let (why_missing, why_missing_error) = mysql.detail(a, c)
    if why_missing_error != ok || why_missing.code != 1146u32 { ret 57i32 }
    // A failure later in a script stops it there, with the rows before it kept.
    let (partial, partial_error) = db.execute(c, "INSERT INTO other VALUES (4); INSERT INTO nowhere VALUES (1); INSERT INTO other VALUES (5)", zero)
    if partial_error != db.InvalidQuery { ret 58i32 }
    let (after_partial, after_partial_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if after_partial_error != ok || after_partial != 4i64 { ret 59i32 }

    var dup: [2]db.Parameter = zero
    dup[0] = positional(db.Value{ I64: 1i64 })
    dup[1] = positional(db.Value{ Text: "again" })
    let (dup_n, dup_error) = db.execute(c, "INSERT INTO item(id, name) VALUES (?, ?)", dup[0..])
    if dup_error != db.Constraint { ret 60i32 }
    let (why_dup, why_dup_error) = mysql.detail(a, c)
    if why_dup_error != ok || why_dup.code != 1062u32 || !str.eq(why_dup.sqlstate, "23000") { ret 61i32 }
    let (nn_n, nn_error) = db.execute(c, "INSERT INTO item(id, name) VALUES (9, NULL)", zero)
    if nn_error != db.Constraint { ret 62i32 }
    let (check_n, check_error) = db.execute(c, "INSERT INTO item(id, name, label) VALUES (9, 'x', 'bad')", zero)
    if check_error != db.Constraint { ret 63i32 }
    // A CHECK violation is reported under `HY000`, so it is mapped by its number.
    let (why_check, why_check_error) = mysql.detail(a, c)
    if why_check_error != ok || why_check.code != 3819u32 { ret 64i32 }

    let (few, few_error) = db.execute(c, "INSERT INTO item(id, name) VALUES (?, ?)", dup[0usize..1usize])
    if few_error != db.InvalidQuery { ret 65i32 }
    let (why_few, why_few_error) = mysql.detail(a, c)
    if why_few_error != ok || why_few.code != 0u32 || !str.contains(why_few.message, "parameter count") { ret 66i32 }
    var named: [1]db.Parameter = zero
    named[0] = db.Parameter { name: "id", value: db.Value{ I64: 1i64 } }
    let (named_rows, named_error) = db.query(c, "SELECT ?", named[0..])
    if named_error != db.InvalidQuery { ret 67i32 }
    var inf: [1]db.Parameter = zero
    inf[0] = positional(db.Value{ F64: mem.bitcast[f64](9218868437227405312u64) })
    let (inf_rows, inf_error) = db.query(c, "SELECT ?", inf[0..])
    if inf_error != db.Unsupported { ret 68i32 }
    let (two, two_error) = db.query(c, "SELECT 1; SELECT 2", zero)
    if two_error != db.InvalidQuery { ret 69i32 }
    let (empty_n, empty_error) = db.execute(c, "  -- nothing\n", zero)
    if empty_error != ok || empty_n != 0u64 { ret 70i32 }
    let (trailing0, trailing_error) = db.query(c, "SELECT 7; -- done", zero)
    if trailing_error != ok { ret 71i32 }
    var trailing = trailing0
    if db.close_rows(&trailing) != ok { ret 72i32 }

    let (short0, short_error) = db.query(c, "SELECT 1, 2", zero)
    if short_error != ok { ret 73i32 }
    var short = short0
    var slot: [1]db.Value = zero
    let (short_more, short_next_error) = db.reader_next_err(&short, slot[0..])
    if short_next_error != db.InvalidQuery { ret 74i32 }
    if db.close_rows(&short) != ok { ret 75i32 }
    let (count_now, count_error) = scalar_i64(c, "SELECT count(*) FROM item")
    if count_error != ok || count_now != 2i64 { ret 76i32 }
    let (why_ok, why_ok_error) = mysql.detail(a, c)
    if why_ok_error != ok || why_ok.code != 0u32 || why_ok.message.len != 0usize { ret 77i32 }
    ret 0i32
}

fn streaming(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (all0, all_error) = db.query(c, "WITH RECURSIVE g(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM g WHERE n < 1000) SELECT n FROM g", zero)
    if all_error != ok { ret 90i32 }
    var all = all0
    let (busy_n, busy_error) = db.execute(c, "SELECT 1", zero)
    if busy_error != db.Busy { ret 91i32 }
    let (busy_tx, busy_tx_error) = db.begin(c)
    if busy_tx_error != db.Busy { ret 92i32 }
    var row: [1]db.Value = zero
    var count = 0i64
    var sum = 0i64
    while true {
        let (more, next_error) = db.reader_next_err(&all, row[0..])
        if next_error != ok { ret 93i32 }
        if !more { break }
        let (x, is_int) = as_i64(row[0])
        if !is_int { ret 94i32 }
        count += 1i64
        sum += x
    }
    if count != 1000i64 || sum != 500500i64 { ret 95i32 }
    if db.close_rows(&all) != ok { ret 96i32 }
    let (part0, part_error) = db.query(c, "WITH RECURSIVE g(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM g WHERE n < 1000) SELECT a.n FROM g AS a, g AS b", zero)
    if part_error != ok { ret 97i32 }
    var part = part0
    var k = 0usize
    while k < 10usize {
        let (part_more, part_next_error) = db.reader_next_err(&part, row[0..])
        if part_next_error != ok || !part_more { ret 98i32 }
        k += 1usize
    }
    if db.close_rows(&part) != ok { ret 99i32 }
    let (after, after_error) = scalar_i64(c, "SELECT 5")
    if after_error != ok || after != 5i64 { ret 100i32 }

    let (big, big_alloc_error) = mem.alloc[u8](a, 100000usize)
    if big_alloc_error != ok { ret 101i32 }
    var i = 0usize
    while i < big.len {
        big[i] = u8(97usize + i % 26usize)
        i += 1usize
    }
    var big_param: [1]db.Parameter = zero
    big_param[0] = positional(db.Value{ Text: big })
    let (back0, back_error) = db.query(c, "SELECT ?, CHAR_LENGTH(?)", zero)
    if back_error != db.InvalidQuery { ret 102i32 }
    var both: [2]db.Parameter = zero
    both[0] = big_param[0]
    both[1] = big_param[0]
    let (back1, back1_error) = db.query(c, "SELECT ?, CHAR_LENGTH(?)", both[0..])
    if back1_error != ok { ret 103i32 }
    var back = back1
    var pair: [2]db.Value = zero
    let (got, got_error) = db.reader_next_err(&back, pair[0..])
    let (back_text, back_ok) = as_text(pair[0])
    let (back_len, back_len_ok) = as_i64(pair[1])
    if got_error != ok || !got || !back_ok || !same_bytes(back_text, big) || !back_len_ok || back_len != 100000i64 { ret 104i32 }
    if db.close_rows(&back) != ok { ret 105i32 }
    ret 0i32
}

fn statements(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (insert0, prepare_error) = db.prepare(c, "INSERT INTO item(id, name, big) VALUES (?, ?, ?)")
    if prepare_error != ok { ret 120i32 }
    var insert = insert0
    var p: [3]db.Parameter = zero
    var id = 100i64
    while id < 200i64 {
        p[0] = positional(db.Value{ I64: id })
        p[1] = positional(db.Value{ Text: "row" })
        p[2] = positional(db.Value{ U64: u64(id) * 1000u64 })
        let (n, run_error) = db.execute_statement(&insert, p[0..])
        if run_error != ok || n != 1u64 { ret 121i32 }
        id += 1i64
    }
    let (short_n, short_error) = db.execute_statement(&insert, p[0usize..2usize])
    if short_error != db.InvalidQuery { ret 122i32 }
    if db.close_statement(&insert) != ok { ret 123i32 }
    // The server compiles the text at prepare, so a statement that cannot run fails there.
    let (bad_statement, bad_error) = db.prepare(c, "SELECT * FROM nowhere WHERE x = ?")
    if bad_error != db.InvalidQuery { ret 124i32 }
    let (why, why_error) = mysql.detail(a, c)
    if why_error != ok || why.code != 1146u32 { ret 125i32 }
    let (two_statements, two_error) = db.prepare(c, "SELECT 1; SELECT 2")
    if two_error != db.InvalidQuery { ret 126i32 }

    let (select0, select_error) = db.prepare(c, "SELECT big FROM item WHERE id >= ? ORDER BY id")
    if select_error != ok { ret 127i32 }
    var select = select0
    var bound: [1]db.Parameter = zero
    bound[0] = positional(db.Value{ I64: 190i64 })
    let (first0, first_error) = db.query_statement(&select, bound[0..])
    if first_error != ok { ret 128i32 }
    var first = first0
    var row: [1]db.Value = zero
    var sum = 0i64
    while true {
        let (more, next_error) = db.reader_next_err(&first, row[0..])
        if next_error != ok { ret 129i32 }
        if !more { break }
        // `BIGINT UNSIGNED` inside `i64` reads back as `I64`.
        let (x, is_int) = as_i64(row[0])
        if !is_int { ret 130i32 }
        sum += x
    }
    if sum != 1945000i64 { ret 131i32 }
    if db.close_rows(&first) != ok { ret 132i32 }
    bound[0] = positional(db.Value{ I64: 198i64 })
    let (tail0, tail_error) = db.query_statement(&select, bound[0..])
    if tail_error != ok { ret 133i32 }
    var tail = tail0
    let (t1, t1_error) = db.reader_next_err(&tail, row[0..])
    let (v1, v1_ok) = as_i64(row[0])
    if t1_error != ok || !t1 || !v1_ok || v1 != 198000i64 { ret 134i32 }
    if db.close_statement(&select) != ok { ret 135i32 }
    let (t2, t2_error) = db.reader_next_err(&tail, row[0..])
    if t2_error != db.Closed { ret 136i32 }
    if db.close_rows(&tail) != ok { ret 137i32 }
    let (after, after_error) = scalar_i64(c, "SELECT count(*) FROM item")
    if after_error != ok || after != 102i64 { ret 138i32 }
    ret 0i32
}

// `reader_next_borrowed` hands back the library's own bytes: each row checked before the
// next is read, the copying reader interleaved on the same stream, a 60 KB value, an empty
// one, and `Closed` after the close.
fn borrowed(c: *db.Connection) -> i32 {
    let (made, made_error) = db.execute(c, "DROP TABLE IF EXISTS words; CREATE TABLE words(id BIGINT, w TEXT, b BLOB) ENGINE=InnoDB; INSERT INTO words VALUES (1, 'alpha', X'0001'), (2, 'bravo', X'02'), (3, REPEAT('xyz', 20000), NULL), (4, '', NULL);", zero)
    if made_error != ok { ret 190i32 }
    let (rows0, rows_error) = db.query(c, "SELECT w, b FROM words ORDER BY id", zero)
    if rows_error != ok { ret 191i32 }
    var rows = rows0
    var row: [2]db.Value = zero
    let (m1, e1) = db.reader_next_borrowed(&rows, row[0..])
    let (w1, w1_ok) = as_text(row[0])
    let (b1, b1_ok) = as_bytes(row[1])
    if e1 != ok || !m1 || !w1_ok || !same_bytes(w1, "alpha") || !b1_ok || b1.len != 2usize || b1[0usize] != 0u8 || b1[1usize] != 1u8 { ret 192i32 }
    let (m2, e2) = db.reader_next_err(&rows, row[0..])
    let (w2, w2_ok) = as_text(row[0])
    if e2 != ok || !m2 || !w2_ok || !same_bytes(w2, "bravo") { ret 193i32 }
    let (m3, e3) = db.reader_next_borrowed(&rows, row[0..])
    let (w3, w3_ok) = as_text(row[0])
    if e3 != ok || !m3 || !w3_ok || w3.len != 60000usize || w3[0usize] != 120u8 || w3[59999usize] != 122u8 || !is_null(row[1]) { ret 194i32 }
    let (m4, e4) = db.reader_next_borrowed(&rows, row[0..])
    let (w4, w4_ok) = as_text(row[0])
    if e4 != ok || !m4 || !w4_ok || w4.len != 0usize { ret 195i32 }
    let (m5, e5) = db.reader_next_borrowed(&rows, row[0..])
    if e5 != ok || m5 { ret 196i32 }
    if db.close_rows(&rows) != ok { ret 197i32 }
    let (m6, e6) = db.reader_next_borrowed(&rows, row[0..])
    if e6 != db.Closed { ret 198i32 }
    ret 0i32
}

fn transactions(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (tx0, begin_error) = db.begin(c)
    if begin_error != ok { ret 140i32 }
    var tx = tx0
    let (nested, nested_error) = db.begin(c)
    if nested_error != db.Busy { ret 141i32 }
    let (n1, e1) = db.execute_transaction(&tx, "INSERT INTO other VALUES (10)", zero)
    if e1 != ok || n1 != 1u64 { ret 142i32 }
    if db.rollback(&tx) != ok { ret 143i32 }
    if db.rollback(&tx) != db.Closed { ret 144i32 }
    let (after_rollback, after_rollback_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if after_rollback_error != ok || after_rollback != 4i64 { ret 145i32 }

    let (tx1, begin1_error) = db.begin(c)
    if begin1_error != ok { ret 146i32 }
    var kept = tx1
    let (n2, e2) = db.execute_transaction(&kept, "INSERT INTO other VALUES (11)", zero)
    if e2 != ok { ret 147i32 }
    let (inside0, inside_error) = db.query_transaction(&kept, "SELECT count(*) FROM other", zero)
    if inside_error != ok { ret 148i32 }
    var inside = inside0
    var row: [1]db.Value = zero
    let (inside_more, inside_next_error) = db.reader_next_err(&inside, row[0..])
    let (inside_n, inside_ok) = as_i64(row[0])
    if inside_next_error != ok || !inside_more || !inside_ok || inside_n != 5i64 { ret 149i32 }
    if db.commit(&kept) != ok { ret 150i32 }
    if db.close_rows(&inside) != ok { ret 151i32 }
    let (after_commit, after_commit_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if after_commit_error != ok || after_commit != 5i64 { ret 152i32 }
    // A failed statement inside leaves the transaction open and rollback-able.
    let (tx2, begin2_error) = db.begin(c)
    if begin2_error != ok { ret 153i32 }
    var failing = tx2
    let (n3, e3) = db.execute_transaction(&failing, "INSERT INTO other VALUES (12)", zero)
    if e3 != ok { ret 154i32 }
    let (n4, e4) = db.execute_transaction(&failing, "INSERT INTO nowhere VALUES (1)", zero)
    if e4 != db.InvalidQuery { ret 155i32 }
    if db.rollback(&failing) != ok { ret 156i32 }
    let (after_fail, after_fail_error) = scalar_i64(c, "SELECT count(*) FROM other WHERE x >= 12")
    if after_fail_error != ok || after_fail != 0i64 { ret 157i32 }
    ret 0i32
}

fn two_connections(a: *mem.Arena, options: mysql.Options) -> i32 {
    let (first0, first_error) = mysql.open(a, options)
    if first_error != ok { ret 170i32 }
    var first = first0
    let (second0, second_error) = mysql.open(a, options)
    if second_error != ok { ret 171i32 }
    var second = second0
    let (tx0, begin_error) = db.begin(&first)
    if begin_error != ok { ret 172i32 }
    var tx = tx0
    let (locked0, lock_error) = db.query_transaction(&tx, "SELECT id FROM item WHERE id = 1 FOR UPDATE", zero)
    if lock_error != ok { ret 173i32 }
    var locked = locked0
    if db.close_rows(&locked) != ok { ret 174i32 }
    let (blocked, blocked_error) = db.query(&second, "SELECT id FROM item WHERE id = 1 FOR UPDATE NOWAIT", zero)
    if blocked_error != db.Busy { ret 175i32 }
    let (why, why_error) = mysql.detail(a, &second)
    if why_error != ok || why.code != 3572u32 { ret 176i32 }
    if db.rollback(&tx) != ok { ret 177i32 }
    let (free0, free_error) = db.query(&second, "SELECT id FROM item WHERE id = 1 FOR UPDATE NOWAIT", zero)
    if free_error != ok { ret 178i32 }
    var free = free0
    if db.close_rows(&free) != ok { ret 179i32 }
    if db.close(&second) != ok { ret 180i32 }
    if db.close(&first) != ok { ret 181i32 }
    if db.close(&first) != db.Closed { ret 182i32 }
    let (closed_n, closed_error) = db.execute(&first, "SELECT 1", zero)
    if closed_error != db.Closed { ret 183i32 }
    var refused_options = options
    refused_options.port = 1u16
    let (refused, refused_error) = mysql.open(a, refused_options)
    if refused_error != mysql.CannotConnect { ret 184i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { os.exit(1i32) }
    if mysql.version() < 50700usize { os.exit(2i32) }
    let (port, port_error) = str.parse_u64(args[1])
    if port_error != ok || port > 65535u64 { os.exit(3i32) }
    let options = mysql.Options { host: "127.0.0.1", port: u16(port), user: "root", password: "", database: "neper" }
    let (conn0, open_error) = mysql.open(a, options)
    if open_error != ok { os.exit(4i32) }
    var c = conn0
    var code = values(a, &c)
    if code == 0i32 { code = counts_and_errors(a, &c) }
    if code == 0i32 { code = streaming(a, &c) }
    if code == 0i32 { code = statements(a, &c) }
    if code == 0i32 { code = borrowed(&c) }
    if code == 0i32 { code = transactions(a, &c) }
    if code == 0i32 { code = two_connections(a, options) }
    if code == 0i32 && db.close(&c) != ok { code = 5i32 }
    if code != 0i32 { os.exit(code) }
    ret ok
}
