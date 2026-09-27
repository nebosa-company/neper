// Unit tests for the database drivers' own logic, with no server and no client library: the
// language has no visibility, so a driver's internal functions are called directly. Nothing
// here reaches an `@import`, so the executable binds neither libpq nor libmysql and runs on a
// host that has neither. Every check has its own exit code.
//
// `x.postgresql.libpq`: big-endian reads, the binary `numeric` renderer on hand-built values
// (the same encodings the server-side fixture reads back from PostgreSQL), `uuid` spelling,
// parameter encoding for natural and server-settled types, and SQLSTATE mapping.
// `x.oracle.mysql`: the statement scanner (placeholders and statement ends outside strings,
// identifiers and comments), rendering (double literals, hex blobs, datetimes), datetime
// parsing including zero dates, column kinds, and error mapping.
use e.os
use e.mem
use e.str
use e.time
use e.db
use x.postgresql.libpq
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

fn pg_conn(a: *mem.Arena) -> libpq.Conn {
    let (buffers, buffers_error) = mem.alloc[u8](a, 1288usize)
    var c: libpq.Conn = zero
    c.arena = a
    c.state = buffers[0usize..8usize]
    c.message = buffers[8usize..1032usize]
    c.constraint = buffers[1032usize..]
    ret c
}

fn pg_reader(c: *libpq.Conn) -> libpq.Reader {
    var r: libpq.Reader = zero
    r.conn = c
    ret r
}

// A binary `numeric`: digit count, weight, sign, display scale, then base-10000 digits.
fn numeric(out: []u8, weight: i64, sign: u64, dscale: u64, digits: []const u64) -> []u8 {
    libpq.put_be(out[0usize..2usize], u64(digits.len), 2usize)
    libpq.put_be(out[2usize..4usize], mem.bitcast[u64](weight), 2usize)
    libpq.put_be(out[4usize..6usize], sign, 2usize)
    libpq.put_be(out[6usize..8usize], dscale, 2usize)
    var i = 0usize
    while i < digits.len {
        libpq.put_be(out[8usize + i * 2usize..10usize + i * 2usize], digits[i], 2usize)
        i += 1usize
    }
    ret out[0usize..8usize + digits.len * 2usize]
}

fn renders(r: *libpq.Reader, encoded: []const u8, expected: str) -> bool {
    let (text, text_error) = libpq.numeric_text(r, encoded)
    ret text_error == ok && same_bytes(text, expected)
}

fn postgresql(a: *mem.Arena) -> i32 {
    var two: [2]u8 = zero
    two[0] = 255u8
    two[1] = 254u8
    if libpq.get_be_signed(two[0..], 2usize) != -2i64 { ret 10i32 }
    var eight: [8]u8 = zero
    eight[0] = 128u8
    if libpq.get_be_signed(eight[0..], 8usize) != -9223372036854775807i64 - 1i64 { ret 11i32 }
    if libpq.get_be(two[0..], 2usize) != 65534u64 { ret 12i32 }

    var c = pg_conn(a)
    var r = pg_reader(&c)
    var buf: [32]u8 = zero
    var d3: [3]u64 = zero
    d3[0] = 1u64
    d3[1] = 2345u64
    d3[2] = 6789u64
    if !renders(&r, numeric(buf[0..], 1i64, 0u64, 6u64, d3[0..]), "12345.678900") { ret 13i32 }
    var d1: [1]u64 = zero
    d1[0] = 1u64
    if !renders(&r, numeric(buf[0..], -1i64, 16384u64, 6u64, d1[0..]), "-0.000100") { ret 14i32 }
    let none: []const u64 = zero
    if !renders(&r, numeric(buf[0..], 0i64, 0u64, 2u64, none), "0.00") { ret 15i32 }
    d1[0] = 1u64
    if !renders(&r, numeric(buf[0..], -2i64, 0u64, 8u64, d1[0..]), "0.00000001") { ret 16i32 }
    if !renders(&r, numeric(buf[0..], 1i64, 0u64, 0u64, d1[0..]), "10000") { ret 17i32 }
    if !renders(&r, numeric(buf[0..], 0i64, 49152u64, 0u64, none), "NaN") { ret 18i32 }
    if !renders(&r, numeric(buf[0..], 0i64, 61440u64, 0u64, none), "-Infinity") { ret 19i32 }
    // Scale shorter than the stored group: 1.5 is the group 5000 at weight -1, scale 1.
    var d2: [2]u64 = zero
    d2[0] = 1u64
    d2[1] = 5000u64
    if !renders(&r, numeric(buf[0..], 0i64, 0u64, 1u64, d2[0..]), "1.5") { ret 20i32 }
    // Truncated input is refused, not read past.
    let (cut, cut_error) = libpq.numeric_text(&r, buf[0usize..5usize])
    if cut_error == ok { ret 21i32 }

    var id: [16]u8 = zero
    var k = 0usize
    while k < 16usize {
        id[k] = u8(k * 17usize)
        k += 1usize
    }
    let (spelled, spelled_error) = libpq.uuid_text(&r, id[0..])
    if spelled_error != ok || !same_bytes(spelled, "00112233-4455-6677-8899-aabbccddeeff") { ret 22i32 }

    // Natural types: int8, float8, bool, bytea, timestamptz from PostgreSQL's epoch, and text as
    // `unknown`, NUL-terminated.
    let (p1, p1_error) = libpq.encode(&c, a, db.Value{ I64: -2i64 }, 0u32)
    if p1_error != ok || p1.oid != 20u32 || p1.format != 1i32 || p1.bytes.len != 8usize || p1.bytes[7usize] != 254u8 || p1.bytes[0usize] != 255u8 { ret 23i32 }
    let (p2, p2_error) = libpq.encode(&c, a, db.Value{ F64: 1.0f64 }, 0u32)
    if p2_error != ok || p2.oid != 701u32 || libpq.get_be(p2.bytes, 8usize) != 4607182418800017408u64 { ret 24i32 }
    let (p3, p3_error) = libpq.encode(&c, a, db.Value{ Text: "hi" }, 0u32)
    if p3_error != ok || p3.oid != 0u32 || p3.format != 0i32 || p3.bytes.len != 3usize || p3.bytes[2usize] != 0u8 { ret 25i32 }
    var nothing: [1]u8 = zero
    let (p4, p4_error) = libpq.encode(&c, a, db.Value{ Bytes: nothing[0usize..0usize] }, 0u32)
    if p4_error != ok || p4.oid != 17u32 || p4.bytes.len != 0usize || p4.address == 0usize || p4.null { ret 26i32 }
    let (p5, p5_error) = libpq.encode(&c, a, db.Value{ Time: time.Instant { nanos: 946684800000001000i64 } }, 0u32)
    if p5_error != ok || p5.oid != 1184u32 || libpq.get_be_signed(p5.bytes, 8usize) != 1i64 { ret 27i32 }
    let (p6, p6_error) = libpq.encode(&c, a, .Null, 23u32)
    if p6_error != ok || !p6.null { ret 28i32 }
    // A `U64` past `bigint` goes as numeric text.
    let (p7, p7_error) = libpq.encode(&c, a, db.Value{ U64: 18446744073709551615u64 }, 0u32)
    if p7_error != ok || p7.oid != 1700u32 || p7.format != 0i32 || !same_bytes(p7.bytes[0usize..20usize], "18446744073709551615") { ret 29i32 }
    // Server-settled types: an `I64` narrows to int4 and int2 with a range check; a double into
    // numeric goes as its shortest text; a time into a date is a day count.
    let (p8, p8_error) = libpq.encode(&c, a, db.Value{ I64: 7i64 }, 23u32)
    if p8_error != ok || p8.oid != 23u32 || p8.bytes.len != 4usize || libpq.get_be(p8.bytes, 4usize) != 7u64 { ret 30i32 }
    let (p9, p9_error) = libpq.encode(&c, a, db.Value{ I64: 40000i64 }, 21u32)
    if p9_error != db.Unsupported { ret 31i32 }
    let (p10, p10_error) = libpq.encode(&c, a, db.Value{ F64: 0.1f64 }, 1700u32)
    if p10_error != ok || p10.format != 0i32 || !same_bytes(p10.bytes[0usize..3usize], "0.1") { ret 32i32 }
    let (p11, p11_error) = libpq.encode(&c, a, db.Value{ Time: time.Instant { nanos: 86400000000000i64 * 10958i64 } }, 1082u32)
    if p11_error != ok || p11.oid != 1082u32 || libpq.get_be_signed(p11.bytes, 4usize) != 1i64 { ret 33i32 }
    let (p12, p12_error) = libpq.encode(&c, a, db.Value{ F64: mem.bitcast[f64](9218868437227405312u64) }, 1700u32)
    if p12_error != ok || !same_bytes(p12.bytes[0usize..8usize], "Infinity") { ret 34i32 }
    let (p13, p13_error) = libpq.encode(&c, a, db.Value{ Time: time.Instant { nanos: 0i64 } }, 25u32)
    if p13_error != db.Unsupported { ret 35i32 }

    if libpq.mapped("23505") != db.Constraint || libpq.mapped("40P01") != db.Busy || libpq.mapped("55P03") != db.Busy { ret 36i32 }
    if libpq.mapped("42601") != db.InvalidQuery || libpq.mapped("22012") != db.InvalidQuery || libpq.mapped("0A000") != db.Unsupported { ret 37i32 }
    if libpq.mapped("25P02") != libpq.Aborted || libpq.mapped("XX000") != libpq.Failed || libpq.mapped("") != libpq.Failed { ret 38i32 }
    if libpq.kind_of(1184u32) != .Time || libpq.kind_of(1700u32) != .Text || libpq.kind_of(600u32) != .Bytes || libpq.kind_of(16u32) != .Bool { ret 39i32 }
    ret 0i32
}

fn my_conn(a: *mem.Arena) -> mysql.Conn {
    let (buffers, buffers_error) = mem.alloc[u8](a, 1032usize)
    var c: mysql.Conn = zero
    c.arena = a
    c.state = buffers[0usize..8usize]
    c.message = buffers[8usize..]
    ret c
}

fn scans(sql: str, placeholders: usize, statements: usize) -> bool {
    var nothing: []u8 = zero
    let (scan, written) = mysql.walk(sql, zero, nothing)
    ret scan.placeholders == placeholders && scan.statements == statements
}

fn oracle_mysql(a: *mem.Arena) -> i32 {
    if !scans("SELECT ?", 1usize, 1usize) { ret 50i32 }
    if !scans("SELECT '?', \"?\", `?`, ? -- ?\n# ?\n/* ? */", 1usize, 1usize) { ret 51i32 }
    // Escaped and doubled quotes do not end a string.
    if !scans("SELECT 'it''s ?', 'a\\'?', ?", 1usize, 1usize) { ret 52i32 }
    if !scans("INSERT INTO t VALUES (?); INSERT INTO t VALUES (?, ?);", 3usize, 2usize) { ret 53i32 }
    if !scans("  -- only a comment\n; ;", 0usize, 0usize) { ret 54i32 }
    if !scans("SELECT 1; -- trailing", 0usize, 1usize) { ret 55i32 }
    // `--` needs a space after it to start a comment; `1--1` is arithmetic.
    if !scans("SELECT 1--1, ?", 1usize, 1usize) { ret 56i32 }
    if !scans("SELECT ';'", 0usize, 1usize) { ret 57i32 }
    // An unterminated string runs to the end rather than past it.
    if !scans("SELECT 'open ?", 0usize, 1usize) { ret 58i32 }

    var rendered: [2]str = zero
    rendered[0] = "1"
    rendered[1] = "'x'"
    var out: [64]u8 = zero
    let (filled, written) = mysql.walk("SELECT ?, '?', ? # ?", rendered[0..], out[0..])
    if !same_bytes(out[0usize..written], "SELECT 1, '?', 'x' # ?") { ret 59i32 }

    var c = my_conn(a)
    let (d1, d1_error) = mysql.double_literal(&c, a, 0.1f64)
    if d1_error != ok || !str.eq(d1, "0.1e0") { ret 60i32 }
    let (d2, d2_error) = mysql.double_literal(&c, a, 1e300f64)
    if d2_error != ok || !str.eq(d2, "1e300") { ret 61i32 }
    let (d3, d3_error) = mysql.double_literal(&c, a, mem.bitcast[f64](9221120237041090560u64))
    if d3_error != db.Unsupported { ret 62i32 }
    var blob: [3]u8 = zero
    blob[0] = 0u8
    blob[1] = 171u8
    blob[2] = 255u8
    let (hexed, hexed_error) = mysql.hex_literal(a, blob[0..])
    if hexed_error != ok || !str.eq(hexed, "X'00ABFF'") { ret 63i32 }
    let (stamp, stamp_error) = mysql.datetime_literal(&c, a, time.Instant { nanos: 1700000000123456789i64 })
    if stamp_error != ok || !str.eq(stamp, "'2023-11-14 22:13:20.123456'") { ret 64i32 }
    // Before the epoch, the microsecond is floored, not truncated toward zero.
    let (early, early_error) = mysql.datetime_literal(&c, a, time.Instant { nanos: -1i64 })
    if early_error != ok || !str.eq(early, "'1969-12-31 23:59:59.999999'") { ret 65i32 }

    let (n1, p1) = mysql.parse_datetime("2023-11-14 22:13:20.123456")
    if !p1 || n1 != 1700000000123456000i64 { ret 67i32 }
    let (n2, p2) = mysql.parse_datetime("2024-02-29")
    if !p2 || n2 != 19782i64 * 86400000000000i64 { ret 68i32 }
    let (n3, p3) = mysql.parse_datetime("0000-00-00 00:00:00")
    if p3 { ret 69i32 }
    let (n4, p4) = mysql.parse_datetime("2023-02-29")
    if p4 { ret 70i32 }
    let (n5, p5) = mysql.parse_datetime("2023-11-14 22:13:20.5")
    if !p5 || n5 != 1700000000500000000i64 { ret 71i32 }

    // Column kinds: TINYINT(1) is a boolean, BIGINT UNSIGNED may pass i64, binary strings are
    // bytes, DECIMAL is text.
    if mysql.kind_of(1u32, 0u32, false, 1usize) != .Bool || mysql.kind_of(1u32, 0u32, false, 4usize) != .I64 { ret 72i32 }
    if mysql.kind_of(8u32, 32u32, false, 20usize) != .U64 || mysql.kind_of(3u32, 32u32, false, 10usize) != .I64 { ret 73i32 }
    if mysql.kind_of(252u32, 0u32, true, 0usize) != .Bytes || mysql.kind_of(252u32, 0u32, false, 0usize) != .Text { ret 74i32 }
    if mysql.kind_of(246u32, 0u32, false, 10usize) != .Text || mysql.kind_of(12u32, 0u32, false, 26usize) != .Time { ret 75i32 }

    if mysql.mapped(1062u32, "23000") != db.Constraint || mysql.mapped(3819u32, "HY000") != db.Constraint { ret 76i32 }
    if mysql.mapped(1213u32, "40001") != db.Busy || mysql.mapped(3572u32, "HY000") != db.Busy || mysql.mapped(1205u32, "HY000") != db.Busy { ret 77i32 }
    if mysql.mapped(1064u32, "42000") != db.InvalidQuery || mysql.mapped(2013u32, "HY000") != mysql.Failed { ret 78i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var code = postgresql(a)
    if code == 0i32 { code = oracle_mysql(a) }
    if code != 0i32 { os.exit(code) }
    ret ok
}
