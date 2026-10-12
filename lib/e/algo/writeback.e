// The push half of two-way sync (L037), after appdor's `src/sync/writeback.js` with the outbox model of
// `src/connectors/writeback-outbox.js` and the mapping, merge and echo halves of `src/connectors/sync-engine.js`:
//
//   * the outbox entry and its lifecycle: created pending, a delivery attempt recorded (delivered, retry, or dead-lettered
//     after `maxAttempts`), the field-level reversion planned for a dead letter, the entry marked reverted, and the
//     summary of an outbox;
//   * the host's judgements: which mapped columns are two-way (a column with no direction is pull-only), the mapping in
//     the engine's shape, an entry from a persisted row and the patch an entry implies, the revert patch (the last
//     confirmed value back, the rejected value kept beside it under `_writebackRejected`), the echo set of delivered
//     writebacks and the pull updates it suppresses, and the one line a status panel shows;
//   * the engine: `mapRemoteToLocal` / `mapLocalToRemote` with per-field direction, and the three-way merge
//     `planTwoWaySync` (local-only change pushes, remote-only pulls, both changed is a conflict resolved by policy or
//     queued), and the SSRF-checked request builder `buildRequest` with the PATCH push.
//
// Values are JSON. The clock and the entry id are arguments, never read: `now_iso` is the instant an operation takes
// place and `id` is the entry id a creation gets. A transform function of a mapping cannot cross as JSON and is not
// carried. Words come back through the host's translator (the catalogue key and the count as text).
//
// ponytail: the host name is read by `e.net.ssrf.parse_href` (ASCII names, WHATWG IPv4 forms); the request's query is the
// form-urlencoded text of `URLSearchParams`.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.algo.sync as sync
use e.algo.syncjob as syncjob
use e.data.list as list
use e.fmt.encode as encode
use e.fmt.json as json
use e.mem
use e.net.ssrf as ssrf
use e.str

// The key a rejected writeback is preserved under, on the record itself.
fn rejected_key() -> str { ret "_writebackRejected" }

fn default_max_attempts() -> i64 { ret 5i64 }

// --- helpers ---------------------------------------------------------------------------------------------------------

// `String(value)`; an absent value is `"undefined"`, an array its elements joined by commas (null ones empty).
fn js_string(a: *mem.Arena, v: json.Value, present: bool) -> str {
    if !present { ret "undefined" }
    switch v {
    case .Null:
        ret "null"
    case .Array as xs:
        var out = ""
        var at = 0usize
        while at < xs.len {
            if at > 0usize { out = sync.cat(a, out, ",") }
            if !ir.is_null(xs[at]) { out = sync.cat(a, out, js_string(a, xs[at], true)) }
            at += 1usize
        }
        ret out
    case .Object as ms:
        ret "[object Object]"
    default:
        ret sync.as_text(v)
    }
}

// `JSON.stringify(v ?? null)`.
fn hash_of(a: *mem.Arena, v: json.Value) -> str { ret syncjob.plain(a, v) }

// The texts of an array value (an element that is not text reads as empty).
fn strings_of(a: *mem.Arena, v: json.Value) -> []const str {
    let (xs, is_array) = ir.items_of(v)
    if !is_array { ret zero }
    let (buf, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { ret zero }
    var at = 0usize
    while at < xs.len {
        let (s, is_text) = ir.string_of(xs[at])
        if is_text { buf[at] = s } else { buf[at] = "" }
        at += 1usize
    }
    ret buf[0usize..xs.len]
}

fn array_of(a: *mem.Arena, l: list.List[json.Value]) -> json.Value { ret json.Value{ Array: list.slice_const[json.Value](&l) } }

fn empty_obj() -> json.Value { ret ir.empty_object() }

fn str_member(v: json.Value, key: str) -> str {
    let (s, found) = sync.member_text(v, key)
    if !found { ret "" }
    ret s
}

// `a === 'text'` for a member.
fn member_is(v: json.Value, key: str, want: str) -> bool {
    let (s, found) = sync.member_text(v, key)
    ret found && str.eq(s, want)
}

// `PUSH_DIRECTIONS.includes(c.direction)`.
fn pushes(v: json.Value) -> bool { ret member_is(v, "direction", "both") || member_is(v, "direction", "push") }

fn strict_true(v: json.Value, key: str) -> bool {
    let (x, found) = sync.get(v, key)
    if !found { ret false }
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

// A copy of an object value's members.
fn copy_of(a: *mem.Arena, v: json.Value) -> ir.Obj {
    var o = sync.obj(a)
    let copied = ir.assign(&o, v)
    ret o
}

// --- the outbox model ------------------------------------------------------------------------------------------------

// A new pending entry: `{id, connectionId, tableId, recordKey, payload, status, attempts, maxAttempts, errors,
// lastConfirmedValue, createdAt, lastAttemptAt, deliveredAt, deadLetteredAt}`.
fn create_entry(a: *mem.Arena, opts: json.Value, id: str, now_iso: str) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, "id", sync.text(id))
    sync.put(&o, "connectionId", ir.or_falsy(opts, "connectionId", sync.text("")))
    sync.put(&o, "tableId", ir.or_falsy(opts, "tableId", sync.text("")))
    sync.put(&o, "recordKey", ir.or_falsy(opts, "recordKey", sync.text("")))
    sync.put(&o, "payload", ir.or_falsy(opts, "payload", empty_obj()))
    sync.put(&o, "status", sync.text("pending"))
    sync.put(&o, "attempts", sync.number(a, 0i64))
    sync.put(&o, "maxAttempts", ir.or_falsy(opts, "maxAttempts", sync.number(a, default_max_attempts())))
    sync.put(&o, "errors", ir.empty_array())
    sync.put(&o, "lastConfirmedValue", ir.or_falsy(opts, "lastConfirmedValue", .Null))
    sync.put(&o, "createdAt", sync.text(now_iso))
    sync.put(&o, "lastAttemptAt", .Null)
    sync.put(&o, "deliveredAt", .Null)
    sync.put(&o, "deadLetteredAt", .Null)
    ret ir.obj_value(&o)
}

// `{entry, terminal, action}` for one delivery attempt: `delivered`, `retry`, or `dead_lettered` once the attempts reach
// `maxAttempts`. `result` is `{ok, error?, sourceError?: {code?, message?}}`.
fn record_delivery(a: *mem.Arena, entry: json.Value, result: json.Value, now_iso: str) -> json.Value {
    var out = sync.obj(a)
    if !ir.truthy(entry) {
        sync.put(&out, "terminal", sync.flag(false))
        sync.put(&out, "action", sync.text("retry"))
        ret ir.obj_value(&out)
    }
    var e = copy_of(a, entry)
    let attempts = sync.count_value(entry, "attempts", 0i64) + 1i64
    sync.put(&e, "attempts", sync.number(a, attempts))
    sync.put(&e, "lastAttemptAt", sync.text(now_iso))
    if ir.truthy(ir.value_of(result, "ok")) {
        sync.put(&e, "status", sync.text("delivered"))
        sync.put(&e, "deliveredAt", sync.text(now_iso))
        sync.put(&out, "entry", ir.obj_value(&e))
        sync.put(&out, "terminal", sync.flag(true))
        sync.put(&out, "action", sync.text("delivered"))
        ret ir.obj_value(&out)
    }
    var message: json.Value = sync.text("delivery failed")
    let source_error = ir.value_of(result, "sourceError")
    let own_error = ir.value_of(result, "error")
    if ir.truthy(source_error) {
        let code = ir.or_falsy(source_error, "code", sync.text("REJECTED"))
        let detail = ir.or_falsy(source_error, "message", ir.or_falsy(result, "error", sync.text("unknown")))
        let line = sync.cat(a, sync.cat(a, js_string(a, code, true), ": "), js_string(a, detail, true))
        message = sync.text(line)
    } else if ir.truthy(own_error) {
        message = own_error
    }
    var errors = sync.empty_list(a)
    let (past, is_array) = ir.items_of(ir.value_of(entry, "errors"))
    if is_array {
        var at = 0usize
        while at < past.len {
            sync.push_value(&errors, past[at])
            at += 1usize
        }
    }
    sync.push_value(&errors, message)
    sync.put(&e, "errors", array_of(a, errors))
    let limit = sync.count_value(entry, "maxAttempts", 0i64)
    if attempts >= limit {
        sync.put(&e, "status", sync.text("dead_lettered"))
        sync.put(&e, "deadLetteredAt", sync.text(now_iso))
        sync.put(&out, "entry", ir.obj_value(&e))
        sync.put(&out, "terminal", sync.flag(true))
        sync.put(&out, "action", sync.text("dead_lettered"))
        ret ir.obj_value(&out)
    }
    sync.put(&e, "status", sync.text("failed"))
    sync.put(&out, "entry", ir.obj_value(&e))
    sync.put(&out, "terminal", sync.flag(false))
    sync.put(&out, "action", sync.text("retry"))
    ret ir.obj_value(&out)
}

// `{reversions, unrevertable, empty}` for a dead-lettered entry: each pushed field with a last confirmed value goes back
// to it; one without is unrevertable and left alone.
fn plan_reversion(a: *mem.Arena, entry: json.Value) -> json.Value {
    var out = sync.obj(a)
    var reversions = sync.obj(a)
    var unrevertable = sync.empty_list(a)
    if !ir.truthy(entry) || !member_is(entry, "status", "dead_lettered") {
        sync.put(&out, "reversions", empty_obj())
        sync.put(&out, "unrevertable", ir.empty_array())
        sync.put(&out, "empty", sync.flag(true))
        ret ir.obj_value(&out)
    }
    let (fields, is_object) = ir.members_of(ir.value_of(entry, "payload"))
    let confirmed = ir.or_falsy(entry, "lastConfirmedValue", empty_obj())
    var at = 0usize
    while at < fields.len {
        let (value, have) = sync.get(confirmed, fields[at].key)
        if have {
            sync.put(&reversions, fields[at].key, value)
        } else {
            sync.push_value(&unrevertable, sync.text(fields[at].key))
        }
        at += 1usize
    }
    let none = reversions.len == 0usize && unrevertable.len == 0usize
    sync.put(&out, "reversions", ir.obj_value(&reversions))
    sync.put(&out, "unrevertable", array_of(a, unrevertable))
    sync.put(&out, "empty", sync.flag(none))
    ret ir.obj_value(&out)
}

// The entry as reverted: `status: 'reverted'` with the fields it was put back to and the instant.
fn mark_reverted(a: *mem.Arena, entry: json.Value, reverted_fields: json.Value, now_iso: str) -> json.Value {
    if !ir.truthy(entry) { ret entry }
    var e = copy_of(a, entry)
    sync.put(&e, "status", sync.text("reverted"))
    sync.put(&e, "_revertedFields", reverted_fields)
    sync.put(&e, "_revertedAt", sync.text(now_iso))
    ret ir.obj_value(&e)
}

fn status_counter(status: str) -> str {
    if str.eq(status, "pending") { ret "pending" }
    if str.eq(status, "delivered") { ret "delivered" }
    if str.eq(status, "failed") { ret "failed" }
    if str.eq(status, "dead_lettered") { ret "deadLettered" }
    if str.eq(status, "reverted") { ret "reverted" }
    ret ""
}

// `{total, pending, delivered, failed, deadLettered, reverted, oldestPending}`. An unknown status counts in `total` only.
fn summarize_outbox(a: *mem.Arena, entries: []const json.Value) -> json.Value {
    var counts: [5]i64 = zero
    var oldest = ""
    var have_oldest = false
    var at = 0usize
    while at < entries.len {
        let status = str_member(entries[at], "status")
        let counter = status_counter(status)
        if str.eq(counter, "pending") { counts[0] += 1i64 }
        if str.eq(counter, "delivered") { counts[1] += 1i64 }
        if str.eq(counter, "failed") { counts[2] += 1i64 }
        if str.eq(counter, "deadLettered") { counts[3] += 1i64 }
        if str.eq(counter, "reverted") { counts[4] += 1i64 }
        if str.eq(status, "pending") || str.eq(status, "failed") {
            let created = str_member(entries[at], "createdAt")
            if !have_oldest || oldest.len == 0usize || str_less(created, oldest) {
                oldest = created
                have_oldest = true
            }
        }
        at += 1usize
    }
    var o = sync.obj(a)
    sync.put(&o, "total", sync.number(a, i64(entries.len)))
    sync.put(&o, "pending", sync.number(a, counts[0]))
    sync.put(&o, "delivered", sync.number(a, counts[1]))
    sync.put(&o, "failed", sync.number(a, counts[2]))
    sync.put(&o, "deadLettered", sync.number(a, counts[3]))
    sync.put(&o, "reverted", sync.number(a, counts[4]))
    if have_oldest { sync.put(&o, "oldestPending", sync.text(oldest)) } else { sync.put(&o, "oldestPending", .Null) }
    ret ir.obj_value(&o)
}

// `x < y` for texts: by code unit (these are ISO instants).
fn str_less(x: str, y: str) -> bool {
    var at = 0usize
    while at < x.len && at < y.len {
        if x[at] != y[at] { ret x[at] < y[at] }
        at += 1usize
    }
    ret x.len < y.len
}

// --- the host's judgements -------------------------------------------------------------------------------------------

// The names of the mapped columns that are two-way, in mapping order: not missing in the source, direction `both` or
// `push`. A column with no direction is pull-only.
fn two_way_fields(a: *mem.Arena, mapping: json.Value) -> json.Value {
    var out = sync.empty_list(a)
    let (columns, is_array) = ir.items_of(mapping)
    var at = 0usize
    while at < columns.len {
        let column = columns[at]
        at += 1usize
        let name = ir.value_of(column, "name")
        if !ir.truthy(column) || !ir.truthy(name) { continue }
        if strict_true(column, "missingInSource") { continue }
        if !pushes(column) { continue }
        sync.push_value(&out, name)
    }
    ret array_of(a, out)
}

// The mapping in the engine's shape: `[{remote, local, direction}]`, `remote` the column's `sourceName` or its name,
// `direction` `both` for a two-way column and `pull` otherwise.
fn writeback_mapping(a: *mem.Arena, mapping: json.Value) -> json.Value {
    var out = sync.empty_list(a)
    let (columns, is_array) = ir.items_of(mapping)
    var at = 0usize
    while at < columns.len {
        let column = columns[at]
        at += 1usize
        let name = ir.value_of(column, "name")
        if !ir.truthy(column) || !ir.truthy(name) { continue }
        var m = sync.obj(a)
        sync.put(&m, "remote", ir.or_falsy(column, "sourceName", name))
        sync.put(&m, "local", name)
        if pushes(column) { sync.put(&m, "direction", sync.text("both")) } else { sync.put(&m, "direction", sync.text("pull")) }
        sync.push_value(&out, ir.obj_value(&m))
    }
    ret array_of(a, out)
}

// An entry from a persisted `writeback_outbox` row, over the shape a creation gives.
fn entry_from_row(a: *mem.Arena, row: json.Value, id: str, now_iso: str) -> json.Value {
    var opts = sync.obj(a)
    sync.put(&opts, "connectionId", ir.or_falsy(row, "connection_id", sync.text("")))
    sync.put(&opts, "tableId", ir.or_falsy(row, "table_id", sync.text("")))
    sync.put(&opts, "recordKey", ir.or_falsy(row, "record_key", sync.text("")))
    sync.put(&opts, "payload", ir.or_falsy(row, "fields", empty_obj()))
    sync.put(&opts, "lastConfirmedValue", ir.or_falsy(row, "last_confirmed", empty_obj()))
    sync.put(&opts, "maxAttempts", ir.or_falsy(row, "max_attempts", .Null))
    let base = create_entry(a, ir.obj_value(&opts), id, now_iso)
    var e = copy_of(a, base)
    sync.put(&e, "id", ir.or_falsy(row, "id", sync.text(id)))
    sync.put(&e, "status", ir.or_falsy(row, "status", sync.text("pending")))
    let attempts = syncjob.number_or(ir.value_of(row, "attempts"), 0.0f64)
    sync.put(&e, "attempts", syncjob.number_value(a, attempts))
    var errors = ir.empty_array()
    let (past, is_array) = ir.items_of(ir.value_of(row, "errors"))
    if is_array { errors = json.Value{ Array: past } }
    sync.put(&e, "errors", errors)
    sync.put(&e, "createdAt", ir.or_falsy(row, "created_at", sync.text(now_iso)))
    sync.put(&e, "lastAttemptAt", ir.or_falsy(row, "last_attempt_at", .Null))
    sync.put(&e, "deliveredAt", ir.or_falsy(row, "delivered_at", .Null))
    sync.put(&e, "deadLetteredAt", ir.or_falsy(row, "dead_lettered_at", .Null))
    ret ir.obj_value(&e)
}

fn put_present(o: *ir.Obj, from: json.Value, key: str, as_key: str) {
    let (x, found) = sync.get(from, key)
    if found { sync.put(o, as_key, x) }
}

// The `writeback_outbox` columns an entry's current state implies.
fn entry_patch(a: *mem.Arena, entry: json.Value) -> json.Value {
    var o = sync.obj(a)
    put_present(&o, entry, "status", "status")
    put_present(&o, entry, "attempts", "attempts")
    sync.put(&o, "errors", ir.or_falsy(entry, "errors", ir.empty_array()))
    sync.put(&o, "last_attempt_at", ir.or_falsy(entry, "lastAttemptAt", .Null))
    sync.put(&o, "delivered_at", ir.or_falsy(entry, "deliveredAt", .Null))
    sync.put(&o, "dead_lettered_at", ir.or_falsy(entry, "deadLetteredAt", .Null))
    sync.put(&o, "reverted_at", ir.or_falsy(entry, "_revertedAt", .Null))
    ret ir.obj_value(&o)
}

// Settle one attempt: `{entry, terminal, action, reversion}`, the reversion planned only on a dead letter.
fn settle_delivery(a: *mem.Arena, entry: json.Value, result: json.Value, now_iso: str) -> json.Value {
    let settled = record_delivery(a, entry, result, now_iso)
    var o = copy_of(a, settled)
    if member_is(settled, "action", "dead_lettered") {
        sync.put(&o, "reversion", plan_reversion(a, ir.value_of(settled, "entry")))
    } else {
        sync.put(&o, "reversion", .Null)
    }
    ret ir.obj_value(&o)
}

// The last error an entry holds, or null.
fn last_error(entry: json.Value) -> json.Value {
    let (errors, is_array) = ir.items_of(ir.value_of(entry, "errors"))
    if !is_array || errors.len == 0usize { ret .Null }
    ret errors[errors.len - 1usize]
}

// The row patch that reverts a dead letter: `{data, reverted, unrevertable}`. `data` is the reversions with the rejected
// value and the source's last word under `_writebackRejected`, one record per pushed field.
fn revert_patch(a: *mem.Arena, entry: json.Value, reversion: json.Value, now_iso: str) -> json.Value {
    let reversions = ir.or_falsy(reversion, "reversions", empty_obj())
    var rejected = sync.obj(a)
    let (fields, is_object) = ir.members_of(ir.value_of(entry, "payload"))
    var at = 0usize
    while at < fields.len {
        var r = sync.obj(a)
        sync.put(&r, "value", fields[at].value)
        sync.put(&r, "error", last_error(entry))
        sync.put(&r, "at", sync.text(now_iso))
        let (v, have) = sync.get(reversions, fields[at].key)
        sync.put(&r, "reverted", sync.flag(have))
        sync.put(&rejected, fields[at].key, ir.obj_value(&r))
        at += 1usize
    }
    var data = copy_of(a, reversions)
    sync.put(&data, rejected_key(), ir.obj_value(&rejected))
    var names = sync.empty_list(a)
    let (rv, rv_is_object) = ir.members_of(reversions)
    var k = 0usize
    while k < rv.len {
        sync.push_value(&names, sync.text(rv[k].key))
        k += 1usize
    }
    var o = sync.obj(a)
    sync.put(&o, "data", ir.obj_value(&data))
    sync.put(&o, "reverted", array_of(a, names))
    sync.put(&o, "unrevertable", ir.or_falsy(reversion, "unrevertable", ir.empty_array()))
    ret ir.obj_value(&o)
}

// The entry marked reverted with the patch's data.
fn finish_reversion(a: *mem.Arena, entry: json.Value, patch: json.Value, now_iso: str) -> json.Value {
    ret mark_reverted(a, entry, ir.or_falsy(patch, "data", empty_obj()), now_iso)
}

// `${key}:${JSON.stringify(fields.map((f) => record[f]))}`.
fn echo_hash(a: *mem.Arena, key_text: str, record: json.Value, fields: []const str) -> str {
    var values = sync.empty_list(a)
    var at = 0usize
    while at < fields.len {
        sync.push_value(&values, ir.value_of(record, fields[at]))
        at += 1usize
    }
    ret sync.cat(a, sync.cat(a, key_text, ":"), hash_of(a, array_of(a, values)))
}

fn has_text(l: list.List[json.Value], s: str) -> bool {
    var at = 0usize
    while at < l.len {
        let (t, is_text) = ir.string_of(l.items[at])
        if is_text && str.eq(t, s) { ret true }
        at += 1usize
    }
    ret false
}

// The echo set for a binding's next pull, as an array of hashes in insertion order: one per delivered row that has a
// record key.
fn echo_set(a: *mem.Arena, delivered: []const json.Value, fields: []const str) -> json.Value {
    var out = sync.empty_list(a)
    var at = 0usize
    while at < delivered.len {
        let row = delivered[at]
        at += 1usize
        let key = ir.value_of(row, "record_key")
        if !ir.truthy(row) || !ir.truthy(key) { continue }
        let record = ir.or_falsy(row, "fields", empty_obj())
        let h = echo_hash(a, js_string(a, key, true), record, fields)
        if !has_text(out, h) { sync.push_value(&out, sync.text(h)) }
    }
    ret array_of(a, out)
}

// A pull plan without the updates that are our own delivered writebacks: `{plan, suppressed}`. The match is on key plus
// the compared field values, so a remote row carrying our value and a further change is kept.
fn suppress_echoes(a: *mem.Arena, plan: json.Value, echo: []const json.Value, sync_key: str, fields: []const str) -> json.Value {
    var out = sync.obj(a)
    if !ir.is_null(plan) { sync.put(&out, "plan", plan) }
    sync.put(&out, "suppressed", sync.number(a, 0i64))
    if !ir.truthy(plan) || echo.len == 0usize { ret ir.obj_value(&out) }
    var kept = sync.empty_list(a)
    var suppressed = 0i64
    let updates = sync.items(ir.value_of(plan, "updates"))
    var at = 0usize
    while at < updates.len {
        let update = updates[at]
        at += 1usize
        let remote = ir.or_falsy(update, "remote", empty_obj())
        let (own_key, have_key) = sync.get(update, "key")
        var key_text = ""
        if have_key {
            key_text = js_string(a, own_key, true)
        } else {
            let (k, have) = sync.get(remote, sync_key)
            key_text = js_string(a, k, have)
        }
        let h = echo_hash(a, key_text, remote, fields)
        if has_text_in(echo, h) {
            suppressed += 1i64
            continue
        }
        sync.push_value(&kept, update)
    }
    var next = copy_of(a, plan)
    sync.put(&next, "updates", array_of(a, kept))
    var result = sync.obj(a)
    sync.put(&result, "plan", ir.obj_value(&next))
    sync.put(&result, "suppressed", sync.number(a, suppressed))
    ret ir.obj_value(&result)
}

fn has_text_in(values: []const json.Value, s: str) -> bool {
    var at = 0usize
    while at < values.len {
        let (t, is_text) = ir.string_of(values[at])
        if is_text && str.eq(t, s) { ret true }
        at += 1usize
    }
    ret false
}

// The one-line outbox state a sync status panel shows: `{tone, text, summary}`, tone `ok`, `pending` or `failing`.
fn outbox_line(a: *mem.Arena, entries: []const json.Value, translate: *const syncjob.Translate) -> json.Value {
    let summary = summarize_outbox(a, entries)
    var o = sync.obj(a)
    sync.put(&o, "summary", summary)
    let total = sync.count_value(summary, "total", 0i64)
    let dead = sync.count_value(summary, "deadLettered", 0i64)
    if total == 0i64 {
        sync.put(&o, "tone", sync.text("ok"))
        sync.put(&o, "text", sync.text(translate.run(translate.ctx, "sync.writeback.none", "")))
        ret ir.obj_value(&o)
    }
    if dead > 0i64 {
        sync.put(&o, "tone", sync.text("failing"))
        sync.put(&o, "text", sync.text(translate.run(translate.ctx, "sync.writeback.deadLettered", js_string(a, sync.number(a, dead), true))))
        ret ir.obj_value(&o)
    }
    let waiting = sync.count_value(summary, "pending", 0i64) + sync.count_value(summary, "failed", 0i64)
    if waiting > 0i64 {
        sync.put(&o, "tone", sync.text("pending"))
        sync.put(&o, "text", sync.text(translate.run(translate.ctx, "sync.writeback.pending", js_string(a, sync.number(a, waiting), true))))
        ret ir.obj_value(&o)
    }
    let delivered = sync.count_value(summary, "delivered", 0i64)
    sync.put(&o, "tone", sync.text("ok"))
    sync.put(&o, "text", sync.text(translate.run(translate.ctx, "sync.writeback.delivered", js_string(a, sync.number(a, delivered), true))))
    ret ir.obj_value(&o)
}

// --- the engine: mapping ---------------------------------------------------------------------------------------------

// `{[m.local]: remote[m.remote]}` for every mapping not `push`-only, where the remote member is present.
fn map_remote_to_local(a: *mem.Arena, remote: json.Value, mapping: []const json.Value) -> json.Value {
    var out = sync.obj(a)
    var at = 0usize
    while at < mapping.len {
        let m = mapping[at]
        at += 1usize
        if member_is(m, "direction", "push") { continue }
        let (v, have) = sync.get(remote, js_string(a, ir.value_of(m, "remote"), true))
        if have { sync.put(&out, js_string(a, ir.value_of(m, "local"), true), v) }
    }
    ret ir.obj_value(&out)
}

// `{[m.remote]: local[m.local]}` for every mapping not `pull`-only, where the local member is present.
fn map_local_to_remote(a: *mem.Arena, local: json.Value, mapping: []const json.Value) -> json.Value {
    var out = sync.obj(a)
    var at = 0usize
    while at < mapping.len {
        let m = mapping[at]
        at += 1usize
        if member_is(m, "direction", "pull") { continue }
        let (v, have) = sync.get(local, js_string(a, ir.value_of(m, "local"), true))
        if have { sync.put(&out, js_string(a, ir.value_of(m, "remote"), true), v) }
    }
    ret ir.obj_value(&out)
}

// --- the engine: the three-way merge ---------------------------------------------------------------------------------

type Keyed = struct { id: str, key: json.Value, has_key: bool, row: json.Value }

// The rows by key, in first-seen order, a later row with the same key replacing the earlier one in place.
fn index_rows(a: *mem.Arena, rows: []const json.Value, key: str) -> list.List[Keyed] {
    let (made, e) = list.init[Keyed](a, rows.len + 1usize)
    var out = made
    var at = 0usize
    while at < rows.len {
        let (k, have) = sync.get(rows[at], key)
        let id = js_identity(a, k, have)
        var slot = out.len
        var j = 0usize
        while j < out.len {
            if str.eq(out.items[j].id, id) { slot = j }
            j += 1usize
        }
        let item = Keyed { id: id, key: k, has_key: have, row: rows[at] }
        if slot < out.len {
            out.items[slot] = item
        } else {
            let pushed = list.push[Keyed](&out, item)
        }
        at += 1usize
    }
    ret out
}

// Map-key identity: type and value, an absent key apart from a null one.
fn js_identity(a: *mem.Arena, v: json.Value, present: bool) -> str {
    if !present { ret "undefined" }
    ret hash_of(a, v)
}

fn find_row(l: list.List[Keyed], id: str) -> (json.Value, bool) {
    var at = 0usize
    while at < l.len {
        if str.eq(l.items[at].id, id) { ret (l.items[at].row, true) }
        at += 1usize
    }
    ret (.Null, false)
}

fn has_id(l: list.List[Keyed], id: str) -> bool {
    let (row, found) = find_row(l, id)
    ret found
}

// Does any compared field differ between two rows (an absent row reads as null)?
fn fields_changed(a: *mem.Arena, x: json.Value, base: json.Value, fields: []const str) -> bool {
    var at = 0usize
    while at < fields.len {
        if !str.eq(hash_of(a, ir.value_of(x, fields[at])), hash_of(a, ir.value_of(base, fields[at]))) { ret true }
        at += 1usize
    }
    ret false
}

type Plan = struct {
    pulls: list.List[json.Value],
    pushes: list.List[json.Value],
    conflicts: list.List[json.Value],
    echoes: list.List[json.Value],
    create_local: list.List[json.Value],
    create_remote: list.List[json.Value],
    delete_local: list.List[json.Value],
    delete_remote: list.List[json.Value],
    noops: i64
}

fn move_entry(a: *mem.Arena, k: Keyed, record: json.Value, via_conflict: bool) -> json.Value {
    var o = sync.obj(a)
    if k.has_key { sync.put(&o, "key", k.key) }
    sync.put(&o, "record", record)
    if via_conflict { sync.put(&o, "viaConflict", sync.flag(true)) }
    ret ir.obj_value(&o)
}

fn add_conflict(a: *mem.Arena, p: *Plan, k: Keyed, local: json.Value, remote: json.Value, base: json.Value, policy: str) {
    var c = sync.obj(a)
    if k.has_key { sync.put(&c, "key", k.key) }
    sync.put(&c, "local", local)
    sync.put(&c, "remote", remote)
    sync.put(&c, "base", base)
    sync.put(&c, "policy", sync.text(policy))
    if str.eq(policy, "source-wins") && ir.truthy(remote) {
        sync.put(&c, "resolution", sync.text("pull"))
        sync.push_value(&p.pulls, move_entry(a, k, remote, true))
    } else if str.eq(policy, "local-wins") && ir.truthy(local) {
        sync.put(&c, "resolution", sync.text("push"))
        sync.push_value(&p.pushes, move_entry(a, k, local, true))
    } else {
        sync.put(&c, "resolution", sync.text("manual"))
    }
    sync.push_value(&p.conflicts, ir.obj_value(&c))
}

// One two-way pass over `local`, `remote` and the last-synced `base`, all keyed by `key`, comparing `fields`; `echo` is
// the hashes of the engine's own recent writes. Returns `{pulls, pushes, conflicts, echoes, creates: {local, remote},
// deletes: {local, remote}, noops}`.
fn plan_two_way_sync(a: *mem.Arena, local_rows: []const json.Value, remote_rows: []const json.Value, base_rows: []const json.Value, key: str, fields: []const str, policy: str, echo: []const json.Value) -> json.Value {
    let local_by = index_rows(a, local_rows, key)
    let remote_by = index_rows(a, remote_rows, key)
    let base_by = index_rows(a, base_rows, key)
    var p = Plan {
        pulls: sync.empty_list(a), pushes: sync.empty_list(a), conflicts: sync.empty_list(a), echoes: sync.empty_list(a),
        create_local: sync.empty_list(a), create_remote: sync.empty_list(a), delete_local: sync.empty_list(a), delete_remote: sync.empty_list(a),
        noops: 0i64
    }
    // the union of keys in insertion order: local, then remote, then base
    let (made, made_error) = list.init[Keyed](a, local_by.len + remote_by.len + base_by.len + 1usize)
    var keys = made
    var side = 0usize
    while side < 3usize {
        var source = local_by
        if side == 1usize { source = remote_by }
        if side == 2usize { source = base_by }
        var at = 0usize
        while at < source.len {
            if !has_id(keys, source.items[at].id) {
                let pushed = list.push[Keyed](&keys, source.items[at])
            }
            at += 1usize
        }
        side += 1usize
    }
    var n = 0usize
    while n < keys.len {
        let k = keys.items[n]
        n += 1usize
        let (local_row, has_local) = find_row(local_by, k.id)
        let (remote_row, has_remote) = find_row(remote_by, k.id)
        let (base_row, has_base) = find_row(base_by, k.id)
        var local: json.Value = .Null
        var remote: json.Value = .Null
        var base: json.Value = .Null
        if has_local && ir.truthy(local_row) { local = local_row }
        if has_remote && ir.truthy(remote_row) { remote = remote_row }
        if has_base && ir.truthy(base_row) { base = base_row }
        let have_local = !ir.is_null(local)
        let have_remote = !ir.is_null(remote)
        let have_base = !ir.is_null(base)
        if !have_base {
            if have_remote && !have_local {
                sync.push_value(&p.create_local, remote)
            } else if have_local && !have_remote {
                sync.push_value(&p.create_remote, local)
            } else if have_local && have_remote {
                if fields_changed(a, local, remote, fields) {
                    add_conflict(a, &p, k, local, remote, base, policy)
                } else {
                    p.noops += 1i64
                }
            }
            continue
        }
        if !have_remote && !have_local { continue }
        if !have_remote {
            if fields_changed(a, local, base, fields) {
                add_conflict(a, &p, k, local, .Null, base, policy)
            } else {
                sync.push_value(&p.delete_local, local)
            }
            continue
        }
        if !have_local {
            if fields_changed(a, remote, base, fields) {
                add_conflict(a, &p, k, .Null, remote, base, policy)
            } else {
                sync.push_value(&p.delete_remote, remote)
            }
            continue
        }
        let h = echo_hash(a, js_string(a, k.key, k.has_key), remote, fields)
        if has_text_in(echo, h) {
            if k.has_key { sync.push_value(&p.echoes, k.key) } else { sync.push_value(&p.echoes, .Null) }
            continue
        }
        let local_changed = fields_changed(a, local, base, fields)
        let remote_changed = fields_changed(a, remote, base, fields)
        if !local_changed && !remote_changed {
            p.noops += 1i64
        } else if local_changed && !remote_changed {
            sync.push_value(&p.pushes, move_entry(a, k, local, false))
        } else if !local_changed && remote_changed {
            sync.push_value(&p.pulls, move_entry(a, k, remote, false))
        } else if !fields_changed(a, local, remote, fields) {
            p.noops += 1i64
        } else {
            add_conflict(a, &p, k, local, remote, base, policy)
        }
    }
    var creates = sync.obj(a)
    sync.put(&creates, "local", array_of(a, p.create_local))
    sync.put(&creates, "remote", array_of(a, p.create_remote))
    var deletes = sync.obj(a)
    sync.put(&deletes, "local", array_of(a, p.delete_local))
    sync.put(&deletes, "remote", array_of(a, p.delete_remote))
    var o = sync.obj(a)
    sync.put(&o, "pulls", array_of(a, p.pulls))
    sync.put(&o, "pushes", array_of(a, p.pushes))
    sync.put(&o, "conflicts", array_of(a, p.conflicts))
    sync.put(&o, "echoes", array_of(a, p.echoes))
    sync.put(&o, "creates", ir.obj_value(&creates))
    sync.put(&o, "deletes", ir.obj_value(&deletes))
    sync.put(&o, "noops", sync.number(a, p.noops))
    ret ir.obj_value(&o)
}

// --- the request builder ---------------------------------------------------------------------------------------------

fn lower_ascii(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

fn upper_ascii(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

fn hex_digit(n: u8) -> u8 {
    if n < 10u8 { ret 48u8 + n }
    ret 55u8 + n
}

fn is_alnum(c: u8) -> bool { ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) }

// `encodeURIComponent` over the bytes of the text.
fn encode_uri_component(a: *mem.Arena, s: str) -> str {
    let (b, e) = str.builder(a, s.len * 3usize + 8usize)
    if e != ok { ret s }
    var out = b
    var at = 0usize
    while at < s.len {
        let c = s[at]
        let plain_byte = is_alnum(c) || c == 45u8 || c == 95u8 || c == 46u8 || c == 33u8 || c == 126u8 || c == 42u8 || c == 39u8 || c == 40u8 || c == 41u8
        if plain_byte {
            let pushed = str.push_byte(&out, c)
        } else {
            let p1 = str.push_byte(&out, 37u8)
            let p2 = str.push_byte(&out, hex_digit(c / 16u8))
            let p3 = str.push_byte(&out, hex_digit(c % 16u8))
        }
        at += 1usize
    }
    ret str.done(&out)
}

// `application/x-www-form-urlencoded` over the bytes of the text (what `URLSearchParams` writes).
fn form_encode(a: *mem.Arena, s: str) -> str {
    let (b, e) = str.builder(a, s.len * 3usize + 8usize)
    if e != ok { ret s }
    var out = b
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if is_alnum(c) || c == 42u8 || c == 45u8 || c == 46u8 || c == 95u8 {
            let pushed = str.push_byte(&out, c)
        } else if c == 32u8 {
            let pushed = str.push_byte(&out, 43u8)
        } else {
            let p1 = str.push_byte(&out, 37u8)
            let p2 = str.push_byte(&out, hex_digit(c / 16u8))
            let p3 = str.push_byte(&out, hex_digit(c % 16u8))
        }
        at += 1usize
    }
    ret str.done(&out)
}

fn is_digits(s: str) -> bool {
    if s.len == 0usize { ret false }
    var at = 0usize
    while at < s.len {
        if s[at] < 48u8 || s[at] > 57u8 { ret false }
        at += 1usize
    }
    ret true
}

fn small_number(s: str) -> i64 {
    var n = 0i64
    var at = 0usize
    while at < s.len {
        n = n * 10i64 + i64(s[at] - 48u8)
        at += 1usize
    }
    ret n
}

// `{a}.{b}.{c}.{d}` of one to three digits each: the first two octets, or none.
fn private_v4(host: str) -> bool {
    var parts: [4]str = zero
    var count = 0usize
    var start = 0usize
    var at = 0usize
    while at <= host.len {
        if at == host.len || host[at] == 46u8 {
            if count >= 4usize { ret false }
            parts[count] = host[start..at]
            count += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    if count != 4usize { ret false }
    var k = 0usize
    while k < 4usize {
        if !is_digits(parts[k]) || parts[k].len > 3usize { ret false }
        k += 1usize
    }
    let first = small_number(parts[0])
    let second = small_number(parts[1])
    if first == 10i64 || first == 127i64 || first == 0i64 { ret true }
    if first == 169i64 && second == 254i64 { ret true }
    if first == 172i64 && second >= 16i64 && second <= 31i64 { ret true }
    if first == 192i64 && second == 168i64 { ret true }
    ret false
}

// `{safe, reason}` for an outbound URL: http or https, not loopback, not a private or link-local address, not the cloud
// metadata name, not a dotless internal host.
fn is_safe_url(a: *mem.Arena, url: str) -> (bool, str) {
    let p = ssrf.parse_href(a, url)
    if !p.valid { ret (false, "invalid-url") }
    if !str.eq(p.scheme, "http") && !str.eq(p.scheme, "https") { ret (false, "bad-protocol") }
    var host = lower_ascii(a, p.host)
    if host.len > 0usize && host[0] == 91u8 { host = host[1usize..host.len] }
    if host.len > 0usize && host[host.len - 1usize] == 93u8 { host = host[0usize..host.len - 1usize] }
    if str.eq(host, "localhost") || str.ends_with(host, ".localhost") || str.eq(host, "::1") || str.starts_with(host, "127.") {
        ret (false, "loopback")
    }
    if str.contains(host, ":") && ssrf.is_blocked_address(a, host) { ret (false, "private-network") }
    if private_v4(host) { ret (false, "private-network") }
    if str.eq(host, "metadata.google.internal") { ret (false, "metadata-endpoint") }
    if !str.contains(host, ".") && !str.contains(host, ":") { ret (false, "internal-hostname") }
    ret (true, "")
}

// The headers an auth block adds: bearer, basic, apiKey (in a header unless `in` is `query`) or customHeader.
fn auth_headers(a: *mem.Arena, o: *ir.Obj, auth: json.Value) {
    let kind = str_member(auth, "type")
    if str.eq(kind, "bearer") {
        let (t, have) = sync.get(auth, "token")
        sync.put(o, "Authorization", sync.text(sync.cat(a, "Bearer ", js_string(a, t, have))))
    } else if str.eq(kind, "basic") {
        let (u, have_u) = sync.get(auth, "username")
        let (pw, have_p) = sync.get(auth, "password")
        let pair = sync.cat(a, sync.cat(a, js_string(a, u, have_u), ":"), js_string(a, pw, have_p))
        let (encoded, e) = encode.base64_encode(a, pair)
        sync.put(o, "Authorization", sync.text(sync.cat(a, "Basic ", encoded)))
    } else if str.eq(kind, "apiKey") {
        if !member_is(auth, "in", "query") {
            let name = js_string(a, ir.or_falsy(auth, "header", sync.text("X-API-Key")), true)
            put_present(o, auth, "key", name)
        }
    } else if str.eq(kind, "customHeader") {
        let (h, have_h) = sync.get(auth, "header")
        put_present(o, auth, "value", js_string(a, h, have_h))
    }
}

type Param = struct { name: str, value: str }

// `{url, method, headers, body?}`, or `{url, error: "ssrf-blocked:<reason>"}`. `request` is `{path, query?, method?,
// body?}`; the base is the connection's `baseUrl` without one trailing slash.
fn build_request(a: *mem.Arena, connection: json.Value, request: json.Value) -> json.Value {
    var base = ""
    let (b, have_base) = sync.member_text(connection, "baseUrl")
    if have_base { base = b }
    if base.len > 0usize && base[base.len - 1usize] == 47u8 { base = base[0usize..base.len - 1usize] }
    var path = ""
    let (p, have_path) = sync.member_text(request, "path")
    if have_path { path = p }
    let (made, made_error) = list.init[Param](a, 8usize)
    var params = made
    let (query, is_object) = ir.members_of(ir.or_falsy(request, "query", empty_obj()))
    var at = 0usize
    while at < query.len {
        let pushed = list.push[Param](&params, Param { name: query[at].key, value: js_string(a, query[at].value, true) })
        at += 1usize
    }
    let auth = ir.value_of(connection, "auth")
    if ir.truthy(auth) && member_is(auth, "type", "apiKey") && member_is(auth, "in", "query") {
        let name = js_string(a, ir.or_falsy(auth, "param", sync.text("api_key")), true)
        let (k, have_k) = sync.get(auth, "key")
        let value = js_string(a, k, have_k)
        var slot = params.len
        var j = 0usize
        while j < params.len {
            if str.eq(params.items[j].name, name) && slot == params.len { slot = j }
            j += 1usize
        }
        if slot < params.len {
            params.items[slot].value = value
            // `set` drops every later pair of the same name
            var kept = slot + 1usize
            var scan = slot + 1usize
            while scan < params.len {
                if !str.eq(params.items[scan].name, name) {
                    params.items[kept] = params.items[scan]
                    kept += 1usize
                }
                scan += 1usize
            }
            params.len = kept
        } else {
            let pushed = list.push[Param](&params, Param { name: name, value: value })
        }
    }
    var qs = ""
    var q = 0usize
    while q < params.len {
        if q > 0usize { qs = sync.cat(a, qs, "&") }
        qs = sync.cat(a, qs, sync.cat(a, sync.cat(a, form_encode(a, params.items[q].name), "="), form_encode(a, params.items[q].value)))
        q += 1usize
    }
    var url = sync.cat(a, base, path)
    if qs.len > 0usize { url = sync.cat(a, sync.cat(a, url, "?"), qs) }
    var out = sync.obj(a)
    sync.put(&out, "url", sync.text(url))
    let (safe, reason) = is_safe_url(a, url)
    if !safe {
        sync.put(&out, "error", sync.text(sync.cat(a, "ssrf-blocked:", reason)))
        ret ir.obj_value(&out)
    }
    var headers = sync.obj(a)
    sync.put(&headers, "Content-Type", sync.text("application/json"))
    auth_headers(a, &headers, auth)
    let (extra_members, extra_is_object) = ir.members_of(ir.or_falsy(connection, "headers", empty_obj()))
    var h = 0usize
    while h < extra_members.len {
        sync.put(&headers, extra_members[h].key, extra_members[h].value)
        h += 1usize
    }
    var method = "GET"
    let (m, have_m) = sync.member_text(request, "method")
    if have_m && m.len > 0usize { method = m }
    sync.put(&out, "method", sync.text(upper_ascii(a, method)))
    sync.put(&out, "headers", ir.obj_value(&headers))
    let (body, have_body) = sync.get(request, "body")
    if have_body {
        let (body_text, is_text) = ir.string_of(body)
        if is_text { sync.put(&out, "body", sync.text(body_text)) } else { sync.put(&out, "body", sync.text(hash_of(a, body))) }
    }
    ret ir.obj_value(&out)
}

// The outbound push of an entry: a PATCH of the two-way fields to `<entity>/<encoded record key>`.
fn build_push_request(a: *mem.Arena, connection: json.Value, entity: str, entry: json.Value, mapping: json.Value) -> json.Value {
    let mapped = sync.items(writeback_mapping(a, mapping))
    let remote = map_local_to_remote(a, ir.or_falsy(entry, "payload", empty_obj()), mapped)
    var path = entity
    if !str.starts_with(path, "/") { path = sync.cat(a, "/", path) }
    var key = ""
    let (k, have_k) = sync.get(entry, "recordKey")
    if have_k && !ir.is_null(k) { key = js_string(a, k, true) }
    var request = sync.obj(a)
    sync.put(&request, "path", sync.text(sync.cat(a, sync.cat(a, path, "/"), encode_uri_component(a, key))))
    sync.put(&request, "method", sync.text("PATCH"))
    sync.put(&request, "body", remote)
    var conn = connection
    if !ir.truthy(connection) { conn = empty_obj() }
    ret build_request(a, conn, ir.obj_value(&request))
}
