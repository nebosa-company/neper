// Offline-first sync (L037), after appdor's `src/offline/index.js` (the coalescing write queue and optimistic apply),
// `durable-queue.js` (the outbox: sequence numbers, bounded retry with exponential backoff, dead letters, quota-aware
// persistence) and `sync-engine.js` (the `(updatedAt, id)` cursor, delta pull, applying a page around pending writes,
// field-level conflict detection and the three resolution strategies, and one full sync with its second pull).
//
// Everything outside is injected: the persistence is `StoreHooks` (`load`, `save`, `clear`), the server is `Remote`
// (`fetch_page`, `push`) and time is `now`. Calls are synchronous; appdor's per-store lock is not needed. Mutations,
// records and pages are JSON; a mutation is `{op, table, recordId, payload?, baseVersion?, at?}`.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str

// What a store's save or clear answered; `quota` marks a full device.
type SaveResult = struct { saved: bool, quota: bool, message: str }

type StoreHooks = struct { ctx: *void, durable: bool, load: fn(*void) -> []const json.Value, save: fn(*void, []const json.Value) -> SaveResult, clear: fn(*void) -> SaveResult }

// What pushing one mutation answered: accepted, a version conflict (with the server's record) or an error.
type PushResult = struct { accepted: bool, conflict: bool, server: json.Value, has_server: bool, failure: str, has_failure: bool }

type Remote = struct { ctx: *void, now: fn(*void) -> i64, fetch_page: fn(*void, json.Value, i64) -> json.Value, push: fn(*void, json.Value) -> PushResult }

type Outbox = struct { a: *mem.Arena, store: *const StoreHooks, now: fn(*void) -> i64, now_ctx: *void, queue: list.List[json.Value], dead: list.List[json.Value], sequence: i64, loaded: bool, healthy: bool, last_error: str, has_error: bool, evicted: i64, max_attempts: i64, base_delay: i64 }

fn text(s: str) -> json.Value { ret json.Value{ String: s } }

fn flag(b: bool) -> json.Value { ret json.Value{ Bool: b } }

fn number(a: *mem.Arena, n: i64) -> json.Value {
    let (v, e) = json.number_from_i64(a, n)
    if e != ok { ret json.Value{ Number: json.Number{ lexeme: "0" } } }
    ret json.Value{ Number: v }
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { ret ir.Obj { items: zero, len: 0usize, arena: a } }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn get(v: json.Value, key: str) -> (json.Value, bool) {
    let (x, found) = ir.get(v, key)
    ret (x, found)
}

fn member_text(v: json.Value, key: str) -> (str, bool) {
    let (x, found) = get(v, key)
    if !found { ret ("", false) }
    let (s, is_text) = ir.string_of(x)
    ret (s, is_text)
}

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
}

// `delete o[key]`.
fn unset(o: *ir.Obj, key: str) {
    var at = 0usize
    while at < o.len {
        if str.eq(o.items[at].key, key) {
            var k = at
            while k + 1usize < o.len {
                o.items[k] = o.items[k + 1usize]
                k += 1usize
            }
            o.len -= 1usize
            ret
        }
        at += 1usize
    }
}

fn push_value(l: *list.List[json.Value], v: json.Value) {
    let e = list.push[json.Value](l, v)
}

fn empty_list(a: *mem.Arena) -> list.List[json.Value] {
    let (l, e) = list.init[json.Value](a, 8usize)
    if e != ok { ret list.List[json.Value] { items: zero, len: 0usize, arena: a } }
    ret l
}

fn count_value(v: json.Value, key: str, fallback: i64) -> i64 {
    let (x, found) = get(v, key)
    if !found { ret fallback }
    switch x {
    case .Number as n:
        let (value, e) = json.number_i64(n)
        if e == ok { ret value }
        ret fallback
    default:
        ret fallback
    }
}

// `String(value)` for what a cursor or an id carries: text as is, a number as written.
fn as_text(v: json.Value) -> str {
    switch v {
    case .String as s:
        ret s
    case .Number as n:
        ret n.lexeme
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    default:
        ret ""
    }
}

// `a ?? b ?? ''` over two member names, as text.
fn first_text(v: json.Value, first: str, second: str) -> str {
    let (x, found) = get(v, first)
    if found && !ir.is_null(x) { ret as_text(x) }
    let (y, found_y) = get(v, second)
    if found_y && !ir.is_null(y) { ret as_text(y) }
    ret ""
}

fn same_json(a: *mem.Arena, x: json.Value, y: json.Value) -> bool {
    let (tx, ex) = plain(a, x)
    let (ty, ey) = plain(a, y)
    ret ex == ok && ey == ok && str.eq(tx, ty)
}

fn plain(a: *mem.Arena, v: json.Value) -> (str, err) {
    let (b, builder_error) = str.builder(a, 128usize)
    if builder_error != ok { ret ("", builder_error) }
    var out = b
    let written = write_plain(&out, v)
    if written != ok { ret ("", written) }
    ret (str.done(&out), ok)
}

fn write_plain(b: *str.Builder, v: json.Value) -> err {
    switch v {
    case .Null:
        ret str.push(b, "null")
    case .Bool as f:
        if f { ret str.push(b, "true") }
        ret str.push(b, "false")
    case .Number as n:
        ret str.push(b, n.lexeme)
    case .String as s:
        try str.push_byte(b, 34u8)
        var at = 0usize
        while at < s.len {
            let c = s[at]
            if c == 34u8 {
                try str.push(b, "\\\"")
            } else if c == 92u8 {
                try str.push(b, "\\\\")
            } else if c == 10u8 {
                try str.push(b, "\\n")
            } else {
                try str.push_byte(b, c)
            }
            at += 1usize
        }
        ret str.push_byte(b, 34u8)
    case .Array as elements:
        try str.push_byte(b, 91u8)
        var at = 0usize
        while at < elements.len {
            if at > 0usize { try str.push_byte(b, 44u8) }
            try write_plain(b, elements[at])
            at += 1usize
        }
        ret str.push_byte(b, 93u8)
    case .Object as members:
        try str.push_byte(b, 123u8)
        var at = 0usize
        while at < members.len {
            if at > 0usize { try str.push_byte(b, 44u8) }
            try write_plain(b, text(members[at].key))
            try str.push_byte(b, 58u8)
            try write_plain(b, members[at].value)
            at += 1usize
        }
        ret str.push_byte(b, 125u8)
    }
}

// `{...a, ...b}`.
fn spread(a: *mem.Arena, x: json.Value, y: json.Value) -> ir.Obj {
    var o = obj(a)
    let first = ir.assign(&o, x)
    let second = ir.assign(&o, y)
    ret o
}

// --- the cursor ----------------------------------------------------------------------------------------------------

// The beginning of time: `{updatedAt: null, id: null}`.
fn initial_cursor(a: *mem.Arena) -> json.Value {
    var o = obj(a)
    put(&o, "updatedAt", .Null)
    put(&o, "id", .Null)
    ret ir.obj_value(&o)
}

fn cursor_at(c: json.Value) -> (str, bool) {
    let (x, found) = get(c, "updatedAt")
    if !found || ir.is_null(x) { ret ("", false) }
    ret (as_text(x), true)
}

// `updatedAt|id`, or the empty text for the beginning.
fn encode_cursor(a: *mem.Arena, c: json.Value) -> str {
    let (at, have) = cursor_at(c)
    if !have { ret "" }
    var id = ""
    let (x, found) = get(c, "id")
    if found && !ir.is_null(x) { id = as_text(x) }
    ret cat(a, cat(a, at, "|"), id)
}

// Anything unreadable restarts from the beginning.
fn decode_cursor(a: *mem.Arena, s: str) -> json.Value {
    if s.len == 0usize { ret initial_cursor(a) }
    let (at, found) = str.find(s, "|")
    if !found { ret initial_cursor(a) }
    var o = obj(a)
    put(&o, "updatedAt", text(s[0usize..at]))
    let id = s[at + 1usize..]
    if id.len == 0usize { put(&o, "id", .Null) } else { put(&o, "id", text(id)) }
    ret ir.obj_value(&o)
}

// Is this record after the cursor, in `(updatedAt, id)` order?
fn is_after_cursor(record: json.Value, c: json.Value) -> bool {
    let (at, have) = cursor_at(c)
    if !have { ret true }
    let record_at = first_text(record, "updatedAt", "updated_at")
    let order = str.compare(record_at, at)
    if order > 0i32 { ret true }
    if order < 0i32 { ret false }
    var cursor_id = ""
    let (x, found) = get(c, "id")
    if found && !ir.is_null(x) { cursor_id = as_text(x) }
    ret str.compare(as_text(ir.value_of(record, "id")), cursor_id) > 0i32
}

fn advance_cursor(a: *mem.Arena, records: []const json.Value, previous: json.Value) -> json.Value {
    if records.len == 0usize { ret previous }
    let last = records[records.len - 1usize]
    var o = obj(a)
    put(&o, "updatedAt", text(first_text(last, "updatedAt", "updated_at")))
    put(&o, "id", text(as_text(ir.value_of(last, "id"))))
    ret ir.obj_value(&o)
}

// --- pull and apply ------------------------------------------------------------------------------------------------

// Pull pages until one is short, the cursor stops moving or `max_pages` is reached:
// `{records, deletions, cursor, complete, stalled, pages}`.
fn pull_changes(a: *mem.Arena, remote: *const Remote, cursor: json.Value, limit: i64, max_pages: i64) -> json.Value {
    var current = cursor
    var records = empty_list(a)
    var deletions = empty_list(a)
    var pages = 0i64
    var out = obj(a)
    while pages < max_pages {
        let page = remote.fetch_page(remote.ctx, current, limit)
        let batch = items(ir.value_of(page, "records"))
        let dropped = items(ir.value_of(page, "deletions"))
        var d = 0usize
        while d < dropped.len {
            push_value(&deletions, dropped[d])
            d += 1usize
        }
        if batch.len == 0usize {
            pages = pages
            put(&out, "records", json.Value{ Array: list.slice_const[json.Value](&records) })
            put(&out, "deletions", json.Value{ Array: list.slice_const[json.Value](&deletions) })
            put(&out, "cursor", current)
            put(&out, "complete", flag(pages < max_pages))
            put(&out, "stalled", flag(false))
            put(&out, "pages", number(a, pages))
            ret ir.obj_value(&out)
        }
        var b = 0usize
        while b < batch.len {
            push_value(&records, batch[b])
            b += 1usize
        }
        let next = advance_cursor(a, batch, current)
        if str.eq(encode_cursor(a, next), encode_cursor(a, current)) {
            put(&out, "records", json.Value{ Array: list.slice_const[json.Value](&records) })
            put(&out, "deletions", json.Value{ Array: list.slice_const[json.Value](&deletions) })
            put(&out, "cursor", current)
            put(&out, "complete", flag(false))
            put(&out, "stalled", flag(true))
            put(&out, "pages", number(a, pages + 1i64))
            ret ir.obj_value(&out)
        }
        current = next
        pages += 1i64
        if i64(batch.len) < limit {
            put(&out, "records", json.Value{ Array: list.slice_const[json.Value](&records) })
            put(&out, "deletions", json.Value{ Array: list.slice_const[json.Value](&deletions) })
            put(&out, "cursor", current)
            put(&out, "complete", flag(pages < max_pages))
            put(&out, "stalled", flag(false))
            put(&out, "pages", number(a, pages))
            ret ir.obj_value(&out)
        }
    }
    put(&out, "records", json.Value{ Array: list.slice_const[json.Value](&records) })
    put(&out, "deletions", json.Value{ Array: list.slice_const[json.Value](&deletions) })
    put(&out, "cursor", current)
    put(&out, "complete", flag(pages < max_pages))
    put(&out, "stalled", flag(false))
    put(&out, "pages", number(a, pages))
    ret ir.obj_value(&out)
}

fn id_in(ids: []const str, id: str) -> bool {
    var at = 0usize
    while at < ids.len {
        if str.eq(ids[at], id) { ret true }
        at += 1usize
    }
    ret false
}

// Apply a pulled page to a local record set; a record with a pending write is not overwritten but reported as
// `shadowed`. `{records, inserted, updated, removed, shadowed}`.
fn apply_changes(a: *mem.Arena, local: []const json.Value, changes: json.Value, pending_ids: []const str) -> json.Value {
    var ids = empty_list(a)
    var rows = empty_list(a)
    var at = 0usize
    while at < local.len {
        let id = as_text(ir.value_of(local[at], "id"))
        var found = false
        var k = 0usize
        while k < ids.len {
            if str.eq(as_text(ids.items[k]), id) {
                rows.items[k] = local[at]
                found = true
            }
            k += 1usize
        }
        if !found {
            push_value(&ids, text(id))
            push_value(&rows, local[at])
        }
        at += 1usize
    }
    var inserted = empty_list(a)
    var updated = empty_list(a)
    var shadowed = empty_list(a)
    var removed = empty_list(a)
    let incoming = items(ir.value_of(changes, "records"))
    var i = 0usize
    while i < incoming.len {
        let id = as_text(ir.value_of(incoming[i], "id"))
        if id_in(pending_ids, id) {
            push_value(&shadowed, incoming[i])
        } else {
            var index = ids.len
            var k = 0usize
            while k < ids.len {
                if str.eq(as_text(ids.items[k]), id) { index = k }
                k += 1usize
            }
            if index < ids.len {
                push_value(&updated, text(id))
                rows.items[index] = incoming[i]
            } else {
                push_value(&inserted, text(id))
                push_value(&ids, text(id))
                push_value(&rows, incoming[i])
            }
        }
        i += 1usize
    }
    let gone = items(ir.value_of(changes, "deletions"))
    var d = 0usize
    while d < gone.len {
        var id = ""
        let (given, have_given) = get(gone[d], "id")
        if have_given && !ir.is_null(given) { id = as_text(given) } else { id = as_text(gone[d]) }
        if id_in(pending_ids, id) {
            var o = obj(a)
            put(&o, "id", text(id))
            put(&o, "deleted", flag(true))
            push_value(&shadowed, ir.obj_value(&o))
        } else {
            var index = ids.len
            var k = 0usize
            while k < ids.len {
                if str.eq(as_text(ids.items[k]), id) { index = k }
                k += 1usize
            }
            if index < ids.len {
                var m = index
                while m + 1usize < ids.len {
                    ids.items[m] = ids.items[m + 1usize]
                    rows.items[m] = rows.items[m + 1usize]
                    m += 1usize
                }
                ids.len -= 1usize
                rows.len -= 1usize
                push_value(&removed, text(id))
            }
        }
        d += 1usize
    }
    var out = obj(a)
    put(&out, "records", json.Value{ Array: list.slice_const[json.Value](&rows) })
    put(&out, "inserted", json.Value{ Array: list.slice_const[json.Value](&inserted) })
    put(&out, "updated", json.Value{ Array: list.slice_const[json.Value](&updated) })
    put(&out, "removed", json.Value{ Array: list.slice_const[json.Value](&removed) })
    put(&out, "shadowed", json.Value{ Array: list.slice_const[json.Value](&shadowed) })
    ret ir.obj_value(&out)
}

// --- conflicts -----------------------------------------------------------------------------------------------------

fn add_key(keys: *list.List[json.Value], key: str) {
    var at = 0usize
    while at < keys.len {
        if str.eq(as_text(keys.items[at]), key) { ret }
        at += 1usize
    }
    push_value(keys, text(key))
}

fn add_keys_of(keys: *list.List[json.Value], v: json.Value) {
    let (members, is_object) = ir.members_of(v)
    var at = 0usize
    while is_object && at < members.len {
        add_key(keys, members[at].key)
        at += 1usize
    }
}

// The field of `v`, missing as null (`JSON.stringify(undefined)` differs from null only by being absent, and both
// sides are read the same way).
fn field_of(v: json.Value, key: str) -> json.Value {
    let (x, found) = get(v, key)
    if !found { ret .Null }
    ret x
}

// Which fields each side changed against the base: `{ok, mineChanged, theirsChanged, conflicting}`, or
// `{ok: false, reason: "no-base-version"}` without a base.
fn detect_field_conflicts(a: *mem.Arena, base: json.Value, has_base: bool, mine: json.Value, theirs: json.Value) -> json.Value {
    var out = obj(a)
    if !has_base || !ir.truthy(base) {
        put(&out, "ok", flag(false))
        put(&out, "reason", text("no-base-version"))
        ret ir.obj_value(&out)
    }
    var keys = empty_list(a)
    add_keys_of(&keys, base)
    add_keys_of(&keys, mine)
    add_keys_of(&keys, theirs)
    var mine_changed = empty_list(a)
    var theirs_changed = empty_list(a)
    var conflicting = empty_list(a)
    var at = 0usize
    while at < keys.len {
        let key = as_text(keys.items[at])
        let b = field_of(base, key)
        let m = field_of(mine, key)
        let t = field_of(theirs, key)
        let by_me = !same_json(a, b, m)
        let by_them = !same_json(a, b, t)
        if by_me && by_them {
            if same_json(a, m, t) {
                push_value(&mine_changed, text(key))
            } else {
                push_value(&conflicting, text(key))
            }
        } else {
            if by_me { push_value(&mine_changed, text(key)) }
            if by_them { push_value(&theirs_changed, text(key)) }
        }
        at += 1usize
    }
    put(&out, "ok", flag(true))
    put(&out, "mineChanged", json.Value{ Array: list.slice_const[json.Value](&mine_changed) })
    put(&out, "theirsChanged", json.Value{ Array: list.slice_const[json.Value](&theirs_changed) })
    put(&out, "conflicting", json.Value{ Array: list.slice_const[json.Value](&conflicting) })
    ret ir.obj_value(&out)
}

fn known_strategy(s: str) -> bool {
    ret str.eq(s, "last-write-wins") || str.eq(s, "field-merge") || str.eq(s, "manual")
}

// Resolve one conflict `{base, mine, theirs, mineAt, theirsAt}` under a strategy.
fn resolve_conflict(a: *mem.Arena, conflict: json.Value, strategy: str) -> json.Value {
    var out = obj(a)
    if !known_strategy(strategy) {
        put(&out, "resolved", flag(false))
        put(&out, "reason", text(cat(a, "unknown strategy: ", strategy)))
        ret ir.obj_value(&out)
    }
    let (base, has_base) = get(conflict, "base")
    let mine = ir.value_of(conflict, "mine")
    let theirs = ir.value_of(conflict, "theirs")
    if str.eq(strategy, "manual") {
        put(&out, "resolved", flag(false))
        put(&out, "reason", text("manual-resolution-required"))
        put(&out, "mine", mine)
        put(&out, "theirs", theirs)
        ret ir.obj_value(&out)
    }
    if str.eq(strategy, "last-write-wins") {
        // Ties go to the server: picking the local write would let a fast clock win every race.
        let mine_at = first_text(conflict, "mineAt", "mineAt")
        let theirs_at = first_text(conflict, "theirsAt", "theirsAt")
        var winner = "theirs"
        if str.compare(mine_at, theirs_at) > 0i32 { winner = "mine" }
        put(&out, "resolved", flag(true))
        put(&out, "strategy", text(strategy))
        put(&out, "winner", text(winner))
        var chosen = spread(a, mine, ir.empty_object())
        if str.eq(winner, "theirs") { chosen = spread(a, theirs, ir.empty_object()) }
        put(&out, "merged", ir.obj_value(&chosen))
        ret ir.obj_value(&out)
    }
    let diff = detect_field_conflicts(a, base, has_base, mine, theirs)
    let (good, have_good) = get(diff, "ok")
    var is_ok = false
    switch good {
    case .Bool as b:
        is_ok = b
    default:
        is_ok = false
    }
    if !is_ok {
        put(&out, "resolved", flag(false))
        put(&out, "reason", ir.value_of(diff, "reason"))
        ret ir.obj_value(&out)
    }
    let conflicting = items(ir.value_of(diff, "conflicting"))
    if conflicting.len > 0usize {
        put(&out, "resolved", flag(false))
        put(&out, "reason", text("field-conflict"))
        put(&out, "fields", json.Value{ Array: conflicting })
        put(&out, "mine", mine)
        put(&out, "theirs", theirs)
        ret ir.obj_value(&out)
    }
    var merged = spread(a, base, ir.empty_object())
    let theirs_changed = items(ir.value_of(diff, "theirsChanged"))
    var t = 0usize
    while t < theirs_changed.len {
        put(&merged, as_text(theirs_changed[t]), field_of(theirs, as_text(theirs_changed[t])))
        t += 1usize
    }
    let mine_changed = items(ir.value_of(diff, "mineChanged"))
    var m = 0usize
    while m < mine_changed.len {
        put(&merged, as_text(mine_changed[m]), field_of(mine, as_text(mine_changed[m])))
        m += 1usize
    }
    put(&out, "resolved", flag(true))
    put(&out, "strategy", text(strategy))
    put(&out, "winner", text("merged"))
    put(&out, "merged", ir.obj_value(&merged))
    put(&out, "mineChanged", json.Value{ Array: mine_changed })
    put(&out, "theirsChanged", json.Value{ Array: theirs_changed })
    ret ir.obj_value(&out)
}

// --- the coalescing queue --------------------------------------------------------------------------------------------

fn same_target(x: json.Value, y: json.Value) -> bool {
    ret str.eq(as_text(ir.value_of(x, "table")), as_text(ir.value_of(y, "table"))) && str.eq(as_text(ir.value_of(x, "recordId")), as_text(ir.value_of(y, "recordId")))
}

// `{...existing, payload: {...existing.payload, ...mutation.payload}, at: mutation.at}`.
fn merged_payload(a: *mem.Arena, existing: json.Value, mutation: json.Value) -> json.Value {
    var merged = spread(a, ir.value_of(existing, "payload"), ir.value_of(mutation, "payload"))
    var out = spread(a, existing, ir.empty_object())
    put(&out, "payload", ir.obj_value(&merged))
    let (at, have_at) = get(mutation, "at")
    if have_at { put(&out, "at", at) } else { unset(&out, "at") }
    ret ir.obj_value(&out)
}

// Coalesce a mutation into a queue (a new queue is returned): an insert and a delete cancel, an insert or update takes
// a later update's payload, anything followed by a delete becomes the delete, and otherwise the later one replaces.
fn enqueue(a: *mem.Arena, queue: []const json.Value, mutation: json.Value) -> []const json.Value {
    var out = empty_list(a)
    var index = queue.len
    var at = 0usize
    while at < queue.len {
        push_value(&out, queue[at])
        if index == queue.len && same_target(queue[at], mutation) { index = at }
        at += 1usize
    }
    if index == queue.len {
        push_value(&out, mutation)
        ret list.slice_const[json.Value](&out)
    }
    let existing = queue[index]
    let was = as_text(ir.value_of(existing, "op"))
    let now_op = as_text(ir.value_of(mutation, "op"))
    if str.eq(was, "insert") && str.eq(now_op, "delete") {
        var k = index
        while k + 1usize < out.len {
            out.items[k] = out.items[k + 1usize]
            k += 1usize
        }
        out.len -= 1usize
        ret list.slice_const[json.Value](&out)
    }
    if (str.eq(was, "insert") || str.eq(was, "update")) && str.eq(now_op, "update") {
        out.items[index] = merged_payload(a, existing, mutation)
        ret list.slice_const[json.Value](&out)
    }
    out.items[index] = mutation
    ret list.slice_const[json.Value](&out)
}

// Apply a mutation optimistically to a record set, marking the touched record `_pending`.
fn apply_optimistic(a: *mem.Arena, records: []const json.Value, mutation: json.Value) -> []const json.Value {
    var out = empty_list(a)
    let id = as_text(ir.value_of(mutation, "recordId"))
    let op = as_text(ir.value_of(mutation, "op"))
    var index = records.len
    var at = 0usize
    while at < records.len {
        if index == records.len && str.eq(as_text(ir.value_of(records[at], "id")), id) { index = at }
        at += 1usize
    }
    if str.eq(op, "delete") {
        var k = 0usize
        while k < records.len {
            if !str.eq(as_text(ir.value_of(records[k], "id")), id) { push_value(&out, records[k]) }
            k += 1usize
        }
        ret list.slice_const[json.Value](&out)
    }
    var k = 0usize
    while k < records.len {
        push_value(&out, records[k])
        k += 1usize
    }
    if str.eq(op, "insert") {
        var row = obj(a)
        put(&row, "id", ir.value_of(mutation, "recordId"))
        let assigned = ir.assign(&row, ir.value_of(mutation, "payload"))
        put(&row, "_pending", flag(true))
        push_value(&out, ir.obj_value(&row))
        ret list.slice_const[json.Value](&out)
    }
    if str.eq(op, "update") && index < records.len {
        var row = spread(a, records[index], ir.value_of(mutation, "payload"))
        put(&row, "_pending", flag(true))
        out.items[index] = ir.obj_value(&row)
    }
    ret list.slice_const[json.Value](&out)
}

fn push_answer(remote: *const Remote, mutation: json.Value) -> PushResult {
    ret remote.push(remote.ctx, mutation)
}

// Push a queue in order: `{synced, conflicts, failed, remaining}`. `resolve` is "server-wins" to drop a conflicting
// local write, and `stop_on_error` (appdor's default) blocks the rest of the queue after a failure.
fn sync_queue(a: *mem.Arena, queue: []const json.Value, remote: *const Remote, resolve: str, stop_on_error: bool) -> json.Value {
    var synced = empty_list(a)
    var conflicts = empty_list(a)
    var failed = empty_list(a)
    var remaining = empty_list(a)
    var blocked = false
    var at = 0usize
    while at < queue.len {
        let mutation = queue[at]
        if blocked {
            push_value(&remaining, mutation)
        } else {
            let res = push_answer(remote, mutation)
            if res.accepted {
                push_value(&synced, mutation)
            } else if res.conflict {
                var c = obj(a)
                put(&c, "mutation", mutation)
                if res.has_server { put(&c, "server", res.server) }
                push_value(&conflicts, ir.obj_value(&c))
                if !str.eq(resolve, "server-wins") { push_value(&remaining, mutation) }
            } else {
                var f = obj(a)
                put(&f, "mutation", mutation)
                var message = "failed"
                if res.has_failure && res.failure.len > 0usize { message = res.failure }
                put(&f, "error", text(message))
                push_value(&failed, ir.obj_value(&f))
                push_value(&remaining, mutation)
                if stop_on_error { blocked = true }
            }
        }
        at += 1usize
    }
    var out = obj(a)
    put(&out, "synced", json.Value{ Array: list.slice_const[json.Value](&synced) })
    put(&out, "conflicts", json.Value{ Array: list.slice_const[json.Value](&conflicts) })
    put(&out, "failed", json.Value{ Array: list.slice_const[json.Value](&failed) })
    put(&out, "remaining", json.Value{ Array: list.slice_const[json.Value](&remaining) })
    ret ir.obj_value(&out)
}

// --- the durable outbox ------------------------------------------------------------------------------------------------

fn new_outbox(a: *mem.Arena, store: *const StoreHooks, now: fn(*void) -> i64, now_ctx: *void, max_attempts: i64, base_delay: i64) -> Outbox {
    var attempts = max_attempts
    if attempts <= 0i64 { attempts = 6i64 }
    var delay = base_delay
    if delay <= 0i64 { delay = 1000i64 }
    ret Outbox { a: a, store: store, now: now, now_ctx: now_ctx, queue: empty_list(a), dead: empty_list(a), sequence: 0i64, loaded: false, healthy: true, last_error: "", has_error: false, evicted: 0i64, max_attempts: attempts, base_delay: delay }
}

fn backoff_delay(attempts: i64, base: i64) -> i64 {
    var delay = base
    var n = 1i64
    while n < attempts && delay < 300000i64 {
        delay = delay * 2i64
        n += 1i64
    }
    if delay > 300000i64 { delay = 300000i64 }
    ret delay
}

fn durable(o: *const Outbox) -> bool { ret o.store.durable && o.healthy }

fn with_dead_flag(a: *mem.Arena, m: json.Value, dead: bool) -> json.Value {
    var out = spread(a, m, ir.empty_object())
    put(&out, "__dead", flag(dead))
    ret ir.obj_value(&out)
}

fn write_store(o: *Outbox) -> SaveResult {
    var all = empty_list(o.a)
    var q = 0usize
    while q < o.queue.len {
        push_value(&all, with_dead_flag(o.a, o.queue.items[q], false))
        q += 1usize
    }
    var d = 0usize
    while d < o.dead.len {
        push_value(&all, with_dead_flag(o.a, o.dead.items[d], true))
        d += 1usize
    }
    ret o.store.save(o.store.ctx, list.slice_const[json.Value](&all))
}

// Persist; never fails the caller. A full device first drops the dead letters, then keeps the queue in memory only.
// `{ok, error?, quota?, evicted?}`.
fn persist(o: *Outbox) -> json.Value {
    var out = obj(o.a)
    let first = write_store(o)
    if first.saved {
        o.healthy = true
        o.has_error = false
        put(&out, "ok", flag(true))
        ret ir.obj_value(&out)
    }
    if !first.quota {
        o.healthy = false
        o.last_error = first.message
        o.has_error = true
        put(&out, "ok", flag(false))
        put(&out, "error", text(first.message))
        ret ir.obj_value(&out)
    }
    let droppable = o.dead.len
    if droppable > 0usize {
        o.dead.len = 0usize
        o.evicted += i64(droppable)
        let again = write_store(o)
        if again.saved {
            o.healthy = true
            o.has_error = false
            put(&out, "ok", flag(true))
            put(&out, "evicted", number(o.a, i64(droppable)))
            ret ir.obj_value(&out)
        }
        o.last_error = again.message
        o.has_error = true
    } else {
        o.last_error = first.message
        o.has_error = true
    }
    o.healthy = false
    put(&out, "ok", flag(false))
    put(&out, "error", text(o.last_error))
    put(&out, "quota", flag(true))
    put(&out, "evicted", number(o.a, i64(droppable)))
    ret ir.obj_value(&out)
}

// Load the stored queue and dead letters; `{pending, dead}`.
fn restore(o: *Outbox) -> json.Value {
    let saved = o.store.load(o.store.ctx)
    var queue = empty_list(o.a)
    var dead = empty_list(o.a)
    var at = 0usize
    while at < saved.len {
        let marked = ir.truthy(ir.value_of(saved[at], "__dead"))
        if marked { push_value(&dead, saved[at]) } else { push_value(&queue, saved[at]) }
        let s = count_value(saved[at], "seq", 0i64)
        if s > o.sequence { o.sequence = s }
        at += 1usize
    }
    o.queue = queue
    o.dead = dead
    o.loaded = true
    var out = obj(o.a)
    put(&out, "pending", number(o.a, i64(queue.len)))
    put(&out, "dead", number(o.a, i64(dead.len)))
    ret ir.obj_value(&out)
}

// Every mutating operation first re-reads the store, unless storage has failed (the local copy then holds work the
// store did not accept).
fn refresh(o: *Outbox) {
    if o.loaded && o.healthy {
        let reloaded = restore(o)
    }
}

fn pending(o: *const Outbox) -> []const json.Value { ret list.slice_const[json.Value](&o.queue) }

fn dead_letters(o: *const Outbox) -> []const json.Value { ret list.slice_const[json.Value](&o.dead) }

// What is due at `at`.
fn ready(a: *mem.Arena, o: *const Outbox, at: i64) -> []const json.Value {
    var out = empty_list(a)
    var q = 0usize
    while q < o.queue.len {
        if count_value(o.queue.items[q], "nextAttemptAt", 0i64) <= at { push_value(&out, o.queue.items[q]) }
        q += 1usize
    }
    ret list.slice_const[json.Value](&out)
}

// Queue a mutation: `{queued, coalesced, persisted, durable[, storageError]}`.
fn add(o: *Outbox, mutation: json.Value) -> json.Value {
    refresh(o)
    o.sequence += 1i64
    var stamped = spread(o.a, mutation, ir.empty_object())
    put(&stamped, "seq", number(o.a, o.sequence))
    let (at, have_at) = get(mutation, "at")
    if !have_at || ir.is_null(at) { put(&stamped, "at", number(o.a, o.now(o.now_ctx))) }
    put(&stamped, "attempts", number(o.a, 0i64))
    // A caller's `nextAttemptAt` is honoured: it holds a write back until something else finishes.
    var hold = count_value(mutation, "nextAttemptAt", 0i64)
    if !ir.truthy(ir.value_of(mutation, "nextAttemptAt")) { hold = 0i64 }
    put(&stamped, "nextAttemptAt", number(o.a, hold))
    let before = o.queue.len
    let merged = enqueue(o.a, list.slice_const[json.Value](&o.queue), ir.obj_value(&stamped))
    var next = empty_list(o.a)
    var k = 0usize
    while k < merged.len {
        push_value(&next, merged[k])
        k += 1usize
    }
    o.queue = next
    let saved = persist(o)
    var out = obj(o.a)
    put(&out, "queued", number(o.a, i64(o.queue.len)))
    put(&out, "coalesced", flag(o.queue.len == before))
    var persisted = false
    switch ir.value_of(saved, "ok") {
    case .Bool as b:
        persisted = b
    default:
        persisted = false
    }
    put(&out, "persisted", flag(persisted))
    put(&out, "durable", flag(durable(o)))
    if !persisted { put(&out, "storageError", ir.value_of(saved, "error")) }
    ret ir.obj_value(&out)
}

// Release writes held back on attachments once all of them are uploaded; the count released.
fn release_attachments(o: *Outbox, uploaded: []const str) -> i64 {
    refresh(o)
    var released = 0i64
    var q = 0usize
    while q < o.queue.len {
        let waiting = ir.value_of(o.queue.items[q], "waitingOnAttachments")
        if ir.truthy(waiting) {
            let ids = items(waiting)
            var all = true
            var k = 0usize
            while k < ids.len {
                if !id_in(uploaded, as_text(ids[k])) { all = false }
                k += 1usize
            }
            if all {
                var m = spread(o.a, o.queue.items[q], ir.empty_object())
                unset(&m, "waitingOnAttachments")
                put(&m, "nextAttemptAt", number(o.a, 0i64))
                o.queue.items[q] = ir.obj_value(&m)
                released += 1i64
            }
        }
        q += 1usize
    }
    if released > 0i64 {
        let saved = persist(o)
    }
    ret released
}

// Flush the queue through the remote's `push`. `{synced, conflicts, failed, remaining, dead, persisted, durable}`.
fn flush(o: *Outbox, remote: *const Remote, at: i64, continue_on_error: bool, resolve: str) -> json.Value {
    refresh(o)
    var synced = empty_list(o.a)
    var conflicts = empty_list(o.a)
    var failed = empty_list(o.a)
    var deferred = empty_list(o.a)
    var blocked = false
    var snapshot = empty_list(o.a)
    var s = 0usize
    while s < o.queue.len {
        push_value(&snapshot, o.queue.items[s])
        s += 1usize
    }
    var index = 0usize
    while index < snapshot.len {
        let mutation = snapshot.items[index]
        if blocked || count_value(mutation, "nextAttemptAt", 0i64) > at {
            push_value(&deferred, mutation)
        } else {
            let res = push_answer(remote, mutation)
            if res.accepted {
                push_value(&synced, mutation)
            } else if res.conflict {
                var c = obj(o.a)
                put(&c, "mutation", mutation)
                if res.has_server { put(&c, "server", res.server) }
                push_value(&conflicts, ir.obj_value(&c))
                // server-wins drops the local write; otherwise it stays, and a conflict is not an attempt.
                if !str.eq(resolve, "server-wins") { push_value(&deferred, mutation) }
            } else {
                let attempts = count_value(mutation, "attempts", 0i64) + 1i64
                var message = "failed"
                if res.has_failure && res.failure.len > 0usize { message = res.failure }
                if attempts >= o.max_attempts {
                    var gone = spread(o.a, mutation, ir.empty_object())
                    put(&gone, "attempts", number(o.a, attempts))
                    put(&gone, "lastError", text(message))
                    put(&gone, "deadAt", number(o.a, at))
                    push_value(&o.dead, ir.obj_value(&gone))
                    var f = obj(o.a)
                    put(&f, "mutation", mutation)
                    put(&f, "error", text(message))
                    put(&f, "dead", flag(true))
                    push_value(&failed, ir.obj_value(&f))
                } else {
                    var again = spread(o.a, mutation, ir.empty_object())
                    put(&again, "attempts", number(o.a, attempts))
                    put(&again, "lastError", text(message))
                    put(&again, "nextAttemptAt", number(o.a, at + backoff_delay(attempts, o.base_delay)))
                    var f = obj(o.a)
                    put(&f, "mutation", ir.obj_value(&again))
                    put(&f, "error", text(message))
                    put(&f, "dead", flag(false))
                    push_value(&failed, ir.obj_value(&f))
                    push_value(&deferred, ir.obj_value(&again))
                    if !continue_on_error { blocked = true }
                }
            }
        }
        index += 1usize
    }
    o.queue = deferred
    let saved = persist(o)
    var persisted = false
    switch ir.value_of(saved, "ok") {
    case .Bool as b:
        persisted = b
    default:
        persisted = false
    }
    var out = obj(o.a)
    put(&out, "synced", json.Value{ Array: list.slice_const[json.Value](&synced) })
    put(&out, "conflicts", json.Value{ Array: list.slice_const[json.Value](&conflicts) })
    put(&out, "failed", json.Value{ Array: list.slice_const[json.Value](&failed) })
    put(&out, "remaining", number(o.a, i64(o.queue.len)))
    put(&out, "dead", number(o.a, i64(o.dead.len)))
    put(&out, "persisted", flag(persisted))
    put(&out, "durable", flag(durable(o)))
    ret ir.obj_value(&out)
}

// A dead letter back to the queue with a clean budget: `{ok}` or `{ok: false, reason: "not-found"}`.
fn revive(o: *Outbox, seq: i64) -> json.Value {
    refresh(o)
    var out = obj(o.a)
    var index = o.dead.len
    var at = 0usize
    while at < o.dead.len {
        if index == o.dead.len && count_value(o.dead.items[at], "seq", -1i64) == seq { index = at }
        at += 1usize
    }
    if index == o.dead.len {
        put(&out, "ok", flag(false))
        put(&out, "reason", text("not-found"))
        ret ir.obj_value(&out)
    }
    let item = o.dead.items[index]
    var m = index
    while m + 1usize < o.dead.len {
        o.dead.items[m] = o.dead.items[m + 1usize]
        m += 1usize
    }
    o.dead.len -= 1usize
    var again = spread(o.a, item, ir.empty_object())
    put(&again, "attempts", number(o.a, 0i64))
    put(&again, "nextAttemptAt", number(o.a, 0i64))
    unset(&again, "lastError")
    unset(&again, "deadAt")
    push_value(&o.queue, ir.obj_value(&again))
    let saved = persist(o)
    put(&out, "ok", flag(true))
    ret ir.obj_value(&out)
}

// Discard a dead letter for good; whether one was removed.
fn discard(o: *Outbox, seq: i64) -> bool {
    refresh(o)
    let before = o.dead.len
    var kept = empty_list(o.a)
    var at = 0usize
    while at < o.dead.len {
        if count_value(o.dead.items[at], "seq", -1i64) != seq { push_value(&kept, o.dead.items[at]) }
        at += 1usize
    }
    o.dead = kept
    let saved = persist(o)
    ret o.dead.len < before
}

// Take a live mutation out of the queue because it has been dealt with; whether one was removed.
fn settle(o: *Outbox, seq: i64) -> bool {
    refresh(o)
    let before = o.queue.len
    var kept = empty_list(o.a)
    var at = 0usize
    while at < o.queue.len {
        if count_value(o.queue.items[at], "seq", -1i64) != seq { push_value(&kept, o.queue.items[at]) }
        at += 1usize
    }
    o.queue = kept
    let saved = persist(o)
    ret o.queue.len < before
}

// Empty both lists and the store; a clean clear restores the durability claim.
fn clear(o: *Outbox) {
    refresh(o)
    o.queue = empty_list(o.a)
    o.dead = empty_list(o.a)
    let cleared = o.store.clear(o.store.ctx)
    if cleared.saved {
        o.healthy = true
        o.has_error = false
    } else {
        o.healthy = false
        o.last_error = cleared.message
        o.has_error = true
    }
}

// What is waiting, for a badge: `{pending, dead, durable, byTable, oldestAt, needsAttention, storageError,
// evictedForSpace}`.
fn describe_outbox(a: *mem.Arena, o: *const Outbox) -> json.Value {
    var out = obj(a)
    var by_table = obj(a)
    var oldest = 0i64
    var have_oldest = false
    var q = 0usize
    while q < o.queue.len {
        let table = as_text(ir.value_of(o.queue.items[q], "table"))
        put(&by_table, table, number(a, count_value(ir.obj_value(&by_table), table, 0i64) + 1i64))
        let at = count_value(o.queue.items[q], "at", 0i64)
        if !have_oldest || at < oldest {
            oldest = at
            have_oldest = true
        }
        q += 1usize
    }
    put(&out, "pending", number(a, i64(o.queue.len)))
    put(&out, "dead", number(a, i64(o.dead.len)))
    put(&out, "durable", flag(durable(o)))
    put(&out, "byTable", ir.obj_value(&by_table))
    if have_oldest { put(&out, "oldestAt", number(a, oldest)) } else { put(&out, "oldestAt", .Null) }
    put(&out, "needsAttention", flag(o.dead.len > 0usize || o.has_error))
    if o.has_error { put(&out, "storageError", text(o.last_error)) } else { put(&out, "storageError", .Null) }
    put(&out, "evictedForSpace", number(a, o.evicted))
    ret ir.obj_value(&out)
}

// One full sync: pull, apply around pending writes, flush, and pull again what the flushed writes changed.
fn run_sync(a: *mem.Arena, o: *Outbox, has_outbox: bool, remote: *const Remote, local: []const json.Value, cursor: json.Value, strategy: str) -> json.Value {
    let started = remote.now(remote.ctx)
    var ids = empty_list(a)
    if has_outbox {
        var q = 0usize
        while q < o.queue.len {
            push_value(&ids, text(as_text(ir.value_of(o.queue.items[q], "recordId"))))
            q += 1usize
        }
    }
    let pending_ids = to_ids(a, list.slice_const[json.Value](&ids))
    let pulled = pull_changes(a, remote, cursor, 200i64, 50i64)
    let applied = apply_changes(a, local, pulled, pending_ids)
    var flushed_synced: []const json.Value = zero
    var flushed_conflicts: []const json.Value = zero
    var remaining = 0i64
    var dead = 0i64
    if has_outbox {
        var resolve = ""
        if str.eq(strategy, "last-write-wins") { resolve = "server-wins" }
        let result = flush(o, remote, remote.now(remote.ctx), false, resolve)
        flushed_synced = items(ir.value_of(result, "synced"))
        flushed_conflicts = items(ir.value_of(result, "conflicts"))
        remaining = count_value(result, "remaining", 0i64)
        dead = count_value(result, "dead", 0i64)
    }
    var records = items(ir.value_of(applied, "records"))
    var inserted = i64(items(ir.value_of(applied, "inserted")).len)
    var updated = i64(items(ir.value_of(applied, "updated")).len)
    let removed = i64(items(ir.value_of(applied, "removed")).len)
    let shadowed = i64(items(ir.value_of(applied, "shadowed")).len)
    var final_cursor = ir.value_of(pulled, "cursor")
    var pulled_count = i64(items(ir.value_of(pulled, "records")).len)
    if flushed_synced.len > 0usize {
        let second = pull_changes(a, remote, ir.value_of(pulled, "cursor"), 200i64, 50i64)
        let again = apply_changes(a, records, second, zero)
        records = items(ir.value_of(again, "records"))
        updated += i64(items(ir.value_of(again, "updated")).len)
        inserted += i64(items(ir.value_of(again, "inserted")).len)
        final_cursor = ir.value_of(second, "cursor")
        pulled_count += i64(items(ir.value_of(second, "records")).len)
    }
    var out = obj(a)
    put(&out, "records", json.Value{ Array: records })
    put(&out, "cursor", final_cursor)
    put(&out, "pulled", number(a, pulled_count))
    put(&out, "inserted", number(a, inserted))
    put(&out, "updated", number(a, updated))
    put(&out, "removed", number(a, removed))
    put(&out, "shadowed", number(a, shadowed))
    put(&out, "pushed", number(a, i64(flushed_synced.len)))
    put(&out, "conflicts", json.Value{ Array: flushed_conflicts })
    put(&out, "stillPending", number(a, remaining))
    put(&out, "deadLetters", number(a, dead))
    put(&out, "stalled", ir.value_of(pulled, "stalled"))
    put(&out, "durationMs", number(a, remote.now(remote.ctx) - started))
    ret ir.obj_value(&out)
}

fn to_ids(a: *mem.Arena, values: []const json.Value) -> []const str {
    let (out, e) = mem.alloc[str](a, values.len + 1usize)
    if e != ok { ret zero }
    var at = 0usize
    while at < values.len {
        out[at] = as_text(values[at])
        at += 1usize
    }
    ret out[0usize..values.len]
}
