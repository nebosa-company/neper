// `e.algo.sync` against appdor's offline modules (src/offline/index.js, durable-queue.js, sync-engine.js):
// scripts/sync_reference.mjs runs random operation scripts -- the outbox over a memory store with scripted save failures,
// the coalescing queue, cursors, delta pulls and applies, conflict detection and resolution, full syncs -- and writes
// `{"spec", "ops", "e"}` lines. The fixture replays the operations over the Neper module with stand-ins for the store
// (a saved array that fails per `saveFailures`), the server (`server` records served in cursor order) and the push
// (`pushPlan`, a cycle of outcomes per record id), and compares the canonical results one per line.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.sync as sync
use e.data.list as list
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

type Sim = struct { a: *mem.Arena, spec: json.Value, clock: i64, tick: i64, stored: []const json.Value, saves: i64, names: [16]str, counts: [16]i64, used: usize }

fn field(v: json.Value, key: str) -> (json.Value, bool) {
    let (x, found) = ir.get(v, key)
    ret (x, found)
}

fn text_field(v: json.Value, key: str) -> str {
    let (x, found) = field(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn items(v: json.Value) -> []const json.Value {
    let (xs, is_array) = ir.items_of(v)
    ret xs
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn count_of(v: json.Value, key: str, fallback: i64) -> i64 {
    let (x, found) = field(v, key)
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

fn flag_of(v: json.Value, key: str) -> bool {
    let (x, found) = field(v, key)
    if !found { ret false }
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

fn number(a: *mem.Arena, n: i64) -> json.Value {
    let (v, e) = json.number_from_i64(a, n)
    if e != ok { os.exit(82i32) }
    ret json.Value{ Number: v }
}

fn strings_of(a: *mem.Arena, v: json.Value) -> []const str {
    let xs = items(v)
    let (out, e) = mem.alloc[str](a, xs.len + 1usize)
    if e != ok { os.exit(83i32) }
    var at = 0usize
    while at < xs.len {
        let (s, is_text) = ir.string_of(xs[at])
        out[at] = s
        at += 1usize
    }
    ret out[0usize..xs.len]
}

// --- the stand-ins --------------------------------------------------------------------------------------------------

fn sim_now(ctx: *void) -> i64 {
    var sim = mem.cast[*Sim](ctx)
    let v = sim.clock
    sim.clock = sim.clock + sim.tick
    ret v
}

fn sim_load(ctx: *void) -> []const json.Value {
    var sim = mem.cast[*Sim](ctx)
    ret sim.stored
}

fn sim_save(ctx: *void, next: []const json.Value) -> sync.SaveResult {
    var sim = mem.cast[*Sim](ctx)
    let plan = items(ir.value_of(sim.spec, "saveFailures"))
    var how = ""
    if plan.len > 0usize {
        let (s, is_text) = ir.string_of(plan[usize(sim.saves) % plan.len])
        if is_text { how = s }
    }
    sim.saves += 1i64
    if str.eq(how, "quota") { ret sync.SaveResult { saved: false, quota: true, message: "full" } }
    if str.eq(how, "io") { ret sync.SaveResult { saved: false, quota: false, message: "disk broke" } }
    sim.stored = next
    ret sync.SaveResult { saved: true, quota: false, message: "" }
}

fn sim_clear(ctx: *void) -> sync.SaveResult {
    var sim = mem.cast[*Sim](ctx)
    if flag_of(sim.spec, "clearFails") { ret sync.SaveResult { saved: false, quota: false, message: "clear broke" } }
    var none: []const json.Value = zero
    sim.stored = none
    ret sync.SaveResult { saved: true, quota: false, message: "" }
}

fn bump(sim: *Sim, name: str) -> i64 {
    var at = 0usize
    while at < sim.used {
        if str.eq(sim.names[at], name) {
            let before = sim.counts[at]
            sim.counts[at] = before + 1i64
            ret before
        }
        at += 1usize
    }
    sim.names[sim.used] = name
    sim.counts[sim.used] = 1i64
    sim.used += 1usize
    ret 0i64
}

fn sim_push(ctx: *void, mutation: json.Value) -> sync.PushResult {
    var sim = mem.cast[*Sim](ctx)
    let a = sim.a
    var key = ""
    let (rid, have_rid) = field(mutation, "recordId")
    switch rid {
    case .String as s:
        key = s
    case .Number as n:
        key = n.lexeme
    default:
        key = ""
    }
    let n = bump(sim, key)
    let (plan, have_plan) = field(ir.value_of(sim.spec, "pushPlan"), key)
    var outcome = "ok"
    let steps = items(plan)
    if have_plan && steps.len > 0usize {
        let (s, is_text) = ir.string_of(steps[usize(n) % steps.len])
        if is_text { outcome = s }
    }
    if str.eq(outcome, "ok") {
        ret sync.PushResult { accepted: true, conflict: false, server: .Null, has_server: false, failure: "", has_failure: false }
    }
    if str.eq(outcome, "conflict") {
        let (made, e) = ir.new_obj(a)
        if e != ok { os.exit(84i32) }
        var o = made
        let one = ir.put(&o, "id", json.Value{ String: key })
        let two = ir.put(&o, "v", number(a, n))
        ret sync.PushResult { accepted: false, conflict: true, server: ir.obj_value(&o), has_server: true, failure: "", has_failure: false }
    }
    if str.eq(outcome, "throw") {
        ret sync.PushResult { accepted: false, conflict: false, server: .Null, has_server: false, failure: join(a, "boom ", key), has_failure: true }
    }
    let message = join(a, join(a, join(a, "err ", key), " "), ir.index_text(a, usize(n)))
    ret sync.PushResult { accepted: false, conflict: false, server: .Null, has_server: false, failure: message, has_failure: true }
}

// The server's page after a cursor, in `(updatedAt, id)` order, `min(limit, pageSize)` records; the deletions ride on the
// first page only.
fn sim_fetch(ctx: *void, cursor: json.Value, limit: i64) -> json.Value {
    var sim = mem.cast[*Sim](ctx)
    let a = sim.a
    let server = items(ir.value_of(sim.spec, "server"))
    let ignore = flag_of(sim.spec, "ignoreCursor")
    let (picked, e) = list.init[json.Value](a, 8usize)
    if e != ok { os.exit(85i32) }
    var chosen = picked
    var at = 0usize
    while at < server.len {
        if ignore || sync.is_after_cursor(server[at], cursor) {
            let pushed = list.push[json.Value](&chosen, server[at])
        }
        at += 1usize
    }
    // insertion sort by (updatedAt, id)
    var i = 1usize
    while i < chosen.len {
        let item = chosen.items[i]
        var j = i
        while j > 0usize && sorts_before(item, chosen.items[j - 1usize]) {
            chosen.items[j] = chosen.items[j - 1usize]
            j -= 1usize
        }
        chosen.items[j] = item
        i += 1usize
    }
    var take = limit
    let page = count_of(sim.spec, "pageSize", 200i64)
    if page < take { take = page }
    var shown = chosen.len
    if take >= 0i64 && usize(take) < shown { shown = usize(take) }
    let (made, made_error) = ir.new_obj(a)
    if made_error != ok { os.exit(86i32) }
    var o = made
    let r = ir.put(&o, "records", json.Value{ Array: list.slice_const[json.Value](&chosen)[0usize..shown] })
    let (at_value, have_at) = field(cursor, "updatedAt")
    var first = !have_at
    switch at_value {
    case .Null:
        first = true
    default:
        first = first
    }
    if first {
        let d = ir.put(&o, "deletions", ir.value_of(sim.spec, "deletions"))
    }
    ret ir.obj_value(&o)
}

fn sorts_before(x: json.Value, y: json.Value) -> bool {
    let xa = text_field(x, "updatedAt")
    let ya = text_field(y, "updatedAt")
    let order = str.compare(xa, ya)
    if order != 0i32 { ret order < 0i32 }
    ret str.compare(text_field(x, "id"), text_field(y, "id")) < 0i32
}

// --- the case -------------------------------------------------------------------------------------------------------

fn run_case(a: *mem.Arena, root: json.Value) -> str {
    let (spec, have_spec) = field(root, "spec")
    var sim = Sim { a: a, spec: spec, clock: count_of(spec, "start", 1000i64), tick: count_of(spec, "tick", 1i64), stored: zero, saves: 0i64, names: zero, counts: zero, used: 0usize }
    let store = sync.StoreHooks { ctx: mem.cast[*void](&sim), durable: flag_of(spec, "durable"), load: sim_load, save: sim_save, clear: sim_clear }
    let remote = sync.Remote { ctx: mem.cast[*void](&sim), now: sim_now, fetch_page: sim_fetch, push: sim_push }
    var outbox = sync.new_outbox(a, &store, sim_now, mem.cast[*void](&sim), count_of(spec, "maxAttempts", 0i64), count_of(spec, "baseDelayMs", 0i64))
    var out = ""
    let ops = items(ir.value_of(root, "ops"))
    var at = 0usize
    while at < ops.len {
        let op = ops[at]
        let name = text_field(op, "op")
        var result: json.Value = .Null
        if str.eq(name, "restore") {
            result = sync.restore(&outbox)
        } else if str.eq(name, "add") {
            result = sync.add(&outbox, ir.value_of(op, "mutation"))
        } else if str.eq(name, "flush") {
            let (given_at, have_at) = field(op, "at")
            var instant = 0i64
            if have_at { instant = count_of(op, "at", 0i64) } else { instant = sim_now(mem.cast[*void](&sim)) }
            result = sync.flush(&outbox, &remote, instant, flag_of(op, "continueOnError"), text_field(op, "resolve"))
        } else if str.eq(name, "revive") {
            result = sync.revive(&outbox, count_of(op, "seq", 0i64))
        } else if str.eq(name, "discard") {
            let (made, e) = ir.new_obj(a)
            if e != ok { os.exit(87i32) }
            var o = made
            let stored = ir.put(&o, "ok", json.Value{ Bool: sync.discard(&outbox, count_of(op, "seq", 0i64)) })
            result = ir.obj_value(&o)
        } else if str.eq(name, "settle") {
            let (made, e) = ir.new_obj(a)
            if e != ok { os.exit(87i32) }
            var o = made
            let stored = ir.put(&o, "ok", json.Value{ Bool: sync.settle(&outbox, count_of(op, "seq", 0i64)) })
            result = ir.obj_value(&o)
        } else if str.eq(name, "release") {
            result = number(a, sync.release_attachments(&outbox, strings_of(a, ir.value_of(op, "ids"))))
        } else if str.eq(name, "clear") {
            sync.clear(&outbox)
        } else if str.eq(name, "pending") {
            result = json.Value{ Array: sync.pending(&outbox) }
        } else if str.eq(name, "dead") {
            result = json.Value{ Array: sync.dead_letters(&outbox) }
        } else if str.eq(name, "ready") {
            result = json.Value{ Array: sync.ready(a, &outbox, count_of(op, "at", 0i64)) }
        } else if str.eq(name, "describe") {
            result = sync.describe_outbox(a, &outbox)
        } else if str.eq(name, "runSync") {
            result = sync.run_sync(a, &outbox, true, &remote, items(ir.value_of(op, "local")), ir.value_of(op, "cursor"), text_field(op, "strategy"), ir.value_of(op, "table"))
        } else if str.eq(name, "pull") {
            result = sync.pull_changes(a, &remote, ir.value_of(op, "cursor"), count_of(op, "limit", 200i64), count_of(op, "maxPages", 50i64))
        } else if str.eq(name, "syncQueue") {
            var stop = true
            let (given, have_given) = field(op, "stopOnError")
            if have_given { stop = flag_of(op, "stopOnError") }
            result = sync.sync_queue(a, items(ir.value_of(op, "queue")), &remote, text_field(op, "resolve"), stop)
        } else if str.eq(name, "enqueue") {
            result = json.Value{ Array: sync.enqueue(a, items(ir.value_of(op, "queue")), ir.value_of(op, "mutation")) }
        } else if str.eq(name, "optimistic") {
            result = json.Value{ Array: sync.apply_optimistic(a, items(ir.value_of(op, "records")), ir.value_of(op, "mutation")) }
        } else if str.eq(name, "cursor") {
            let cursor = ir.value_of(op, "cursor")
            let encoded = sync.encode_cursor(a, cursor)
            let (made, e) = ir.new_obj(a)
            if e != ok { os.exit(88i32) }
            var o = made
            let p1 = ir.put(&o, "enc", json.Value{ String: encoded })
            let p2 = ir.put(&o, "dec", sync.decode_cursor(a, encoded))
            let p3 = ir.put(&o, "after", json.Value{ Bool: sync.is_after_cursor(ir.value_of(op, "record"), cursor) })
            let p4 = ir.put(&o, "adv", sync.advance_cursor(a, items(ir.value_of(op, "records")), cursor))
            result = ir.obj_value(&o)
        } else if str.eq(name, "resolve") {
            result = sync.resolve_conflict(a, ir.value_of(op, "conflict"), text_field(op, "strategy"))
        } else if str.eq(name, "detect") {
            let (base, have_base) = field(op, "base")
            result = sync.detect_field_conflicts(a, base, have_base, ir.value_of(op, "mine"), ir.value_of(op, "theirs"))
        } else if str.eq(name, "apply") {
            result = sync.apply_changes(a, items(ir.value_of(op, "local")), ir.value_of(op, "changes"), strings_of(a, ir.value_of(op, "pendingIds")))
        } else {
            os.exit(89i32)
        }
        let (text, e) = chain.canonical_json(a, result)
        if e != ok { os.exit(81i32) }
        if at > 0usize { out = join(a, out, "\n") }
        out = join(a, out, text)
        at += 1usize
    }
    ret out
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                want = text_field(root, "e")
                got = run_case(a, root)
                good = str.eq(got, want)
            }
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(join(a, "\ngot ", got))
                let shown_want = io.print(join(a, "\nwant ", want))
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

type CheckState = struct { a: *mem.Arena, fetch_calls: i64, push_calls: i64, fetch_mode: i64, push_limit: i64 }

fn check_now(ctx: *void) -> i64 { ret 0i64 }
fn check_load(ctx: *void) -> []const json.Value { ret zero }
fn check_save(ctx: *void, next: []const json.Value) -> sync.SaveResult { ret sync.SaveResult { saved: true, quota: false, message: "" } }
fn check_clear(ctx: *void) -> sync.SaveResult { ret sync.SaveResult { saved: true, quota: false, message: "" } }

fn check_push(ctx: *void, mutation: json.Value) -> sync.PushResult {
    var st = mem.cast[*CheckState](ctx)
    st.push_calls += 1i64
    if st.push_limit >= 0i64 && st.push_calls > st.push_limit {
        ret sync.PushResult { accepted: false, conflict: false, server: .Null, has_server: false, failure: "offline", has_failure: true }
    }
    ret sync.PushResult { accepted: true, conflict: false, server: .Null, has_server: false, failure: "", has_failure: false }
}

// mode 0: always orders/5; mode 1: empty then orders/6; mode 2: always one record.
fn check_fetch(ctx: *void, cursor: json.Value, limit: i64) -> json.Value {
    var st = mem.cast[*CheckState](ctx)
    st.fetch_calls += 1i64
    var records = sync.empty_list(st.a)
    var page_id = ""
    var has_row = false
    if st.fetch_mode == 0i64 {
        page_id = "5"
        has_row = true
    } else if st.fetch_mode == 1i64 && st.fetch_calls >= 2i64 {
        page_id = "6"
        has_row = true
    } else if st.fetch_mode == 2i64 {
        page_id = "a"
        has_row = true
    }
    if has_row {
        var row = sync.obj(st.a)
        sync.put(&row, "id", sync.text(page_id))
        sync.put(&row, "v", sync.number(st.a, 99i64))
        sync.push_value(&records, ir.obj_value(&row))
    }
    var out = sync.obj(st.a)
    sync.put(&out, "records", json.Value{ Array: list.slice_const[json.Value](&records) })
    sync.put(&out, "deletions", json.Value{ Array: zero })
    ret ir.obj_value(&out)
}

fn check_mutation(a: *mem.Arena, table: str, rid: str, op: str) -> json.Value {
    var m = sync.obj(a)
    sync.put(&m, "table", sync.text(table))
    sync.put(&m, "recordId", sync.text(rid))
    sync.put(&m, "op", sync.text(op))
    sync.put(&m, "payload", ir.empty_object())
    ret ir.obj_value(&m)
}

fn check_count(v: json.Value, key: str) -> i64 {
    let (x, found) = sync.get(v, key)
    if !found { ret -999i64 }
    switch x {
    case .Number as n:
        let (z, e) = json.number_i64(n)
        if e == ok { ret z }
        ret -999i64
    default:
        ret -999i64
    }
}

fn check_flag(v: json.Value, key: str) -> bool {
    let (x, found) = sync.get(v, key)
    if !found { ret false }
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

fn check_local(a: *mem.Arena, source: str) -> []const json.Value {
    let (root, e) = json.parse(a, source, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
    if e != ok { os.exit(91i32) }
    ret sync.items(root)
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    // #217: a short last page is complete; pending ids are scoped to the synced
    // table; and the second pull still shadows writes left in the queue.
    var st_complete = CheckState { a: a, fetch_calls: 0i64, push_calls: 0i64, fetch_mode: 2i64, push_limit: -1i64 }
    let remote_complete = sync.Remote { ctx: mem.cast[*void](&st_complete), now: check_now, fetch_page: check_fetch, push: check_push }
    let complete = sync.pull_changes(a, &remote_complete, .Null, 200i64, 1i64)
    if !check_flag(complete, "complete") { os.exit(60i32) }
    var st_scope = CheckState { a: a, fetch_calls: 0i64, push_calls: 0i64, fetch_mode: 0i64, push_limit: 0i64 }
    let remote_scope = sync.Remote { ctx: mem.cast[*void](&st_scope), now: check_now, fetch_page: check_fetch, push: check_push }
    let store_scope = sync.StoreHooks { ctx: mem.cast[*void](&st_scope), durable: true, load: check_load, save: check_save, clear: check_clear }
    var ob_scope = sync.new_outbox(a, &store_scope, check_now, mem.cast[*void](&st_scope), 3i64, 1000i64)
    sync.push_value(&ob_scope.queue, check_mutation(a, "customers", "5", "update"))
    let scoped = sync.run_sync(a, &ob_scope, true, &remote_scope, check_local(a, "[{\"id\":\"5\",\"v\":1}]"), .Null, "server-wins", sync.text("orders"))
    if check_count(scoped, "updated") != 1i64 || check_count(scoped, "shadowed") != 0i64 { os.exit(61i32) }
    var st_second = CheckState { a: a, fetch_calls: 0i64, push_calls: 0i64, fetch_mode: 1i64, push_limit: 1i64 }
    let remote_second = sync.Remote { ctx: mem.cast[*void](&st_second), now: check_now, fetch_page: check_fetch, push: check_push }
    let store_second = sync.StoreHooks { ctx: mem.cast[*void](&st_second), durable: true, load: check_load, save: check_save, clear: check_clear }
    var ob_second = sync.new_outbox(a, &store_second, check_now, mem.cast[*void](&st_second), 3i64, 1000i64)
    sync.push_value(&ob_second.queue, check_mutation(a, "orders", "7", "update"))
    sync.push_value(&ob_second.queue, check_mutation(a, "orders", "6", "update"))
    let twice = sync.run_sync(a, &ob_second, true, &remote_second, check_local(a, "[{\"id\":\"6\",\"v\":\"mine\"}]"), .Null, "server-wins", sync.text("orders"))
    if check_count(twice, "shadowed") != 1i64 || check_count(twice, "updated") != 0i64 { os.exit(62i32) }
    let (twice_rows, twice_found) = sync.get(twice, "records")
    let twice_list = sync.items(twice_rows)
    if !twice_found || twice_list.len != 1usize { os.exit(62i32) }
    let (mine, mine_found) = sync.get(twice_list[0usize], "v")
    if !mine_found || !str.eq(sync.as_text(mine), "mine") { os.exit(62i32) }
    try io.print("algo sync ok")
    ret ok
}
