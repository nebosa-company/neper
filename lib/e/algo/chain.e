// Tamper-evident record history (L037), after appdor's `src/history/tamper-evident.js` and the field diff of
// `src/history/index.js`: a hash chain over an audit stream (each entry's hash covers the previous hash and its own
// canonical content, so an edit breaks every later link), the WAS and CHANGED temporal predicates a view filters history
// with, the field-level diff that makes a revision, plan-tiered retention that re-anchors the chain with a marker, and a
// portable export. Values are JSON; storage is the host's.
//
// A hash is the SHA-256 of `prev + canonical(entry)` as 64 lowercase hex digits, the first link's `prev` being
// "genesis"; the canonical text has keys in byte order and no whitespace, numbers as written. Strings compare in byte
// order (appdor compares UTF-16 units, which agree for the basic plane).
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.crypto.hash as hash
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str
use e.time as time

error Invalid

fn text(s: str) -> json.Value { ret json.Value{ String: s } }

fn hex_digit(n: u8) -> u8 {
    if n < 10u8 { ret 48u8 + n }
    ret 87u8 + n
}

fn write_string(b: *str.Builder, s: str) -> err {
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
        } else if c == 13u8 {
            try str.push(b, "\\r")
        } else if c == 9u8 {
            try str.push(b, "\\t")
        } else if c == 8u8 {
            try str.push(b, "\\b")
        } else if c == 12u8 {
            try str.push(b, "\\f")
        } else if c < 32u8 {
            try str.push(b, "\\u00")
            try str.push_byte(b, hex_digit(c >> 4u8))
            try str.push_byte(b, hex_digit(c & 15u8))
        } else {
            try str.push_byte(b, c)
        }
        at += 1usize
    }
    ret str.push_byte(b, 34u8)
}

fn write_value(a: *mem.Arena, b: *str.Builder, v: json.Value, sorted: bool) -> err {
    switch v {
    case .Null:
        ret str.push(b, "null")
    case .Bool as flag:
        if flag { ret str.push(b, "true") }
        ret str.push(b, "false")
    case .Number as n:
        ret str.push(b, n.lexeme)
    case .String as s:
        ret write_string(b, s)
    case .Array as elements:
        try str.push_byte(b, 91u8)
        var at = 0usize
        while at < elements.len {
            if at > 0usize { try str.push_byte(b, 44u8) }
            try write_value(a, b, elements[at], sorted)
            at += 1usize
        }
        ret str.push_byte(b, 93u8)
    case .Object as members:
        try str.push_byte(b, 123u8)
        var written = 0usize
        var previous = ""
        while written < members.len {
            var best = members.len
            if sorted {
                // The builder owns the arena's tail while it is open, so the order is found by repeated selection.
                var at = 0usize
                while at < members.len {
                    let above = written == 0usize || str.compare(members[at].key, previous) > 0i32
                    if above && (best == members.len || str.compare(members[at].key, members[best].key) < 0i32) { best = at }
                    at += 1usize
                }
                if best == members.len { ret Invalid }
            } else {
                best = written
            }
            if written > 0usize { try str.push_byte(b, 44u8) }
            try write_string(b, members[best].key)
            try str.push_byte(b, 58u8)
            try write_value(a, b, members[best].value, sorted)
            previous = members[best].key
            written += 1usize
        }
        ret str.push_byte(b, 125u8)
    }
}

// The canonical text of a value: keys in byte order, no whitespace.
fn canonical_json(a: *mem.Arena, v: json.Value) -> (str, err) {
    let (b, builder_error) = str.builder(a, 256usize)
    if builder_error != ok { ret ("", builder_error) }
    var out = b
    let written = write_value(a, &out, v, true)
    if written != ok { ret ("", written) }
    ret (str.done(&out), ok)
}

// The text of a value in member order, as `JSON.stringify` writes it: what appdor compares revision values by.
fn plain_json(a: *mem.Arena, v: json.Value) -> (str, err) {
    let (b, builder_error) = str.builder(a, 256usize)
    if builder_error != ok { ret ("", builder_error) }
    var out = b
    let written = write_value(a, &out, v, false)
    if written != ok { ret ("", written) }
    ret (str.done(&out), ok)
}

fn sha256_hex(a: *mem.Arena, s: str) -> (str, err) {
    let digest = hash.sha256(s)
    let (out, out_error) = mem.alloc[u8](a, 64usize)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    while at < 32usize {
        out[at * 2usize] = hex_digit(digest[at] >> 4u8)
        out[at * 2usize + 1usize] = hex_digit(digest[at] & 15u8)
        at += 1usize
    }
    ret (out[0usize..64usize], ok)
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

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { ret ir.Obj { items: zero, len: 0usize, arena: a } }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn number(a: *mem.Arena, n: i64) -> json.Value {
    let (v, e) = json.number_from_i64(a, n)
    if e != ok { ret json.Value{ Number: json.Number{ lexeme: "0" } } }
    ret json.Value{ Number: v }
}

// --- the chain -----------------------------------------------------------------------------------------------------

fn last_hash(chain: *const list.List[json.Value]) -> str {
    if chain.len == 0usize { ret "genesis" }
    let (h, is_text) = member_text(chain.items[chain.len - 1usize], "hash")
    if !is_text { ret "" }
    ret h
}

// Append an entry; answers the stored record, `entry` with its `prev` and `hash`.
fn chain_append(a: *mem.Arena, chain: *list.List[json.Value], entry: json.Value) -> (json.Value, err) {
    let prev = last_hash(chain)
    let (canonical, canonical_error) = canonical_json(a, entry)
    if canonical_error != ok { ret (.Null, canonical_error) }
    let (joined, joined_error) = str.concat(a, prev, canonical)
    if joined_error != ok { ret (.Null, joined_error) }
    let (digest, digest_error) = sha256_hex(a, joined)
    if digest_error != ok { ret (.Null, digest_error) }
    var record = obj(a)
    try ir.assign(&record, entry)
    put(&record, "prev", text(prev))
    put(&record, "hash", text(digest))
    let value = ir.obj_value(&record)
    try list.push[json.Value](chain, value)
    ret (value, ok)
}

// An entry without its `hash` and `prev`.
fn bare(a: *mem.Arena, record: json.Value) -> json.Value {
    var o = obj(a)
    let (members, is_object) = ir.members_of(record)
    var at = 0usize
    while is_object && at < members.len {
        if !str.eq(members[at].key, "hash") && !str.eq(members[at].key, "prev") { put(&o, members[at].key, members[at].value) }
        at += 1usize
    }
    ret ir.obj_value(&o)
}

// Verify the whole chain: `{ok: true, length}` or `{ok: false, brokenAt, reason}`.
fn verify_chain(a: *mem.Arena, chain: []const json.Value) -> (json.Value, err) {
    var prev = "genesis"
    var i = 0usize
    while i < chain.len {
        var o = obj(a)
        let (recorded, have_prev) = member_text(chain[i], "prev")
        if !have_prev || !str.eq(recorded, prev) {
            put(&o, "ok", json.Value{ Bool: false })
            put(&o, "brokenAt", number(a, i64(i)))
            put(&o, "reason", text("prev-mismatch"))
            ret (ir.obj_value(&o), ok)
        }
        let (canonical, canonical_error) = canonical_json(a, bare(a, chain[i]))
        if canonical_error != ok { ret (.Null, canonical_error) }
        let (joined, joined_error) = str.concat(a, prev, canonical)
        if joined_error != ok { ret (.Null, joined_error) }
        let (digest, digest_error) = sha256_hex(a, joined)
        if digest_error != ok { ret (.Null, digest_error) }
        let (stored, have_hash) = member_text(chain[i], "hash")
        if !have_hash || !str.eq(stored, digest) {
            put(&o, "ok", json.Value{ Bool: false })
            put(&o, "brokenAt", number(a, i64(i)))
            put(&o, "reason", text("hash-mismatch"))
            ret (ir.obj_value(&o), ok)
        }
        prev = stored
        i += 1usize
    }
    var o = obj(a)
    put(&o, "ok", json.Value{ Bool: true })
    put(&o, "length", number(a, i64(chain.len)))
    ret (ir.obj_value(&o), ok)
}

// --- the diff ------------------------------------------------------------------------------------------------------

fn is_object_value(v: json.Value) -> bool {
    let (members, is_object) = ir.members_of(v)
    ret is_object
}

fn same_value(a: *mem.Arena, x: json.Value, y: json.Value) -> bool {
    if ir.is_null(x) && ir.is_null(y) { ret true }
    switch x {
    case .Number as nx:
        switch y {
        case .Number as ny:
            let (fx, ex) = json.number_f64(nx)
            let (fy, ey) = json.number_f64(ny)
            ret ex == ok && ey == ok && fx == fy
        default:
            ret false
        }
    case .Bool as bx:
        switch y {
        case .Bool as by:
            ret bx == by
        default:
            ret false
        }
    case .String as sx:
        switch y {
        case .String as sy:
            ret str.eq(sx, sy)
        default:
            ret false
        }
    case .Null:
        ret false
    default:
        let (ix, is_array_x) = ir.items_of(x)
        let (iy, is_array_y) = ir.items_of(y)
        let kind_x = is_array_x || is_object_value(x)
        let kind_y = is_array_y || is_object_value(y)
        if !kind_x || !kind_y { ret false }
        let (tx, ex) = plain_json(a, x)
        let (ty, ey) = plain_json(a, y)
        ret ex == ok && ey == ok && str.eq(tx, ty)
    }
}

fn in_list(names: []const str, key: str) -> bool {
    var at = 0usize
    while at < names.len {
        if str.eq(names[at], key) { ret true }
        at += 1usize
    }
    ret false
}

// The field-level diff of two record states, in key order (before's keys, then after's new ones): `{field, from, to}`
// with a missing side as null. `ignore` defaults to `updated_at` and `updated_by` where the caller passes none.
fn diff_records(a: *mem.Arena, before: json.Value, after: json.Value, ignore: []const str) -> ([]const json.Value, err) {
    let (found, found_error) = list.init[json.Value](a, 8usize)
    if found_error != ok { ret (zero, found_error) }
    var changes = found
    let (bm, b_is_object) = ir.members_of(before)
    let (am, a_is_object) = ir.members_of(after)
    var seen_list: [64]str = zero
    var seen = 0usize
    var pass = 0usize
    while pass < 2usize {
        var members = bm
        if pass == 1usize { members = am }
        var at = 0usize
        while at < members.len {
            let key = members[at].key
            var done = in_list(seen_list[0usize..seen], key) || in_list(ignore, key)
            if !done {
                if seen < 64usize {
                    seen_list[seen] = key
                    seen += 1usize
                }
                var from: json.Value = .Null
                var to: json.Value = .Null
                if b_is_object {
                    let (x, have) = get(before, key)
                    if have { from = x }
                }
                if a_is_object {
                    let (x, have) = get(after, key)
                    if have { to = x }
                }
                if !same_value(a, from, to) {
                    var c = obj(a)
                    put(&c, "field", text(key))
                    put(&c, "from", from)
                    put(&c, "to", to)
                    try list.push[json.Value](&changes, ir.obj_value(&c))
                }
            }
            at += 1usize
        }
        pass += 1usize
    }
    ret (list.slice_const[json.Value](&changes), ok)
}

fn default_ignore(a: *mem.Arena) -> []const str {
    let (names, e) = mem.alloc[str](a, 2usize)
    if e != ok { ret zero }
    names[0] = "updated_at"
    names[1] = "updated_by"
    ret names[0usize..2usize]
}

// Build an audited revision entry from `{recordId, before, after, actor, at, action}` and chain it.
fn record_change(a: *mem.Arena, chain: *list.List[json.Value], change: json.Value) -> (json.Value, err) {
    var before = ir.value_of(change, "before")
    var after = ir.value_of(change, "after")
    if !ir.truthy(before) { before = ir.empty_object() }
    if !ir.truthy(after) { after = ir.empty_object() }
    let (changes, diff_error) = diff_records(a, before, after, default_ignore(a))
    if diff_error != ok { ret (.Null, diff_error) }
    var entry = obj(a)
    let (record_id, have_record) = get(change, "recordId")
    if have_record { put(&entry, "recordId", record_id) }
    var action = "update"
    let (given, have_action) = member_text(change, "action")
    if have_action && given.len > 0usize { action = given }
    put(&entry, "action", text(action))
    let (actor, have_actor) = get(change, "actor")
    if have_actor { put(&entry, "actor", actor) }
    let (at, have_at) = get(change, "at")
    if have_at { put(&entry, "at", at) }
    put(&entry, "changes", json.Value{ Array: changes })
    let (stored, stored_error) = chain_append(a, chain, ir.obj_value(&entry))
    ret (stored, stored_error)
}

// --- WAS and CHANGED -----------------------------------------------------------------------------------------------

fn at_of(rev: json.Value) -> str {
    let (s, is_text) = member_text(rev, "at")
    ret s
}

// A record's revisions in `at` order (a stable insertion sort).
fn revisions_of(a: *mem.Arena, revisions: []const json.Value, record_id: json.Value) -> ([]const json.Value, err) {
    let (found, found_error) = list.init[json.Value](a, 8usize)
    if found_error != ok { ret (zero, found_error) }
    var out = found
    var at = 0usize
    while at < revisions.len {
        let (rid, have) = get(revisions[at], "recordId")
        if have && same_value(a, rid, record_id) { try list.push[json.Value](&out, revisions[at]) }
        at += 1usize
    }
    var i = 1usize
    while i < out.len {
        let item = out.items[i]
        var j = i
        while j > 0usize && str.compare(at_of(out.items[j - 1usize]), at_of(item)) > 0i32 {
            out.items[j] = out.items[j - 1usize]
            j -= 1usize
        }
        out.items[j] = item
        i += 1usize
    }
    ret (list.slice_const[json.Value](&out), ok)
}

fn json_equal(a: *mem.Arena, x: json.Value, y: json.Value) -> bool {
    let (tx, ex) = plain_json(a, x)
    let (ty, ey) = plain_json(a, y)
    ret ex == ok && ey == ok && str.eq(tx, ty)
}

fn changes_field(rev: json.Value, field: str) -> bool {
    let cs = items(ir.value_of(rev, "changes"))
    var at = 0usize
    while at < cs.len {
        let (f, is_text) = member_text(cs[at], "field")
        if is_text && str.eq(f, field) { ret true }
        at += 1usize
    }
    ret false
}

// Did `field` ever hold `value` for this record? `options.during` is `{from, to}`, either side optional.
fn was(a: *mem.Arena, revisions: []const json.Value, record_id: json.Value, field: str, value: json.Value, options: json.Value) -> bool {
    let (window, have_window_value) = get(options, "during")
    let has_window = have_window_value && ir.truthy(window)
    let (relevant, rel_error) = revisions_of(a, revisions, record_id)
    if rel_error != ok { ret false }
    var r = 0usize
    while r < relevant.len {
        let rev = relevant[r]
        let cs = items(ir.value_of(rev, "changes"))
        var c = 0usize
        while c < cs.len {
            let (f, is_text) = member_text(cs[c], "field")
            if is_text && str.eq(f, field) {
                if json_equal(a, ir.value_of(cs[c], "to"), value) {
                    if !has_window { ret true }
                    let held_from = at_of(rev)
                    var held_to = ""
                    var has_held_to = false
                    var n = 0usize
                    while n < relevant.len && !has_held_to {
                        if str.compare(at_of(relevant[n]), held_from) > 0i32 && changes_field(relevant[n], field) {
                            held_to = at_of(relevant[n])
                            has_held_to = true
                        }
                        n += 1usize
                    }
                    var upper = "\xEF\xBF\xBF"
                    let (to_text, have_to) = member_text(window, "to")
                    if have_to { upper = to_text }
                    var lower = ""
                    let (from_text, have_from) = member_text(window, "from")
                    if have_from { lower = from_text }
                    if str.compare(held_from, upper) <= 0i32 && (!has_held_to || str.compare(held_to, lower) >= 0i32) { ret true }
                }
                if json_equal(a, ir.value_of(cs[c], "from"), value) && !has_window { ret true }
            }
            c += 1usize
        }
        r += 1usize
    }
    ret false
}

// Did `field` change for this record, optionally `from`/`to` specific values and `after`/`before` an instant?
fn changed(a: *mem.Arena, revisions: []const json.Value, record_id: json.Value, field: str, options: json.Value) -> bool {
    let (after, have_after) = member_text(options, "after")
    let (before, have_before) = member_text(options, "before")
    let (from, have_from) = get(options, "from")
    let (to, have_to) = get(options, "to")
    var r = 0usize
    while r < revisions.len {
        let rev = revisions[r]
        let (rid, have_rid) = get(rev, "recordId")
        if have_rid && same_value(a, rid, record_id) {
            var inside = true
            if have_after && after.len > 0usize && str.compare(at_of(rev), after) < 0i32 { inside = false }
            if have_before && before.len > 0usize && str.compare(at_of(rev), before) > 0i32 { inside = false }
            if inside {
                let cs = items(ir.value_of(rev, "changes"))
                var c = 0usize
                while c < cs.len {
                    let (f, is_text) = member_text(cs[c], "field")
                    if is_text && str.eq(f, field) {
                        var ok_from = true
                        var ok_to = true
                        if have_from { ok_from = json_equal(a, ir.value_of(cs[c], "from"), from) }
                        if have_to { ok_to = json_equal(a, ir.value_of(cs[c], "to"), to) }
                        if ok_from && ok_to { ret true }
                    }
                    c += 1usize
                }
            }
        }
        r += 1usize
    }
    ret false
}

// The records a WAS or CHANGED predicate (`{op, field, value, options}`) keeps.
fn filter_by_history(a: *mem.Arena, records: []const json.Value, revisions: []const json.Value, predicate: json.Value) -> ([]const json.Value, err) {
    let (found, found_error) = list.init[json.Value](a, 8usize)
    if found_error != ok { ret (zero, found_error) }
    var out = found
    let (op, have_op) = member_text(predicate, "op")
    var options = ir.value_of(predicate, "options")
    if !ir.truthy(options) { options = ir.empty_object() }
    var at = 0usize
    while at < records.len {
        let id = ir.value_of(records[at], "id")
        var keep = false
        let (name, have_name) = member_text(predicate, "field")
        if have_op && str.eq(op, "was") { keep = was(a, revisions, id, name, ir.value_of(predicate, "value"), options) }
        if have_op && str.eq(op, "changed") { keep = changed(a, revisions, id, name, options) }
        if keep { try list.push[json.Value](&out, records[at]) }
        at += 1usize
    }
    ret (list.slice_const[json.Value](&out), ok)
}

// A record's revision stream narrowed to the named fields, empty revisions dropped.
fn field_history(a: *mem.Arena, revisions: []const json.Value, record_id: json.Value, fields: []const str) -> ([]const json.Value, err) {
    let (found, found_error) = list.init[json.Value](a, 8usize)
    if found_error != ok { ret (zero, found_error) }
    var out = found
    var at = 0usize
    while at < revisions.len {
        let (rid, have_rid) = get(revisions[at], "recordId")
        if have_rid && same_value(a, rid, record_id) {
            let (kept, kept_error) = list.init[json.Value](a, 4usize)
            if kept_error != ok { ret (zero, kept_error) }
            var cs_out = kept
            let cs = items(ir.value_of(revisions[at], "changes"))
            var c = 0usize
            while c < cs.len {
                let (f, is_text) = member_text(cs[c], "field")
                if is_text && in_list(fields, f) { try list.push[json.Value](&cs_out, cs[c]) }
                c += 1usize
            }
            if cs_out.len > 0usize {
                var o = obj(a)
                try ir.assign(&o, revisions[at])
                put(&o, "changes", json.Value{ Array: list.slice_const[json.Value](&cs_out) })
                try list.push[json.Value](&out, ir.obj_value(&o))
            }
        }
        at += 1usize
    }
    ret (list.slice_const[json.Value](&out), ok)
}

// --- retention and export -------------------------------------------------------------------------------------------

fn window_days(plan: str, windows: json.Value, has_windows: bool) -> (f64, bool) {
    if has_windows {
        let (w, found) = get(windows, plan)
        if !found || ir.is_null(w) { ret (0.0f64, false) }
        switch w {
        case .Number as n:
            let (x, e) = json.number_f64(n)
            ret (x, e == ok)
        default:
            ret (0.0f64, false)
        }
    }
    if str.eq(plan, "free") { ret (14.0f64, true) }
    if str.eq(plan, "pro") { ret (365.0f64, true) }
    if str.eq(plan, "business") { ret (1095.0f64, true) }
    ret (0.0f64, false)
}

// Milliseconds since the epoch of an ISO timestamp, or absent.
fn parse_ms(s: str) -> (i64, bool) {
    let (t, e) = time.parse_iso8601(s)
    if e != ok { ret (0i64, false) }
    var ms = t.nanos / 1000000i64
    if t.nanos < 0i64 && t.nanos % 1000000i64 != 0i64 { ms -= 1i64 }
    ret (ms, true)
}

// `new Date(ms).toISOString()`: `YYYY-MM-DDTHH:MM:SS.mmmZ`.
fn iso_ms(a: *mem.Arena, ms: i64) -> (str, err) {
    let (buf, buf_error) = mem.alloc[u8](a, 32usize)
    if buf_error != ok { ret ("", buf_error) }
    let full = time.format_iso8601(time.Timestamp { nanos: ms * 1000000i64 }, buf[0usize..32usize])
    if full.len < 30usize { ret ("", Invalid) }
    let (head, head_error) = str.concat(a, full[0usize..23usize], "Z")
    ret (head, head_error)
}

// Plan-tiered retention. A plan with no window (or none known) keeps everything; otherwise entries older than the
// window drop and the retained ones are rebuilt into a fresh chain led by a `retention-truncation` marker.
// `{chain, purged}`.
fn apply_history_retention(a: *mem.Arena, chain: []const json.Value, plan: str, now_ms: i64, windows: json.Value, has_windows: bool) -> (json.Value, err) {
    var o = obj(a)
    let (days, have_days) = window_days(plan, windows, has_windows)
    if !have_days {
        put(&o, "chain", json.Value{ Array: chain })
        put(&o, "purged", number(a, 0i64))
        ret (ir.obj_value(&o), ok)
    }
    let cutoff = f64(now_ms) - days * 24.0f64 * 3600.0f64 * 1000.0f64
    let (found, found_error) = list.init[json.Value](a, 8usize)
    if found_error != ok { ret (.Null, found_error) }
    var kept = found
    var at = 0usize
    while at < chain.len {
        let (stamp, is_text) = member_text(chain[at], "at")
        if is_text {
            let (ms, good) = parse_ms(stamp)
            if good && f64(ms) >= cutoff { try list.push[json.Value](&kept, chain[at]) }
        }
        at += 1usize
    }
    if kept.len == chain.len {
        put(&o, "chain", json.Value{ Array: list.slice_const[json.Value](&kept) })
        put(&o, "purged", number(a, 0i64))
        ret (ir.obj_value(&o), ok)
    }
    let (made, made_error) = list.init[json.Value](a, kept.len + 1usize)
    if made_error != ok { ret (.Null, made_error) }
    var rebuilt = made
    var marker = obj(a)
    put(&marker, "action", text("retention-truncation"))
    put(&marker, "purged", number(a, i64(chain.len - kept.len)))
    let (stamp, stamp_error) = iso_ms(a, now_ms)
    if stamp_error != ok { ret (.Null, stamp_error) }
    put(&marker, "at", text(stamp))
    let (first, first_error) = chain_append(a, &rebuilt, ir.obj_value(&marker))
    if first_error != ok { ret (.Null, first_error) }
    var k = 0usize
    while k < kept.len {
        let (next, next_error) = chain_append(a, &rebuilt, bare(a, kept.items[k]))
        if next_error != ok { ret (.Null, next_error) }
        k += 1usize
    }
    put(&o, "chain", json.Value{ Array: list.slice_const[json.Value](&rebuilt) })
    put(&o, "purged", number(a, i64(chain.len - kept.len)))
    ret (ir.obj_value(&o), ok)
}

// A portable export: the whole chain is verifiable offline, a filtered one is not (continuity breaks by design).
fn export_history(a: *mem.Arena, chain: []const json.Value, record_id: json.Value, has_record_id: bool) -> (json.Value, err) {
    var o = obj(a)
    put(&o, "kind", text("history-export"))
    put(&o, "exportedAt", .Null)
    put(&o, "verifiable", json.Value{ Bool: !has_record_id })
    var entries = chain
    if has_record_id && ir.truthy(record_id) {
        let (found, found_error) = list.init[json.Value](a, 8usize)
        if found_error != ok { ret (.Null, found_error) }
        var out = found
        var at = 0usize
        while at < chain.len {
            let (rid, have) = get(chain[at], "recordId")
            if have && same_value(a, rid, record_id) { try list.push[json.Value](&out, chain[at]) }
            at += 1usize
        }
        entries = list.slice_const[json.Value](&out)
    }
    put(&o, "entries", json.Value{ Array: entries })
    ret (ir.obj_value(&o), ok)
}
