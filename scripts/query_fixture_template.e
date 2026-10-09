// The `e.algo.view` and `e.algo.pivot` modules against appdor's own `src/views/query.js`, `src/grid/{filter-tree,
// multi-sort}.js`, `src/charts/{buckets,aggregate,server-aggregate}.js` and `src/pivot/index.js`:
// scripts/query_reference.mjs runs appdor's engine over random record sets, field descriptors, filter trees, view
// configs, chart, KPI and pivot configs and writes `{"op": ..., ...inputs, "e": outcome}` lines; the fixture rebuilds
// the inputs as Neper values and must produce the same rendering.
use e.algo.formula as f
use e.algo.formula.library as library
use e.algo.pivot as p
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

fn render_value(a: *mem.Arena, x: f.Value) -> str {
    if x.kind == .Blank { ret "_" }
    if x.kind == .Number { ret join(a, "N", num(a, x.n)) }
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

fn render_cell(a: *mem.Arena, c: p.Cell) -> str {
    if c.none { ret "_" }
    ret num(a, c.n)
}

// --- JSON to values ---------------------------------------------------------------------------------------------

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

fn sorts_of(a: *mem.Arena, x: json.Value) -> []const v.SortSpec {
    let items = items_of(x)
    var none: []const v.SortSpec = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[v.SortSpec](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let m = members_of(items[i])
        out[i] = v.SortSpec { field: text_of(m, "field"), direction: text_of(m, "direction") }
        i += 1usize
    }
    ret out
}

fn context_of(a: *mem.Arena, x: json.Value) -> v.Context {
    let m = members_of(x)
    var c: v.Context = zero
    let (now, has_now) = get(m, "now")
    switch now {
    case .String as s:
        let (ms, good) = f.parse_iso(s)
        c.now = ms
        c.has_now = good
    default:
        c.has_now = false
    }
    let (user, has_user) = get(m, "userId")
    if has_user {
        c.user_id = value_of(a, user)
        c.has_user = true
    } else {
        c.user_id = f.blank()
    }
    ret c
}

// --- rendering --------------------------------------------------------------------------------------------------

// The positions of the picked rows: every input row carries its position as text in the field `~idx`, after a
// control character no data value contains.
fn render_indices(a: *mem.Arena, all: []const v.Row, picked: []const v.Row) -> str {
    var out = ""
    var i = 0usize
    while i < picked.len {
        let tag = v.value_at(picked[i], "~idx")
        var shown = "?"
        if tag.kind == .Text && tag.s.len > 1usize { shown = tag.s[1usize..tag.s.len] }
        if i > 0usize { out = join(a, out, ",") }
        out = join(a, out, shown)
        i += 1usize
    }
    ret out
}

fn render_node(a: *mem.Arena, n: v.Node) -> str {
    if v.is_group(n) {
        var out = join3(a, "G[", n.operator, "](")
        var i = 0usize
        while i < n.children.len {
            if i > 0usize { out = join(a, out, ";") }
            out = join(a, out, render_node(a, n.children[i]))
            i += 1usize
        }
        ret join(a, out, ")")
    }
    var operand = "U"
    if n.operand.present { operand = render_value(a, n.operand.value) }
    if n.operand.is_object { operand = "O" }
    ret join3(a, join3(a, "C[", hex_text(a, n.field), "|"), join3(a, n.op, "|", n.type_name), join3(a, "|", operand, "]"))
}

fn render_summary(a: *mem.Arena, s: v.Summary) -> str {
    if s.kind == 0u8 { ret "-" }
    if s.kind == 1u8 { ret join(a, "n", num(a, s.n)) }
    if s.kind == 2u8 { ret join(a, "d", f.date_iso(a, s.n)) }
    if s.kind == 4u8 { ret join(a, "b", num(a, s.n)) }
    var out = "dist"
    var i = 0usize
    while i < s.entries.len {
        out = join(a, out, join3(a, ":", hex_text(a, s.entries[i].label), join(a, "=", num(a, f64(s.entries[i].count)))))
        i += 1usize
    }
    ret out
}

fn render_chart(a: *mem.Arena, d: p.ChartData) -> str {
    var out = ""
    var i = 0usize
    while i < d.labels.len {
        if i > 0usize { out = join(a, out, ",") }
        out = join(a, out, hex_text(a, d.labels[i]))
        i += 1usize
    }
    out = join(a, out, "|")
    i = 0usize
    while i < d.datasets.len {
        let s = d.datasets[i]
        out = join(a, out, hex_text(a, s.label))
        if s.has_split {
            if s.split_none { out = join(a, out, "~null") } else { out = join(a, out, join(a, "~", render_value(a, s.split_value))) }
        }
        out = join(a, out, "=")
        var k = 0usize
        while k < s.data.len {
            if k > 0usize { out = join(a, out, ",") }
            out = join(a, out, render_cell(a, s.data[k]))
            k += 1usize
        }
        out = join(a, out, ";")
        i += 1usize
    }
    out = join(a, out, "|")
    i = 0usize
    while i < d.drilldown.len {
        let g = d.drilldown[i]
        if g.other {
            out = join(a, out, "other;")
        } else if g.is_null {
            out = join(a, out, join3(a, hex_text(a, g.field), "=null", ";"))
        } else {
            out = join(a, out, join3(a, hex_text(a, g.field), join(a, "=", render_value(a, g.value)), ";"))
        }
        i += 1usize
    }
    ret out
}

fn series_of(a: *mem.Arena, x: json.Value) -> []const p.Series {
    let items = items_of(x)
    var none: []const p.Series = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[p.Series](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let m = members_of(items[i])
        out[i] = p.Series { field: text_of(m, "field"), aggregation: text_of(m, "aggregation"), label: text_of(m, "label") }
        i += 1usize
    }
    ret out
}

fn thresholds_of(a: *mem.Arena, x: json.Value) -> []const p.Threshold {
    let items = items_of(x)
    var none: []const p.Threshold = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[p.Threshold](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let m = members_of(items[i])
        out[i] = p.Threshold { value: number_of(m, "value", 0.0f64), has_value: has_number(m, "value"), label: text_of(m, "label"), color: text_of(m, "color"), icon: text_of(m, "icon") }
        i += 1usize
    }
    ret out
}

fn chart_config_of(a: *mem.Arena, m: []const json.Member) -> p.ChartConfig {
    var c: p.ChartConfig = zero
    c.chart_type = text_of(m, "chartType")
    c.x_field = text_of(m, "xField")
    c.x_bucket = bucket_of(m, "xBucket")
    c.split_field = text_of(m, "splitField")
    let (series, has_series) = get(m, "series")
    c.series = series_of(a, series)
    let (filter, has_filter) = get(m, "filter")
    if has_filter && !is_null(filter) {
        c.has_filter = true
        c.filter = node_of(a, filter)
    }
    let top_n = number_of(m, "topN", 0.0f64)
    if top_n > 0.0f64 { c.top_n = usize(top_n) }
    let (comparison, has_comparison) = get(m, "comparison")
    if has_comparison {
        let cm = members_of(comparison)
        let (cf, has_cf) = get(cm, "filter")
        if has_cf && !is_null(cf) {
            c.has_comparison_filter = true
            c.comparison_filter = node_of(a, cf)
        }
    }
    let (thresholds, has_thresholds) = get(m, "thresholds")
    c.thresholds = thresholds_of(a, thresholds)
    ret c
}

fn measures_of(a: *mem.Arena, x: json.Value) -> []const p.Measure {
    let items = items_of(x)
    var none: []const p.Measure = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[p.Measure](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let m = members_of(items[i])
        out[i] = p.Measure { series: p.Series { field: text_of(m, "field"), aggregation: text_of(m, "aggregation"), label: "" }, label: text_of(m, "label") }
        i += 1usize
    }
    ret out
}

fn render_conditions(a: *mem.Arena, list: []const p.Condition) -> str {
    var out = ""
    var i = 0usize
    while i < list.len {
        let c = list[i]
        out = join(a, out, join3(a, hex_text(a, c.field), join3(a, ":", c.op, ":"), c.type_name))
        if c.is_bucket {
            var bucket = "-"
            if c.has_bucket { bucket = c.bucket }
            out = join(a, out, join3(a, ":bucket=", bucket, join3(a, ":", render_value(a, c.bucket_value), ":")))
            var k = 0usize
            while k < c.bucket_values.len {
                out = join(a, out, join(a, render_value(a, c.bucket_values[k]), ","))
                k += 1usize
            }
        } else if c.has_value {
            out = join(a, out, join(a, ":", hex_text(a, c.value)))
        }
        out = join(a, out, ";")
        i += 1usize
    }
    ret out
}

fn path_of(a: *mem.Arena, x: json.Value) -> []usize {
    var none: []usize = zero
    let items = items_of(x)
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[usize](a, items.len)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < items.len {
        switch items[i] {
        case .Number as num_value:
            let (value, ne) = json.number_f64(num_value)
            out[n] = usize(value)
            n += 1usize
        default:
            n += 0usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn run(a: *mem.Arena, body: str, reg: *f.Registry) -> u8 {
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
                let (rows_value, has_rows) = get(m, "rows")
                let rows = rows_of(a, rows_value)
                let (fields_value, has_fields) = get(m, "fields")
                let fields = field_defs_of(a, fields_value)
                let (ctx_value, has_ctx) = get(m, "ctx")
                let ctx = context_of(a, ctx_value)
                if str.eq(op, "filter") {
                    let (tree_value, has_tree) = get(m, "tree")
                    var has_filter = false
                    var tree = v.empty_group("and")
                    if has_tree && !is_null(tree_value) {
                        has_filter = true
                        tree = node_of(a, tree_value)
                    }
                    got = render_indices(a, rows, v.filter_rows(a, reg, rows, tree, has_filter, fields, &ctx))
                } else if str.eq(op, "sort") {
                    let (sorts_value, hs) = get(m, "sorts")
                    got = render_indices(a, rows, v.sort_rows(a, rows, sorts_of(a, sorts_value), fields))
                } else if str.eq(op, "group") {
                    let (spec_value, hs) = get(m, "spec")
                    var field = ""
                    var direction = ""
                    switch spec_value {
                    case .String as s:
                        field = s
                    case .Object as sm:
                        field = text_of(sm, "field")
                        direction = text_of(sm, "direction")
                    default:
                        field = ""
                    }
                    let groups = v.group_rows(a, rows, field, direction, fields)
                    var out = ""
                    var k = 0usize
                    while k < groups.len {
                        var shown = "null"
                        if !groups[k].is_none { shown = render_value(a, groups[k].value) }
                        out = join(a, out, join3(a, shown, join3(a, "/", hex_text(a, groups[k].label), "="), render_indices(a, rows, groups[k].rows)))
                        out = join(a, out, ";")
                        k += 1usize
                    }
                    got = out
                } else if str.eq(op, "summary") {
                    let (values_value, hv) = get(m, "values")
                    let list = items_of(values_value)
                    let (vals, ve) = mem.alloc[f.Value](a, list.len + 1usize)
                    if ve == ok {
                        var k = 0usize
                        while k < list.len {
                            vals[k] = value_of(a, list[k])
                            k += 1usize
                        }
                        got = render_summary(a, v.summarize_values(a, vals[0usize..list.len], text_of(m, "fn")))
                    }
                } else if str.eq(op, "search") {
                    let (names_value, hn) = get(m, "names")
                    got = render_indices(a, rows, v.quick_search(a, rows, text_of(m, "term"), strings_of(a, names_value)))
                } else if str.eq(op, "bucket") {
                    let (value, hv) = get(m, "value")
                    let (key, is_none) = v.bucket_key(a, value_of(a, value), bucket_of(m, "bucket"))
                    if is_none { got = "none" } else { got = hex_text(a, key) }
                } else if str.eq(op, "aggregate") {
                    let (series_value, hs) = get(m, "series")
                    let list = series_of(a, series_value)
                    var series = p.count_series()
                    if list.len > 0usize { series = list[0usize] } else { series = p.Series { field: "", aggregation: "", label: "" } }
                    got = render_cell(a, p.aggregate(a, rows, series))
                } else if str.eq(op, "chart") {
                    let (config_value, hc) = get(m, "config")
                    let config = chart_config_of(a, members_of(config_value))
                    got = render_chart(a, p.build_chart_data(a, reg, rows, config, fields, &ctx))
                } else if str.eq(op, "kpi") {
                    let (config_value, hc) = get(m, "config")
                    let config = chart_config_of(a, members_of(config_value))
                    let k = p.build_kpi(a, reg, rows, config, fields, &ctx)
                    var out = join(a, render_cell(a, k.value), join(a, "|", num(a, f64(k.row_count))))
                    if k.has_comparison {
                        out = join(a, out, join3(a, "|", render_cell(a, k.comparison.value), join3(a, ":", num(a, k.comparison.delta), join3(a, ":", render_cell(a, k.comparison.percent_delta), join(a, ":", k.comparison.direction))))
)
                    }
                    if k.has_threshold {
                        out = join(a, out, join3(a, "|", hex_text(a, k.threshold.label), join3(a, ":", k.threshold.color, join3(a, ":", hex_text(a, k.threshold.icon), join(a, ":", num(a, f64(k.threshold.band)))))))
                    }
                    got = out
                } else if str.eq(op, "pivot") {
                    let (config_value, hc) = get(m, "config")
                    let cm = members_of(config_value)
                    let (rf, h1) = get(cm, "rows")
                    let (cf, h2) = get(cm, "columns")
                    let (measure_value, h3) = get(cm, "measure")
                    let mm = members_of(measure_value)
                    var measure = p.Series { field: text_of(mm, "field"), aggregation: text_of(mm, "aggregation"), label: "" }
                    let (filter, has_filter) = get(cm, "filter")
                    var tree = v.empty_group("and")
                    var use_filter = false
                    if has_filter && !is_null(filter) {
                        use_filter = true
                        tree = node_of(a, filter)
                    }
                    let pv = p.build_pivot(a, reg, rows, strings_of(a, rf), strings_of(a, cf), measure, use_filter, tree, fields, &ctx)
                    var out = ""
                    var k = 0usize
                    while k < pv.row_keys.len {
                        out = join(a, out, hex_text(a, pv.row_keys[k]))
                        out = join(a, out, ",")
                        k += 1usize
                    }
                    out = join(a, out, "|")
                    k = 0usize
                    while k < pv.column_keys.len {
                        out = join(a, out, join(a, hex_text(a, pv.column_keys[k]), ","))
                        k += 1usize
                    }
                    out = join(a, out, "|")
                    k = 0usize
                    while k < pv.rows.len {
                        var c = 0usize
                        while c < pv.rows[k].cells.len {
                            out = join(a, out, join(a, render_cell(a, pv.rows[k].cells[c]), ","))
                            c += 1usize
                        }
                        out = join(a, out, join(a, render_cell(a, pv.rows[k].total), ";"))
                        k += 1usize
                    }
                    out = join(a, out, "|")
                    k = 0usize
                    while k < pv.column_totals.len {
                        out = join(a, out, join(a, render_cell(a, pv.column_totals[k]), ","))
                        k += 1usize
                    }
                    got = join(a, out, join(a, "|", render_cell(a, pv.grand_total)))
                } else if str.eq(op, "report") {
                    let (config_value, hc) = get(m, "config")
                    let cm = members_of(config_value)
                    let (gb, h1) = get(cm, "groupBy")
                    let (measures_value, h2) = get(cm, "measures")
                    let (filter, has_filter) = get(cm, "filter")
                    var tree = v.empty_group("and")
                    var use_filter = false
                    if has_filter && !is_null(filter) {
                        use_filter = true
                        tree = node_of(a, filter)
                    }
                    let r = p.summary_report(a, reg, rows, strings_of(a, gb), measures_of(a, measures_value), use_filter, tree, fields, &ctx)
                    var out = ""
                    var k = 0usize
                    while k < r.labels.len {
                        out = join(a, out, join(a, hex_text(a, r.labels[k]), ","))
                        k += 1usize
                    }
                    out = join(a, out, "|")
                    k = 0usize
                    while k < r.groups.len {
                        out = join(a, out, join3(a, hex_text(a, r.groups[k].key), join(a, ":", num(a, f64(r.groups[k].count))), ":"))
                        var c = 0usize
                        while c < r.groups[k].values.len {
                            out = join(a, out, join(a, render_cell(a, r.groups[k].values[c]), ","))
                            c += 1usize
                        }
                        out = join(a, out, ";")
                        k += 1usize
                    }
                    out = join(a, out, "|")
                    k = 0usize
                    while k < r.grand_total.len {
                        out = join(a, out, join(a, render_cell(a, r.grand_total[k]), ","))
                        k += 1usize
                    }
                    got = join(a, out, join(a, "|", num(a, f64(r.total))))
                } else if str.eq(op, "tree") {
                    let (tree_value, ht) = get(m, "tree")
                    var tree = v.empty_group("and")
                    var has_tree = false
                    if ht && !is_null(tree_value) {
                        tree = node_of(a, tree_value)
                        has_tree = true
                    }
                    let action = text_of(m, "action")
                    let (path_value, hp) = get(m, "path")
                    let path = path_of(a, path_value)
                    let (node_value, hn) = get(m, "node")
                    if str.eq(action, "add") {
                        got = render_node(a, v.add_node(a, tree, path, node_of(a, node_value)))
                    } else if str.eq(action, "remove") {
                        got = render_node(a, v.remove_node(a, tree, path))
                    } else if str.eq(action, "replace") {
                        got = render_node(a, v.replace_node(a, tree, path, node_of(a, node_value)))
                    } else if str.eq(action, "toggle") {
                        let (flipped, did) = v.toggle_group_operator(a, tree, path)
                        if did { got = join(a, render_node(a, flipped), join(a, "|", flipped.operator)) } else { got = join(a, render_node(a, flipped), "|null") }
                    } else if str.eq(action, "prune") {
                        let (pruned, kept) = v.prune_tree(a, tree)
                        if kept && has_tree { got = render_node(a, pruned) } else { got = "null" }
                    } else if str.eq(action, "count") {
                        got = num(a, f64(v.count_conditions(tree)))
                    } else {
                        got = num(a, f64(v.tree_depth(tree)))
                    }
                } else if str.eq(op, "sortlevels") {
                    let (sorts_value, hs) = get(m, "sorts")
                    let sorts = sorts_of(a, sorts_value)
                    let field = text_of(m, "field")
                    let action = text_of(m, "action")
                    var result = sorts
                    var extra = ""
                    if str.eq(action, "append") {
                        let (next, direction) = v.append_sort_level(a, sorts, field)
                        result = next
                        extra = direction
                    } else if str.eq(action, "remove") {
                        result = v.remove_sort_level(a, sorts, field)
                    } else if str.eq(action, "move") {
                        let (next, moved) = v.move_sort_level(a, sorts, field, i64(number_of(m, "delta", 0.0f64)))
                        result = next
                        if moved { extra = "moved" }
                    } else {
                        extra = num(a, f64(v.sort_level(sorts, field)))
                    }
                    var out = ""
                    var k = 0usize
                    while k < result.len {
                        out = join(a, out, join3(a, hex_text(a, result[k].field), ":", join(a, result[k].direction, ",")))
                        k += 1usize
                    }
                    got = join(a, out, join(a, "|", extra))
                } else if str.eq(op, "plan") {
                    let (config_value, hc) = get(m, "config")
                    let cm = members_of(config_value)
                    var pc: p.PlanConfig = zero
                    pc.table_id = text_of(cm, "tableId")
                    let (series_value, hs) = get(cm, "series")
                    pc.series = series_of(a, series_value)
                    pc.aggregation = text_of(cm, "aggregation")
                    pc.field = text_of(cm, "field")
                    pc.measure_field = text_of(cm, "measureField")
                    pc.x_field = text_of(cm, "xField")
                    let (xb, has_xb) = get(cm, "xBucket")
                    switch xb {
                    case .String as s:
                        pc.x_bucket = v.Bucket { name: s, size: 0.0f64, has_size: false }
                    case .Object as xm:
                        let (size, has_size) = get(xm, "size")
                        let size_n = number_of(xm, "size", f.nan())
                        if has_size && size_n == size_n && size_n - size_n == 0.0f64 {
                            pc.x_bucket = v.Bucket { name: "", size: size_n, has_size: true }
                            pc.x_bucket_size_text = num(a, size_n)
                        } else {
                            pc.x_bucket_invalid = true
                        }
                    default:
                        pc.x_bucket = v.no_bucket()
                    }
                    pc.split_field = text_of(cm, "splitField")
                    let top_n = number_of(cm, "topN", 0.0f64)
                    if top_n > 0.0f64 { pc.top_n = usize(top_n) }
                    let (comparison, has_comparison) = get(cm, "comparison")
                    if has_comparison {
                        let (cf, has_cf) = get(members_of(comparison), "filter")
                        if has_cf && !is_null(cf) { pc.has_comparison_filter = true }
                    }
                    let (filter, has_filter) = get(cm, "filter")
                    if has_filter && !is_null(filter) {
                        pc.has_filter = true
                        pc.filter = node_of(a, filter)
                    }
                    let plan = p.plan_aggregate(a, pc, text_of(m, "kind"))
                    if !plan.usable {
                        got = join(a, "no:", plan.reason)
                    } else {
                        let g = plan.args
                        var x = "-"
                        if g.has_x_field { x = hex_text(a, g.x_field) }
                        var xbk = "-"
                        if g.has_x_bucket { xbk = g.x_bucket }
                        var mf = "-"
                        if g.has_measure_field { mf = hex_text(a, g.measure_field) }
                        var sf = "-"
                        if g.has_split_field { sf = hex_text(a, g.split_field) }
                        var head = join3(a, "ok:", hex_text(a, g.table_id), ":")
                        head = join(a, head, join3(a, x, ":", xbk))
                        head = join(a, head, join3(a, ":", g.aggregation, ":"))
                        head = join(a, head, join3(a, mf, ":", sf))
                        head = join(a, head, join3(a, ":", num(a, f64(g.limit)), ":"))
                        got = join(a, head, render_conditions(a, g.conditions))
                    }
                } else if str.eq(op, "gchart") || str.eq(op, "gkpi") {
                    let (groups_value, hg) = get(m, "groups")
                    let list = items_of(groups_value)
                    let (groups, ge) = mem.alloc[p.Group](a, list.len + 1usize)
                    if ge == ok {
                        var k = 0usize
                        while k < list.len {
                            let gm = members_of(list[k])
                            let (bucket, has_bucket) = get(gm, "bucket")
                            let (split, has_split) = get(gm, "split")
                            let (measure, has_measure) = get(gm, "measure")
                            var mc = p.no_cell()
                            switch measure {
                            case .Number as n:
                                let (value, e) = json.number_f64(n)
                                mc = p.cell(value)
                            default:
                                mc = p.no_cell()
                            }
                            var b = ""
                            var b_ok = false
                            switch bucket {
                            case .String as s:
                                b = s
                                b_ok = true
                            default:
                                b_ok = false
                            }
                            var sp = ""
                            var sp_ok = false
                            switch split {
                            case .String as s:
                                sp = s
                                sp_ok = true
                            default:
                                sp_ok = false
                            }
                            groups[k] = p.Group { bucket: b, has_bucket: b_ok, split: sp, has_split: sp_ok, measure: mc, row_count: number_of(gm, "row_count", 0.0f64) }
                            k += 1usize
                        }
                    }
                    let (config_value, hc) = get(m, "config")
                    let cm = members_of(config_value)
                    if str.eq(op, "gchart") {
                        var pc: p.PlanConfig = zero
                        let (series_value, hs) = get(cm, "series")
                        pc.series = series_of(a, series_value)
                        pc.aggregation = text_of(cm, "aggregation")
                        pc.x_field = text_of(cm, "xField")
                        pc.split_field = text_of(cm, "splitField")
                        let top_n = number_of(cm, "topN", 0.0f64)
                        if top_n > 0.0f64 { pc.top_n = usize(top_n) }
                        let r = p.chart_data_from_groups(a, groups[0usize..list.len], pc, text_of(cm, "chartType"))
                        got = join(a, render_chart(a, r.data), join(a, "|", num(a, r.total)))
                    } else {
                        var aggregation = text_of(cm, "aggregation")
                        let (series_value, hs) = get(cm, "series")
                        let series = series_of(a, series_value)
                        if series.len > 0usize && series[0usize].aggregation.len > 0usize { aggregation = series[0usize].aggregation }
                        if aggregation.len == 0usize { aggregation = "count" }
                        let (thresholds_value, ht) = get(cm, "thresholds")
                        let k = p.kpi_from_groups(a, groups[0usize..list.len], aggregation, thresholds_of(a, thresholds_value))
                        var out = join(a, render_cell(a, k.value), join(a, "|", num(a, k.row_count)))
                        if k.has_threshold {
                            out = join(a, out, join3(a, "|", hex_text(a, k.threshold.label), join3(a, ":", k.threshold.color, join(a, ":", num(a, f64(k.threshold.band))))))
                        }
                        got = out
                    }
                } else if str.eq(op, "view") {
                    let (config_value, hc) = get(m, "config")
                    let cm = members_of(config_value)
                    var vc: v.ViewConfig = zero
                    let (filters, has_filters) = get(cm, "filters")
                    if has_filters && !is_null(filters) {
                        vc.has_filter = true
                        vc.filter = node_of(a, filters)
                    }
                    vc.search = text_of(cm, "search")
                    let (sf, h1) = get(cm, "searchFields")
                    vc.search_fields = strings_of(a, sf)
                    let (sorts_value, h2) = get(cm, "sorts")
                    vc.sorts = sorts_of(a, sorts_value)
                    let (gb, h3) = get(cm, "group_by")
                    vc.group_by = strings_of(a, gb)
                    let (vf, h4) = get(cm, "visibleFields")
                    vc.visible_fields = strings_of(a, vf)
                    vc.hide_new_fields = str.eq(text_of(cm, "newFieldPolicy"), "hide")
                    let (summaries, has_summaries) = get(cm, "summaries")
                    if has_summaries {
                        let sm = members_of(summaries)
                        let (specs, se) = mem.alloc[v.SummarySpec](a, sm.len + 1usize)
                        if se == ok {
                            var k = 0usize
                            while k < sm.len {
                                var fname = ""
                                switch sm[k].value {
                                case .String as s:
                                    fname = s
                                default:
                                    fname = ""
                                }
                                specs[k] = v.SummarySpec { field: sm[k].key, function: fname }
                                k += 1usize
                            }
                            vc.summaries = specs[0usize..sm.len]
                        }
                    }
                    let result = v.apply_view(a, reg, rows, vc, fields, &ctx)
                    var out = ""
                    if result.projected {
                        var k = 0usize
                        while k < result.rows.len {
                            var c = 0usize
                            while c < result.rows[k].fields.len {
                                out = join(a, out, join3(a, hex_text(a, result.rows[k].fields[c].name), "=", join(a, render_value(a, result.rows[k].fields[c].value), ",")))
                                c += 1usize
                            }
                            out = join(a, out, ";")
                            k += 1usize
                        }
                    } else {
                        out = render_indices(a, rows, result.rows)
                    }
                    out = join(a, out, "|")
                    var k2 = 0usize
                    while k2 < result.summaries.len {
                        out = join(a, out, join3(a, hex_text(a, result.summaries[k2].field), "=", join(a, render_summary(a, result.summaries[k2].value), ";")))
                        k2 += 1usize
                    }
                    out = join(a, out, "|")
                    k2 = 0usize
                    while k2 < result.groups.len {
                        let vg = result.groups[k2]
                        var shown = "null"
                        if !vg.group.is_none { shown = render_value(a, vg.group.value) }
                        out = join(a, out, join3(a, shown, join3(a, "/", hex_text(a, vg.group.label), ":"), join(a, num(a, f64(vg.group.count)), ":")))
                        var s = 0usize
                        while s < vg.subgroups.len {
                            var sshown = "null"
                            if !vg.subgroups[s].is_none { sshown = render_value(a, vg.subgroups[s].value) }
                            out = join(a, out, join3(a, sshown, join3(a, "/", hex_text(a, vg.subgroups[s].label), ":"), join(a, num(a, f64(vg.subgroups[s].count)), ",")))
                            s += 1usize
                        }
                        var t = 0usize
                        while t < vg.summaries.len {
                            out = join(a, out, join3(a, hex_text(a, vg.summaries[t].field), "=", join(a, render_summary(a, vg.summaries[t].value), ",")))
                            t += 1usize
                        }
                        out = join(a, out, ";")
                        k2 += 1usize
                    }
                    got = out
                } else if str.eq(op, "color") {
                    let (row_value, hr) = get(m, "row")
                    let (color_value, hc) = get(m, "color")
                    let cm = members_of(color_value)
                    var cc: v.ColorConfig = zero
                    cc.mode = text_of(cm, "mode")
                    cc.field = text_of(cm, "field")
                    let (rules_value, has_rules) = get(cm, "rules")
                    let rule_items = items_of(rules_value)
                    let (rules, re) = mem.alloc[v.ColorRule](a, rule_items.len + 1usize)
                    if re == ok {
                        var k = 0usize
                        while k < rule_items.len {
                            let rm = members_of(rule_items[k])
                            let (rf, has_rf) = get(rm, "filter")
                            var rule: v.ColorRule = zero
                            if has_rf && !is_null(rf) {
                                rule.has_filter = true
                                rule.filter = node_of(a, rf)
                            }
                            rule.expr = text_of(rm, "expr")
                            rule.color = text_of(rm, "color")
                            rules[k] = rule
                            k += 1usize
                        }
                        cc.rules = rules[0usize..rule_items.len]
                    }
                    let (color, has_color) = v.row_color(a, reg, row_of(a, row_value), cc, fields, &ctx)
                    if has_color { got = hex_text(a, color) } else { got = "none" }
                } else if str.eq(op, "eval") {
                    // threshold bands over a number
                    let (thresholds_value, ht) = get(m, "thresholds")
                    let (value_value, hv) = get(m, "value")
                    var cellv = p.no_cell()
                    switch value_value {
                    case .Number as n:
                        let (value, e) = json.number_f64(n)
                        cellv = p.cell(value)
                    default:
                        cellv = p.no_cell()
                    }
                    let (band, has_band) = p.evaluate_thresholds(a, cellv, thresholds_of(a, thresholds_value))
                    if has_band { got = join3(a, hex_text(a, band.label), join3(a, ":", band.color, ":"), join(a, hex_text(a, band.icon), join(a, ":", num(a, f64(band.band))))) } else { got = "none" }
                } else {
                    got = "unknown op"
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
    //__VECTOR_CALLS__
    try io.print("algo query ok")
    ret ok
}
