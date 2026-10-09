// The `e.data.validate` record validation against appdor's own `src/validation` (validators, index, conditional,
// bulk): scripts/validate_reference.mjs builds table definitions and records over every field type and rule
// shape, runs appdor's engine over them (the formula engine included) and records the outcome. A line is
// `{"op": ..., ...inputs, "e": outcome}`; the fixture rebuilds the same inputs as Neper values and compares.
use e.algo.formula as f
use e.algo.formula.library as library
use e.data.validate as v
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

// --- values as the reference renders them --------------------------------------------------------------------------

fn render_value(a: *mem.Arena, x: f.Value) -> str {
    if x.kind == .Error { ret "E" }
    if x.kind == .Blank { ret "_" }
    if x.kind == .Number { ret join(a, "N", f.number_text(a, x.n)) }
    if x.kind == .Text { ret join(a, "T", hex_text(a, x.s)) }
    if x.kind == .Bool {
        if x.n != 0.0f64 { ret "B1" }
        ret "B0"
    }
    if x.kind == .Date { ret join(a, "D", f.date_iso(a, x.n)) }
    if x.kind == .Record { ret "O" }
    var out = "["
    var i = 0usize
    while i < x.items.len {
        if i > 0usize { out = join(a, out, ",") }
        out = join(a, out, render_value(a, x.items[i]))
        i += 1usize
    }
    ret join(a, out, "]")
}

fn render_violation(a: *mem.Arena, x: v.Violation) -> str {
    var field = "-"
    if x.has_field { field = hex_text(a, x.field) }
    var rule = "-"
    if x.has_rule_id { rule = hex_text(a, x.rule_id) }
    ret join(a, join(a, join(a, field, ":"), join(a, x.code, ":")), join(a, join(a, x.severity, ":"), join(a, join(a, rule, ":"), hex_text(a, x.message))))
}

fn render_violations(a: *mem.Arena, list: []const v.Violation) -> str {
    var out = ""
    var i = 0usize
    while i < list.len {
        if i > 0usize { out = join(a, out, ";") }
        out = join(a, out, render_violation(a, list[i]))
        i += 1usize
    }
    ret out
}

fn render_flag(b: bool) -> str {
    if b { ret "1" }
    ret "0"
}

fn render_indices(a: *mem.Arena, list: []const usize) -> str {
    var out = ""
    var i = 0usize
    while i < list.len {
        if i > 0usize { out = join(a, out, ",") }
        out = join(a, out, f.number_text(a, f64(list[i])))
        i += 1usize
    }
    ret out
}

// --- JSON to values -------------------------------------------------------------------------------------------------

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

fn bool_of(members: []const json.Member, key: str) -> bool {
    let (x, found) = get(members, key)
    if !found { ret false }
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

// A number member: present, not null.
fn number_of(members: []const json.Member, key: str) -> (f64, bool) {
    let (x, found) = get(members, key)
    if !found { ret (0.0f64, false) }
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret (value, true)
    default:
        ret (0.0f64, false)
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
        if members.len == 0usize { ret f.record(f.zero_items()) }
        let (out, e) = mem.alloc[f.Value](a, members.len)
        if e != ok { ret f.blank() }
        var i = 0usize
        while i < members.len {
            out[i] = value_of(a, members[i].value)
            i += 1usize
        }
        ret f.record(out)
    default:
        ret f.blank()
    }
}

fn fields_of(a: *mem.Arena, x: json.Value) -> []const f.Field {
    let members = members_of(x)
    var none: []const f.Field = zero
    if members.len == 0usize { ret none }
    let (out, e) = mem.alloc[f.Field](a, members.len)
    if e != ok { ret none }
    var i = 0usize
    while i < members.len {
        out[i] = f.Field { name: members[i].key, value: value_of(a, members[i].value) }
        i += 1usize
    }
    ret out
}

fn rows_of(a: *mem.Arena, x: json.Value) -> []const v.Row {
    let items = items_of(x)
    var none: []const v.Row = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[v.Row](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        out[i] = v.Row { fields: fields_of(a, items[i]) }
        i += 1usize
    }
    ret out
}

fn strings_of(a: *mem.Arena, x: json.Value) -> []const str {
    var none: []const str = zero
    switch x {
    case .String as s:
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

fn definition_of(a: *mem.Arena, x: json.Value) -> v.Definition {
    let m = members_of(x)
    var d = v.blank_definition()
    d.name = text_of(m, "name")
    d.label = text_of(m, "label")
    d.type_name = text_of(m, "type")
    d.required = bool_of(m, "required")
    d.computed = bool_of(m, "computed")
    d.show_if = text_of(m, "showIf")
    d.editable_if = text_of(m, "editableIf")
    d.require_if = text_of(m, "requireIf")
    let (min_value, has_min) = get(m, "min")
    if has_min && !is_null(min_value) {
        d.has_min = true
        d.min = value_of(a, min_value)
    }
    let (max_value, has_max) = get(m, "max")
    if has_max && !is_null(max_value) {
        d.has_max = true
        d.max = value_of(a, max_value)
    }
    let (min_length, has_min_length) = number_of(m, "minLength")
    d.has_min_length = has_min_length
    d.min_length = min_length
    let (max_length, has_max_length) = number_of(m, "maxLength")
    d.has_max_length = has_max_length
    d.max_length = max_length
    d.pattern = text_of(m, "pattern")
    let (options, has_options) = get(m, "options")
    switch options {
    case .Array as items:
        d.has_options = true
        let (out, e) = mem.alloc[f.Value](a, items.len + 1usize)
        if e == ok {
            var i = 0usize
            while i < items.len {
                out[i] = value_of(a, items[i])
                i += 1usize
            }
            d.options = out[0usize..items.len]
        }
    default:
        d.has_options = false
    }
    d.allow_user_input = bool_of(m, "allowUserInput")
    let (limit, has_limit) = number_of(m, "limit")
    d.has_limit = has_limit
    d.limit = limit
    let (valid_if, has_valid_if) = get(m, "validIf")
    if has_valid_if { d.valid_if = strings_of(a, valid_if) }
    let (unique, has_unique) = get(m, "unique")
    if has_unique {
        switch unique {
        case .Bool as b:
            d.unique = b
        case .Object as um:
            d.unique = true
            d.unique_case_sensitive = bool_of(um, "caseSensitive")
        default:
            d.unique = false
        }
    }
    let (messages, has_messages) = get(m, "messages")
    if has_messages { d.messages = fields_of(a, messages) }
    let (severities, has_severities) = get(m, "severities")
    if has_severities { d.severities = fields_of(a, severities) }
    d.severity = text_of(m, "severity")
    let (auto, has_auto) = get(m, "autoSet")
    if has_auto {
        let am = members_of(auto)
        d.has_auto_set = true
        d.auto_when = text_of(am, "when")
        d.auto_value = text_of(am, "value")
        d.auto_replace = bool_of(am, "replace")
    }
    d.initial_value = text_of(m, "initialValue")
    let (default_value, has_default) = get(m, "defaultValue")
    if has_default {
        d.has_default = true
        d.default_value = value_of(a, default_value)
    }
    d.suggested_values = text_of(m, "suggestedValues")
    let (suggestion_limit, has_suggestion_limit) = number_of(m, "suggestionLimit")
    d.has_suggestion_limit = has_suggestion_limit
    d.suggestion_limit = suggestion_limit
    ret d
}

fn rule_of(x: json.Value) -> v.Rule {
    let m = members_of(x)
    var r: v.Rule = zero
    let (id, has_id) = get(m, "id")
    switch id {
    case .String as s:
        r.id = s
        r.has_id = true
    default:
        r.has_id = false
    }
    let (field, has_field) = get(m, "field")
    switch field {
    case .String as s:
        r.field = s
        r.has_field = s.len > 0usize
    default:
        r.has_field = false
    }
    r.expression = text_of(m, "expression")
    r.message = text_of(m, "message")
    r.severity = text_of(m, "severity")
    let (active, has_active) = get(m, "active")
    if has_active {
        switch active {
        case .Bool as b:
            r.inactive = !b
        default:
            r.inactive = false
        }
    }
    ret r
}

fn table_of(a: *mem.Arena, x: json.Value) -> v.Table {
    let m = members_of(x)
    var none_defs: []const v.Definition = zero
    var none_rules: []const v.Rule = zero
    var t = v.Table { fields: none_defs, rules: none_rules }
    let (fields, has_fields) = get(m, "fields")
    let field_items = items_of(fields)
    if field_items.len > 0usize {
        let (out, e) = mem.alloc[v.Definition](a, field_items.len)
        if e == ok {
            var i = 0usize
            while i < field_items.len {
                out[i] = definition_of(a, field_items[i])
                i += 1usize
            }
            t.fields = out
        }
    }
    var rules: json.Value = .Null
    let (record_rules, has_record_rules) = get(m, "recordRules")
    if has_record_rules {
        rules = record_rules
    } else {
        let (plain_rules, has_plain) = get(m, "rules")
        if has_plain { rules = plain_rules }
    }
    let rule_items = items_of(rules)
    if rule_items.len > 0usize {
        let (out, e) = mem.alloc[v.Rule](a, rule_items.len)
        if e == ok {
            var i = 0usize
            while i < rule_items.len {
                out[i] = rule_of(rule_items[i])
                i += 1usize
            }
            t.rules = out
        }
    }
    ret t
}

fn containers_of(a: *mem.Arena, x: json.Value) -> []const v.Container {
    let items = items_of(x)
    var none: []const v.Container = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[v.Container](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let m = members_of(items[i])
        let (children, has_children) = get(m, "children")
        let (field_names, has_names) = get(m, "fields")
        out[i] = v.Container { id: text_of(m, "id"), kind: text_of(m, "kind"), show_if: text_of(m, "showIf"), fields: strings_of(a, field_names), children: containers_of(a, children) }
        i += 1usize
    }
    ret out
}

fn context_of(a: *mem.Arena, x: json.Value, now_ms: f64) -> v.Context {
    let m = members_of(x)
    var locale = text_of(m, "locale")
    if locale.len == 0usize { locale = "en" }
    var c = v.context(locale)
    c.base.now = now_ms
    c.base.has_now = true
    let (existing, has_existing) = get(m, "existing")
    switch existing {
    case .Array as items:
        c.has_existing = true
        c.existing = rows_of(a, existing)
    default:
        c.has_existing = false
    }
    c.is_new = bool_of(m, "isNew")
    let (prior, has_prior) = get(m, "prior")
    if has_prior {
        c.has_prior = true
        c.prior = fields_of(a, prior)
    }
    c.self_index = -1i64
    ret c
}

fn run(a: *mem.Arena, body: str, reg: *f.Registry, now_ms: f64) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 24u16 })
            var good = false
            var got = ""
            var want = ""
            if parse_error == ok {
                let m = members_of(root)
                want = text_of(m, "e")
                let op = text_of(m, "op")
                let (ctx_value, has_ctx) = get(m, "ctx")
                let ctx = context_of(a, ctx_value, now_ms)
                if str.eq(op, "validate") {
                    let (table_value, ht) = get(m, "table")
                    let (record_value, hr) = get(m, "record")
                    let table = table_of(a, table_value)
                    let record = fields_of(a, record_value)
                    var local = ctx
                    // an existing row that is the record itself, named by index
                    let (self_value, has_self) = number_of(m, "self")
                    if has_self { local.self_index = i64(self_value) }
                    let out = v.validate_record(a, reg, table, record, &local)
                    got = join(a, join(a, render_flag(out.valid), "|"), render_violations(a, out.violations))
                } else if str.eq(op, "behavior") {
                    let (field_value, hf) = get(m, "field")
                    let (record_value, hr) = get(m, "record")
                    let b = v.field_behavior(a, reg, definition_of(a, field_value), fields_of(a, record_value), &ctx)
                    got = join(a, join(a, render_flag(b.visible), render_flag(b.editable)), render_flag(b.required))
                } else if str.eq(op, "import") {
                    let (table_value, ht) = get(m, "table")
                    let (rows_value, hr) = get(m, "rows")
                    let rows = rows_of(a, rows_value)
                    let r = v.validate_import(a, reg, table_of(a, table_value), rows, text_of(m, "policy"), ctx.existing, &ctx)
                    var out = join(a, join(a, r.policy, "|"), join(a, render_flag(r.valid), "|"))
                    out = join(a, out, join(a, render_indices(a, r.imported), "|"))
                    out = join(a, out, join(a, render_indices(a, r.rejected), "|"))
                    out = join(a, out, join(a, render_indices(a, r.flagged), "|"))
                    var k = 0usize
                    while k < r.rows.len {
                        out = join(a, out, join(a, render_flag(r.rows[k].valid), render_violations(a, r.rows[k].violations)))
                        out = join(a, out, "/")
                        k += 1usize
                    }
                    out = join(a, out, join(a, "|", f.number_text(a, f64(r.summary.total))))
                    out = join(a, out, join(a, ",", f.number_text(a, f64(r.summary.valid))))
                    out = join(a, out, join(a, ",", f.number_text(a, f64(r.summary.invalid))))
                    k = 0usize
                    while k < r.summary.by_code.len {
                        out = join(a, out, join(a, ",", join(a, r.summary.by_code[k].code, join(a, "=", f.number_text(a, f64(r.summary.by_code[k].count))))))
                        k += 1usize
                    }
                    got = out
                } else if str.eq(op, "backfill") {
                    let (table_value, ht) = get(m, "table")
                    let (records_value, hr) = get(m, "records")
                    let (rule_value, hrule) = get(m, "rule")
                    let rule_members = members_of(rule_value)
                    let (field_name, has_rule_field) = get(rule_members, "field")
                    var sample = 10usize
                    let (sample_value, has_sample) = number_of(m, "sample")
                    if has_sample { sample = usize(sample_value) }
                    var r: v.BackfillReport = zero
                    if has_rule_field {
                        var candidate = definition_of(a, rule_value)
                        candidate.name = text_of(rule_members, "field")
                        r = v.backfill_check(a, reg, table_of(a, table_value), rows_of(a, records_value), candidate, true, zero, sample, &ctx)
                    } else {
                        r = v.backfill_check(a, reg, table_of(a, table_value), rows_of(a, records_value), v.blank_definition(), false, rule_of(rule_value), sample, &ctx)
                    }
                    var out = join(a, f.number_text(a, f64(r.checked)), join(a, "|", f.number_text(a, f64(r.violating))))
                    out = join(a, out, "|")
                    var k = 0usize
                    while k < r.violations.len {
                        out = join(a, out, join(a, f.number_text(a, f64(r.violations[k].index)), join(a, "=", join(a, render_violation(a, r.violations[k].violation), ";"))))
                        k += 1usize
                    }
                    out = join(a, out, join(a, "|", f.number_text(a, f64(r.sample.len))))
                    got = out
                } else if str.eq(op, "dups") {
                    let (record_value, hr) = get(m, "record")
                    let (existing_value, he) = get(m, "existing")
                    let (config_value, hc) = get(m, "config")
                    let config = members_of(config_value)
                    let (fields_value, hf) = get(config, "fields")
                    var threshold = 1.0f64
                    let (t, has_t) = number_of(config, "threshold")
                    if has_t { threshold = t }
                    let list = v.find_duplicates(a, fields_of(a, record_value), rows_of(a, existing_value), -1i64, strings_of(a, fields_value), threshold)
                    var out = ""
                    var k = 0usize
                    while k < list.len {
                        out = join(a, out, join(a, f.number_text(a, f64(list[k].index)), join(a, ":", join(a, f.number_text(a, list[k].score), join(a, ":", join(a, f.number_text(a, f64(list[k].matched)), join(a, ":", join(a, f.number_text(a, f64(list[k].compared)), ";"))))))))
                        k += 1usize
                    }
                    got = out
                } else if str.eq(op, "suggest") {
                    let (field_value, hf) = get(m, "field")
                    let (record_value, hr) = get(m, "record")
                    let (limit, has_limit) = number_of(m, "limit")
                    let s = v.suggested_values(a, reg, definition_of(a, field_value), fields_of(a, record_value), &ctx, has_limit, limit)
                    var out = join(a, render_flag(s.constrained), render_flag(s.failed))
                    out = join(a, out, "|")
                    var k = 0usize
                    while k < s.values.len {
                        if k > 0usize { out = join(a, out, ",") }
                        out = join(a, out, render_value(a, s.values[k]))
                        k += 1usize
                    }
                    got = out
                } else if str.eq(op, "containers") {
                    let (containers_value, hc) = get(m, "containers")
                    let (record_value, hr) = get(m, "record")
                    let states = v.evaluate_containers(a, reg, containers_of(a, containers_value), fields_of(a, record_value), &ctx)
                    var out = ""
                    var k = 0usize
                    while k < states.len {
                        out = join(a, out, join(a, states[k].id, join(a, ":", join(a, render_flag(states[k].visible), join(a, render_flag(states[k].self_visible), join(a, render_flag(states[k].hidden_by_ancestor), join(a, ":", join(a, states[k].kind, ";"))))))))
                        k += 1usize
                    }
                    got = out
                } else if str.eq(op, "form") {
                    let (form_value, hf) = get(m, "form")
                    let form = members_of(form_value)
                    let (containers_value, hc) = get(form, "containers")
                    let (fields_value, hfields) = get(form, "fields")
                    let (record_value, hr) = get(m, "record")
                    let defs_items = items_of(fields_value)
                    let (defs, de) = mem.alloc[v.Definition](a, defs_items.len + 1usize)
                    var k = 0usize
                    while k < defs_items.len && de == ok {
                        defs[k] = definition_of(a, defs_items[k])
                        k += 1usize
                    }
                    let behaviors = v.evaluate_form_behavior(a, reg, defs[0usize..defs_items.len], containers_of(a, containers_value), fields_of(a, record_value), &ctx)
                    var out = ""
                    k = 0usize
                    while k < behaviors.len {
                        var holder = "-"
                        if behaviors[k].has_container { holder = behaviors[k].container }
                        out = join(a, out, join(a, behaviors[k].name, join(a, ":", join(a, render_flag(behaviors[k].visible), join(a, render_flag(behaviors[k].editable), join(a, render_flag(behaviors[k].required), join(a, ":", join(a, holder, ";"))))))))
                        k += 1usize
                    }
                    got = out
                } else if str.eq(op, "initial") {
                    let (table_value, ht) = get(m, "table")
                    let values = v.compute_initial_values(a, reg, table_of(a, table_value), &ctx)
                    var out = ""
                    var k = 0usize
                    while k < values.len {
                        out = join(a, out, join(a, values[k].name, join(a, "=", join(a, render_value(a, values[k].value), ";"))))
                        k += 1usize
                    }
                    got = out
                } else if str.eq(op, "autoset") {
                    let (table_value, ht) = get(m, "table")
                    let (record_value, hr) = get(m, "record")
                    let values = v.apply_auto_set(a, reg, table_of(a, table_value), fields_of(a, record_value), &ctx)
                    var out = ""
                    var k = 0usize
                    while k < values.len {
                        out = join(a, out, join(a, values[k].name, join(a, "=", join(a, render_value(a, values[k].value), ";"))))
                        k += 1usize
                    }
                    got = out
                } else if str.eq(op, "computed") {
                    let (table_value, ht) = get(m, "table")
                    let (keys_value, hk) = get(m, "keys")
                    let list = v.computed_write_violations(a, table_of(a, table_value), strings_of(a, keys_value), &ctx)
                    got = render_violations(a, list)
                }
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

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    let (built, build_error) = library.build(a)
    if build_error != ok { os.exit(90i32) }
    var registry = built
    let (now_ms, now_ok) = f.parse_iso("2026-06-15T09:30:00.000Z")
    //__VECTOR_CALLS__
    try io.print("data validate ok")
    ret ok
}
