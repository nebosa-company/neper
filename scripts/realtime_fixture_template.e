// `e.algo.realtime` against appdor's src/realtime/index.js: scripts/realtime_reference.mjs runs random operation scripts
// (presence, cell resolution, merge, topic authorization, the connection lifecycle, telemetry, trimming, view
// membership) with one clock counter and a scripted Math.random, and writes `{"spec", "ops", "e"}` lines. The fixture
// replays the operations over the Neper module with the same clock and jitter and compares the canonical results.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.realtime as realtime
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

type Sim = struct { a: *mem.Arena, clock: i64, tick: i64, jitter: json.Value, calls: usize }

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

fn sim_now(ctx: *void) -> i64 {
    var sim = mem.cast[*Sim](ctx)
    let v = sim.clock
    sim.clock = sim.clock + sim.tick
    ret v
}

fn sim_jitter(ctx: *void) -> f64 {
    var sim = mem.cast[*Sim](ctx)
    let plan = items(sim.jitter)
    let at = sim.calls % plan.len
    sim.calls += 1usize
    switch plan[at] {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e == ok { ret x * 500.0f64 }
        ret 0.0f64
    default:
        ret 0.0f64
    }
}

fn run_case(a: *mem.Arena, root: json.Value) -> str {
    let (spec, have_spec) = field(root, "spec")
    var sim = Sim { a: a, clock: count_of(spec, "start", 0i64), tick: count_of(spec, "tick", 1i64), jitter: ir.value_of(spec, "jitter"), calls: 0usize }
    let clock = realtime.Clock { ctx: mem.cast[*void](&sim), now: sim_now, jitter: sim_jitter }
    var auth = realtime.new_topic_auth(a, &clock)
    var lc = realtime.new_lifecycle(a, &clock)
    var tel = realtime.new_telemetry(a, &clock)
    var presence = ir.empty_object()
    var users = json.Value{ Array: zero }
    var trace_id = "none"
    var out = ""
    let ops = items(ir.value_of(root, "ops"))
    var at = 0usize
    while at < ops.len {
        let op = ops[at]
        let name = text_field(op, "op")
        var result: json.Value = .Null
        if str.eq(name, "setPresence") {
            presence = realtime.set_presence(a, presence, text_field(op, "user"), ir.value_of(op, "info"))
            result = presence
        } else if str.eq(name, "clearPresence") {
            presence = realtime.clear_presence(a, presence, text_field(op, "user"))
            result = presence
        } else if str.eq(name, "active") {
            var ttl = 30000.0f64
            let (given, have_ttl) = field(op, "ttl")
            if have_ttl { ttl = f64(count_of(op, "ttl", 30000i64)) }
            users = realtime.active_users(a, presence, ir.value_of(op, "now"), ttl)
            result = users
        } else if str.eq(name, "filterView") {
            result = realtime.filter_presence_for_viewer(a, items(users), ir.value_of(op, "policy"))
        } else if str.eq(name, "status") {
            result = realtime.realtime_status(a, ir.value_of(op, "state"))
        } else if str.eq(name, "tok") {
            realtime.register_token(&auth, text_field(op, "token"), ir.value_of(op, "info"))
            let (made, e) = ir.new_obj(a)
            if e != ok { os.exit(81i32) }
            var o = made
            let stored = ir.put(&o, "ok", json.Value{ Bool: true })
            result = ir.obj_value(&o)
        } else if str.eq(name, "revoke") {
            let evicted = realtime.revoke_token(&auth, text_field(op, "token"))
            let (made, e) = ir.new_obj(a)
            if e != ok { os.exit(81i32) }
            var o = made
            let p1 = ir.put(&o, "ok", json.Value{ Bool: true })
            let p2 = ir.put(&o, "evicted", evicted)
            result = ir.obj_value(&o)
        } else if str.eq(name, "sub") {
            result = realtime.subscribe(&auth, text_field(op, "topic"), text_field(op, "token"), ir.value_of(op, "userId"))
        } else if str.eq(name, "unsub") {
            result = json.Value{ Bool: realtime.unsubscribe(&auth, text_field(op, "topic")) }
        } else if str.eq(name, "evict") {
            let evicted = realtime.evict_user(&auth, ir.value_of(op, "userId"))
            let (made, e) = ir.new_obj(a)
            if e != ok { os.exit(81i32) }
            var o = made
            let p1 = ir.put(&o, "ok", json.Value{ Bool: true })
            let p2 = ir.put(&o, "evicted", evicted)
            result = ir.obj_value(&o)
        } else if str.eq(name, "may") {
            result = json.Value{ Bool: realtime.may_receive(&auth, ir.value_of(op, "userId"), text_field(op, "topic")) }
        } else if str.eq(name, "subs") {
            let (user, have_user) = field(op, "userId")
            result = realtime.active_subscriptions(&auth, user, have_user)
        } else if str.eq(name, "lc") {
            let what = text_field(op, "what")
            let (given, have_n) = field(op, "n")
            let n = count_of(op, "n", 0i64)
            if str.eq(what, "heartbeat") {
                realtime.heartbeat(&lc)
            } else if str.eq(what, "disconnected") {
                result = realtime.disconnected(&lc)
            } else if str.eq(what, "plan") {
                result = realtime.plan_reconnect(&lc)
            } else if str.eq(what, "reconnected") {
                result = realtime.reconnected(&lc, n)
            } else if str.eq(what, "seq") {
                result = ir.number_lexeme(ir.index_text(a, usize(realtime.advance_seq(&lc))))
            } else if str.eq(what, "stale") {
                var ttl = 60000i64
                if have_n { ttl = n }
                result = json.Value{ Bool: realtime.is_stale(&lc, ttl) }
            } else if str.eq(what, "should") {
                var gap = 2000i64
                if have_n { gap = n }
                result = json.Value{ Bool: realtime.should_reconnect(&lc, gap) }
            } else if str.eq(what, "state") {
                let (made, e) = ir.new_obj(a)
                if e != ok { os.exit(81i32) }
                var o = made
                let p1 = ir.put(&o, "state", json.Value{ String: lc.state })
                let p2 = ir.put(&o, "seq", ir.number_lexeme(ir.index_text(a, usize(lc.sequence))))
                if lc.has_disconnect { let p3 = ir.put(&o, "disconnectAt", ir.number_lexeme(ir.index_text(a, usize(lc.disconnect_at)))) } else { let p3 = ir.put(&o, "disconnectAt", .Null) }
                result = ir.obj_value(&o)
            } else if str.eq(what, "events") {
                result = json.Value{ Array: realtime.take_events(&lc) }
            } else {
                os.exit(82i32)
            }
        } else if str.eq(name, "tel") {
            let what = text_field(op, "what")
            let info = ir.value_of(op, "info")
            if str.eq(what, "trace") {
                result = realtime.start_trace(&tel, count_of(op, "publishAt", 0i64))
                trace_id = text_field(result, "correlationId")
            } else if str.eq(what, "delivery") {
                result = realtime.record_delivery(&tel, trace_id, info)
            } else if str.eq(what, "degradation") {
                realtime.record_degradation(&tel, json.Value{ String: "slow" })
            } else if str.eq(what, "coalesce") {
                let c = count_of(op, "count", 0i64)
                realtime.record_coalesce(&tel, c, c - 1i64)
            } else if str.eq(what, "conn") {
                realtime.record_connection_count(&tel, count_of(op, "count", 0i64))
            } else if str.eq(what, "export") {
                result = realtime.export_telemetry(&tel, count_of(op, "since", 0i64))
            } else {
                os.exit(83i32)
            }
        } else if str.eq(name, "resolveEdit") {
            let (cell, have_cell) = field(op, "cell")
            result = realtime.resolve_edit(a, cell, have_cell, ir.value_of(op, "edit"))
        } else if str.eq(name, "merge") {
            result = realtime.merge_record(a, ir.value_of(op, "base"), items(ir.value_of(op, "edits")))
        } else if str.eq(name, "trim") {
            let (trimmed, kept) = realtime.trim_event_payload(a, ir.value_of(op, "payload"), ir.value_of(op, "permissions"))
            if kept { result = trimmed }
        } else if str.eq(name, "member") {
            let (previous, have_previous) = field(op, "previous")
            result = realtime.evaluate_view_membership(a, ir.value_of(op, "record"), ir.value_of(op, "filter"), previous, have_previous)
        } else if str.eq(name, "affected") {
            let (previous, have_previous) = field(op, "previous")
            result = realtime.affected_views(a, ir.value_of(op, "record"), previous, have_previous, items(ir.value_of(op, "views")))
        } else {
            os.exit(89i32)
        }
        let (text, e) = chain.canonical_json(a, result)
        if e != ok { os.exit(84i32) }
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

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("algo realtime ok")
    ret ok
}
