// `e.algo.trigger` against appdor's own `src/workflow/schedule.js`: scripts/trigger_reference.mjs runs appdor's cron
// parser, zone arithmetic, schedule normalization, missed-fire policies, fire plans, overlap decisions, due-date
// stamps, duration-in-state and scheduled scan over random inputs (TZ=UTC) and writes `{"op": ..., ...inputs,
// "e": outcome}` lines; the fixture rebuilds the inputs and must render the same outcome.
use e.algo.formula as f
use e.algo.formula.library as library
use e.algo.trigger as t
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


// --- fixture-specific model builders -------------------------------------------------------------------------------

fn flag(x: bool) -> str {
    if x { ret "1" }
    ret "0"
}

fn ms_text(a: *mem.Arena, x: f64) -> str { ret f.number_text(a, x) }

// A value as JavaScript's `String(value)`, or absent for null and missing.
fn field_of(a: *mem.Arena, m: []const json.Member, key: str) -> t.Field {
    let (x, found) = get(m, key)
    if !found { ret t.no_field() }
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret t.Field { has: true, text: f.number_text(a, value) }
    case .String as s:
        ret t.Field { has: true, text: s }
    default:
        ret t.no_field()
    }
}

fn simple_of(a: *mem.Arena, m: []const json.Member, key: str) -> t.Simple {
    let (x, found) = get(m, key)
    if !found || is_null(x) { ret t.no_simple() }
    switch x {
    case .Object as sm:
        ret t.Simple {
            present: true, minute: field_of(a, sm, "minute"), hour: field_of(a, sm, "hour"), day: field_of(a, sm, "day"),
            day_of_month: field_of(a, sm, "dayOfMonth"),
        }
    default:
        ret t.no_simple()
    }
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn number_or_nan(m: []const json.Member, key: str) -> f64 { ret number_of(m, key, nan()) }

fn spec_of(a: *mem.Arena, x: json.Value) -> t.Spec {
    let m = members_of(x)
    var s = t.no_spec()
    s.timezone = text_of(m, "timezone")
    s.on_missed = text_of(m, "onMissed")
    let (cron, has_cron) = get(m, "cron")
    if has_cron && !is_null(cron) {
        s.has_cron = true
        s.cron = field_of(a, m, "cron").text
    }
    let (every, has_every) = get(m, "everyMs")
    if has_every && !is_null(every) {
        s.has_every = true
        s.every_ms = number_or_nan(m, "everyMs")
    }
    let (minutes, has_minutes) = get(m, "intervalMinutes")
    if has_minutes && !is_null(minutes) {
        s.has_minutes = true
        s.minutes = number_or_nan(m, "intervalMinutes")
    }
    s.daily = simple_of(a, m, "daily")
    s.weekly = simple_of(a, m, "weekly")
    s.monthly = simple_of(a, m, "monthly")
    ret s
}

fn stored_of(a: *mem.Arena, x: json.Value) -> t.Stored {
    let m = members_of(x)
    let (cron, has_cron) = get(m, "cron")
    ret t.Stored {
        kind: text_of(m, "type"), cron: text_of(m, "cron"), has_cron: has_cron && !is_null(cron),
        every_ms: number_or_nan(m, "everyMs"), has_every: has_number(m, "everyMs"), timezone: text_of(m, "timezone"),
        on_missed: text_of(m, "onMissed"), at_hour: field_of(a, m, "atHour"), at_minute: field_of(a, m, "atMinute"),
    }
}

// --- rendering ------------------------------------------------------------------------------------------------------

fn bits_list(a: *mem.Arena, bits: u64, low: i64, high: i64) -> str {
    var out = ""
    var first = true
    var bit = low
    while bit <= high {
        if (bits >> u64(bit)) & 1u64 == 1u64 {
            if !first { out = join(a, out, ",") }
            first = false
            out = join(a, out, ms_text(a, f64(bit)))
        }
        bit += 1i64
    }
    ret out
}

fn render_cron(a: *mem.Arena, c: t.Cron) -> str {
    var out = join3(a, "m=", bits_list(a, c.minute, 0i64, 59i64), ";h=")
    out = join3(a, out, bits_list(a, u64(c.hour), 0i64, 23i64), ";d=")
    out = join3(a, out, bits_list(a, u64(c.dom), 1i64, 31i64), ";mo=")
    out = join3(a, out, bits_list(a, u64(c.month), 1i64, 12i64), ";w=")
    out = join3(a, out, bits_list(a, u64(c.dow), 0i64, 6i64), ";dw=")
    out = join3(a, out, flag(c.dom_wild), ";ww=")
    ret join(a, out, flag(c.dow_wild))
}

fn render_schedule(a: *mem.Arena, s: t.Schedule) -> str {
    if s.has_error { ret join(a, "ERR:", s.reason) }
    if s.kind == t.KIND_INTERVAL {
        ret join3(a, join3(a, "interval|", ms_text(a, s.every_ms), "|"), s.timezone, join(a, "|", s.on_missed))
    }
    ret join3(a, join3(a, "cron|", hex_text(a, s.cron), "|"), s.timezone, join(a, "|", s.on_missed))
}

fn render_list(a: *mem.Arena, items: []const f64) -> str {
    var out = ""
    var i = 0usize
    while i < items.len {
        if i > 0usize { out = join(a, out, ",") }
        out = join(a, out, ms_text(a, items[i]))
        i += 1usize
    }
    ret out
}

fn render_plan(a: *mem.Arena, p: t.Plan) -> str {
    var out = join3(a, p.policy, "|", flag(p.due))
    out = join3(a, out, "|", render_list(a, p.fire_at))
    out = join3(a, out, "|", ms_text(a, f64(p.missed)))
    out = join3(a, out, "|", ms_text(a, f64(p.skipped)))
    out = join3(a, out, "|", flag(p.capped))
    out = join(a, out, "|")
    if p.has_spent { ret join(a, out, ms_text(a, p.spent_at)) }
    ret join(a, out, "_")
}

fn render_decision(a: *mem.Arena, d: t.Decision) -> str {
    var out = join3(a, flag(d.fire), "|", d.reason)
    var skipped = "-"
    if d.has_skipped {
        skipped = "_"
        if d.skipped_fire_at == d.skipped_fire_at { skipped = ms_text(a, d.skipped_fire_at) }
    }
    var stale = "-"
    if d.has_stale { stale = ms_text(a, d.stale_for_ms) }
    var active = "-"
    if d.has_skipped {
        active = "_"
        if d.has_active { active = ms_text(a, d.active_since_ms) }
    }
    out = join3(a, out, "|", skipped)
    out = join3(a, out, "|", stale)
    ret join3(a, out, "|", active)
}

fn rows_with_filter(a: *mem.Arena, m: []const json.Member) -> []const v.Row { ret rows_of(a, member_of(m, "records")) }

fn member_of(m: []const json.Member, key: str) -> json.Value {
    let (x, found) = get(m, key)
    ret x
}

fn evaluate(a: *mem.Arena, m: []const json.Member, reg: *f.Registry, clock: *const t.Clock) -> str {
    let op = text_of(m, "op")
    if str.eq(op, "parse") {
        let (c, good) = t.parse_cron(text_of(m, "expr"))
        if !good { ret "null" }
        ret render_cron(a, c)
    }
    if str.eq(op, "wall") {
        let w = t.wall_clock(clock, number_of(m, "ms", 0.0f64), text_of(m, "tz"))
        var out = join3(a, ms_text(a, f64(w.year)), ",", ms_text(a, f64(w.month)))
        out = join3(a, out, ",", ms_text(a, f64(w.day)))
        out = join3(a, out, ",", ms_text(a, f64(w.hour)))
        out = join3(a, out, ",", ms_text(a, f64(w.minute)))
        out = join3(a, out, ",", ms_text(a, f64(w.second)))
        ret join3(a, out, ",", ms_text(a, f64(w.weekday)))
    }
    if str.eq(op, "offset") { ret ms_text(a, f64(t.zone_offset_ms(clock, number_of(m, "ms", 0.0f64), text_of(m, "tz")))) }
    if str.eq(op, "instants") {
        let r = t.wall_to_instants(clock, i64(number_of(m, "y", 0.0f64)), i64(number_of(m, "mo", 0.0f64)), i64(number_of(m, "d", 0.0f64)), i64(number_of(m, "h", 0.0f64)), i64(number_of(m, "mi", 0.0f64)), text_of(m, "tz"))
        var out = ""
        var i = 0usize
        while i < r.count {
            if i > 0usize { out = join(a, out, ",") }
            out = join(a, out, ms_text(a, f64(r.at[i])))
            i += 1usize
        }
        ret out
    }
    if str.eq(op, "nextcron") {
        let (c, good) = t.parse_cron(text_of(m, "expr"))
        if !good { ret "null" }
        let (at, found) = t.next_cron_fire(clock, c, number_of(m, "from", 0.0f64), text_of(m, "tz"))
        if !found { ret "null" }
        ret ms_text(a, at)
    }
    if str.eq(op, "normalize") { ret render_schedule(a, t.normalize_schedule(a, clock, spec_of(a, member_of(m, "spec")))) }
    if str.eq(op, "runtime") {
        let (s, known) = t.runtime_schedule(a, clock, stored_of(a, member_of(m, "stored")))
        if !known { ret "null" }
        ret render_schedule(a, s)
    }
    if str.eq(op, "nextfires") {
        let s = t.normalize_schedule(a, clock, spec_of(a, member_of(m, "spec")))
        if s.has_error { ret render_schedule(a, s) }
        ret render_list(a, t.next_fires(a, clock, s, number_of(m, "from", 0.0f64), i64(number_of(m, "n", 0.0f64)), number_of(m, "anchor", 0.0f64)))
    }
    if str.eq(op, "missed") || str.eq(op, "catchup") {
        let s = t.normalize_schedule(a, clock, spec_of(a, member_of(m, "spec")))
        if s.has_error { ret render_schedule(a, s) }
        let last = number_of(m, "last", nan())
        let now_ms = number_of(m, "now", nan())
        let anchor = number_of(m, "anchor", 0.0f64)
        if str.eq(op, "missed") { ret render_plan(a, t.missed_fires(a, clock, s, last, now_ms, anchor)) }
        let r = t.catch_up(a, clock, s, last, now_ms, anchor)
        if !r.due { ret "0" }
        var out = join3(a, "1|", ms_text(a, r.fire_at), "|")
        out = join3(a, out, ms_text(a, f64(r.missed)), "|")
        out = join3(a, out, flag(r.catch_up), "|")
        ret join(a, out, flag(r.capped))
    }
    if str.eq(op, "plan") {
        let r = t.schedule_fire_plan(a, clock, stored_of(a, member_of(m, "stored")), number_of(m, "last", nan()), number_of(m, "now", nan()), number_of(m, "anchor", nan()))
        if !r.present { ret "null" }
        ret render_plan(a, r.plan)
    }
    if str.eq(op, "due") {
        ret flag(t.is_due(a, clock, stored_of(a, member_of(m, "stored")), number_of(m, "now", nan()), number_of(m, "last", nan()), number_of(m, "anchor", nan())))
    }
    if str.eq(op, "workflows") {
        let items = items_of(member_of(m, "workflows"))
        let (list, e) = mem.alloc[t.Workflow](a, items.len + 1usize)
        if e != ok { ret "?" }
        var i = 0usize
        while i < items.len {
            let wm = members_of(items[i])
            let (sv, has_s) = get(wm, "schedule")
            let (av, has_a) = get(wm, "activeRun")
            var started = nan()
            if has_a && !is_null(av) { started = number_or_nan(members_of(av), "startedAt") }
            var sched_concurrency = ""
            if has_s && !is_null(sv) { sched_concurrency = text_of(members_of(sv), "concurrency") }
            list[i] = t.Workflow {
                id: text_of(wm, "id"), has_schedule: has_s && !is_null(sv), schedule: stored_of(a, sv),
                last_run: number_of(wm, "lastRunAt", nan()), anchor: number_of(wm, "anchorMs", nan()),
                has_active_run: has_a && !is_null(av), started_at: started, concurrency: text_of(wm, "concurrency"),
                schedule_concurrency: sched_concurrency,
            }
            i += 1usize
        }
        let verdicts = t.due_workflows(a, clock, list[0usize..items.len], number_of(m, "now", nan()))
        var out = ""
        i = 0usize
        while i < verdicts.len {
            out = join3(a, out, hex_text(a, verdicts[i].id), "=")
            out = join3(a, out, render_decision(a, verdicts[i].decision), ";")
            i += 1usize
        }
        ret out
    }
    if str.eq(op, "overlap") {
        let (av, has_a) = get(m, "activeRun")
        var started = nan()
        if has_a && !is_null(av) { started = number_or_nan(members_of(av), "startedAt") }
        var concurrency = "skip"
        let given = text_of(m, "concurrency")
        if given.len != 0usize { concurrency = given }
        var stale = 21600000.0f64
        if has_number(m, "staleAfterMs") { stale = number_of(m, "staleAfterMs", stale) }
        ret render_decision(a, t.overlap_decision(bool_of(m, "due"), number_of(m, "fireAt", nan()), has_a && !is_null(av), started, concurrency, stale, number_of(m, "now", 0.0f64)))
    }
    if str.eq(op, "dueevents") {
        let items = items_of(member_of(m, "records"))
        let cm = members_of(member_of(m, "config"))
        let field = text_of(cm, "field")
        let (ids, e1) = mem.alloc[str](a, items.len + 1usize)
        let (dates, e2) = mem.alloc[str](a, items.len + 1usize)
        let stamp_items = items_of(member_of(m, "stamps"))
        let (stamps, e3) = mem.alloc[t.Stamp](a, stamp_items.len + items.len + 1usize)
        if e1 != ok || e2 != ok || e3 != ok { ret "?" }
        var i = 0usize
        while i < items.len {
            let rm = members_of(items[i])
            ids[i] = text_of(rm, "id")
            dates[i] = text_of(rm, field)
            i += 1usize
        }
        i = 0usize
        while i < stamp_items.len {
            let pair = items_of(stamp_items[i])
            stamps[i] = t.Stamp { id: text_of_value(pair[0usize]), goal: number_of_value(pair[1usize]) }
            i += 1usize
        }
        let r = t.due_date_events(a, ids[0usize..items.len], dates[0usize..items.len], number_of(cm, "offsetMs", 0.0f64), stamps, stamp_items.len, number_of(m, "now", 0.0f64))
        var out = ""
        i = 0usize
        while i < r.events.len {
            out = join3(a, out, hex_text(a, r.events[i].id), ":")
            out = join3(a, out, ms_text(a, r.events[i].goal), ":")
            out = join3(a, out, ms_text(a, r.events[i].fire_at), ";")
            i += 1usize
        }
        out = join(a, out, "#")
        i = 0usize
        while i < r.stamp_count {
            out = join3(a, out, hex_text(a, stamps[i].id), "=")
            out = join3(a, out, ms_text(a, stamps[i].goal), ";")
            i += 1usize
        }
        ret out
    }
    if str.eq(op, "duration") || str.eq(op, "scan") {
        let rows = rows_of(a, member_of(m, "records"))
        let cm = members_of(member_of(m, "config"))
        let fields = field_defs_of(a, member_of(m, "fields"))
        var has_filter = false
        var tree = v.empty_group("and")
        let (tv, has_tree) = get(cm, "filter")
        if has_tree && !is_null(tv) {
            has_filter = true
            tree = node_of(a, tv)
        }
        var ctx: v.Context = zero
        ctx.user_id = f.blank()
        if str.eq(op, "scan") {
            let om = members_of(member_of(m, "opts"))
            var cap = 10000usize
            let cap_raw = number_of(om, "cap", 0.0f64)
            if cap_raw > 0.0f64 { cap = usize(cap_raw) }
            var cursor = 0usize
            let cursor_raw = number_of(om, "cursor", 0.0f64)
            if cursor_raw > 0.0f64 { cursor = usize(cursor_raw) }
            let batch = text_of(om, "batchId")
            let r = t.scan_batch(a, reg, rows, tree, has_filter, fields, &ctx, cap, cursor, batch, batch.len != 0usize)
            var out = ""
            var i = 0usize
            while i < r.events.len {
                out = join3(a, out, hex_text(a, r.events[i].id), "@")
                out = join3(a, out, hex_text(a, r.events[i].batch_id), "@")
                out = join3(a, out, ms_text(a, f64(r.events[i].size)), "@")
                out = join3(a, out, ms_text(a, f64(r.events[i].position)), ";")
                i += 1usize
            }
            out = join3(a, out, "n=", ms_text(a, f64(r.total)))
            if r.has_next { ret join3(a, out, ",", ms_text(a, f64(r.next_cursor))) }
            ret join(a, out, ",_")
        }
        let initial = items_of(member_of(m, "state"))
        let (state, es) = mem.alloc[t.InState](a, initial.len + rows.len + 1usize)
        if es != ok { ret "?" }
        var i = 0usize
        while i < initial.len {
            let triple = items_of(initial[i])
            state[i] = t.InState { id: text_of_value(triple[0usize]), since: number_of_value(triple[1usize]), fired: bool_of_value(triple[2usize]) }
            i += 1usize
        }
        let r = t.duration_in_state_due(a, reg, rows, tree, has_filter, fields, &ctx, number_of(cm, "durationMs", 0.0f64), state, initial.len, number_of(m, "now", 0.0f64))
        var out = ""
        i = 0usize
        while i < r.events.len {
            out = join3(a, out, hex_text(a, r.events[i].id), ":")
            out = join3(a, out, ms_text(a, r.events[i].since), ":")
            out = join3(a, out, ms_text(a, r.events[i].duration_ms), ";")
            i += 1usize
        }
        out = join(a, out, "#")
        i = 0usize
        while i < r.state_count {
            out = join3(a, out, hex_text(a, state[i].id), "=")
            out = join3(a, out, ms_text(a, state[i].since), ",")
            out = join3(a, out, flag(state[i].fired), ";")
            i += 1usize
        }
        ret out
    }
    ret "?op"
}

fn text_of_value(x: json.Value) -> str {
    switch x {
    case .String as s:
        ret s
    default:
        ret ""
    }
}

fn number_of_value(x: json.Value) -> f64 {
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        ret value
    default:
        ret 0.0f64
    }
}

fn bool_of_value(x: json.Value) -> bool {
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

fn bool_of(members: []const json.Member, key: str) -> bool {
    let (x, found) = get(members, key)
    if !found { ret false }
    ret bool_of_value(x)
}

//__VECTOR_FUNCTIONS__
fn run(a: *mem.Arena, body: str, reg: *f.Registry, clock: *const t.Clock) -> u8 {
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
                got = evaluate(a, m, reg, clock)
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
    let (clock, clock_error) = t.new_clock(a)
    if clock_error != ok { os.exit(91i32) }
    //__VECTOR_CALLS__
    try io.print("algo trigger ok")
    ret ok
}
