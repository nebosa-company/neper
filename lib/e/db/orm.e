// A small object-relational mapper over `e.db`, in the shape of gorm and Dapper: a
// struct is a row, its fields are columns in declaration order (read through `e.meta`
// at compile time, so no runtime type information exists), and its first field must
// be an integer named `id`, the primary key. `str` fields are TEXT, integers INTEGER
// (BIGINT off SQLite), floats REAL, bools a one-byte integer or BOOLEAN.
//
// A `Session` is a connection, the arena every statement and every row string is
// built in, the dialect (placeholders `?` or `$n`) and a count of statements issued,
// so a test can tell one preloading query from N+1. Nothing is reset: the caller
// frames each unit of work with `mem.mark`/`mem.reset` as it would any arena.
//
// `insert` with `id == 0` leaves the key to the database and writes the generated one
// back into the row; `update` and `delete` act on the row's `id`. The eight `Hooks`
// run in gorm's order: create is before_save, before_create, INSERT, after_create,
// after_save; update the same with update; delete is before_delete, DELETE,
// after_delete. A hook that answers an error stops the operation (a before hook
// before any SQL) and the error is the caller's. `belongs_to` follows a foreign key
// field to its parent; `has_many` preloads: one `WHERE fk IN (...)` query for all the
// parents given, ordered by the key, then each parent's children are a `Span` of the
// output.
//
// A field type other than integer, float, bool or `str` is `Invalid`; a struct whose
// first field is not an integer `id` is `NoKey`.

use e.db
use e.db.migrate as migrate
use e.mem
use e.meta
use e.str

type Session = struct { c: *db.Connection, a: *mem.Arena, d: migrate.Dialect, queries: u64 }
type Hooks[T: type] = struct { before_save: fn(*T) -> err, after_save: fn(*T) -> err, before_create: fn(*T) -> err, after_create: fn(*T) -> err, before_update: fn(*T) -> err, after_update: fn(*T) -> err, before_delete: fn(*T) -> err, after_delete: fn(*T) -> err }
// A parent's children are `out[start..start + len]` of the `has_many` output.
type Span = struct { start: usize, len: usize }
error Invalid
error NoKey
error NotFound
error TooSmall

fn session(c: *db.Connection, a: *mem.Arena, d: migrate.Dialect) -> Session {
    ret Session { c: c, a: a, d: d, queries: 0u64 }
}

// A hook that does nothing, for the events a caller does not care about.
fn hook_ok[T: type](row: *T) -> err { ret ok }

fn type_sql(d: migrate.Dialect, kind: meta.TypeKind) -> str {
    if kind == .Slice { ret "TEXT" }
    if kind == .Float {
        if d == .Postgres { ret "DOUBLE PRECISION" }
        if d == .Mysql { ret "DOUBLE" }
        ret "REAL"
    }
    if kind == .Bool {
        if d == .Postgres { ret "BOOLEAN" }
        if d == .Mysql { ret "TINYINT(1)" }
        ret "INTEGER"
    }
    if d == .Sqlite { ret "INTEGER" }
    ret "BIGINT"
}

fn push_placeholder(b: *str.Builder, d: migrate.Dialect, n: usize) -> err {
    if d == .Postgres {
        try str.push(b, "$")
        try str.push_usize(b, n)
        ret ok
    }
    ret str.push(b, "?")
}

fn to_value[F: type](slot: F) -> db.Value {
    var v: db.Value = zero
    if meta.kind[F]() == .Slice {
        v = db.Value{ Text: slot }
    } else {
    if meta.kind[F]() == .Bool {
        v = db.Value{ Bool: slot }
    } else {
    if meta.kind[F]() == .Int {
        if slot < 0 {
            v = db.Value{ I64: i64(slot) }
        } else {
            v = db.Value{ U64: u64(slot) }
        }
    } else {
    if meta.kind[F]() == .Float {
        v = db.Value{ F64: f64(slot) }
    }
    }
    }
    }
    ret v
}

fn copy_text(a: *mem.Arena, text: str) -> (str, err) {
    if text.len == 0usize { ret ("", ok) }
    let (buffer, allocation_error) = mem.alloc[u8](a, text.len)
    if allocation_error != ok { ret ("", allocation_error) }
    mem.copy[u8](buffer, text)
    ret (buffer, ok)
}

// One cell as an `F`; a cell of the wrong storage class is `Invalid`, NULL is zero.
fn from_value[F: type](a: *mem.Arena, v: db.Value) -> (F, err) {
    var slot: F = zero
    var failure: err = ok
    if meta.kind[F]() == .Slice {
        switch v {
        case .Text as text:
            let (kept, copy_error) = copy_text(a, text)
            if copy_error != ok { failure = copy_error } else { slot = kept }
        case .Null:
            failure = ok
        default:
            failure = Invalid
        }
    } else {
    if meta.kind[F]() == .Bool {
        switch v {
        case .Bool as b:
            slot = b
        case .I64 as n:
            slot = n != 0i64
        case .Null:
            failure = ok
        default:
            failure = Invalid
        }
    } else {
    if meta.kind[F]() == .Int {
        switch v {
        case .I64 as n:
            slot = F(n)
        case .U64 as n:
            slot = F(n)
        case .Bool as b:
            if b { slot = F(1u8) }
        case .Null:
            failure = ok
        default:
            failure = Invalid
        }
    } else {
    if meta.kind[F]() == .Float {
        switch v {
        case .F64 as x:
            slot = F(x)
        case .I64 as n:
            slot = F(n)
        case .Null:
            failure = ok
        default:
            failure = Invalid
        }
    } else {
        failure = Invalid
    }
    }
    }
    }
    ret (slot, failure)
}

// The leading `id` column, as an integer. `NoKey` when the struct has none.
fn key_of[T: type](row: *const T) -> (i64, err) {
    var key = 0i64
    var seen = false
    var good = false
    for f in meta.fields[T]() {
        if !seen {
            seen = true
            if meta.kind[f.ty]() == .Int {
                if str.eq(f.name, "id") {
                    var slot: f.ty = zero
                    slot = meta.get[f, T](row)
                    key = i64(slot)
                    good = true
                }
            }
        }
    }
    if !good { ret (0i64, NoKey) }
    ret (key, ok)
}

fn set_key[T: type](row: *T, key: i64) -> err {
    var seen = false
    var good = false
    for f in meta.fields[T]() {
        if !seen {
            seen = true
            if meta.kind[f.ty]() == .Int {
                if str.eq(f.name, "id") {
                    var slot: f.ty = zero
                    slot = f.ty(key)
                    meta.set[f, T](row, slot)
                    good = true
                }
            }
        }
    }
    if !good { ret NoKey }
    ret ok
}

// The integer field called `name`, wherever it sits.
fn int_field[T: type](row: *const T, name: str) -> (i64, bool) {
    var key = 0i64
    var found = false
    for f in meta.fields[T]() {
        if meta.kind[f.ty]() == .Int {
            if str.eq(f.name, name) {
                var slot: f.ty = zero
                slot = meta.get[f, T](row)
                key = i64(slot)
                found = true
            }
        }
    }
    ret (key, found)
}

fn field_count[T: type]() -> usize {
    var n = 0usize
    for f in meta.fields[T]() { n += 1usize }
    ret n
}

// The column list `id, name, ...` in field order.
fn push_columns[T: type](b: *str.Builder) -> err {
    var first = true
    for f in meta.fields[T]() {
        if !first { try str.push(b, ", ") }
        try str.push(b, f.name)
        first = false
    }
    ret ok
}

fn run(s: *Session, sql: str, params: []const db.Parameter) -> (u64, err) {
    s.queries += 1u64
    let (n, run_error) = db.execute(s.c, sql, params)
    ret (n, run_error)
}

// The struct has a leading integer `id` and only column-shaped fields.
fn check_key[T: type]() -> err {
    var seen = false
    var good = false
    var plain = true
    for f in meta.fields[T]() {
        if !seen {
            seen = true
            if str.eq(f.name, "id") && meta.kind[f.ty]() == .Int { good = true }
        }
        if meta.kind[f.ty]() != .Int && meta.kind[f.ty]() != .Float && meta.kind[f.ty]() != .Bool && meta.kind[f.ty]() != .Slice { plain = false }
    }
    if !good { ret NoKey }
    if !plain { ret Invalid }
    ret ok
}

// `CREATE TABLE IF NOT EXISTS` for `T`, the auto-migrate half: columns, types and the
// primary key, derived from the struct. Answers the statement (built in the arena).
fn create_sql[T: type](s: *Session, table: str) -> (str, err) {
    try check_key[T]()
    let (builder0, builder_error) = str.builder(s.a, 256usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = builder0
    try str.push(&b, "CREATE TABLE IF NOT EXISTS ")
    try str.push(&b, table)
    try str.push(&b, " (")
    var first = true
    for f in meta.fields[T]() {
        if !first { try str.push(&b, ", ") }
        try str.push(&b, f.name)
        try str.push(&b, " ")
        try str.push(&b, type_sql(s.d, meta.kind[f.ty]()))
        if first { try str.push(&b, " PRIMARY KEY") } else { try str.push(&b, " NOT NULL") }
        first = false
    }
    try str.push(&b, ")")
    ret (str.done(&b), ok)
}

fn create_table[T: type](s: *Session, table: str) -> err {
    let (sql, sql_error) = create_sql[T](s, table)
    if sql_error != ok { ret sql_error }
    let (changed, run_error) = run(s, sql, zero)
    ret run_error
}

fn last_id(s: *Session) -> (i64, err) {
    var sql = "SELECT last_insert_rowid()"
    if s.d == .Mysql { sql = "SELECT LAST_INSERT_ID()" }
    s.queries += 1u64
    let (rows0, query_error) = db.query(s.c, sql, zero)
    if query_error != ok { ret (0i64, query_error) }
    var rows = rows0
    var cell: [1]db.Value = zero
    let (more, next_error) = db.reader_next_err(&rows, cell[0..])
    let close_error = db.close_rows(&rows)
    if next_error != ok { ret (0i64, next_error) }
    if !more { ret (0i64, NotFound) }
    var id = 0i64
    switch cell[0] {
    case .I64 as n:
        id = n
    default:
        id = 0i64
    }
    ret (id, close_error)
}

// INSERT the row; `id == 0` is generated by the database and written back. Hooks run
// as documented above.
fn insert[T: type](s: *Session, table: str, row: *T, h: *const Hooks[T]) -> err {
    try check_key[T]()
    let (key, key_error) = key_of[T](row)
    if key_error != ok { ret key_error }
    try h.before_save(row)
    try h.before_create(row)
    let auto = key == 0i64
    let (builder0, builder_error) = str.builder(s.a, 256usize)
    if builder_error != ok { ret builder_error }
    var b = builder0
    try str.push(&b, "INSERT INTO ")
    try str.push(&b, table)
    try str.push(&b, " (")
    var first = true
    var skipped = false
    for f in meta.fields[T]() {
        if auto && !skipped {
            skipped = true
        } else {
            if !first { try str.push(&b, ", ") }
            try str.push(&b, f.name)
            first = false
        }
    }
    try str.push(&b, ") VALUES (")
    let total = field_count[T]()
    var wanted = total
    if auto { wanted = total - 1usize }
    var k = 0usize
    while k < wanted {
        if k != 0usize { try str.push(&b, ", ") }
        try push_placeholder(&b, s.d, k + 1usize)
        k += 1usize
    }
    try str.push(&b, ")")
    let sql = str.done(&b)
    let (params, alloc_error) = mem.alloc[db.Parameter](s.a, wanted)
    if alloc_error != ok { ret alloc_error }
    var at = 0usize
    var passed = false
    for f in meta.fields[T]() {
        if auto && !passed {
            passed = true
        } else {
            var slot: f.ty = zero
            slot = meta.get[f, T](row)
            params[at] = db.Parameter { name: "", value: to_value[f.ty](slot) }
            at += 1usize
        }
    }
    let (changed, run_error) = run(s, sql, params)
    if run_error != ok { ret run_error }
    if auto {
        let (generated, id_error) = last_id(s)
        if id_error != ok { ret id_error }
        try set_key[T](row, generated)
    }
    try h.after_create(row)
    try h.after_save(row)
    ret ok
}

// UPDATE every column but `id` of the row with that `id`; `NotFound` when no row has it.
fn update[T: type](s: *Session, table: str, row: *T, h: *const Hooks[T]) -> err {
    let (key, key_error) = key_of[T](row)
    if key_error != ok { ret key_error }
    try h.before_save(row)
    try h.before_update(row)
    let (builder0, builder_error) = str.builder(s.a, 256usize)
    if builder_error != ok { ret builder_error }
    var b = builder0
    try str.push(&b, "UPDATE ")
    try str.push(&b, table)
    try str.push(&b, " SET ")
    var at = 0usize
    var passed = false
    for f in meta.fields[T]() {
        if !passed {
            passed = true
        } else {
            if at != 0usize { try str.push(&b, ", ") }
            try str.push(&b, f.name)
            try str.push(&b, " = ")
            try push_placeholder(&b, s.d, at + 1usize)
            at += 1usize
        }
    }
    try str.push(&b, " WHERE id = ")
    try push_placeholder(&b, s.d, at + 1usize)
    let sql = str.done(&b)
    let (params, alloc_error) = mem.alloc[db.Parameter](s.a, at + 1usize)
    if alloc_error != ok { ret alloc_error }
    var fill = 0usize
    var skip = false
    for f in meta.fields[T]() {
        if !skip {
            skip = true
        } else {
            var slot: f.ty = zero
            slot = meta.get[f, T](row)
            params[fill] = db.Parameter { name: "", value: to_value[f.ty](slot) }
            fill += 1usize
        }
    }
    params[fill] = db.Parameter { name: "", value: db.Value{ I64: key } }
    let (changed, run_error) = run(s, sql, params)
    if run_error != ok { ret run_error }
    if changed == 0u64 { ret NotFound }
    try h.after_update(row)
    try h.after_save(row)
    ret ok
}

// DELETE the row with this `id`; `NotFound` when none has it.
fn delete[T: type](s: *Session, table: str, row: *T, h: *const Hooks[T]) -> err {
    let (key, key_error) = key_of[T](row)
    if key_error != ok { ret key_error }
    try h.before_delete(row)
    let (builder0, builder_error) = str.builder(s.a, 64usize)
    if builder_error != ok { ret builder_error }
    var b = builder0
    try str.push(&b, "DELETE FROM ")
    try str.push(&b, table)
    try str.push(&b, " WHERE id = ")
    try push_placeholder(&b, s.d, 1usize)
    let sql = str.done(&b)
    var p: [1]db.Parameter = zero
    p[0] = db.Parameter { name: "", value: db.Value{ I64: key } }
    let (changed, run_error) = run(s, sql, p[0..])
    if run_error != ok { ret run_error }
    if changed == 0u64 { ret NotFound }
    try h.after_delete(row)
    ret ok
}

// Read the next row of `rows` into `out`; false when the reader is exhausted.
fn read_row[T: type](s: *Session, rows: *db.Rows, cells: []db.Value, out: *T) -> (bool, err) {
    let (more, next_error) = db.reader_next_err(rows, cells)
    if next_error != ok { ret (false, next_error) }
    if !more { ret (false, ok) }
    var column = 0usize
    for f in meta.fields[T]() {
        let (value, value_error) = from_value[f.ty](s.a, cells[column])
        if value_error != ok { ret (false, value_error) }
        meta.set[f, T](out, value)
        column += 1usize
    }
    ret (true, ok)
}

// `SELECT cols FROM table [WHERE where_sql]`: `where_sql` is the caller's condition
// (with `?`/`$n` placeholders for `params`, or empty for every row), at most
// `out.len` rows into `out`; `TooSmall` when the result is longer. `order_sql`
// is a bare `ORDER BY ...` clause or empty.
fn select[T: type](s: *Session, table: str, where_sql: str, order_sql: str, params: []const db.Parameter, out: []T) -> (usize, err) {
    let kept = check_key[T]()
    if kept != ok { ret (0usize, kept) }
    let (builder0, builder_error) = str.builder(s.a, 256usize)
    if builder_error != ok { ret (0usize, builder_error) }
    var b = builder0
    try str.push(&b, "SELECT ")
    try push_columns[T](&b)
    try str.push(&b, " FROM ")
    try str.push(&b, table)
    if where_sql.len != 0usize {
        try str.push(&b, " WHERE ")
        try str.push(&b, where_sql)
    }
    if order_sql.len != 0usize {
        try str.push(&b, " ")
        try str.push(&b, order_sql)
    }
    let sql = str.done(&b)
    s.queries += 1u64
    let (rows0, query_error) = db.query(s.c, sql, params)
    if query_error != ok { ret (0usize, query_error) }
    var rows = rows0
    let (cells, alloc_error) = mem.alloc[db.Value](s.a, field_count[T]())
    if alloc_error != ok {
        let closed = db.close_rows(&rows)
        ret (0usize, alloc_error)
    }
    var n = 0usize
    var failure: err = ok
    while true {
        var row: T = zero
        let (more, row_error) = read_row[T](s, &rows, cells, &row)
        if row_error != ok {
            failure = row_error
            break
        }
        if !more { break }
        if n >= out.len {
            failure = TooSmall
            break
        }
        out[n] = row
        n += 1usize
    }
    let close_error = db.close_rows(&rows)
    if failure != ok { ret (n, failure) }
    if close_error != ok { ret (n, close_error) }
    ret (n, ok)
}

// The row with this `id`: false when there is none.
fn find[T: type](s: *Session, table: str, id: i64, out: *T) -> (bool, err) {
    var p: [1]db.Parameter = zero
    p[0] = db.Parameter { name: "", value: db.Value{ I64: id } }
    var holder: [1]T = zero
    var where_sql = "id = ?"
    if s.d == .Postgres { where_sql = "id = $1" }
    let (n, select_error) = select[T](s, table, where_sql, "", p[0..], holder[0..])
    if select_error != ok { ret (false, select_error) }
    if n == 0usize { ret (false, ok) }
    *out = holder[0]
    ret (true, ok)
}

// The parent a child's foreign-key field `fk` names: false when no such parent row.
// `NoKey` when `C` has no integer field called `fk`.
fn belongs_to[C: type, P: type](s: *Session, parent_table: str, child: *const C, fk: str, out: *P) -> (bool, err) {
    let (parent_id, found) = int_field[C](child, fk)
    if !found { ret (false, NoKey) }
    let (good, find_error) = find[P](s, parent_table, parent_id, out)
    ret (good, find_error)
}

// Preload the children of every parent in one query. `out` receives the children
// grouped by the parent's order in `parents` (parent `i`'s are `out[spans[i].start..]`
// for `spans[i].len`); `spans` has one entry per parent and `out` must hold them all
// (`TooSmall` otherwise). Answers the total children read. A parent with no children has a zero span.
fn has_many[P: type, C: type](s: *Session, child_table: str, fk: str, parents: []const P, out: []C, spans: []Span) -> (usize, err) {
    if spans.len < parents.len { ret (0usize, TooSmall) }
    if parents.len == 0usize { ret (0usize, ok) }
    let (builder0, builder_error) = str.builder(s.a, 128usize)
    if builder_error != ok { ret (0usize, builder_error) }
    var b = builder0
    try str.push(&b, fk)
    try str.push(&b, " IN (")
    var i = 0usize
    while i < parents.len {
        if i != 0usize { try str.push(&b, ", ") }
        try push_placeholder(&b, s.d, i + 1usize)
        i += 1usize
    }
    try str.push(&b, ")")
    let where_sql = str.done(&b)
    let (params, alloc_error) = mem.alloc[db.Parameter](s.a, parents.len)
    if alloc_error != ok { ret (0usize, alloc_error) }
    i = 0usize
    while i < parents.len {
        let (parent_key, key_error) = key_of[P](&parents[i])
        if key_error != ok { ret (0usize, key_error) }
        params[i] = db.Parameter { name: "", value: db.Value{ I64: parent_key } }
        i += 1usize
    }
    let (order0, order_error) = str.builder(s.a, 64usize)
    if order_error != ok { ret (0usize, order_error) }
    var ob = order0
    try str.push(&ob, "ORDER BY ")
    try str.push(&ob, fk)
    try str.push(&ob, ", id")
    let order_sql = str.done(&ob)
    let (scratch, scratch_error) = mem.alloc[C](s.a, out.len)
    if scratch_error != ok { ret (0usize, scratch_error) }
    let (n, select_error) = select[C](s, child_table, where_sql, order_sql, params, scratch)
    if select_error != ok { ret (n, select_error) }
    // `scratch` is ordered by (fk, id); lay each parent's run out in parent order.
    var written = 0usize
    i = 0usize
    while i < parents.len {
        let (parent_key, key_error) = key_of[P](&parents[i])
        if key_error != ok { ret (n, key_error) }
        spans[i] = Span { start: written, len: 0usize }
        var j = 0usize
        while j < n {
            let (child_key, found) = int_field[C](&scratch[j], fk)
            if !found { ret (n, NoKey) }
            if child_key == parent_key {
                if written >= out.len { ret (n, TooSmall) }
                out[written] = scratch[j]
                written += 1usize
                spans[i].len += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}
