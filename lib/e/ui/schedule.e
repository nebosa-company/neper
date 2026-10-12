// `e.ui.schedule` (L148): the model of a scheduler control -- day, week and agenda views
// of appointments, with recurrence, overlap columns, hit regions, drag-to-create and an
// accessible tree -- over `e.time.calendar` and the RFC 5545 rules of `e.time.recur`.
// `build` is a pure function from items and a `Config` to a `Layout` in caller storage,
// so every rectangle, lane and row is data a fixture can compare with an independent model.
//
// Items and recurrence: an `Item` is a start, a length in minutes (an all-day item is
// whole days, at least one) and an optional rule text (`FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6`),
// expanded from the item's start with `recur.expand_from` for the days in view; the rule's
// time of day is the item's unless the rule sets BYHOUR/BYMINUTE. An occurrence is shown
// on every day it overlaps (`before`/`after` mark the cut ends); in a time grid it is
// clipped to the hours `day_start..day_end` and one wholly outside them is not placed.
//
// Time grid (Day, Week): the week starts on `week_start`; the columns split `width` less
// the `gutter` evenly; above the grid are the header row and an all-day band as tall as
// its fullest day needs. Timed occurrences of a column are sorted by start, longer first,
// then item order; a run of transitively overlapping ones is a cluster whose occurrences
// take the first free lane, and share the column width by the cluster's lane count. Height
// follows `hour_h`, never below `min_h`.
//
// Agenda: the `agenda_days` from the anchor, each day with something on it a header row
// then its occurrences (all-day first, then by start and item), every row `row_h`.
//
// Input: `slot_at` and `drag_range` turn a pointer position into snapped day and minute
// ranges (the drag-to-create gesture), `hit` names what is under a point.
//
// ponytail: English day and month names in the accessible labels (a locale table would
// replace them); floating times, no zones; items' seconds are ignored; the occurrence
// scratch caps an endless rule at its capacity and says so in `truncated`; sorting is an
// insertion sort over one day's occurrences.

use e.time
use e.time.calendar
use e.time.recur
use e.ui.accessibility

type Mode = enum u8 { Day, Week, Agenda }
type Kind = enum u8 { Timed, AllDay }
type RowKind = enum u8 { DayHeader, Event }
type HitKind = enum u8 { None, Event, AllDay, Slot, DayHeader, Gutter }

type Item = struct { id: u32, start: calendar.DateTime, minutes: u32, all_day: bool, title: str, rule: str }
type Config = struct { mode: Mode, anchor: time.Date, week_start: calendar.Weekday, day_start: u32, day_end: u32, slot: u32, agenda_days: u32, width: f32, gutter: f32, header: f32, all_day_h: f32, hour_h: f32, row_h: f32, min_h: f32 }
// `start` and `end` are absolute minutes (day count * 1440 + minute of day); `x, y, w, h`
// the rectangle; `day` the column (or the agenda day) and `lane` of `lanes` the overlap column.
type Placed = struct { item: u32, kind: Kind, day: u32, start: i64, end: i64, x: f32, y: f32, w: f32, h: f32, lane: u32, lanes: u32, before: bool, after: bool, recurring: bool }
type Column = struct { date: time.Date, count: i64, x: f32, w: f32 }
type Row = struct { kind: RowKind, day: u32, placed: u32, y: f32, h: f32 }
type Access = struct { role: accessibility.Role, x: f32, y: f32, w: f32, h: f32, label_start: usize, label_len: usize, row: u32, column: u32, row_count: u32, column_count: u32, level: u8 }
type Hit = struct { kind: HitKind, index: usize, day: u32, minute: u32 }
type Slot = struct { day: u32, minute: u32, start: calendar.DateTime }
type Span = struct { day: u32, start: calendar.DateTime, minutes: u32 }
type Occ = struct { item: u32, start: i64, minutes: i64, recurring: bool, all_day: bool }
type Storage = struct { occ: []Occ, stamps: []calendar.DateTime, placed: []Placed, columns: []Column, rows: []Row, nodes: []Access, labels: []u8, order: []u32, lane_end: []i64 }
type Layout = struct { cfg: Config, placed: []Placed, columns: []Column, rows: []Row, nodes: []Access, labels: []u8, placed_count: usize, column_count: usize, row_count: usize, node_count: usize, labels_len: usize, band_h: f32, grid_top: f32, height: f32, first_day: i64, days: i64, truncated: bool }

error TooLarge
error Invalid

fn abs_minutes(d: calendar.DateTime) -> i64 {
    ret calendar.day_count(d.date) * 1440i64 + i64(d.time.hour) * 60i64 + i64(d.time.minute)
}

fn datetime_of(abs: i64) -> calendar.DateTime {
    let day = time.floor_div(abs, 1440i64)
    let minute = abs - day * 1440i64
    var t: time.Time = zero
    t.hour = u8(minute / 60i64)
    t.minute = u8(minute % 60i64)
    ret calendar.DateTime { date: calendar.date_of(day), time: t }
}

fn max_i64(a: i64, b: i64) -> i64 {
    if a > b { ret a }
    ret b
}

fn min_i64(a: i64, b: i64) -> i64 {
    if a < b { ret a }
    ret b
}

// The first day of the range and its length in days.
fn range_of(cfg: Config) -> (i64, i64) {
    let anchor = calendar.day_count(cfg.anchor)
    if cfg.mode == .Day { ret (anchor, 1i64) }
    if cfg.mode == .Week {
        let behind = time.floor_mod(calendar.weekday_index(calendar.weekday_of_count(anchor)) - calendar.weekday_index(cfg.week_start), 7i64)
        ret (anchor - behind, 7i64)
    }
    ret (anchor, i64(cfg.agenda_days))
}

type Ctx = struct { st: Storage, cfg: Config, placed: usize, columns: usize, rows: usize, nodes: usize, labels: usize, occ: usize, truncated: bool, first: i64, days: i64, band: f32, height: f32 }

fn push_occ(c: *Ctx, item: u32, start: i64, minutes: i64, recurring: bool, all_day: bool) -> err {
    if start >= (c.first + c.days) * 1440i64 || start + minutes <= c.first * 1440i64 { ret ok }
    if c.occ >= c.st.occ.len { ret TooLarge }
    c.st.occ[c.occ] = Occ { item: item, start: start, minutes: minutes, recurring: recurring, all_day: all_day }
    c.occ += 1usize
    ret ok
}

fn collect(c: *Ctx, items: []const Item) -> err {
    var i = 0usize
    while i < items.len {
        let it = items[i]
        var minutes = i64(it.minutes)
        if minutes < 1i64 { minutes = 1i64 }
        var start = abs_minutes(it.start)
        if it.all_day {
            start = calendar.day_count(it.start.date) * 1440i64
            minutes = ((minutes + 1439i64) / 1440i64) * 1440i64
        }
        if it.rule.len == 0usize {
            try push_occ(c, u32(i), start, minutes, false, it.all_day)
        } else {
            let (rule, rule_error) = recur.parse_rule(it.rule)
            if rule_error != ok { ret Invalid }
            // Occurrences that began up to the item's length before the range still show.
            let back = (minutes + 1439i64) / 1440i64
            var floor_dt = datetime_of((c.first - back) * 1440i64)
            if calendar.compare(floor_dt, it.start) < 0i32 { floor_dt = it.start }
            let (n, expand_error) = recur.expand_from(rule, it.start, floor_dt, c.st.stamps)
            if expand_error != ok { ret Invalid }
            var k = 0usize
            while k < n {
                var at = abs_minutes(c.st.stamps[k])
                if it.all_day { at = calendar.day_count(c.st.stamps[k].date) * 1440i64 }
                try push_occ(c, u32(i), at, minutes, true, it.all_day)
                k += 1usize
            }
            if n == c.st.stamps.len && n > 0usize && abs_minutes(c.st.stamps[n - 1usize]) < (c.first + c.days) * 1440i64 { c.truncated = true }
        }
        i += 1usize
    }
    ret ok
}

// All-day before timed, then by start, longer first, then by item.
fn occ_before(c: *const Ctx, x: u32, y: u32) -> bool {
    let a = c.st.occ[usize(x)]
    let b = c.st.occ[usize(y)]
    if a.all_day != b.all_day { ret a.all_day }
    if a.start != b.start { ret a.start < b.start }
    if a.minutes != b.minutes { ret a.minutes > b.minutes }
    ret a.item < b.item
}

fn put_placed(c: *Ctx, p: Placed) -> err {
    if c.placed >= c.st.placed.len { ret TooLarge }
    c.st.placed[c.placed] = p
    c.placed += 1usize
    ret ok
}

// The occurrences overlapping the day starting at absolute minute `day0`, sorted into
// `order`; how many.
fn day_order(c: *Ctx, day0: i64) -> usize {
    var n = 0usize
    var i = 0usize
    while i < c.occ {
        let o = c.st.occ[i]
        if o.start < day0 + 1440i64 && o.start + o.minutes > day0 {
            var at = n
            while at > 0usize && occ_before(c, u32(i), c.st.order[at - 1usize]) {
                c.st.order[at] = c.st.order[at - 1usize]
                at -= 1usize
            }
            c.st.order[at] = u32(i)
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// One day of a time grid: all-day occurrences stacked in the band, timed ones in lanes.
fn place_day(c: *Ctx, d: usize, top: f32) -> err {
    let cfg = c.cfg
    let col = c.st.columns[d]
    let day0 = col.count * 1440i64
    let w0 = day0 + i64(cfg.day_start) * 60i64
    let w1 = day0 + i64(cfg.day_end) * 60i64
    let n = day_order(c, day0)
    var row = 0u32
    var i = 0usize
    while i < n {
        let o = c.st.occ[usize(c.st.order[i])]
        if o.all_day {
            try put_placed(c, Placed { item: o.item, kind: .AllDay, day: u32(d), start: o.start, end: o.start + o.minutes, x: col.x, y: cfg.header + f32(row) * cfg.all_day_h, w: col.w, h: cfg.all_day_h, lane: 0u32, lanes: 1u32, before: o.start < day0, after: o.start + o.minutes > day0 + 1440i64, recurring: o.recurring })
            row += 1u32
        }
        i += 1usize
    }
    var cluster_end = 0i64
    var cluster_first = c.placed
    var lanes_used = 0usize
    var started = false
    i = 0usize
    while i < n {
        let o = c.st.occ[usize(c.st.order[i])]
        if o.all_day {
            i += 1usize
            continue
        }
        let s = max_i64(o.start, w0)
        let e = min_i64(o.start + o.minutes, w1)
        if s >= e {
            i += 1usize
            continue
        }
        if !started || s >= cluster_end {
            var m = cluster_first
            while started && m < c.placed {
                c.st.placed[m].lanes = u32(lanes_used)
                m += 1usize
            }
            cluster_first = c.placed
            cluster_end = e
            lanes_used = 0usize
            started = true
        }
        if e > cluster_end { cluster_end = e }
        var lane = 0usize
        while lane < lanes_used && c.st.lane_end[lane] > s { lane += 1usize }
        if lane == lanes_used {
            if lane >= c.st.lane_end.len { ret TooLarge }
            lanes_used += 1usize
        }
        c.st.lane_end[lane] = e
        var h = f32(e - s) * cfg.hour_h / 60.0
        if h < cfg.min_h { h = cfg.min_h }
        try put_placed(c, Placed { item: o.item, kind: .Timed, day: u32(d), start: s, end: e, x: 0.0, y: top + f32(s - w0) * cfg.hour_h / 60.0, w: 0.0, h: h, lane: u32(lane), lanes: 1u32, before: o.start < day0, after: o.start + o.minutes > day0 + 1440i64, recurring: o.recurring })
        i += 1usize
    }
    var m = cluster_first
    while started && m < c.placed {
        c.st.placed[m].lanes = u32(lanes_used)
        m += 1usize
    }
    // Lane geometry from each cluster's lane count.
    var k = 0usize
    while k < c.placed {
        let p = c.st.placed[k]
        if p.day == u32(d) && p.kind == .Timed {
            let share = col.w / f32(p.lanes)
            c.st.placed[k].w = share
            c.st.placed[k].x = col.x + f32(p.lane) * share
        }
        k += 1usize
    }
    ret ok
}

fn weekday_name(index: i64) -> str {
    if index == 0i64 { ret "Monday" }
    if index == 1i64 { ret "Tuesday" }
    if index == 2i64 { ret "Wednesday" }
    if index == 3i64 { ret "Thursday" }
    if index == 4i64 { ret "Friday" }
    if index == 5i64 { ret "Saturday" }
    ret "Sunday"
}

fn month_name(month: u8) -> str {
    if month == 1u8 { ret "January" }
    if month == 2u8 { ret "February" }
    if month == 3u8 { ret "March" }
    if month == 4u8 { ret "April" }
    if month == 5u8 { ret "May" }
    if month == 6u8 { ret "June" }
    if month == 7u8 { ret "July" }
    if month == 8u8 { ret "August" }
    if month == 9u8 { ret "September" }
    if month == 10u8 { ret "October" }
    if month == 11u8 { ret "November" }
    ret "December"
}

fn put_label(c: *Ctx, s: str) -> err {
    if c.labels + s.len > c.st.labels.len { ret TooLarge }
    var i = 0usize
    while i < s.len {
        c.st.labels[c.labels + i] = s[i]
        i += 1usize
    }
    c.labels += s.len
    ret ok
}

fn put_number(c: *Ctx, v: i64, width: usize) -> err {
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = v
    if rest == 0i64 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while rest > 0i64 {
        digits[count] = 48u8 + u8(rest % 10i64)
        rest = rest / 10i64
        count += 1usize
    }
    while count < width {
        digits[count] = 48u8
        count += 1usize
    }
    var out: [20]u8 = zero
    var i = 0usize
    while i < count {
        out[i] = digits[count - 1usize - i]
        i += 1usize
    }
    ret put_label(c, out[0usize..count])
}

// "Monday 12 October 2026".
fn put_date(c: *Ctx, count: i64) -> err {
    let date = calendar.date_of(count)
    try put_label(c, weekday_name(calendar.weekday_index(calendar.weekday_of_count(count))))
    try put_label(c, " ")
    try put_number(c, i64(date.day), 1usize)
    try put_label(c, " ")
    try put_label(c, month_name(date.month))
    try put_label(c, " ")
    ret put_number(c, i64(date.year), 1usize)
}

fn put_clock(c: *Ctx, abs: i64) -> err {
    let minute = abs - time.floor_div(abs, 1440i64) * 1440i64
    try put_number(c, minute / 60i64, 2usize)
    try put_label(c, ":")
    ret put_number(c, minute % 60i64, 2usize)
}

// "Title, 09:00 to 10:30" (all-day items: "Title, all day"), "(repeats)" on a recurrence.
fn put_event_label(c: *Ctx, items: []const Item, p: Placed) -> err {
    try put_label(c, items[usize(p.item)].title)
    if p.kind == .AllDay {
        try put_label(c, ", all day")
    } else {
        try put_label(c, ", ")
        try put_clock(c, p.start)
        try put_label(c, " to ")
        try put_clock(c, p.end)
    }
    if p.recurring { try put_label(c, ", repeats") }
    ret ok
}

fn put_node(c: *Ctx, role: accessibility.Role, x: f32, y: f32, w: f32, h: f32, label_start: usize, row: u32, column: u32, row_count: u32, column_count: u32, level: u8) -> err {
    if c.nodes >= c.st.nodes.len { ret TooLarge }
    c.st.nodes[c.nodes] = Access { role: role, x: x, y: y, w: w, h: h, label_start: label_start, label_len: c.labels - label_start, row: row, column: column, row_count: row_count, column_count: column_count, level: level }
    c.nodes += 1usize
    ret ok
}

fn build_grid(c: *Ctx, items: []const Item) -> err {
    let cfg = c.cfg
    let columns = usize(c.days)
    if columns > c.st.columns.len { ret TooLarge }
    let col_w = (cfg.width - cfg.gutter) / f32(c.days)
    var d = 0usize
    var band_rows = 0usize
    while d < columns {
        let day = c.first + i64(d)
        c.st.columns[d] = Column { date: calendar.date_of(day), count: day, x: cfg.gutter + f32(d) * col_w, w: col_w }
        // The band needs a row for each all-day occurrence of a day.
        var rows_here = 0usize
        var i = 0usize
        while i < c.occ {
            let o = c.st.occ[i]
            if o.all_day && o.start < day * 1440i64 + 1440i64 && o.start + o.minutes > day * 1440i64 { rows_here += 1usize }
            i += 1usize
        }
        if rows_here > band_rows { band_rows = rows_here }
        d += 1usize
    }
    c.columns = columns
    let band = f32(band_rows) * cfg.all_day_h
    let top = cfg.header + band
    d = 0usize
    while d < columns {
        try place_day(c, d, top)
        d += 1usize
    }
    // The accessible tree: grid, a header per day, its occurrences as cells.
    let grid_h = top + f32(cfg.day_end - cfg.day_start) * cfg.hour_h
    var start = c.labels
    if cfg.mode == .Day {
        try put_label(c, "Day schedule")
    } else {
        try put_label(c, "Week schedule")
    }
    try put_node(c, .Grid, 0.0, 0.0, cfg.width, grid_h, start, 0u32, 0u32, u32(c.placed), u32(columns), 0u8)
    d = 0usize
    while d < columns {
        start = c.labels
        try put_date(c, c.st.columns[d].count)
        try put_node(c, .ColumnHeader, c.st.columns[d].x, 0.0, c.st.columns[d].w, cfg.header, start, 0u32, u32(d + 1usize), 0u32, u32(columns), 0u8)
        var in_day = 0u32
        var k = 0usize
        while k < c.placed {
            if c.st.placed[k].day == u32(d) { in_day += 1u32 }
            k += 1usize
        }
        var seen = 0u32
        k = 0usize
        while k < c.placed {
            let p = c.st.placed[k]
            if p.day == u32(d) {
                seen += 1u32
                start = c.labels
                try put_event_label(c, items, p)
                try put_node(c, .Cell, p.x, p.y, p.w, p.h, start, seen, u32(d + 1usize), in_day, u32(columns), 0u8)
            }
            k += 1usize
        }
        d += 1usize
    }
    c.band = band
    c.height = grid_h
    ret ok
}

fn build_agenda(c: *Ctx, items: []const Item) -> err {
    let cfg = c.cfg
    var y: f32 = 0.0
    var start = c.labels
    try put_label(c, "Agenda")
    var d = 0usize
    // The list node is filled in once the rows are known; reserve its slot first.
    let list_slot = c.nodes
    try put_node(c, .List, 0.0, 0.0, cfg.width, 0.0, start, 0u32, 0u32, 0u32, 1u32, 0u8)
    var total_events = 0u32
    while i64(d) < c.days {
        let day = c.first + i64(d)
        let n = day_order(c, day * 1440i64)
        if n > 0usize {
            if c.rows >= c.st.rows.len { ret TooLarge }
            c.st.rows[c.rows] = Row { kind: .DayHeader, day: u32(d), placed: 0u32, y: y, h: cfg.row_h }
            c.rows += 1usize
            start = c.labels
            try put_date(c, day)
            try put_node(c, .Heading, 0.0, y, cfg.width, cfg.row_h, start, 0u32, 0u32, 0u32, 1u32, 2u8)
            y += cfg.row_h
            var i = 0usize
            while i < n {
                let o = c.st.occ[usize(c.st.order[i])]
                var kind: Kind = .Timed
                if o.all_day { kind = .AllDay }
                let s = max_i64(o.start, day * 1440i64)
                let e = min_i64(o.start + o.minutes, day * 1440i64 + 1440i64)
                let index = c.placed
                try put_placed(c, Placed { item: o.item, kind: kind, day: u32(d), start: s, end: e, x: 0.0, y: y, w: cfg.width, h: cfg.row_h, lane: 0u32, lanes: 1u32, before: o.start < day * 1440i64, after: o.start + o.minutes > day * 1440i64 + 1440i64, recurring: o.recurring })
                if c.rows >= c.st.rows.len { ret TooLarge }
                c.st.rows[c.rows] = Row { kind: .Event, day: u32(d), placed: u32(index), y: y, h: cfg.row_h }
                c.rows += 1usize
                start = c.labels
                try put_event_label(c, items, c.st.placed[index])
                try put_node(c, .ListItem, 0.0, y, cfg.width, cfg.row_h, start, 0u32, 0u32, 0u32, 1u32, 0u8)
                total_events += 1u32
                y += cfg.row_h
                i += 1usize
            }
        }
        d += 1usize
    }
    c.st.nodes[list_slot].h = y
    c.st.nodes[list_slot].row_count = total_events
    c.height = y
    ret ok
}

// Lays the items out for `cfg` into `st`. Errors: `Invalid` (a rule that does not parse or
// an inverted hour window), `TooLarge` (a storage slice, or an `order` shorter than one
// day's occurrences).
fn build(items: []const Item, cfg: Config, st: Storage) -> (Layout, err) {
    if cfg.day_start >= cfg.day_end || cfg.day_end > 24u32 || cfg.slot == 0u32 || cfg.width <= cfg.gutter { ret (zero, Invalid) }
    let (first, days) = range_of(cfg)
    if days < 1i64 { ret (zero, Invalid) }
    var c = Ctx { st: st, cfg: cfg, placed: 0usize, columns: 0usize, rows: 0usize, nodes: 0usize, labels: 0usize, occ: 0usize, truncated: false, first: first, days: days, band: 0.0, height: 0.0 }
    if st.rows.len == 0usize || st.order.len < st.occ.len { ret (zero, TooLarge) }
    try collect(&c, items)
    if cfg.mode == .Agenda {
        try build_agenda(&c, items)
    } else {
        try build_grid(&c, items)
    }
    ret (Layout { cfg: cfg, placed: st.placed, columns: st.columns, rows: st.rows, nodes: st.nodes, labels: st.labels, placed_count: c.placed, column_count: c.columns, row_count: c.rows, node_count: c.nodes, labels_len: c.labels, band_h: c.band, grid_top: cfg.header + c.band, height: c.height, first_day: first, days: days, truncated: c.truncated }, ok)
}

fn label_of(l: *const Layout, node: usize) -> str {
    let n = l.nodes[node]
    ret l.labels[n.label_start..n.label_start + n.label_len]
}

// The day column and snapped minute of day (a multiple of `slot`, from `day_start`) under
// a point of a time grid.
fn slot_at(l: *const Layout, x: f32, y: f32) -> (Slot, bool) {
    var s: Slot = zero
    if l.cfg.mode == .Agenda || y < l.grid_top || x < l.cfg.gutter { ret (s, false) }
    let bottom = l.grid_top + f32(l.cfg.day_end - l.cfg.day_start) * l.cfg.hour_h
    if y >= bottom || x >= l.cfg.width { ret (s, false) }
    var d = 0usize
    while d < l.column_count {
        let col = l.columns[d]
        if x >= col.x && x < col.x + col.w {
            let raw = u32((y - l.grid_top) * 60.0 / l.cfg.hour_h)
            let snapped = raw / l.cfg.slot * l.cfg.slot + l.cfg.day_start * 60u32
            let abs = col.count * 1440i64 + i64(snapped)
            ret (Slot { day: u32(d), minute: snapped, start: datetime_of(abs) }, true)
        }
        d += 1usize
    }
    ret (s, false)
}

// A drag from one point to another as a new appointment: the start column, the start
// snapped down and the end snapped up to `slot`, at least one slot long and kept inside
// the day window.
fn drag_range(l: *const Layout, x0: f32, y0: f32, x1: f32, y1: f32) -> (Span, bool) {
    var out: Span = zero
    let (a, a_ok) = slot_at(l, x0, y0)
    if !a_ok { ret (out, false) }
    var yy = y1
    let bottom = l.grid_top + f32(l.cfg.day_end - l.cfg.day_start) * l.cfg.hour_h
    if yy < l.grid_top { yy = l.grid_top }
    if yy >= bottom { yy = bottom - 0.001 }
    let lo_raw = u32((y0 - l.grid_top) * 60.0 / l.cfg.hour_h)
    let hi_raw = u32((yy - l.grid_top) * 60.0 / l.cfg.hour_h)
    var first_raw = lo_raw
    var last_raw = hi_raw
    if hi_raw < lo_raw {
        first_raw = hi_raw
        last_raw = lo_raw
    }
    let slot = l.cfg.slot
    let begin = first_raw / slot * slot
    var finish = (last_raw + slot - 1u32) / slot * slot
    if finish <= begin { finish = begin + slot }
    let window = (l.cfg.day_end - l.cfg.day_start) * 60u32
    if finish > window { finish = window }
    let minute = begin + l.cfg.day_start * 60u32
    out.day = a.day
    out.minutes = finish - begin
    out.start = datetime_of(l.columns[usize(a.day)].count * 1440i64 + i64(minute))
    ret (out, true)
}

// What is under a point: the topmost placed occurrence, else the header, the gutter or
// an empty slot.
fn hit(l: *const Layout, x: f32, y: f32) -> Hit {
    var out: Hit = zero
    if y < 0.0 || x < 0.0 || x >= l.cfg.width { ret out }
    var i = l.placed_count
    while i > 0usize {
        i -= 1usize
        let p = l.placed[i]
        if x >= p.x && x < p.x + p.w && y >= p.y && y < p.y + p.h {
            out.index = i
            out.day = p.day
            out.kind = .Event
            if p.kind == .AllDay { out.kind = .AllDay }
            ret out
        }
    }
    if l.cfg.mode == .Agenda {
        var r = 0usize
        while r < l.row_count {
            let row = l.rows[r]
            if row.kind == .DayHeader && y >= row.y && y < row.y + row.h {
                out.kind = .DayHeader
                out.day = row.day
                out.index = r
                ret out
            }
            r += 1usize
        }
        ret out
    }
    if y < l.cfg.header {
        var d = 0usize
        while d < l.column_count {
            let col = l.columns[d]
            if x >= col.x && x < col.x + col.w {
                out.kind = .DayHeader
                out.day = u32(d)
                out.index = d
                ret out
            }
            d += 1usize
        }
        out.kind = .Gutter
        ret out
    }
    if x < l.cfg.gutter {
        out.kind = .Gutter
        ret out
    }
    let (s, found) = slot_at(l, x, y)
    if found {
        out.kind = .Slot
        out.day = s.day
        out.minute = s.minute
    }
    ret out
}
