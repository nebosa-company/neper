// `e.algo.ir` against appdor's own workflow IR (src/workflow/ir.js): scripts/ir_reference.mjs drives it through random
// definitions and writes `{"ops": [...], "e": one canonical result per op joined by newlines}` lines; the fixture replays
// the ops over the Neper module and must render the same. Operations: `normalize`, `walk`, `ids`, `validate`, `register`,
// `unregister`, `step`, `key`. The approval routing matcher is injected: `routing_stub` answers for the rule shapes the
// script generates (approvers, policy, definition) as appdor's matcher does.
use e.algo.ir as ir
use e.algo.trigger as trigger
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.agent.contract as contract

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

// ASCII case-insensitive equality with an already lowercase name.
fn is_named(s: str, lower: str) -> bool {
    if s.len != lower.len { ret false }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        if c != lower[at] { ret false }
        at += 1usize
    }
    ret true
}

// appdor's routingRuleProblem for rules with `approvers`, `policy` or `rule`, and `definition`: "" when usable.
fn routing_stub(rule: json.Value) -> str {
    let (members, is_object) = ir.members_of(rule)
    if !is_object { ret "" }
    var policy: json.Value = .Null
    let (p, have_p) = field(rule, "policy")
    let (r, have_r) = field(rule, "rule")
    if have_p && ir.truthy(p) {
        policy = p
    } else if have_r && ir.truthy(r) {
        policy = r
    } else {
        policy = json.Value{ String: "any" }
    }
    let (policy_members, policy_is_object) = ir.members_of(policy)
    if policy_is_object {
        if ir.truthy(ir.value_of(policy, "quorum")) { ret "quorum-unsupported" }
        ret "unknown-policy"
    }
    let (policy_text, policy_is_text) = ir.string_of(policy)
    var named = false
    var quorum = false
    if policy_is_text {
        let t = str.trim(policy_text)
        named = is_named(t, "any") || is_named(t, "all") || is_named(t, "first-response") || is_named(t, "all-must-approve")
        quorum = t.len > 7usize && is_named(t[0usize..7usize], "quorum(")
    }
    if !named {
        if quorum { ret "quorum-unsupported" }
        ret "unknown-policy"
    }
    let (definition, have_definition) = field(rule, "definition")
    if !(have_definition && ir.truthy(definition)) {
        let (approvers, have_approvers) = field(rule, "approvers")
        var any = false
        if have_approvers {
            let list = items(approvers)
            var at = 0usize
            while at < list.len {
                let (t, t_is_text) = ir.string_of(list[at])
                if t_is_text && str.trim(t).len > 0usize { any = true }
                at += 1usize
            }
        }
        if !any { ret "rule-asks-nobody" }
    }
    ret ""
}

fn csv_array(a: *mem.Arena, csv: str) -> json.Value {
    var none: []const json.Value = zero
    if csv.len == 0usize { ret json.Value{ Array: none } }
    let (parts, e) = mem.alloc[json.Value](a, csv.len + 1usize)
    if e != ok { os.exit(83i32) }
    var count = 0usize
    var begin = 0usize
    var at = 0usize
    while at <= csv.len {
        if at == csv.len || csv[at] == 44u8 {
            parts[count] = json.Value{ String: csv[begin..at] }
            count += 1usize
            begin = at + 1usize
        }
        at += 1usize
    }
    ret json.Value{ Array: parts[0usize..count] }
}

fn step_value(a: *mem.Arena, plugins: *const ir.Plugins, name: str) -> json.Value {
    let info = ir.step_type(plugins, name)
    if !info.found { ret .Null }
    let (o, oe) = ir.new_obj(a)
    if oe != ok { os.exit(84i32) }
    var out = o
    let p1 = ir.put(&out, "kind", json.Value{ String: info.kind })
    let p2 = ir.put(&out, "suspends", json.Value{ Bool: info.suspends })
    let p3 = ir.put(&out, "mutates", json.Value{ Bool: info.mutates })
    let p4 = ir.put(&out, "body", csv_array(a, info.body))
    let p5 = ir.put(&out, "raw", csv_array(a, info.raw))
    if p1 != ok || p2 != ok || p3 != ok || p4 != ok || p5 != ok { os.exit(84i32) }
    if info.installed {
        let q1 = ir.put(&out, "installed", json.Value{ Bool: true })
        let q2 = ir.put(&out, "runnable", json.Value{ Bool: false })
        let q3 = ir.put(&out, "label", json.Value{ String: ir.plugin_label(plugins, name) })
        let q4 = ir.put(&out, "provenance", .Null)
        if q1 != ok || q2 != ok || q3 != ok || q4 != ok { os.exit(84i32) }
    } else {
        let q = ir.put(&out, "output", json.Value{ String: info.output })
        if q != ok { os.exit(84i32) }
    }
    ret ir.obj_value(&out)
}

fn run_case(a: *mem.Arena, spec: json.Value, clock: *const trigger.Clock) -> str {
    let (ops_value, have_ops) = field(spec, "ops")
    let ops = items(ops_value)
    let (made, plugins_error) = ir.new_plugins(a)
    if plugins_error != ok { os.exit(85i32) }
    var plugins = made
    var out = ""
    var at = 0usize
    while at < ops.len {
        let op = ops[at]
        let name = text_field(op, "op")
        let (def, have_def) = field(op, "def")
        var line = ""
        if str.eq(name, "normalize") {
            let (v, e) = ir.normalize_workflow(a, def)
            if e != ok { os.exit(86i32) }
            line = canon(a, v)
        } else if str.eq(name, "walk") {
            let (steps, have_steps) = field(def, "steps")
            let (visits, e) = ir.walk_steps(a, steps)
            if e != ok { os.exit(87i32) }
            let (rendered, re) = mem.alloc[json.Value](a, visits.len + 1usize)
            if re != ok { os.exit(87i32) }
            var i = 0usize
            while i < visits.len {
                let (o, oe) = ir.new_obj(a)
                if oe != ok { os.exit(87i32) }
                var one = o
                let (id, have_id) = field(visits[i].step, "id")
                var id_value: json.Value = .Null
                if have_id { id_value = id }
                let (path_values, pe) = mem.alloc[json.Value](a, visits[i].path.len + 1usize)
                if pe != ok { os.exit(87i32) }
                var p = 0usize
                while p < visits[i].path.len {
                    path_values[p] = json.Value{ String: visits[i].path[p] }
                    p += 1usize
                }
                let w1 = ir.put(&one, "id", id_value)
                let w2 = ir.put(&one, "path", json.Value{ Array: path_values[0usize..visits[i].path.len] })
                if w1 != ok || w2 != ok { os.exit(87i32) }
                rendered[i] = ir.obj_value(&one)
                i += 1usize
            }
            line = canon(a, json.Value{ Array: rendered[0usize..visits.len] })
        } else if str.eq(name, "ids") {
            let (ids, e) = ir.collect_step_ids(a, def)
            if e != ok { os.exit(88i32) }
            let (rendered, re) = mem.alloc[json.Value](a, ids.len + 1usize)
            if re != ok { os.exit(88i32) }
            var i = 0usize
            while i < ids.len {
                rendered[i] = json.Value{ String: ids[i] }
                i += 1usize
            }
            line = canon(a, json.Value{ Array: rendered[0usize..ids.len] })
        } else if str.eq(name, "validate") {
            let (v, e) = ir.validate_workflow(a, clock, &plugins, routing_stub, def)
            if e != ok { os.exit(89i32) }
            line = canon(a, v)
        } else if str.eq(name, "register") {
            let (key, problem, e) = ir.register_plugin_step(a, &plugins, text_field(op, "ns"), text_field(op, "id"), text_field(op, "label"))
            if e != ok { os.exit(90i32) }
            let (o, oe) = ir.new_obj(a)
            if oe != ok { os.exit(90i32) }
            var one = o
            if problem.len == 0usize {
                let r1 = ir.put(&one, "ok", json.Value{ Bool: true })
                let r2 = ir.put(&one, "key", json.Value{ String: key })
                if r1 != ok || r2 != ok { os.exit(90i32) }
            } else {
                let r1 = ir.put(&one, "ok", json.Value{ Bool: false })
                let r2 = ir.put(&one, "error", json.Value{ String: problem })
                if r1 != ok || r2 != ok { os.exit(90i32) }
            }
            line = canon(a, ir.obj_value(&one))
        } else if str.eq(name, "unregister") {
            let removed = ir.unregister_plugin_step(&plugins, text_field(op, "key"))
            let (o, oe) = ir.new_obj(a)
            if oe != ok { os.exit(91i32) }
            var one = o
            let r1 = ir.put(&one, "ok", json.Value{ Bool: removed })
            if r1 != ok { os.exit(91i32) }
            line = canon(a, ir.obj_value(&one))
        } else if str.eq(name, "step") {
            line = canon(a, step_value(a, &plugins, text_field(op, "name")))
        } else {
            let (frames_value, have_frames) = field(op, "frames")
            let frame_items = items(frames_value)
            let (frames, fe) = mem.alloc[str](a, frame_items.len + 1usize)
            if fe != ok { os.exit(92i32) }
            var i = 0usize
            while i < frame_items.len {
                let (s, is_text) = ir.string_of(frame_items[i])
                frames[i] = s
                i += 1usize
            }
            let (key, ke) = ir.execution_key(a, text_field(op, "id"), frames[0usize..frame_items.len])
            if ke != ok { os.exit(93i32) }
            line = canon(a, json.Value{ String: key })
        }
        if at > 0usize { out = join(a, out, "\n") }
        out = join(a, out, line)
        at += 1usize
    }
    ret out
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str, clock: *const trigger.Clock) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 40u16 })
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                want = text_field(root, "e")
                got = run_case(a, root, clock)
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

fn main(a: *mem.Arena, args: []str) -> err {
    let (made, clock_error) = trigger.new_clock(a)
    if clock_error != ok { os.exit(94i32) }
    var clock = made
    //__VECTOR_CALLS__
    try io.print("algo ir ok")
    ret ok
}
