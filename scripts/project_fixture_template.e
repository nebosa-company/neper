// `e.algo.project` against appdor's own `src/scheduling/{index,dependencies,working-calendar}.js`:
// scripts/project_reference.mjs runs appdor's critical path, Gantt layout, progress roll-up, month grid, workload,
// cascade and working calendar over random inputs and writes `{"op": ..., ...inputs, "e": outcome}` lines; the
// fixture rebuilds the inputs and must render the same outcome.
use e.algo.formula as f
use e.algo.project as p
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

const DAY: i64 = 86400000i64

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

fn int_text(a: *mem.Arena, n: i64) -> str { ret f.number_text(a, f64(n)) }

fn flag(x: bool) -> str {
    if x { ret "1" }
    ret "0"
}

// --- JSON access ----------------------------------------------------------------------------------------------------

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

fn member(members: []const json.Member, key: str) -> json.Value {
    let (x, found) = get(members, key)
    ret x
}

fn is_number(x: json.Value) -> bool {
    switch x {
    case .Number as n:
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

// A member that is a number, or NaN.
fn number_member(members: []const json.Member, key: str) -> f64 {
    let (x, found) = get(members, key)
    if !found { ret 0.0f64 / 0.0f64 }
    ret number_of(x, 0.0f64 / 0.0f64)
}

fn bool_member(members: []const json.Member, key: str) -> bool {
    let (x, found) = get(members, key)
    if !found { ret false }
    switch x {
    case .Bool as v:
        ret v
    default:
        ret false
    }
}

fn ms_of(x: json.Value) -> i64 { ret i64(number_of(x, 0.0f64)) }

// --- JSON to model --------------------------------------------------------------------------------------------------

fn dependency_from(x: json.Value) -> (p.Dependency, bool) {
    var empty = p.Dependency { id: "", kind: p.FS, lag: 0i64 }
    switch x {
    case .String as s:
        let (plain, plain_ok) = p.dependency_of(s, "", 0.0f64)
        ret (plain, plain_ok)
    case .Object as m:
        var id = ""
        let (a1, h1) = get(m, "id")
        if h1 && is_string(a1) {
            id = text_of(a1)
        } else {
            let (a2, h2) = get(m, "predecessor")
            if h2 && is_string(a2) {
                id = text_of(a2)
            } else {
                let (a3, h3) = get(m, "from")
                if h3 && is_string(a3) { id = text_of(a3) }
            }
        }
        let (type_value, has_type) = get(m, "type")
        var kind_text = ""
        if has_type && is_string(type_value) { kind_text = text_of(type_value) }
        let (lag_value, has_lag) = get(m, "lag")
        var lag = 0.0f64 / 0.0f64
        if has_lag && is_number(lag_value) { lag = number_of(lag_value, 0.0f64) }
        let (made, made_ok) = p.dependency_of(id, kind_text, lag)
        ret (made, made_ok)
    default:
        ret (empty, false)
    }
}

fn deps_of(a: *mem.Arena, x: json.Value) -> []const p.Dependency {
    var none: []const p.Dependency = zero
    let items = items_of(x)
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[p.Dependency](a, items.len)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < items.len {
        let (d, good) = dependency_from(items[i])
        if good {
            out[n] = d
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn tasks_of(a: *mem.Arena, x: json.Value) -> []const p.Task {
    var none: []const p.Task = zero
    let items = items_of(x)
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[p.Task](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        let m = members_of(items[i])
        let (dv, has_duration_member) = get(m, "duration")
        var duration = 0i64
        var has_duration = false
        if has_duration_member && is_number(dv) {
            let raw = number_of(dv, 0.0f64)
            duration = i64(raw)
            has_duration = true
        }
        let (deps_value, has_deps) = get(m, "deps")
        var deps: []const p.Dependency = zero
        if has_deps { deps = deps_of(a, deps_value) }
        let (parent_value, has_parent_member) = get(m, "parent")
        var parent = ""
        var has_parent = false
        if has_parent_member && is_string(parent_value) {
            parent = text_of(parent_value)
            has_parent = true
        }
        out[i] = p.Task {
            id: text_member(m, "id"), name: text_member(m, "name"), duration: duration, has_duration: has_duration,
            milestone: bool_member(m, "milestone"), progress: number_member(m, "progress"), parent: parent,
            has_parent: has_parent, deps: deps,
        }
        i += 1usize
    }
    ret out[0usize..items.len]
}

fn mask_of(x: json.Value) -> u32 {
    var mask = 0u32
    let days = items_of(x)
    var i = 0usize
    while i < days.len {
        let d = i64(number_of(days[i], 7.0f64))
        if d >= 0i64 && d <= 6i64 { mask = mask | (1u32 << u32(d)) }
        i += 1usize
    }
    ret mask
}

fn days_of(a: *mem.Arena, x: json.Value) -> []const i64 {
    var none: []const i64 = zero
    let items = items_of(x)
    if items.len == 0usize { ret none }
    let (out, e) = mem.alloc[i64](a, items.len)
    if e != ok { ret none }
    var i = 0usize
    while i < items.len {
        out[i] = p.day_of_ms(ms_of(items[i]))
        i += 1usize
    }
    ret out[0usize..items.len]
}

// `calendarFrom(options)`: the options' working days and holidays, or the continuous calendar.
fn calendar_of(a: *mem.Arena, m: []const json.Member) -> p.Calendar {
    let (wd, has_wd) = get(m, "workingDays")
    let (hol, has_hol) = get(m, "holidays")
    if !has_wd && !has_hol { ret p.continuous_calendar() }
    var mask = p.DEFAULT_WORKING_DAYS
    if has_wd { mask = mask_of(wd) }
    var holidays: []const i64 = zero
    if has_hol { holidays = days_of(a, hol) }
    ret p.working_calendar(a, mask, holidays)
}

// --- rendering ------------------------------------------------------------------------------------------------------

fn render_cpm(a: *mem.Arena, tasks: []const p.Task) -> str {
    let r = p.critical_path(a, tasks)
    if r.has_cycle { ret join3(a, "!", "Circular dependency: ", r.cycle) }
    var out = join3(a, "D", int_text(a, r.project_duration), ";")
    var i = 0usize
    while i < r.slots.len {
        let s = r.slots[i]
        out = join3(a, out, hex_text(a, tasks[s.index].id), ":")
        out = join3(a, out, int_text(a, s.es), ",")
        out = join3(a, out, int_text(a, s.ef), ",")
        out = join3(a, out, int_text(a, s.ls), ",")
        out = join3(a, out, int_text(a, s.lf), ",")
        out = join3(a, out, int_text(a, s.slack), ",")
        out = join3(a, out, flag(s.critical), ";")
        i += 1usize
    }
    out = join(a, out, "P:")
    var first = true
    i = 0usize
    while i < r.slots.len {
        if r.slots[i].critical {
            if !first { out = join(a, out, ",") }
            first = false
            out = join(a, out, hex_text(a, tasks[r.slots[i].index].id))
        }
        i += 1usize
    }
    ret out
}

fn optional_ms(a: *mem.Arena, present: bool, value: i64, absent_mark: str) -> str {
    if !present { ret absent_mark }
    ret int_text(a, value)
}

fn render_gantt(a: *mem.Arena, tasks: []const p.Task, m: []const json.Member) -> str {
    let cal = calendar_of(a, m)
    let (start_value, has_start_member) = get(m, "projectStart")
    var has_start = false
    var start_ms = 0i64
    if has_start_member && is_number(start_value) {
        has_start = true
        start_ms = ms_of(start_value)
    }
    // The baseline: members keyed by task id.
    var baseline: []const p.Baseline = zero
    let (base_value, has_base) = get(m, "baseline")
    if has_base {
        let entries = members_of(base_value)
        let (cells, e) = mem.alloc[p.Baseline](a, entries.len + 1usize)
        if e == ok {
            var i = 0usize
            while i < entries.len {
                let em = members_of(entries[i].value)
                let (sv, hs) = get(em, "start")
                let (ev, he) = get(em, "end")
                cells[i] = p.Baseline {
                    id: entries[i].key, start_ms: ms_of(sv), has_start: hs && is_number(sv),
                    end_ms: ms_of(ev), has_end: he && is_number(ev),
                }
                i += 1usize
            }
            baseline = cells[0usize..entries.len]
        }
    }
    let r = p.gantt_layout(a, tasks, cal, start_ms, has_start, baseline)
    if r.has_cycle { ret join3(a, "!", "Circular dependency: ", r.cycle) }
    var out = join3(a, "D", int_text(a, r.project_duration), ";S")
    // The project start is read as given, a time of day included; only the bars snap to a day.
    var shown_start = 0i64
    if has_start { shown_start = start_ms }
    out = join3(a, out, int_text(a, shown_start), ";E")
    out = join3(a, out, int_text(a, r.end_day * DAY), ";")
    var i = 0usize
    while i < r.bars.len {
        let b = r.bars[i]
        out = join3(a, out, hex_text(a, b.id), "|")
        out = join3(a, out, hex_text(a, b.name), "|")
        out = join3(a, out, int_text(a, b.start_offset), "|")
        out = join3(a, out, int_text(a, b.duration), "|")
        out = join3(a, out, int_text(a, b.start_day * DAY), "|")
        out = join3(a, out, int_text(a, b.end_day * DAY), "|")
        out = join3(a, out, int_text(a, b.slack), "|")
        out = join3(a, out, flag(b.critical), "|")
        out = join3(a, out, flag(b.milestone), "|")
        out = join3(a, out, num(a, b.progress), "|")
        // `-` when the task has no baseline entry, `_` when it has one without that field.
        var bs = "-"
        var be = "-"
        var bv = "-"
        if b.has_baseline {
            bs = optional_ms(a, b.has_baseline_start, b.baseline_start_ms, "_")
            be = optional_ms(a, b.has_baseline_end, b.baseline_end_ms, "_")
            bv = optional_ms(a, b.has_variance, b.variance, "_")
        }
        out = join3(a, out, bs, "|")
        out = join3(a, out, be, "|")
        out = join3(a, out, bv, ";")
        i += 1usize
    }
    out = join(a, out, "P:")
    i = 0usize
    while i < r.critical.len {
        if i > 0usize { out = join(a, out, ",") }
        out = join(a, out, hex_text(a, tasks[r.critical[i]].id))
        i += 1usize
    }
    ret out
}

fn render_rollup(a: *mem.Arena, tasks: []const p.Task) -> str {
    let values = p.roll_up_progress(a, tasks)
    var out = ""
    var i = 0usize
    while i < tasks.len {
        out = join3(a, out, hex_text(a, tasks[i].id), "=")
        out = join3(a, out, num(a, values[i]), ";")
        i += 1usize
    }
    ret out
}

fn render_calendar(a: *mem.Arena, m: []const json.Member) -> str {
    let items = items_of(member(m, "events"))
    let (cells, e) = mem.alloc[p.Event](a, items.len + 1usize)
    if e != ok { ret "?" }
    var i = 0usize
    while i < items.len {
        let em = members_of(items[i])
        let (sv, hs) = get(em, "start")
        let (dv, hd) = get(em, "date")
        let (ev, he) = get(em, "end")
        var ev_out = p.Event { id: text_member(em, "id"), start_ms: 0i64, has_start: false, end_ms: 0i64, has_end: false }
        if hs && is_number(sv) {
            ev_out.start_ms = ms_of(sv)
            ev_out.has_start = true
        } else if hd && is_number(dv) {
            ev_out.start_ms = ms_of(dv)
            ev_out.has_start = true
        }
        if he && is_number(ev) {
            ev_out.end_ms = ms_of(ev)
            ev_out.has_end = true
        }
        cells[i] = ev_out
        i += 1usize
    }
    let pm = members_of(member(m, "params"))
    let year = i64(number_member(pm, "year"))
    let month = i64(number_member(pm, "month"))
    var week_start = 0i64
    let (wv, has_w) = get(pm, "weekStart")
    if has_w && is_number(wv) { week_start = i64(number_of(wv, 0.0f64)) }
    let r = p.calendar_layout(a, cells[0usize..items.len], year, month, week_start)
    var out = join3(a, int_text(a, r.year), ",", int_text(a, r.month))
    out = join(a, out, ",")
    var c = 0usize
    while c < r.weeks.len {
        if c > 0usize {
            if c % 7usize == 0usize { out = join(a, out, "/") } else { out = join(a, out, ";") }
        }
        let cell = r.weeks[c]
        if cell.day == 0i64 { out = join(a, out, "_:") } else { out = join3(a, out, int_text(a, cell.day), ":") }
        var k = 0usize
        while k < cell.events.len {
            if k > 0usize { out = join(a, out, ",") }
            out = join(a, out, hex_text(a, cells[cell.events[k]].id))
            k += 1usize
        }
        c += 1usize
    }
    ret out
}

fn render_workload(a: *mem.Arena, m: []const json.Member) -> str {
    let om = members_of(member(m, "options"))
    var effort_field = ""
    let (ef, has_ef) = get(om, "effortField")
    if has_ef && is_string(ef) { effort_field = text_of(ef) }
    let items = items_of(member(m, "assignments"))
    let (cells, e) = mem.alloc[p.Assignment](a, items.len + 1usize)
    if e != ok { ret "?" }
    var i = 0usize
    while i < items.len {
        let am = members_of(items[i])
        let (sv, hs) = get(am, "start")
        let (ev, he) = get(am, "end")
        var x = p.Assignment {
            assignee: text_member(am, "assignee"), start_ms: ms_of(sv), has_start: hs && is_number(sv), end_ms: 0i64,
            has_end: false, hours: 0.0f64, has_hours: false,
        }
        if he && is_number(ev) {
            x.end_ms = ms_of(ev)
            x.has_end = true
        }
        // The declared effort: the named field, else `hoursPerDay`.
        var key = "hoursPerDay"
        if effort_field.len != 0usize { key = effort_field }
        let (hv, hh) = get(am, key)
        if hh && is_number(hv) {
            x.hours = number_of(hv, 0.0f64)
            x.has_hours = true
        }
        cells[i] = x
        i += 1usize
    }
    var capacity = 8.0f64
    let (cv, has_c) = get(om, "capacityPerDay")
    if has_c && is_number(cv) { capacity = number_of(cv, 8.0f64) }
    var overrides: []const p.CapacityOverride = zero
    let (ov, has_o) = get(om, "capacityOverrides")
    if has_o {
        let entries = members_of(ov)
        let (list, e2) = mem.alloc[p.CapacityOverride](a, entries.len + 1usize)
        if e2 == ok {
            var k = 0usize
            while k < entries.len {
                list[k] = p.CapacityOverride { assignee: entries[k].key, capacity: number_of(entries[k].value, 0.0f64 / 0.0f64) }
                k += 1usize
            }
            overrides = list[0usize..entries.len]
        }
    }
    var count_mode = false
    let (mv, has_m) = get(om, "mode")
    if has_m && str.eq(text_of(mv), "count") { count_mode = true }
    let cal = calendar_of(a, om)
    let r = p.workload(a, cells[0usize..items.len], capacity, overrides, count_mode, cal)
    var out = ""
    var w = 0usize
    while w < r.per_assignee.len {
        if w > 0usize { out = join(a, out, ";") }
        out = join3(a, out, hex_text(a, r.per_assignee[w].assignee), "{")
        var d = 0usize
        while d < r.per_assignee[w].days.len {
            if d > 0usize { out = join(a, out, ",") }
            out = join3(a, out, int_text(a, r.per_assignee[w].days[d].day), "=")
            out = join(a, out, num(a, r.per_assignee[w].days[d].hours))
            d += 1usize
        }
        out = join(a, out, "}")
        w += 1usize
    }
    out = join(a, out, "#")
    var o = 0usize
    while o < r.overallocated.len {
        let x = r.overallocated[o]
        if o > 0usize { out = join(a, out, ";") }
        out = join3(a, out, hex_text(a, x.assignee), "|")
        out = join3(a, out, int_text(a, x.day), "|")
        out = join3(a, out, num(a, x.hours), "|")
        out = join3(a, out, num(a, x.over), "|")
        out = join(a, out, num(a, x.capacity))
        o += 1usize
    }
    ret out
}

fn render_cascade(a: *mem.Arena, tasks: []const p.Task, m: []const json.Member) -> str {
    let entries = members_of(member(m, "schedule"))
    let (cells, e) = mem.alloc[p.Window](a, entries.len + 1usize)
    if e != ok { ret "?" }
    var i = 0usize
    while i < entries.len {
        let wm = members_of(entries[i].value)
        cells[i] = p.Window { id: entries[i].key, es: i64(number_member(wm, "es")), ef: i64(number_member(wm, "ef")) }
        i += 1usize
    }
    let cm = members_of(member(m, "change"))
    let moves = p.cascade_reschedule(a, tasks, cells[0usize..entries.len], text_member(cm, "id"), i64(number_member(cm, "start")))
    var out = ""
    i = 0usize
    while i < moves.len {
        out = join3(a, out, hex_text(a, moves[i].id), ":")
        out = join3(a, out, int_text(a, moves[i].from), ">")
        out = join3(a, out, int_text(a, moves[i].to), "(")
        out = join3(a, out, int_text(a, moves[i].shift), ");")
        i += 1usize
    }
    ret out
}

fn render_calendar_ops(a: *mem.Arena, m: []const json.Member) -> str {
    var mask = p.DEFAULT_WORKING_DAYS
    let (wd, has_wd) = get(m, "workingDays")
    if has_wd && !is_null_value(wd) { mask = mask_of(wd) }
    let cal = p.working_calendar(a, mask, days_of(a, member(m, "holidays")))
    let all_week = cal.weekdays == 127u32 && cal.holidays.len == 0usize
    var out = flag(cal.continuous || all_week)
    let queries = items_of(member(m, "queries"))
    var i = 0usize
    while i < queries.len {
        let q = items_of(queries[i])
        let kind = text_of(q[0usize])
        let from_ms = ms_of(q[1usize])
        let to_ms = ms_of(q[2usize])
        let count = i64(number_of(q[3usize], 0.0f64))
        let from = p.day_of_ms(from_ms)
        let to = p.day_of_ms(to_ms)
        out = join(a, out, ",")
        if str.eq(kind, "is") { out = join(a, out, flag(p.is_working_day(cal, from))) }
        if str.eq(kind, "next") { out = join(a, out, int_text(a, p.next_working_day(cal, from) * DAY)) }
        if str.eq(kind, "add") { out = join(a, out, int_text(a, p.add_working_days(cal, from, count) * DAY)) }
        if str.eq(kind, "count") { out = join(a, out, int_text(a, p.count_working_days(cal, from, to))) }
        if str.eq(kind, "span") { out = join(a, out, int_text(a, p.working_span(cal, from, to))) }
        i += 1usize
    }
    ret out
}

fn is_null_value(x: json.Value) -> bool {
    switch x {
    case .Null:
        ret true
    default:
        ret false
    }
}

fn evaluate(a: *mem.Arena, m: []const json.Member) -> str {
    let op = text_member(m, "op")
    if str.eq(op, "cpm") { ret render_cpm(a, tasks_of(a, member(m, "tasks"))) }
    if str.eq(op, "gantt") { ret render_gantt(a, tasks_of(a, member(m, "tasks")), members_of(member(m, "options"))) }
    if str.eq(op, "rollup") { ret render_rollup(a, tasks_of(a, member(m, "tasks"))) }
    if str.eq(op, "calendar") { ret render_calendar(a, m) }
    if str.eq(op, "workload") { ret render_workload(a, m) }
    if str.eq(op, "cascade") { ret render_cascade(a, tasks_of(a, member(m, "tasks")), m) }
    if str.eq(op, "calendar-ops") { ret render_calendar_ops(a, m) }
    if str.eq(op, "depfn") {
        let (dep, good) = p.dependency_of("x", text_member(m, "kind"), number_member(m, "lag"))
        let es = i64(number_member(m, "es"))
        let ef = i64(number_member(m, "ef"))
        let dur = i64(number_member(m, "dur"))
        let start = p.earliest_start_under(dep, es, ef, dur)
        let finish = p.latest_finish_under(dep, es, ef, dur)
        ret join3(a, int_text(a, start), ",", int_text(a, finish))
    }
    ret "?op"
}

//__VECTOR_FUNCTIONS__
fn run(a: *mem.Arena, body: str) -> u8 {
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

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("algo project ok")
    ret ok
}
