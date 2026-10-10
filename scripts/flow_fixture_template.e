// `e.algo.flow` against appdor's own inline interpreter (src/workflow/flow-engine.js): scripts/flow_reference.mjs runs it
// over random flows with the real formula engine and writes `{"flow", "trigger", "options", "plan", "e"}` lines. The
// fixture replays the same flow over the Neper interpreter with stand-ins for what is injected: the effect handlers
// follow the `plan` (the n-th call of a handler fails while n <= failFirst, then answers a result built from its
// request), the dataset is the options' own, and a filter tree never matches (none is generated).
use e.algo.flow as flow
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.contract as contract

type Sim = struct { a: *mem.Arena, plan: json.Value, options: json.Value, names: [16]str, counts: [16]i64, used: usize }

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

fn number(a: *mem.Arena, n: i64) -> json.Value {
    let (v, e) = json.number_from_i64(a, n)
    if e != ok { os.exit(82i32) }
    ret json.Value{ Number: v }
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

fn new_obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { os.exit(83i32) }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
    if e != ok { os.exit(84i32) }
}

fn put_found(o: *ir.Obj, key: str, v: json.Value, found: bool) {
    if found { put(o, key, v) }
}

// --- the stand-ins --------------------------------------------------------------------------------------------------

fn bump(sim: *Sim, name: str) -> i64 {
    var at = 0usize
    while at < sim.used {
        if str.eq(sim.names[at], name) {
            sim.counts[at] = sim.counts[at] + 1i64
            ret sim.counts[at]
        }
        at += 1usize
    }
    sim.names[sim.used] = name
    sim.counts[sim.used] = 1i64
    sim.used += 1usize
    ret 1i64
}

fn no_effect() -> flow.Effect {
    ret flow.Effect { present: false, failed: false, permanent: false, message: "", code: "", has_code: false, has_value: false, value: .Null }
}

fn answered(v: json.Value) -> flow.Effect {
    ret flow.Effect { present: true, failed: false, permanent: false, message: "", code: "", has_code: false, has_value: true, value: v }
}

fn sim_effect(ctx: *void, name: str, request: json.Value) -> flow.Effect {
    var sim = mem.cast[*Sim](ctx)
    let a = sim.a
    let (p, found) = field(sim.plan, name)
    if !found { ret no_effect() }
    let n = bump(sim, name)
    if n <= count_of(p, "failFirst", 0i64) {
        let message = join(a, join(a, join(a, name, " failed "), ir.index_text(a, usize(n))), "")
        let (code, have_code) = field(p, "code")
        let (code_text, code_is_text) = ir.string_of(code)
        ret flow.Effect { present: true, failed: true, permanent: flag_of(p, "permanent"), message: message, code: code_text, has_code: have_code && code_is_text, has_value: false, value: .Null }
    }
    var o = new_obj(a)
    let n_text = ir.index_text(a, usize(n))
    let (table, have_table) = field(request, "table")
    let (values, have_values) = field(request, "values")
    let (subject, have_subject) = field(request, "target")
    if str.eq(name, "findRecords") {
        let (records, have_records) = field(p, "records")
        ret answered(records)
    }
    if str.eq(name, "createRecord") {
        if !flag_of(p, "noId") { put(&o, "id", json.Value{ String: join(a, "c", n_text) }) }
        put_found(&o, "table", table, have_table)
        put_found(&o, "values", values, have_values)
        ret answered(ir.obj_value(&o))
    }
    if str.eq(name, "updateRecord") {
        if !flag_of(p, "noId") { put(&o, "id", json.Value{ String: join(a, "u", n_text) }) }
        put_found(&o, "table", table, have_table)
        put_found(&o, "target", subject, have_subject)
        put_found(&o, "values", values, have_values)
        ret answered(ir.obj_value(&o))
    }
    if str.eq(name, "deleteRecord") {
        if !flag_of(p, "noId") { put(&o, "id", json.Value{ String: join(a, "d", n_text) }) }
        put_found(&o, "table", table, have_table)
        put_found(&o, "target", subject, have_subject)
        ret answered(ir.obj_value(&o))
    }
    if str.eq(name, "email") {
        if flag_of(p, "withId") { put(&o, "id", json.Value{ String: join(a, "e", n_text) }) }
        var delivered = true
        let (d, have_d) = field(p, "delivered")
        if have_d { delivered = flag_of(p, "delivered") }
        put(&o, "delivered", json.Value{ Bool: delivered })
        let (to, have_to) = field(request, "to")
        put_found(&o, "to", to, have_to)
        put(&o, "apiKey", json.Value{ String: "k" })
        put(&o, "messageId", json.Value{ String: join(a, "m", n_text) })
        ret answered(ir.obj_value(&o))
    }
    if str.eq(name, "notify") {
        put(&o, "delivered", json.Value{ Bool: true })
        put(&o, "payload", request)
        ret answered(ir.obj_value(&o))
    }
    if str.eq(name, "http") {
        put(&o, "status", number(a, 200i64))
        put(&o, "body", request)
        put(&o, "authorization", json.Value{ String: "x" })
        ret answered(ir.obj_value(&o))
    }
    if str.eq(name, "runWorkflow") {
        if flag_of(p, "nullResult") { ret answered(.Null) }
        let (status, have_status) = field(p, "status")
        put_found(&o, "status", status, have_status)
        let (id, have_id) = field(request, "workflowId")
        put_found(&o, "id", id, have_id)
        let (params, have_params) = field(request, "params")
        put_found(&o, "params", params, have_params)
        let (depth, have_depth) = field(request, "depth")
        put_found(&o, "depth", depth, have_depth)
        ret answered(ir.obj_value(&o))
    }
    ret no_effect()
}

fn sim_filter(ctx: *void, tree: json.Value, subject: json.Value) -> bool { ret false }

// The options' dataset: a table's rows, the first `limit` of them (no filter or sort is generated).
fn sim_dataset(ctx: *void, table: str, filter: json.Value, sort: json.Value, limit: json.Value) -> (json.Value, bool) {
    var sim = mem.cast[*Sim](ctx)
    let (dataset, have_dataset) = field(sim.options, "dataset")
    if !have_dataset { ret (.Null, false) }
    let (rows, have_rows) = field(dataset, table)
    if !have_rows { ret (.Null, false) }
    var all = items(rows)
    switch limit {
    case .Number as n:
        let (count, e) = json.number_i64(n)
        if e == ok && count >= 0i64 && usize(count) < all.len { all = all[0usize..usize(count)] }
    default:
        all = all
    }
    ret (json.Value{ Array: all }, true)
}

fn sim_script(ctx: *void, step: json.Value, inputs: json.Value) -> flow.Stepped {
    ret flow.Stepped { status: "failed", code: "", has_code: false, message: "no script runner", output: .Null, has_output: false, typed: .Null, has_typed: false }
}

fn sim_ai(ctx: *void, step: json.Value, config: json.Value, sources: json.Value, name: str, dry: bool) -> flow.Stepped {
    ret flow.Stepped { status: "skipped", code: "no_ai_model", has_code: true, message: "", output: .Null, has_output: false, typed: .Null, has_typed: false }
}

// --- the case -------------------------------------------------------------------------------------------------------

fn run_case(a: *mem.Arena, spec: json.Value) -> str {
    let (plan, have_plan) = field(spec, "plan")
    let (options, have_options) = field(spec, "options")
    var sim = Sim { a: a, plan: plan, options: options, names: zero, counts: zero, used: 0usize }
    let hooks = flow.Hooks {
        ctx: mem.cast[*void](&sim),
        effect: sim_effect,
        filter_matches: sim_filter,
        dataset_find: sim_dataset,
        script: sim_script,
        ai: sim_ai,
    }
    let (def, have_def) = field(spec, "flow")
    let (trigger, have_trigger) = field(spec, "trigger")
    let (result, re) = flow.run_flow(a, &hooks, def, trigger, options)
    if re != ok { os.exit(95i32) }
    ret canon(a, result)
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
    try io.print("algo flow ok")
    ret ok
}
