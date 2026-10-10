// Scheduled external sync (L037), after appdor's `src/sync/sync-schedule.js`, `sync-refusal.js` and the pure planning
// half of `src/sync/synced-table.js` with `syncPlan` and `detectDrift` of `src/connectors`: the lease a worker holds
// on a binding, which bindings are due, the doubling retry delay after consecutive failures and the next run, a
// binding's health, what a deletion policy does to rows the source no longer has, the sync-key check, quarantine of
// rows without a usable key, the insert/update/delete plan of one pull, the run ledger row, and schema drift against a
// stored column mapping and its acceptance. Rows and mappings are JSON; instants are ISO-8601 texts or numbers of
// milliseconds. User-facing words come back as the catalogue key's humanized last segment, as appdor answers outside a
// browser (`sync.key.unknownColumn` is "Unknown column").
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str
use e.time as time

error Invalid

fn sync_lease_ms() -> f64 { ret 300000.0f64 }

fn min_interval_minutes() -> f64 { ret 5.0f64 }

fn max_backoff_minutes() -> f64 { ret 360.0f64 }

fn failing_after() -> f64 { ret 3.0f64 }

// Translate a catalogue key for the viewer; `variable` is the setting a message names.
type Translate = struct { ctx: *void, run: fn(*void, str, str) -> str }

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

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
}

fn push_value(l: *list.List[json.Value], v: json.Value) {
    let e = list.push[json.Value](l, v)
}

fn empty_list(a: *mem.Arena) -> list.List[json.Value] {
    let (l, e) = list.init[json.Value](a, 8usize)
    if e != ok { ret list.List[json.Value] { items: zero, len: 0usize, arena: a } }
    ret l
}

fn nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }

fn is_finite(x: f64) -> bool { ret x == x && x < 1.0e300f64 && x > -1.0e300f64 }

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

// A member that is neither missing, null, nor the empty text: the sync key's "has a value".
fn has_value(v: json.Value, key: str) -> bool {
    let (x, found) = get(v, key)
    if !found || ir.is_null(x) { ret false }
    switch x {
    case .String as s:
        ret s.len > 0usize
    default:
        ret true
    }
}

// --- instants ---------------------------------------------------------------------------------------------------------

// `new Date(v).getTime()`: a number as is, an ISO-8601 text parsed, anything else NaN.
fn to_ms(v: json.Value) -> f64 {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e == ok { ret x }
        ret nan()
    case .String as s:
        let (t, e) = time.parse_iso8601(s)
        if e != ok { ret nan() }
        var ms = t.nanos / 1000000i64
        if t.nanos < 0i64 && t.nanos % 1000000i64 != 0i64 { ms -= 1i64 }
        ret f64(ms)
    default:
        ret nan()
    }
}

// `new Date(ms).toISOString()`: `YYYY-MM-DDTHH:MM:SS.mmmZ`; an unrepresentable instant is an error, as appdor throws.
fn iso_ms(a: *mem.Arena, ms: f64) -> (str, err) {
    if !is_finite(ms) { ret ("", Invalid) }
    let whole = i64(ms)
    let (buf, buf_error) = mem.alloc[u8](a, 32usize)
    if buf_error != ok { ret ("", buf_error) }
    let full = time.format_iso8601(time.Timestamp { nanos: whole * 1000000i64 }, buf[0usize..32usize])
    if full.len < 30usize { ret ("", Invalid) }
    let (head, head_error) = str.concat(a, full[0usize..23usize], "Z")
    ret (head, head_error)
}

// `Number(v) || fallback`: a number, a numeric text, a boolean; null, an empty or unparsable text and NaN fall back.
fn number_or(v: json.Value, fallback: f64) -> f64 {
    var x = 0.0f64
    switch v {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        if e == ok { x = value }
    case .String as s:
        x = parse_decimal(str.trim(s))
    case .Bool as b:
        if b { x = 1.0f64 }
    default:
        x = 0.0f64
    }
    if x != x || x == 0.0f64 { ret fallback }
    ret x
}

fn parse_decimal(s: str) -> f64 {
    if s.len == 0usize { ret 0.0f64 }
    var at = 0usize
    var sign = 1.0f64
    if s[0] == 45u8 {
        sign = -1.0f64
        at = 1usize
    } else if s[0] == 43u8 {
        at = 1usize
    }
    var whole = 0.0f64
    var digits = 0usize
    while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 {
        whole = whole * 10.0f64 + f64(s[at] - 48u8)
        digits += 1usize
        at += 1usize
    }
    var scale = 0.1f64
    if at < s.len && s[at] == 46u8 {
        at += 1usize
        while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 {
            whole = whole + f64(s[at] - 48u8) * scale
            scale = scale / 10.0f64
            digits += 1usize
            at += 1usize
        }
    }
    if digits == 0usize || at != s.len { ret nan() }
    ret sign * whole
}

fn max_f(x: f64, y: f64) -> f64 {
    if x > y { ret x }
    ret y
}

fn min_f(x: f64, y: f64) -> f64 {
    if x < y { ret x }
    ret y
}

// --- the schedule -----------------------------------------------------------------------------------------------------

// Whether a worker may claim the binding: unclaimed, claimed by itself, or its lease has run out.
fn lease_available(row: json.Value, me: str, now: json.Value) -> bool {
    let (by, have_by) = get(row, "claimed_by")
    if !have_by || !ir.truthy(by) { ret true }
    if str.eq(as_text(by), me) { ret true }
    let (at, have_at) = get(row, "claimed_at")
    if !have_at || !ir.truthy(at) { ret true }
    let age = to_ms(now) - to_ms(at)
    ret is_finite(age) && age > sync_lease_ms()
}

fn status_of(row: json.Value) -> str {
    let (s, is_text) = ir.string_of(ir.value_of(row, "status"))
    if !is_text { ret "" }
    ret s
}

fn next_run_text(row: json.Value) -> str {
    let (x, found) = get(row, "next_run_at")
    if !found || !ir.truthy(x) { ret "" }
    ret as_text(x)
}

// The bindings due at `now`, soonest first (a binding with no `next_run_at` is due and sorts first).
fn due_bindings(a: *mem.Arena, rows: []const json.Value, now: json.Value) -> []const json.Value {
    let at = to_ms(now)
    var kept = empty_list(a)
    var i = 0usize
    while i < rows.len {
        let r = rows[i]
        let status = status_of(r)
        if ir.truthy(r) && (str.eq(status, "active") || str.eq(status, "error")) {
            var due = true
            let (next, have_next) = get(r, "next_run_at")
            if have_next && ir.truthy(next) {
                let due_at = to_ms(next)
                due = !is_finite(due_at) || due_at <= at
            }
            if due { push_value(&kept, r) }
        }
        i += 1usize
    }
    // binary insertion sort, as the engine's, so equal keys keep their order
    var n = 1usize
    while n < kept.len {
        let pivot = kept.items[n]
        var left = 0usize
        var right = n
        while left < right {
            let mid = (left + right) / 2usize
            if str.compare(next_run_text(pivot), next_run_text(kept.items[mid])) < 0i32 { right = mid } else { left = mid + 1usize }
        }
        var k = n
        while k > left {
            kept.items[k] = kept.items[k - 1usize]
            k -= 1usize
        }
        kept.items[left] = pivot
        n += 1usize
    }
    ret list.slice_const[json.Value](&kept)
}

// Minutes to wait after the n-th consecutive failure: the interval doubled per failure, capped at six hours (never
// below the interval itself).
fn backoff_minutes(consecutive_failures: json.Value, interval_minutes: json.Value) -> f64 {
    let base = max_f(min_interval_minutes(), number_or(interval_minutes, 60.0f64))
    let n = max_f(1.0f64, number_or(consecutive_failures, 1.0f64))
    var power = min_f(n - 1.0f64, 20.0f64)
    var factor = 1.0f64
    var k = 0.0f64
    while k < power {
        factor = factor * 2.0f64
        k += 1.0f64
    }
    factor = min_f(factor, max_backoff_minutes())
    ret max_f(base, min_f(base * factor, max_f(base, max_backoff_minutes())))
}

// What the row becomes when a run finishes: `{status, next_run_at, last_run_at, consecutive_failures, claimed_by,
// claimed_at, updated_at}`. A failure (`failed`) backs off; a success resets the count.
fn schedule_after_run(a: *mem.Arena, row: json.Value, failed: bool, now: json.Value) -> (json.Value, err) {
    let finished = to_ms(now)
    let interval = max_f(min_interval_minutes(), number_or(ir.value_of(row, "interval_minutes"), 60.0f64))
    var failures = 0.0f64
    if failed { failures = number_or(ir.value_of(row, "consecutive_failures"), 0.0f64) + 1.0f64 }
    var minutes = interval
    if failed { minutes = backoff_minutes(number_value(a, failures), number_value(a, interval)) }
    let (next, next_error) = iso_ms(a, trunc(finished + minutes * 60000.0f64))
    if next_error != ok { ret (.Null, next_error) }
    let (last, last_error) = iso_ms(a, finished)
    if last_error != ok { ret (.Null, last_error) }
    var o = obj(a)
    if failed { put(&o, "status", text("error")) } else { put(&o, "status", text("active")) }
    put(&o, "next_run_at", text(next))
    put(&o, "last_run_at", text(last))
    put(&o, "consecutive_failures", number(a, i64(failures)))
    put(&o, "claimed_by", .Null)
    put(&o, "claimed_at", .Null)
    put(&o, "updated_at", text(last))
    ret (ir.obj_value(&o), ok)
}

fn trunc(x: f64) -> f64 {
    if !is_finite(x) { ret x }
    ret f64(i64(x))
}

fn number_value(a: *mem.Arena, x: f64) -> json.Value {
    let (n, e) = json.number_from_f64(a, x)
    if e != ok { ret json.Value{ Number: json.Number{ lexeme: "0" } } }
    ret json.Value{ Number: n }
}

// `{state, consecutiveFailures}`: detached, connection_removed, paused, failing (three in a row), flaky or ok.
fn binding_health(a: *mem.Arena, row: json.Value) -> json.Value {
    let failures = number_or(ir.value_of(row, "consecutive_failures"), 0.0f64)
    let status = status_of(row)
    var state = "ok"
    var shown = failures
    if str.eq(status, "detached") {
        state = "detached"
    } else if str.eq(status, "connection_removed") {
        state = "connection_removed"
    } else if str.eq(status, "paused") {
        state = "paused"
    } else if failures >= failing_after() {
        state = "failing"
    } else if failures > 0.0f64 {
        state = "flaky"
    } else {
        shown = 0.0f64
    }
    var o = obj(a)
    put(&o, "state", text(state))
    put(&o, "consecutiveFailures", number_value(a, shown))
    ret ir.obj_value(&o)
}

// `{softDelete, flag}`: a `flag` policy keeps the rows and marks them, anything else soft-deletes them.
fn apply_deletion_policy(a: *mem.Arena, deletes: []const json.Value, policy: str) -> json.Value {
    var o = obj(a)
    if str.eq(policy, "flag") {
        put(&o, "softDelete", json.Value{ Array: zero })
        put(&o, "flag", json.Value{ Array: deletes })
    } else {
        put(&o, "softDelete", json.Value{ Array: deletes })
        put(&o, "flag", json.Value{ Array: zero })
    }
    ret ir.obj_value(&o)
}

// Patches that mark rows the source lost: `{id, data: {_missingInSource: true}}` for each not already marked.
fn flag_plan(a: *mem.Arena, flagged: []const json.Value) -> json.Value {
    var out = empty_list(a)
    var i = 0usize
    while i < flagged.len {
        let r = flagged[i]
        let marked = strict_true(ir.value_of(r, "_missingInSource"))
        if ir.truthy(ir.value_of(r, "__rowId")) && !marked {
            var data = obj(a)
            put(&data, "_missingInSource", flag(true))
            var o = obj(a)
            put(&o, "id", ir.value_of(r, "__rowId"))
            put(&o, "data", ir.obj_value(&data))
            push_value(&out, ir.obj_value(&o))
        }
        i += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

fn strict_true(v: json.Value) -> bool {
    switch v {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

fn plain(a: *mem.Arena, v: json.Value) -> str {
    let (b, e) = str.builder(a, 64usize)
    if e != ok { ret "" }
    var out = b
    let written = write_plain(&out, v)
    if written != ok { ret "" }
    ret str.done(&out)
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

// `[{id, data: {_missingInSource: false}}]` for flagged local rows whose key is back in the remote rows.
fn unflag_plan(a: *mem.Arena, local_rows: []const json.Value, remote_rows: []const json.Value, sync_key: str) -> json.Value {
    var present = empty_list(a)
    var i = 0usize
    while i < remote_rows.len {
        if ir.truthy(remote_rows[i]) && has_value(remote_rows[i], sync_key) {
            push_value(&present, text(plain(a, ir.value_of(remote_rows[i], sync_key))))
        }
        i += 1usize
    }
    var out = empty_list(a)
    var j = 0usize
    while j < local_rows.len {
        let r = local_rows[j]
        if ir.truthy(ir.value_of(r, "__rowId")) && strict_true(ir.value_of(r, "_missingInSource")) {
            let key = plain(a, ir.value_of(r, sync_key))
            var found = false
            var k = 0usize
            while k < present.len {
                if str.eq(as_text(present.items[k]), key) { found = true }
                k += 1usize
            }
            if found {
                var data = obj(a)
                put(&data, "_missingInSource", flag(false))
                var o = obj(a)
                put(&o, "id", ir.value_of(r, "__rowId"))
                put(&o, "data", ir.obj_value(&data))
                push_value(&out, ir.obj_value(&o))
            }
        }
        j += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

// --- refusals ---------------------------------------------------------------------------------------------------------

fn is_sql_address_code(code: str) -> bool {
    if !str.starts_with(code, "sql-address-") || code.len <= 12usize { ret false }
    var at = 12usize
    while at < code.len {
        let c = code[at]
        if !((c >= 97u8 && c <= 122u8) || c == 45u8) { ret false }
        at += 1usize
    }
    ret true
}

// The catalogue key for a refusal code, or absent for one this does not know.
fn sync_refusal_key(code: str) -> (str, bool) {
    if str.eq(code, "sql-sources-not-configured") || str.eq(code, "sql-host-not-allowed") { ret ("sync.refusal.sqlHostNotAllowed", true) }
    if str.eq(code, "sql-source-unresolved") { ret ("sync.refusal.sqlUnresolved", true) }
    if is_sql_address_code(code) { ret ("sync.refusal.sqlAddressRefused", true) }
    ret ("", false)
}

// The words for a refusal: the host's translation of its key (naming the `SQL_SOURCE_HOSTS` setting), or the code.
fn describe_sync_refusal(code: str, translate: *const Translate) -> str {
    let (key, known) = sync_refusal_key(code)
    if !known { ret code }
    ret translate.run(translate.ctx, key, "SQL_SOURCE_HOSTS")
}

// --- the pull ---------------------------------------------------------------------------------------------------------

// A value as stored in a synced column: a structured column holds its JSON text, a missing value is null.
fn coerce_value(a: *mem.Arena, structured: bool, value: json.Value, has: bool) -> json.Value {
    if !has { ret .Null }
    if structured {
        if ir.is_null(value) { ret .Null }
        ret text(plain(a, value))
    }
    ret value
}

fn in_values(values: []const json.Value, v: json.Value) -> bool {
    var at = 0usize
    while at < values.len {
        if same_scalar(values[at], v) { ret true }
        at += 1usize
    }
    ret false
}

fn same_scalar(x: json.Value, y: json.Value) -> bool {
    switch x {
    case .Null:
        switch y {
        case .Null:
            ret true
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
    case .Number as nx:
        switch y {
        case .Number as ny:
            let (fx, ex) = json.number_f64(nx)
            let (fy, ey) = json.number_f64(ny)
            ret ex == ok && ey == ok && fx == fy
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
    default:
        ret false
    }
}

// Is the chosen sync key usable against the columns and a sample? `{ok: true}` or `{ok: false, reason, message
// [, duplicates]}` with reason missing, unknown-column, blank-values or duplicate-values.
fn validate_sync_key(a: *mem.Arena, columns: []const json.Value, sync_key: str, has_key: bool, sample: []const json.Value) -> json.Value {
    var o = obj(a)
    if !has_key || sync_key.len == 0usize {
        put(&o, "ok", flag(false))
        put(&o, "reason", text("missing"))
        put(&o, "message", text("Required"))
        ret ir.obj_value(&o)
    }
    var known = false
    var c = 0usize
    while c < columns.len {
        if str.eq(as_text(ir.value_of(columns[c], "name")), sync_key) { known = true }
        c += 1usize
    }
    if !known {
        put(&o, "ok", flag(false))
        put(&o, "reason", text("unknown-column"))
        put(&o, "message", text("Unknown column"))
        ret ir.obj_value(&o)
    }
    var seen = empty_list(a)
    var duplicates = empty_list(a)
    var blanks = 0i64
    var r = 0usize
    while r < sample.len {
        if !has_value(sample[r], sync_key) {
            blanks += 1i64
        } else {
            let value = ir.value_of(sample[r], sync_key)
            let k = plain(a, value)
            var found = false
            var s = 0usize
            while s < seen.len {
                if str.eq(as_text(seen.items[s]), k) { found = true }
                s += 1usize
            }
            if found {
                if !in_values(list.slice_const[json.Value](&duplicates), value) { push_value(&duplicates, value) }
            } else {
                push_value(&seen, text(k))
            }
        }
        r += 1usize
    }
    if blanks > 0i64 {
        put(&o, "ok", flag(false))
        put(&o, "reason", text("blank-values"))
        put(&o, "message", text("Blank values"))
        ret ir.obj_value(&o)
    }
    if duplicates.len > 0usize {
        put(&o, "ok", flag(false))
        put(&o, "reason", text("duplicate-values"))
        put(&o, "message", text("Duplicate values"))
        put(&o, "duplicates", json.Value{ Array: list.slice_const[json.Value](&duplicates) })
        ret ir.obj_value(&o)
    }
    put(&o, "ok", flag(true))
    ret ir.obj_value(&o)
}

// Split remote rows into those with a unique key and those without one: `{accepted, quarantined}`, a quarantined entry
// being `{row, reason}` with reason missing-sync-key or duplicate-sync-key.
fn quarantine_by_key(a: *mem.Arena, remote_rows: []const json.Value, sync_key: str) -> json.Value {
    var keys = empty_list(a)
    var counts = empty_list(a)
    var i = 0usize
    while i < remote_rows.len {
        if ir.truthy(remote_rows[i]) && has_value(remote_rows[i], sync_key) {
            let k = plain(a, ir.value_of(remote_rows[i], sync_key))
            var index = keys.len
            var s = 0usize
            while s < keys.len {
                if str.eq(as_text(keys.items[s]), k) { index = s }
                s += 1usize
            }
            if index == keys.len {
                push_value(&keys, text(k))
                push_value(&counts, number(a, 1i64))
            } else {
                counts.items[index] = number(a, count_of(counts.items[index]) + 1i64)
            }
        }
        i += 1usize
    }
    var accepted = empty_list(a)
    var quarantined = empty_list(a)
    var j = 0usize
    while j < remote_rows.len {
        let row = remote_rows[j]
        var reason = ""
        if !(ir.truthy(row) && has_value(row, sync_key)) {
            reason = "missing-sync-key"
        } else {
            let k = plain(a, ir.value_of(row, sync_key))
            var s = 0usize
            while s < keys.len {
                if str.eq(as_text(keys.items[s]), k) && count_of(counts.items[s]) > 1i64 { reason = "duplicate-sync-key" }
                s += 1usize
            }
        }
        if reason.len > 0usize {
            var q = obj(a)
            put(&q, "row", row)
            put(&q, "reason", text(reason))
            push_value(&quarantined, ir.obj_value(&q))
        } else {
            push_value(&accepted, row)
        }
        j += 1usize
    }
    var o = obj(a)
    put(&o, "accepted", json.Value{ Array: list.slice_const[json.Value](&accepted) })
    put(&o, "quarantined", json.Value{ Array: list.slice_const[json.Value](&quarantined) })
    ret ir.obj_value(&o)
}

fn count_of(v: json.Value) -> i64 {
    switch v {
    case .Number as n:
        let (x, e) = json.number_i64(n)
        if e == ok { ret x }
        ret 0i64
    default:
        ret 0i64
    }
}

fn row_field(row: json.Value, key: str) -> (json.Value, bool) {
    let (x, found) = get(row, key)
    ret (x, found)
}

fn row_differs(a: *mem.Arena, x: json.Value, y: json.Value, fields: []const str, has_fields: bool) -> bool {
    var keys = empty_list(a)
    if has_fields {
        var f = 0usize
        while f < fields.len {
            push_value(&keys, text(fields[f]))
            f += 1usize
        }
    } else {
        let (xm, x_obj) = ir.members_of(x)
        let (ym, y_obj) = ir.members_of(y)
        var i = 0usize
        while x_obj && i < xm.len {
            push_value(&keys, text(xm[i].key))
            i += 1usize
        }
        var j = 0usize
        while y_obj && j < ym.len {
            var present = false
            var k = 0usize
            while k < keys.len {
                if str.eq(as_text(keys.items[k]), ym[j].key) { present = true }
                k += 1usize
            }
            if !present { push_value(&keys, text(ym[j].key)) }
            j += 1usize
        }
    }
    var at = 0usize
    while at < keys.len {
        let key = as_text(keys.items[at])
        let (vx, hx) = row_field(x, key)
        let (vy, hy) = row_field(y, key)
        if hx != hy { ret true }
        if hx && !str.eq(plain(a, vx), plain(a, vy)) { ret true }
        at += 1usize
    }
    ret false
}

// The key of a row as the Map in appdor holds it: scalars by value, a missing key as itself.
fn key_equal(x: json.Value, hx: bool, y: json.Value, hy: bool) -> bool {
    if !hx && !hy { ret true }
    if hx != hy { ret false }
    ret same_scalar(x, y)
}

// The insert, update and delete lists that make local rows equal remote ones, keyed on `key_field`:
// `{inserts, updates: [{key, local, remote}], deletes, bulkLoad}`.
fn sync_plan(a: *mem.Arena, local_rows: []const json.Value, remote_rows: []const json.Value, key_field: str, fields: []const str, has_fields: bool, bulk_load: bool) -> json.Value {
    var local_keys = empty_list(a)
    var local_by = empty_list(a)
    var local_have = empty_list(a)
    var i = 0usize
    while i < local_rows.len {
        let (k, h) = row_field(local_rows[i], key_field)
        var index = local_keys.len
        var s = 0usize
        while s < local_keys.len {
            if key_equal(local_keys.items[s], strict_true(local_have.items[s]), k, h) { index = s }
            s += 1usize
        }
        if index == local_keys.len {
            push_value(&local_keys, k)
            push_value(&local_have, flag(h))
            push_value(&local_by, local_rows[i])
        } else {
            local_by.items[index] = local_rows[i]
        }
        i += 1usize
    }
    var remote_keys = empty_list(a)
    var remote_by = empty_list(a)
    var remote_have = empty_list(a)
    var j = 0usize
    while j < remote_rows.len {
        let (k, h) = row_field(remote_rows[j], key_field)
        var index = remote_keys.len
        var s = 0usize
        while s < remote_keys.len {
            if key_equal(remote_keys.items[s], strict_true(remote_have.items[s]), k, h) { index = s }
            s += 1usize
        }
        if index == remote_keys.len {
            push_value(&remote_keys, k)
            push_value(&remote_have, flag(h))
            push_value(&remote_by, remote_rows[j])
        } else {
            remote_by.items[index] = remote_rows[j]
        }
        j += 1usize
    }
    var inserts = empty_list(a)
    var updates = empty_list(a)
    var deletes = empty_list(a)
    var r = 0usize
    while r < remote_by.len {
        var match_at = local_keys.len
        var s = 0usize
        while s < local_keys.len {
            if key_equal(local_keys.items[s], strict_true(local_have.items[s]), remote_keys.items[r], strict_true(remote_have.items[r])) { match_at = s }
            s += 1usize
        }
        if match_at == local_keys.len {
            push_value(&inserts, remote_by.items[r])
        } else if row_differs(a, local_by.items[match_at], remote_by.items[r], fields, has_fields) {
            var u = obj(a)
            if strict_true(remote_have.items[r]) { put(&u, "key", remote_keys.items[r]) }
            put(&u, "local", local_by.items[match_at])
            put(&u, "remote", remote_by.items[r])
            push_value(&updates, ir.obj_value(&u))
        }
        r += 1usize
    }
    var l = 0usize
    while l < local_by.len {
        var found = false
        var s = 0usize
        while s < remote_keys.len {
            if key_equal(remote_keys.items[s], strict_true(remote_have.items[s]), local_keys.items[l], strict_true(local_have.items[l])) { found = true }
            s += 1usize
        }
        if !found { push_value(&deletes, local_by.items[l]) }
        l += 1usize
    }
    var o = obj(a)
    put(&o, "inserts", json.Value{ Array: list.slice_const[json.Value](&inserts) })
    put(&o, "updates", json.Value{ Array: list.slice_const[json.Value](&updates) })
    put(&o, "deletes", json.Value{ Array: list.slice_const[json.Value](&deletes) })
    put(&o, "bulkLoad", flag(bulk_load))
    ret ir.obj_value(&o)
}

// One pull's plan: quarantine, diff, and (for a truncated pull) no deletions. `{inserts, updates, deletes, bulkLoad,
// quarantined, partial}`.
fn plan_pull(a: *mem.Arena, local_rows: []const json.Value, remote_rows: []const json.Value, sync_key: str, fields: []const str, partial: bool) -> json.Value {
    let split = quarantine_by_key(a, remote_rows, sync_key)
    let plan = sync_plan(a, local_rows, items(ir.value_of(split, "accepted")), sync_key, fields, fields.len > 0usize, local_rows.len == 0usize)
    var o = obj(a)
    put(&o, "inserts", ir.value_of(plan, "inserts"))
    put(&o, "updates", ir.value_of(plan, "updates"))
    if partial { put(&o, "deletes", json.Value{ Array: zero }) } else { put(&o, "deletes", ir.value_of(plan, "deletes")) }
    put(&o, "bulkLoad", ir.value_of(plan, "bulkLoad"))
    put(&o, "quarantined", ir.value_of(split, "quarantined"))
    put(&o, "partial", flag(partial))
    ret ir.obj_value(&o)
}

// Where a pull's writes come from: `sync` for a bulk load (no record-created triggers), `connector` otherwise.
fn pull_write_origin(plan: json.Value) -> str {
    if strict_true(ir.value_of(plan, "bulkLoad")) { ret "sync" }
    ret "connector"
}

// The ledger row for one run: counts from the plan, a status, and the duration when both instants are valid.
fn run_ledger_row(a: *mem.Arena, synced_table_id: json.Value, trigger: json.Value, plan: json.Value, failure: json.Value, started: json.Value, finished: json.Value) -> json.Value {
    var started_at = nan()
    if ir.truthy(started) { started_at = to_ms(started) }
    var finished_at = nan()
    if ir.truthy(finished) { finished_at = to_ms(finished) }
    var o = obj(a)
    put(&o, "synced_table_id", synced_table_id)
    put(&o, "trigger", trigger)
    if ir.truthy(failure) { put(&o, "status", text("failed")) } else { put(&o, "status", text("completed")) }
    put(&o, "rows_added", number(a, i64(items(ir.value_of(plan, "inserts")).len)))
    put(&o, "rows_updated", number(a, i64(items(ir.value_of(plan, "updates")).len)))
    put(&o, "rows_removed", number(a, i64(items(ir.value_of(plan, "deletes")).len)))
    put(&o, "rows_quarantined", number(a, i64(items(ir.value_of(plan, "quarantined")).len)))
    put(&o, "bulk_load", flag(strict_true(ir.value_of(plan, "bulkLoad"))))
    if ir.truthy(failure) { put(&o, "error", failure) } else { put(&o, "error", .Null) }
    if ir.truthy(started) { put(&o, "started_at", started) } else { put(&o, "started_at", .Null) }
    if ir.truthy(finished) { put(&o, "finished_at", finished) } else { put(&o, "finished_at", .Null) }
    if is_finite(started_at) && is_finite(finished_at) && finished_at >= started_at {
        put(&o, "duration_ms", number(a, i64(finished_at - started_at)))
    } else {
        put(&o, "duration_ms", .Null)
    }
    ret ir.obj_value(&o)
}

// When the next scheduled pull runs: the interval (at least five minutes, an hour by default) after `now`.
fn next_run_at(a: *mem.Arena, row: json.Value, now: json.Value) -> (str, err) {
    let minutes = max_f(min_interval_minutes(), number_or(ir.value_of(row, "interval_minutes"), 60.0f64))
    let (at, at_error) = iso_ms(a, trunc(to_ms(now) + minutes * 60000.0f64))
    ret (at, at_error)
}

// The records array of a response body: the body itself or the first of data, records, value, items, results.
fn records_from_body(body: json.Value) -> (json.Value, bool) {
    let (xs, is_array) = ir.items_of(body)
    if is_array { ret (body, true) }
    let (members, is_object) = ir.members_of(body)
    if !is_object { ret (.Null, false) }
    var names: [5]str = zero
    names[0] = "data"
    names[1] = "records"
    names[2] = "value"
    names[3] = "items"
    names[4] = "results"
    var at = 0usize
    while at < 5usize {
        let (x, found) = get(body, names[at])
        if found {
            let (ys, y_array) = ir.items_of(x)
            if y_array { ret (x, true) }
        }
        at += 1usize
    }
    ret (.Null, false)
}

// --- drift --------------------------------------------------------------------------------------------------------------

fn find_named(rows: []const json.Value, name: str) -> (json.Value, bool) {
    var found = false
    var out: json.Value = .Null
    var at = 0usize
    while at < rows.len {
        if str.eq(as_text(ir.value_of(rows[at], "name")), name) {
            out = rows[at]
            found = true
        }
        at += 1usize
    }
    ret (out, found)
}

// How a stored column mapping differs from the columns the source now shows: `{drifted, missingInSource, added,
// typeChanged, unchanged}`.
fn drift_report(a: *mem.Arena, stored: []const json.Value, observed: []const json.Value) -> json.Value {
    var missing = empty_list(a)
    var added = empty_list(a)
    var changed = empty_list(a)
    var i = 0usize
    while i < stored.len {
        let c = stored[i]
        if ir.truthy(c) && !strict_true(ir.value_of(c, "missingInSource")) {
            let name = as_text(ir.value_of(c, "name"))
            let (now, present) = find_named(observed, name)
            if !present {
                var m = obj(a)
                put(&m, "name", text(name))
                var kind = "text"
                let (given, have_given) = get(c, "lc8Type")
                if have_given && ir.truthy(given) { kind = as_text(given) }
                put(&m, "lc8Type", text(kind))
                push_value(&missing, ir.obj_value(&m))
            } else {
                let was = ir.value_of(c, "nativeType")
                let to = ir.value_of(now, "nativeType")
                if ir.truthy(was) && ir.truthy(to) && !str.eq(plain(a, was), plain(a, to)) {
                    var t = obj(a)
                    put(&t, "name", text(name))
                    put(&t, "from", was)
                    put(&t, "to", to)
                    let (would, have_would) = get(now, "lc8Type")
                    if have_would { put(&t, "wouldBecome", would) } else { put(&t, "wouldBecome", .Null) }
                    put(&t, "downgraded", flag(strict_true(ir.value_of(now, "downgraded"))))
                    let (d, have_d) = get(now, "diagnostic")
                    if have_d && ir.truthy(d) { put(&t, "diagnostic", d) } else { put(&t, "diagnostic", .Null) }
                    push_value(&changed, ir.obj_value(&t))
                }
            }
        }
        i += 1usize
    }
    var j = 0usize
    while j < observed.len {
        let name = as_text(ir.value_of(observed[j], "name"))
        var mapped = false
        var k = 0usize
        while k < stored.len {
            if ir.truthy(stored[k]) && !strict_true(ir.value_of(stored[k], "missingInSource")) && str.eq(as_text(ir.value_of(stored[k], "name")), name) { mapped = true }
            k += 1usize
        }
        if !mapped {
            let (current, ok_current) = find_named(observed, name)
            var col = obj(a)
            put(&col, "name", ir.value_of(current, "name"))
            put(&col, "nativeType", ir.value_of(current, "nativeType"))
            put(&col, "lc8Type", ir.value_of(current, "lc8Type"))
            put(&col, "downgraded", flag(strict_true(ir.value_of(current, "downgraded"))))
            let (d, have_d) = get(current, "diagnostic")
            if have_d && ir.truthy(d) { put(&col, "diagnostic", d) } else { put(&col, "diagnostic", .Null) }
            put(&col, "structured", flag(strict_true(ir.value_of(current, "structured"))))
            push_value(&added, ir.obj_value(&col))
        }
        j += 1usize
    }
    var o = obj(a)
    put(&o, "drifted", flag(missing.len > 0usize || changed.len > 0usize || added.len > 0usize))
    put(&o, "missingInSource", json.Value{ Array: list.slice_const[json.Value](&missing) })
    put(&o, "added", json.Value{ Array: list.slice_const[json.Value](&added) })
    put(&o, "typeChanged", json.Value{ Array: list.slice_const[json.Value](&changed) })
    put(&o, "unchanged", number(a, i64(stored.len) - i64(missing.len) - i64(changed.len)))
    ret ir.obj_value(&o)
}

// Accept a drift report into the stored mapping: lost columns are marked missing, retyped ones take the new type, and
// the offered new columns named in `add` are appended. `{mapping, addedColumns}`.
fn accept_drift(a: *mem.Arena, stored: []const json.Value, report: json.Value, add: []const str) -> json.Value {
    let missing = items(ir.value_of(report, "missingInSource"))
    let retyped = items(ir.value_of(report, "typeChanged"))
    let offered = items(ir.value_of(report, "added"))
    var mapping = empty_list(a)
    var i = 0usize
    while i < stored.len {
        let col = stored[i]
        let name = as_text(ir.value_of(col, "name"))
        let (gone, is_gone) = find_named(missing, name)
        if is_gone {
            var o = obj(a)
            let assigned = ir.assign(&o, col)
            put(&o, "missingInSource", flag(true))
            push_value(&mapping, ir.obj_value(&o))
        } else {
            let (change, is_changed) = find_named(retyped, name)
            if !is_changed {
                push_value(&mapping, col)
            } else {
                var o = obj(a)
                let assigned = ir.assign(&o, col)
                put(&o, "nativeType", ir.value_of(change, "to"))
                let would = ir.value_of(change, "wouldBecome")
                if ir.truthy(would) { put(&o, "lc8Type", would) } else { put(&o, "lc8Type", ir.value_of(col, "lc8Type")) }
                let downgraded = strict_true(ir.value_of(change, "downgraded"))
                put(&o, "downgraded", flag(downgraded))
                let (d, have_d) = get(change, "diagnostic")
                if downgraded && have_d && ir.truthy(d) { put(&o, "diagnostic", d) } else { put(&o, "diagnostic", .Null) }
                push_value(&mapping, ir.obj_value(&o))
            }
        }
        i += 1usize
    }
    var added_columns = empty_list(a)
    var seen = empty_list(a)
    var w = 0usize
    while w < add.len {
        var done = false
        var s = 0usize
        while s < seen.len {
            if str.eq(as_text(seen.items[s]), add[w]) { done = true }
            s += 1usize
        }
        if !done {
            push_value(&seen, text(add[w]))
            let (col, offered_has) = find_named(offered, add[w])
            if offered_has {
                let (existing, exists) = find_named(list.slice_const[json.Value](&mapping), add[w])
                if !exists {
                    push_value(&added_columns, col)
                    push_value(&mapping, col)
                }
            }
        }
        w += 1usize
    }
    var o = obj(a)
    put(&o, "mapping", json.Value{ Array: list.slice_const[json.Value](&mapping) })
    put(&o, "addedColumns", json.Value{ Array: list.slice_const[json.Value](&added_columns) })
    ret ir.obj_value(&o)
}
