// `e.algo.page` and `e.algo.batch` against appdor's own `src/grid-ops/{records-engine,bulk,undo-redo}.js`,
// `src/grid/virtual-rows.js` and `src/performance/limits.js`: scripts/page_reference.mjs runs appdor's engine over
// key-minting scripts, keyset paging walks, table duplications, row-window plans, limits, batch runs, bulk
// mutations and undo/redo scripts and writes `{"op": ..., ...inputs, "e": outcome}` lines; the fixture rebuilds the
// inputs and must render the same outcome.
use e.algo.batch as b
use e.algo.formula as f
use e.algo.page as p
use e.algo.view as view
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

fn flag(x: bool) -> str {
    if x { ret "1" }
    ret "0"
}

fn render_value(a: *mem.Arena, x: f.Value) -> str {
    if x.kind == .Blank { ret "_" }
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
        out = join(a, out, render_value(a, x.items[i]))
        i += 1usize
    }
    ret join(a, out, "]")
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

fn text_of(x: json.Value) -> str {
    switch x {
    case .String as s:
        ret s
    default:
        ret ""
    }
}

fn text_member(members: []const json.Member, key: str) -> str {
    let (x, found) = get(members, key)
    if !found { ret "" }
    ret text_of(x)
}

fn number_of(x: json.Value, fallback: f64) -> f64 {
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret value
    default:
        ret fallback
    }
}

fn bool_of(members: []const json.Member, key: str) -> bool {
    let (x, found) = get(members, key)
    if !found { ret false }
    switch x {
    case .Bool as v:
        ret v
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
    case .Bool as v:
        ret f.boolean(v)
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
        ret f.record(f.zero_items())
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

fn page_rows_of(a: *mem.Arena, x: json.Value) -> []const p.Row {
    let items = items_of(x)
    var none: []const p.Row = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[p.Row](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        out[i] = p.Row { fields: fields_of(a, items[i]) }
        i += 1usize
    }
    ret out
}

fn view_rows_of(a: *mem.Arena, x: json.Value) -> []const view.Row {
    let items = items_of(x)
    var none: []const view.Row = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[view.Row](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        out[i] = view.Row { fields: fields_of(a, items[i]) }
        i += 1usize
    }
    ret out
}

fn values_of(a: *mem.Arena, x: json.Value) -> []const f.Value {
    let items = items_of(x)
    if items.len == 0usize { ret f.zero_items() }
    let (out, e) = mem.alloc[f.Value](a, items.len)
    if e != ok { ret f.zero_items() }
    var i = 0usize
    while i < items.len {
        out[i] = value_of(a, items[i])
        i += 1usize
    }
    ret out
}

fn strings_of(a: *mem.Arena, x: json.Value) -> []const str {
    let items = items_of(x)
    var none: []const str = zero
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

fn render_fields(a: *mem.Arena, fields: []const f.Field) -> str {
    var out = ""
    var i = 0usize
    while i < fields.len {
        out = join(a, out, join3(a, hex_text(a, fields[i].name), "=", join(a, render_value(a, fields[i].value), ",")))
        i += 1usize
    }
    ret out
}

// --- batch and bulk callbacks ------------------------------------------------------------------------------------

// What the host's apply does, as the vector describes it: ids that fail with a reason, ids that throw.
type Behavior = struct {
    fail_ids: []const f.Field,
    throw_ids: []const str,
    chunk_throw: []const f64,
    void_chunks: bool,
    cancel_after: f64,
    has_cancel: bool,
    chunk_no: f64,
    deny: []const f.Field,
}

fn lookup_text(a: *mem.Arena, list: []const f.Field, id: f.Value) -> (str, bool) {
    let key = view.js_string(a, id)
    var i = 0usize
    while i < list.len {
        if str.eq(list[i].name, key) {
            if list[i].value.kind == .Text { ret (list[i].value.s, true) }
            ret ("", true)
        }
        i += 1usize
    }
    ret ("", false)
}

fn state_arena() -> *mem.Arena {
    // the callbacks need an arena for key text; they read the one the run installed
    ret g_arena
}

var g_arena: *mem.Arena = zero

fn batch_apply(state: *void, id: f.Value) -> b.Outcome {
    let behavior = mem.cast[*Behavior](state)
    let a = g_arena
    let key = view.js_string(a, id)
    var i = 0usize
    while i < behavior.throw_ids.len {
        if str.eq(behavior.throw_ids[i], key) { ret b.failure(join(a, "boom ", key)) }
        i += 1usize
    }
    let (reason, found) = lookup_text(a, behavior.fail_ids, id)
    if found { ret b.failure(reason) }
    ret b.success()
}

fn authorize_fn(state: *void, id: f.Value) -> b.Verdict {
    let behavior = mem.cast[*Behavior](state)
    let (reason, found) = lookup_text(g_arena, behavior.deny, id)
    if found { ret b.Verdict { allowed: false, reason: reason } }
    ret b.Verdict { allowed: true, reason: "" }
}

fn bulk_apply(state: *void, ids: []const f.Value, patch: []const f.Field, correlation: str) -> b.Applied {
    let behavior = mem.cast[*Behavior](state)
    let a = g_arena
    behavior.chunk_no += 1.0f64
    var i = 0usize
    while i < behavior.chunk_throw.len {
        if behavior.chunk_throw[i] == behavior.chunk_no { ret b.Applied { threw: true, reason: "boom", all_ok: false, results: zero_outcomes() } }
        i += 1usize
    }
    if behavior.void_chunks { ret b.Applied { threw: false, reason: "", all_ok: true, results: zero_outcomes() } }
    let (out, e) = mem.alloc[b.IdOutcome](a, ids.len + 1usize)
    if e != ok { ret b.Applied { threw: true, reason: "oom", all_ok: false, results: zero_outcomes() } }
    var k = 0usize
    while k < ids.len {
        let (reason, found) = lookup_text(a, behavior.fail_ids, ids[k])
        if found {
            out[k] = b.IdOutcome { id: ids[k], good: false, reason: reason }
        } else {
            out[k] = b.IdOutcome { id: ids[k], good: true, reason: "" }
        }
        k += 1usize
    }
    ret b.Applied { threw: false, reason: "", all_ok: false, results: out[0usize..ids.len] }
}

fn zero_outcomes() -> []const b.IdOutcome {
    var none: []const b.IdOutcome = zero
    ret none
}

fn cancel_fn(state: *void) -> bool {
    let behavior = mem.cast[*Behavior](state)
    ret behavior.has_cancel && behavior.chunk_no >= behavior.cancel_after
}

fn behavior_of(a: *mem.Arena, m: []const json.Member) -> Behavior {
    var behavior: Behavior = zero
    let (fail, has_fail) = get(m, "fail")
    if has_fail { behavior.fail_ids = fields_of(a, fail) }
    let (throws, has_throws) = get(m, "throwIds")
    if has_throws { behavior.throw_ids = strings_of(a, throws) }
    let (chunks, has_chunks) = get(m, "throwChunks")
    if has_chunks {
        let list = items_of(chunks)
        let (nums, ne) = mem.alloc[f64](a, list.len + 1usize)
        if ne == ok {
            var i = 0usize
            while i < list.len {
                nums[i] = number_of(list[i], 0.0f64)
                i += 1usize
            }
            behavior.chunk_throw = nums[0usize..list.len]
        }
    }
    behavior.void_chunks = bool_of(m, "voidChunks")
    let (cancel, has_cancel) = get(m, "cancelAfter")
    if has_cancel && !is_null(cancel) {
        behavior.has_cancel = true
        behavior.cancel_after = number_of(cancel, 0.0f64)
    }
    let (deny, has_deny) = get(m, "deny")
    if has_deny { behavior.deny = fields_of(a, deny) }
    ret behavior
}

fn render_denied(a: *mem.Arena, list: []const b.Denied) -> str {
    var out = ""
    var i = 0usize
    while i < list.len {
        out = join(a, out, join3(a, render_value(a, list[i].id), ":", join(a, hex_text(a, list[i].reason), ";")))
        i += 1usize
    }
    ret out
}

fn render_plan(a: *mem.Arena, plan: b.BulkPlan) -> str {
    var out = join(a, flag(plan.valid), join(a, "|", hex_text(a, plan.reason)))
    out = join(a, out, join(a, "|", render_denied(a, plan.denied)))
    if !plan.valid { ret out }
    out = join(a, out, join3(a, "|", hex_text(a, plan.correlation_id), "|"))
    out = join(a, out, render_fields(a, plan.patch))
    out = join(a, out, join3(a, "|", num(a, f64(plan.total)), "|"))
    out = join(a, out, join(a, render_denied(a, plan.skipped), "|"))
    var c = 0usize
    while c < plan.chunks.len {
        var k = 0usize
        while k < plan.chunks[c].len {
            out = join(a, out, join(a, render_value(a, plan.chunks[c][k]), ","))
            k += 1usize
        }
        out = join(a, out, "/")
        c += 1usize
    }
    ret join(a, out, join(a, "|", plan.mode))
}

fn render_outcomes(a: *mem.Arena, list: []const b.IdOutcome) -> str {
    var out = ""
    var i = 0usize
    while i < list.len {
        out = join(a, out, join3(a, render_value(a, list[i].id), ":", join3(a, flag(list[i].good), ":", join(a, hex_text(a, list[i].reason), ";"))))
        i += 1usize
    }
    ret out
}

fn render_writes(a: *mem.Arena, list: []const b.Write) -> str {
    var out = ""
    var i = 0usize
    while i < list.len {
        out = join(a, out, join3(a, render_value(a, list[i].record_id), ".", join(a, hex_text(a, list[i].field), "=")))
        out = join(a, out, render_value(a, list[i].value))
        if list[i].has_expected { out = join(a, out, join(a, "~", render_value(a, list[i].expected))) }
        out = join(a, out, ";")
        i += 1usize
    }
    ret out
}

fn render_step(a: *mem.Arena, s: b.Step) -> str {
    if !s.valid { ret join(a, "no:", s.reason) }
    var label = "-"
    if s.has_label { label = hex_text(a, s.label) }
    ret join3(a, "ok:", label, join(a, ":", render_writes(a, s.writes)))
}

fn changes_of(a: *mem.Arena, x: json.Value) -> []const b.Change {
    let items = items_of(x)
    var none: []const b.Change = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[b.Change](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let parts = items_of(items[i])
        var c: b.Change = zero
        c.record_id = f.blank()
        c.before = f.blank()
        c.after = f.blank()
        if parts.len >= 4usize {
            c.record_id = value_of(a, parts[0usize])
            c.field = text_of(parts[1usize])
            c.before = value_of(a, parts[2usize])
            c.after = value_of(a, parts[3usize])
        }
        out[i] = c
        i += 1usize
    }
    ret out
}

fn acks_of(a: *mem.Arena, x: json.Value) -> []const b.Ack {
    let items = items_of(x)
    var none: []const b.Ack = zero
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[b.Ack](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let parts = items_of(items[i])
        var k: b.Ack = zero
        k.record_id = f.blank()
        if parts.len >= 2usize {
            k.record_id = value_of(a, parts[0usize])
            k.field = text_of(parts[1usize])
        }
        out[i] = k
        i += 1usize
    }
    ret out
}

fn run(a: *mem.Arena, body: str) -> u8 {
    g_arena = a
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
                want = text_member(m, "e")
                got = evaluate(a, m)
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

// A requested chunk size: zero is the default, a negative one is the smallest chunk (`Math.max(1, size)`).
fn chunk_of(x: f64) -> usize {
    if x < 0.0f64 { ret 1usize }
    ret usize(x)
}

fn evaluate(a: *mem.Arena, m: []const json.Member) -> str {
    let op = text_member(m, "op")
    if str.eq(op, "prefix") { ret p.prefix_for(a, text_member(m, "name")) }
    if str.eq(op, "parsekey") {
        let (prefix, n, good) = p.parse_record_key(text_member(m, "key"))
        if !good { ret "null" }
        ret join3(a, prefix, ":", num(a, n))
    }
    if str.eq(op, "keys") {
        let (initial, has_initial) = get(m, "initial")
        var minter = p.new_minter(a, 64usize)
        let init_fields = fields_of(a, initial)
        var k = 0usize
        while k < init_fields.len {
            p.reserve(&minter, init_fields[k].name, init_fields[k].value.n)
            k += 1usize
        }
        let (script, has_script) = get(m, "script")
        let steps = items_of(script)
        var out = ""
        k = 0usize
        while k < steps.len {
            let parts = items_of(steps[k])
            let kind = text_of(parts[0usize])
            if str.eq(kind, "mint") {
                out = join(a, out, p.mint(a, &minter, text_of(parts[1usize]), text_of(parts[2usize])))
            } else if str.eq(kind, "many") {
                var c = 0usize
                let count = usize(number_of(parts[3usize], 0.0f64))
                while c < count {
                    if c > 0usize { out = join(a, out, ",") }
                    out = join(a, out, p.mint(a, &minter, text_of(parts[1usize]), text_of(parts[2usize])))
                    c += 1usize
                }
            } else if str.eq(kind, "reserve") {
                p.reserve(&minter, text_of(parts[1usize]), number_of(parts[2usize], 0.0f64))
                out = join(a, out, "r")
            } else if str.eq(kind, "counter") {
                out = join(a, out, num(a, p.counter_of(&minter, text_of(parts[1usize]))))
            } else {
                var c = 0usize
                while c < minter.count {
                    out = join(a, out, join3(a, minter.counters[c].table, "=", join(a, num(a, minter.counters[c].value), ",")))
                    c += 1usize
                }
            }
            out = join(a, out, ";")
            k += 1usize
        }
        ret out
    }
    if str.eq(op, "page") {
        let (rows_value, hr) = get(m, "rows")
        let rows = page_rows_of(a, rows_value)
        let (sort_value, hs) = get(m, "sort")
        let sort_items = items_of(sort_value)
        let (keys, ke) = mem.alloc[p.SortKey](a, sort_items.len + 1usize)
        var kn = 0usize
        if ke == ok {
            var k = 0usize
            while k < sort_items.len {
                let sm = members_of(sort_items[k])
                keys[kn] = p.SortKey { field: text_member(sm, "field"), descending: str.eq(text_member(sm, "dir"), "desc") }
                kn += 1usize
                k += 1usize
            }
        }
        let (limit_value, has_limit) = get(m, "limit")
        var limit = 50.0f64
        if has_limit { limit = number_of(limit_value, 0.0f64) }
        let (cursor_value, has_cursor) = get(m, "cursor")
        var cursor = ""
        var use_cursor = false
        switch cursor_value {
        case .String as s:
            cursor = s
            use_cursor = true
        default:
            use_cursor = false
        }
        let page = p.paginate(a, rows, keys[0usize..kn], limit, cursor, use_cursor)
        if !page.valid { ret join(a, "no:", page.reason) }
        var out = ""
        var k = 0usize
        while k < page.positions.len {
            let tag = view.value_at(view.Row { fields: rows[page.positions[k]].fields }, "~idx")
            var shown = "?"
            if tag.kind == .Text && tag.s.len > 1usize { shown = tag.s[1usize..tag.s.len] }
            out = join(a, out, join(a, shown, ","))
            k += 1usize
        }
        var next = "-"
        if page.has_next_cursor { next = page.next_cursor }
        ret join3(a, out, "|", join3(a, next, "|", flag(page.has_more)))
    }
    if str.eq(op, "dup") {
        let (table_value, ht) = get(m, "table")
        let tm = members_of(table_value)
        let (cols_value, hc) = get(tm, "columns")
        let col_items = items_of(cols_value)
        let (cols, ce) = mem.alloc[p.Column](a, col_items.len + 1usize)
        if ce != ok { ret "oom" }
        var k = 0usize
        while k < col_items.len {
            let cm = members_of(col_items[k])
            let (config, has_config) = get(cm, "config")
            let (linked, has_linked) = get(members_of(config), "linkedTableId")
            var linked_text = ""
            if has_linked && !is_null(linked) { linked_text = view.js_string(a, value_of(a, linked)) }
            cols[k] = p.Column { id: text_member(cm, "id"), name: text_member(cm, "name"), type_name: text_member(cm, "type"), linked_table: linked_text, has_linked_table: has_linked && !is_null(linked) }
            k += 1usize
        }
        let table = p.Table { id: text_member(tm, "id"), name: text_member(tm, "name"), columns: cols[0usize..col_items.len] }
        let (rows_value, hr) = get(m, "rows")
        var minter = p.new_minter(a, 8usize)
        let d = p.duplicate_table(a, table, page_rows_of(a, rows_value), bool_of(m, "withRecords"), text_member(m, "newId"), text_member(m, "newName"), &minter, true)
        var out = join3(a, hex_text(a, d.table.id), "|", join(a, hex_text(a, d.table.name), "|"))
        k = 0usize
        while k < d.table.columns.len {
            let c = d.table.columns[k]
            var link = "-"
            if c.has_linked_table { link = hex_text(a, c.linked_table) }
            out = join(a, out, join3(a, hex_text(a, c.id), ":", join3(a, hex_text(a, c.name), ":", join3(a, c.type_name, ":", join(a, link, ";")))))
            k += 1usize
        }
        out = join(a, out, "|")
        k = 0usize
        while k < d.rows.len {
            out = join(a, out, join(a, render_fields(a, d.rows[k].fields), ";"))
            k += 1usize
        }
        out = join(a, out, "|")
        k = 0usize
        while k < d.id_from.len {
            out = join(a, out, join3(a, hex_text(a, d.id_from[k]), ">", join(a, hex_text(a, d.id_to[k]), ";")))
            k += 1usize
        }
        ret join(a, out, join(a, "|", num(a, p.counter_of(&minter, d.table.id))))
    }
    if str.eq(op, "rows") {
        let (total, h1) = get(m, "total")
        let (scroll, h2) = get(m, "scrollTop")
        let (viewport, h3) = get(m, "viewportHeight")
        let (height, h4) = get(m, "rowHeight")
        let (overscan, h5) = get(m, "overscan")
        var over = -1.0f64
        if h5 { over = number_of(overscan, 3.0f64) }
        let r = p.plan_rows(number_of(total, 0.0f64), number_of(scroll, 0.0f64), number_of(viewport, 0.0f64), number_of(height, 0.0f64), over)
        ret join3(a, num(a, r.start), ",", join3(a, num(a, r.end), ",", join3(a, num(a, r.top_spacer), ",", join3(a, num(a, r.bottom_spacer), ",", num(a, r.aria_row_count)))))
    }
    if str.eq(op, "load") {
        let (n, h1) = get(m, "n")
        let l = p.load_plan(a, number_of(n, 0.0f64), text_member(m, "locale"))
        var notice = "-"
        if l.has_notice { notice = hex_text(a, l.notice) }
        ret join3(a, num(a, l.loaded), "|", join3(a, flag(l.truncated), "|", join3(a, num(a, l.requests), "|", notice)))
    }
    if str.eq(op, "percentile") {
        let (values_value, hv) = get(m, "values")
        let list = items_of(values_value)
        let (nums, ne) = mem.alloc[f64](a, list.len + 1usize)
        if ne != ok { ret "oom" }
        var k = 0usize
        while k < list.len {
            nums[k] = number_of(list[k], f.nan())
            k += 1usize
        }
        let (p_value, hp) = get(m, "p")
        let (result, good) = p.percentile(a, nums[0usize..list.len], number_of(p_value, 0.0f64))
        if !good { ret "nan" }
        ret num(a, result)
    }
    if str.eq(op, "budget") {
        let (ms, hm) = get(m, "ms")
        let r = p.within_budget(a, text_member(m, "name"), number_of(ms, 0.0f64))
        ret join(a, flag(r.within), join(a, "|", hex_text(a, r.message)))
    }
    if str.eq(op, "batch") {
        let (ids_value, hi) = get(m, "ids")
        let ids = values_of(a, ids_value)
        var behavior = behavior_of(a, m)
        let (chunk, hc) = get(m, "chunkSize")
        let (start_index, hs) = get(m, "startIndex")
        var ledger: b.Ledger = zero
        let (ledger_value, has_ledger) = get(m, "ledger")
        if has_ledger {
            let lm = members_of(ledger_value)
            let (succeeded, hs2) = get(lm, "succeeded")
            ledger.succeeded = values_of(a, succeeded)
            let (failed, hf) = get(lm, "failed")
            let items = items_of(failed)
            let (list, le) = mem.alloc[b.Failed](a, items.len + 1usize)
            if le == ok {
                var k = 0usize
                while k < items.len {
                    let fm = members_of(items[k])
                    let (rid, hr) = get(fm, "recordId")
                    list[k] = b.Failed { record_id: value_of(a, rid), reason: text_member(fm, "error") }
                    k += 1usize
                }
                ledger.failed = list[0usize..items.len]
            }
        }
        let r = b.run_batch(a, ids, batch_apply, mem.cast[*void](&behavior), usize(number_of(chunk, 0.0f64)), usize(number_of(start_index, 0.0f64)), ledger)
        var out = join3(a, num(a, f64(r.processed)), "|", join3(a, num(a, f64(r.total)), "|", join3(a, flag(r.done), "|", "")))
        if r.has_next_index { out = join(a, out, num(a, f64(r.next_index))) } else { out = join(a, out, "-") }
        out = join(a, out, join3(a, "|", num(a, f64(r.succeeded)), join3(a, ",", num(a, f64(r.failed)), "|")))
        var k = 0usize
        while k < r.ledger.succeeded.len {
            out = join(a, out, join(a, render_value(a, r.ledger.succeeded[k]), ","))
            k += 1usize
        }
        out = join(a, out, "|")
        k = 0usize
        while k < r.ledger.failed.len {
            out = join(a, out, join3(a, render_value(a, r.ledger.failed[k].record_id), ":", join(a, hex_text(a, r.ledger.failed[k].reason), ";")))
            k += 1usize
        }
        ret join(a, out, join(a, "|", b.describe_batch(a, r.total, r.succeeded, r.failed)))
    }
    if str.eq(op, "bulk") {
        var behavior = behavior_of(a, m)
        let (targets_value, ht) = get(m, "targets")
        let (patch_value, hp) = get(m, "patch")
        let (chunk, hc) = get(m, "chunkSize")
        let (threshold, hth) = get(m, "syncThreshold")
        var has_threshold = false
        if hth && !is_null(threshold) { has_threshold = true }
        var skip = false
        if str.eq(text_member(m, "onDenied"), "skip") { skip = true }
        let (deny_value, hd) = get(m, "deny")
        var catalog: []const b.Message = zero
        let plan = b.plan_bulk_mutation(a, catalog, values_of(a, targets_value), fields_of(a, patch_value), authorize_fn, hd, mem.cast[*void](&behavior), skip, chunk_of(number_of(chunk, 0.0f64)), usize(number_of(threshold, 0.0f64)), has_threshold, text_member(m, "correlationId"))
        let (run_it, hrun) = get(m, "run")
        if !hrun || is_null(run_it) { ret render_plan(a, plan) }
        let r = b.run_bulk_mutation(a, plan, bulk_apply, mem.cast[*void](&behavior), cancel_fn, behavior.has_cancel)
        var out = render_plan(a, plan)
        out = join(a, out, join3(a, "#", flag(r.valid), join3(a, ":", hex_text(a, r.reason), join3(a, ":", flag(r.cancelled), ":"))))
        out = join(a, out, join3(a, num(a, f64(r.total)), ",", join3(a, num(a, f64(r.applied)), ",", num(a, f64(r.failed)))))
        out = join(a, out, join(a, "#", render_outcomes(a, r.outcomes)))
        out = join(a, out, "#")
        var k = 0usize
        while k < r.progress.len {
            let pr = r.progress[k]
            out = join(a, out, join3(a, num(a, f64(pr.done)), "/", join3(a, num(a, f64(pr.total)), "/", join3(a, num(a, f64(pr.applied)), "/", join3(a, num(a, f64(pr.failed)), "/", join(a, num(a, pr.percent), ";"))))))
            k += 1usize
        }
        let summary = b.summarize_bulk_outcome(a, catalog, r)
        out = join(a, out, join3(a, "#", flag(summary.valid), join3(a, ":", hex_text(a, summary.headline), ":")))
        k = 0usize
        while k < summary.by_reason.len {
            out = join(a, out, join3(a, hex_text(a, summary.by_reason[k].reason), "=", join(a, num(a, f64(summary.by_reason[k].count)), ",")))
            k += 1usize
        }
        ret out
    }
    if str.eq(op, "undo") {
        let (depth, hd) = get(m, "depth")
        var store = b.new_undo_store(a, usize(number_of(depth, 0.0f64)), 32usize, 64usize)
        b.set_scope(&store, "acct")
        let (script, hs) = get(m, "script")
        let steps = items_of(script)
        var out = ""
        var tokens: [32]usize = zero
        var token_count = 0usize
        var k = 0usize
        while k < steps.len {
            let parts = items_of(steps[k])
            let kind = text_of(parts[0usize])
            if str.eq(kind, "scope") {
                b.set_scope(&store, text_of(parts[1usize]))
                out = join(a, out, "s")
            } else if str.eq(kind, "push") {
                var label = ""
                var has_label = false
                if parts.len > 4usize {
                    switch parts[4usize] {
                    case .String as s:
                        label = s
                        has_label = true
                    default:
                        has_label = false
                    }
                }
                let depth_after = b.undo_push(&store, text_of(parts[1usize]), text_of(parts[2usize]), changes_of(a, parts[3usize]), label, has_label)
                out = join(a, out, num(a, f64(depth_after)))
            } else if str.eq(kind, "undo") {
                out = join(a, out, render_step(a, b.undo(&store, text_of(parts[1usize]), text_of(parts[2usize]))))
            } else if str.eq(kind, "redo") {
                out = join(a, out, render_step(a, b.redo(&store, text_of(parts[1usize]), text_of(parts[2usize]))))
            } else if str.eq(kind, "state") {
                let st = b.undo_state(&store, text_of(parts[1usize]), text_of(parts[2usize]))
                out = join(a, out, join3(a, flag(st.can_undo), flag(st.can_redo), num(a, f64(st.undo_depth))))
            } else if str.eq(kind, "prepareUndo") || str.eq(kind, "prepareRedo") {
                let step = b.prepare(&store, text_of(parts[1usize]), text_of(parts[2usize]), str.eq(kind, "prepareRedo"))
                out = join(a, out, render_step(a, step))
                if step.has_token && token_count < 32usize {
                    tokens[token_count] = step.token
                    token_count += 1usize
                }
            } else if str.eq(kind, "commit") {
                let at = usize(number_of(parts[1usize], 0.0f64))
                var applied = 0usize
                if at < token_count { applied = b.commit(&store, tokens[at], acks_of(a, parts[2usize])) }
                out = join(a, out, num(a, f64(applied)))
            } else if str.eq(kind, "bulkChanges") {
                let rows = view_rows_of(a, parts[1usize])
                let list = b.bulk_changes(a, rows, values_of(a, parts[2usize]), text_of(parts[3usize]), value_of(a, parts[4usize]))
                var c = 0usize
                while c < list.len {
                    out = join(a, out, join3(a, render_value(a, list[c].record_id), ":", join3(a, render_value(a, list[c].before), ">", join(a, render_value(a, list[c].after), ","))))
                    c += 1usize
                }
            }
            out = join(a, out, ";")
            k += 1usize
        }
        ret out
    }
    ret "unknown op"
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("algo page batch ok")
    ret ok
}
