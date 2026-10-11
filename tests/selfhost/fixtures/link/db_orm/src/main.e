// `e.db.orm` over `x.sqlite.sqlite` in memory. The generated DDL, the rows read back and
// the preload ordering are the ones scripts/gen_db_orm_test.py reaches replaying the same
// SQL through Python's sqlite3. Sections: DDL per dialect and the shape refusals, insert
// with generated and explicit keys, find and select round trips of every column kind,
// update and delete with NotFound, hook order and a vetoing hook, belongs-to, and a
// has-many preload that takes exactly one statement for any number of parents. Every
// check has its own exit code.
use e.os
use e.mem
use e.str
use e.db
use e.db.migrate as migrate
use e.db.orm as orm
use x.sqlite.sqlite

type User = struct { id: i64, name: str, age: i32, score: f64, active: bool }
type Post = struct { id: i64, user_id: i64, title: str, views: u32 }
type Keyless = struct { name: str }
type Inner = struct { x: i32 }
type Odd = struct { id: i64, inner: Inner }

error Veto

var trace: [64]u8 = zero
var trace_len: usize = 0usize

fn note(code: u8) {
    trace[trace_len] = code
    trace_len += 1usize
}

fn trace_is(want: str) -> bool {
    if trace_len != want.len { ret false }
    var i = 0usize
    while i < trace_len {
        if trace[i] != want[i] { ret false }
        i += 1usize
    }
    ret true
}

fn h_before_save(u: *User) -> err {
    note(49u8)
    ret ok
}
fn h_after_save(u: *User) -> err {
    note(50u8)
    ret ok
}
fn h_before_create(u: *User) -> err {
    note(51u8)
    ret ok
}
fn h_after_create(u: *User) -> err {
    note(52u8)
    ret ok
}
fn h_before_update(u: *User) -> err {
    note(53u8)
    ret ok
}
fn h_after_update(u: *User) -> err {
    note(54u8)
    ret ok
}
fn h_before_delete(u: *User) -> err {
    note(55u8)
    ret ok
}
fn h_after_delete(u: *User) -> err {
    note(56u8)
    ret ok
}
fn h_veto(u: *User) -> err {
    note(86u8)
    ret Veto
}

fn traced() -> orm.Hooks[User] {
    ret orm.Hooks[User] { before_save: h_before_save, after_save: h_after_save, before_create: h_before_create, after_create: h_after_create, before_update: h_before_update, after_update: h_after_update, before_delete: h_before_delete, after_delete: h_after_delete }
}

fn quiet_user() -> orm.Hooks[User] {
    ret orm.Hooks[User] { before_save: orm.hook_ok[User], after_save: orm.hook_ok[User], before_create: orm.hook_ok[User], after_create: orm.hook_ok[User], before_update: orm.hook_ok[User], after_update: orm.hook_ok[User], before_delete: orm.hook_ok[User], after_delete: orm.hook_ok[User] }
}

fn quiet_post() -> orm.Hooks[Post] {
    ret orm.Hooks[Post] { before_save: orm.hook_ok[Post], after_save: orm.hook_ok[Post], before_create: orm.hook_ok[Post], after_create: orm.hook_ok[Post], before_update: orm.hook_ok[Post], after_update: orm.hook_ok[Post], before_delete: orm.hook_ok[Post], after_delete: orm.hook_ok[Post] }
}

fn fresh(a: *mem.Arena) -> (db.Connection, err) {
    let (conn, open_error) = sqlite.open(a, ":memory:")
    ret (conn, open_error)
}

fn checks_ddl(a: *mem.Arena) -> i32 {
    let (c0, open_error) = fresh(a)
    if open_error != ok { ret 10i32 }
    var c = c0
    var s = orm.session(&c, a, .Sqlite)
    let (user_sql, user_error) = orm.create_sql[User](&s, "users")
    if user_error != ok { ret 11i32 }
    if !str.eq(user_sql, "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER NOT NULL, score REAL NOT NULL, active INTEGER NOT NULL)") { ret 12i32 }
    var pg = orm.session(&c, a, .Postgres)
    let (pg_sql, pg_error) = orm.create_sql[Post](&pg, "posts")
    if pg_error != ok { ret 13i32 }
    if !str.eq(pg_sql, "CREATE TABLE IF NOT EXISTS posts (id BIGINT PRIMARY KEY, user_id BIGINT NOT NULL, title TEXT NOT NULL, views BIGINT NOT NULL)") { ret 14i32 }
    var my = orm.session(&c, a, .Mysql)
    let (my_sql, my_error) = orm.create_sql[User](&my, "users")
    if my_error != ok { ret 15i32 }
    if !str.eq(my_sql, "CREATE TABLE IF NOT EXISTS users (id BIGINT PRIMARY KEY, name TEXT NOT NULL, age BIGINT NOT NULL, score DOUBLE NOT NULL, active TINYINT(1) NOT NULL)") { ret 16i32 }
    let (keyless_sql, keyless_error) = orm.create_sql[Keyless](&s, "k")
    if keyless_error != orm.NoKey || keyless_sql.len != 0usize { ret 17i32 }
    let (odd_sql, odd_error) = orm.create_sql[Odd](&s, "o")
    if odd_error != orm.Invalid || odd_sql.len != 0usize { ret 18i32 }
    if orm.create_table[User](&s, "users") != ok { ret 19i32 }
    if orm.create_table[User](&s, "users") != ok { ret 20i32 }
    if db.close(&c) != ok { ret 21i32 }
    ret 0i32
}

fn checks_crud(a: *mem.Arena) -> i32 {
    let (c0, open_error) = fresh(a)
    if open_error != ok { ret 30i32 }
    var c = c0
    var s = orm.session(&c, a, .Sqlite)
    let hooks = quiet_user()
    if orm.create_table[User](&s, "users") != ok { ret 31i32 }
    var ada = User { id: 0i64, name: "Ada L\xc3\xa9", age: 36i32, score: 0.1f64, active: true }
    var bob = User { id: 0i64, name: "Bob", age: 0i32 - 7i32, score: 2.5f64, active: false }
    var cy = User { id: 10i64, name: "", age: 41i32, score: 0.0f64, active: true }
    if orm.insert[User](&s, "users", &ada, &hooks) != ok { ret 32i32 }
    if orm.insert[User](&s, "users", &bob, &hooks) != ok { ret 33i32 }
    if orm.insert[User](&s, "users", &cy, &hooks) != ok { ret 34i32 }
    if ada.id != 1i64 || bob.id != 2i64 || cy.id != 10i64 { ret 35i32 }
    // The same explicit key twice is the database's constraint, not a hook or a panic.
    var twin = User { id: 10i64, name: "x", age: 1i32, score: 1.0f64, active: false }
    if orm.insert[User](&s, "users", &twin, &hooks) == ok { ret 36i32 }
    var got: User = zero
    let (found, find_error) = orm.find[User](&s, "users", 1i64, &got)
    if find_error != ok || !found { ret 37i32 }
    if got.id != 1i64 || !str.eq(got.name, "Ada L\xc3\xa9") || got.age != 36i32 || got.score != 0.1f64 || !got.active { ret 38i32 }
    let (found2, find2_error) = orm.find[User](&s, "users", 2i64, &got)
    if find2_error != ok || !found2 || got.age != 0i32 - 7i32 || got.active || got.score != 2.5f64 { ret 39i32 }
    let (found3, find3_error) = orm.find[User](&s, "users", 10i64, &got)
    if find3_error != ok || !found3 || got.name.len != 0usize || got.score != 0.0f64 { ret 40i32 }
    let (missing, missing_error) = orm.find[User](&s, "users", 99i64, &got)
    if missing_error != ok || missing { ret 41i32 }
    var rows: [8]User = zero
    var p: [1]db.Parameter = zero
    p[0] = db.Parameter { name: "", value: db.Value{ I64: 0i64 } }
    let (n, select_error) = orm.select[User](&s, "users", "age >= ?", "ORDER BY age DESC, id", p[0..], rows[0..])
    if select_error != ok || n != 2usize { ret 42i32 }
    if rows[0].id != 10i64 || rows[1].id != 1i64 { ret 43i32 }
    let (all_n, all_error) = orm.select[User](&s, "users", "", "ORDER BY id", zero, rows[0..])
    if all_error != ok || all_n != 3usize || rows[0].id != 1i64 || rows[1].id != 2i64 || rows[2].id != 10i64 { ret 44i32 }
    var tiny: [2]User = zero
    let (cut, cut_error) = orm.select[User](&s, "users", "", "ORDER BY id", zero, tiny[0..])
    if cut_error != orm.TooSmall || cut != 2usize { ret 45i32 }
    // Update every column; then NotFound for a key nobody has.
    ada.name = "Ada"
    ada.age = 37i32
    ada.active = false
    if orm.update[User](&s, "users", &ada, &hooks) != ok { ret 46i32 }
    let (_, back_error) = orm.find[User](&s, "users", 1i64, &got)
    if back_error != ok || !str.eq(got.name, "Ada") || got.age != 37i32 || got.active || got.score != 0.1f64 { ret 47i32 }
    var ghost = User { id: 99i64, name: "g", age: 1i32, score: 1.0f64, active: true }
    if orm.update[User](&s, "users", &ghost, &hooks) != orm.NotFound { ret 48i32 }
    if orm.delete[User](&s, "users", &bob, &hooks) != ok { ret 49i32 }
    let (gone, gone_error) = orm.find[User](&s, "users", 2i64, &got)
    if gone_error != ok || gone { ret 50i32 }
    if orm.delete[User](&s, "users", &bob, &hooks) != orm.NotFound { ret 51i32 }
    if db.close(&c) != ok { ret 52i32 }
    ret 0i32
}

fn checks_hooks(a: *mem.Arena) -> i32 {
    let (c0, open_error) = fresh(a)
    if open_error != ok { ret 60i32 }
    var c = c0
    var s = orm.session(&c, a, .Sqlite)
    if orm.create_table[User](&s, "users") != ok { ret 61i32 }
    let hooks = traced()
    var u = User { id: 0i64, name: "H", age: 1i32, score: 1.0f64, active: true }
    if orm.insert[User](&s, "users", &u, &hooks) != ok { ret 62i32 }
    // save, create, (insert), create, save.
    if !trace_is("1342") { ret 63i32 }
    trace_len = 0usize
    u.age = 2i32
    if orm.update[User](&s, "users", &u, &hooks) != ok { ret 64i32 }
    if !trace_is("1562") { ret 65i32 }
    trace_len = 0usize
    if orm.delete[User](&s, "users", &u, &hooks) != ok { ret 66i32 }
    if !trace_is("78") { ret 67i32 }
    trace_len = 0usize
    // A before hook that answers an error stops the operation before any SQL.
    var veto = traced()
    veto.before_create = h_veto
    let before = s.queries
    var v = User { id: 0i64, name: "V", age: 1i32, score: 1.0f64, active: true }
    if orm.insert[User](&s, "users", &v, &veto) != Veto { ret 68i32 }
    if !trace_is("1V") { ret 69i32 }
    if s.queries != before { ret 70i32 }
    var rows: [4]User = zero
    let (n, select_error) = orm.select[User](&s, "users", "", "", zero, rows[0..])
    if select_error != ok || n != 0usize { ret 71i32 }
    if db.close(&c) != ok { ret 72i32 }
    ret 0i32
}

fn checks_relations(a: *mem.Arena) -> i32 {
    let (c0, open_error) = fresh(a)
    if open_error != ok { ret 80i32 }
    var c = c0
    var s = orm.session(&c, a, .Sqlite)
    let uh = quiet_user()
    let ph = quiet_post()
    if orm.create_table[User](&s, "users") != ok { ret 81i32 }
    if orm.create_table[Post](&s, "posts") != ok { ret 82i32 }
    var users: [3]User = zero
    users[0] = User { id: 1i64, name: "ada", age: 30i32, score: 1.0f64, active: true }
    users[1] = User { id: 2i64, name: "bob", age: 31i32, score: 2.0f64, active: true }
    users[2] = User { id: 3i64, name: "cy", age: 32i32, score: 3.0f64, active: true }
    var i = 0usize
    while i < 3usize {
        if orm.insert[User](&s, "users", &users[i], &uh) != ok { ret 83i32 }
        i += 1usize
    }
    // user 1: two posts, user 2: none, user 3: three; inserted interleaved.
    var posts: [5]Post = zero
    posts[0] = Post { id: 0i64, user_id: 3i64, title: "c1", views: 5u32 }
    posts[1] = Post { id: 0i64, user_id: 1i64, title: "a1", views: 10u32 }
    posts[2] = Post { id: 0i64, user_id: 3i64, title: "c2", views: 0u32 }
    posts[3] = Post { id: 0i64, user_id: 1i64, title: "a2", views: 4000000000u32 }
    posts[4] = Post { id: 0i64, user_id: 3i64, title: "c3", views: 7u32 }
    i = 0usize
    while i < 5usize {
        if orm.insert[Post](&s, "posts", &posts[i], &ph) != ok { ret 84i32 }
        i += 1usize
    }
    if posts[4].id != 5i64 { ret 85i32 }
    // belongs-to: a post's author, and a dangling key.
    var owner: User = zero
    let (has_owner, owner_error) = orm.belongs_to[Post, User](&s, "users", &posts[3], "user_id", &owner)
    if owner_error != ok || !has_owner || !str.eq(owner.name, "ada") { ret 86i32 }
    var orphan = Post { id: 9i64, user_id: 77i64, title: "o", views: 1u32 }
    let (has_orphan, orphan_error) = orm.belongs_to[Post, User](&s, "users", &orphan, "user_id", &owner)
    if orphan_error != ok || has_orphan { ret 87i32 }
    let (_, nokey_error) = orm.belongs_to[Post, User](&s, "users", &orphan, "owner_id", &owner)
    if nokey_error != orm.NoKey { ret 88i32 }
    // Preload in the parents' own (not key) order: one statement.
    var order: [3]User = zero
    order[0] = users[2]
    order[1] = users[1]
    order[2] = users[0]
    var out: [8]Post = zero
    var spans: [3]orm.Span = zero
    let before = s.queries
    let (total, preload_error) = orm.has_many[User, Post](&s, "posts", "user_id", order[0..], out[0..], spans[0..])
    if preload_error != ok || total != 5usize { ret 89i32 }
    if s.queries - before != 1u64 { ret 90i32 }
    if spans[0].start != 0usize || spans[0].len != 3usize { ret 91i32 }
    if spans[1].len != 0usize { ret 92i32 }
    if spans[2].start != 3usize || spans[2].len != 2usize { ret 93i32 }
    if !str.eq(out[0].title, "c1") || !str.eq(out[1].title, "c2") || !str.eq(out[2].title, "c3") { ret 94i32 }
    if !str.eq(out[3].title, "a1") || !str.eq(out[4].title, "a2") || out[4].views != 4000000000u32 { ret 95i32 }
    var small: [4]Post = zero
    let (_, small_error) = orm.has_many[User, Post](&s, "posts", "user_id", order[0..], small[0..], spans[0..])
    if small_error != orm.TooSmall { ret 96i32 }
    if db.close(&c) != ok { ret 97i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    if sqlite.version() < 3007014i32 { os.exit(1i32) }
    var code = checks_ddl(a)
    if code == 0i32 { code = checks_crud(a) }
    if code == 0i32 { code = checks_hooks(a) }
    if code == 0i32 { code = checks_relations(a) }
    if code != 0i32 { os.exit(code) }
    ret ok
}
