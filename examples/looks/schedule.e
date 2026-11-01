// The scheduler (e.ui.schedule), docs/ui/looks/<look>/schedule.png in all ten looks. e.ui.schedule is a model, not a widget:
// it lays appointments out as day, week, agenda and month rectangles (overlap lanes, all-day band, "+N more" lines). This host
// is the minimal widget tree that draws that layout: header cells, the hour grid, a band for all-day entries, an event block
// in the theme's primary container with a primary edge, agenda rows from the layout's own accessible nodes, month cells with
// their day numbers and event lines. The host adds a tint on the day of the anchor and a ring on a selected event; the model
// has no hover or focus state, so there are no such cells. Everything is drawn through the shared tokens; derived, no platform
// calendar was compared.

use e.gfx.paint
use e.mem
use e.time
use e.time.calendar
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.schedule as sc
use e.ui.style
use e.ui.widget

type Face = struct { bg: paint.Color, filled: bool, edge: paint.Color, edge_w: f32, ink: paint.Color, role: style.TextRole, centered: bool, pad: f32, strong: bool }

fn mem_one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret zero }
    one[0usize] = node
    ret one[0usize..1usize]
}

// One positioned cell: a clipped box of `face` holding `value`, centred or left in its height.
fn cell(a: *mem.Arena, t: *const control.Theme, x: f32, y: f32, w: f32, h: f32, value: str, face: Face) -> (widget.Node, err) {
    var box = control.sized_style(w, h)
    box.overflow = .Clip
    if face.filled { box.background = paint.Brush { Solid: face.bg } }
    if face.edge_w > 0.0 { box.border = style.Border { width: face.edge_w, color: face.edge } }
    let pad = style.Length { Px: face.pad }
    box.padding = style.EdgeLengths { left: pad, top: style.Length { Px: 0.0 }, right: pad, bottom: style.Length { Px: 0.0 } }
    var kids = mem_one(a, zero_node())
    if value.len > 0usize {
        var options = control.text_options()
        options.role = face.role
        options.wrap = .None
        if face.strong { options.weight = 700u32 }
        let (text, text_error) = control.colored_text(a, 0u64, value, t, options, face.ink)
        if text_error != ok { ret (zero, text_error) }
        kids = mem_one(a, text)
    }
    var cross: ui_layout.CrossAlign = .Start
    if face.centered { cross = .Center }
    let inner = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: cross, gap: 0.0 }, box, kids)
    ret (widget.positioned(0u64, x, y, style.defaults(), mem_one(a, inner)), ok)
}

fn zero_node() -> widget.Node {
    ret widget.box(0u64, style.defaults(), zero)
}

fn plain(t: *const control.Theme, ink: style.ColorRole, role: style.TextRole) -> Face {
    ret Face { bg: style.color(t.tokens, .Surface), filled: false, edge: style.color(t.tokens, .OutlineVariant), edge_w: 0.0, ink: style.color(t.tokens, ink), role: role, centered: false, pad: 0.0, strong: false }
}

fn two(a: *mem.Arena, v: u32) -> (str, err) {
    let (b, e) = mem.alloc[u8](a, 2usize)
    if e != ok { ret ("", e) }
    b[0usize] = 48u8 + u8((v / 10u32) % 10u32)
    b[1usize] = 48u8 + u8(v % 10u32)
    ret (b[0usize..2usize], ok)
}

fn day_text(a: *mem.Arena, d: time.Date) -> (str, err) {
    let names = [7]str{ "Mon ", "Tue ", "Wed ", "Thu ", "Fri ", "Sat ", "Sun " }
    let (w, w_error) = calendar.weekday(d)
    if w_error != ok { ret ("", w_error) }
    let (digits, digits_error) = two(a, u32(d.day))
    if digits_error != ok { ret ("", digits_error) }
    var shown = digits
    if digits[0usize] == 48u8 { shown = digits[1usize..2usize] }
    let (out, out_error) = mem.alloc[u8](a, 6usize)
    if out_error != ok { ret ("", out_error) }
    let name = names[usize(calendar.weekday_index(w))]
    var n = 0usize
    while n < 4usize {
        out[n] = name[n]
        n += 1usize
    }
    var k = 0usize
    while k < shown.len {
        out[n] = shown[k]
        n += 1usize
        k += 1usize
    }
    ret (out[0usize..n], ok)
}

fn hour_text(a: *mem.Arena, h: u32) -> (str, err) {
    let (digits, digits_error) = two(a, h)
    if digits_error != ok { ret ("", digits_error) }
    let (out, out_error) = mem.alloc[u8](a, 5usize)
    if out_error != ok { ret (zero, out_error) }
    out[0usize] = digits[0usize]
    out[1usize] = digits[1usize]
    out[2usize] = 58u8
    out[3usize] = 48u8
    out[4usize] = 48u8
    ret (out[0usize..5usize], ok)
}

fn at(day: u8, hour: u8, minute: u8) -> calendar.DateTime {
    var clock: time.Time = zero
    clock.hour = hour
    clock.minute = minute
    ret calendar.DateTime { date: time.Date { year: 2026, month: 10u8, day: day }, time: clock }
}

fn items(a: *mem.Arena) -> ([]sc.Item, err) {
    let (list, list_error) = mem.alloc[sc.Item](a, 12usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = sc.Item { id: 1u32, start: at(12u8, 9u8, 0u8), minutes: 30u32, all_day: false, title: "Standup", rule: "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=10" }
    list[1usize] = sc.Item { id: 2u32, start: at(13u8, 10u8, 0u8), minutes: 90u32, all_day: false, title: "Design review", rule: "" }
    list[2usize] = sc.Item { id: 3u32, start: at(13u8, 10u8, 30u8), minutes: 60u32, all_day: false, title: "Lunch", rule: "" }
    list[3usize] = sc.Item { id: 4u32, start: at(13u8, 11u8, 0u8), minutes: 30u32, all_day: false, title: "Call", rule: "" }
    list[4usize] = sc.Item { id: 5u32, start: at(14u8, 13u8, 0u8), minutes: 180u32, all_day: false, title: "Workshop", rule: "" }
    list[5usize] = sc.Item { id: 6u32, start: at(14u8, 0u8, 0u8), minutes: 2880u32, all_day: true, title: "Conference", rule: "" }
    list[6usize] = sc.Item { id: 7u32, start: at(16u8, 0u8, 0u8), minutes: 1440u32, all_day: true, title: "Holiday", rule: "" }
    list[7usize] = sc.Item { id: 8u32, start: at(14u8, 15u8, 0u8), minutes: 60u32, all_day: false, title: "Weekly sync", rule: "FREQ=WEEKLY;INTERVAL=1;COUNT=4" }
    list[8usize] = sc.Item { id: 9u32, start: at(16u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Chain A", rule: "" }
    list[9usize] = sc.Item { id: 10u32, start: at(16u8, 9u8, 30u8), minutes: 60u32, all_day: false, title: "Chain B", rule: "" }
    list[10usize] = sc.Item { id: 11u32, start: at(15u8, 16u8, 0u8), minutes: 45u32, all_day: false, title: "Review prices", rule: "" }
    list[11usize] = sc.Item { id: 12u32, start: at(15u8, 12u8, 0u8), minutes: 60u32, all_day: false, title: "Lunch break", rule: "" }
    ret (list, ok)
}

fn grid_config(mode: sc.Mode, width: f32, hour_h: f32) -> sc.Config {
    ret sc.Config { mode: mode, anchor: time.Date { year: 2026, month: 10u8, day: 14u8 }, week_start: .Monday, day_start: 8u32, day_end: 18u32, slot: 30u32, agenda_days: 5u32, width: width, gutter: 48.0, header: 28.0, all_day_h: 18.0, hour_h: hour_h, row_h: 24.0, min_h: 14.0 }
}

fn storage(a: *mem.Arena) -> (sc.Storage, err) {
    let (o, e1) = mem.alloc[sc.Occ](a, 256usize)
    if e1 != ok { ret (zero, e1) }
    let (s, e2) = mem.alloc[calendar.DateTime](a, 128usize)
    if e2 != ok { ret (zero, e2) }
    let (p, e3) = mem.alloc[sc.Placed](a, 256usize)
    if e3 != ok { ret (zero, e3) }
    let (c, e4) = mem.alloc[sc.Column](a, 8usize)
    if e4 != ok { ret (zero, e4) }
    let (r, e5) = mem.alloc[sc.Row](a, 520usize)
    if e5 != ok { ret (zero, e5) }
    let (n, e6) = mem.alloc[sc.Access](a, 280usize)
    if e6 != ok { ret (zero, e6) }
    let (lb, e7) = mem.alloc[u8](a, 8192usize)
    if e7 != ok { ret (zero, e7) }
    let (ord, e8) = mem.alloc[u32](a, 256usize)
    if e8 != ok { ret (zero, e8) }
    let (le, e9) = mem.alloc[i64](a, 256usize)
    if e9 != ok { ret (zero, e9) }
    ret (sc.Storage { occ: o, stamps: s, placed: p, columns: c, rows: r, nodes: n, labels: lb, order: ord, lane_end: le }, ok)
}

fn month_storage(a: *mem.Arena) -> (sc.MonthStorage, err) {
    let (o, e1) = mem.alloc[sc.Occ](a, 256usize)
    if e1 != ok { ret (zero, e1) }
    let (s, e2) = mem.alloc[calendar.DateTime](a, 128usize)
    if e2 != ok { ret (zero, e2) }
    let (p, e3) = mem.alloc[sc.Placed](a, 256usize)
    if e3 != ok { ret (zero, e3) }
    let (c, e4) = mem.alloc[sc.MonthCell](a, 42usize)
    if e4 != ok { ret (zero, e4) }
    let (n, e5) = mem.alloc[sc.Access](a, 320usize)
    if e5 != ok { ret (zero, e5) }
    let (lb, e6) = mem.alloc[u8](a, 8192usize)
    if e6 != ok { ret (zero, e6) }
    let (ord, e7) = mem.alloc[u32](a, 256usize)
    if e7 != ok { ret (zero, e7) }
    ret (sc.MonthStorage { occ: o, stamps: s, placed: p, cells: c, order: ord, nodes: n, labels: lb }, ok)
}

fn event_face(t: *const control.Theme, all_day: bool) -> Face {
    var f = plain(t, .OnPrimaryContainer, .LabelSmall)
    f.bg = style.color(t.tokens, .PrimaryContainer)
    f.filled = true
    f.edge = style.color(t.tokens, .Primary)
    f.pad = 5.0
    if all_day {
        f.bg = style.color(t.tokens, .SecondaryContainer)
        f.ink = style.color(t.tokens, .OnSecondaryContainer)
        f.edge = style.color(t.tokens, .Secondary)
    }
    ret f
}

// Day and week: header cells, the hour grid, the all-day band and the event blocks. `selected` is an item id (0: none).
fn grid_view(a: *mem.Arena, t: *const control.Theme, mode: sc.Mode, width: f32, selected: u32) -> (widget.Node, err) {
    let (list, list_error) = items(a)
    if list_error != ok { ret (zero, list_error) }
    let (st, st_error) = storage(a)
    if st_error != ok { ret (zero, st_error) }
    let cfg = grid_config(mode, width, 36.0)
    let (ls, ls_error) = mem.alloc[sc.Layout](a, 1usize)
    if ls_error != ok { ret (zero, ls_error) }
    let (built, built_error) = sc.build(list, cfg, st)
    if built_error != ok { ret (zero, built_error) }
    ls[0usize] = built
    let l = &ls[0usize]
    let (layers, layers_error) = mem.alloc[widget.Node](a, l.placed_count + l.column_count * 3usize + 40usize)
    if layers_error != ok { ret (zero, layers_error) }
    var n = 0usize
    let grid_h = f32(cfg.day_end - cfg.day_start) * cfg.hour_h
    // the day of the anchor, tinted
    var c = 0usize
    while c < l.column_count {
        let col = l.columns[c]
        if col.date.day == cfg.anchor.day {
            var tint = plain(t, .OnSurface, .LabelSmall)
            tint.bg = style.color(t.tokens, .Primary)
            tint.bg.alpha = 0.07
            tint.filled = true
            let (node, node_error) = cell(a, t, col.x, l.grid_top, col.w, grid_h, "", tint)
            if node_error != ok { ret (zero, node_error) }
            layers[n] = node
            n += 1usize
        }
        c += 1usize
    }
    // hour lines and the gutter's hours
    var h = cfg.day_start
    while h < cfg.day_end {
        let y = l.grid_top + f32(h - cfg.day_start) * cfg.hour_h
        var line = plain(t, .OnSurfaceVariant, .LabelSmall)
        line.bg = style.color(t.tokens, .OutlineVariant)
        line.filled = true
        let (rule, rule_error) = cell(a, t, cfg.gutter, y, width - cfg.gutter, 1.0, "", line)
        if rule_error != ok { ret (zero, rule_error) }
        layers[n] = rule
        n += 1usize
        let (words, words_error) = hour_text(a, h)
        if words_error != ok { ret (zero, words_error) }
        var hour = plain(t, .OnSurfaceVariant, .LabelSmall)
        hour.pad = 6.0
        let (label, label_error) = cell(a, t, 0.0, y, cfg.gutter, 16.0, words, hour)
        if label_error != ok { ret (zero, label_error) }
        layers[n] = label
        n += 1usize
        h += 1u32
    }
    // column headers and separators
    c = 0usize
    while c < l.column_count {
        let col = l.columns[c]
        let (words, words_error) = day_text(a, col.date)
        if words_error != ok { ret (zero, words_error) }
        var head = plain(t, .OnSurface, .LabelMedium)
        head.centered = true
        head.strong = col.date.day == cfg.anchor.day
        head.edge = style.color(t.tokens, .OutlineVariant)
        head.edge_w = 0.0
        let (node, node_error) = cell(a, t, col.x, 0.0, col.w, cfg.header, words, head)
        if node_error != ok { ret (zero, node_error) }
        layers[n] = node
        n += 1usize
        var sep = plain(t, .OnSurface, .LabelSmall)
        sep.bg = style.color(t.tokens, .OutlineVariant)
        sep.filled = true
        let (bar, bar_error) = cell(a, t, col.x, 0.0, 1.0, l.grid_top + grid_h, "", sep)
        if bar_error != ok { ret (zero, bar_error) }
        layers[n] = bar
        n += 1usize
        c += 1usize
    }
    // events
    var p = 0usize
    while p < l.placed_count {
        let ev = l.placed[p]
        let item = list[usize(ev.item)]
        var face = event_face(t, ev.kind == .AllDay)
        if item.id == selected {
            face.edge = style.color(t.tokens, .Focus)
            face.edge_w = 2.0
        }
        let (node, node_error) = cell(a, t, ev.x + 1.0, ev.y + 1.0, ev.w - 2.0, ev.h - 2.0, item.title, face)
        if node_error != ok { ret (zero, node_error) }
        layers[n] = node
        n += 1usize
        p += 1usize
    }
    ret (widget.stack(0u64, control.sized_style(width, l.height), layers[0usize..n]), ok)
}

// Agenda: the layout's own day headings and rows.
fn agenda_view(a: *mem.Arena, t: *const control.Theme, width: f32) -> (widget.Node, err) {
    let (list, list_error) = items(a)
    if list_error != ok { ret (zero, list_error) }
    let (st, st_error) = storage(a)
    if st_error != ok { ret (zero, st_error) }
    let cfg = grid_config(.Agenda, width, 36.0)
    let (built, built_error) = sc.build(list, cfg, st)
    if built_error != ok { ret (zero, built_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, built.node_count + 2usize)
    if layers_error != ok { ret (zero, layers_error) }
    var n = 0usize
    var i = 0usize
    while i < built.node_count {
        let node = built.nodes[i]
        let value = sc.label_of(&built, i)
        if node.role == .Heading {
            var face = plain(t, .OnSurface, .LabelMedium)
            face.bg = style.color(t.tokens, .SurfaceContainerHigh)
            face.filled = true
            face.pad = 8.0
            face.strong = true
            let (made, made_error) = cell(a, t, node.x, node.y, node.w, node.h, value, face)
            if made_error != ok { ret (zero, made_error) }
            layers[n] = made
            n += 1usize
        } else if node.role == .ListItem {
            var face = plain(t, .OnSurface, .BodySmall)
            face.edge = style.color(t.tokens, .OutlineVariant)
            face.pad = 8.0
            let (made, made_error) = cell(a, t, node.x, node.y, node.w, node.h, value, face)
            if made_error != ok { ret (zero, made_error) }
            layers[n] = made
            n += 1usize
        }
        i += 1usize
    }
    ret (widget.stack(0u64, control.sized_style(width, built.height), layers[0usize..n]), ok)
}

fn month_view(a: *mem.Arena, t: *const control.Theme, width: f32, lines: u32) -> (widget.Node, err) {
    let (list, list_error) = items(a)
    if list_error != ok { ret (zero, list_error) }
    let (st, st_error) = month_storage(a)
    if st_error != ok { ret (zero, st_error) }
    let cfg = sc.MonthConfig { anchor: time.Date { year: 2026, month: 10u8, day: 14u8 }, week_start: .Monday, width: width, header: 24.0, cell_h: 76.0, line_h: 16.0, lines: lines }
    let (built, built_error) = sc.build_month(list, cfg, st)
    if built_error != ok { ret (zero, built_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, built.cell_count * 3usize + built.placed_count + 20usize)
    if layers_error != ok { ret (zero, layers_error) }
    var n = 0usize
    let names = [7]str{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
    var d = 0usize
    while d < 7usize {
        var head = plain(t, .OnSurfaceVariant, .LabelMedium)
        head.centered = true
        let (made, made_error) = cell(a, t, f32(d) * (width / 7.0), 0.0, width / 7.0, cfg.header, names[d], head)
        if made_error != ok { ret (zero, made_error) }
        layers[n] = made
        n += 1usize
        d += 1usize
    }
    var c = 0usize
    while c < built.cell_count {
        let mc = built.cells[c]
        var face = plain(t, .OnSurface, .LabelSmall)
        face.edge = style.color(t.tokens, .OutlineVariant)
        face.edge_w = 1.0
        if !mc.in_month {
            face.bg = style.color(t.tokens, .SurfaceContainerLow)
            face.filled = true
            face.ink = style.color(t.tokens, .OnSurfaceVariant)
        }
        if mc.date.day == cfg.anchor.day && mc.in_month {
            face.bg = style.color(t.tokens, .Primary)
            face.bg.alpha = 0.07
            face.filled = true
        }
        let (digits, digits_error) = two(a, u32(mc.date.day))
        if digits_error != ok { ret (zero, digits_error) }
        var day = digits
        if digits[0usize] == 48u8 { day = digits[1usize..2usize] }
        face.pad = 6.0
        var corner = face
        corner.centered = false
        let (made, made_error) = cell(a, t, mc.x, mc.y, mc.w, 20.0, day, corner)
        if made_error != ok { ret (zero, made_error) }
        var frame = face
        frame.edge_w = 1.0
        let (back, back_error) = cell(a, t, mc.x, mc.y, mc.w, mc.h, "", frame)
        if back_error != ok { ret (zero, back_error) }
        layers[n] = back
        n += 1usize
        layers[n] = made
        n += 1usize
        c += 1usize
    }
    var p = 0usize
    while p < built.placed_count {
        let ev = built.placed[p]
        if ev.w > 0.0 && ev.h > 0.0 {
            let face = event_face(t, ev.kind == .AllDay)
            let (made, made_error) = cell(a, t, ev.x + 2.0, ev.y + 1.0, ev.w - 4.0, ev.h - 2.0, list[usize(ev.item)].title, face)
            if made_error != ok { ret (zero, made_error) }
            layers[n] = made
            n += 1usize
        }
        p += 1usize
    }
    c = 0usize
    while c < built.cell_count {
        let mc = built.cells[c]
        if mc.more > 0u32 {
            var face = plain(t, .Primary, .LabelSmall)
            face.pad = 6.0
            let (digits, digits_error) = two(a, mc.more)
            if digits_error != ok { ret (zero, digits_error) }
            let (words, words_error) = mem.alloc[u8](a, 8usize)
            if words_error != ok { ret (zero, words_error) }
            words[0usize] = 43u8
            words[1usize] = digits[1usize]
            let tail = " more"
            var k = 0usize
            while k < tail.len {
                words[2usize + k] = tail[k]
                k += 1usize
            }
            let (made, made_error) = cell(a, t, mc.x, mc.y + mc.h - 17.0, mc.w, 16.0, words[0usize..7usize], face)
            if made_error != ok { ret (zero, made_error) }
            layers[n] = made
            n += 1usize
        }
        c += 1usize
    }
    ret (widget.stack(0u64, control.sized_style(width, built.height), layers[0usize..n]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "week", "week, event selected", "day", "agenda", "month", "month, +N more" }
    var i = 0usize
    while i < 6usize {
        var node: widget.Node = zero
        var node_error: err = ok
        if i == 0usize { (node, node_error) = grid_view(a, t, .Week, 660.0, 0u32) }
        if i == 1usize { (node, node_error) = grid_view(a, t, .Week, 660.0, 2u32) }
        if i == 2usize { (node, node_error) = grid_view(a, t, .Day, 300.0, 0u32) }
        if i == 3usize { (node, node_error) = agenda_view(a, t, 300.0) }
        if i == 4usize { (node, node_error) = month_view(a, t, 660.0, 4u32) }
        if i == 5usize { (node, node_error) = month_view(a, t, 660.0, 2u32) }
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "schedule", cells: 6usize, columns: 2usize, cell_w: 690.0, cell_h: 440.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_material(a, &sheet)
}
