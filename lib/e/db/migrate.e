// A versioned SQL migration runner over `e.db`, after goose and golang-migrate. A
// migration is a version (strictly ascending, above zero), a name, and `up` and
// `down` SQL. The journal is the table `schema_migrations(version, name, checksum,
// dirty, applied_at)`, created with the dialect's own column types, and a statement
// is written with the dialect's own placeholder (`?`, or `$n` for Postgres).
//
// `up` locks before it runs: the journal row is inserted with `dirty = 1` and
// committed, the migration's SQL then runs in a transaction together with the
// `dirty = 0` update, and a failure rolls the transaction back and leaves the dirty
// row. Every later `up`, `down` and `verify` refuses a dirty journal with `Dirty`
// until the operator has undone whatever the failure left and calls `unlock`. A
// database without transactional DDL (MySQL) may keep part of a failed migration;
// the lock is the same. `down` locks the same way and deletes the row on success.
// The checksum is FNV-1a 64 of the `up` text: an applied migration whose text has
// since changed is refused with `Checksum`, one that is no longer supplied with
// `Missing`, and an unapplied version below the newest applied one with `Order`.
//
// A migration's SQL goes to the driver as one `execute`, so a driver that takes one
// statement per call (as most server drivers do) takes one statement per migration.
// The runner holds no clock: `now` is the caller's applied-at stamp.

use e.algo.hash
use e.db
use e.mem

type Dialect = enum u8 { Sqlite, Postgres, Mysql }
type Migration = struct { version: i64, name: str, up: str, down: str }
// One journal row; `checksum` is the value `checksum` computed when it was applied.
type Entry = struct { version: i64, checksum: i64, dirty: bool }
error Order
error Checksum
error Missing
error Dirty
error Failed
error Irreversible
error TooSmall

fn checksum(m: Migration) -> i64 { ret mem.bitcast[i64](hash.fnv1a64(m.up)) }

fn journal_ddl(d: Dialect) -> str {
    if d == .Postgres { ret "CREATE TABLE IF NOT EXISTS schema_migrations (version BIGINT PRIMARY KEY, name TEXT NOT NULL, checksum BIGINT NOT NULL, dirty SMALLINT NOT NULL, applied_at BIGINT NOT NULL)" }
    if d == .Mysql { ret "CREATE TABLE IF NOT EXISTS schema_migrations (version BIGINT PRIMARY KEY, name VARCHAR(255) NOT NULL, checksum BIGINT NOT NULL, dirty TINYINT NOT NULL, applied_at BIGINT NOT NULL)" }
    ret "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, checksum INTEGER NOT NULL, dirty INTEGER NOT NULL, applied_at INTEGER NOT NULL)"
}

fn lock_sql(d: Dialect) -> str {
    if d == .Postgres { ret "INSERT INTO schema_migrations (version, name, checksum, dirty, applied_at) VALUES ($1, $2, $3, 1, $4)" }
    ret "INSERT INTO schema_migrations (version, name, checksum, dirty, applied_at) VALUES (?, ?, ?, 1, ?)"
}

fn clean_sql(d: Dialect) -> str {
    if d == .Postgres { ret "UPDATE schema_migrations SET dirty = 0 WHERE version = $1" }
    ret "UPDATE schema_migrations SET dirty = 0 WHERE version = ?"
}

fn dirty_sql(d: Dialect) -> str {
    if d == .Postgres { ret "UPDATE schema_migrations SET dirty = 1 WHERE version = $1" }
    ret "UPDATE schema_migrations SET dirty = 1 WHERE version = ?"
}

fn remove_sql(d: Dialect) -> str {
    if d == .Postgres { ret "DELETE FROM schema_migrations WHERE version = $1" }
    ret "DELETE FROM schema_migrations WHERE version = ?"
}

fn int_of(v: db.Value) -> i64 {
    switch v {
    case .I64 as n:
        ret n
    case .U64 as n:
        ret mem.bitcast[i64](n)
    case .Bool as b:
        if b { ret 1i64 }
        ret 0i64
    default:
        ret 0i64
    }
}

// The journal table, created when absent.
fn ensure_journal(c: *db.Connection, d: Dialect) -> err {
    let (changed, create_error) = db.execute(c, journal_ddl(d), zero)
    if create_error != ok { ret create_error }
    ret ok
}

// The journal rows in version order into `out`; `TooSmall` when there are more.
fn read_journal(c: *db.Connection, out: []Entry) -> (usize, err) {
    let (rows0, query_error) = db.query(c, "SELECT version, checksum, dirty FROM schema_migrations ORDER BY version", zero)
    if query_error != ok { ret (0usize, query_error) }
    var rows = rows0
    var row: [3]db.Value = zero
    var n = 0usize
    var failure: err = ok
    while true {
        let (more, next_error) = db.reader_next_err(&rows, row[0..])
        if next_error != ok {
            failure = next_error
            break
        }
        if !more { break }
        if n >= out.len {
            failure = TooSmall
            break
        }
        out[n] = Entry { version: int_of(row[0]), checksum: int_of(row[1]), dirty: int_of(row[2]) != 0i64 }
        n += 1usize
    }
    let close_error = db.close_rows(&rows)
    if failure != ok { ret (n, failure) }
    if close_error != ok { ret (n, close_error) }
    ret (n, ok)
}

// The supplied list is strictly ascending with every version above zero.
fn validate(ms: []const Migration) -> err {
    var i = 0usize
    var previous = 0i64
    while i < ms.len {
        if ms[i].version <= previous { ret Order }
        previous = ms[i].version
        i += 1usize
    }
    ret ok
}

// The journal agrees with the supplied migrations: nothing dirty, every applied
// version still supplied with its text unchanged, and no unapplied version below
// the newest applied one.
fn verify(ms: []const Migration, entries: []const Entry) -> err {
    let order_error = validate(ms)
    if order_error != ok { ret order_error }
    var newest = 0i64
    var i = 0usize
    while i < entries.len {
        if entries[i].dirty { ret Dirty }
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        var found = false
        var j = 0usize
        while j < ms.len {
            if ms[j].version == entries[i].version {
                found = true
                if checksum(ms[j]) != entries[i].checksum { ret Checksum }
            }
            j += 1usize
        }
        if !found { ret Missing }
        if entries[i].version > newest { newest = entries[i].version }
        i += 1usize
    }
    var m = 0usize
    while m < ms.len {
        if ms[m].version < newest && !applied(entries, ms[m].version) { ret Order }
        m += 1usize
    }
    ret ok
}

fn applied(entries: []const Entry, version: i64) -> bool {
    var i = 0usize
    while i < entries.len {
        if entries[i].version == version { ret true }
        i += 1usize
    }
    ret false
}

// The journal as it stands, without judging it.
fn status(c: *db.Connection, d: Dialect, out: []Entry) -> (usize, err) {
    let ensure_error = ensure_journal(c, d)
    if ensure_error != ok { ret (0usize, ensure_error) }
    let (n, read_error) = read_journal(c, out)
    ret (n, read_error)
}

fn one_version(c: *db.Connection, sql: str, version: i64) -> err {
    var p: [1]db.Parameter = zero
    p[0] = db.Parameter { name: "", value: db.Value{ I64: version } }
    let (changed, run_error) = db.execute(c, sql, p[0..])
    ret run_error
}

fn lock_up(c: *db.Connection, d: Dialect, m: Migration, now: i64) -> err {
    var p: [4]db.Parameter = zero
    p[0] = db.Parameter { name: "", value: db.Value{ I64: m.version } }
    p[1] = db.Parameter { name: "", value: db.Value{ Text: m.name } }
    p[2] = db.Parameter { name: "", value: db.Value{ I64: checksum(m) } }
    p[3] = db.Parameter { name: "", value: db.Value{ I64: now } }
    let (changed, run_error) = db.execute(c, lock_sql(d), p[0..])
    ret run_error
}

// Run `body` and then `finish` (with `version` bound) in one transaction.
fn in_transaction(c: *db.Connection, body: str, finish: str, version: i64) -> err {
    let (tx0, begin_error) = db.begin(c)
    if begin_error != ok { ret begin_error }
    var tx = tx0
    let (changed, body_error) = db.execute_transaction(&tx, body, zero)
    if body_error != ok {
        let rolled = db.rollback(&tx)
        ret body_error
    }
    var p: [1]db.Parameter = zero
    p[0] = db.Parameter { name: "", value: db.Value{ I64: version } }
    let (finished, finish_error) = db.execute_transaction(&tx, finish, p[0..])
    if finish_error != ok {
        let rolled = db.rollback(&tx)
        ret finish_error
    }
    ret db.commit(&tx)
}

// Apply every pending migration whose version is at most `limit_version` (zero for
// all), in order; answers how many were applied. `buf` holds the journal rows.
// A failed migration answers `Failed` and leaves its row dirty.
fn up(c: *db.Connection, d: Dialect, ms: []const Migration, buf: []Entry, limit_version: i64, now: i64) -> (usize, err) {
    let ensure_error = ensure_journal(c, d)
    if ensure_error != ok { ret (0usize, ensure_error) }
    let (n, read_error) = read_journal(c, buf)
    if read_error != ok { ret (0usize, read_error) }
    let verify_error = verify(ms, buf[0..n])
    if verify_error != ok { ret (0usize, verify_error) }
    var newest = 0i64
    if n > 0usize { newest = buf[n - 1usize].version }
    var count = 0usize
    var i = 0usize
    while i < ms.len {
        let m = ms[i]
        i += 1usize
        if m.version <= newest { continue }
        if limit_version != 0i64 && m.version > limit_version { break }
        if lock_up(c, d, m, now) != ok { ret (count, Failed) }
        if in_transaction(c, m.up, clean_sql(d), m.version) != ok { ret (count, Failed) }
        count += 1usize
    }
    ret (count, ok)
}

// Revert the newest `steps` applied migrations, newest first; answers how many. A
// migration with no `down` text refuses the whole call before anything changes.
fn down(c: *db.Connection, d: Dialect, ms: []const Migration, buf: []Entry, steps: usize) -> (usize, err) {
    let ensure_error = ensure_journal(c, d)
    if ensure_error != ok { ret (0usize, ensure_error) }
    let (n, read_error) = read_journal(c, buf)
    if read_error != ok { ret (0usize, read_error) }
    let verify_error = verify(ms, buf[0..n])
    if verify_error != ok { ret (0usize, verify_error) }
    var take = steps
    if take > n { take = n }
    var k = 0usize
    while k < take {
        let version = buf[n - 1usize - k].version
        var j = 0usize
        while j < ms.len {
            if ms[j].version == version && ms[j].down.len == 0usize { ret (0usize, Irreversible) }
            j += 1usize
        }
        k += 1usize
    }
    var count = 0usize
    k = 0usize
    while k < take {
        let version = buf[n - 1usize - k].version
        k += 1usize
        var j = 0usize
        while j < ms.len {
            if ms[j].version == version {
                if one_version(c, dirty_sql(d), version) != ok { ret (count, Failed) }
                if in_transaction(c, ms[j].down, remove_sql(d), version) != ok { ret (count, Failed) }
                count += 1usize
            }
            j += 1usize
        }
    }
    ret (count, ok)
}

// Forget a dirty row once the operator has undone what the failure left: the
// version is pending again and `up` runs it afresh.
fn unlock(c: *db.Connection, d: Dialect, version: i64) -> err {
    ret one_version(c, remove_sql(d), version)
}
