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
// Month (`build_month`): the weeks of the anchor's month, as many as it spans (four to six),
// seven cells of `width / 7` by `cell_h`; a cell is its day number's line then one `line_h`
// line per occurrence (all-day first). When a day has more than `lines` occurrences the last
// line is the "+N more" line and the rest are placed with no area (`w` and `h` zero), so a
// popover can still list them. `hit_month` names header, cell, event or more-line.
//
// Bars: `all_day_bars` turns a grid layout's per-day all-day entries into one bar per
// occurrence, spanning its columns and stacked in lanes. Moving and resizing: `move_target`
// and `resize_target` turn a drag of a placed occurrence into its new start and length.
// Keyboard: `focus_next` and `month_move` step the focus among occurrences and cells.
//
// Names: the labels' words come from a `Names` (`english()` by default; `build_named` and
// `build_month_named` take another), so a locale is a table, not code.
//
// ponytail: floating times, no zones (a display zone and DST would convert each
// occurrence's instant); items' seconds are ignored; the occurrence scratch caps an endless
// rule at its capacity and says so in `truncated`; sorting is an insertion sort over one
// day's occurrences; painting and pointer capture are the control's, not this model's.

use e.time
use e.time.calendar
use e.time.recur
use e.ui.accessibility

type Mode = enum u8 { Day, Week, Agenda }
type Key = enum u8 { Left, Right, Up, Down, Home, End }
type MonthHitKind = enum u8 { None, Header, Cell, Event, More }
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

// The words of the accessible labels. `weekdays` start at Monday.
type Names = struct { weekdays: [7]str, months: [12]str, all_day: str, to: str, repeats: str, day_schedule: str, week_schedule: str, agenda: str, month_schedule: str, no_events: str, one_event: str, events: str, more: str }
type MonthConfig = struct { anchor: time.Date, week_start: calendar.Weekday, width: f32, header: f32, cell_h: f32, line_h: f32, lines: u32 }
// `count` is the cell's day count, `first` the index of its first occurrence in `placed`
// (its `total` follow it), `shown` how many have a line and `more` how many the "+N more" line
// stands for.
type MonthCell = struct { date: time.Date, count: i64, in_month: bool, x: f32, y: f32, w: f32, h: f32, first: u32, total: u32, shown: u32, more: u32 }
type MonthStorage = struct { occ: []Occ, stamps: []calendar.DateTime, placed: []Placed, cells: []MonthCell, order: []u32, nodes: []Access, labels: []u8 }
type MonthLayout = struct { cfg: MonthConfig, placed: []Placed, cells: []MonthCell, nodes: []Access, labels: []u8, placed_count: usize, cell_count: usize, node_count: usize, labels_len: usize, weeks: u32, first_day: i64, height: f32, truncated: bool }
type MonthHit = struct { kind: MonthHitKind, cell: u32, index: usize }
// One all-day occurrence over the columns `first..=last`; `lane` is its row in the band.
type Bar = struct { item: u32, first: u32, last: u32, lane: u32, x: f32, y: f32, w: f32, h: f32, before: bool, after: bool, recurring: bool }

error TooLarge
error Invalid

fn english() -> Names {
    var n: Names = zero
    n.weekdays[0usize] = "Monday"
    n.weekdays[1usize] = "Tuesday"
    n.weekdays[2usize] = "Wednesday"
    n.weekdays[3usize] = "Thursday"
    n.weekdays[4usize] = "Friday"
    n.weekdays[5usize] = "Saturday"
    n.weekdays[6usize] = "Sunday"
    n.months[0usize] = "January"
    n.months[1usize] = "February"
    n.months[2usize] = "March"
    n.months[3usize] = "April"
    n.months[4usize] = "May"
    n.months[5usize] = "June"
    n.months[6usize] = "July"
    n.months[7usize] = "August"
    n.months[8usize] = "September"
    n.months[9usize] = "October"
    n.months[10usize] = "November"
    n.months[11usize] = "December"
    n.all_day = ", all day"
    n.to = " to "
    n.repeats = ", repeats"
    n.day_schedule = "Day schedule"
    n.week_schedule = "Week schedule"
    n.agenda = "Agenda"
    n.month_schedule = "Month schedule"
    n.no_events = "no events"
    n.one_event = "1 event"
    n.events = " events"
    n.more = " more"
    ret n
}

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

type Ctx = struct { st: Storage, cfg: Config, placed: usize, columns: usize, rows: usize, nodes: usize, labels: usize, occ: usize, truncated: bool, first: i64, days: i64, band: f32, height: f32, names: Names }

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
    try put_label(c, c.names.weekdays[usize(calendar.weekday_index(calendar.weekday_of_count(count)))])
    try put_label(c, " ")
    try put_number(c, i64(date.day), 1usize)
    try put_label(c, " ")
    try put_label(c, c.names.months[usize(date.month) - 1usize])
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
        try put_label(c, c.names.all_day)
    } else {
        try put_label(c, ", ")
        try put_clock(c, p.start)
        try put_label(c, c.names.to)
        try put_clock(c, p.end)
    }
    if p.recurring { try put_label(c, c.names.repeats) }
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
        try put_label(c, c.names.day_schedule)
    } else {
        try put_label(c, c.names.week_schedule)
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
    try put_label(c, c.names.agenda)
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
    let (l, e) = build_named(items, cfg, st, english())
    ret (l, e)
}

// `build` with the labels' words from `names`.
fn build_named(items: []const Item, cfg: Config, st: Storage, names: Names) -> (Layout, err) {
    if cfg.day_start >= cfg.day_end || cfg.day_end > 24u32 || cfg.slot == 0u32 || cfg.width <= cfg.gutter { ret (zero, Invalid) }
    let (first, days) = range_of(cfg)
    if days < 1i64 { ret (zero, Invalid) }
    var c = Ctx { st: st, cfg: cfg, placed: 0usize, columns: 0usize, rows: 0usize, nodes: 0usize, labels: 0usize, occ: 0usize, truncated: false, first: first, days: days, band: 0.0, height: 0.0, names: names }
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

// ---- month view ----

// The day count of the first cell (the week start on or before the 1st) and the weeks the
// month spans.
fn month_first(cfg: MonthConfig) -> (i64, u32) {
    let first_of = time.Date { year: cfg.anchor.year, month: cfg.anchor.month, day: 1u8 }
    let count = calendar.day_count(first_of)
    let behind = time.floor_mod(calendar.weekday_index(calendar.weekday_of_count(count)) - calendar.weekday_index(cfg.week_start), 7i64)
    let length = time.days_in_month(i64(cfg.anchor.year), i64(cfg.anchor.month))
    ret (count - behind, u32((behind + length + 6i64) / 7i64))
}

// "Monday 12 October 2026, 3 events".
fn put_cell_label(c: *Ctx, count: i64, total: usize) -> err {
    try put_date(c, count)
    try put_label(c, ", ")
    if total == 0usize { ret put_label(c, c.names.no_events) }
    if total == 1usize { ret put_label(c, c.names.one_event) }
    try put_number(c, i64(total), 1usize)
    ret put_label(c, c.names.events)
}

fn build_month(items: []const Item, cfg: MonthConfig, ms: MonthStorage) -> (MonthLayout, err) {
    let (l, e) = build_month_named(items, cfg, ms, english())
    ret (l, e)
}

// Lays the items out as the month of `cfg.anchor`. Errors: `Invalid` (a bad rule, a month
// outside 1..12 or a non-positive size), `TooLarge` (a storage slice, `order` shorter than
// `occ`, or `cells` shorter than the weeks need: 42 is always enough).
fn build_month_named(items: []const Item, cfg: MonthConfig, ms: MonthStorage, names: Names) -> (MonthLayout, err) {
    if cfg.width <= 0.0 || cfg.cell_h <= 0.0 || cfg.line_h <= 0.0 || cfg.anchor.month < 1u8 || cfg.anchor.month > 12u8 { ret (zero, Invalid) }
    let (first, weeks) = month_first(cfg)
    let days = i64(weeks) * 7i64
    if ms.cells.len < usize(days) || ms.order.len < ms.occ.len { ret (zero, TooLarge) }
    var no_columns: [1]Column = zero
    var no_rows: [1]Row = zero
    var no_lanes: [1]i64 = zero
    let st = Storage { occ: ms.occ, stamps: ms.stamps, placed: ms.placed, columns: no_columns[0usize..0usize], rows: no_rows[0usize..0usize], nodes: ms.nodes, labels: ms.labels, order: ms.order, lane_end: no_lanes[0usize..0usize] }
    var base: Config = zero
    base.anchor = cfg.anchor
    var c = Ctx { st: st, cfg: base, placed: 0usize, columns: 0usize, rows: 0usize, nodes: 0usize, labels: 0usize, occ: 0usize, truncated: false, first: first, days: days, band: 0.0, height: 0.0, names: names }
    try collect(&c, items)
    let col_w = cfg.width / 7.0
    let lines = usize(cfg.lines)
    var d = 0usize
    while i64(d) < days {
        let count = first + i64(d)
        let date = calendar.date_of(count)
        let cx = f32(d % 7usize) * col_w
        let cy = cfg.header + f32(d / 7usize) * cfg.cell_h
        let n = day_order(&c, count * 1440i64)
        var shown = n
        var more = 0usize
        if n > lines {
            if lines == 0usize {
                shown = 0usize
            } else {
                shown = lines - 1usize
            }
            more = n - shown
        }
        let first_index = c.placed
        let day0 = count * 1440i64
        var k = 0usize
        while k < n {
            let o = c.st.occ[usize(c.st.order[k])]
            var kind: Kind = .Timed
            if o.all_day { kind = .AllDay }
            var py = cy + f32(k + 1usize) * cfg.line_h
            var pw = col_w
            var ph = cfg.line_h
            if k >= shown {
                py = cy
                pw = 0.0
                ph = 0.0
            }
            try put_placed(&c, Placed { item: o.item, kind: kind, day: u32(d), start: max_i64(o.start, day0), end: min_i64(o.start + o.minutes, day0 + 1440i64), x: cx, y: py, w: pw, h: ph, lane: u32(k), lanes: u32(n), before: o.start < day0, after: o.start + o.minutes > day0 + 1440i64, recurring: o.recurring })
            k += 1usize
        }
        ms.cells[d] = MonthCell { date: date, count: count, in_month: date.month == cfg.anchor.month && date.year == cfg.anchor.year, x: cx, y: cy, w: col_w, h: cfg.cell_h, first: u32(first_index), total: u32(n), shown: u32(shown), more: u32(more) }
        d += 1usize
    }
    // The accessible tree: the grid, the weekday headers, then each cell and its occurrences.
    let height = cfg.header + f32(weeks) * cfg.cell_h
    var start = c.labels
    try put_label(&c, names.month_schedule)
    try put_label(&c, ", ")
    try put_label(&c, names.months[usize(cfg.anchor.month) - 1usize])
    try put_label(&c, " ")
    try put_number(&c, i64(cfg.anchor.year), 1usize)
    try put_node(&c, .Grid, 0.0, 0.0, cfg.width, height, start, 0u32, 0u32, weeks, 7u32, 0u8)
    let week_start = calendar.weekday_index(cfg.week_start)
    var col = 0usize
    while col < 7usize {
        start = c.labels
        try put_label(&c, names.weekdays[usize((week_start + i64(col)) % 7i64)])
        try put_node(&c, .ColumnHeader, f32(col) * col_w, 0.0, col_w, cfg.header, start, 0u32, u32(col + 1usize), 0u32, 7u32, 0u8)
        col += 1usize
    }
    d = 0usize
    while i64(d) < days {
        let cell = ms.cells[d]
        start = c.labels
        try put_cell_label(&c, cell.count, usize(cell.total))
        try put_node(&c, .Cell, cell.x, cell.y, cell.w, cell.h, start, u32(d / 7usize + 1usize), u32(d % 7usize + 1usize), weeks, 7u32, 0u8)
        var k = 0usize
        while k < usize(cell.total) {
            let p = c.st.placed[usize(cell.first) + k]
            start = c.labels
            try put_event_label(&c, items, p)
            try put_node(&c, .ListItem, p.x, p.y, p.w, p.h, start, 0u32, 0u32, 0u32, 0u32, 1u8)
            k += 1usize
        }
        d += 1usize
    }
    ret (MonthLayout { cfg: cfg, placed: ms.placed, cells: ms.cells, nodes: ms.nodes, labels: ms.labels, placed_count: c.placed, cell_count: usize(days), node_count: c.nodes, labels_len: c.labels, weeks: weeks, first_day: first, height: height, truncated: c.truncated }, ok)
}

fn month_label_of(l: *const MonthLayout, node: usize) -> str {
    let n = l.nodes[node]
    ret l.labels[n.label_start..n.label_start + n.label_len]
}

// The top `y` of a cell's "+N more" line (one `line_h` tall), meaningful when `more > 0`.
fn more_top(l: *const MonthLayout, cell: usize) -> f32 {
    let c = l.cells[cell]
    ret c.y + f32(c.shown + 1u32) * l.cfg.line_h
}

// What is under a point of a month: a weekday header (`cell` is the column), an occurrence
// (`index` into `placed`, `cell` its cell), the "+N more" line (`index` is the cell), or a
// cell.
fn hit_month(l: *const MonthLayout, x: f32, y: f32) -> MonthHit {
    var out: MonthHit = zero
    let total = l.cfg.header + f32(l.weeks) * l.cfg.cell_h
    if x < 0.0 || y < 0.0 || x >= l.cfg.width || y >= total { ret out }
    let col_w = l.cfg.width / 7.0
    var col = u32(x / col_w)
    if col > 6u32 { col = 6u32 }
    if y < l.cfg.header {
        out.kind = .Header
        out.cell = col
        ret out
    }
    let week = u32((y - l.cfg.header) / l.cfg.cell_h)
    let index = usize(week * 7u32 + col)
    if index >= l.cell_count { ret out }
    out.cell = u32(index)
    out.kind = .Cell
    let cell = l.cells[index]
    var k = 0usize
    while k < usize(cell.shown) {
        let p = l.placed[usize(cell.first) + k]
        if y >= p.y && y < p.y + p.h {
            out.kind = .Event
            out.index = usize(cell.first) + k
            ret out
        }
        k += 1usize
    }
    if cell.more > 0u32 {
        let top = more_top(l, index)
        if y >= top && y < top + l.cfg.line_h {
            out.kind = .More
            out.index = index
        }
    }
    ret out
}

// The cell the arrow keys move the focus to: a day left or right, a week up or down, the
// first or last day of the week; the cell itself at an edge of the grid.
fn month_move(l: *const MonthLayout, cell: u32, key: Key) -> u32 {
    let total = u32(l.cell_count)
    if cell >= total { ret cell }
    if key == .Left && cell > 0u32 { ret cell - 1u32 }
    if key == .Right && cell + 1u32 < total { ret cell + 1u32 }
    if key == .Up && cell >= 7u32 { ret cell - 7u32 }
    if key == .Down && cell + 7u32 < total { ret cell + 7u32 }
    if key == .Home { ret cell - cell % 7u32 }
    if key == .End { ret cell - cell % 7u32 + 6u32 }
    ret cell
}

// ---- all-day bars, moving, resizing, keyboard ----

fn bar_before(a: Bar, b: Bar) -> bool {
    if a.first != b.first { ret a.first < b.first }
    if a.last - a.first != b.last - b.first { ret a.last - a.first > b.last - b.first }
    ret a.item < b.item
}

// One bar for each all-day occurrence of a Day or Week layout, over the columns it covers
// (clipped to the view; `before`/`after` mark a cut end), ordered by first column, longer
// first, then item, each in the lowest lane free over its columns. Answers the bars written
// and the lanes used; the band they need is `lanes * cfg.all_day_h`.
fn all_day_bars(l: *const Layout, out: []Bar) -> (usize, u32, err) {
    if l.cfg.mode == .Agenda { ret (0usize, 0u32, Invalid) }
    var n = 0usize
    var i = 0usize
    while i < l.placed_count {
        let p = l.placed[i]
        i += 1usize
        if p.kind != .AllDay { continue }
        if p.before && p.day > 0u32 { continue }
        if n >= out.len { ret (0usize, 0u32, TooLarge) }
        var last_day = time.floor_div(p.end - 1i64, 1440i64) - l.first_day
        if last_day > l.days - 1i64 { last_day = l.days - 1i64 }
        if last_day < i64(p.day) { last_day = i64(p.day) }
        let from = l.columns[usize(p.day)]
        let to = l.columns[usize(last_day)]
        let bar = Bar { item: p.item, first: p.day, last: u32(last_day), lane: 0u32, x: from.x, y: l.cfg.header, w: to.x + to.w - from.x, h: l.cfg.all_day_h, before: p.before, after: p.end > (l.first_day + l.days) * 1440i64, recurring: p.recurring }
        var at = n
        while at > 0usize && bar_before(bar, out[at - 1usize]) {
            out[at] = out[at - 1usize]
            at -= 1usize
        }
        out[at] = bar
        n += 1usize
    }
    var lanes = 0u32
    i = 0usize
    while i < n {
        var lane = 0u32
        var settled = false
        while !settled {
            settled = true
            var j = 0usize
            while j < i {
                if out[j].lane == lane && out[j].last >= out[i].first && out[j].first <= out[i].last {
                    settled = false
                    lane += 1u32
                    break
                }
                j += 1usize
            }
        }
        out[i].lane = lane
        out[i].y = l.cfg.header + f32(lane) * l.cfg.all_day_h
        if lane + 1u32 > lanes { lanes = lane + 1u32 }
        i += 1usize
    }
    ret (n, lanes, ok)
}

// The column under `x` of a grid layout.
fn column_at(l: *const Layout, x: f32) -> (usize, bool) {
    var d = 0usize
    while d < l.column_count {
        let col = l.columns[d]
        if x >= col.x && x < col.x + col.w { ret (d, true) }
        d += 1usize
    }
    ret (0usize, false)
}

// Dragging placed occurrence `index` from the grab point to `(x, y)`: its new start and
// length. A timed one keeps the grab point's offset into it, lands snapped down to `slot`
// inside the day window, and is refused if it continues from an earlier day (move it from its
// first day); an all-day one shifts by the columns between the grab and the pointer. The
// length is the item's. The caller decides whether a recurring occurrence moves alone or the
// series.
fn move_target(l: *const Layout, items: []const Item, index: usize, grab_x: f32, grab_y: f32, x: f32, y: f32) -> (Span, bool) {
    var out: Span = zero
    if l.cfg.mode == .Agenda || index >= l.placed_count { ret (out, false) }
    let p = l.placed[index]
    let item = items[usize(p.item)]
    var minutes = i64(item.minutes)
    if minutes < 1i64 { minutes = 1i64 }
    if p.kind == .AllDay {
        let (from_col, from_found) = column_at(l, grab_x)
        let (to_col, to_found) = column_at(l, x)
        if !from_found || !to_found { ret (out, false) }
        let start = p.start + (i64(to_col) - i64(from_col)) * 1440i64
        var col = time.floor_div(start, 1440i64) - l.first_day
        if col < 0i64 { col = 0i64 }
        if col > l.days - 1i64 { col = l.days - 1i64 }
        out.day = u32(col)
        out.start = datetime_of(start)
        out.minutes = u32(((minutes + 1439i64) / 1440i64) * 1440i64)
        ret (out, true)
    }
    if p.before { ret (out, false) }
    var top_y = y - (grab_y - p.y)
    let bottom = l.grid_top + f32(l.cfg.day_end - l.cfg.day_start) * l.cfg.hour_h
    if top_y < l.grid_top { top_y = l.grid_top }
    if top_y >= bottom { top_y = bottom - 0.001 }
    let (s, found) = slot_at(l, x, top_y)
    if !found { ret (out, false) }
    out.day = s.day
    out.start = s.start
    out.minutes = u32(minutes)
    ret (out, true)
}

// Dragging the bottom edge of timed occurrence `index` to `y`: its new length in minutes,
// the end snapped up to `slot` inside the day window and at least one slot. An occurrence
// that starts before or runs past its day is refused.
fn resize_target(l: *const Layout, index: usize, y: f32) -> (u32, bool) {
    if l.cfg.mode == .Agenda || index >= l.placed_count { ret (0u32, false) }
    let p = l.placed[index]
    if p.kind != .Timed || p.before || p.after { ret (0u32, false) }
    var yy = y
    let bottom = l.grid_top + f32(l.cfg.day_end - l.cfg.day_start) * l.cfg.hour_h
    if yy < l.grid_top { yy = l.grid_top }
    if yy >= bottom { yy = bottom - 0.001 }
    let day0 = l.columns[usize(p.day)].count * 1440i64
    let start_minute = u32(p.start - day0)
    let raw = u32((yy - l.grid_top) * 60.0 / l.cfg.hour_h) + l.cfg.day_start * 60u32
    var finish = (raw + l.cfg.slot - 1u32) / l.cfg.slot * l.cfg.slot
    if finish <= start_minute { finish = start_minute + l.cfg.slot }
    if finish > l.cfg.day_end * 60u32 { finish = l.cfg.day_end * 60u32 }
    if finish <= start_minute { ret (0u32, false) }
    ret (finish - start_minute, true)
}

// Where the arrow keys move the focus among placed occurrences. Up and Down step within the
// day (a time grid, in the layout's order: all-day first, then by start) or through the
// agenda's list; Left and Right go to the nearest day on that side that has one, the
// occurrence starting closest to the current one's start (the earlier on a tie); Home and End
// are the day's first and last (the list's, in an agenda). The index itself when there is
// nowhere to go.
fn focus_next(l: *const Layout, current: usize, key: Key) -> usize {
    if current >= l.placed_count { ret current }
    let day = l.placed[current].day
    if l.cfg.mode == .Agenda {
        if key == .Up && current > 0usize { ret current - 1usize }
        if key == .Down && current + 1usize < l.placed_count { ret current + 1usize }
        if key == .Home { ret 0usize }
        if key == .End { ret l.placed_count - 1usize }
        ret current
    }
    if key == .Up || key == .Down || key == .Home || key == .End {
        var i = 0usize
        var found_first = false
        var first_of_day = current
        var last_of_day = current
        var before_me = current
        var after_me = current
        var seen_me = false
        while i < l.placed_count {
            if l.placed[i].day == day {
                if !found_first {
                    first_of_day = i
                    found_first = true
                }
                last_of_day = i
                if i < current { before_me = i }
                if i > current && !seen_me {
                    after_me = i
                    seen_me = true
                }
            }
            i += 1usize
        }
        if key == .Up { ret before_me }
        if key == .Down { ret after_me }
        if key == .Home { ret first_of_day }
        ret last_of_day
    }
    var step = 0i64 - 1i64
    if key == .Right { step = 1i64 }
    var want_day = i64(day) + step
    let from = l.placed[current]
    var mark = from.start
    if from.kind == .AllDay { mark = (l.first_day + i64(day)) * 1440i64 }
    var best = current
    while want_day >= 0i64 && want_day < i64(l.column_count) {
        var found = false
        var gap = 0i64
        var i = 0usize
        while i < l.placed_count {
            let p = l.placed[i]
            if p.day == u32(want_day) {
                var at = p.start
                if p.kind == .AllDay { at = (l.first_day + want_day) * 1440i64 }
                var distance = at - mark
                if distance < 0i64 { distance = 0i64 - distance }
                if !found || distance < gap {
                    best = i
                    gap = distance
                    found = true
                }
            }
            i += 1usize
        }
        if found { ret best }
        want_day += step
    }
    ret current
}
