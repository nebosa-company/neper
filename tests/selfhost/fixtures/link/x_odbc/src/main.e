// `x.microsoft.odbc`: an `e.db` driver over the host's ODBC driver manager, run against a live
// PostgreSQL through psqlODBC. The first argument is the ODBC connection string (the suites
// start a throwaway server with tests/selfhost/db_servers.* and name the driver by a per-user
// DSN on Windows and by its path on Linux; `BoolsAsChar=0` makes psqlODBC report `boolean` as
// `SQL_BIT`). Every check has its own exit code; each section is a function answering the first
// failing code, or 0.
//
// Covered: every `db.Value` kind bound and read back through the wide API (bigint, int2/int4,
// float8/float4, boolean, bytea with NULs, text with 4-byte UTF-8 and a leading U+FEFF,
// timestamp and date as UTC, numeric as text, NULL, empty text and bytea), a column name
// outside ASCII; affected-row counts summed over a script, and an UPDATE that matched nothing;
// SQLSTATEs mapped onto `e.db`'s errors with `detail` carrying state, native code and message;
// the driver's own refusals; prepared statements reused, closed under their reader, and
// refused at `prepare`; 1000 rows and a reader closed early; 100 KB text and bytea read in
// pieces; transactions committed, rolled back, refused when nested, and aborted by a failed
// statement; a row lock refused as `Busy` across two connections; and a missing data source.
use e.os
use e.mem
use e.str
use e.time
use e.db
use x.microsoft.odbc

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

// The single value the query answers.
fn scalar(c: *db.Connection, sql: str) -> (db.Value, err) {
    var nothing: db.Value = .Null
    let (rows0, query_error) = db.query(c, sql, zero)
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
    let (value, value_error) = scalar(c, sql)
    if value_error != ok { ret (0i64, value_error) }
    let (n, is_int) = as_i64(value)
    if !is_int { ret (0i64, db.InvalidQuery) }
    ret (n, ok)
}

fn schema() -> str {
    ret "DROP TABLE IF EXISTS item; DROP TABLE IF EXISTS other;\nCREATE TABLE item(id bigint PRIMARY KEY, name text NOT NULL, score float8, data bytea, flag boolean, seen timestamp, small int2, medium int4, single float4, amount numeric(12,6), day date, label varchar(20) CHECK (label <> 'bad'));\nCREATE TABLE other(x bigint);"
}

fn values(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (schema_changed, schema_error) = db.execute(c, schema(), zero)
    if schema_error != ok { ret 10i32 }
    if schema_changed != 0u64 { ret 11i32 }

    var blob: [5]u8 = zero
    blob[0] = 1u8
    blob[2] = 255u8
    blob[4] = 7u8
    var p: [12]db.Parameter = zero
    p[0] = positional(db.Value{ I64: 1i64 })
    // A leading U+FEFF, a two-byte, a three-byte and a four-byte (surrogate pair) character.
    p[1] = positional(db.Value{ Text: "\xef\xbb\xbfh\xc3\xa9llo \xe2\x82\xac \xf0\x9f\x98\x80" })
    p[2] = positional(db.Value{ F64: 0.1f64 })
    p[3] = positional(db.Value{ Bytes: blob[0..] })
    p[4] = positional(db.Value{ Bool: true })
    p[5] = positional(db.Value{ Time: time.Instant { nanos: 1700000000123456000i64 } })
    p[6] = positional(db.Value{ I64: -32768i64 })
    p[7] = positional(db.Value{ I64: 2147483647i64 })
    p[8] = positional(db.Value{ F64: 0.5f64 })
    p[9] = positional(db.Value{ Text: "12345.678900" })
    p[10] = positional(db.Value{ Time: time.Instant { nanos: 1709164800000000000i64 } })
    p[11] = positional(db.Value{ Text: "tag" })
    let (inserted, insert_error) = db.execute(c, "INSERT INTO item VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", p[0..])
    if insert_error != ok { ret 12i32 }
    if inserted != 1u64 { ret 13i32 }

    // Empty text and bytea, false, NULLs everywhere else.
    var empty: [1]u8 = zero
    var q: [5]db.Parameter = zero
    q[0] = positional(db.Value{ I64: 2i64 })
    q[1] = positional(db.Value{ Text: "" })
    q[2] = positional(db.Value{ Bytes: empty[0usize..0usize] })
    q[3] = positional(db.Value{ Bool: false })
    q[4] = positional(.Null)
    let (second, second_error) = db.execute(c, "INSERT INTO item(id, name, data, flag, score) VALUES (?, ?, ?, ?, ?)", q[0..])
    if second_error != ok || second != 1u64 { ret 14i32 }

    let (rows0, query_error) = db.query(c, "SELECT id, name, score, data, flag, seen, small, medium, single, amount, day, label FROM item ORDER BY id", zero)
    if query_error != ok { ret 15i32 }
    var rows = rows0
    let cols = db.columns(&rows)
    if cols.len != 12usize { ret 16i32 }
    if !str.eq(cols[0].name, "id") || cols[0].kind != .I64 || cols[1].kind != .Text || cols[2].kind != .F64 { ret 17i32 }
    if cols[3].kind != .Bytes || cols[4].kind != .Bool || cols[5].kind != .Time || cols[6].kind != .I64 || cols[7].kind != .I64 { ret 18i32 }
    if cols[8].kind != .F64 || cols[9].kind != .Text || cols[10].kind != .Time || cols[11].kind != .Text { ret 19i32 }
    if cols[0].nullable || cols[1].nullable || !cols[2].nullable { ret 20i32 }

    var row: [12]db.Value = zero
    let (first, first_error) = db.reader_next_err(&rows, row[0..])
    if first_error != ok || !first { ret 21i32 }
    let (id1, id1_ok) = as_i64(row[0])
    if !id1_ok || id1 != 1i64 { ret 22i32 }
    let (name1, name1_ok) = as_text(row[1])
    if !name1_ok || !str.eq(name1, "\xef\xbb\xbfh\xc3\xa9llo \xe2\x82\xac \xf0\x9f\x98\x80") { ret 23i32 }
    let (score1, score1_ok) = as_f64(row[2])
    if !score1_ok || score1 != 0.1f64 { ret 24i32 }
    let (data1, data1_ok) = as_bytes(row[3])
    if !data1_ok || !same_bytes(data1, blob[0..]) { ret 25i32 }
    let (flag1, flag1_ok) = as_bool(row[4])
    if !flag1_ok || !flag1 { ret 26i32 }
    let (seen1, seen1_ok) = as_time(row[5])
    if !seen1_ok || seen1 != 1700000000123456000i64 { ret 27i32 }
    let (small1, small1_ok) = as_i64(row[6])
    if !small1_ok || small1 != -32768i64 { ret 28i32 }
    let (medium1, medium1_ok) = as_i64(row[7])
    if !medium1_ok || medium1 != 2147483647i64 { ret 29i32 }
    let (single1, single1_ok) = as_f64(row[8])
    if !single1_ok || single1 != 0.5f64 { ret 30i32 }
    let (amount1, amount1_ok) = as_text(row[9])
    if !amount1_ok || !str.eq(amount1, "12345.678900") { ret 31i32 }
    let (day1, day1_ok) = as_time(row[10])
    if !day1_ok || day1 != 1709164800000000000i64 { ret 32i32 }
    let (label1, label1_ok) = as_text(row[11])
    if !label1_ok || !str.eq(label1, "tag") { ret 33i32 }

    let (more2, second_row_error) = db.reader_next_err(&rows, row[0..])
    if second_row_error != ok || !more2 { ret 34i32 }
    let (name2, name2_ok) = as_text(row[1])
    if !name2_ok || name2.len != 0usize { ret 35i32 }
    let (data2, data2_ok) = as_bytes(row[3])
    if !data2_ok || data2.len != 0usize { ret 36i32 }
    let (flag2, flag2_ok) = as_bool(row[4])
    if !flag2_ok || flag2 { ret 37i32 }
    if !is_null(row[2]) || !is_null(row[5]) || !is_null(row[6]) || !is_null(row[9]) || !is_null(row[10]) || !is_null(row[11]) { ret 38i32 }
    let (more3, end_error) = db.reader_next_err(&rows, row[0..])
    if end_error != ok || more3 { ret 39i32 }
    if db.close_rows(&rows) != ok { ret 40i32 }

    // A column name outside ASCII, and a double and an unsigned value bound where no column
    // decides their type.
    let (named0, named_error) = db.query(c, "SELECT 1 AS \"na\xc3\xafve\"", zero)
    if named_error != ok { ret 41i32 }
    var named = named0
    let named_cols = db.columns(&named)
    if named_cols.len != 1usize || !str.eq(named_cols[0].name, "na\xc3\xafve") { ret 42i32 }
    if db.close_rows(&named) != ok { ret 43i32 }
    var u: [1]db.Parameter = zero
    u[0] = positional(db.Value{ U64: 4000000000u64 })
    let (bigger, bigger_error) = db.execute(c, "UPDATE item SET medium = 0 WHERE id + ? > 4000000000", u[0..])
    if bigger_error != ok || bigger != 2u64 { ret 44i32 }
    ret 0i32
}

fn counts_and_errors(a: *mem.Arena, c: *db.Connection) -> i32 {
    // Rows changed are summed over the script; the SELECT in it counts nothing.
    let (script, script_error) = db.execute(c, "INSERT INTO other VALUES (1), (2); SELECT 1; UPDATE other SET x = x + 10; INSERT INTO other VALUES (3)", zero)
    if script_error != ok || script != 5u64 { ret 50i32 }
    // A searched UPDATE that matches nothing answers SQL_NO_DATA from SQLExecute.
    let (none, none_error) = db.execute(c, "UPDATE other SET x = 0 WHERE x < 0", zero)
    if none_error != ok || none != 0u64 { ret 51i32 }
    let (clean, clean_error) = odbc.detail(a, c)
    if clean_error != ok || clean.sqlstate.len != 0usize || clean.message.len != 0usize || clean.native != 0i32 { ret 52i32 }

    var dup: [3]db.Parameter = zero
    dup[0] = positional(db.Value{ I64: 1i64 })
    dup[1] = positional(db.Value{ Text: "again" })
    dup[2] = positional(db.Value{ Text: "ok" })
    let (d, dup_error) = db.execute(c, "INSERT INTO item(id, name, label) VALUES (?, ?, ?)", dup[0..])
    if dup_error != db.Constraint { ret 53i32 }
    let (why, why_error) = odbc.detail(a, c)
    if why_error != ok || !str.eq(why.sqlstate, "23505") || why.message.len == 0usize { ret 54i32 }
    dup[0] = positional(db.Value{ I64: 3i64 })
    dup[2] = positional(db.Value{ Text: "bad" })
    let (k, check_error) = db.execute(c, "INSERT INTO item(id, name, label) VALUES (?, ?, ?)", dup[0..])
    if check_error != db.Constraint { ret 55i32 }
    let (syntax, syntax_error) = db.execute(c, "SELEC 1", zero)
    if syntax_error != db.InvalidQuery { ret 56i32 }
    let (syntax_why, syntax_why_error) = odbc.detail(a, c)
    if syntax_why_error != ok || !str.eq(syntax_why.sqlstate, "42601") { ret 57i32 }
    let (divided, divide_error) = db.execute(c, "SELECT 1 / 0", zero)
    if divide_error != db.InvalidQuery { ret 58i32 }
    let (missing, missing_error) = db.query(c, "SELECT * FROM nowhere", zero)
    if missing_error != db.InvalidQuery { ret 59i32 }

    // The driver's own refusals: a named parameter, and a count that differs.
    var named: [1]db.Parameter = zero
    named[0] = db.Parameter { name: "id", value: db.Value{ I64: 1i64 } }
    let (n1, named_error) = db.execute(c, "SELECT ?", named[0..])
    if named_error != db.InvalidQuery { ret 60i32 }
    let (refusal, refusal_error) = odbc.detail(a, c)
    if refusal_error != ok || refusal.sqlstate.len != 0usize || refusal.native != 0i32 || refusal.message.len == 0usize { ret 61i32 }
    let (n2, count_error) = db.execute(c, "SELECT ?, ?", dup[0..1])
    if count_error != db.InvalidQuery { ret 62i32 }
    var row: [1]db.Value = zero
    let (echo0, echo_error) = db.query(c, "SELECT count(*) FROM other", zero)
    if echo_error != ok { ret 63i32 }
    var echo = echo0
    let (short, short_error) = db.reader_next_err(&echo, row[0usize..0usize])
    if short_error != db.InvalidQuery { ret 64i32 }
    if db.close_rows(&echo) != ok { ret 65i32 }
    ret 0i32
}

fn statements(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (st0, prepare_error) = db.prepare(c, "INSERT INTO other VALUES (?)")
    if prepare_error != ok { ret 70i32 }
    var st = st0
    var p: [1]db.Parameter = zero
    var i = 0i64
    while i < 3i64 {
        p[0] = positional(db.Value{ I64: 100i64 + i })
        let (n, e) = db.execute_statement(&st, p[0..])
        if e != ok || n != 1u64 { ret 71i32 }
        i += 1i64
    }
    if db.close_statement(&st) != ok { ret 72i32 }
    let (after, after_error) = db.execute_statement(&st, p[0..])
    if after_error != db.Closed { ret 73i32 }

    let (sel0, sel_error) = db.prepare(c, "SELECT x FROM other WHERE x >= ? ORDER BY x")
    if sel_error != ok { ret 74i32 }
    var sel = sel0
    p[0] = positional(db.Value{ I64: 101i64 })
    let (r0, r_error) = db.query_statement(&sel, p[0..])
    if r_error != ok { ret 75i32 }
    var r = r0
    var row: [1]db.Value = zero
    let (m1, e1) = db.reader_next_err(&r, row[0..])
    let (x1, x1_ok) = as_i64(row[0])
    if e1 != ok || !m1 || !x1_ok || x1 != 101i64 { ret 76i32 }
    // Running the statement again starts over.
    p[0] = positional(db.Value{ I64: 102i64 })
    let (r1, again_error) = db.query_statement(&sel, p[0..])
    if again_error != ok { ret 77i32 }
    var again = r1
    let (m2, e2) = db.reader_next_err(&again, row[0..])
    let (x2, x2_ok) = as_i64(row[0])
    if e2 != ok || !m2 || !x2_ok || x2 != 102i64 { ret 78i32 }
    // Closing the statement under its reader: the reader answers `Closed`.
    if db.close_statement(&sel) != ok { ret 79i32 }
    let (m3, e3) = db.reader_next_err(&again, row[0..])
    if e3 != db.Closed { ret 80i32 }
    if db.close_rows(&again) != ok { ret 81i32 }

    let (bad, bad_error) = db.prepare(c, "SELECT nothing_here FROM other")
    if bad_error != db.InvalidQuery { ret 82i32 }
    ret 0i32
}

fn streaming(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (rows0, rows_error) = db.query(c, "SELECT g, repeat('x', g % 7) FROM generate_series(1, 1000) AS g", zero)
    if rows_error != ok { ret 90i32 }
    var rows = rows0
    var row: [2]db.Value = zero
    var total = 0i64
    var count = 0i64
    while true {
        let (more, next_error) = db.reader_next_err(&rows, row[0..])
        if next_error != ok { ret 91i32 }
        if !more { break }
        let (g, g_ok) = as_i64(row[0])
        let (s, s_ok) = as_text(row[1])
        if !g_ok || !s_ok || i64(s.len) != g % 7i64 { ret 92i32 }
        total += g
        count += 1i64
    }
    if count != 1000i64 || total != 500500i64 { ret 93i32 }
    if db.close_rows(&rows) != ok { ret 94i32 }

    // A reader closed after one row; the connection goes on.
    let (early0, early_error) = db.query(c, "SELECT g FROM generate_series(1, 500) AS g", zero)
    if early_error != ok { ret 95i32 }
    var early = early0
    let (e_more, e_next_error) = db.reader_next_err(&early, row[0..])
    if e_next_error != ok || !e_more { ret 96i32 }
    if db.close_rows(&early) != ok { ret 97i32 }
    if db.close_rows(&early) != db.Closed { ret 98i32 }
    let (n, n_error) = scalar_i64(c, "SELECT 42")
    if n_error != ok || n != 42i64 { ret 99i32 }

    // 100 KB of text (two-byte characters, so 200 KB of UTF-16) and of bytes: several
    // `SQLGetData` pieces each.
    let (big, big_error) = mem.alloc[u8](a, 100000usize)
    if big_error != ok { ret 100i32 }
    var i = 0usize
    while i < big.len {
        big[i] = u8(i % 251usize)
        i += 1usize
    }
    let (text, text_error) = mem.alloc[u8](a, 100000usize)
    if text_error != ok { ret 101i32 }
    i = 0usize
    while i < text.len {
        text[i] = 195u8
        text[i + 1usize] = 169u8
        i += 2usize
    }
    let long_text: str = text
    var p: [3]db.Parameter = zero
    p[0] = positional(db.Value{ I64: 50i64 })
    p[1] = positional(db.Value{ Text: long_text })
    p[2] = positional(db.Value{ Bytes: big })
    let (stored, store_error) = db.execute(c, "INSERT INTO item(id, name, data) VALUES (?, ?, ?)", p[0..])
    if store_error != ok || stored != 1u64 { ret 102i32 }
    let (back0, back_error) = db.query(c, "SELECT name, data FROM item WHERE id = 50", zero)
    if back_error != ok { ret 103i32 }
    var back = back0
    let (b_more, b_error) = db.reader_next_err(&back, row[0..])
    if b_error != ok || !b_more { ret 104i32 }
    let (name, name_ok) = as_text(row[0])
    if !name_ok || !same_bytes(name, text) { ret 105i32 }
    let (data, data_ok) = as_bytes(row[1])
    if !data_ok || !same_bytes(data, big) { ret 106i32 }
    if db.close_rows(&back) != ok { ret 107i32 }
    ret 0i32
}

fn transactions(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (before, before_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if before_error != ok { ret 110i32 }
    let (tx0, begin_error) = db.begin(c)
    if begin_error != ok { ret 111i32 }
    var tx = tx0
    let (nested, nested_error) = db.begin(c)
    if nested_error != db.Busy { ret 112i32 }
    let (n1, e1) = db.execute_transaction(&tx, "INSERT INTO other VALUES (10)", zero)
    if e1 != ok || n1 != 1u64 { ret 113i32 }
    if db.rollback(&tx) != ok { ret 114i32 }
    if db.rollback(&tx) != db.Closed { ret 115i32 }
    let (after_rollback, after_rollback_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if after_rollback_error != ok || after_rollback != before { ret 116i32 }

    let (tx1, begin1_error) = db.begin(c)
    if begin1_error != ok { ret 117i32 }
    var kept = tx1
    let (n2, e2) = db.execute_transaction(&kept, "INSERT INTO other VALUES (11)", zero)
    if e2 != ok { ret 118i32 }
    let (inside0, inside_error) = db.query_transaction(&kept, "SELECT count(*) FROM other", zero)
    if inside_error != ok { ret 119i32 }
    var inside = inside0
    var row: [1]db.Value = zero
    let (inside_more, inside_next_error) = db.reader_next_err(&inside, row[0..])
    let (inside_n, inside_ok) = as_i64(row[0])
    if inside_next_error != ok || !inside_more || !inside_ok || inside_n != before + 1i64 { ret 120i32 }
    if db.close_rows(&inside) != ok { ret 121i32 }
    if db.commit(&kept) != ok { ret 122i32 }
    let (after_commit, after_commit_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if after_commit_error != ok || after_commit != before + 1i64 { ret 123i32 }
    // Autocommit is back: a plain insert lands without a transaction.
    let (n3, e3) = db.execute(c, "INSERT INTO other VALUES (12)", zero)
    if e3 != ok || n3 != 1u64 { ret 124i32 }

    // psqlODBC rolls back only a failed statement (its default statement-level rollback, done
    // with savepoints), so the transaction goes on; rolling it back discards all of it.
    let (tx2, begin2_error) = db.begin(c)
    if begin2_error != ok { ret 125i32 }
    var failing = tx2
    let (n4, e4) = db.execute_transaction(&failing, "INSERT INTO other VALUES (13)", zero)
    if e4 != ok { ret 126i32 }
    let (n5, e5) = db.execute_transaction(&failing, "INSERT INTO nowhere VALUES (1)", zero)
    if e5 != db.InvalidQuery { ret 127i32 }
    let (n6, e6) = db.execute_transaction(&failing, "INSERT INTO other VALUES (14)", zero)
    if e6 != ok || n6 != 1u64 { ret 128i32 }
    if db.rollback(&failing) != ok { ret 129i32 }
    let (after_fail, after_fail_error) = scalar_i64(c, "SELECT count(*) FROM other WHERE x >= 13 AND x < 100")
    if after_fail_error != ok || after_fail != 0i64 { ret 130i32 }
    ret 0i32
}

fn two_connections(a: *mem.Arena, connection_string: str) -> i32 {
    let (first0, first_error) = odbc.open(a, connection_string)
    if first_error != ok { ret 140i32 }
    var first = first0
    let (second0, second_error) = odbc.open(a, connection_string)
    if second_error != ok { ret 141i32 }
    var second = second0
    let (tx0, begin_error) = db.begin(&first)
    if begin_error != ok { ret 142i32 }
    var tx = tx0
    let (locked0, lock_error) = db.query_transaction(&tx, "SELECT id FROM item WHERE id = 1 FOR UPDATE", zero)
    if lock_error != ok { ret 143i32 }
    var locked = locked0
    if db.close_rows(&locked) != ok { ret 144i32 }
    let (blocked, blocked_error) = db.query(&second, "SELECT id FROM item WHERE id = 1 FOR UPDATE NOWAIT", zero)
    if blocked_error != db.Busy { ret 145i32 }
    let (why, why_error) = odbc.detail(a, &second)
    if why_error != ok || !str.eq(why.sqlstate, "55P03") { ret 146i32 }
    if db.rollback(&tx) != ok { ret 147i32 }
    let (free0, free_error) = db.query(&second, "SELECT id FROM item WHERE id = 1 FOR UPDATE NOWAIT", zero)
    if free_error != ok { ret 148i32 }
    var free = free0
    if db.close_rows(&free) != ok { ret 149i32 }
    // Closing with a transaction open rolls it back rather than failing.
    let (open_tx, open_tx_error) = db.begin(&second)
    if open_tx_error != ok { ret 150i32 }
    if db.close(&second) != ok { ret 151i32 }
    if db.close(&first) != ok { ret 152i32 }
    if db.close(&first) != db.Closed { ret 153i32 }
    let (closed_n, closed_error) = db.execute(&first, "SELECT 1", zero)
    if closed_error != db.Closed { ret 154i32 }
    let (closed_detail, closed_detail_error) = odbc.detail(a, &first)
    if closed_detail_error != db.Closed { ret 155i32 }
    let (missing, missing_error) = odbc.open(a, "DSN=neper_no_such_data_source")
    if missing_error != odbc.CannotConnect { ret 156i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { os.exit(1i32) }
    let (conn0, open_error) = odbc.open(a, args[1])
    if open_error != ok { os.exit(3i32) }
    var c = conn0
    var code = values(a, &c)
    if code == 0i32 { code = counts_and_errors(a, &c) }
    if code == 0i32 { code = statements(a, &c) }
    if code == 0i32 { code = streaming(a, &c) }
    if code == 0i32 { code = transactions(a, &c) }
    if code == 0i32 { code = two_connections(a, args[1]) }
    if code == 0i32 && db.close(&c) != ok { code = 4i32 }
    if code != 0i32 { os.exit(code) }
    ret ok
}
