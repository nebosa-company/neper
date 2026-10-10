// `e.algo.fsm` against appdor's own `src/workflows/{definition,registry,guard}.js`: scripts/fsm_reference.mjs runs
// appdor's validator, differ, guard, bulk transitions, simulation, templates and time-in-state over random
// workflows, records, principals and environments and writes `{"op": ..., ...inputs, "e": outcome}` lines; the
// fixture rebuilds the inputs and must render the same outcome.
use e.algo.formula as f
use e.algo.formula.library as library
use e.algo.fsm as w
use e.algo.view as v
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn hex_text(a: *mem.Arena, s: str) -> str {
    if s.len == 0usize { ret "_" }
    let (out, e) = mem.alloc[u8](a, s.len * 2usize)
    if e != ok { ret "?" }
    var i = 0usize
    while i < s.len {
        let hi = s[i] >> 4u8
        let lo = s[i] & 15u8
        var h = 48u8 + hi
        if hi > 9u8 { h = 87u8 + hi }
        var l = 48u8 + lo
        if lo > 9u8 { l = 87u8 + lo }
        out[i * 2usize] = h
        out[i * 2usize + 1usize] = l
        i += 1usize
    }
    ret out[0usize..s.len * 2usize]
}

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn join3(a: *mem.Arena, x: str, y: str, z: str) -> str { ret f.join3(a, x, y, z) }

fn num(a: *mem.Arena, n: f64) -> str { ret f.number_text(a, n) }



fn members_of(x: json.Value) -> []const json.Member {
    var none: []const json.Member = zero
    switch x {
    case .Object as m:
        ret m
    default:
        ret none
    }
}

fn items_of(x: json.Value) -> []const json.Value {
    var none: []const json.Value = zero
    switch x {
    case .Array as items:
        ret items
    default:
        ret none
    }
}

fn get(members: []const json.Member, key: str) -> (json.Value, bool) {
    var i = 0usize
    while i < members.len {
        if str.eq(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    var null_value: json.Value = .Null
    ret (null_value, false)
}

fn is_null(x: json.Value) -> bool {
    switch x {
    case .Null:
        ret true
    default:
        ret false
    }
}

fn text_of(members: []const json.Member, key: str) -> str {
    let (x, found) = get(members, key)
    if !found { ret "" }
    switch x {
    case .String as s:
        ret s
    default:
        ret ""
    }
}

fn number_of(members: []const json.Member, key: str, fallback: f64) -> f64 {
    let (x, found) = get(members, key)
    if !found { ret fallback }
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret value
    default:
        ret fallback
    }
}

fn has_number(members: []const json.Member, key: str) -> bool {
    let (x, found) = get(members, key)
    if !found { ret false }
    switch x {
    case .Number as n:
        ret true
    default:
        ret false
    }
}

fn value_of(a: *mem.Arena, x: json.Value) -> f.Value {
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret f.number(value)
    case .String as s:
        ret f.text(s)
    case .Bool as b:
        ret f.boolean(b)
    case .Array as items:
        if items.len == 0usize { ret f.array(f.zero_items()) }
        let (out, e) = mem.alloc[f.Value](a, items.len)
        if e != ok { ret f.blank() }
        var i = 0usize
        while i < items.len {
            out[i] = value_of(a, items[i])
            i += 1usize
        }
        ret f.array(out)
    case .Object as members:
        // an attachment descriptor: its `size` is all the engine reads
        let (size, has_size) = get(members, "size")
        let (out, e) = mem.alloc[f.Value](a, 1usize)
        if e != ok { ret f.record(f.zero_items()) }
        if has_size { out[0usize] = value_of(a, size) } else { out[0usize] = f.blank() }
        ret f.record(out[0usize..1usize])
    default:
        ret f.blank()
    }
}

fn row_of(a: *mem.Arena, x: json.Value) -> v.Row {
    let members = members_of(x)
    var none: []const f.Field = zero
    if members.len == 0usize { ret v.Row { fields: none } }
    let (out, e) = mem.alloc[f.Field](a, members.len)
    if e != ok { ret v.Row { fields: none } }
    var i = 0usize
    while i < members.len {
        out[i] = f.Field { name: members[i].key, value: value_of(a, members[i].value) }
        i += 1usize
    }
    ret v.Row { fields: out }
}

fn rows_of(a: *mem.Arena, x: json.Value) -> []const v.Row {
    let items = items_of(x)
    var none: []const v.Row = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[v.Row](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        out[i] = row_of(a, items[i])
        i += 1usize
    }
    ret out
}

fn strings_of(a: *mem.Arena, x: json.Value) -> []const str {
    var none: []const str = zero
    let items = items_of(x)
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[str](a, items.len)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < items.len {
        switch items[i] {
        case .String as s:
            out[n] = s
            n += 1usize
        default:
            n += 0usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn field_defs_of(a: *mem.Arena, x: json.Value) -> []const v.FieldDef {
    let items = items_of(x)
    var none: []const v.FieldDef = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[v.FieldDef](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let m = members_of(items[i])
        var d: v.FieldDef = zero
        d.name = text_of(m, "name")
        d.type_name = text_of(m, "type")
        let (options, has_options) = get(m, "options")
        if has_options {
            let list = items_of(options)
            d.has_options = true
            let (vals, ve) = mem.alloc[f.Value](a, list.len + 1usize)
            if ve == ok {
                var k = 0usize
                while k < list.len {
                    vals[k] = value_of(a, list[k])
                    k += 1usize
                }
                d.options = vals[0usize..list.len]
            }
        }
        let (colors, has_colors) = get(m, "optionColors")
        if has_colors {
            let cm = members_of(colors)
            let (cs, ce) = mem.alloc[f.Field](a, cm.len + 1usize)
            if ce == ok {
                var k = 0usize
                while k < cm.len {
                    cs[k] = f.Field { name: cm[k].key, value: value_of(a, cm[k].value) }
                    k += 1usize
                }
                d.option_colors = cs[0usize..cm.len]
            }
        }
        out[i] = d
        i += 1usize
    }
    ret out
}

fn operand_of(a: *mem.Arena, m: []const json.Member) -> v.Operand {
    let (x, present) = get(m, "value")
    if !present { ret v.Operand { present: false, value: f.blank(), relative: "", days: 0.0f64, has_start: false, start: f.blank(), has_end: false, end: f.blank(), is_object: false } }
    switch x {
    case .Object as om:
        let (start, has_start) = get(om, "start")
        let (end, has_end) = get(om, "end")
        var days = 0.0f64
        let raw_days = number_of(om, "days", 0.0f64)
        if raw_days == raw_days && raw_days != 0.0f64 { days = raw_days }
        ret v.Operand { present: true, value: f.blank(), relative: text_of(om, "relative"), days: days, has_start: has_start && !is_null(start), start: value_of(a, start), has_end: has_end && !is_null(end), end: value_of(a, end), is_object: true }
    default:
        ret v.plain_operand(value_of(a, x))
    }
}

fn bucket_of(m: []const json.Member, key: str) -> v.Bucket {
    let (x, found) = get(m, key)
    if !found { ret v.no_bucket() }
    switch x {
    case .String as s:
        ret v.Bucket { name: s, size: 0.0f64, has_size: false }
    case .Object as om:
        let size = number_of(om, "size", 0.0f64)
        if size != 0.0f64 { ret v.Bucket { name: "", size: size, has_size: true } }
        ret v.no_bucket()
    default:
        ret v.no_bucket()
    }
}

fn node_of(a: *mem.Arena, x: json.Value) -> v.Node {
    let m = members_of(x)
    var n = v.empty_group("and")
    let operator = text_of(m, "operator")
    n.operator = ""
    if str.eq(operator, "and") || str.eq(operator, "or") || operator.len > 0usize { n.operator = operator }
    let (children, has_children) = get(m, "children")
    if has_children {
        let list = items_of(children)
        if list.len > 0usize {
            let (out, e) = mem.alloc[v.Node](a, list.len)
            if e == ok {
                var i = 0usize
                while i < list.len {
                    out[i] = node_of(a, list[i])
                    i += 1usize
                }
                n.children = out
            }
        }
    }
    n.field = text_of(m, "field")
    n.op = text_of(m, "op")
    n.type_name = text_of(m, "type")
    n.expr = text_of(m, "expr")
    n.operand = operand_of(a, m)
    n.bucket = bucket_of(m, "bucket")
    let (values, has_values) = get(m, "values")
    if has_values {
        let list = items_of(values)
        n.has_values = true
        let (out, e) = mem.alloc[f.Value](a, list.len + 1usize)
        if e == ok {
            var i = 0usize
            while i < list.len {
                out[i] = value_of(a, list[i])
                i += 1usize
            }
            n.values = out[0usize..list.len]
        }
    }
    ret n
}


// --- fixture-specific builders --------------------------------------------------------------------------------------

fn flag(x: bool) -> str {
    if x { ret "1" }
    ret "0"
}

fn json_encode(a: *mem.Arena, value: json.Value) -> str {
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret "" }
    var held = state
    var sink = io.writer(mem.cast[*void](&held), io.memory_write)
    var copy = value
    let write_error = json.write(&sink, &copy)
    if write_error != ok { ret "" }
    ret io.memory_bytes(&held)
}

fn member_of(m: []const json.Member, key: str) -> json.Value {
    let (x, found) = get(m, key)
    ret x
}

fn has_member(m: []const json.Member, key: str) -> bool {
    let (x, found) = get(m, key)
    ret found
}

fn is_array(x: json.Value) -> bool {
    switch x {
    case .Array as items:
        ret true
    default:
        ret false
    }
}

fn is_object(x: json.Value) -> bool {
    switch x {
    case .Object as members:
        ret true
    default:
        ret false
    }
}

fn is_string(x: json.Value) -> bool {
    switch x {
    case .String as s:
        ret true
    default:
        ret false
    }
}

fn string_of(x: json.Value) -> str {
    switch x {
    case .String as s:
        ret s
    default:
        ret ""
    }
}

// `toList` over strings: an array's string elements, a string as itself, anything else empty.
fn list_of(a: *mem.Arena, x: json.Value) -> []const str {
    var none: []const str = zero
    switch x {
    case .String as s:
        if s.len == 0usize { ret none }
        let (one, e) = mem.alloc[str](a, 1usize)
        if e != ok { ret none }
        one[0usize] = s
        ret one
    case .Array as items:
        let (out, e) = mem.alloc[str](a, items.len + 1usize)
        if e != ok { ret none }
        var n = 0usize
        var i = 0usize
        while i < items.len {
            switch items[i] {
            case .String as s:
                out[n] = s
                n += 1usize
            default:
                n += 0usize
            }
            i += 1usize
        }
        ret out[0usize..n]
    default:
        ret none
    }
}

fn keys_of(a: *mem.Arena, m: []const json.Member) -> []const str {
    var none: []const str = zero
    let (out, e) = mem.alloc[str](a, m.len + 1usize)
    if e != ok { ret none }
    var i = 0usize
    while i < m.len {
        out[i] = m[i].key
        i += 1usize
    }
    ret out[0usize..m.len]
}

fn rule_of(a: *mem.Arena, x: json.Value) -> w.Rule {
    var r = w.blank_rule(json_encode(a, x), "")
    switch x {
    case .Object as m:
        r.kind = text_of(m, "type")
        r.keys = keys_of(a, m)
        let all = member_of(m, "all")
        let any = member_of(m, "any")
        var group: json.Value = .Null
        if is_array(all) {
            r.has_all = true
            group = all
        } else if is_array(any) {
            r.has_any = true
            group = any
        }
        let items = items_of(group)
        if items.len > 0usize {
            let (kids, e) = mem.alloc[w.Rule](a, items.len)
            if e == ok {
                var i = 0usize
                while i < items.len {
                    kids[i] = rule_of(a, items[i])
                    i += 1usize
                }
                r.children = kids
            }
        }
        r.roles = list_of(a, member_of(m, "roles"))
        r.groups = list_of(a, member_of(m, "groups"))
        r.fields = list_of(a, member_of(m, "fields"))
        r.field = text_of(m, "field")
        let (fv, has_f) = get(m, "filter")
        if has_f && !is_null(fv) {
            r.has_filter = true
            r.filter = node_of(a, fv)
        }
        r.expr = text_of(m, "expr")
        r.table = text_of(m, "table")
        r.approval = text_of(m, "approval")
        r.relation = text_of(m, "relation")
        r.quantifier = text_of(m, "quantifier")
        r.has_quantifier = has_member(m, "quantifier")
        r.message = text_of(m, "message")
    default:
        r.is_object = false
    }
    ret r
}

fn rules_of(a: *mem.Arena, x: json.Value) -> []const w.Rule {
    var none: []const w.Rule = zero
    let items = items_of(x)
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[w.Rule](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        out[i] = rule_of(a, items[i])
        i += 1usize
    }
    ret out
}

fn post_of(a: *mem.Arena, x: json.Value) -> w.PostFn {
    var p = w.blank_post(json_encode(a, x), "")
    switch x {
    case .Object as m:
        p.kind = text_of(m, "type")
        p.keys = keys_of(a, m)
        p.id = text_of(m, "id")
        p.field = text_of(m, "field")
        p.has_field = has_member(m, "field")
        p.value = json_encode(a, member_of(m, "value"))
        p.has_value = has_member(m, "value")
        p.value_spec = json_encode(a, member_of(m, "valueSpec"))
        p.has_value_spec = has_member(m, "valueSpec")
        p.user = json_encode(a, member_of(m, "user"))
        p.has_user = has_member(m, "user")
        p.table = json_encode(a, member_of(m, "table"))
        p.values = json_encode(a, member_of(m, "values"))
        p.has_values = has_member(m, "values")
        p.goal = json_encode(a, member_of(m, "target"))
        p.has_goal = has_member(m, "target")
        p.config = json_encode(a, member_of(m, "config"))
        p.has_config = has_member(m, "config")
        p.workflow_id = json_encode(a, member_of(m, "workflowId"))
        p.has_workflow_id = has_member(m, "workflowId")
        p.params = json_encode(a, member_of(m, "params"))
        p.has_params = has_member(m, "params")
    default:
        p.is_object = false
    }
    ret p
}

fn posts_of(a: *mem.Arena, x: json.Value) -> []const w.PostFn {
    var none: []const w.PostFn = zero
    let items = items_of(x)
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[w.PostFn](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        out[i] = post_of(a, items[i])
        i += 1usize
    }
    ret out
}

fn permissions_of(a: *mem.Arena, x: json.Value) -> w.Permissions {
    var p = w.no_permissions()
    if !is_object(x) { ret p }
    let m = members_of(x)
    p.present = true
    p.roles = list_of(a, member_of(m, "roles"))
    p.users = list_of(a, member_of(m, "users"))
    p.groups = list_of(a, member_of(m, "groups"))
    p.people_fields = list_of(a, member_of(m, "peopleFields"))
    ret p
}

fn screen_of(a: *mem.Arena, x: json.Value) -> w.Screen {
    var s = w.no_screen()
    if !is_object(x) { ret s }
    let m = members_of(x)
    s.present = true
    let items = items_of(member_of(m, "fields"))
    if items.len > 0usize {
        let (out, e) = mem.alloc[w.ScreenField](a, items.len)
        if e == ok {
            var i = 0usize
            while i < items.len {
                let fm = members_of(items[i])
                out[i] = w.ScreenField { field: text_of(fm, "field"), required: bool_member(fm, "required") }
                i += 1usize
            }
            s.fields = out
        }
    }
    ret s
}

fn bool_member(m: []const json.Member, key: str) -> bool {
    let x = member_of(m, key)
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

fn transition_of(a: *mem.Arena, x: json.Value) -> w.Transition {
    let m = members_of(x)
    let icon = member_of(m, "icon")
    ret w.Transition {
        id: text_of(m, "id"), name: text_of(m, "name"), description: text_of(m, "description"), icon: string_of(icon),
        has_icon: is_string(icon), from: text_of(m, "from"), to: text_of(m, "to"), primary: bool_member(m, "primary"),
        conditions: rules_of(a, member_of(m, "conditions")), validators: rules_of(a, member_of(m, "validators")),
        post_functions: posts_of(a, member_of(m, "postFunctions")), permissions: permissions_of(a, member_of(m, "permissions")),
        screen: screen_of(a, member_of(m, "screen")),
    }
}

fn workflow_of(a: *mem.Arena, x: json.Value) -> w.Workflow {
    let m = members_of(x)
    var wf = w.empty_workflow(text_of(m, "id"), text_of(m, "tableId"), text_of(m, "statusField"), text_of(m, "name"))
    wf.status = text_of(m, "status")
    wf.version = number_of(m, "version", 0.0f64)
    let init = member_of(m, "initialState")
    wf.initial_state = string_of(init)
    wf.has_initial = is_string(init)
    wf.blocked_treatment = text_of(m, "blockedTreatment")
    wf.open = bool_member(m, "open")
    let states = items_of(member_of(m, "states"))
    if states.len > 0usize {
        let (out, e) = mem.alloc[w.State](a, states.len)
        if e == ok {
            var i = 0usize
            while i < states.len {
                let sm = members_of(states[i])
                out[i] = w.State { id: text_of(sm, "id"), label: text_of(sm, "label"), category: text_of(sm, "category") }
                i += 1usize
            }
            wf.states = out
        }
    }
    let transitions = items_of(member_of(m, "transitions"))
    if transitions.len > 0usize {
        let (out, e) = mem.alloc[w.Transition](a, transitions.len)
        if e == ok {
            var i = 0usize
            while i < transitions.len {
                out[i] = transition_of(a, transitions[i])
                i += 1usize
            }
            wf.transitions = out
        }
    }
    ret wf
}

fn principal_of(a: *mem.Arena, x: json.Value) -> w.Principal {
    var none: []const str = zero
    var p = w.Principal { present: false, id: "", has_id: false, permissions: none, roles: none, groups: none }
    if !is_object(x) { ret p }
    let m = members_of(x)
    p.present = true
    let id = member_of(m, "id")
    p.id = string_of(id)
    p.has_id = is_string(id)
    p.permissions = list_of(a, member_of(m, "permissions"))
    p.roles = list_of(a, member_of(m, "roles"))
    p.groups = list_of(a, member_of(m, "groups"))
    ret p
}

fn fields_of(a: *mem.Arena, x: json.Value) -> []const f.Field { ret row_of(a, x).fields }

fn pairs_of(a: *mem.Arena, x: json.Value) -> []const w.Pair {
    var none: []const w.Pair = zero
    let m = members_of(x)
    if m.len == 0usize { ret none }
    let (out, e) = mem.alloc[w.Pair](a, m.len)
    if e != ok { ret none }
    var i = 0usize
    while i < m.len {
        out[i] = w.Pair { key: m[i].key, value: string_of(m[i].value) }
        i += 1usize
    }
    ret out
}

fn env_of(a: *mem.Arena, x: json.Value, reg: *const f.Registry) -> w.Env {
    let m = members_of(x)
    var none_tables: []const w.Table = zero
    var none_dt: []const w.DecisionTable = zero
    var env = w.Env {
        reg: reg, has_legacy: false, legacy: pairs_of(a, member_of(m, "legacyMap")), fields: field_defs_of(a, member_of(m, "fields")),
        dataset: none_tables, approvals: pairs_of(a, member_of(m, "approvals")), decision_tables: none_dt,
    }
    env.has_legacy = has_member(m, "legacyMap")
    let ds = members_of(member_of(m, "dataset"))
    if ds.len > 0usize {
        let (out, e) = mem.alloc[w.Table](a, ds.len)
        if e == ok {
            var i = 0usize
            while i < ds.len {
                out[i] = w.Table { name: ds[i].key, rows: rows_of(a, ds[i].value) }
                i += 1usize
            }
            env.dataset = out
        }
    }
    let dts = members_of(member_of(m, "decisionTables"))
    if dts.len > 0usize {
        let (out, e) = mem.alloc[w.DecisionTable](a, dts.len)
        if e == ok {
            var i = 0usize
            while i < dts.len {
                let tm = members_of(dts[i].value)
                var none_rows: []const w.DecisionRow = zero
                var table = w.DecisionTable { id: dts[i].key, has_inputs: false, inputs: list_of(a, member_of(tm, "inputs")), rows: none_rows }
                table.has_inputs = is_array(member_of(tm, "inputs"))
                let rows = items_of(member_of(tm, "rows"))
                if rows.len > 0usize {
                    let (rs, er) = mem.alloc[w.DecisionRow](a, rows.len)
                    if er == ok {
                        var r = 0usize
                        while r < rows.len {
                            let rm = members_of(rows[r])
                            let pairs = members_of(member_of(rm, "when"))
                            let (ks, ek) = mem.alloc[str](a, pairs.len + 1usize)
                            let (vs, ev) = mem.alloc[f.Value](a, pairs.len + 1usize)
                            if ek == ok && ev == ok {
                                var k = 0usize
                                while k < pairs.len {
                                    ks[k] = pairs[k].key
                                    vs[k] = value_of(a, pairs[k].value)
                                    k += 1usize
                                }
                                rs[r] = w.DecisionRow { keys: ks[0usize..pairs.len], values: vs[0usize..pairs.len], result: bool_member(rm, "result") }
                            }
                            r += 1usize
                        }
                        table.rows = rs
                    }
                }
                out[i] = table
                i += 1usize
            }
            env.decision_tables = out
        }
    }
    ret env
}

fn options_of(a: *mem.Arena, x: json.Value) -> w.Options {
    let m = members_of(x)
    let obo = member_of(m, "onBehalfOf")
    let (expected, has_expected) = get(m, "expectedVersion")
    var o = w.Options {
        principal: principal_of(a, member_of(m, "principal")), on_behalf_of: string_of(obo), has_on_behalf: is_string(obo) && string_of(obo).len != 0usize,
        inputs: fields_of(a, member_of(m, "inputs")), channel: text_of(m, "channel"), now: text_of(m, "now"),
        has_expected_version: has_expected, expected_version: f.blank(), override: bool_member(m, "override"), reason: text_of(m, "reason"),
        cascade_depth: number_of(m, "cascadeDepth", 0.0f64),
    }
    if has_expected { o.expected_version = value_of(a, expected) }
    ret o
}

// --- rendering ------------------------------------------------------------------------------------------------------

fn render_value(a: *mem.Arena, x: f.Value, present: bool) -> str {
    if !present || x.kind == .Blank { ret "_" }
    if x.kind == .Number { ret join(a, "N", num(a, x.n)) }
    if x.kind == .Text { ret join(a, "T", hex_text(a, x.s)) }
    if x.kind == .Bool {
        if x.n != 0.0f64 { ret "B1" }
        ret "B0"
    }
    if x.kind == .Record { ret "O" }
    var out = "["
    var i = 0usize
    while i < x.items.len {
        if i > 0usize { out = join(a, out, ",") }
        out = join(a, out, render_value(a, x.items[i], true))
        i += 1usize
    }
    ret join(a, out, "]")
}

fn render_fields(a: *mem.Arena, fields: []const f.Field) -> str {
    var out = ""
    var i = 0usize
    while i < fields.len {
        out = join3(a, out, hex_text(a, fields[i].name), "=")
        out = join3(a, out, render_value(a, fields[i].value, true), ";")
        i += 1usize
    }
    ret out
}

fn render_list(a: *mem.Arena, items: []const str) -> str {
    var out = ""
    var i = 0usize
    while i < items.len {
        if i > 0usize { out = join(a, out, ",") }
        out = join(a, out, hex_text(a, items[i]))
        i += 1usize
    }
    ret out
}

fn render_steps(a: *mem.Arena, steps: []const str) -> str {
    var out = ""
    var i = 0usize
    while i < steps.len {
        out = join3(a, out, hex_text(a, steps[i]), ";")
        i += 1usize
    }
    ret out
}

fn opt_text(a: *mem.Arena, present: bool, s: str) -> str {
    if !present { ret "_" }
    ret hex_text(a, s)
}

fn render_outcome(a: *mem.Arena, o: w.Outcome) -> str {
    if !o.good {
        var out = join(a, "ERR|", o.error_code)
        out = join3(a, out, "|", opt_text(a, o.transition_id.len != 0usize, o.transition_id))
        out = join3(a, out, "|", render_value(a, o.expected, true))
        out = join3(a, out, "|", render_value(a, o.actual, true))
        out = join3(a, out, "|", render_value(a, o.from, o.has_from))
        out = join3(a, out, "|", flag(o.override))
        out = join3(a, out, "|", opt_text(a, o.condition.len != 0usize, o.condition))
        out = join3(a, out, "|", render_list(a, o.missing))
        out = join3(a, out, "|", opt_text(a, o.validator.len != 0usize, o.validator))
        out = join3(a, out, "|", opt_text(a, o.detail.len != 0usize, o.detail))
        ret join3(a, out, "|", opt_text(a, o.has_field, o.field))
    }
    let h = o.history
    var out = join3(a, "OK|", render_fields(a, o.record), "|")
    out = join3(a, out, render_value(a, h.record_id, h.has_record_id), ",")
    out = join3(a, out, hex_text(a, h.workflow_id), ",")
    out = join3(a, out, num(a, h.workflow_version), ",")
    out = join3(a, out, hex_text(a, h.transition_id), ",")
    out = join3(a, out, hex_text(a, h.transition_name), ",")
    out = join3(a, out, render_value(a, h.from, h.has_from), ",")
    out = join3(a, out, hex_text(a, h.to), ",")
    out = join3(a, out, opt_text(a, h.has_actor, h.actor), ",")
    out = join3(a, out, opt_text(a, h.has_on_behalf, h.on_behalf_of), ",")
    out = join3(a, out, hex_text(a, h.channel), ",")
    if h.has_inputs { out = join3(a, out, render_fields(a, h.inputs), ",") } else { out = join(a, out, "_,") }
    out = join3(a, out, flag(h.override), ",")
    out = join3(a, out, opt_text(a, h.has_reason, h.reason), ",")
    out = join3(a, out, hex_text(a, h.at), "|")
    let ev = o.event
    out = join3(a, out, hex_text(a, ev.table_id), ",")
    out = join3(a, out, render_value(a, ev.from, ev.has_from), ",")
    out = join3(a, out, hex_text(a, ev.to), ",")
    out = join3(a, out, hex_text(a, ev.transition_id), ",")
    out = join3(a, out, opt_text(a, ev.has_actor, ev.actor), ",")
    out = join3(a, out, num(a, ev.cascade_depth), ",")
    out = join3(a, out, hex_text(a, ev.dedup_key), "|")
    out = join3(a, out, render_steps(a, o.post_steps), "|")
    ret join(a, out, flag(o.self_transition))
}

fn render_rule_reports(a: *mem.Arena, items: []const w.RuleReport) -> str {
    var out = ""
    var i = 0usize
    while i < items.len {
        out = join3(a, out, hex_text(a, items[i].kind), "=")
        out = join(a, out, flag(items[i].passed))
        if items[i].has_error { out = join(a, join(a, out, "="), hex_text(a, items[i].error_text)) }
        out = join(a, out, ";")
        i += 1usize
    }
    ret out
}

fn render_report(a: *mem.Arena, r: w.Report) -> str {
    if !r.found { ret "ok=0,error=unknown-transition" }
    var out = join3(a, flag(r.good), "|", hex_text(a, r.transition_id))
    out = join3(a, out, "|", hex_text(a, r.transition_name))
    out = join3(a, out, "|", hex_text(a, r.from))
    out = join3(a, out, "|", hex_text(a, r.to))
    out = join3(a, out, "|", flag(r.from_state_ok))
    out = join3(a, out, "|", flag(r.permission_ok))
    out = join3(a, out, "|", render_rule_reports(a, r.conditions))
    out = join3(a, out, "|", render_rule_reports(a, r.validators))
    out = join3(a, out, "|", render_list(a, r.missing_inputs))
    ret join3(a, out, "|", render_steps(a, r.post_preview))
}

fn render_findings(a: *mem.Arena, items: []const w.Finding) -> str {
    var out = ""
    var i = 0usize
    while i < items.len {
        out = join3(a, out, items[i].code, "@")
        out = join3(a, out, opt_text(a, items[i].has_transition, items[i].transition), "@")
        out = join3(a, out, opt_text(a, items[i].has_state, items[i].state), "@")
        out = join3(a, out, hex_text(a, items[i].message), ";")
        i += 1usize
    }
    ret out
}

fn render_workflow_brief(a: *mem.Arena, wf: w.Workflow) -> str {
    var out = join3(a, hex_text(a, wf.name), "|", opt_text(a, wf.has_initial, wf.initial_state))
    out = join3(a, out, "|", wf.status)
    out = join3(a, out, "|", num(a, wf.version))
    out = join(a, out, "|")
    var i = 0usize
    while i < wf.states.len {
        out = join3(a, out, hex_text(a, wf.states[i].id), ":")
        out = join3(a, out, hex_text(a, wf.states[i].label), ":")
        out = join3(a, out, wf.states[i].category, ";")
        i += 1usize
    }
    out = join(a, out, "|")
    i = 0usize
    while i < wf.transitions.len {
        let t = wf.transitions[i]
        out = join3(a, out, hex_text(a, t.id), ":")
        out = join3(a, out, hex_text(a, t.name), ":")
        out = join3(a, out, hex_text(a, t.from), ":")
        out = join3(a, out, hex_text(a, t.to), ":")
        out = join3(a, out, num(a, f64(t.validators.len)), ":")
        out = join3(a, out, num(a, f64(t.post_functions.len)), ":")
        out = join3(a, out, flag(t.screen.present), ";")
        i += 1usize
    }
    ret out
}

fn evaluate(a: *mem.Arena, m: []const json.Member, reg: *const f.Registry) -> str {
    let op = text_of(m, "op")
    if str.eq(op, "validate") {
        let r = w.validate_workflow(a, workflow_of(a, member_of(m, "workflow")))
        ret join3(a, flag(r.valid), "|E:", join3(a, render_findings(a, r.errors), "|W:", render_findings(a, r.warnings)))
    }
    if str.eq(op, "diff") {
        let changes = w.diff_workflows(a, workflow_of(a, member_of(m, "a")), workflow_of(a, member_of(m, "b")))
        var out = ""
        var i = 0usize
        while i < changes.len {
            out = join3(a, out, changes[i].kind, ":")
            out = join3(a, out, hex_text(a, changes[i].id), ":")
            out = join3(a, out, hex_text(a, changes[i].label), ";")
            i += 1usize
        }
        ret out
    }
    if str.eq(op, "allowed") {
        let wf = workflow_of(a, member_of(m, "workflow"))
        let record = fields_of(a, member_of(m, "record"))
        let p = principal_of(a, member_of(m, "principal"))
        let env = env_of(a, member_of(m, "env"), reg)
        let offered = w.allowed_transitions(a, wf, record, p, &env)
        var out = ""
        var i = 0usize
        while i < offered.len {
            if i > 0usize { out = join(a, out, ",") }
            out = join(a, out, hex_text(a, offered[i].id))
            i += 1usize
        }
        out = join(a, out, "#")
        i = 0usize
        while i < wf.transitions.len {
            let x = w.explain_transition(a, wf, record, wf.transitions[i], p, &env)
            out = join3(a, out, hex_text(a, wf.transitions[i].id), "=")
            if x.available { out = join(a, out, "yes") } else { out = join3(a, out, x.reason, join(a, ":", render_list(a, x.conditions))) }
            out = join(a, out, ";")
            i += 1usize
        }
        ret out
    }
    if str.eq(op, "exec") {
        let wf = workflow_of(a, member_of(m, "workflow"))
        let env = env_of(a, member_of(m, "env"), reg)
        ret render_outcome(a, w.execute_transition(a, wf, fields_of(a, member_of(m, "record")), text_of(m, "transitionId"), options_of(a, member_of(m, "opts")), &env))
    }
    if str.eq(op, "resolve") {
        let wf = workflow_of(a, member_of(m, "workflow"))
        let env = env_of(a, member_of(m, "env"), reg)
        let r = w.resolve_status_write(a, wf, fields_of(a, member_of(m, "record")), text_of(m, "status"), principal_of(a, member_of(m, "principal")), &env)
        if r.noop { ret "noop" }
        if r.has_transition { ret join(a, "t:", hex_text(a, r.transition.id)) }
        var out = join(a, "e:", r.error_code)
        if r.candidates.len > 0usize {
            out = join(a, out, ":")
            var i = 0usize
            while i < r.candidates.len {
                if i > 0usize { out = join(a, out, ",") }
                out = join(a, out, hex_text(a, r.candidates[i].id))
                i += 1usize
            }
        }
        ret out
    }
    if str.eq(op, "simulate") {
        let wf = workflow_of(a, member_of(m, "workflow"))
        let env = env_of(a, member_of(m, "env"), reg)
        ret render_report(a, w.simulate_transition(a, wf, fields_of(a, member_of(m, "record")), text_of(m, "transitionId"), principal_of(a, member_of(m, "principal")), &env, fields_of(a, member_of(m, "inputs"))))
    }
    if str.eq(op, "bulk") {
        let wf = workflow_of(a, member_of(m, "workflow"))
        let env = env_of(a, member_of(m, "env"), reg)
        let items = items_of(member_of(m, "records"))
        let (records, e) = mem.alloc[[]const f.Field](a, items.len + 1usize)
        if e != ok { ret "?" }
        var i = 0usize
        while i < items.len {
            records[i] = fields_of(a, items[i])
            i += 1usize
        }
        let atomic = str.eq(text_of(m, "policy"), "atomic")
        let r = w.bulk_transition(a, wf, records[0usize..items.len], text_of(m, "transitionId"), options_of(a, member_of(m, "opts")), &env, atomic)
        var out = join3(a, r.policy, "|", num(a, f64(r.committed)))
        i = 0usize
        while i < r.outcomes.len {
            let b = r.outcomes[i]
            out = join3(a, out, "|", render_value(a, b.record_id, true))
            out = join3(a, out, ":", b.status)
            if str.eq(b.status, "transitioned") {
                out = join3(a, out, ":", render_fields(a, b.record))
            } else if b.blocked_by_probe {
                out = join3(a, out, ":probe:", render_report(a, b.probe))
            } else if b.probe_error.len != 0usize {
                out = join(a, out, ":abort")
            } else {
                out = join3(a, out, ":", join3(a, b.error_code, ":", opt_text(a, b.detail.len != 0usize, b.detail)))
            }
            i += 1usize
        }
        ret out
    }
    if str.eq(op, "time") {
        let items = items_of(member_of(m, "entries"))
        let (entries, e) = mem.alloc[w.Entry](a, items.len + 1usize)
        if e != ok { ret "?" }
        var i = 0usize
        while i < items.len {
            let em = members_of(items[i])
            entries[i] = w.Entry { from: text_of(em, "from"), to: text_of(em, "to"), at: text_of(em, "at") }
            i += 1usize
        }
        let r = w.time_in_state(a, entries[0usize..items.len], text_of(m, "now"))
        var out = ""
        i = 0usize
        while i < r.visits.len {
            let vis = r.visits[i]
            out = join3(a, out, hex_text(a, vis.state), "|")
            out = join3(a, out, hex_text(a, vis.entered_at), "|")
            out = join3(a, out, opt_text(a, vis.has_left, vis.left_at), "|")
            out = join3(a, out, num(a, vis.ms), ";")
            i += 1usize
        }
        out = join(a, out, "#")
        i = 0usize
        while i < r.totals.len {
            out = join3(a, out, hex_text(a, r.totals[i].state), "=")
            out = join3(a, out, num(a, r.totals[i].ms), ";")
            i += 1usize
        }
        ret out
    }
    if str.eq(op, "open") {
        ret render_workflow_brief(a, w.open_workflow(a, text_of(m, "tableId"), text_of(m, "statusField"), list_of(a, member_of(m, "options"))))
    }
    if str.eq(op, "template") {
        let (wf, known) = w.template(a, text_of(m, "key"), text_of(m, "tableId"), text_of(m, "statusField"), "GEN")
        if !known { ret "unknown" }
        ret render_workflow_brief(a, wf)
    }
    if str.eq(op, "normalize") {
        let states = items_of(member_of(m, "states"))
        var out = ""
        var i = 0usize
        while i < states.len {
            switch states[i] {
            case .String as s:
                let st = w.normalize_state(s, "", false, "")
                out = join3(a, out, hex_text(a, st.id), join3(a, ":", hex_text(a, st.label), join(a, ":", st.category)))
            default:
                let sm = members_of(states[i])
                let label = member_of(sm, "label")
                let st = w.normalize_state(text_of(sm, "id"), string_of(label), is_string(label), text_of(sm, "category"))
                out = join3(a, out, hex_text(a, st.id), join3(a, ":", hex_text(a, st.label), join(a, ":", st.category)))
            }
            out = join(a, out, ";")
            i += 1usize
        }
        out = join(a, out, "#")
        let trs = items_of(member_of(m, "transitions"))
        i = 0usize
        while i < trs.len {
            let tm = members_of(trs[i])
            let from = member_of(tm, "from")
            var t = transition_of(a, trs[i])
            t = w.normalize_transition(t, is_string(from), "GEN")
            out = join3(a, out, hex_text(a, t.id), ":")
            out = join3(a, out, hex_text(a, t.name), ":")
            out = join3(a, out, hex_text(a, t.from), ":")
            out = join3(a, out, hex_text(a, t.to), ":")
            out = join3(a, out, flag(t.primary), ";")
            i += 1usize
        }
        ret out
    }
    if str.eq(op, "edit") {
        var wf = workflow_of(a, member_of(m, "workflow"))
        let script = items_of(member_of(m, "script"))
        var out = ""
        var i = 0usize
        while i < script.len {
            let step = items_of(script[i])
            let kind = string_of(step[0usize])
            var r = w.edit_refused(wf, "?")
            if str.eq(kind, "addState") {
                let sm = members_of(step[1usize])
                let label = member_of(sm, "label")
                r = w.add_state(a, wf, w.normalize_state(text_of(sm, "id"), string_of(label), is_string(label), text_of(sm, "category")))
            } else if str.eq(kind, "addTransition") {
                let tm = members_of(step[1usize])
                let t = w.normalize_transition(transition_of(a, step[1usize]), is_string(member_of(tm, "from")), "GEN")
                r = w.add_transition(a, wf, t)
            } else if str.eq(kind, "removeState") {
                r = w.remove_state(a, wf, string_of(step[1usize]))
            }
            if r.failed { out = join3(a, out, "!", join(a, hex_text(a, r.message), ";")) } else {
                wf = r.wf
                out = join(a, out, "ok;")
            }
            i += 1usize
        }
        ret join3(a, out, "#", render_workflow_brief(a, wf))
    }
    ret "?op"
}

//__VECTOR_FUNCTIONS__
fn run(a: *mem.Arena, body: str, reg: *const f.Registry) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 48u16 })
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                let m = members_of(root)
                want = text_of(m, "e")
                got = evaluate(a, m, reg)
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
    let (built, build_error) = library.build(a)
    if build_error != ok { os.exit(90i32) }
    var registry = built
    //__VECTOR_CALLS__
    try io.print("algo fsm ok")
    ret ok
}
