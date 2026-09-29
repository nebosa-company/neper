// `x.microsoft.tds`: an `e.db` driver that speaks TDS to SQL Server itself, inside TLS 1.3 (TDS
// 8.0 strict), run against a live server. The arguments are the host, the port, the server's
// certificate (DER, the trust root), a login and its password, all from the ports file the
// suites' tests/selfhost/sqlserver.* scripts write; the login owns database `neper`. Every check
// has its own exit code; each section is a function answering the first failing code, or 0.
//
// Covered: every `db.Value` kind bound and read back (bigint, smallint, int, tinyint, float,
// real, bit, varbinary with NULs, nvarchar with 4-byte UTF-8 and a leading U+FEFF, datetime2 and
// date as UTC, decimal as text, NULL into a binary column), and read-only types (money,
// datetime, datetimeoffset, time, uniqueidentifier, nchar, a Latin-1 varchar); a `U64` past
// `i64`; a column name outside ASCII; affected-row counts summed over a script; `?` inside
// strings, quoted identifiers and nested comments left alone; server errors mapped onto `e.db`
// with number, state, severity and message; the driver's own refusals; prepared statements;
// 1000 rows streamed with the connection busy meanwhile and a reader closed early; 100 KB of
// text and bytes as nvarchar(max) and varbinary(max); transactions committed, rolled back,
// refused when nested, surviving a failed statement and ended by the server (`XACT_ABORT`);
// a row lock refused as `Busy` across two connections; a refused login and no trust root.
use e.os
use e.mem
use e.str
use e.fs
use e.time
use e.db
use x.microsoft.tds
use x.openssl.crypto

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

fn text_is(c: *db.Connection, sql: str, params: []const db.Parameter, expected: str) -> bool {
    let (value, value_error) = scalar(c, sql, params)
    let (s, is_text) = as_text(value)
    ret value_error == ok && is_text && str.eq(s, expected)
}

fn schema() -> str {
    ret "DROP TABLE IF EXISTS item; DROP TABLE IF EXISTS other;\nCREATE TABLE item(id bigint PRIMARY KEY, name nvarchar(max) NOT NULL, score float, data varbinary(max), flag bit, seen datetime2(7), small smallint, medium int, single real, amount decimal(12,6), day date, label varchar(20) CHECK (label <> 'bad'), tiny tinyint, cash money, legacy datetime, zone datetimeoffset(7), clock time(7), tag uniqueidentifier, code nchar(3), latin varchar(10) COLLATE SQL_Latin1_General_CP1_CI_AS);\nCREATE TABLE other(x bigint);"
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
    p[5] = positional(db.Value{ Time: time.Instant { nanos: 1700000000123456700i64 } })
    p[6] = positional(db.Value{ I64: -32768i64 })
    p[7] = positional(db.Value{ I64: 2147483647i64 })
    p[8] = positional(db.Value{ F64: 0.5f64 })
    p[9] = positional(db.Value{ Text: "12345.678900" })
    p[10] = positional(db.Value{ Time: time.Instant { nanos: 1709164800000000000i64 } })
    p[11] = positional(db.Value{ Text: "tag" })
    let (inserted, insert_error) = db.execute(c, "INSERT INTO item(id, name, score, data, flag, seen, small, medium, single, amount, day, label) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", p[0..])
    if insert_error != ok { ret 12i32 }
    if inserted != 1u64 { ret 13i32 }
    // The types a parameter never takes, as literals.
    let (typed, typed_error) = db.execute(c, "UPDATE item SET tiny = 255, cash = -12.3456, legacy = '2024-02-29T12:34:56.787', zone = '2024-02-29T12:00:00+02:00', clock = '12:34:56.1234567', tag = '6F9619FF-8B86-D011-B42D-00C04FC964FF', code = N'ab', latin = 'caf' + CHAR(233) WHERE id = 1", zero)
    if typed_error != ok || typed != 1u64 { ret 14i32 }

    // Empty text and varbinary, false, and NULL into a float and (as a literal) a varbinary.
    var empty: [1]u8 = zero
    var q: [6]db.Parameter = zero
    q[0] = positional(db.Value{ I64: 2i64 })
    q[1] = positional(db.Value{ Text: "" })
    q[2] = positional(db.Value{ Bytes: empty[0usize..0usize] })
    q[3] = positional(db.Value{ Bool: false })
    q[4] = positional(.Null)
    q[5] = positional(.Null)
    let (second, second_error) = db.execute(c, "INSERT INTO item(id, name, data, flag, score) VALUES (?, ?, ?, ?, ?); UPDATE item SET data = ? WHERE id = 99", q[0..])
    if second_error != ok || second != 1u64 { ret 15i32 }

    let (rows0, query_error) = db.query(c, "SELECT id, name, score, data, flag, seen, small, medium, single, amount, day, label, tiny, cash, legacy, zone, clock, tag, code, latin FROM item ORDER BY id", zero)
    if query_error != ok { ret 16i32 }
    var rows = rows0
    let cols = db.columns(&rows)
    if cols.len != 20usize { ret 17i32 }
    if !str.eq(cols[0].name, "id") || cols[0].kind != .I64 || cols[1].kind != .Text || cols[2].kind != .F64 { ret 18i32 }
    if cols[3].kind != .Bytes || cols[4].kind != .Bool || cols[5].kind != .Time || cols[6].kind != .I64 || cols[7].kind != .I64 { ret 19i32 }
    if cols[8].kind != .F64 || cols[9].kind != .Text || cols[10].kind != .Time || cols[11].kind != .Text || cols[12].kind != .I64 { ret 20i32 }
    if cols[13].kind != .Text || cols[14].kind != .Time || cols[15].kind != .Time || cols[16].kind != .Text || cols[17].kind != .Text || cols[18].kind != .Text { ret 21i32 }
    if cols[0].nullable || cols[1].nullable || !cols[2].nullable { ret 22i32 }

    var row: [20]db.Value = zero
    let (first, first_error) = db.reader_next_err(&rows, row[0..])
    if first_error != ok || !first { ret 23i32 }
    let (id1, id1_ok) = as_i64(row[0])
    if !id1_ok || id1 != 1i64 { ret 24i32 }
    let (name1, name1_ok) = as_text(row[1])
    if !name1_ok || !str.eq(name1, "\xef\xbb\xbfh\xc3\xa9llo \xe2\x82\xac \xf0\x9f\x98\x80") { ret 25i32 }
    let (score1, score1_ok) = as_f64(row[2])
    if !score1_ok || score1 != 0.1f64 { ret 26i32 }
    let (data1, data1_ok) = as_bytes(row[3])
    if !data1_ok || !same_bytes(data1, blob[0..]) { ret 27i32 }
    let (flag1, flag1_ok) = as_bool(row[4])
    if !flag1_ok || !flag1 { ret 28i32 }
    // datetime2(7) keeps 100 ns.
    let (seen1, seen1_ok) = as_time(row[5])
    if !seen1_ok || seen1 != 1700000000123456700i64 { ret 29i32 }
    let (small1, small1_ok) = as_i64(row[6])
    if !small1_ok || small1 != -32768i64 { ret 30i32 }
    let (medium1, medium1_ok) = as_i64(row[7])
    if !medium1_ok || medium1 != 2147483647i64 { ret 31i32 }
    let (single1, single1_ok) = as_f64(row[8])
    if !single1_ok || single1 != 0.5f64 { ret 32i32 }
    let (amount1, amount1_ok) = as_text(row[9])
    if !amount1_ok || !str.eq(amount1, "12345.678900") { ret 33i32 }
    let (day1, day1_ok) = as_time(row[10])
    if !day1_ok || day1 != 1709164800000000000i64 { ret 34i32 }
    let (label1, label1_ok) = as_text(row[11])
    if !label1_ok || !str.eq(label1, "tag") { ret 35i32 }
    let (tiny1, tiny1_ok) = as_i64(row[12])
    if !tiny1_ok || tiny1 != 255i64 { ret 36i32 }
    let (cash1, cash1_ok) = as_text(row[13])
    if !cash1_ok || !str.eq(cash1, "-12.3456") { ret 37i32 }
    // datetime ticks are 1/300 s; .787 is one of the values it holds.
    let (legacy1, legacy1_ok) = as_time(row[14])
    if !legacy1_ok || legacy1 != 1709210096787000000i64 { ret 38i32 }
    // datetimeoffset as the instant: 12:00 at +02:00 is 10:00 UTC.
    let (zone1, zone1_ok) = as_time(row[15])
    if !zone1_ok || zone1 != 1709200800000000000i64 { ret 39i32 }
    let (clock1, clock1_ok) = as_text(row[16])
    if !clock1_ok || !str.eq(clock1, "12:34:56.1234567") { ret 40i32 }
    let (tag1, tag1_ok) = as_text(row[17])
    if !tag1_ok || !str.eq(tag1, "6F9619FF-8B86-D011-B42D-00C04FC964FF") { ret 41i32 }
    let (code1, code1_ok) = as_text(row[18])
    if !code1_ok || !str.eq(code1, "ab ") { ret 42i32 }
    // A Windows-1252 byte (0xE9) read as UTF-8.
    let (latin1, latin1_ok) = as_text(row[19])
    if !latin1_ok || !str.eq(latin1, "caf\xc3\xa9") { ret 43i32 }

    let (more2, second_row_error) = db.reader_next_err(&rows, row[0..])
    if second_row_error != ok || !more2 { ret 44i32 }
    let (name2, name2_ok) = as_text(row[1])
    if !name2_ok || name2.len != 0usize { ret 45i32 }
    let (data2, data2_ok) = as_bytes(row[3])
    if !data2_ok || data2.len != 0usize { ret 46i32 }
    let (flag2, flag2_ok) = as_bool(row[4])
    if !flag2_ok || flag2 { ret 47i32 }
    if !is_null(row[2]) || !is_null(row[5]) || !is_null(row[6]) || !is_null(row[9]) || !is_null(row[10]) || !is_null(row[11]) || !is_null(row[17]) { ret 48i32 }
    let (more3, end_error) = db.reader_next_err(&rows, row[0..])
    if end_error != ok || more3 { ret 49i32 }
    if db.close_rows(&rows) != ok { ret 50i32 }

    // A column name outside ASCII; a U64 inside and past `i64`; NULL, a bool and a double echoed.
    let (named0, named_error) = db.query(c, "SELECT 1 AS [na\xc3\xafve]", zero)
    if named_error != ok { ret 51i32 }
    var named = named0
    let named_cols = db.columns(&named)
    if named_cols.len != 1usize || !str.eq(named_cols[0].name, "na\xc3\xafve") { ret 52i32 }
    if db.close_rows(&named) != ok { ret 53i32 }
    var u: [1]db.Parameter = zero
    u[0] = positional(db.Value{ U64: 4000000000u64 })
    let (bigger, bigger_error) = db.execute(c, "UPDATE item SET medium = 0 WHERE id + ? > 4000000000", u[0..])
    if bigger_error != ok || bigger != 2u64 { ret 54i32 }
    u[0] = positional(db.Value{ U64: 18446744073709551615u64 })
    if !text_is(c, "SELECT CAST(? AS nvarchar(40))", u[0..], "18446744073709551615") { ret 55i32 }
    u[0] = positional(.Null)
    let (null_back, null_error) = scalar(c, "SELECT ?", u[0..])
    if null_error != ok || !is_null(null_back) { ret 56i32 }
    u[0] = positional(db.Value{ F64: 1e300f64 })
    let (real_back, real_error) = scalar(c, "SELECT ?", u[0..])
    let (real_value, real_ok) = as_f64(real_back)
    if real_error != ok || !real_ok || real_value != 1e300f64 { ret 57i32 }
    ret 0i32
}

fn counts_and_errors(a: *mem.Arena, c: *db.Connection) -> i32 {
    // Rows changed are summed over the script; the SELECT in it counts nothing.
    let (script, script_error) = db.execute(c, "INSERT INTO other VALUES (1), (2); SELECT 1; UPDATE other SET x = x + 10; INSERT INTO other VALUES (3)", zero)
    if script_error != ok || script != 5u64 { ret 60i32 }
    let (none, none_error) = db.execute(c, "UPDATE other SET x = 0 WHERE x < 0", zero)
    if none_error != ok || none != 0u64 { ret 61i32 }
    let (clean, clean_error) = tds.detail(a, c)
    if clean_error != ok || clean.number != 0i32 || clean.message.len != 0usize { ret 62i32 }

    var dup: [3]db.Parameter = zero
    dup[0] = positional(db.Value{ I64: 1i64 })
    dup[1] = positional(db.Value{ Text: "again" })
    dup[2] = positional(db.Value{ Text: "ok" })
    let (d, dup_error) = db.execute(c, "INSERT INTO item(id, name, label) VALUES (?, ?, ?)", dup[0..])
    if dup_error != db.Constraint { ret 63i32 }
    let (why, why_error) = tds.detail(a, c)
    if why_error != ok || why.number != 2627i32 || why.severity != 14u8 || why.message.len == 0usize { ret 64i32 }
    dup[0] = positional(db.Value{ I64: 3i64 })
    dup[2] = positional(db.Value{ Text: "bad" })
    let (k, check_error) = db.execute(c, "INSERT INTO item(id, name, label) VALUES (?, ?, ?)", dup[0..])
    if check_error != db.Constraint { ret 65i32 }
    let (check_why, check_why_error) = tds.detail(a, c)
    if check_why_error != ok || check_why.number != 547i32 { ret 66i32 }
    let (syntax, syntax_error) = db.execute(c, "SELECT FROM WHERE", zero)
    if syntax_error != db.InvalidQuery { ret 67i32 }
    let (syntax_why, syntax_why_error) = tds.detail(a, c)
    if syntax_why_error != ok || syntax_why.number != 156i32 || syntax_why.severity != 15u8 { ret 68i32 }
    let (divided, divide_error) = db.execute(c, "SELECT 1 / 0", zero)
    if divide_error != db.InvalidQuery { ret 69i32 }
    let (missing, missing_error) = db.query(c, "SELECT * FROM nowhere", zero)
    if missing_error != db.InvalidQuery { ret 70i32 }
    let (missing_why, missing_why_error) = tds.detail(a, c)
    if missing_why_error != ok || missing_why.number != 208i32 { ret 71i32 }

    // The driver's own refusals: a named parameter, and a count that differs.
    var named: [1]db.Parameter = zero
    named[0] = db.Parameter { name: "id", value: db.Value{ I64: 1i64 } }
    let (n1, named_error) = db.execute(c, "SELECT ?", named[0..])
    if named_error != db.InvalidQuery { ret 72i32 }
    let (refusal, refusal_error) = tds.detail(a, c)
    if refusal_error != ok || refusal.number != 0i32 || refusal.message.len == 0usize { ret 73i32 }
    let (n2, count_error) = db.execute(c, "SELECT ?, ?", dup[0..1])
    if count_error != db.InvalidQuery { ret 74i32 }
    var row: [1]db.Value = zero
    let (echo0, echo_error) = db.query(c, "SELECT count(*) FROM other", zero)
    if echo_error != ok { ret 75i32 }
    var echo = echo0
    let (short, short_error) = db.reader_next_err(&echo, row[0usize..0usize])
    if short_error != db.InvalidQuery { ret 76i32 }
    if db.close_rows(&echo) != ok { ret 77i32 }

    // Not placeholders: in a string, quoted identifiers and a nested comment.
    var one: [1]db.Parameter = zero
    one[0] = positional(db.Value{ Text: "x" })
    if !text_is(c, "SELECT '?''?' + [a?] + \"b?\" + ? /* ? /* ? */ ? */ -- ?\n FROM (SELECT 'a' AS [a?], 'b' AS \"b?\") AS t", one[0..], "?'?abx") { ret 78i32 }
    ret 0i32
}

fn statements(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (st0, prepare_error) = db.prepare(c, "INSERT INTO other VALUES (?)")
    if prepare_error != ok { ret 80i32 }
    var st = st0
    var p: [1]db.Parameter = zero
    var i = 0i64
    while i < 3i64 {
        p[0] = positional(db.Value{ I64: 100i64 + i })
        let (n, e) = db.execute_statement(&st, p[0..])
        if e != ok || n != 1u64 { ret 81i32 }
        i += 1i64
    }
    let (short_n, short_error) = db.execute_statement(&st, zero)
    if short_error != db.InvalidQuery { ret 82i32 }
    if db.close_statement(&st) != ok { ret 83i32 }
    let (after, after_error) = db.execute_statement(&st, p[0..])
    if after_error != db.Closed { ret 84i32 }

    let (sel0, sel_error) = db.prepare(c, "SELECT x FROM other WHERE x >= ? ORDER BY x")
    if sel_error != ok { ret 85i32 }
    var sel = sel0
    p[0] = positional(db.Value{ I64: 101i64 })
    let (r0, r_error) = db.query_statement(&sel, p[0..])
    if r_error != ok { ret 86i32 }
    var r = r0
    var row: [1]db.Value = zero
    let (m1, e1) = db.reader_next_err(&r, row[0..])
    let (x1, x1_ok) = as_i64(row[0])
    if e1 != ok || !m1 || !x1_ok || x1 != 101i64 { ret 87i32 }
    // The connection is busy while the reader streams, the statement's own included.
    let (busy, busy_error) = db.query_statement(&sel, p[0..])
    if busy_error != db.Busy { ret 88i32 }
    // Closing the statement under its reader: the reader answers `Closed`, the connection goes on.
    if db.close_statement(&sel) != ok { ret 89i32 }
    let (m3, e3) = db.reader_next_err(&r, row[0..])
    if e3 != db.Closed { ret 90i32 }
    if db.close_rows(&r) != ok { ret 91i32 }
    let (n, n_error) = scalar_i64(c, "SELECT 7")
    if n_error != ok || n != 7i64 { ret 92i32 }

    // `prepare` sends nothing, so text that cannot run fails at its first execution.
    let (bad0, bad_error) = db.prepare(c, "SELECT nothing_here FROM other")
    if bad_error != ok { ret 93i32 }
    var bad = bad0
    let (bad_rows, bad_run_error) = db.query_statement(&bad, zero)
    if bad_run_error != db.InvalidQuery { ret 94i32 }
    let (bad_why, bad_why_error) = tds.detail(a, c)
    if bad_why_error != ok || bad_why.number != 207i32 { ret 95i32 }
    if db.close_statement(&bad) != ok { ret 96i32 }
    ret 0i32
}

fn streaming(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (rows0, rows_error) = db.query(c, "SELECT value, REPLICATE('x', value % 7) FROM GENERATE_SERIES(1, 1000) ORDER BY value", zero)
    if rows_error != ok { ret 100i32 }
    var rows = rows0
    let (busy_n, busy_error) = db.execute(c, "SELECT 1", zero)
    if busy_error != db.Busy { ret 101i32 }
    let (busy_tx, busy_tx_error) = db.begin(c)
    if busy_tx_error != db.Busy { ret 102i32 }
    var row: [2]db.Value = zero
    var total = 0i64
    var count = 0i64
    while true {
        let (more, next_error) = db.reader_next_err(&rows, row[0..])
        if next_error != ok { ret 103i32 }
        if !more { break }
        let (g, g_ok) = as_i64(row[0])
        let (s, s_ok) = as_text(row[1])
        if !g_ok || !s_ok || i64(s.len) != g % 7i64 { ret 104i32 }
        total += g
        count += 1i64
    }
    if count != 1000i64 || total != 500500i64 { ret 105i32 }
    if db.close_rows(&rows) != ok { ret 106i32 }

    // A reader closed after one row of a million; the connection goes on.
    let (early0, early_error) = db.query(c, "SELECT a.value FROM GENERATE_SERIES(1, 1000) AS a CROSS JOIN GENERATE_SERIES(1, 1000) AS b", zero)
    if early_error != ok { ret 107i32 }
    var early = early0
    let (e_more, e_next_error) = db.reader_next_err(&early, row[0..])
    if e_next_error != ok || !e_more { ret 108i32 }
    if db.close_rows(&early) != ok { ret 109i32 }
    if db.close_rows(&early) != db.Closed { ret 110i32 }
    let (n, n_error) = scalar_i64(c, "SELECT 42")
    if n_error != ok || n != 42i64 { ret 111i32 }

    // 100 KB of text (two-byte characters) and of bytes: nvarchar(max) and varbinary(max), PLP
    // both ways and across many packets.
    let (big, big_error) = mem.alloc[u8](a, 100000usize)
    if big_error != ok { ret 112i32 }
    var i = 0usize
    while i < big.len {
        big[i] = u8(i % 251usize)
        i += 1usize
    }
    let (text, text_error) = mem.alloc[u8](a, 100000usize)
    if text_error != ok { ret 113i32 }
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
    if store_error != ok || stored != 1u64 { ret 114i32 }
    let (back0, back_error) = db.query(c, "SELECT name, data, LEN(name) FROM item WHERE id = 50", zero)
    if back_error != ok { ret 115i32 }
    var back = back0
    var three: [3]db.Value = zero
    let (b_more, b_error) = db.reader_next_err(&back, three[0..])
    if b_error != ok || !b_more { ret 116i32 }
    let (name, name_ok) = as_text(three[0])
    if !name_ok || !same_bytes(name, text) { ret 117i32 }
    let (data, data_ok) = as_bytes(three[1])
    if !data_ok || !same_bytes(data, big) { ret 118i32 }
    let (length, length_ok) = as_i64(three[2])
    if !length_ok || length != 50000i64 { ret 119i32 }
    if db.close_rows(&back) != ok { ret 120i32 }

    // The connection keeps nothing it grows: a caller may reset the arena around any call, the
    // 100 KB ones included, and the connection goes on even after the freed memory is reused.
    var round = 0usize
    while round < 3usize {
        let mark = mem.mark(a)
        var update: [2]db.Parameter = zero
        update[0] = positional(db.Value{ Bytes: big })
        update[1] = positional(db.Value{ Text: long_text })
        let (changed, change_error) = db.execute(c, "UPDATE item SET data = ?, name = ? WHERE id = 50", update[0..])
        if change_error != ok || changed != 1u64 { ret 121i32 }
        let (again0, again_error) = db.query(c, "SELECT name, data FROM item WHERE id = 50", zero)
        if again_error != ok { ret 122i32 }
        var again = again0
        let (a_more, a_error) = db.reader_next_err(&again, three[0..])
        let (again_name, again_name_ok) = as_text(three[0])
        let (again_data, again_data_ok) = as_bytes(three[1])
        if a_error != ok || !a_more || !again_name_ok || !same_bytes(again_name, text) || !again_data_ok || !same_bytes(again_data, big) { ret 123i32 }
        if db.close_rows(&again) != ok { ret 124i32 }
        mem.reset(a, mark)
        let (scribble, scribble_error) = mem.alloc[u8](a, 600000usize)
        if scribble_error != ok { ret 125i32 }
        var s = 0usize
        while s < scribble.len {
            scribble[s] = 170u8
            s += 1usize
        }
        mem.reset(a, mark)
        round += 1usize
    }
    let (after, after_error) = scalar_i64(c, "SELECT 43")
    if after_error != ok || after != 43i64 { ret 126i32 }
    ret 0i32
}

fn transactions(a: *mem.Arena, c: *db.Connection) -> i32 {
    let (before, before_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if before_error != ok { ret 130i32 }
    let (tx0, begin_error) = db.begin(c)
    if begin_error != ok { ret 131i32 }
    var tx = tx0
    let (nested, nested_error) = db.begin(c)
    if nested_error != db.Busy { ret 132i32 }
    let (n1, e1) = db.execute_transaction(&tx, "INSERT INTO other VALUES (10)", zero)
    if e1 != ok || n1 != 1u64 { ret 133i32 }
    if db.rollback(&tx) != ok { ret 134i32 }
    if db.rollback(&tx) != db.Closed { ret 135i32 }
    let (after_rollback, after_rollback_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if after_rollback_error != ok || after_rollback != before { ret 136i32 }

    let (tx1, begin1_error) = db.begin(c)
    if begin1_error != ok { ret 137i32 }
    var kept = tx1
    var p: [1]db.Parameter = zero
    p[0] = positional(db.Value{ I64: 11i64 })
    let (n2, e2) = db.execute_transaction(&kept, "INSERT INTO other VALUES (?)", p[0..])
    if e2 != ok || n2 != 1u64 { ret 138i32 }
    let (inside0, inside_error) = db.query_transaction(&kept, "SELECT count(*) FROM other", zero)
    if inside_error != ok { ret 139i32 }
    var inside = inside0
    var row: [1]db.Value = zero
    let (inside_more, inside_next_error) = db.reader_next_err(&inside, row[0..])
    let (inside_n, inside_ok) = as_i64(row[0])
    if inside_next_error != ok || !inside_more || !inside_ok || inside_n != before + 1i64 { ret 140i32 }
    // Committing with the reader open ends the reader first.
    if db.commit(&kept) != ok { ret 141i32 }
    if db.close_rows(&inside) != ok { ret 142i32 }
    let (after_commit, after_commit_error) = scalar_i64(c, "SELECT count(*) FROM other")
    if after_commit_error != ok || after_commit != before + 1i64 { ret 143i32 }
    let (n3, e3) = db.execute(c, "INSERT INTO other VALUES (12)", zero)
    if e3 != ok || n3 != 1u64 { ret 144i32 }

    // A failed statement leaves SQL Server's transaction open (XACT_ABORT is off).
    let (tx2, begin2_error) = db.begin(c)
    if begin2_error != ok { ret 145i32 }
    var failing = tx2
    let (n4, e4) = db.execute_transaction(&failing, "INSERT INTO other VALUES (13)", zero)
    if e4 != ok { ret 146i32 }
    let (n5, e5) = db.execute_transaction(&failing, "INSERT INTO other VALUES (1 / 0)", zero)
    if e5 != db.InvalidQuery { ret 147i32 }
    let (n6, e6) = db.execute_transaction(&failing, "INSERT INTO other VALUES (14)", zero)
    if e6 != ok || n6 != 1u64 { ret 148i32 }
    if db.rollback(&failing) != ok { ret 149i32 }
    let (after_fail, after_fail_error) = scalar_i64(c, "SELECT count(*) FROM other WHERE x IN (13, 14)")
    if after_fail_error != ok || after_fail != 0i64 { ret 150i32 }

    // With XACT_ABORT on, the error ends the transaction on the server: what follows is `Aborted`.
    let (tx3, begin3_error) = db.begin(c)
    if begin3_error != ok { ret 151i32 }
    var aborted = tx3
    let (n7, e7) = db.execute_transaction(&aborted, "INSERT INTO other VALUES (15)", zero)
    if e7 != ok { ret 152i32 }
    let (n8, e8) = db.execute_transaction(&aborted, "SET XACT_ABORT ON; INSERT INTO other VALUES (1 / 0)", zero)
    if e8 != db.InvalidQuery { ret 153i32 }
    let (n9, e9) = db.execute_transaction(&aborted, "INSERT INTO other VALUES (16)", zero)
    if e9 != tds.Aborted { ret 154i32 }
    if db.commit(&aborted) != tds.Aborted { ret 155i32 }
    let (n10, e10) = db.execute(c, "SET XACT_ABORT OFF", zero)
    if e10 != ok { ret 156i32 }
    let (after_abort, after_abort_error) = scalar_i64(c, "SELECT count(*) FROM other WHERE x IN (15, 16)")
    if after_abort_error != ok || after_abort != 0i64 { ret 157i32 }
    let (tx4, begin4_error) = db.begin(c)
    if begin4_error != ok { ret 158i32 }
    var again = tx4
    if db.rollback(&again) != ok { ret 159i32 }
    ret 0i32
}

fn two_connections(a: *mem.Arena, options: tds.Options) -> i32 {
    let (first0, first_error) = tds.open(a, options)
    if first_error != ok { ret 170i32 }
    var first = first0
    let (second0, second_error) = tds.open(a, options)
    if second_error != ok { ret 171i32 }
    var second = second0
    let (tx0, begin_error) = db.begin(&first)
    if begin_error != ok { ret 172i32 }
    var tx = tx0
    let (locked, lock_error) = db.execute_transaction(&tx, "UPDATE item SET flag = 1 WHERE id = 1", zero)
    if lock_error != ok || locked != 1u64 { ret 173i32 }
    let (blocked, blocked_error) = db.execute(&second, "SET LOCK_TIMEOUT 0; SELECT id FROM item WITH (UPDLOCK, ROWLOCK) WHERE id = 1", zero)
    if blocked_error != db.Busy { ret 174i32 }
    let (why, why_error) = tds.detail(a, &second)
    if why_error != ok || why.number != 1222i32 { ret 175i32 }
    if db.rollback(&tx) != ok { ret 176i32 }
    let (free, free_error) = db.execute(&second, "SELECT id FROM item WITH (UPDLOCK, ROWLOCK) WHERE id = 1", zero)
    if free_error != ok { ret 177i32 }
    // Closing with a transaction open lets the server roll it back.
    let (open_tx, open_tx_error) = db.begin(&second)
    if open_tx_error != ok { ret 178i32 }
    if db.close(&second) != ok { ret 179i32 }
    if db.close(&first) != ok { ret 180i32 }
    if db.close(&first) != db.Closed { ret 181i32 }
    let (closed_n, closed_error) = db.execute(&first, "SELECT 1", zero)
    if closed_error != db.Closed { ret 182i32 }
    let (closed_detail, closed_detail_error) = tds.detail(a, &first)
    if closed_detail_error != db.Closed { ret 183i32 }

    // A wrong password is refused by SQL Server; no trust root is refused before connecting.
    var wrong = options
    wrong.password = "not the password"
    let (refused, refused_error) = tds.open(a, wrong)
    if refused_error != tds.CannotConnect { ret 184i32 }
    var untrusted = options
    untrusted.trust_roots = options.trust_roots[0usize..0usize]
    let (unchecked, unchecked_error) = tds.open(a, untrusted)
    if unchecked_error != tds.CannotConnect { ret 185i32 }
    ret 0i32
}

// With the host's OpenSSL, if it has one, sealing the records (D1646): 100 KB of text and bytes
// through a connection whose TLS cipher is libcrypto's, read back by the portable one.
fn openssl_cipher(a: *mem.Arena, options: tds.Options) -> i32 {
    let (openssl, load_error) = crypto.load(a)
    if load_error == crypto.NotFound { ret 0i32 }
    if load_error != ok { ret 190i32 }
    let (c0, open_error) = tds.open_with_cipher(a, options, crypto.aead_of(openssl))
    if open_error != ok { ret 191i32 }
    var c = c0
    let (text, text_error) = mem.alloc[u8](a, 100000usize)
    let (big, big_error) = mem.alloc[u8](a, 100000usize)
    if text_error != ok || big_error != ok { ret 192i32 }
    var i = 0usize
    while i < 100000usize {
        text[i] = u8(97usize + i % 26usize)
        big[i] = u8(i % 253usize)
        i += 1usize
    }
    let long_text: str = text
    var p: [3]db.Parameter = zero
    p[0] = positional(db.Value{ I64: 60i64 })
    p[1] = positional(db.Value{ Text: long_text })
    p[2] = positional(db.Value{ Bytes: big })
    let (stored, store_error) = db.execute(&c, "INSERT INTO item(id, name, data) VALUES (?, ?, ?)", p[0..])
    if store_error != ok || stored != 1u64 { ret 193i32 }
    if db.close(&c) != ok { ret 194i32 }
    if crypto.close(openssl) != ok { ret 195i32 }
    let (plain0, plain_error) = tds.open(a, options)
    if plain_error != ok { ret 196i32 }
    var plain = plain0
    let (back0, back_error) = db.query(&plain, "SELECT name, data FROM item WHERE id = 60", zero)
    if back_error != ok { ret 197i32 }
    var back = back0
    var row: [2]db.Value = zero
    let (more, next_error) = db.reader_next_err(&back, row[0..])
    let (name, name_ok) = as_text(row[0])
    let (data, data_ok) = as_bytes(row[1])
    if next_error != ok || !more || !name_ok || !same_bytes(name, text) || !data_ok || !same_bytes(data, big) { ret 198i32 }
    if db.close_rows(&back) != ok || db.close(&plain) != ok { ret 199i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 6usize { os.exit(1i32) }
    let (roots, roots_error) = fs.read_file(a, args[3], 65536usize)
    if roots_error != ok { os.exit(2i32) }
    let (port, port_error) = str.parse_u64(args[2])
    if port_error != ok { os.exit(2i32) }
    let options = tds.Options { host: args[1], port: u16(port), user: args[4], password: args[5], database: "neper", trust_roots: roots }
    let (conn0, open_error) = tds.open(a, options)
    if open_error != ok { os.exit(3i32) }
    var c = conn0
    var code = values(a, &c)
    if code == 0i32 { code = counts_and_errors(a, &c) }
    if code == 0i32 { code = statements(a, &c) }
    if code == 0i32 { code = streaming(a, &c) }
    if code == 0i32 { code = transactions(a, &c) }
    if code == 0i32 { code = two_connections(a, options) }
    if code == 0i32 { code = openssl_cipher(a, options) }
    if code == 0i32 && db.close(&c) != ok { code = 4i32 }
    if code != 0i32 { os.exit(code) }
    ret ok
}
