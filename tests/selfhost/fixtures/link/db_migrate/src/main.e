// `e.db.migrate` over `x.sqlite.sqlite` in memory. Checksum vectors come from
// scripts/gen_db_migrate_test.py (FNV-1a 64 of the `up` text, as the signed i64 the
// journal stores); the table state each section asserts is the one Python's sqlite3
// reaches for the same SQL. Sections: checksums and ordering, up/down/idempotence,
// partial `up` to a version, the three refusals (changed text, missing, out of order),
// a failed migration locking the journal until `unlock`, a failed multi-statement
// migration rolled back whole, an irreversible `down`, and the dialect SQL. Every
// check has its own exit code.
use e.os
use e.mem
use e.str
use e.db
use e.db.migrate as migrate
use x.sqlite.sqlite

fn up1() -> str { ret "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)" }
fn up2() -> str { ret "INSERT INTO users (id, name) VALUES (1, 'ada'), (2, 'bob')" }
fn up3() -> str { ret "CREATE INDEX users_name ON users (name)" }

fn all() -> [3]migrate.Migration {
    var ms: [3]migrate.Migration = zero
    ms[0] = migrate.Migration { version: 1i64, name: "create users", up: up1(), down: "DROP TABLE users" }
    ms[1] = migrate.Migration { version: 2i64, name: "seed", up: up2(), down: "DELETE FROM users" }
    ms[2] = migrate.Migration { version: 3i64, name: "index", up: up3(), down: "DROP INDEX users_name" }
    ret ms
}

fn scalar(c: *db.Connection, sql: str) -> i64 {
    let (rows0, query_error) = db.query(c, sql, zero)
    if query_error != ok { ret -1i64 }
    var rows = rows0
    var row: [1]db.Value = zero
    let (more, next_error) = db.reader_next_err(&rows, row[0..])
    let close_error = db.close_rows(&rows)
    if next_error != ok || !more { ret -1i64 }
    switch row[0] {
    case .I64 as n:
        ret n
    default:
        ret -1i64
    }
}

fn fresh(a: *mem.Arena) -> (db.Connection, err) {
    let (conn, open_error) = sqlite.open(a, ":memory:")
    ret (conn, open_error)
}

fn checks_pure() -> i32 {
    let ms = all()
    if migrate.checksum(ms[0]) != 4762152631198849030i64 { ret 10i32 }
    if migrate.checksum(ms[1]) != 0i64 - 2018011388470497333i64 { ret 11i32 }
    if migrate.checksum(ms[2]) != 5104457436989305108i64 { ret 12i32 }
    if migrate.validate(ms[0..]) != ok { ret 13i32 }
    var dup = all()
    dup[1].version = 1i64
    if migrate.validate(dup[0..]) != migrate.Order { ret 14i32 }
    var zero_v = all()
    zero_v[0].version = 0i64
    if migrate.validate(zero_v[0..]) != migrate.Order { ret 15i32 }
    var entries: [2]migrate.Entry = zero
    entries[0] = migrate.Entry { version: 1i64, checksum: migrate.checksum(ms[0]), dirty: false }
    entries[1] = migrate.Entry { version: 2i64, checksum: migrate.checksum(ms[1]), dirty: false }
    if migrate.verify(ms[0..], entries[0..]) != ok { ret 16i32 }
    entries[1].dirty = true
    if migrate.verify(ms[0..], entries[0..]) != migrate.Dirty { ret 17i32 }
    entries[1].dirty = false
    entries[1].checksum = 5i64
    if migrate.verify(ms[0..], entries[0..]) != migrate.Checksum { ret 18i32 }
    ret 0i32
}

fn checks_updown(a: *mem.Arena) -> i32 {
    let (c0, open_error) = fresh(a)
    if open_error != ok { ret 20i32 }
    var c = c0
    let ms = all()
    var buf: [8]migrate.Entry = zero
    let (n, up_error) = migrate.up(&c, .Sqlite, ms[0..], buf[0..], 0i64, 100i64)
    if up_error != ok || n != 3usize { ret 21i32 }
    if scalar(&c, "SELECT count(*) FROM users") != 2i64 { ret 22i32 }
    if scalar(&c, "SELECT count(*) FROM sqlite_master WHERE name = 'users_name'") != 1i64 { ret 23i32 }
    if scalar(&c, "SELECT count(*) FROM schema_migrations WHERE dirty = 0") != 3i64 { ret 24i32 }
    if scalar(&c, "SELECT applied_at FROM schema_migrations WHERE version = 2") != 100i64 { ret 25i32 }
    let (again, again_error) = migrate.up(&c, .Sqlite, ms[0..], buf[0..], 0i64, 200i64)
    if again_error != ok || again != 0usize { ret 26i32 }
    let (reverted, down_error) = migrate.down(&c, .Sqlite, ms[0..], buf[0..], 1usize)
    if down_error != ok || reverted != 1usize { ret 27i32 }
    if scalar(&c, "SELECT count(*) FROM sqlite_master WHERE name = 'users_name'") != 0i64 { ret 28i32 }
    if scalar(&c, "SELECT count(*) FROM schema_migrations") != 2i64 { ret 29i32 }
    let (rest, rest_error) = migrate.down(&c, .Sqlite, ms[0..], buf[0..], 10usize)
    if rest_error != ok || rest != 2usize { ret 30i32 }
    if scalar(&c, "SELECT count(*) FROM sqlite_master WHERE name = 'users'") != 0i64 { ret 31i32 }
    let (back, back_error) = migrate.up(&c, .Sqlite, ms[0..], buf[0..], 0i64, 300i64)
    if back_error != ok || back != 3usize { ret 32i32 }
    var status: [8]migrate.Entry = zero
    let (m, status_error) = migrate.status(&c, .Sqlite, status[0..])
    if status_error != ok || m != 3usize || status[2].version != 3i64 { ret 33i32 }
    var tiny: [2]migrate.Entry = zero
    let (cut, tiny_error) = migrate.status(&c, .Sqlite, tiny[0..])
    if tiny_error != migrate.TooSmall || cut != 2usize { ret 34i32 }
    if db.close(&c) != ok { ret 35i32 }
    ret 0i32
}

fn checks_limit(a: *mem.Arena) -> i32 {
    let (c0, open_error) = fresh(a)
    if open_error != ok { ret 40i32 }
    var c = c0
    let ms = all()
    var buf: [8]migrate.Entry = zero
    let (n, up_error) = migrate.up(&c, .Sqlite, ms[0..], buf[0..], 2i64, 1i64)
    if up_error != ok || n != 2usize { ret 41i32 }
    if scalar(&c, "SELECT count(*) FROM sqlite_master WHERE name = 'users_name'") != 0i64 { ret 42i32 }
    let (rest, rest_error) = migrate.up(&c, .Sqlite, ms[0..], buf[0..], 0i64, 2i64)
    if rest_error != ok || rest != 1usize { ret 43i32 }
    if scalar(&c, "SELECT count(*) FROM sqlite_master WHERE name = 'users_name'") != 1i64 { ret 44i32 }
    ret 0i32
}

fn checks_refusals(a: *mem.Arena) -> i32 {
    let (c0, open_error) = fresh(a)
    if open_error != ok { ret 50i32 }
    var c = c0
    let ms = all()
    var buf: [8]migrate.Entry = zero
    let (n, up_error) = migrate.up(&c, .Sqlite, ms[0..], buf[0..], 0i64, 1i64)
    if up_error != ok || n != 3usize { ret 51i32 }
    // Changed text of an applied migration.
    var edited = all()
    edited[1].up = "INSERT INTO users (id, name) VALUES (1, 'eve')"
    let (e1, e1_error) = migrate.up(&c, .Sqlite, edited[0..], buf[0..], 0i64, 2i64)
    if e1_error != migrate.Checksum || e1 != 0usize { ret 52i32 }
    let (e2, e2_error) = migrate.down(&c, .Sqlite, edited[0..], buf[0..], 1usize)
    if e2_error != migrate.Checksum || e2 != 0usize { ret 53i32 }
    if scalar(&c, "SELECT count(*) FROM schema_migrations") != 3i64 { ret 54i32 }
    // An applied version no longer supplied.
    var kept: [2]migrate.Migration = zero
    kept[0] = ms[0]
    kept[1] = ms[2]
    let (e3, e3_error) = migrate.up(&c, .Sqlite, kept[0..], buf[0..], 0i64, 3i64)
    if e3_error != migrate.Missing || e3 != 0usize { ret 55i32 }
    // An unapplied version below the newest applied one.
    let (d0, open2_error) = fresh(a)
    if open2_error != ok { ret 56i32 }
    var c2 = d0
    let (n2, up2_error) = migrate.up(&c2, .Sqlite, kept[0..], buf[0..], 0i64, 1i64)
    if up2_error != ok || n2 != 2usize { ret 57i32 }
    let (e4, e4_error) = migrate.up(&c2, .Sqlite, ms[0..], buf[0..], 0i64, 2i64)
    if e4_error != migrate.Order || e4 != 0usize { ret 58i32 }
    if db.close(&c2) != ok || db.close(&c) != ok { ret 59i32 }
    ret 0i32
}

fn checks_failure(a: *mem.Arena) -> i32 {
    let (c0, open_error) = fresh(a)
    if open_error != ok { ret 60i32 }
    var c = c0
    var ms = all()
    ms[1].up = "CREATE TABL oops"
    var buf: [8]migrate.Entry = zero
    let (n, up_error) = migrate.up(&c, .Sqlite, ms[0..], buf[0..], 0i64, 1i64)
    if up_error != migrate.Failed || n != 1usize { ret 61i32 }
    if scalar(&c, "SELECT dirty FROM schema_migrations WHERE version = 2") != 1i64 { ret 62i32 }
    if scalar(&c, "SELECT count(*) FROM sqlite_master WHERE name = 'users_name'") != 0i64 { ret 63i32 }
    // Locked: nothing runs, whatever the migrations say.
    var fixed = all()
    let (n2, locked_error) = migrate.up(&c, .Sqlite, fixed[0..], buf[0..], 0i64, 2i64)
    if locked_error != migrate.Dirty || n2 != 0usize { ret 64i32 }
    let (n3, locked_down) = migrate.down(&c, .Sqlite, fixed[0..], buf[0..], 1usize)
    if locked_down != migrate.Dirty || n3 != 0usize { ret 65i32 }
    if migrate.unlock(&c, .Sqlite, 2i64) != ok { ret 66i32 }
    let (n4, fixed_error) = migrate.up(&c, .Sqlite, fixed[0..], buf[0..], 0i64, 3i64)
    if fixed_error != ok || n4 != 2usize { ret 67i32 }
    if scalar(&c, "SELECT count(*) FROM users") != 2i64 { ret 68i32 }
    if db.close(&c) != ok { ret 69i32 }
    ret 0i32
}

fn checks_atomic(a: *mem.Arena) -> i32 {
    let (c0, open_error) = fresh(a)
    if open_error != ok { ret 70i32 }
    var c = c0
    var ms: [2]migrate.Migration = zero
    ms[0] = migrate.Migration { version: 1i64, name: "twice", up: "CREATE TABLE t1 (a); CREATE TABLE t1 (a)", down: "DROP TABLE t1" }
    ms[1] = migrate.Migration { version: 2i64, name: "fine", up: "CREATE TABLE t2 (a)", down: "" }
    var buf: [4]migrate.Entry = zero
    let (n, up_error) = migrate.up(&c, .Sqlite, ms[0..], buf[0..], 0i64, 1i64)
    if up_error != migrate.Failed || n != 0usize { ret 71i32 }
    // The transaction rolled back whole: the first CREATE left nothing behind.
    if scalar(&c, "SELECT count(*) FROM sqlite_master WHERE name = 't1'") != 0i64 { ret 72i32 }
    if migrate.unlock(&c, .Sqlite, 1i64) != ok { ret 73i32 }
    var ok_ms: [2]migrate.Migration = zero
    ok_ms[0] = migrate.Migration { version: 1i64, name: "once", up: "CREATE TABLE t1 (a)", down: "DROP TABLE t1" }
    ok_ms[1] = ms[1]
    let (n2, up2_error) = migrate.up(&c, .Sqlite, ok_ms[0..], buf[0..], 0i64, 2i64)
    if up2_error != ok || n2 != 2usize { ret 74i32 }
    // Version 2 has no `down`: the whole call is refused before anything changes.
    let (n3, down_error) = migrate.down(&c, .Sqlite, ok_ms[0..], buf[0..], 2usize)
    if down_error != migrate.Irreversible || n3 != 0usize { ret 75i32 }
    if scalar(&c, "SELECT count(*) FROM schema_migrations WHERE dirty = 0") != 2i64 { ret 76i32 }
    if db.close(&c) != ok { ret 77i32 }
    ret 0i32
}

fn checks_dialect() -> i32 {
    if !str.eq(migrate.lock_sql(.Sqlite), "INSERT INTO schema_migrations (version, name, checksum, dirty, applied_at) VALUES (?, ?, ?, 1, ?)") { ret 80i32 }
    if !str.eq(migrate.lock_sql(.Mysql), migrate.lock_sql(.Sqlite)) { ret 81i32 }
    if !str.eq(migrate.lock_sql(.Postgres), "INSERT INTO schema_migrations (version, name, checksum, dirty, applied_at) VALUES ($1, $2, $3, 1, $4)") { ret 82i32 }
    if !str.eq(migrate.remove_sql(.Postgres), "DELETE FROM schema_migrations WHERE version = $1") { ret 83i32 }
    if str.eq(migrate.journal_ddl(.Postgres), migrate.journal_ddl(.Sqlite)) { ret 84i32 }
    if str.eq(migrate.journal_ddl(.Mysql), migrate.journal_ddl(.Postgres)) { ret 85i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    if sqlite.version() < 3007014i32 { os.exit(1i32) }
    var code = checks_pure()
    if code == 0i32 { code = checks_updown(a) }
    if code == 0i32 { code = checks_limit(a) }
    if code == 0i32 { code = checks_refusals(a) }
    if code == 0i32 { code = checks_failure(a) }
    if code == 0i32 { code = checks_atomic(a) }
    if code == 0i32 { code = checks_dialect() }
    if code != 0i32 { os.exit(code) }
    ret ok
}
