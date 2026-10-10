// `e.algo.syncjob` against appdor's src/sync (sync-schedule.js, sync-refusal.js, the pure half of synced-table.js and
// syncPlan from src/connectors): scripts/syncjob_reference.mjs runs 700 random single operations and writes `{"op", "e"}`
// lines; the fixture replays each over the Neper module and compares the canonical result.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.syncjob as syncjob
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

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

fn truthy_flag(v: json.Value, key: str) -> bool {
    let (x, found) = field(v, key)
    if !found { ret false }
    ret ir.truthy(x)
}

fn translate(ctx: *void, key: str, variable: str) -> str {
    var sim = mem.cast[*mem.Arena](ctx)
    let (joined, e) = str.concat(sim, key, "|")
    if e != ok { os.exit(84i32) }
    let (out, e2) = str.concat(sim, joined, variable)
    if e2 != ok { os.exit(84i32) }
    ret out
}

fn run_one(a: *mem.Arena, root: json.Value) -> str {
    let (op, have_op) = field(root, "op")
    let name = text_field(op, "op")
    var result: json.Value = .Null
    if str.eq(name, "lease") {
        result = json.Value{ Bool: syncjob.lease_available(ir.value_of(op, "row"), text_field(op, "me"), ir.value_of(op, "now")) }
    } else if str.eq(name, "due") {
        result = json.Value{ Array: syncjob.due_bindings(a, items(ir.value_of(op, "rows")), ir.value_of(op, "now")) }
    } else if str.eq(name, "backoff") {
        result = syncjob.number_value(a, syncjob.backoff_minutes(ir.value_of(op, "failures"), ir.value_of(op, "interval")))
    } else if str.eq(name, "after") {
        let (v, e) = syncjob.schedule_after_run(a, ir.value_of(op, "row"), truthy_flag(op, "failed"), ir.value_of(op, "now"))
        if e != ok { os.exit(85i32) }
        result = v
    } else if str.eq(name, "health") {
        result = syncjob.binding_health(a, ir.value_of(op, "row"))
    } else if str.eq(name, "policy") {
        result = syncjob.apply_deletion_policy(a, items(ir.value_of(op, "deletes")), text_field(op, "policy"))
    } else if str.eq(name, "flagPlan") {
        result = syncjob.flag_plan(a, items(ir.value_of(op, "rows")))
    } else if str.eq(name, "unflagPlan") {
        result = syncjob.unflag_plan(a, items(ir.value_of(op, "local")), items(ir.value_of(op, "remote")), text_field(op, "key"))
    } else if str.eq(name, "refusal") {
        let code = text_field(op, "code")
        let (key, known) = syncjob.sync_refusal_key(code)
        let (made, e) = ir.new_obj(a)
        if e != ok { os.exit(86i32) }
        var o = made
        if known { let p = ir.put(&o, "key", json.Value{ String: key }) } else { let p = ir.put(&o, "key", .Null) }
        let tr = syncjob.Translate { ctx: mem.cast[*void](a), run: translate }
        let p2 = ir.put(&o, "text", json.Value{ String: syncjob.describe_sync_refusal(code, &tr) })
        result = ir.obj_value(&o)
    } else if str.eq(name, "coerce") {
        let (column, have_column) = field(op, "column")
        let (value, have_value) = field(op, "value")
        result = syncjob.coerce_value(a, truthy_flag(column, "structured"), value, have_value)
    } else if str.eq(name, "validateKey") {
        let (key, have_key) = field(op, "key")
        result = syncjob.validate_sync_key(a, items(ir.value_of(op, "columns")), text_field(op, "key"), have_key, items(ir.value_of(op, "sample")))
    } else if str.eq(name, "quarantine") {
        result = syncjob.quarantine_by_key(a, items(ir.value_of(op, "rows")), text_field(op, "key"))
    } else if str.eq(name, "syncPlan") {
        let options = ir.value_of(op, "options")
        let (fields, have_fields) = field(options, "fields")
        result = syncjob.sync_plan(a, items(ir.value_of(op, "local")), items(ir.value_of(op, "remote")), text_field(op, "key"), strings_of(a, fields), have_fields, truthy_flag(options, "bulkLoad"))
    } else if str.eq(name, "planPull") {
        let (partial, have_partial) = field(op, "partial")
        var is_partial = false
        switch partial {
        case .Bool as b:
            is_partial = b
        default:
            is_partial = false
        }
        result = syncjob.plan_pull(a, items(ir.value_of(op, "local")), items(ir.value_of(op, "remote")), text_field(op, "key"), strings_of(a, ir.value_of(op, "fields")), is_partial)
    } else if str.eq(name, "ledger") {
        result = syncjob.run_ledger_row(a, ir.value_of(op, "synced"), ir.value_of(op, "trigger"), ir.value_of(op, "plan"), ir.value_of(op, "error"), ir.value_of(op, "started"), ir.value_of(op, "finished"))
    } else if str.eq(name, "nextRun") {
        let (v, e) = syncjob.next_run_at(a, ir.value_of(op, "row"), ir.value_of(op, "now"))
        if e != ok { os.exit(87i32) }
        result = json.Value{ String: v }
    } else if str.eq(name, "bodyRecords") {
        let (records, found) = syncjob.records_from_body(ir.value_of(op, "body"))
        if found { result = records }
    } else if str.eq(name, "drift") {
        result = syncjob.drift_report(a, items(ir.value_of(op, "stored")), items(ir.value_of(op, "observed")))
    } else if str.eq(name, "accept") {
        let stored = items(ir.value_of(op, "stored"))
        let report = syncjob.drift_report(a, stored, items(ir.value_of(op, "observed")))
        let (choices, have_choices) = field(op, "choices")
        let (add, have_add) = field(choices, "add")
        var names: []const str = zero
        let (xs, is_array) = ir.items_of(add)
        if have_add && is_array { names = strings_of(a, add) }
        result = syncjob.accept_drift(a, stored, report, names)
    } else {
        os.exit(89i32)
    }
    let (text, e) = chain.canonical_json(a, result)
    if e != ok { os.exit(81i32) }
    ret text
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
                got = run_one(a, root)
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
    try io.print("algo syncjob ok")
    ret ok
}
