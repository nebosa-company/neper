// `x.postgresql.libpq`: an `e.db` driver over libpq, run against a live server whose libpq
// connection string is the first argument (the suites start a throwaway one with
// tests/selfhost/db_servers.*). Every check has its own exit code; each section is a function
// answering the first failing code, or 0.
//
// Covered: a multi-statement script; every `db.Value` kind sent as its natural type and read
// back exactly from binary results (int2/4/8, float4/8, bool, bytea with NULs, text in UTF-8,
// timestamptz and date, numeric -- scale, negative weight, NaN, past 2^64 -- uuid, jsonb, NULL,
// empty text and bytea); affected-row counts; SQLSTATEs mapped onto `e.db`'s errors with
// `detail` carrying state, message and constraint; the driver's own refusals; single-row
// streaming, a busy connection while it streams, and a reader closed early; prepared
// statements whose parameter types the server settled (an `I64` into `int4`, and out of its
// range); transactions committed, rolled back, refused when nested, and aborted by a failed
// statement; a 100 KB value; and a row lock refused as `Busy` across two connections.
use e.os
use e.mem
use e.str
use e.time
use e.db
use x.postgresql.libpq

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

fn scalar_text(c: *db.Connection, sql: str) -> (str, err) {
    let (value, value_error) = scalar(c, sql)
    if value_error != ok { ret ("", value_error) }
    let (s, is_text) = as_text(value)
    if !is_text { ret ("", db.InvalidQuery) }
    ret (s, ok)
}

fn schema() -> str {
    ret "DROP TABLE IF EXISTS item; DROP TABLE IF EXISTS other;\nCREATE TABLE item(id bigint PRIMARY KEY, name text NOT NULL, score float8, data bytea, flag boolean, seen timestamptz, small int2, medium int4, single float4, amount numeric, key uuid, doc jsonb, day date, label varchar(20) CHECK (label <> 'bad'));\n-- a comment between statements\nCREATE TABLE other(x bigint);"
}

fn values(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (schema_changed, schema_error) = db.execute(c, schema(), zero)
    if schema_error != ok { ret 10i32 }
    if schema_changed != 0u64 { ret 11i32 }

    // Every kind in its natural type; text is `unknown`, so the server reads it as the column's.
    var blob: [5]u8 = zero
    blob[0] = 1u8
    blob[2] = 255u8
    blob[4] = 7u8
    var p: [14]db.Parameter = zero
    p[0] = positional(db.Value{ I64: 1i64 })
    p[1] = positional(db.Value{ Text: "h\xc3\xa9llo \xe2\x82\xac" })
    p[2] = positional(db.Value{ F64: 0.1f64 })
    p[3] = positional(db.Value{ Bytes: blob[0..] })
    p[4] = positional(db.Value{ Bool: true })
    p[5] = positional(db.Value{ Time: time.Instant { nanos: 1700000000123456000i64 } })
    p[6] = positional(db.Value{ I64: -32768i64 })
    p[7] = positional(db.Value{ I64: 2147483647i64 })
    p[8] = positional(db.Value{ F64: 0.5f64 })
    p[9] = positional(db.Value{ Text: "12345.678900" })
    p[10] = positional(db.Value{ Text: "A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11" })
    p[11] = positional(db.Value{ Text: "{\"b\":[1,2],\"a\":\"x\"}" })
    p[12] = positional(db.Value{ Text: "2024-02-29" })
    p[13] = positional(db.Value{ Text: "tag" })
    let (inserted, insert_error) = db.execute(c, "INSERT INTO item VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)", p[0..])
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
    let (second, second_error) = db.execute(c, "INSERT INTO item(id, name, data, flag, score) VALUES ($1, $2, $3, $4, $5)", q[0..])
    if second_error != ok || second != 1u64 { ret 14i32 }

    let (rows0, query_error) = db.query(c, "SELECT id, name, score, data, flag, seen, small, medium, single, amount, key, doc, day, label FROM item ORDER BY id", zero)
    if query_error != ok { ret 15i32 }
    var rows = rows0
    let cols = db.columns(&rows)
    if cols.len != 14usize { ret 16i32 }
    if !str.eq(cols[0].name, "id") || cols[0].kind != .I64 || cols[1].kind != .Text || cols[2].kind != .F64 { ret 17i32 }
    if cols[3].kind != .Bytes || cols[4].kind != .Bool || cols[5].kind != .Time || cols[6].kind != .I64 || cols[7].kind != .I64 { ret 18i32 }
    if cols[8].kind != .F64 || cols[9].kind != .Text || cols[10].kind != .Text || cols[11].kind != .Text || cols[12].kind != .Time || cols[13].kind != .Text { ret 19i32 }

    var row: [14]db.Value = zero
    let (first, first_error) = db.reader_next_err(&rows, row[0..])
    if first_error != ok || !first { ret 20i32 }
    let (id1, id1_ok) = as_i64(row[0])
    if !id1_ok || id1 != 1i64 { ret 21i32 }
    let (name1, name1_ok) = as_text(row[1])
    if !name1_ok || !str.eq(name1, "h\xc3\xa9llo \xe2\x82\xac") { ret 22i32 }
    let (score1, score1_ok) = as_f64(row[2])
    if !score1_ok || score1 != 0.1f64 { ret 23i32 }
    let (data1, data1_ok) = as_bytes(row[3])
    if !data1_ok || !same_bytes(data1, blob[0..]) { ret 24i32 }
    let (flag1, flag1_ok) = as_bool(row[4])
    if !flag1_ok || !flag1 { ret 25i32 }
    let (seen1, seen1_ok) = as_time(row[5])
    if !seen1_ok || seen1 != 1700000000123456000i64 { ret 26i32 }
    let (small1, small1_ok) = as_i64(row[6])
    if !small1_ok || small1 != -32768i64 { ret 27i32 }
    let (medium1, medium1_ok) = as_i64(row[7])
    if !medium1_ok || medium1 != 2147483647i64 { ret 28i32 }
    let (single1, single1_ok) = as_f64(row[8])
    if !single1_ok || single1 != 0.5f64 { ret 29i32 }
    let (amount1, amount1_ok) = as_text(row[9])
    if !amount1_ok || !str.eq(amount1, "12345.678900") { ret 30i32 }
    let (key1, key1_ok) = as_text(row[10])
    if !key1_ok || !str.eq(key1, "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11") { ret 31i32 }
    // jsonb stores its own canonical form: keys sorted by length then bytes, one space after `:`
    // and `,`.
    let (doc1, doc1_ok) = as_text(row[11])
    if !doc1_ok || !str.eq(doc1, "{\"a\": \"x\", \"b\": [1, 2]}") { ret 32i32 }
    let (day1, day1_ok) = as_time(row[12])
    // 2024-02-29 is day 19782 after 1970-01-01.
    if !day1_ok || day1 != 19782i64 * 86400000000000i64 { ret 33i32 }
    let (label1, label1_ok) = as_text(row[13])
    if !label1_ok || !str.eq(label1, "tag") { ret 34i32 }

    let (more2, second_row_error) = db.reader_next_err(&rows, row[0..])
    if second_row_error != ok || !more2 { ret 35i32 }
    let (name2, name2_ok) = as_text(row[1])
    if !name2_ok || name2.len != 0usize { ret 36i32 }
    let (data2, data2_ok) = as_bytes(row[3])
    if !data2_ok || data2.len != 0usize { ret 37i32 }
    let (flag2, flag2_ok) = as_bool(row[4])
    if !flag2_ok || flag2 { ret 38i32 }
    if !is_null(row[2]) || !is_null(row[5]) || !is_null(row[9]) || !is_null(row[13]) { ret 39i32 }
    let (more3, third_error) = db.reader_next_err(&rows, row[0..])
    if third_error != ok || more3 { ret 40i32 }
    let (more4, fourth_error) = db.reader_next_err(&rows, row[0..])
    if fourth_error != ok || more4 { ret 41i32 }
    if db.close_rows(&rows) != ok { ret 42i32 }

    // numeric, exactly: a negative weight, a negative sign, zero at scale, NaN and a value past
    // what any integer type holds.
    let (tiny, tiny_error) = scalar_text(c, "SELECT -0.000100::numeric")
    if tiny_error != ok || !str.eq(tiny, "-0.000100") { ret 43i32 }
    let (zeroes, zeroes_error) = scalar_text(c, "SELECT 0.00::numeric")
    if zeroes_error != ok || !str.eq(zeroes, "0.00") { ret 44i32 }
    let (nan, nan_error) = scalar_text(c, "SELECT 'NaN'::numeric")
    if nan_error != ok || !str.eq(nan, "NaN") { ret 45i32 }
    let (huge, huge_error) = scalar_text(c, "SELECT 123456789012345678901234567890.5::numeric")
    if huge_error != ok || !str.eq(huge, "123456789012345678901234567890.5") { ret 46i32 }
    let (whole, whole_error) = scalar_text(c, "SELECT 10000::numeric")
    if whole_error != ok || !str.eq(whole, "10000") { ret 47i32 }
    // A `U64` past `bigint` goes as numeric and comes back as its text.
    var u: [1]db.Parameter = zero
    u[0] = positional(db.Value{ U64: 18446744073709551615u64 })
    let (u_rows0, u_error) = db.query(c, "SELECT $1::numeric + 0", u[0..])
    if u_error != ok { ret 48i32 }
    var u_rows = u_rows0
    var u_row: [1]db.Value = zero
    let (u_more, u_next_error) = db.reader_next_err(&u_rows, u_row[0..])
    let (u_text, u_text_ok) = as_text(u_row[0])
    if u_next_error != ok || !u_more || !u_text_ok || !str.eq(u_text, "18446744073709551615") { ret 49i32 }
    if db.close_rows(&u_rows) != ok { ret 50i32 }
    // Infinite timestamps have no instant, so they come back as PostgreSQL's text.
    let (forever, forever_error) = scalar_text(c, "SELECT 'infinity'::timestamptz")
    if forever_error != ok || !str.eq(forever, "infinity") { ret 51i32 }
    // A type the driver does not know arrives as its binary representation: `point` is two
    // float8s.
    let (point, point_error) = scalar(c, "SELECT point(1, 2)")
    let (point_bytes, point_ok) = as_bytes(point)
    if point_error != ok || !point_ok || point_bytes.len != 16usize { ret 52i32 }
    ret 0i32
}

fn counts_and_errors(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (updated, update_error) = db.execute(c, "UPDATE item SET score = 2.5", zero)
    if update_error != ok || updated != 2u64 { ret 60i32 }
    let (ddl, ddl_error) = db.execute(c, "CREATE INDEX item_name ON item(name)", zero)
    if ddl_error != ok || ddl != 0u64 { ret 61i32 }
    let (selected, selected_error) = db.execute(c, "SELECT * FROM item", zero)
    if selected_error != ok || selected != 0u64 { ret 62i32 }
    let (script, script_error) = db.execute(c, "INSERT INTO other VALUES (1); INSERT INTO other VALUES (2), (3);", zero)
    if script_error != ok || script != 3u64 { ret 63i32 }

    let (bad, bad_error) = db.execute(c, "SELEKT 1", zero)
    if bad_error != db.InvalidQuery { ret 64i32 }
    let (why, why_error) = libpq.detail(a, c)
    if why_error != ok || !str.eq(why.sqlstate, "42601") || !str.contains(why.message, "syntax error") { ret 65i32 }
    let (missing, missing_error) = db.query(c, "SELECT * FROM nowhere", zero)
    if missing_error != db.InvalidQuery { ret 66i32 }
    let (why_missing, why_missing_error) = libpq.detail(a, c)
    if why_missing_error != ok || !str.eq(why_missing.sqlstate, "42P01") { ret 67i32 }

    var dup: [2]db.Parameter = zero
    dup[0] = positional(db.Value{ I64: 1i64 })
    dup[1] = positional(db.Value{ Text: "again" })
    let (dup_n, dup_error) = db.execute(c, "INSERT INTO item(id, name) VALUES ($1, $2)", dup[0..])
    if dup_error != db.Constraint { ret 68i32 }
    let (why_dup, why_dup_error) = libpq.detail(a, c)
    if why_dup_error != ok || !str.eq(why_dup.sqlstate, "23505") || !str.eq(why_dup.constraint, "item_pkey") { ret 69i32 }
    let (nn_n, nn_error) = db.execute(c, "INSERT INTO item(id, name) VALUES (9, NULL)", zero)
    if nn_error != db.Constraint { ret 70i32 }
    let (why_nn, why_nn_error) = libpq.detail(a, c)
    if why_nn_error != ok || !str.eq(why_nn.sqlstate, "23502") { ret 71i32 }
    let (check_n, check_error) = db.execute(c, "INSERT INTO item(id, name, label) VALUES (9, 'x', 'bad')", zero)
    if check_error != db.Constraint { ret 72i32 }
    let (why_check, why_check_error) = libpq.detail(a, c)
    if why_check_error != ok || !str.eq(why_check.constraint, "item_label_check") { ret 73i32 }
    let (div, div_error) = db.query(c, "SELECT 1 / 0", zero)
    if div_error != db.InvalidQuery { ret 74i32 }

    // The server's refusals of the parameters, and the driver's own.
    let (few, few_error) = db.execute(c, "INSERT INTO item(id, name) VALUES ($1, $2)", dup[0usize..1usize])
    if few_error != db.InvalidQuery { ret 75i32 }
    var named: [1]db.Parameter = zero
    named[0] = db.Parameter { name: "id", value: db.Value{ I64: 1i64 } }
    let (named_rows, named_error) = db.query(c, "SELECT $1::int8", named[0..])
    if named_error != db.InvalidQuery { ret 76i32 }
    let (why_named, why_named_error) = libpq.detail(a, c)
    if why_named_error != ok || why_named.sqlstate.len != 0usize || !str.contains(why_named.message, "named parameters") { ret 77i32 }
    let (two, two_error) = db.query(c, "SELECT 1; SELECT 2", zero)
    if two_error != db.InvalidQuery { ret 78i32 }
    let (empty_n, empty_error) = db.execute(c, "", zero)
    if empty_error != ok || empty_n != 0u64 { ret 79i32 }

    let (short0, short_error) = db.query(c, "SELECT 1, 2", zero)
    if short_error != ok { ret 80i32 }
    var short = short0
    var one: [1]db.Value = zero
    let (short_more, short_next_error) = db.reader_next_err(&short, one[0..])
    if short_next_error != db.InvalidQuery { ret 81i32 }
    if db.close_rows(&short) != ok { ret 82i32 }

    let (count_now, count_error) = scalar_i64(c, "SELECT count(*) FROM item")
    if count_error != ok || count_now != 2i64 { ret 83i32 }
    let (why_ok, why_ok_error) = libpq.detail(a, c)
    if why_ok_error != ok || why_ok.sqlstate.len != 0usize || why_ok.message.len != 0usize { ret 84i32 }
    ret 0i32
}

fn streaming(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (all0, all_error) = db.query(c, "SELECT g FROM generate_series(1, 1000) AS g", zero)
    if all_error != ok { ret 90i32 }
    var all = all0
    // While it streams the connection is busy.
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
    // `generate_series` answers int4, which reads back as `I64` all the same.
    if count != 1000i64 || sum != 500500i64 { ret 95i32 }
    if db.close_rows(&all) != ok { ret 96i32 }
    // A reader closed early discards the rest and frees the connection.
    let (part0, part_error) = db.query(c, "SELECT g FROM generate_series(1, 100000) AS g", zero)
    if part_error != ok { ret 97i32 }
    var part = part0
    var k = 0usize
    while k < 10usize {
        let (part_more, part_next_error) = db.reader_next_err(&part, row[0..])
        if part_next_error != ok || !part_more { ret 98i32 }
        k += 1usize
    }
    if db.close_rows(&part) != ok { ret 99i32 }
    let (after, after_error) = scalar_i64(c, "SELECT 5::int8")
    if after_error != ok || after != 5i64 { ret 100i32 }
    // A failure mid-stream is the reader's error, and the connection is usable after it.
    let (fails0, fails_error) = db.query(c, "SELECT 10 / (3 - g) FROM generate_series(1, 5) AS g", zero)
    if fails_error != ok { ret 101i32 }
    var fails = fails0
    let (fail_a, fail_a_error) = db.reader_next_err(&fails, row[0..])
    let (fail_b, fail_b_error) = db.reader_next_err(&fails, row[0..])
    let (fail_c, fail_c_error) = db.reader_next_err(&fails, row[0..])
    if fail_a_error != ok || fail_b_error != ok || fail_c_error != db.InvalidQuery { ret 102i32 }
    let (why, why_error) = libpq.detail(a, c)
    if why_error != ok || !str.eq(why.sqlstate, "22012") { ret 103i32 }
    if db.close_rows(&fails) != ok { ret 104i32 }
    let (again, again_error) = scalar_i64(c, "SELECT 6::int8")
    if again_error != ok || again != 6i64 { ret 105i32 }

    // 100 KB round trip.
    let (big, big_alloc_error) = mem.alloc[u8](a, 100000usize)
    if big_alloc_error != ok { ret 106i32 }
    var i = 0usize
    while i < big.len {
        big[i] = u8(97usize + i % 26usize)
        i += 1usize
    }
    var big_param: [1]db.Parameter = zero
    big_param[0] = positional(db.Value{ Text: big })
    let (back0, back_error) = db.query(c, "SELECT $1::text, length($1::text)", big_param[0..])
    if back_error != ok { ret 107i32 }
    var back = back0
    var pair: [2]db.Value = zero
    let (got, got_error) = db.reader_next_err(&back, pair[0..])
    let (back_text, back_ok) = as_text(pair[0])
    let (back_len, back_len_ok) = as_i64(pair[1])
    if got_error != ok || !got || !back_ok || !same_bytes(back_text, big) || !back_len_ok || back_len != 100000i64 { ret 108i32 }
    if db.close_rows(&back) != ok { ret 109i32 }
    ret 0i32
}

fn statements(a: *mem.Arena, c: *db.Connection) -> i32 {
    // The server settles `$1` as int4 from the column; an `I64` goes in that width.
    let (insert0, prepare_error) = db.prepare(c, "INSERT INTO item(id, name, medium) VALUES ($1, $2, $3)")
    if prepare_error != ok { ret 120i32 }
    var insert = insert0
    var p: [3]db.Parameter = zero
    var id = 100i64
    while id < 200i64 {
        p[0] = positional(db.Value{ I64: id })
        p[1] = positional(db.Value{ Text: "row" })
        p[2] = positional(db.Value{ I64: id * 1000i64 })
        let (n, run_error) = db.execute_statement(&insert, p[0..])
        if run_error != ok || n != 1u64 { ret 121i32 }
        id += 1i64
    }
    p[0] = positional(db.Value{ I64: 500i64 })
    p[2] = positional(db.Value{ I64: 3000000000i64 })
    let (over, over_error) = db.execute_statement(&insert, p[0..])
    if over_error != db.Unsupported { ret 122i32 }
    let (short_n, short_error) = db.execute_statement(&insert, p[0usize..2usize])
    if short_error != db.InvalidQuery { ret 123i32 }
    if db.close_statement(&insert) != ok { ret 124i32 }
    let (bad_statement, bad_error) = db.prepare(c, "SELECT * FROM nowhere WHERE x = $1")
    if bad_error != db.InvalidQuery { ret 125i32 }

    let (select0, select_error) = db.prepare(c, "SELECT medium FROM item WHERE id >= $1 ORDER BY id")
    if select_error != ok { ret 126i32 }
    var select = select0
    var bound: [1]db.Parameter = zero
    bound[0] = positional(db.Value{ I64: 190i64 })
    let (first0, first_error) = db.query_statement(&select, bound[0..])
    if first_error != ok { ret 127i32 }
    var first = first0
    var row: [1]db.Value = zero
    var sum = 0i64
    while true {
        let (more, next_error) = db.reader_next_err(&first, row[0..])
        if next_error != ok { ret 128i32 }
        if !more { break }
        let (x, is_int) = as_i64(row[0])
        if !is_int { ret 129i32 }
        sum += x
    }
    // 190..199 times 1000.
    if sum != 1945000i64 { ret 130i32 }
    if db.close_rows(&first) != ok { ret 131i32 }
    bound[0] = positional(db.Value{ I64: 198i64 })
    let (tail0, tail_error) = db.query_statement(&select, bound[0..])
    if tail_error != ok { ret 132i32 }
    var tail = tail0
    let (t1, t1_error) = db.reader_next_err(&tail, row[0..])
    let (v1, v1_ok) = as_i64(row[0])
    if t1_error != ok || !t1 || !v1_ok || v1 != 198000i64 { ret 133i32 }
    // Closing the statement under its reader: the reader answers `Closed`.
    if db.close_statement(&select) != ok { ret 134i32 }
    let (t2, t2_error) = db.reader_next_err(&tail, row[0..])
    if t2_error != db.Closed { ret 135i32 }
    if db.close_rows(&tail) != ok { ret 136i32 }
    let (after, after_error) = scalar_i64(c, "SELECT count(*) FROM item")
    if after_error != ok || after != 102i64 { ret 137i32 }
    ret 0i32
}

// `reader_next_borrowed` hands back the library's own bytes: each row checked before the
// next is read, the copying reader interleaved on the same stream, a 60 KB value, an empty
// one, and `Closed` after the close.
fn borrowed(c: *db.Connection) -> i32 {
    let (made, made_error) = db.execute(c, "DROP TABLE IF EXISTS words; CREATE TABLE words(id bigint, w text, b bytea); INSERT INTO words VALUES (1, 'alpha', decode('0001', 'hex')), (2, 'bravo', decode('02', 'hex')), (3, repeat('xyz', 20000), NULL), (4, '', NULL);", zero)
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
    if after_rollback_error != ok || after_rollback != 3i64 { ret 145i32 }

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
    if inside_next_error != ok || !inside_more || !inside_ok || inside_n != 4i64 { ret 149i32 }
    // Committing with the reader still open ends the reader first.
    if db.commit(&kept) != ok { ret 150i32 }
    if db.close_rows(&inside) != ok { ret 151i32 }
    let (after_commit, after_commit_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if after_commit_error != ok || after_commit != 4i64 { ret 152i32 }

    // A failed statement aborts the transaction; commit answers `Aborted` and nothing lands.
    let (tx2, begin2_error) = db.begin(c)
    if begin2_error != ok { ret 153i32 }
    var failing = tx2
    let (n3, e3) = db.execute_transaction(&failing, "INSERT INTO other VALUES (12)", zero)
    if e3 != ok { ret 154i32 }
    let (n4, e4) = db.execute_transaction(&failing, "INSERT INTO nowhere VALUES (1)", zero)
    if e4 != db.InvalidQuery { ret 155i32 }
    let (n5, e5) = db.execute_transaction(&failing, "INSERT INTO other VALUES (13)", zero)
    if e5 != libpq.Aborted { ret 156i32 }
    if db.commit(&failing) != libpq.Aborted { ret 157i32 }
    let (after_fail, after_fail_error) = scalar_i64(c, "SELECT count(*) FROM other WHERE x >= 12")
    if after_fail_error != ok || after_fail != 0i64 { ret 158i32 }
    ret 0i32
}

fn two_connections(a: *mem.Arena, conninfo: str) -> i32 {
    let (first0, first_error) = libpq.open(a, conninfo)
    if first_error != ok { ret 170i32 }
    var first = first0
    let (second0, second_error) = libpq.open(a, conninfo)
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
    let (why, why_error) = libpq.detail(a, &second)
    if why_error != ok || !str.eq(why.sqlstate, "55P03") { ret 176i32 }
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
    let (closed_detail, closed_detail_error) = libpq.detail(a, &first)
    if closed_detail_error != db.Closed { ret 184i32 }
    // Nothing listens on port 1.
    let (refused, refused_error) = libpq.open(a, "host=127.0.0.1 port=1 connect_timeout=5")
    if refused_error != libpq.CannotConnect { ret 185i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { os.exit(1i32) }
    if libpq.version() < 90200i32 { os.exit(2i32) }
    let (conn0, open_error) = libpq.open(a, args[1])
    if open_error != ok { os.exit(3i32) }
    var c = conn0
    var code = values(a, &c)
    if code == 0i32 { code = counts_and_errors(a, &c) }
    if code == 0i32 { code = streaming(a, &c) }
    if code == 0i32 { code = statements(a, &c) }
    if code == 0i32 { code = borrowed(&c) }
    if code == 0i32 { code = transactions(a, &c) }
    if code == 0i32 { code = two_connections(a, args[1]) }
    if code == 0i32 && db.close(&c) != ok { code = 4i32 }
    if code != 0i32 { os.exit(code) }
    ret ok
}
