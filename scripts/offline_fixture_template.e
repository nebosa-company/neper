// `e.algo.offline` against appdor's src/offline (write-queue.js, read-cache.js, conflict-review.js, access-purge.js):
// scripts/offline_reference.mjs runs random operation scripts -- network-failure classification, the write queue over a
// memory outbox, the read cache with overlay and purge, the connectivity machine, replay planning and resolution, the
// conflict review and its resolution plans -- and writes `{"spec", "ops", "e"}` lines. The fixture replays the operations
// over the Neper module with stand-ins for the store (always saves), the clock (a counter) and the push (`pushPlan`, a
// cycle of outcomes per record id), and compares the canonical results one per line.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.offline as offline
use e.algo.sync as sync
use e.data.list as list
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

type Sim = struct { a: *mem.Arena, spec: json.Value, clock: i64, tick: i64, stored: []const json.Value, names: [16]str, counts: [16]i64, used: usize }

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

fn flag_of(v: json.Value, key: str, fallback: bool) -> bool {
    let (x, found) = field(v, key)
    if !found { ret fallback }
    switch x {
    case .Bool as b:
        ret b
    default:
        ret fallback
    }
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
    sim.stored = next
    ret sync.SaveResult { saved: true, quota: false, message: "" }
}

fn sim_clear(ctx: *void) -> sync.SaveResult {
    var sim = mem.cast[*Sim](ctx)
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
        let two = ir.put(&o, "v", sync.number(a, n))
        ret sync.PushResult { accepted: false, conflict: true, server: ir.obj_value(&o), has_server: true, failure: "", has_failure: false }
    }
    if str.eq(outcome, "throw") {
        ret sync.PushResult { accepted: false, conflict: false, server: .Null, has_server: false, failure: join(a, "boom ", key), has_failure: true }
    }
    let message = join(a, join(a, join(a, "err ", key), " "), ir.index_text(a, usize(n)))
    ret sync.PushResult { accepted: false, conflict: false, server: .Null, has_server: false, failure: message, has_failure: true }
}

fn sim_fetch(ctx: *void, cursor: json.Value, limit: i64) -> json.Value {
    ret .Null
}

// --- the case -------------------------------------------------------------------------------------------------------

fn run_case(a: *mem.Arena, root: json.Value) -> str {
    let (spec, have_spec) = field(root, "spec")
    var sim = Sim { a: a, spec: spec, clock: count_of(spec, "start", 1000i64), tick: count_of(spec, "tick", 1i64), stored: zero, names: zero, counts: zero, used: 0usize }
    let store = sync.StoreHooks { ctx: mem.cast[*void](&sim), durable: false, load: sim_load, save: sim_save, clear: sim_clear }
    let remote = sync.Remote { ctx: mem.cast[*void](&sim), now: sim_now, fetch_page: sim_fetch, push: sim_push }
    var outbox = sync.new_outbox(a, &store, sim_now, mem.cast[*void](&sim), count_of(spec, "maxAttempts", 0i64), 0i64)
    let restored = sync.restore(&outbox)
    var cache = offline.new_read_cache(a, offline.FRESH_MS)
    var conn = offline.new_connectivity(a)
    var out = ""
    let ops = items(ir.value_of(root, "ops"))
    var at = 0usize
    while at < ops.len {
        let op = ops[at]
        let name = text_field(op, "op")
        var result: json.Value = .Null
        if str.eq(name, "netFail") {
            let (failure, have_failure) = field(op, "error")
            result = json.Value{ Bool: offline.is_network_failure(a, failure, have_failure) }
        } else if str.eq(name, "queue") {
            let (failure, have_failure) = field(op, "error")
            let (mutation, have_mutation) = field(op, "mutation")
            result = offline.queue_if_offline(a, &outbox, failure, have_failure, mutation, have_mutation)
        } else if str.eq(name, "qflush") {
            let (given_at, have_at) = field(op, "at")
            var instant = 0i64
            if have_at { instant = count_of(op, "at", 0i64) } else { instant = sim_now(mem.cast[*void](&sim)) }
            result = offline.flush_queue(a, &outbox, &remote, instant, text_field(op, "resolve"))
        } else if str.eq(name, "qstatus") {
            result = offline.queue_status(a, &outbox, true)
        } else if str.eq(name, "describe") {
            let (status, have_status) = field(op, "status")
            result = offline.describe_queue(a, status, have_status)
        } else if str.eq(name, "cstore") {
            offline.cache_store(&cache, ir.value_of(op, "table"), ir.value_of(op, "records"), ir.value_of(op, "at"))
        } else if str.eq(name, "cread") {
            result = offline.cache_read(&cache, ir.value_of(op, "table"), count_of(op, "now", 0i64), flag_of(op, "online", true))
        } else if str.eq(name, "coverlay") {
            let (rows, found) = offline.cache_overlay(&cache, ir.value_of(op, "table"), items(ir.value_of(op, "writes")))
            if found { result = rows }
        } else if str.eq(name, "cevict") {
            result = json.Value{ Bool: offline.cache_evict(&cache, ir.value_of(op, "table")) }
        } else if str.eq(name, "cscopes") {
            result = offline.cache_scopes(&cache)
        } else if str.eq(name, "cdrop") {
            result = sync.number(a, offline.cache_drop_records(&cache, ir.value_of(op, "table"), strings_of(a, ir.value_of(op, "ids"))))
        } else if str.eq(name, "conn") {
            let (given_at, have_at) = field(op, "at")
            result = offline.connect_to(&conn, text_field(op, "next"), given_at, have_at)
        } else if str.eq(name, "history") {
            result = json.Value{ Array: offline.connectivity_history(&conn) }
        } else if str.eq(name, "replay") {
            result = offline.plan_replay(a, items(ir.value_of(op, "queue")), ir.value_of(op, "versions"))
        } else if str.eq(name, "resolveReplay") {
            let (server, have_server) = field(op, "server")
            let (base, have_base) = field(op, "base")
            result = offline.resolve_replay_conflict(a, ir.value_of(op, "conflict"), text_field(op, "choice"), server, have_server, base, have_base)
        } else if str.eq(name, "review") {
            result = offline.build_conflict_review(a, items(ir.value_of(op, "conflicts")))
        } else if str.eq(name, "resolution") {
            let conflicts = items(ir.value_of(op, "conflicts"))
            let review = offline.build_conflict_review(a, conflicts)
            let review_items = items(ir.value_of(review, "items"))
            // the conflicts the review kept: those with a truthy mutation
            var valid = sync.empty_list(a)
            var c = 0usize
            while c < conflicts.len {
                if ir.truthy(conflicts[c]) && ir.truthy(ir.value_of(conflicts[c], "mutation")) { sync.push_value(&valid, conflicts[c]) }
                c += 1usize
            }
            var size = review_items.len
            if size == 0usize { size = 1usize }
            let index = usize(count_of(op, "index", 0i64)) % size
            var item: json.Value = .Null
            var have_item = false
            if index < review_items.len {
                item = review_items[index]
                have_item = true
            }
            var raw: json.Value = ir.empty_object()
            if index < valid.len { raw = valid.items[index] }
            let (server, have_server) = field(raw, "server")
            let (mutation, have_mutation) = field(raw, "mutation")
            result = offline.plan_offline_resolution(a, item, have_item, text_field(op, "choice"), server, have_server, mutation, have_mutation)
        } else if str.eq(name, "count") {
            result = sync.number(a, offline.conflict_count(offline.build_conflict_review(a, items(ir.value_of(op, "conflicts")))))
        } else if str.eq(name, "purge") {
            let (readable, have_readable) = field(op, "readable")
            let plan = offline.plan_cache_purge(a, items(ir.value_of(op, "cached")), readable, have_readable, flag_of(op, "probeOk", true))
            var o = sync.obj(a)
            sync.put(&o, "plan", plan)
            sync.put(&o, "outcome", offline.purge_outcome(a, plan, true))
            result = ir.obj_value(&o)
        } else if str.eq(name, "applyPurge") {
            let (readable, have_readable) = field(op, "readable")
            let plan = offline.plan_cache_purge(a, items(offline.cache_scopes(&cache)), readable, have_readable, flag_of(op, "probeOk", true))
            var o = sync.obj(a)
            sync.put(&o, "plan", plan)
            sync.put(&o, "applied", offline.apply_cache_purge(a, &cache, plan, true))
            sync.put(&o, "outcome", offline.purge_outcome(a, plan, true))
            result = ir.obj_value(&o)
        } else {
            os.exit(89i32)
        }
        let (rendered, e) = chain.canonical_json(a, result)
        if e != ok { os.exit(81i32) }
        if at > 0usize { out = join(a, out, "\n") }
        out = join(a, out, rendered)
        at += 1usize
    }
    ret out
}

// The first line on which the answers differ, with the operation that asked it.
fn show_diff(a: *mem.Arena, line: str, got: str, want: str) -> bool {
    var g = 0usize
    var w = 0usize
    var index = 0usize
    while true {
        var ge = g
        while ge < got.len && got[ge] != 10u8 { ge += 1usize }
        var we = w
        while we < want.len && want[we] != 10u8 { we += 1usize }
        let g_line = got[g..ge]
        let w_line = want[w..we]
        if !str.eq(g_line, w_line) {
            let (parsed, pe) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
            let ops = items(ir.value_of(parsed, "ops"))
            if index < ops.len {
                let (op_text, oe) = chain.canonical_json(a, ops[index])
                let s0 = io.print(join(a, "\nop ", op_text))
            }
            let s1 = io.print(join(a, "\ngot  ", g_line))
            let s2 = io.print(join(a, "\nwant ", w_line))
            ret false
        }
        if ge >= got.len || we >= want.len { ret true }
        g = ge + 1usize
        w = we + 1usize
        index += 1usize
    }
    ret true
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
                let shown_diff = show_diff(a, line, got, want)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("algo offline ok")
    ret ok
}
