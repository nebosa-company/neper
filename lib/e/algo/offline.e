// The offline layer around the outbox (L037), after appdor's `src/offline/write-queue.js`, `read-cache.js`,
// `conflict-review.js` and `access-purge.js`: what `e.algo.sync` leaves to the application.
//
//   * write queue: which failures are the network (`is_network_failure`), queueing only those, flushing with
//     `continueOnError`, and the status and sentence a badge shows (`queue_status`, `describe_queue`);
//   * read cache: table snapshots with a fresh / stale / offline-only verdict, the optimistic overlay of queued writes,
//     the scopes a purge asks the server about, and `drop_records` (which keeps the snapshot's age);
//   * connectivity: online, offline, reconnecting, and the replay each arrival asks for;
//   * replay: `plan_replay` splits a queue into writes safe to send, creates and conflicts against server versions, and
//     `resolve_replay_conflict` is local-wins, server-wins and field merge over base and server records;
//   * conflict review: what a person decides about (`build_conflict_review`), and the queue operation a choice means
//     (`plan_offline_resolution`) -- merge is offered only when the base values were kept, and refuses, naming them,
//     when both sides changed a field;
//   * access purge: of the ids a cache holds, which the server still serves (`plan_cache_purge`), applied to the cache
//     (`apply_cache_purge`); a probe that did not succeed purges nothing.
//
// Values are JSON (`e.fmt.json`); the outbox, the remote and the clock are `e.algo.sync`'s. A JavaScript `undefined` is a
// member that is absent. Rendering the review (`renderConflictReview`) needs the host's escaper and translator and is not
// here.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.algo.sync as sync
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str

const FRESH_MS: i64 = 300000i64

// A cached table: its id as stored, its records and when it was fetched.
type Snapshot = struct { table_id: json.Value, records: []const json.Value, fetched_at: json.Value }

type ReadCache = struct { a: *mem.Arena, fresh_ms: i64, tables: list.List[Snapshot] }

type Connectivity = struct { a: *mem.Arena, state: str, log: list.List[json.Value] }

// --- small JavaScript semantics --------------------------------------------------------------------------------------

// `String(value)`; an absent value is "undefined".
fn js_string(v: json.Value, present: bool) -> str {
    if !present { ret "undefined" }
    switch v {
    case .Null:
        ret "null"
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    case .Number as n:
        ret n.lexeme
    case .String as s:
        ret s
    case .Array as xs:
        ret "[array]"
    case .Object as ms:
        ret "[object Object]"
    }
}

// `v[key]` truthy.
fn truthy_member(v: json.Value, key: str) -> bool {
    let (x, found) = sync.get(v, key)
    ret found && ir.truthy(x)
}

// `x || {}` for an object-valued member.
fn object_or_empty(v: json.Value, key: str) -> json.Value {
    let (x, found) = sync.get(v, key)
    if found && ir.truthy(x) { ret x }
    ret ir.empty_object()
}

// `JSON.stringify(a) === JSON.stringify(b)` where either side may be absent.
fn same_member(a: *mem.Arena, x: json.Value, has_x: bool, y: json.Value, has_y: bool) -> bool {
    if !has_x && !has_y { ret true }
    if has_x != has_y { ret false }
    ret sync.same_json(a, x, y)
}

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

// `{...o, key: value}` with an absent value removing the key, as `undefined` does once serialized.
fn with_member(a: *mem.Arena, o: json.Value, key: str, v: json.Value, present: bool) -> json.Value {
    var out = sync.spread(a, o, ir.empty_object())
    if present { sync.put(&out, key, v) } else { sync.unset(&out, key) }
    ret ir.obj_value(&out)
}

fn text_list(a: *mem.Arena, names: []const str) -> json.Value {
    var out = sync.empty_list(a)
    var at = 0usize
    while at < names.len {
        sync.push_value(&out, sync.text(names[at]))
        at += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

// --- the write queue -------------------------------------------------------------------------------------------------

// Is this failure the network? An `offline: true` flag, or a message that names a transport failure.
fn is_network_failure(a: *mem.Arena, failure: json.Value, has_failure: bool) -> bool {
    if !has_failure || !ir.truthy(failure) { ret false }
    let (flag, found) = sync.get(failure, "offline")
    var flagged = false
    if found {
        switch flag {
        case .Bool as b:
            flagged = b
        default:
            flagged = false
        }
    }
    if flagged { ret true }
    var shown = failure
    let (message, have_message) = sync.get(failure, "message")
    if have_message && ir.truthy(message) { shown = message }
    let low = lower_ascii(a, js_string(shown, true))
    ret str.contains(low, "failed to fetch") || str.contains(low, "networkerror") || str.contains(low, "network request failed") || str.contains(low, "load failed") || str.contains(low, "econnrefused") || str.contains(low, "etimedout") || str.contains(low, "fetch failed")
}

// Queue a write that failed for the network: `{queued: true}`, or `{queued: false, reason}` when it was a real refusal or
// the mutation is incomplete.
fn queue_if_offline(a: *mem.Arena, o: *sync.Outbox, failure: json.Value, has_failure: bool, mutation: json.Value, has_mutation: bool) -> json.Value {
    var out = sync.obj(a)
    if !is_network_failure(a, failure, has_failure) {
        sync.put(&out, "queued", sync.flag(false))
        sync.put(&out, "reason", sync.text("not-a-network-failure"))
        ret ir.obj_value(&out)
    }
    if !has_mutation || !ir.truthy(mutation) || !truthy_member(mutation, "op") || !truthy_member(mutation, "table") {
        sync.put(&out, "queued", sync.flag(false))
        sync.put(&out, "reason", sync.text("incomplete-mutation"))
        ret ir.obj_value(&out)
    }
    let added = sync.add(o, mutation)
    sync.put(&out, "queued", sync.flag(true))
    ret ir.obj_value(&out)
}

// Send what is waiting, one write failing not holding up another: `{sent, conflicts, failed, dead, stillPending}`.
fn flush_queue(a: *mem.Arena, o: *sync.Outbox, remote: *const sync.Remote, at: i64, resolve: str) -> json.Value {
    let result = sync.flush(o, remote, at, true, resolve)
    var out = sync.obj(a)
    sync.put(&out, "sent", sync.number(a, i64(sync.items(ir.value_of(result, "synced")).len)))
    sync.put(&out, "conflicts", ir.value_of(result, "conflicts"))
    sync.put(&out, "failed", sync.number(a, i64(sync.items(ir.value_of(result, "failed")).len)))
    sync.put(&out, "dead", ir.value_of(result, "dead"))
    sync.put(&out, "stillPending", ir.value_of(result, "remaining"))
    ret ir.obj_value(&out)
}

// What a badge needs: how many wait, whether they will survive, and which tables.
fn queue_status(a: *mem.Arena, o: *const sync.Outbox, has_outbox: bool) -> json.Value {
    var out = sync.obj(a)
    if !has_outbox {
        sync.put(&out, "pending", sync.number(a, 0i64))
        sync.put(&out, "dead", sync.number(a, 0i64))
        sync.put(&out, "durable", sync.flag(false))
        ret ir.obj_value(&out)
    }
    let d = sync.describe_outbox(a, o)
    sync.put(&out, "pending", ir.value_of(d, "pending"))
    sync.put(&out, "dead", ir.value_of(d, "dead"))
    sync.put(&out, "durable", ir.value_of(d, "durable"))
    sync.put(&out, "needsAttention", ir.value_of(d, "needsAttention"))
    sync.put(&out, "byTable", ir.value_of(d, "byTable"))
    ret ir.obj_value(&out)
}

fn plural(count: json.Value) -> str {
    if str.eq(js_string(count, true), "1") { ret "" }
    ret "s"
}

// The sentence a person needs about their queued work, or null when there is none; a queue that will not survive a
// closed tab says so.
fn describe_queue(a: *mem.Arena, status: json.Value, has_status: bool) -> json.Value {
    var out = sync.obj(a)
    if !has_status || !ir.truthy(status) || !truthy_member(status, "pending") {
        if has_status && ir.truthy(status) && truthy_member(status, "dead") {
            let dead = ir.value_of(status, "dead")
            sync.put(&out, "tone", sync.text("bad"))
            let head = sync.cat(a, js_string(dead, true), sync.cat(a, " change", plural(dead)))
            sync.put(&out, "text", sync.text(sync.cat(a, head, " could not be saved and need your attention.")))
            ret ir.obj_value(&out)
        }
        ret .Null
    }
    let n = ir.value_of(status, "pending")
    let base = sync.cat(a, js_string(n, true), sync.cat(a, " change", sync.cat(a, plural(n), " waiting to send")))
    if truthy_member(status, "durable") {
        sync.put(&out, "tone", sync.text("info"))
        sync.put(&out, "text", sync.text(sync.cat(a, base, ". They are saved on this device and will send when you reconnect.")))
    } else {
        sync.put(&out, "tone", sync.text("warn"))
        sync.put(&out, "text", sync.text(sync.cat(a, base, ". This browser will not keep them if you close the tab.")))
    }
    ret ir.obj_value(&out)
}

// --- the read cache --------------------------------------------------------------------------------------------------

fn new_read_cache(a: *mem.Arena, fresh_ms: i64) -> ReadCache {
    let (made, e) = list.init[Snapshot](a, 4usize)
    var tables = made
    if e != ok { tables = list.List[Snapshot] { items: zero, len: 0usize, arena: a } }
    ret ReadCache { a: a, fresh_ms: fresh_ms, tables: tables }
}

fn snapshot_index(c: *const ReadCache, table_id: json.Value) -> i64 {
    var at = 0usize
    while at < c.tables.len {
        if sync.same_json(c.a, c.tables.items[at].table_id, table_id) { ret i64(at) }
        at += 1usize
    }
    ret -1i64
}

fn cache_store(c: *ReadCache, table_id: json.Value, records: json.Value, fetched_at: json.Value) {
    let snap = Snapshot { table_id: table_id, records: sync.items(records), fetched_at: fetched_at }
    let at = snapshot_index(c, table_id)
    if at >= 0i64 {
        c.tables.items[usize(at)] = snap
        ret
    }
    let pushed = list.push[Snapshot](&c.tables, snap)
}

// Serve a table with an honest staleness verdict: `{available, records, ageMs, staleness, asOf}`, or `{available: false,
// reason}`.
fn cache_read(c: *const ReadCache, table_id: json.Value, now_ms: i64, online: bool) -> json.Value {
    let a = c.a
    var out = sync.obj(a)
    let at = snapshot_index(c, table_id)
    if at < 0i64 {
        sync.put(&out, "available", sync.flag(false))
        if online { sync.put(&out, "reason", sync.text("not-cached")) } else { sync.put(&out, "reason", sync.text("offline-and-not-cached")) }
        ret ir.obj_value(&out)
    }
    let snap = c.tables.items[usize(at)]
    var fetched_ms = 0i64
    switch snap.fetched_at {
    case .Number as n:
        let (v, e) = json.number_i64(n)
        if e == ok { fetched_ms = v }
    default:
        fetched_ms = 0i64
    }
    let age = now_ms - fetched_ms
    var staleness = "offline-only"
    if online {
        if age <= c.fresh_ms { staleness = "fresh" } else { staleness = "stale" }
    }
    sync.put(&out, "available", sync.flag(true))
    sync.put(&out, "records", json.Value{ Array: snap.records })
    sync.put(&out, "ageMs", sync.number(a, age))
    sync.put(&out, "staleness", sync.text(staleness))
    sync.put(&out, "asOf", snap.fetched_at)
    ret ir.obj_value(&out)
}

fn id_slot(ids: []const json.Value, present: []const bool, live: []const bool, id: json.Value, has_id: bool, a: *mem.Arena) -> i64 {
    var at = 0usize
    while at < ids.len {
        if live[at] && same_member(a, ids[at], present[at], id, has_id) { ret i64(at) }
        at += 1usize
    }
    ret -1i64
}

// The snapshot with local queued writes laid over it, for display; each touched record carries `_pending`. Null (not
// found) when the table is not cached.
fn cache_overlay(c: *const ReadCache, table_id: json.Value, queued: []const json.Value) -> (json.Value, bool) {
    let a = c.a
    let at = snapshot_index(c, table_id)
    if at < 0i64 { ret (.Null, false) }
    let records = c.tables.items[usize(at)].records
    let total = records.len + queued.len + 1usize
    let (ids, ie) = mem.alloc[json.Value](a, total)
    let (present, pe) = mem.alloc[bool](a, total)
    let (rows, re) = mem.alloc[json.Value](a, total)
    let (live, le) = mem.alloc[bool](a, total)
    if ie != ok || pe != ok || re != ok || le != ok { ret (.Null, false) }
    var used = 0usize
    var r = 0usize
    while r < records.len {
        let (id, has_id) = sync.get(records[r], "id")
        let slot = id_slot(ids[0usize..used], present[0usize..used], live[0usize..used], id, has_id, a)
        if slot >= 0i64 {
            rows[usize(slot)] = records[r]
        } else {
            ids[used] = id
            present[used] = has_id
            rows[used] = records[r]
            live[used] = true
            used += 1usize
        }
        r += 1usize
    }
    var q = 0usize
    while q < queued.len {
        let w = queued[q]
        q += 1usize
        let (w_table, has_table) = sync.get(w, "tableId")
        if !has_table || !sync.same_json(a, w_table, table_id) { continue }
        let (op, has_op) = sync.member_text(w, "op")
        let (rid, has_rid) = sync.get(w, "recordId")
        let slot = id_slot(ids[0usize..used], present[0usize..used], live[0usize..used], rid, has_rid, a)
        let (values, has_values) = sync.get(w, "values")
        var vals = ir.empty_object()
        if has_values && ir.truthy(values) { vals = values }
        if has_op && str.eq(op, "update") && slot >= 0i64 {
            var merged = sync.spread(a, rows[usize(slot)], vals)
            sync.put(&merged, "_pending", sync.flag(true))
            rows[usize(slot)] = ir.obj_value(&merged)
        } else if has_op && str.eq(op, "create") {
            var made = sync.obj(a)
            if has_rid { sync.put(&made, "id", rid) }
            let spread_in = ir.assign(&made, vals)
            sync.put(&made, "_pending", sync.flag(true))
            if slot >= 0i64 {
                rows[usize(slot)] = ir.obj_value(&made)
            } else {
                ids[used] = rid
                present[used] = has_rid
                rows[used] = ir.obj_value(&made)
                live[used] = true
                used += 1usize
            }
        } else if has_op && str.eq(op, "delete") && slot >= 0i64 {
            live[usize(slot)] = false
        }
    }
    var out = sync.empty_list(a)
    var k = 0usize
    while k < used {
        if live[k] { sync.push_value(&out, rows[k]) }
        k += 1usize
    }
    ret (json.Value{ Array: list.slice_const[json.Value](&out) }, true)
}

// Drop a table's snapshot; whether there was one.
fn cache_evict(c: *ReadCache, table_id: json.Value) -> bool {
    let at = snapshot_index(c, table_id)
    if at < 0i64 { ret false }
    let gone = list.remove[Snapshot](&c.tables, usize(at))
    ret true
}

// What the cache holds, as the shape a purge asks the server about: `[{tableId, recordIds}]`.
fn cache_scopes(c: *const ReadCache) -> json.Value {
    let a = c.a
    var out = sync.empty_list(a)
    var at = 0usize
    while at < c.tables.len {
        var scope = sync.obj(a)
        sync.put(&scope, "tableId", c.tables.items[at].table_id)
        var ids = sync.empty_list(a)
        var r = 0usize
        while r < c.tables.items[at].records.len {
            let (id, has_id) = sync.get(c.tables.items[at].records[r], "id")
            sync.push_value(&ids, sync.text(js_string(id, has_id)))
            r += 1usize
        }
        sync.put(&scope, "recordIds", json.Value{ Array: list.slice_const[json.Value](&ids) })
        sync.push_value(&out, ir.obj_value(&scope))
        at += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

// Remove named records from a snapshot and keep the rest, and its age; how many were there to remove.
fn cache_drop_records(c: *ReadCache, table_id: json.Value, ids: []const str) -> i64 {
    let at = snapshot_index(c, table_id)
    if at < 0i64 || ids.len == 0usize { ret 0i64 }
    let a = c.a
    let records = c.tables.items[usize(at)].records
    var kept = sync.empty_list(a)
    var r = 0usize
    while r < records.len {
        let (id, has_id) = sync.get(records[r], "id")
        let shown = js_string(id, has_id)
        var doomed = false
        var d = 0usize
        while d < ids.len {
            if str.eq(ids[d], shown) { doomed = true }
            d += 1usize
        }
        if !doomed { sync.push_value(&kept, records[r]) }
        r += 1usize
    }
    let before = records.len
    c.tables.items[usize(at)].records = list.slice_const[json.Value](&kept)
    ret i64(before - kept.len)
}

// --- connectivity ----------------------------------------------------------------------------------------------------

fn new_connectivity(a: *mem.Arena) -> Connectivity {
    ret Connectivity { a: a, state: "online", log: sync.empty_list(a) }
}

fn transition_allowed(from: str, next: str) -> bool {
    if str.eq(from, "online") { ret str.eq(next, "offline") }
    if str.eq(from, "offline") { ret str.eq(next, "reconnecting") }
    ret str.eq(next, "online") || str.eq(next, "offline")
}

// Move to `next`: `{ok: true, replayNow}` (replay is due on arriving online) or `{ok: false, error}`.
fn connect_to(c: *Connectivity, next: str, at: json.Value, has_at: bool) -> json.Value {
    let a = c.a
    var out = sync.obj(a)
    if !transition_allowed(c.state, next) {
        sync.put(&out, "ok", sync.flag(false))
        sync.put(&out, "error", sync.text(sync.cat(a, sync.cat(a, "cannot go ", c.state), sync.cat(a, " → ", next))))
        ret ir.obj_value(&out)
    }
    var entry = sync.obj(a)
    sync.put(&entry, "from", sync.text(c.state))
    sync.put(&entry, "to", sync.text(next))
    if has_at { sync.put(&entry, "at", at) }
    sync.push_value(&c.log, ir.obj_value(&entry))
    c.state = next
    sync.put(&out, "ok", sync.flag(true))
    sync.put(&out, "replayNow", sync.flag(str.eq(next, "online")))
    ret ir.obj_value(&out)
}

fn connectivity_history(c: *const Connectivity) -> []const json.Value {
    ret list.slice_const[json.Value](&c.log)
}

// --- replay with conflict detection ----------------------------------------------------------------------------------

// Split a queue against the versions the server holds (`recordId -> version`): `{apply, creates, conflicts}`. A write
// whose record is gone or has moved past its `baseVersion` is a conflict, never sent.
fn plan_replay(a: *mem.Arena, queue: []const json.Value, versions: json.Value) -> json.Value {
    var apply = sync.empty_list(a)
    var creates = sync.empty_list(a)
    var conflicts = sync.empty_list(a)
    var at = 0usize
    while at < queue.len {
        let w = queue[at]
        at += 1usize
        let (op, has_op) = sync.member_text(w, "op")
        if has_op && str.eq(op, "create") {
            sync.push_value(&creates, w)
            continue
        }
        var have_version = false
        var server_version: json.Value = .Null
        let (rid, has_rid) = sync.get(w, "recordId")
        if has_rid {
            switch rid {
            case .String as key:
                let (v, found) = sync.get(versions, key)
                if found {
                    have_version = true
                    server_version = v
                }
            default:
                have_version = false
            }
        }
        if !have_version {
            var c = sync.obj(a)
            sync.put(&c, "write", w)
            sync.put(&c, "reason", sync.text("record-deleted-on-server"))
            sync.push_value(&conflicts, ir.obj_value(&c))
            continue
        }
        let (base, has_base) = sync.get(w, "baseVersion")
        var behind = false
        if has_base {
            switch server_version {
            case .Number as sv:
                switch base {
                case .Number as bv:
                    let (x, ex) = json.number_f64(sv)
                    let (y, ey) = json.number_f64(bv)
                    behind = ex == ok && ey == ok && x > y
                default:
                    behind = false
                }
            default:
                behind = false
            }
        }
        if behind {
            var c = sync.obj(a)
            sync.put(&c, "write", w)
            sync.put(&c, "reason", sync.text("changed-on-server"))
            sync.put(&c, "serverVersion", server_version)
            sync.push_value(&conflicts, ir.obj_value(&c))
        } else {
            sync.push_value(&apply, w)
        }
    }
    var out = sync.obj(a)
    sync.put(&out, "apply", json.Value{ Array: list.slice_const[json.Value](&apply) })
    sync.put(&out, "creates", json.Value{ Array: list.slice_const[json.Value](&creates) })
    sync.put(&out, "conflicts", json.Value{ Array: list.slice_const[json.Value](&conflicts) })
    ret ir.obj_value(&out)
}

// Resolve one replay conflict (`{write, serverVersion?}`) by `choice`: "local-wins" re-bases the write onto the server
// version, "server-wins" drops it, "merge" keeps the local values of the fields the server did not change.
fn resolve_replay_conflict(a: *mem.Arena, conflict: json.Value, choice: str, server_record: json.Value, has_server: bool, base_record: json.Value, has_base: bool) -> json.Value {
    let w = ir.value_of(conflict, "write")
    var out = sync.obj(a)
    if str.eq(choice, "server-wins") {
        sync.put(&out, "action", sync.text("drop"))
        sync.put(&out, "write", .Null)
        ret ir.obj_value(&out)
    }
    let (sv, has_sv) = sync.get(conflict, "serverVersion")
    if str.eq(choice, "local-wins") {
        sync.put(&out, "action", sync.text("apply"))
        sync.put(&out, "write", with_member(a, w, "baseVersion", sv, has_sv))
        ret ir.obj_value(&out)
    }
    if str.eq(choice, "merge") {
        if !has_server || !ir.truthy(server_record) || !has_base || !ir.truthy(base_record) {
            sync.put(&out, "action", sync.text("error"))
            sync.put(&out, "error", sync.text("merge needs base and server records"))
            ret ir.obj_value(&out)
        }
        var merged = sync.obj(a)
        let (members, is_object) = ir.members_of(object_or_empty(w, "values"))
        var at = 0usize
        while at < members.len {
            let field = members[at].key
            let (sx, has_sx) = sync.get(server_record, field)
            let (bx, has_bx) = sync.get(base_record, field)
            if same_member(a, sx, has_sx, bx, has_bx) { sync.put(&merged, field, members[at].value) }
            at += 1usize
        }
        if merged.len == 0usize {
            sync.put(&out, "action", sync.text("drop"))
            sync.put(&out, "write", .Null)
            sync.put(&out, "note", sync.text("server changed every edited field"))
            ret ir.obj_value(&out)
        }
        let rebased = with_member(a, w, "values", ir.obj_value(&merged), true)
        sync.put(&out, "action", sync.text("apply"))
        sync.put(&out, "write", with_member(a, rebased, "baseVersion", sv, has_sv))
        ret ir.obj_value(&out)
    }
    sync.put(&out, "action", sync.text("error"))
    sync.put(&out, "error", sync.text(sync.cat(a, sync.cat(a, "unknown choice \"", choice), "\"")))
    ret ir.obj_value(&out)
}

// --- the conflict a person reviews -----------------------------------------------------------------------------------

// A server row's business fields: without `id`, `updatedAt` and `updated_at`.
fn server_data(a: *mem.Arena, server: json.Value) -> json.Value {
    var out = sync.spread(a, server, ir.empty_object())
    sync.unset(&out, "id")
    sync.unset(&out, "updatedAt")
    sync.unset(&out, "updated_at")
    ret ir.obj_value(&out)
}

fn member_names(a: *mem.Arena, mine: json.Value, theirs: json.Value) -> []const str {
    var names = sync.empty_list(a)
    let (mm, mo) = ir.members_of(mine)
    var at = 0usize
    while at < mm.len {
        sync.push_value(&names, sync.text(mm[at].key))
        at += 1usize
    }
    let (tm, to) = ir.members_of(theirs)
    var k = 0usize
    while k < tm.len {
        var seen = false
        var j = 0usize
        while j < names.len {
            if str.eq(sync.as_text(names.items[j]), tm[k].key) { seen = true }
            j += 1usize
        }
        if !seen { sync.push_value(&names, sync.text(tm[k].key)) }
        k += 1usize
    }
    let (out, e) = mem.alloc[str](a, names.len + 1usize)
    if e != ok { ret zero }
    var n = 0usize
    while n < names.len {
        out[n] = sync.as_text(names.items[n])
        n += 1usize
    }
    ret out[0usize..names.len]
}

fn names_include(names: json.Value, name: str) -> bool {
    let xs = sync.items(names)
    var at = 0usize
    while at < xs.len {
        if str.eq(sync.as_text(xs[at]), name) { ret true }
        at += 1usize
    }
    ret false
}

// Turn what a flush reported (`[{mutation, server}]`) into what a person can decide about: `{items, count}`. A conflict
// whose server row is gone is kept and marked.
fn build_conflict_review(a: *mem.Arena, conflicts: []const json.Value) -> json.Value {
    var items = sync.empty_list(a)
    var at = 0usize
    while at < conflicts.len {
        let raw = conflicts[at]
        at += 1usize
        let (mutation, has_mutation) = sync.get(raw, "mutation")
        if !ir.truthy(raw) || !has_mutation || !ir.truthy(mutation) { continue }
        let mine = object_or_empty(mutation, "payload")
        let (server, has_server) = sync.get(raw, "server")
        let deleted = !has_server || !ir.truthy(server)
        var theirs: json.Value = .Null
        if !deleted { theirs = server_data(a, server) }
        let (base, has_base) = sync.get(mutation, "baseData")
        let have_base = has_base && ir.truthy(base)
        var contested: json.Value = json.Value{ Array: zero }
        var mergeable = false
        var blocked = ""
        if deleted {
            blocked = "record-deleted"
        } else if !have_base {
            blocked = "no-base-version"
        } else {
            let diff = sync.detect_field_conflicts(a, base, true, mine, theirs)
            if !ir.truthy(ir.value_of(diff, "ok")) {
                blocked = sync.as_text(ir.value_of(diff, "reason"))
            } else {
                contested = ir.value_of(diff, "conflicting")
                mergeable = true
            }
        }
        var compare_theirs = ir.empty_object()
        if !deleted { compare_theirs = theirs }
        let names = member_names(a, mine, compare_theirs)
        var fields = sync.empty_list(a)
        var n = 0usize
        while n < names.len {
            let (mv, has_mv) = sync.get(mine, names[n])
            var tv: json.Value = .Null
            var has_tv = false
            if !deleted {
                let (x, hx) = sync.get(theirs, names[n])
                tv = x
                has_tv = hx
            }
            if !same_member(a, mv, has_mv, tv, has_tv) {
                var f = sync.obj(a)
                sync.put(&f, "name", sync.text(names[n]))
                if has_mv { sync.put(&f, "mine", mv) }
                if has_tv { sync.put(&f, "theirs", tv) }
                sync.put(&f, "differs", sync.flag(true))
                sync.put(&f, "contested", sync.flag(names_include(contested, names[n])))
                sync.push_value(&fields, ir.obj_value(&f))
            }
            n += 1usize
        }
        var item = sync.obj(a)
        var id_text = ""
        let (mid, has_mid) = sync.get(mutation, "id")
        let (mrid, has_mrid) = sync.get(mutation, "recordId")
        if has_mid && ir.truthy(mid) {
            id_text = js_string(mid, true)
        } else if has_mrid && ir.truthy(mrid) {
            id_text = js_string(mrid, true)
        } else {
            id_text = js_string(sync.number(a, i64(items.len)), true)
        }
        sync.put(&item, "id", sync.text(id_text))
        let (mt, has_mt) = sync.get(mutation, "table")
        var table_text = ""
        if has_mt && ir.truthy(mt) { table_text = js_string(mt, true) }
        sync.put(&item, "table", sync.text(table_text))
        var record_text = ""
        if has_mrid && ir.truthy(mrid) { record_text = js_string(mrid, true) }
        sync.put(&item, "recordId", sync.text(record_text))
        if deleted {
            sync.put(&item, "kind", sync.text("record-deleted-on-server"))
        } else {
            sync.put(&item, "kind", sync.text("changed-on-server"))
        }
        sync.put(&item, "fields", json.Value{ Array: list.slice_const[json.Value](&fields) })
        sync.put(&item, "mergeable", sync.flag(mergeable))
        if blocked.len > 0usize { sync.put(&item, "mergeBlockedBy", sync.text(blocked)) } else { sync.put(&item, "mergeBlockedBy", .Null) }
        sync.put(&item, "contestedFields", contested)
        var choices = sync.empty_list(a)
        sync.push_value(&choices, sync.text("keep-mine"))
        sync.push_value(&choices, sync.text("keep-theirs"))
        if mergeable { sync.push_value(&choices, sync.text("merge")) }
        sync.put(&item, "choices", json.Value{ Array: list.slice_const[json.Value](&choices) })
        sync.push_value(&items, ir.obj_value(&item))
    }
    var out = sync.obj(a)
    sync.put(&out, "items", json.Value{ Array: list.slice_const[json.Value](&items) })
    sync.put(&out, "count", sync.number(a, i64(items.len)))
    ret ir.obj_value(&out)
}

// The queue operation a choice means, for one review item: `{action: "push", payload, baseUpdatedAt}`, `{action:
// "drop"}`, or `{action: "refuse", reason, fields?}`. Keep-mine re-bases onto the server's stamp; merge refuses, naming
// them, when both sides changed a field.
fn plan_offline_resolution(a: *mem.Arena, item: json.Value, has_item: bool, choice: str, server: json.Value, has_server: bool, mutation: json.Value, has_mutation: bool) -> json.Value {
    var out = sync.obj(a)
    if !has_item || !ir.truthy(item) || choice.len == 0usize {
        sync.put(&out, "action", sync.text("refuse"))
        sync.put(&out, "reason", sync.text("nothing-to-resolve"))
        ret ir.obj_value(&out)
    }
    if !names_include(ir.value_of(item, "choices"), choice) {
        sync.put(&out, "action", sync.text("refuse"))
        sync.put(&out, "reason", sync.text("choice-unavailable"))
        sync.put(&out, "fields", json.Value{ Array: zero })
        ret ir.obj_value(&out)
    }
    var stamp: json.Value = .Null
    if has_server && ir.truthy(server) {
        if truthy_member(server, "updatedAt") {
            stamp = ir.value_of(server, "updatedAt")
        } else if truthy_member(server, "updated_at") {
            stamp = ir.value_of(server, "updated_at")
        }
    }
    if str.eq(choice, "keep-theirs") {
        sync.put(&out, "action", sync.text("drop"))
        ret ir.obj_value(&out)
    }
    var mine = ir.empty_object()
    if has_mutation && ir.truthy(mutation) { mine = object_or_empty(mutation, "payload") }
    if str.eq(choice, "keep-mine") {
        sync.put(&out, "action", sync.text("push"))
        sync.put(&out, "payload", mine)
        sync.put(&out, "baseUpdatedAt", stamp)
        ret ir.obj_value(&out)
    }
    var base: json.Value = .Null
    var have_base = false
    if has_mutation && ir.truthy(mutation) {
        let (b, hb) = sync.get(mutation, "baseData")
        if hb && ir.truthy(b) {
            base = b
            have_base = true
        }
    }
    var theirs = ir.empty_object()
    if has_server && ir.truthy(server) { theirs = server_data(a, server) }
    if !have_base {
        sync.put(&out, "action", sync.text("refuse"))
        sync.put(&out, "reason", sync.text("no-base-version"))
        ret ir.obj_value(&out)
    }
    let diff = sync.detect_field_conflicts(a, base, true, mine, theirs)
    if !ir.truthy(ir.value_of(diff, "ok")) {
        sync.put(&out, "action", sync.text("refuse"))
        sync.put(&out, "reason", ir.value_of(diff, "reason"))
        ret ir.obj_value(&out)
    }
    if sync.items(ir.value_of(diff, "conflicting")).len > 0usize {
        sync.put(&out, "action", sync.text("refuse"))
        sync.put(&out, "reason", sync.text("fields-contested"))
        sync.put(&out, "fields", ir.value_of(diff, "conflicting"))
        ret ir.obj_value(&out)
    }
    var merged = sync.spread(a, base, ir.empty_object())
    let theirs_changed = sync.items(ir.value_of(diff, "theirsChanged"))
    var t = 0usize
    while t < theirs_changed.len {
        let field = sync.as_text(theirs_changed[t])
        let (v, found) = sync.get(theirs, field)
        if found { sync.put(&merged, field, v) } else { sync.unset(&merged, field) }
        t += 1usize
    }
    let mine_changed = sync.items(ir.value_of(diff, "mineChanged"))
    var m = 0usize
    while m < mine_changed.len {
        let field = sync.as_text(mine_changed[m])
        let (v, found) = sync.get(mine, field)
        if found { sync.put(&merged, field, v) } else { sync.unset(&merged, field) }
        m += 1usize
    }
    sync.put(&out, "action", sync.text("push"))
    sync.put(&out, "payload", ir.obj_value(&merged))
    sync.put(&out, "baseUpdatedAt", stamp)
    ret ir.obj_value(&out)
}

// How many conflicts are outstanding, for the connectivity badge.
fn conflict_count(review: json.Value) -> i64 {
    ret i64(sync.items(ir.value_of(review, "items")).len)
}

// --- access purge ----------------------------------------------------------------------------------------------------

fn string_in(values: []const json.Value, s: str) -> bool {
    var at = 0usize
    while at < values.len {
        let (t, is_text) = ir.string_of(values[at])
        if is_text && str.eq(t, s) { ret true }
        at += 1usize
    }
    ret false
}

// Decide what has to leave a cache: `cached` is `[{tableId, recordIds}]`, `readable` is `{tableIds, recordIdsByTable}`
// as the server answered for exactly those ids. A probe that did not succeed (or no answer) yields `{ok: false}` and
// purges nothing.
fn plan_cache_purge(a: *mem.Arena, cached: []const json.Value, readable: json.Value, has_readable: bool, probe_ok: bool) -> json.Value {
    var out = sync.obj(a)
    if !probe_ok || !has_readable || !ir.truthy(readable) {
        sync.put(&out, "ok", sync.flag(false))
        sync.put(&out, "reason", sync.text("probe-failed"))
        sync.put(&out, "tables", json.Value{ Array: zero })
        sync.put(&out, "records", ir.empty_object())
        sync.put(&out, "purged", sync.number(a, 0i64))
        ret ir.obj_value(&out)
    }
    let table_ids = sync.items(ir.value_of(readable, "tableIds"))
    var tables = sync.empty_list(a)
    var records = sync.obj(a)
    var purged = 0i64
    var at = 0usize
    while at < cached.len {
        let scope = cached[at]
        at += 1usize
        if !ir.truthy(scope) || !truthy_member(scope, "tableId") { continue }
        let table_id = js_string(ir.value_of(scope, "tableId"), true)
        let ids = sync.items(ir.value_of(scope, "recordIds"))
        var readable_table = false
        var t = 0usize
        while t < table_ids.len {
            if str.eq(js_string(table_ids[t], true), table_id) { readable_table = true }
            t += 1usize
        }
        if !readable_table {
            sync.push_value(&tables, sync.text(table_id))
            purged += i64(ids.len)
            continue
        }
        let (by_table, has_by_table) = sync.get(readable, "recordIdsByTable")
        var still: []const json.Value = zero
        if has_by_table {
            let (list_value, found) = sync.get(by_table, table_id)
            if found && ir.truthy(list_value) { still = sync.items(list_value) }
        }
        var gone = sync.empty_list(a)
        var i = 0usize
        while i < ids.len {
            let id = js_string(ids[i], true)
            if !string_in(still, id) { sync.push_value(&gone, sync.text(id)) }
            i += 1usize
        }
        if gone.len > 0usize {
            sync.put(&records, table_id, json.Value{ Array: list.slice_const[json.Value](&gone) })
            purged += i64(gone.len)
        }
    }
    sync.put(&out, "ok", sync.flag(true))
    sync.put(&out, "tables", json.Value{ Array: list.slice_const[json.Value](&tables) })
    sync.put(&out, "records", ir.obj_value(&records))
    sync.put(&out, "purged", sync.number(a, purged))
    ret ir.obj_value(&out)
}

// Apply a plan to a read cache: whole snapshots evicted, named records dropped. A plan that is not `ok` does nothing and
// says so.
fn apply_cache_purge(a: *mem.Arena, c: *ReadCache, plan: json.Value, has_plan: bool) -> json.Value {
    var out = sync.obj(a)
    if !has_plan || !ir.truthy(plan) || !truthy_member(plan, "ok") {
        sync.put(&out, "applied", sync.flag(false))
        sync.put(&out, "tablesEvicted", sync.number(a, 0i64))
        sync.put(&out, "recordsDropped", sync.number(a, 0i64))
        var reason = "no-plan"
        if has_plan && ir.truthy(plan) && truthy_member(plan, "reason") { reason = js_string(ir.value_of(plan, "reason"), true) }
        sync.put(&out, "reason", sync.text(reason))
        ret ir.obj_value(&out)
    }
    var evicted = 0i64
    var dropped = 0i64
    let tables = sync.items(ir.value_of(plan, "tables"))
    var t = 0usize
    while t < tables.len {
        let was_there = cache_evict(c, tables[t])
        evicted += 1i64
        t += 1usize
    }
    let (members, is_object) = ir.members_of(ir.value_of(plan, "records"))
    var m = 0usize
    while m < members.len {
        let ids = sync.items(members[m].value)
        let (names, e) = mem.alloc[str](a, ids.len + 1usize)
        if e != ok { ret .Null }
        var k = 0usize
        while k < ids.len {
            names[k] = js_string(ids[k], true)
            k += 1usize
        }
        dropped += cache_drop_records(c, sync.text(members[m].key), names[0usize..ids.len])
        m += 1usize
    }
    sync.put(&out, "applied", sync.flag(true))
    sync.put(&out, "tablesEvicted", sync.number(a, evicted))
    sync.put(&out, "recordsDropped", sync.number(a, dropped))
    ret ir.obj_value(&out)
}

// What happened, as a code and two counts: "probe-failed", "nothing-to-purge" or "purged".
fn purge_outcome(a: *mem.Arena, plan: json.Value, has_plan: bool) -> json.Value {
    var out = sync.obj(a)
    if !has_plan || !ir.truthy(plan) || !truthy_member(plan, "ok") {
        sync.put(&out, "code", sync.text("probe-failed"))
        sync.put(&out, "tables", sync.number(a, 0i64))
        sync.put(&out, "records", sync.number(a, 0i64))
        ret ir.obj_value(&out)
    }
    let tables = i64(sync.items(ir.value_of(plan, "tables")).len)
    var records = 0i64
    let (members, is_object) = ir.members_of(ir.value_of(plan, "records"))
    var at = 0usize
    while at < members.len {
        records += i64(sync.items(members[at].value).len)
        at += 1usize
    }
    if tables == 0i64 && records == 0i64 {
        sync.put(&out, "code", sync.text("nothing-to-purge"))
        sync.put(&out, "tables", sync.number(a, 0i64))
        sync.put(&out, "records", sync.number(a, 0i64))
        ret ir.obj_value(&out)
    }
    sync.put(&out, "code", sync.text("purged"))
    sync.put(&out, "tables", sync.number(a, tables))
    sync.put(&out, "records", sync.number(a, records))
    ret ir.obj_value(&out)
}
