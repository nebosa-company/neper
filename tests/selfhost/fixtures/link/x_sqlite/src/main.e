// `x.sqlite.sqlite`: an `e.db` driver over the SQLite 3 C library each host ships (Windows'
// `winsqlite3.dll`, Linux's `libsqlite3.so.0`), bound by `@import` through `x.sqlite.capi`.
// Every check has its own exit code; each section is a function answering the first failing
// code, or 0.
//
// Covered: a multi-statement schema script; positional, named and prefix-less named
// parameters; every `db.Value` case written and read back exactly (UTF-8 and empty text,
// blobs with NULs and empty blobs, 0.1, bools, instants, NULL); declared and expression column
// kinds; affected-row counts that are not stale after DDL; the driver's refusals and SQLite's
// errors mapped onto `e.db`'s with `detail` carrying the extended code and message; a prepared
// statement reused, reset and closed under its reader; transactions committed, rolled back and
// refused when nested; a 100 KB value and 1000 streamed rows; and a database file reopened,
// locked by one connection and refused as `Busy` by another.
use e.os
use e.mem
use e.str
use e.fs
use e.time
use e.db
use x.sqlite.sqlite

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

// The single integer the query answers.
fn scalar(c: *db.Connection, sql: str) -> (i64, err) {
    let (rows0, query_error) = db.query(c, sql, zero)
    if query_error != ok { ret (0i64, query_error) }
    var rows = rows0
    var row: [1]db.Value = zero
    let (more, next_error) = db.reader_next_err(&rows, row[0..])
    let close_error = db.close_rows(&rows)
    if next_error != ok { ret (0i64, next_error) }
    if !more { ret (0i64, db.InvalidQuery) }
    let (n, is_int) = as_i64(row[0])
    if !is_int { ret (0i64, db.InvalidQuery) }
    ret (n, ok)
}

fn schema() -> str {
    ret "CREATE TABLE item(id INTEGER PRIMARY KEY, name TEXT NOT NULL, score REAL, data BLOB, flag BOOLEAN, seen TIMESTAMP);\n-- a comment between statements\nCREATE INDEX item_name ON item(name);\n"
}

fn schema_and_values(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (schema_changed, schema_error) = db.execute(c, schema(), zero)
    if schema_error != ok { ret 10i32 }
    if schema_changed != 0u64 { ret 11i32 }

    // Positional: every storage class at once.
    var blob: [5]u8 = zero
    blob[0] = 1u8
    blob[2] = 255u8
    blob[4] = 7u8
    var p: [6]db.Parameter = zero
    p[0] = db.Parameter { name: "", value: db.Value{ I64: 1i64 } }
    p[1] = db.Parameter { name: "", value: db.Value{ Text: "h\xc3\xa9llo \xe2\x82\xac" } }
    p[2] = db.Parameter { name: "", value: db.Value{ F64: 0.1f64 } }
    p[3] = db.Parameter { name: "", value: db.Value{ Bytes: blob[0..] } }
    p[4] = db.Parameter { name: "", value: db.Value{ Bool: true } }
    p[5] = db.Parameter { name: "", value: db.Value{ Time: time.Instant { nanos: 1700000000123456789i64 } } }
    let (inserted, insert_error) = db.execute(c, "INSERT INTO item VALUES (?, ?, ?, ?, ?, ?)", p[0..])
    if insert_error != ok { ret 12i32 }
    if inserted != 1u64 { ret 13i32 }

    // Named, written with and without the prefix; empty text and blob, false, NULLs, and a
    // `U64` that fits.
    var empty: [1]u8 = zero
    var q: [6]db.Parameter = zero
    q[0] = db.Parameter { name: ":id", value: db.Value{ U64: 2u64 } }
    q[1] = db.Parameter { name: "name", value: db.Value{ Text: "" } }
    q[2] = db.Parameter { name: "@score", value: .Null }
    q[3] = db.Parameter { name: "data", value: db.Value{ Bytes: empty[0usize..0usize] } }
    q[4] = db.Parameter { name: "flag", value: db.Value{ Bool: false } }
    q[5] = db.Parameter { name: "$seen", value: .Null }
    let (named, named_error) = db.execute(c, "INSERT INTO item VALUES (:id, :name, @score, :data, :flag, $seen)", q[0..])
    if named_error != ok { ret 14i32 }
    if named != 1u64 { ret 15i32 }

    let (rows0, query_error) = db.query(c, "SELECT id, name, score, data, flag, seen FROM item ORDER BY id", zero)
    if query_error != ok { ret 16i32 }
    var rows = rows0
    let cols = db.columns(&rows)
    if cols.len != 6usize { ret 17i32 }
    if !str.eq(cols[0].name, "id") || cols[0].kind != .I64 { ret 18i32 }
    if !str.eq(cols[1].name, "name") || cols[1].kind != .Text { ret 19i32 }
    if cols[2].kind != .F64 || cols[3].kind != .Bytes || cols[4].kind != .Bool || cols[5].kind != .Time { ret 20i32 }
    if !str.eq(cols[5].name, "seen") || !cols[5].nullable { ret 21i32 }

    var row: [6]db.Value = zero
    let (first, first_error) = db.reader_next_err(&rows, row[0..])
    if first_error != ok || !first { ret 22i32 }
    let (id1, id1_ok) = as_i64(row[0])
    if !id1_ok || id1 != 1i64 { ret 23i32 }
    let (name1, name1_ok) = as_text(row[1])
    if !name1_ok || !str.eq(name1, "h\xc3\xa9llo \xe2\x82\xac") { ret 24i32 }
    let (score1, score1_ok) = as_f64(row[2])
    if !score1_ok || score1 != 0.1f64 { ret 25i32 }
    let (data1, data1_ok) = as_bytes(row[3])
    if !data1_ok || !same_bytes(data1, blob[0..]) { ret 26i32 }
    let (flag1, flag1_ok) = as_bool(row[4])
    if !flag1_ok || !flag1 { ret 27i32 }
    let (seen1, seen1_ok) = as_time(row[5])
    if !seen1_ok || seen1 != 1700000000123456789i64 { ret 28i32 }

    let (second, second_error) = db.reader_next_err(&rows, row[0..])
    if second_error != ok || !second { ret 29i32 }
    let (id2, id2_ok) = as_i64(row[0])
    if !id2_ok || id2 != 2i64 { ret 30i32 }
    let (name2, name2_ok) = as_text(row[1])
    if !name2_ok || name2.len != 0usize { ret 31i32 }
    if !is_null(row[2]) || !is_null(row[5]) { ret 32i32 }
    // A zero-length blob is stored as a blob, not as NULL.
    let (data2, data2_ok) = as_bytes(row[3])
    if !data2_ok || data2.len != 0usize { ret 33i32 }
    let (flag2, flag2_ok) = as_bool(row[4])
    if !flag2_ok || flag2 { ret 34i32 }

    let (third, third_error) = db.reader_next_err(&rows, row[0..])
    if third_error != ok || third { ret 35i32 }
    // Past the end stays at the end.
    let (fourth, fourth_error) = db.reader_next_err(&rows, row[0..])
    if fourth_error != ok || fourth { ret 36i32 }
    if db.close_rows(&rows) != ok { ret 37i32 }

    // Expression columns take the first row's storage class; with no row they are `Null`.
    let (expr0, expr_error) = db.query(c, "SELECT count(*), 1.5, 'x', x'00' FROM item", zero)
    if expr_error != ok { ret 38i32 }
    var expr = expr0
    let expr_cols = db.columns(&expr)
    if expr_cols[0].kind != .I64 || expr_cols[1].kind != .F64 || expr_cols[2].kind != .Text || expr_cols[3].kind != .Bytes { ret 39i32 }
    if !str.eq(expr_cols[0].name, "count(*)") { ret 40i32 }
    if db.close_rows(&expr) != ok { ret 41i32 }
    let (none0, none_error) = db.query(c, "SELECT id + 1 FROM item WHERE id < 0", zero)
    if none_error != ok { ret 42i32 }
    var none = none0
    if db.columns(&none)[0].kind != .Null { ret 43i32 }
    let (none_more, none_next_error) = db.reader_next_err(&none, row[0..])
    if none_next_error != ok || none_more { ret 44i32 }
    if db.close_rows(&none) != ok { ret 45i32 }
    ret 0i32
}

fn counts_and_errors(a: *mem.Arena, c: *db.Connection) -> i32 {
    // Affected rows, and DDL after DML answering 0 rather than the count before it.
    let (updated, update_error) = db.execute(c, "UPDATE item SET score = 2.5", zero)
    if update_error != ok || updated != 2u64 { ret 50i32 }
    let (ddl, ddl_error) = db.execute(c, "CREATE TABLE other(x)", zero)
    if ddl_error != ok || ddl != 0u64 { ret 51i32 }
    let (untouched, untouched_error) = db.execute(c, "UPDATE item SET score = 1 WHERE id < 0", zero)
    if untouched_error != ok || untouched != 0u64 { ret 52i32 }
    // A script's counts add up.
    let (script, script_error) = db.execute(c, "INSERT INTO other VALUES (1); INSERT INTO other VALUES (2), (3);", zero)
    if script_error != ok || script != 3u64 { ret 53i32 }

    // A syntax error: `InvalidQuery`, with SQLite's code and message behind it.
    let (bad, bad_error) = db.execute(c, "SELEKT 1", zero)
    if bad_error != db.InvalidQuery { ret 54i32 }
    let (why, why_error) = sqlite.detail(a, c)
    if why_error != ok || why.code != 1i32 || !str.contains(why.message, "syntax error") { ret 55i32 }
    let (missing, missing_error) = db.query(c, "SELECT * FROM nowhere", zero)
    if missing_error != db.InvalidQuery { ret 56i32 }
    let (why_missing, why_missing_error) = sqlite.detail(a, c)
    if why_missing_error != ok || !str.contains(why_missing.message, "no such table") { ret 57i32 }

    // Constraints, with the extended code naming which one.
    var dup: [2]db.Parameter = zero
    dup[0] = db.Parameter { name: "", value: db.Value{ I64: 1i64 } }
    dup[1] = db.Parameter { name: "", value: db.Value{ Text: "again" } }
    let (dup_n, dup_error) = db.execute(c, "INSERT INTO item(id, name) VALUES (?, ?)", dup[0..])
    if dup_error != db.Constraint { ret 58i32 }
    let (why_dup, why_dup_error) = sqlite.detail(a, c)
    // SQLITE_CONSTRAINT_PRIMARYKEY
    if why_dup_error != ok || why_dup.code != 19i32 || why_dup.extended != 1555i32 { ret 59i32 }
    var nameless: [2]db.Parameter = zero
    nameless[0] = db.Parameter { name: "", value: db.Value{ I64: 9i64 } }
    nameless[1] = db.Parameter { name: "", value: .Null }
    let (nn_n, nn_error) = db.execute(c, "INSERT INTO item(id, name) VALUES (?, ?)", nameless[0..])
    if nn_error != db.Constraint { ret 60i32 }
    let (why_nn, why_nn_error) = sqlite.detail(a, c)
    // SQLITE_CONSTRAINT_NOTNULL
    if why_nn_error != ok || why_nn.extended != 1299i32 { ret 61i32 }

    // The driver's own refusals: code 0 and its reason.
    let (few, few_error) = db.execute(c, "INSERT INTO item(id, name) VALUES (?, ?)", dup[0usize..1usize])
    if few_error != db.InvalidQuery { ret 62i32 }
    let (why_few, why_few_error) = sqlite.detail(a, c)
    if why_few_error != ok || why_few.code != 0i32 || !str.contains(why_few.message, "parameter count") { ret 63i32 }
    var huge: [2]db.Parameter = zero
    huge[0] = db.Parameter { name: "", value: db.Value{ U64: 9223372036854775808u64 } }
    huge[1] = db.Parameter { name: "", value: db.Value{ Text: "huge" } }
    let (huge_n, huge_error) = db.execute(c, "INSERT INTO item(id, name) VALUES (?, ?)", huge[0..])
    if huge_error != db.Unsupported { ret 64i32 }
    var unknown: [1]db.Parameter = zero
    unknown[0] = db.Parameter { name: "nope", value: db.Value{ I64: 1i64 } }
    let (unknown_rows, unknown_error) = db.query(c, "SELECT * FROM item WHERE id = :id", unknown[0..])
    if unknown_error != db.InvalidQuery { ret 65i32 }
    let (why_unknown, why_unknown_error) = sqlite.detail(a, c)
    if why_unknown_error != ok || !str.contains(why_unknown.message, "no parameter of that name") { ret 66i32 }
    let (two, two_error) = db.query(c, "SELECT 1; SELECT 2", zero)
    if two_error != db.InvalidQuery { ret 67i32 }
    let (blank, blank_error) = db.query(c, "  -- nothing\n", zero)
    if blank_error != db.InvalidQuery { ret 68i32 }
    let (empty_n, empty_error) = db.execute(c, "", zero)
    if empty_error != ok || empty_n != 0u64 { ret 69i32 }
    // A trailing semicolon and comment are not a second statement.
    let (trailing, trailing_error) = db.query(c, "SELECT 7; -- done", zero)
    if trailing_error != ok { ret 70i32 }
    var trailing_rows = trailing
    if db.close_rows(&trailing_rows) != ok { ret 71i32 }
    // A row buffer shorter than the row.
    let (short0, short_error) = db.query(c, "SELECT 1, 2", zero)
    if short_error != ok { ret 72i32 }
    var short = short0
    var one: [1]db.Value = zero
    let (short_more, short_next_error) = db.reader_next_err(&short, one[0..])
    if short_next_error != db.InvalidQuery { ret 73i32 }
    if db.close_rows(&short) != ok { ret 74i32 }
    // After a success the detail says so.
    let (count_now, count_error) = scalar(c, "SELECT count(*) FROM item")
    if count_error != ok || count_now != 2i64 { ret 75i32 }
    let (why_ok, why_ok_error) = sqlite.detail(a, c)
    if why_ok_error != ok || why_ok.code != 0i32 { ret 76i32 }
    // A statement that answers a row is still something `execute` runs to its end.
    let (pragma, pragma_error) = db.execute(c, "PRAGMA busy_timeout = 25", zero)
    if pragma_error != ok || pragma != 0u64 { ret 77i32 }
    let (timeout, timeout_error) = scalar(c, "PRAGMA busy_timeout")
    if timeout_error != ok || timeout != 25i64 { ret 78i32 }
    let (reset_timeout, reset_timeout_error) = db.execute(c, "PRAGMA busy_timeout = 0", zero)
    if reset_timeout_error != ok { ret 79i32 }
    ret 0i32
}

fn statements(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (insert0, prepare_error) = db.prepare(c, "INSERT INTO other VALUES (?)")
    if prepare_error != ok { ret 80i32 }
    var insert = insert0
    var one: [1]db.Parameter = zero
    var i = 0i64
    while i < 1000i64 {
        one[0] = db.Parameter { name: "", value: db.Value{ I64: i } }
        let (n, run_error) = db.execute_statement(&insert, one[0..])
        if run_error != ok || n != 1u64 { ret 81i32 }
        i += 1i64
    }
    if db.close_statement(&insert) != ok { ret 82i32 }

    // 1000 rows streamed, and a statement queried twice with different parameters.
    let (select0, select_error) = db.prepare(c, "SELECT x FROM other WHERE x >= ? ORDER BY x")
    if select_error != ok { ret 83i32 }
    var select = select0
    var bound: [1]db.Parameter = zero
    bound[0] = db.Parameter { name: "", value: db.Value{ I64: 0i64 } }
    let (all0, all_error) = db.query_statement(&select, bound[0..])
    if all_error != ok { ret 84i32 }
    var all = all0
    var row: [1]db.Value = zero
    var count = 0i64
    var sum = 0i64
    while true {
        let (more, next_error) = db.reader_next_err(&all, row[0..])
        if next_error != ok { ret 85i32 }
        if !more { break }
        let (x, is_int) = as_i64(row[0])
        if !is_int { ret 86i32 }
        count += 1i64
        sum += x
    }
    // 1, 2, 3 from the script plus 0..999.
    if count != 1003i64 || sum != 499506i64 { ret 87i32 }
    if db.close_rows(&all) != ok { ret 88i32 }
    bound[0] = db.Parameter { name: "", value: db.Value{ I64: 998i64 } }
    let (tail0, tail_error) = db.query_statement(&select, bound[0..])
    if tail_error != ok { ret 89i32 }
    var tail = tail0
    let (t1, t1_error) = db.reader_next_err(&tail, row[0..])
    let (v1, v1_ok) = as_i64(row[0])
    if t1_error != ok || !t1 || !v1_ok || v1 != 998i64 { ret 90i32 }
    // Closing the statement under its reader: the reader answers `Closed`.
    if db.close_statement(&select) != ok { ret 91i32 }
    let (t2, t2_error) = db.reader_next_err(&tail, row[0..])
    if t2_error != db.Closed { ret 92i32 }
    if db.close_rows(&tail) != ok { ret 93i32 }

    // A 100 KB value round-trips, growing the reader's buffer.
    let (big, big_alloc_error) = mem.alloc[u8](a, 100000usize)
    if big_alloc_error != ok { ret 94i32 }
    var k = 0usize
    while k < big.len {
        big[k] = u8(97usize + k % 26usize)
        k += 1usize
    }
    var big_param: [1]db.Parameter = zero
    big_param[0] = db.Parameter { name: "", value: db.Value{ Text: big } }
    let (big_n, big_error) = db.execute(c, "INSERT INTO other VALUES (?)", big_param[0..])
    if big_error != ok || big_n != 1u64 { ret 95i32 }
    let (back0, back_error) = db.query(c, "SELECT x, length(x) FROM other WHERE typeof(x) = 'text'", zero)
    if back_error != ok { ret 96i32 }
    var back = back0
    var pair: [2]db.Value = zero
    let (got, got_error) = db.reader_next_err(&back, pair[0..])
    if got_error != ok || !got { ret 97i32 }
    let (back_text, back_ok) = as_text(pair[0])
    if !back_ok || !same_bytes(back_text, big) { ret 98i32 }
    let (back_len, back_len_ok) = as_i64(pair[1])
    if !back_len_ok || back_len != 100000i64 { ret 99i32 }
    if db.close_rows(&back) != ok { ret 100i32 }
    ret 0i32
}

fn transactions(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (tx0, begin_error) = db.begin(c)
    if begin_error != ok { ret 110i32 }
    var tx = tx0
    let (nested, nested_error) = db.begin(c)
    if nested_error != db.Busy { ret 111i32 }
    let (n1, e1) = db.execute_transaction(&tx, "INSERT INTO item(id, name) VALUES (10, 'rolled back')", zero)
    if e1 != ok || n1 != 1u64 { ret 112i32 }
    let (inside0, inside_error) = db.query_transaction(&tx, "SELECT count(*) FROM item", zero)
    if inside_error != ok { ret 113i32 }
    var inside = inside0
    var row: [1]db.Value = zero
    let (inside_more, inside_next_error) = db.reader_next_err(&inside, row[0..])
    let (inside_n, inside_ok) = as_i64(row[0])
    if inside_next_error != ok || !inside_more || !inside_ok || inside_n != 3i64 { ret 114i32 }
    if db.close_rows(&inside) != ok { ret 115i32 }
    if db.rollback(&tx) != ok { ret 116i32 }
    if db.rollback(&tx) != db.Closed { ret 117i32 }
    let (after_rollback, after_rollback_error) = scalar(c, "SELECT count(*) FROM item")
    if after_rollback_error != ok || after_rollback != 2i64 { ret 118i32 }

    let (tx1, begin1_error) = db.begin(c)
    if begin1_error != ok { ret 119i32 }
    var kept = tx1
    let (n2, e2) = db.execute_transaction(&kept, "INSERT INTO item(id, name) VALUES (11, 'kept')", zero)
    if e2 != ok || n2 != 1u64 { ret 120i32 }
    if db.commit(&kept) != ok { ret 121i32 }
    if db.commit(&kept) != db.Closed { ret 122i32 }
    let (after_commit, after_commit_error) = scalar(c, "SELECT count(*) FROM item")
    if after_commit_error != ok || after_commit != 3i64 { ret 123i32 }

    // A failed statement inside a transaction leaves it open and rollback-able.
    let (tx2, begin2_error) = db.begin(c)
    if begin2_error != ok { ret 124i32 }
    var failing = tx2
    let (n3, e3) = db.execute_transaction(&failing, "INSERT INTO item(id, name) VALUES (12, 'undone')", zero)
    if e3 != ok { ret 125i32 }
    let (n4, e4) = db.execute_transaction(&failing, "INSERT INTO item(id, name) VALUES (12, 'duplicate')", zero)
    if e4 != db.Constraint { ret 126i32 }
    if db.rollback(&failing) != ok { ret 127i32 }
    let (after_fail, after_fail_error) = scalar(c, "SELECT count(*) FROM item WHERE id = 12")
    if after_fail_error != ok || after_fail != 0i64 { ret 128i32 }
    ret 0i32
}

fn files(a: *mem.Arena) -> i32 {
    let (dir, dir_error) = fs.temp_dir(a)
    if dir_error != ok { ret 130i32 }
    let (path, path_error) = str.concat(a, dir, "/np-x-sqlite-fixture.db")
    if path_error != ok { ret 131i32 }
    let (was_there, exists_error) = fs.exists(a, path)
    if exists_error != ok { ret 132i32 }
    if was_there && fs.remove_file(a, path) != ok { ret 133i32 }

    let (first0, first_error) = sqlite.open(a, path)
    if first_error != ok { ret 134i32 }
    var first = first0
    let (made, made_error) = db.execute(&first, "CREATE TABLE kv(k TEXT PRIMARY KEY, v INTEGER); INSERT INTO kv VALUES ('a', 1);", zero)
    if made_error != ok || made != 1u64 { ret 135i32 }
    if db.close(&first) != ok { ret 136i32 }
    if db.close(&first) != db.Closed { ret 137i32 }
    let (closed_n, closed_error) = db.execute(&first, "SELECT 1", zero)
    if closed_error != db.Closed { ret 138i32 }
    let (closed_detail, closed_detail_error) = sqlite.detail(a, &first)
    if closed_detail_error != db.Closed { ret 139i32 }

    // Reopened, the row is there.
    let (again0, again_error) = sqlite.open(a, path)
    if again_error != ok { ret 140i32 }
    var again = again0
    let (v, v_error) = scalar(&again, "SELECT v FROM kv WHERE k = 'a'")
    if v_error != ok || v != 1i64 { ret 141i32 }

    // One connection holds the write lock; the other is refused `Busy` at once (no busy
    // timeout is set), and succeeds after the first lets go.
    let (other0, other_error) = sqlite.open(a, path)
    if other_error != ok { ret 142i32 }
    var other = other0
    let (locked, lock_error) = db.execute(&again, "BEGIN IMMEDIATE", zero)
    if lock_error != ok { ret 143i32 }
    let (blocked, blocked_error) = db.execute(&other, "INSERT INTO kv VALUES ('b', 2)", zero)
    if blocked_error != db.Busy { ret 144i32 }
    let (why, why_error) = sqlite.detail(a, &other)
    if why_error != ok || why.code != 5i32 { ret 145i32 }
    let (released, release_error) = db.execute(&again, "COMMIT", zero)
    if release_error != ok { ret 146i32 }
    let (unblocked, unblocked_error) = db.execute(&other, "INSERT INTO kv VALUES ('b', 2)", zero)
    if unblocked_error != ok || unblocked != 1u64 { ret 147i32 }
    let (seen, seen_error) = scalar(&again, "SELECT count(*) FROM kv")
    if seen_error != ok || seen != 2i64 { ret 148i32 }
    if db.close(&other) != ok { ret 149i32 }
    if db.close(&again) != ok { ret 150i32 }
    if fs.remove_file(a, path) != ok { ret 151i32 }

    // A file that cannot be created.
    let (bad_path, bad_path_error) = str.concat(a, dir, "/np-no-such-directory/x.db")
    if bad_path_error != ok { ret 152i32 }
    let (bad, bad_error) = sqlite.open(a, bad_path)
    if bad_error != sqlite.CannotOpen { ret 153i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    if sqlite.version() < 3007014i32 { os.exit(1i32) }
    let (conn0, open_error) = sqlite.open(a, ":memory:")
    if open_error != ok { os.exit(2i32) }
    var c = conn0
    var code = schema_and_values(a, &c)
    if code == 0i32 { code = counts_and_errors(a, &c) }
    if code == 0i32 { code = statements(a, &c) }
    if code == 0i32 { code = transactions(a, &c) }
    if code == 0i32 && db.close(&c) != ok { code = 3i32 }
    if code == 0i32 { code = files(a) }
    if code != 0i32 { os.exit(code) }
    ret ok
}
