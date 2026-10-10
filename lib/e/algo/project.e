// Project scheduling (L035), after appdor's `src/scheduling/{index,dependencies,working-calendar}.js`: typed task
// dependencies (finish-to-start, start-to-start, finish-to-finish, start-to-finish, each with a lag or lead), the
// critical path method over integer working-day offsets (a forward pass, a backward pass, slack, the critical
// chain), Gantt bars resolved to dates through a working calendar with baseline variance, duration-weighted
// progress roll-up, the month grid of a calendar view, per-assignee workload with capacity overrides, and the
// minimal cascade of follow-on moves when a predecessor is rescheduled.
//
// Offsets are whole working days; dates are UTC and stand as day counts since 1970-01-01 (a time of day is dropped
// where appdor takes `startOfDay`). Millisecond instants appear only where appdor reads them as such (a baseline's
// end, an assignment's start and end).
//
// Differences from appdor's: a task id is a text (a numeric id is its decimal spelling) and ids are unique; a
// duration is a whole number of days; an unparseable event end that appdor throws on is read as absent.

use e.algo.formula as f
use e.math
use e.mem
use e.str

const DAY_MS: i64 = 86400000i64

// --- working calendar ---------------------------------------------------------------------------------------------

// `weekdays` carries bit d for `getUTCDay() == d` (Sunday is 0); `holidays` are sorted, distinct day counts.
type Calendar = struct { weekdays: u32, holidays: []const i64, continuous: bool }

// Monday to Friday.
const DEFAULT_WORKING_DAYS: u32 = 62u32

fn floor_div(x: i64, y: i64) -> i64 {
    var q = x / y
    if (x % y != 0i64) && ((x < 0i64) != (y < 0i64)) { q -= 1i64 }
    ret q
}

// The day count holding an instant, which is what appdor's `startOfDay` keeps.
fn day_of_ms(ms: i64) -> i64 { ret floor_div(ms, DAY_MS) }

// 0 is Sunday, as `getUTCDay`.
fn weekday_of(day: i64) -> i64 {
    var w = (day + 4i64) % 7i64
    if w < 0i64 { w += 7i64 }
    ret w
}

fn sort_days(days: []i64) {
    var i = 1usize
    while i < days.len {
        let v = days[i]
        var j = i
        while j > 0usize && days[j - 1usize] > v {
            days[j] = days[j - 1usize]
            j -= 1usize
        }
        days[j] = v
        i += 1usize
    }
}

// A calendar of the given weekday mask and holidays. No working weekday at all would hang every advance, so it is
// read as continuous time, as appdor's.
fn working_calendar(a: *mem.Arena, weekdays: u32, holidays: []const i64) -> Calendar {
    var none: []const i64 = zero
    var mask = weekdays & 127u32
    var continuous = false
    if mask == 0u32 {
        continuous = true
        mask = 127u32
    }
    let (cells, e) = mem.alloc[i64](a, holidays.len + 1usize)
    if e != ok { ret Calendar { weekdays: mask, holidays: none, continuous: continuous } }
    var n = 0usize
    var i = 0usize
    while i < holidays.len {
        cells[n] = holidays[i]
        n += 1usize
        i += 1usize
    }
    sort_days(cells[0usize..n])
    var kept = 0usize
    i = 0usize
    while i < n {
        if kept == 0usize || cells[kept - 1usize] != cells[i] {
            cells[kept] = cells[i]
            kept += 1usize
        }
        i += 1usize
    }
    ret Calendar { weekdays: mask, holidays: cells[0usize..kept], continuous: continuous }
}

// Every day works: the default when a view declares no working calendar.
fn continuous_calendar() -> Calendar {
    var none: []const i64 = zero
    ret Calendar { weekdays: 127u32, holidays: none, continuous: false }
}

fn is_holiday(cal: Calendar, day: i64) -> bool {
    var i = 0usize
    while i < cal.holidays.len {
        if cal.holidays[i] == day { ret true }
        i += 1usize
    }
    ret false
}

fn is_working_day(cal: Calendar, day: i64) -> bool {
    if cal.continuous { ret true }
    if (cal.weekdays >> u32(weekday_of(day))) & 1u32 == 0u32 { ret false }
    ret !is_holiday(cal, day)
}

// The given day if it works, else the next one that does.
fn next_working_day(cal: Calendar, day: i64) -> i64 {
    var d = day
    while !is_working_day(cal, d) { d += 1i64 }
    ret d
}

// The day `count` working days after `from`; zero snaps forward onto a working day.
fn add_working_days(cal: Calendar, from: i64, count: i64) -> i64 {
    var d = next_working_day(cal, from)
    var remaining = count
    if remaining < 0i64 { remaining = 0i64 }
    while remaining > 0i64 {
        d += 1i64
        if is_working_day(cal, d) { remaining -= 1i64 }
    }
    ret d
}

// Working days from `from` to `to`, the start counted and the end excluded.
fn count_working_days(cal: Calendar, from: i64, to: i64) -> i64 {
    if to <= from { ret 0i64 }
    var n = 0i64
    var d = next_working_day(cal, from)
    while d < to {
        if is_working_day(cal, d) { n += 1i64 }
        d += 1i64
    }
    ret n
}

// The inclusive span of working days a bar covers.
fn working_span(cal: Calendar, from: i64, to: i64) -> i64 {
    if to < from { ret 0i64 }
    var n = 0i64
    var d = from
    while d <= to {
        if is_working_day(cal, d) { n += 1i64 }
        d += 1i64
    }
    ret n
}

// --- dependencies -------------------------------------------------------------------------------------------------

const FS: u8 = 0u8
const SS: u8 = 1u8
const FF: u8 = 2u8
const SF: u8 = 3u8

type Dependency = struct { id: str, kind: u8, lag: i64 }

fn upper_ascii(c: u8) -> u8 {
    if c >= 97u8 && c <= 122u8 { ret c - 32u8 }
    ret c
}

// The kind a spelling names, `FS` when it names none.
fn kind_of(text: str) -> u8 {
    if text.len != 2usize { ret FS }
    let x = upper_ascii(text[0usize])
    let y = upper_ascii(text[1usize])
    if x == 70u8 && y == 83u8 { ret FS }
    if x == 83u8 && y == 83u8 { ret SS }
    if x == 70u8 && y == 70u8 { ret FF }
    if x == 83u8 && y == 70u8 { ret SF }
    ret FS
}

fn is_finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

// `normalizeDependency`: a dependency with no predecessor id is refused (`false`); an unknown kind is
// finish-to-start; a lag that is not a finite number is zero, and a fraction is truncated.
fn dependency_of(id: str, kind_text: str, lag: f64) -> (Dependency, bool) {
    var out = Dependency { id: id, kind: kind_of(kind_text), lag: 0i64 }
    if is_finite(lag) { out.lag = i64(math.trunc[f64](lag)) }
    ret (out, id.len != 0usize)
}

// The earliest start the constraint permits, given the predecessor's window.
fn earliest_start_under(dep: Dependency, es: i64, ef: i64, successor_duration: i64) -> i64 {
    if dep.kind == SS { ret es + dep.lag }
    if dep.kind == FF { ret ef + dep.lag - successor_duration }
    if dep.kind == SF { ret es + dep.lag - successor_duration }
    ret ef + dep.lag
}

// The latest finish the constraint permits for the predecessor, given the successor's window.
fn latest_finish_under(dep: Dependency, ls: i64, lf: i64, predecessor_duration: i64) -> i64 {
    if dep.kind == SS { ret ls - dep.lag + predecessor_duration }
    if dep.kind == FF { ret lf - dep.lag }
    if dep.kind == SF { ret lf - dep.lag + predecessor_duration }
    ret ls - dep.lag
}

// --- tasks and the critical path ---------------------------------------------------------------------------------

// `progress` is NaN when the record carries no finite number; `has_duration` is true for a finite duration.
type Task = struct {
    id: str,
    name: str,
    duration: i64,
    has_duration: bool,
    milestone: bool,
    progress: f64,
    parent: str,
    has_parent: bool,
    deps: []const Dependency,
}

fn index_of(tasks: []const Task, id: str) -> (usize, bool) {
    var i = 0usize
    while i < tasks.len {
        if str.eq(tasks[i].id, id) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn duration_of(t: Task) -> i64 {
    if t.duration < 0i64 { ret 0i64 }
    ret t.duration
}

// One task's offsets and slack.
type Slot = struct { index: usize, es: i64, ef: i64, ls: i64, lf: i64, slack: i64, critical: bool }

// `order` lists the task indices in topological order and `slots` is parallel to it. A dependency cycle is
// `cycle`, the chain `a -> b -> a` appdor's error message carries.
type CriticalPath = struct { order: []const usize, slots: []const Slot, project_duration: i64, cycle: str, has_cycle: bool }

fn join_cycle(a: *mem.Arena, tasks: []const Task, stack: []const usize, depth: usize, closing: usize) -> str {
    var out = ""
    var i = 0usize
    while i < depth {
        out = f.join3(a, out, tasks[stack[i]].id, " -> ")
        i += 1usize
    }
    ret f.join(a, out, tasks[closing].id)
}

type Walk = struct { state: []u8, order: []usize, count: usize, stack: []usize, cycle: str, failed: bool }

fn visit(a: *mem.Arena, tasks: []const Task, w: *Walk, at: usize, depth: usize) {
    if w.failed { ret }
    if w.state[at] == 2u8 { ret }
    if w.state[at] == 1u8 {
        w.failed = true
        w.cycle = join_cycle(a, tasks, w.stack, depth, at)
        ret
    }
    w.state[at] = 1u8
    w.stack[depth] = at
    var d = 0usize
    while d < tasks[at].deps.len && !w.failed {
        let (target_index, found) = index_of(tasks, tasks[at].deps[d].id)
        if found { visit(a, tasks, w, target_index, depth + 1usize) }
        d += 1usize
    }
    if w.failed { ret }
    w.state[at] = 2u8
    w.order[w.count] = at
    w.count += 1usize
}

// The critical path method: the forward pass floors every start at the project origin, the backward pass mirrors
// each constraint from the project's end, and a task is critical when its slack is zero.
fn critical_path(a: *mem.Arena, tasks: []const Task) -> CriticalPath {
    var none_order: []const usize = zero
    var none_slots: []const Slot = zero
    var failure = CriticalPath { order: none_order, slots: none_slots, project_duration: 0i64, cycle: "", has_cycle: false }
    let n = tasks.len
    let (state, e1) = mem.alloc[u8](a, n + 1usize)
    let (order, e2) = mem.alloc[usize](a, n + 1usize)
    let (stack, e3) = mem.alloc[usize](a, n + 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret failure }
    var i = 0usize
    while i < n {
        state[i] = 0u8
        i += 1usize
    }
    var w = Walk { state: state, order: order, count: 0usize, stack: stack, cycle: "", failed: false }
    i = 0usize
    while i < n && !w.failed {
        visit(a, tasks, &w, i, 0usize)
        i += 1usize
    }
    if w.failed {
        failure.cycle = w.cycle
        failure.has_cycle = true
        ret failure
    }
    let (slots, e4) = mem.alloc[Slot](a, n + 1usize)
    let (position, e5) = mem.alloc[usize](a, n + 1usize)
    if e4 != ok || e5 != ok { ret failure }
    // Position in topological order, by task index.
    i = 0usize
    while i < n {
        position[order[i]] = i
        i += 1usize
    }
    var project = 0i64
    i = 0usize
    while i < n {
        let at = order[i]
        let t = tasks[at]
        let dur = duration_of(t)
        var start = 0i64
        var any = false
        var d = 0usize
        while d < t.deps.len {
            let (p, found) = index_of(tasks, t.deps[d].id)
            if found {
                let ps = slots[position[p]]
                let candidate = earliest_start_under(t.deps[d], ps.es, ps.ef, dur)
                if !any || candidate > start { start = candidate }
                any = true
            }
            d += 1usize
        }
        if start < 0i64 { start = 0i64 }
        slots[i] = Slot { index: at, es: start, ef: start + dur, ls: 0i64, lf: 0i64, slack: 0i64, critical: false }
        if start + dur > project { project = start + dur }
        i += 1usize
    }
    // Backward pass over the reverse order; a successor edge is any task listing this one as a predecessor.
    i = n
    while i > 0usize {
        i -= 1usize
        let at = order[i]
        let dur = duration_of(tasks[at])
        var finish = project
        var any = false
        var k = 0usize
        while k < n {
            let t = tasks[k]
            var d = 0usize
            while d < t.deps.len {
                if str.eq(t.deps[d].id, tasks[at].id) {
                    let s = slots[position[k]]
                    let candidate = latest_finish_under(t.deps[d], s.ls, s.lf, dur)
                    if !any || candidate < finish { finish = candidate }
                    any = true
                }
                d += 1usize
            }
            k += 1usize
        }
        slots[i].lf = finish
        slots[i].ls = finish - dur
        slots[i].slack = slots[i].ls - slots[i].es
        slots[i].critical = slots[i].slack == 0i64
    }
    ret CriticalPath { order: order[0usize..n], slots: slots[0usize..n], project_duration: project, cycle: "", has_cycle: false }
}

// --- the Gantt layout ---------------------------------------------------------------------------------------------

// A saved baseline entry, by task id; the instants are epoch milliseconds.
type Baseline = struct { id: str, start_ms: i64, has_start: bool, end_ms: i64, has_end: bool }

type Bar = struct {
    id: str,
    name: str,
    start_offset: i64,
    duration: i64,
    start_day: i64,
    end_day: i64,
    slack: i64,
    critical: bool,
    milestone: bool,
    progress: f64,
    has_baseline: bool,
    baseline_start_ms: i64,
    has_baseline_start: bool,
    baseline_end_ms: i64,
    has_baseline_end: bool,
    variance: i64,
    has_variance: bool,
}

type Layout = struct { bars: []const Bar, project_duration: i64, critical: []const usize, start_day: i64, end_day: i64, cycle: str, has_cycle: bool }

// 0-1 or 0-100 clamped; anything that is not a finite number is 0.
fn normalize_progress(value: f64) -> f64 {
    if !is_finite(value) { ret 0.0f64 }
    var n = value
    if value > 1.0f64 { n = value / 100.0f64 }
    if n < 0.0f64 { n = 0.0f64 }
    if n > 1.0f64 { n = 1.0f64 }
    ret n
}

// `Math.round` of a millisecond difference in days.
fn days_between_ms(a_ms: i64, b_ms: i64) -> i64 {
    let x = f64(b_ms - a_ms) / 86400000.0f64
    ret i64(math.floor[f64](x + 0.5f64))
}

fn find_baseline(entries: []const Baseline, id: str) -> (Baseline, bool) {
    var none = Baseline { id: "", start_ms: 0i64, has_start: false, end_ms: 0i64, has_end: false }
    var i = 0usize
    while i < entries.len {
        if str.eq(entries[i].id, id) { ret (entries[i], true) }
        i += 1usize
    }
    ret (none, false)
}

// Resolve every task's dates from the project start (an epoch-millisecond instant; the epoch when `has_start` is
// false) and the earliest-start offsets. Bars are in task order.
fn gantt_layout(a: *mem.Arena, tasks: []const Task, cal: Calendar, project_start_ms: i64, has_start: bool, baseline: []const Baseline) -> Layout {
    var none_bars: []const Bar = zero
    var none_ids: []const usize = zero
    let cpm = critical_path(a, tasks)
    if cpm.has_cycle {
        ret Layout { bars: none_bars, project_duration: 0i64, critical: none_ids, start_day: 0i64, end_day: 0i64, cycle: cpm.cycle, has_cycle: true }
    }
    var origin_ms = 0i64
    if has_start { origin_ms = project_start_ms }
    let origin = day_of_ms(origin_ms)
    let n = tasks.len
    let (bars, e1) = mem.alloc[Bar](a, n + 1usize)
    let (critical, e2) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok || e2 != ok {
        ret Layout { bars: none_bars, project_duration: 0i64, critical: none_ids, start_day: origin, end_day: origin, cycle: "", has_cycle: false }
    }
    // Slots are in topological order; find a task's by index.
    var i = 0usize
    while i < n {
        var slot = cpm.slots[0usize]
        var s = 0usize
        while s < cpm.slots.len {
            if cpm.slots[s].index == i { slot = cpm.slots[s] }
            s += 1usize
        }
        let t = tasks[i]
        let dur = duration_of(t)
        let start_day = add_working_days(cal, origin, slot.es)
        let end_day = add_working_days(cal, origin, slot.ef)
        var bar = Bar {
            id: t.id, name: t.name, start_offset: slot.es, duration: dur, start_day: start_day, end_day: end_day,
            slack: slot.slack, critical: slot.critical, milestone: dur == 0i64 || t.milestone,
            progress: normalize_progress(t.progress), has_baseline: false, baseline_start_ms: 0i64,
            has_baseline_start: false, baseline_end_ms: 0i64, has_baseline_end: false, variance: 0i64, has_variance: false,
        }
        let (base, found) = find_baseline(baseline, t.id)
        if found {
            bar.has_baseline = true
            bar.baseline_start_ms = base.start_ms
            bar.has_baseline_start = base.has_start
            bar.baseline_end_ms = base.end_ms
            bar.has_baseline_end = base.has_end
            if base.has_end {
                bar.variance = days_between_ms(base.end_ms, end_day * DAY_MS)
                bar.has_variance = true
            }
        }
        bars[i] = bar
        i += 1usize
    }
    var count = 0usize
    i = 0usize
    while i < cpm.slots.len {
        if cpm.slots[i].critical {
            critical[count] = cpm.slots[i].index
            count += 1usize
        }
        i += 1usize
    }
    ret Layout {
        bars: bars[0usize..n], project_duration: cpm.project_duration, critical: critical[0usize..count],
        start_day: origin, end_day: add_working_days(cal, origin, cpm.project_duration), cycle: "", has_cycle: false,
    }
}

// The baseline a layout's present dates make.
fn capture_baseline(a: *mem.Arena, layout: Layout) -> []const Baseline {
    var none: []const Baseline = zero
    let (out, e) = mem.alloc[Baseline](a, layout.bars.len + 1usize)
    if e != ok { ret none }
    var i = 0usize
    while i < layout.bars.len {
        let b = layout.bars[i]
        out[i] = Baseline { id: b.id, start_ms: b.start_day * DAY_MS, has_start: true, end_ms: b.end_day * DAY_MS, has_end: true }
        i += 1usize
    }
    ret out[0usize..layout.bars.len]
}

// --- progress roll-up ---------------------------------------------------------------------------------------------

type Roll = struct { values: []f64, done: []bool, seen: []bool }

fn roll_task(tasks: []const Task, r: *Roll, at: usize) -> f64 {
    if r.done[at] { ret r.values[at] }
    // A cyclic parent chain falls back to the declared value rather than recursing forever.
    if r.seen[at] { ret normalize_progress(tasks[at].progress) }
    r.seen[at] = true
    var weighted = 0.0f64
    var total = 0.0f64
    var any = false
    var k = 0usize
    while k < tasks.len {
        if tasks[k].has_parent && str.eq(tasks[k].parent, tasks[at].id) {
            any = true
            let weight = f64(duration_of(tasks[k]))
            weighted += roll_task(tasks, r, k) * weight
            total += weight
        }
        k += 1usize
    }
    var value = normalize_progress(tasks[at].progress)
    if any && total > 0.0f64 { value = weighted / total }
    r.values[at] = value
    r.done[at] = true
    ret value
}

// A parent's progress from its children, weighted by duration; a parent with no child duration keeps its own.
fn roll_up_progress(a: *mem.Arena, tasks: []const Task) -> []const f64 {
    var none: []const f64 = zero
    let n = tasks.len
    let (values, e1) = mem.alloc[f64](a, n + 1usize)
    let (done, e2) = mem.alloc[bool](a, n + 1usize)
    let (seen, e3) = mem.alloc[bool](a, n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret none }
    var i = 0usize
    while i < n {
        values[i] = 0.0f64
        done[i] = false
        seen[i] = false
        i += 1usize
    }
    var r = Roll { values: values, done: done, seen: seen }
    i = 0usize
    while i < n {
        // Each top-level resolve starts with a fresh seen set.
        var j = 0usize
        while j < n {
            r.seen[j] = false
            j += 1usize
        }
        let _ = roll_task(tasks, &r, i)
        i += 1usize
    }
    ret values[0usize..n]
}

// --- the month grid -----------------------------------------------------------------------------------------------

// An event's span, epoch milliseconds; `has_start` is false when the record carries no valid start.
type Event = struct { id: str, start_ms: i64, has_start: bool, end_ms: i64, has_end: bool }

// `day` is 0 for a padding cell; `events` are indices into the event list, in its order.
type Cell = struct { day: i64, events: []const usize }

type Month = struct { year: i64, month: i64, weeks: []const Cell }

fn civil_days(year: i64, month: i64, day: i64) -> i64 {
    var y = year
    if month <= 2i64 { y -= 1i64 }
    let era = floor_div(y, 400i64)
    let yoe = y - era * 400i64
    var mp = month - 3i64
    if month <= 2i64 { mp = month + 9i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + day - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

fn days_in_month(year: i64, month: i64) -> i64 {
    var next_year = year
    var next_month = month + 1i64
    if next_month == 13i64 {
        next_month = 1i64
        next_year += 1i64
    }
    ret civil_days(next_year, next_month, 1i64) - civil_days(year, month, 1i64)
}

// The weeks (rows of seven cells) of a month, `month` 1-12 and `week_start` 0 for Sunday, each covered day listing
// the events whose span includes it. The cells are returned flat, a multiple of seven.
fn calendar_layout(a: *mem.Arena, events: []const Event, year: i64, month: i64, week_start: i64) -> Month {
    var none: []const Cell = zero
    let total_days = days_in_month(year, month)
    let first = civil_days(year, month, 1i64)
    var leading = (weekday_of(first) - week_start + 7i64) % 7i64
    if leading < 0i64 { leading += 7i64 }
    var cell_count = usize(leading + total_days)
    while cell_count % 7usize != 0usize { cell_count += 1usize }
    let (cells, e1) = mem.alloc[Cell](a, cell_count + 1usize)
    if e1 != ok { ret Month { year: year, month: month, weeks: none } }
    var none_events: []const usize = zero
    var i = 0usize
    while i < cell_count {
        cells[i] = Cell { day: 0i64, events: none_events }
        i += 1usize
    }
    var d = 1i64
    while d <= total_days {
        let day = first + d - 1i64
        // Count then fill the events covering this day.
        var count = 0usize
        var k = 0usize
        while k < events.len {
            let ev = events[k]
            if ev.has_start {
                var end_ms = ev.start_ms
                if ev.has_end { end_ms = ev.end_ms }
                if day >= day_of_ms(ev.start_ms) && day <= day_of_ms(end_ms) { count += 1usize }
            }
            k += 1usize
        }
        let (list, e2) = mem.alloc[usize](a, count + 1usize)
        if e2 != ok { ret Month { year: year, month: month, weeks: none } }
        var n = 0usize
        k = 0usize
        while k < events.len {
            let ev = events[k]
            if ev.has_start {
                var end_ms = ev.start_ms
                if ev.has_end { end_ms = ev.end_ms }
                if day >= day_of_ms(ev.start_ms) && day <= day_of_ms(end_ms) {
                    list[n] = k
                    n += 1usize
                }
            }
            k += 1usize
        }
        cells[usize(leading + d - 1i64)] = Cell { day: d, events: list[0usize..n] }
        d += 1i64
    }
    ret Month { year: year, month: month, weeks: cells[0usize..cell_count] }
}

// --- workload -----------------------------------------------------------------------------------------------------

// `hours` is the declared effort, or has_hours false for the 8-hour default.
type Assignment = struct { assignee: str, start_ms: i64, has_start: bool, end_ms: i64, has_end: bool, hours: f64, has_hours: bool }

type CapacityOverride = struct { assignee: str, capacity: f64 }

type DayLoad = struct { day: i64, hours: f64 }

type Load = struct { assignee: str, days: []const DayLoad }

type Over = struct { assignee: str, day: i64, hours: f64, over: f64, capacity: f64 }

type Workload = struct { per_assignee: []const Load, overallocated: []const Over }

fn capacity_for(overrides: []const CapacityOverride, assignee: str, fallback: f64) -> f64 {
    var i = 0usize
    while i < overrides.len {
        if str.eq(overrides[i].assignee, assignee) && is_finite(overrides[i].capacity) { ret overrides[i].capacity }
        i += 1usize
    }
    ret fallback
}

// Total allocated effort per assignee per day, the days a non-working calendar excludes carrying none, and the
// days over capacity. `count_mode` counts records rather than effort. Assignees and their days keep the order
// appdor's objects keep: first seen.
fn workload(a: *mem.Arena, assignments: []const Assignment, capacity: f64, overrides: []const CapacityOverride, count_mode: bool, cal: Calendar) -> Workload {
    var none_loads: []const Load = zero
    var none_over: []const Over = zero
    let empty = Workload { per_assignee: none_loads, overallocated: none_over }
    var cell_total = 0usize
    var i = 0usize
    while i < assignments.len {
        let x = assignments[i]
        if x.has_start {
            var end_ms = x.start_ms
            if x.has_end { end_ms = x.end_ms }
            let span = days_between_ms(x.start_ms, end_ms)
            if span >= 0i64 { cell_total += usize(span) + 1usize }
        }
        i += 1usize
    }
    let (loads, e1) = mem.alloc[Load](a, assignments.len + 1usize)
    let (cells, e2) = mem.alloc[DayLoad](a, cell_total + 1usize)
    let (over, e3) = mem.alloc[Over](a, cell_total + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret empty }
    var none_days: []const DayLoad = zero
    var people = 0usize
    i = 0usize
    while i < assignments.len {
        let x = assignments[i]
        if x.has_start {
            var seen = false
            var p = 0usize
            while p < people {
                if str.eq(loads[p].assignee, x.assignee) { seen = true }
                p += 1usize
            }
            if !seen {
                loads[people] = Load { assignee: x.assignee, days: none_days }
                people += 1usize
            }
        }
        i += 1usize
    }
    var used = 0usize
    var p = 0usize
    while p < people {
        let start = used
        var n = 0usize
        i = 0usize
        while i < assignments.len {
            let x = assignments[i]
            if x.has_start && str.eq(x.assignee, loads[p].assignee) {
                var end_ms = x.start_ms
                if x.has_end { end_ms = x.end_ms }
                var per_day = 8.0f64
                if count_mode { per_day = 1.0f64 } else if x.has_hours && is_finite(x.hours) { per_day = x.hours }
                let span = days_between_ms(x.start_ms, end_ms)
                var d = 0i64
                while d <= span {
                    let day = day_of_ms(x.start_ms + d * DAY_MS)
                    if is_working_day(cal, day) {
                        var at = n
                        var k = 0usize
                        while k < n {
                            if cells[start + k].day == day { at = k }
                            k += 1usize
                        }
                        if at == n {
                            cells[start + n] = DayLoad { day: day, hours: per_day }
                            n += 1usize
                        } else {
                            cells[start + at].hours += per_day
                        }
                    }
                    d += 1i64
                }
            }
            i += 1usize
        }
        loads[p].days = cells[start..start + n]
        used = start + n
        p += 1usize
    }
    var over_count = 0usize
    p = 0usize
    while p < people {
        let limit = capacity_for(overrides, loads[p].assignee, capacity)
        var d = 0usize
        while d < loads[p].days.len {
            let hours = loads[p].days[d].hours
            if hours > limit {
                over[over_count] = Over { assignee: loads[p].assignee, day: loads[p].days[d].day, hours: hours, over: hours - limit, capacity: limit }
                over_count += 1usize
            }
            d += 1usize
        }
        p += 1usize
    }
    ret Workload { per_assignee: loads[0usize..people], overallocated: over[0usize..over_count] }
}

// --- cascading a reschedule ---------------------------------------------------------------------------------------

type Window = struct { id: str, es: i64, ef: i64 }

type Move = struct { id: str, from: i64, to: i64, shift: i64 }

fn window_index(items: []const Window, id: str) -> (usize, bool) {
    var i = 0usize
    while i < items.len {
        if str.eq(items[i].id, id) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn cascade_duration(tasks: []const Task, schedule: []const Window, id: str) -> i64 {
    let (t, found) = index_of(tasks, id)
    if !found { ret 0i64 }
    if tasks[t].has_duration {
        if tasks[t].duration < 0i64 { ret 0i64 }
        ret tasks[t].duration
    }
    let (s, have) = window_index(schedule, id)
    if !have { ret 0i64 }
    let len = schedule[s].ef - schedule[s].es
    if len < 0i64 { ret 0i64 }
    ret len
}

// The minimal set of follow-on moves that restores every constraint when `change_id` starts at `change_start`:
// successors are only ever pushed later, and the result is a diff of `{id, from, to, shift}`, the moved task
// first, with zero shifts dropped.
fn cascade_reschedule(a: *mem.Arena, tasks: []const Task, schedule: []const Window, change_id: str, change_start: i64) -> []const Move {
    var none: []const Move = zero
    let (changed, known) = index_of(tasks, change_id)
    if !known { ret none }
    let n = schedule.len
    let t = tasks.len
    let (next, e1) = mem.alloc[Window](a, n + 2usize)
    let (moves, e2) = mem.alloc[Move](a, n + t + 2usize)
    let (queue, e3) = mem.alloc[usize](a, t * t + t + 4usize)
    if e1 != ok || e2 != ok || e3 != ok { ret none }
    var i = 0usize
    while i < n {
        next[i] = Window { id: schedule[i].id, es: schedule[i].es, ef: schedule[i].ef }
        i += 1usize
    }
    var total = n
    let (found_slot, have_moved) = window_index(next[0usize..total], change_id)
    var moved_slot = found_slot
    if !have_moved {
        next[total] = Window { id: change_id, es: 0i64, ef: 0i64 }
        moved_slot = total
        total += 1usize
    }
    let own = cascade_duration(tasks, schedule, change_id)
    next[moved_slot] = Window { id: change_id, es: change_start, ef: change_start + own }
    var move_count = 0usize
    var head = 0usize
    var tail = 0usize
    queue[tail] = changed
    tail += 1usize
    var guard = t * t + t
    while head < tail {
        if guard == 0usize { break }
        guard -= 1usize
        let current = queue[head]
        head += 1usize
        let (cur_slot, cur_known) = window_index(next[0usize..total], tasks[current].id)
        // Successors: tasks listing `current` as a predecessor, in task order and dependency order.
        var k = 0usize
        while k < t {
            var d = 0usize
            while d < tasks[k].deps.len {
                if str.eq(tasks[k].deps[d].id, tasks[current].id) && cur_known {
                    let (slot, present) = window_index(next[0usize..total], tasks[k].id)
                    if present {
                        let dur = cascade_duration(tasks, schedule, tasks[k].id)
                        let required = earliest_start_under(tasks[k].deps[d], next[cur_slot].es, next[cur_slot].ef, dur)
                        if required > next[slot].es {
                            let (orig_slot, in_schedule) = window_index(schedule, tasks[k].id)
                            var from = next[slot].es
                            if in_schedule { from = schedule[orig_slot].es }
                            next[slot] = Window { id: tasks[k].id, es: required, ef: required + dur }
                            var at = move_count
                            var m = 0usize
                            while m < move_count {
                                if str.eq(moves[m].id, tasks[k].id) { at = m }
                                m += 1usize
                            }
                            if at == move_count {
                                moves[move_count] = Move { id: tasks[k].id, from: from, to: required, shift: required - from }
                                move_count += 1usize
                            } else {
                                moves[at].to = required
                                moves[at].shift = required - from
                            }
                            if tail < queue.len {
                                queue[tail] = k
                                tail += 1usize
                            }
                        }
                    }
                }
                d += 1usize
            }
            k += 1usize
        }
    }
    var origin = change_start
    let (orig, in_original) = window_index(schedule, change_id)
    if in_original { origin = schedule[orig].es }
    let (out, e4) = mem.alloc[Move](a, move_count + 1usize)
    if e4 != ok { ret none }
    var kept = 0usize
    if change_start - origin != 0i64 {
        out[kept] = Move { id: change_id, from: origin, to: change_start, shift: change_start - origin }
        kept += 1usize
    }
    i = 0usize
    while i < move_count {
        if moves[i].shift != 0i64 {
            out[kept] = moves[i]
            kept += 1usize
        }
        i += 1usize
    }
    ret out[0usize..kept]
}
