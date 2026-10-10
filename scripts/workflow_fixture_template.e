// `e.algo.workflow` against appdor's own durable interpreter (src/workflow/runtime.js): scripts/workflow_reference.mjs runs
// it over random workflows with the real Jinja engine and writes `{"def", "create", "plan", "env", "start", "tick",
// "rounds", "e"}` lines -- one execution per round, operator actions between them (entries and header patches committed
// to the store, the clock moved) and one canonical result per execution. The fixture replays the same rounds over the
// Neper interpreter with stand-ins for what is injected: the clock is a counter that advances `tick` per reading,
// templates are literals and `{{ dotted.path }}` references, trace is the identity, the URL check and the effect handlers
// follow the `plan`, and a filter tree never matches.
use e.algo.ir as ir
use e.algo.journal as journal
use e.algo.workflow as workflow
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.contract as contract

type Sim = struct { a: *mem.Arena, clock: i64, tick: i64, plan: json.Value }

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

fn canon(a: *mem.Arena, v: json.Value) -> str {
    let (text, e) = contract.canonical_json(a, v)
    if e != ok { os.exit(81i32) }
    ret text
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

// --- the stand-ins --------------------------------------------------------------------------------------------------

fn sim_now(ctx: *void) -> i64 {
    var sim = mem.cast[*Sim](ctx)
    let v = sim.clock
    sim.clock = sim.clock + sim.tick
    ret v
}

fn sim_sleep(ctx: *void, ms: i64) {}

// The value at a dotted path in the context; absent (false) when any step of it is missing or not an object.
fn lookup(ctx: json.Value, path: str) -> (json.Value, bool) {
    var current = ctx
    var begin = 0usize
    var at = 0usize
    while at <= path.len {
        if at == path.len || path[at] == 46u8 {
            let (next, found) = ir.get(current, path[begin..at])
            if !found { ret (.Null, false) }
            current = next
            begin = at + 1usize
        }
        at += 1usize
    }
    ret (current, true)
}

fn is_path(s: str) -> bool {
    if s.len == 0usize { ret false }
    var at = 0usize
    while at < s.len {
        let c = s[at]
        let good = (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || (c >= 48u8 && c <= 57u8) || c == 95u8 || c == 46u8
        if !good { ret false }
        at += 1usize
    }
    ret true
}

// The single `{{ path }}` a template consists of, or "" when it is anything else.
fn sole_path(src: str) -> str {
    let t = str.trim(src)
    if t.len < 5usize || t[0] != 123u8 || t[1] != 123u8 || t[t.len - 1usize] != 125u8 || t[t.len - 2usize] != 125u8 { ret "" }
    let inner = str.trim(t[2usize..t.len - 2usize])
    if !is_path(inner) { ret "" }
    ret inner
}

fn scalar_text(v: json.Value) -> str {
    var out = ""
    switch v {
    case .String as s:
        out = s
    case .Number as n:
        out = n.lexeme
    case .Bool as b:
        if b { out = "true" } else { out = "false" }
    default:
        out = ""
    }
    ret out
}

fn sim_render_text(ctx: *void, src: str, context: json.Value) -> str {
    var sim = mem.cast[*Sim](ctx)
    var out = ""
    var at = 0usize
    var begin = 0usize
    while at < src.len {
        if at + 1usize < src.len && src[at] == 123u8 && src[at + 1usize] == 123u8 {
            let (close, found) = str.find_from(src, "}}", at + 2usize)
            if found {
                out = join(sim.a, out, src[begin..at])
                let path = str.trim(src[at + 2usize..close])
                let (v, have) = lookup(context, path)
                if have { out = join(sim.a, out, scalar_text(v)) }
                at = close + 2usize
                begin = at
                continue
            }
        }
        at += 1usize
    }
    ret join(sim.a, out, src[begin..src.len])
}

fn sim_render_value(ctx: *void, src: str, context: json.Value) -> (json.Value, bool) {
    var sim = mem.cast[*Sim](ctx)
    var templated = false
    var at = 0usize
    while at + 1usize < src.len {
        if src[at] == 123u8 && (src[at + 1usize] == 123u8 || src[at + 1usize] == 37u8 || src[at + 1usize] == 35u8) { templated = true }
        at += 1usize
    }
    if !templated { ret (json.Value{ String: src }, true) }
    let path = sole_path(src)
    if str.eq(path, "true") { ret (json.Value{ Bool: true }, true) }
    if str.eq(path, "false") { ret (json.Value{ Bool: false }, true) }
    if path.len > 0usize {
        let (v, have) = lookup(context, path)
        ret (v, have)
    }
    ret (json.Value{ String: sim_render_text(ctx, src, context) }, true)
}

fn sim_trace(ctx: *void, v: json.Value) -> json.Value { ret v }

fn host_of(url: str) -> str {
    let (at, found) = str.find(url, "://")
    var rest = url
    if found { rest = url[at + 3usize..] }
    var end = 0usize
    while end < rest.len && rest[end] != 47u8 { end += 1usize }
    ret rest[0usize..end]
}

fn sim_check_url(ctx: *void, url: str) -> workflow.UrlVerdict {
    let host = host_of(url)
    if str.starts_with(host, "localhost") || str.ends_with(host, ".internal") {
        ret workflow.UrlVerdict { refusal: "is not allowed", unchecked_host: "" }
    }
    if str.ends_with(host, ".test") { ret workflow.UrlVerdict { refusal: "", unchecked_host: host } }
    ret workflow.UrlVerdict { refusal: "", unchecked_host: "" }
}

fn sim_has_effect(ctx: *void, type_name: str) -> bool {
    var sim = mem.cast[*Sim](ctx)
    let (p, found) = field(sim.plan, type_name)
    ret found
}

fn sim_effect(ctx: *void, type_name: str, request: json.Value) -> workflow.EffectResult {
    var sim = mem.cast[*Sim](ctx)
    let (p, found) = field(sim.plan, type_name)
    let attempt = count_of(request, "attempt", 1i64)
    let fail = count_of(p, "fail", 0i64)
    if attempt <= fail {
        var permanent = false
        let (flag, have_flag) = field(p, "permanent")
        switch flag {
        case .Bool as b:
            permanent = b
        default:
            permanent = false
        }
        let attempt_text = ir.index_text(sim.a, usize(attempt))
        let message = join(sim.a, join(sim.a, join(sim.a, type_name, " failed "), attempt_text), "")
        ret workflow.EffectResult { handled: true, failed: true, permanent: permanent, detail: message, has_result: false, result: .Null }
    }
    let (result, have_result) = field(p, "result")
    ret workflow.EffectResult { handled: true, failed: false, permanent: false, detail: "", has_result: have_result, result: result }
}

fn sim_filter(ctx: *void, tree: json.Value, context: json.Value) -> bool { ret false }

// --- the case -------------------------------------------------------------------------------------------------------

fn run_case(a: *mem.Arena, spec: json.Value) -> str {
    let (made, store_error) = journal.new_store(a, "run")
    if store_error != ok { os.exit(90i32) }
    var store = made
    let (create, have_create) = field(spec, "create")
    let (w, hw) = field(create, "workflow")
    let (t, ht) = field(create, "trigger")
    let (o, ho) = field(create, "options")
    let (fresh, fresh_error) = journal.create_run(a, w, t, o)
    if fresh_error != ok { os.exit(91i32) }
    let (stored, create_error) = journal.store_create(&store, fresh)
    if create_error != ok { os.exit(91i32) }
    let run_id = text_field(stored, "runId")
    var (plan, have_plan) = field(spec, "plan")
    var sim = Sim { a: a, clock: count_of(spec, "start", 1000i64), tick: count_of(spec, "tick", 1i64), plan: plan }
    let (env, have_env) = field(spec, "env")
    var hooks = workflow.Hooks {
        ctx: mem.cast[*void](&sim),
        now: sim_now,
        sleep: sim_sleep,
        render_value: sim_render_value,
        render_text: sim_render_text,
        trace: sim_trace,
        check_url: sim_check_url,
        has_effect: sim_has_effect,
        effect: sim_effect,
        filter_matches: sim_filter,
        env: env,
    }
    let (def, have_def) = field(spec, "def")
    let (rounds_value, have_rounds) = field(spec, "rounds")
    let rounds = items(rounds_value)
    var out = ""
    var at = 0usize
    while at < rounds.len {
        let round = rounds[at]
        let pres = items(ir.value_of(round, "pre"))
        var p = 0usize
        while p < pres.len {
            let (base, found) = journal.store_load(&store, run_id)
            if !found { os.exit(92i32) }
            let (c, ce) = journal.begin_commit(a, base)
            if ce != ok { os.exit(92i32) }
            var commit = c
            let entries = items(ir.value_of(pres[p], "entries"))
            var n = 0usize
            while n < entries.len {
                let added = journal.add(a, &commit, text_field(entries[n], "type"), ir.value_of(entries[n], "fields"))
                if added != ok { os.exit(93i32) }
                n += 1usize
            }
            let (patch, have_patch) = field(pres[p], "patch")
            if have_patch {
                let set = journal.set_header(&commit, patch)
                if set != ok { os.exit(93i32) }
            }
            let (built, be) = journal.build(a, &commit)
            if be != ok { os.exit(93i32) }
            let (landed, le) = journal.store_commit(&store, run_id, built)
            if le != ok { os.exit(93i32) }
            p += 1usize
        }
        let (clock_value, have_clock) = field(round, "clock")
        if have_clock { sim.clock = count_of(round, "clock", sim.clock) }
        let (loaded, found) = journal.store_load(&store, run_id)
        if !found { os.exit(94i32) }
        let (result, re) = workflow.execute_run(a, &hooks, &store, def, loaded)
        if re != ok { os.exit(95i32) }
        if at > 0usize { out = join(a, out, "\n") }
        out = join(a, out, canon(a, result))
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
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

// A fork is not in the reference's scripts (its branches run concurrently there, interleaving their journal entries, and
// sequentially here); its outcomes are asserted directly: both branches run, the result names them, the run succeeds.
fn check_fork(a: *mem.Arena) -> u8 {
    let source = "{\"def\":{\"id\":\"wf\",\"name\":\"W\",\"version\":1,\"trigger\":{\"type\":\"manual\"},\"steps\":[{\"id\":\"f\",\"type\":\"fork\",\"config\":{},\"branches\":[{\"name\":\"left\",\"steps\":[{\"id\":\"l1\",\"type\":\"log\",\"config\":{\"message\":\"left\"}}]},{\"name\":\"right\",\"steps\":[{\"id\":\"r1\",\"type\":\"log\",\"config\":{\"message\":\"right\"}},{\"id\":\"r2\",\"type\":\"delay\",\"config\":{\"ms\":500}}]}]}]},\"create\":{\"workflow\":{\"id\":\"wf\",\"version\":1,\"trigger\":{\"type\":\"manual\"}},\"trigger\":{\"payload\":{}},\"options\":{\"mode\":\"live\",\"runId\":\"run-1\",\"now\":0}},\"plan\":{},\"env\":{},\"start\":1000,\"tick\":1,\"rounds\":[{\"pre\":[]},{\"pre\":[],\"clock\":5000}]}"
    let (root, parse_error) = json.parse(a, source, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
    if parse_error != ok { ret 1u8 }
    let got = run_case(a, root)
    let (first, rest, found) = str.split_once(got, "\n")
    if !found { ret 2u8 }
    // Round one parks the run on the right branch's delay with the left branch completed.
    if !str.contains(first, "\"status\":\"suspended\"") || !str.contains(first, "\"kind\":\"timer\"") { ret 3u8 }
    if !str.contains(first, "\"fork-branch-completed\"") || !str.contains(first, "\"branch\":\"left\"") || str.contains(first, "\"branch\":\"right\"") { ret 4u8 }
    // Round two resumes, replays both branches and finishes with the fork's result.
    if !str.contains(rest, "\"status\":\"succeeded\"") || !str.contains(rest, "\"joined\":2") || !str.contains(rest, "\"branches\":[\"left\",\"right\"]") { ret 5u8 }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    let fork_result = check_fork(a)
    if fork_result != 0u8 { os.exit(100i32 + i32(fork_result)) }
    //__VECTOR_CALLS__
    try io.print("algo workflow ok")
    ret ok
}
