// The Linux look's date edit against the real GTK 4.14 / libadwaita 1.5 ones (scripts/linux_cmp_l2.py): the menu button that shows the
// date (date_edit.png: rest, hovered, focused), the bare calendar (date_edit_calendar.png, October 2026 with the 16th chosen, the week
// starting on Sunday) and the button with its calendar in the popover (date_edit_open.png, no GTK capture of the whole). Run from the
// repository root; see docs/ui/looks-howto.md.

use e.mem
use e.time
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_show(ctx: *void, day: time.Date) -> err { ret ok }

fn one_node(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

fn picker(a: *mem.Arena, t: *const control.Theme, key: widget.Key, open: bool) -> (widget.Node, err) {
    let chosen = time.Date { year: 2026i32, month: 10u8, day: 16u8 }
    let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    let n = control.copy_text(buffer, "2026-10-16")
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var footer = overlay.DateFooter { today: chosen, clear: zero, typing: false, buffer: buffer, len: n, typed: zero }
    let (node, node_error) = overlay.date_picker_with(a, key, t, "Date", chosen, true, open, &actions[0usize], chosen, widget.Change[time.Date] { ctx: zero, invoke: noop_show }, widget.Change[time.Date] { ctx: zero, invoke: noop_show }, footer)
    ret (node, node_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [3]str{ "rest", "hover", "focus" }
    var i = 0usize
    while i < 3usize {
        let (node, node_error) = picker(a, t, u64(10usize * (i + 1usize)), false)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (3usize, ok)
}

fn build_calendar(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Sunday first, English names: the language of the United States.
    let us = control.Theme { tokens: t.tokens, fonts: t.fonts, language: "en-US", runtime: t.runtime }
    let day = time.Date { year: 2026i32, month: 10u8, day: 16u8 }
    let (node, node_error) = overlay.calendar(a, 10u64, &us, "Calendar", day, day, true, false, day, day, widget.Change[time.Date] { ctx: zero, invoke: noop_show }, widget.Change[time.Date] { ctx: zero, invoke: noop_show })
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "calendar", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_open(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let us = control.Theme { tokens: t.tokens, fonts: t.fonts, language: "en-US", runtime: t.runtime }
    let (node, node_error) = picker(a, &us, 10u64, true)
    if node_error != ok { ret (0usize, node_error) }
    var room = looks.size_style(320.0, 330.0)
    room.padding = style.EdgeLengths { left: style.Length { Px: 20.0 }, top: style.Length { Px: 20.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, room, one_node(a, node))
    cells[0usize] = looks.Cell { caption: "open", node: column, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    control.set_native_caret_off(true)
    let sheet = looks.Sheet { name: "date_edit", cells: 3usize, columns: 3usize, cell_w: 140.0, cell_h: 44.0, ctx: zero, build: build }
    try looks.run_linux(a, &sheet)
    let calendar = looks.Sheet { name: "date_edit_calendar", cells: 1usize, columns: 1usize, cell_w: 281.0, cell_h: 246.0, ctx: zero, build: build_calendar }
    try looks.run_linux(a, &calendar)
    let open = looks.Sheet { name: "date_edit_open", cells: 1usize, columns: 1usize, cell_w: 320.0, cell_h: 330.0, ctx: zero, build: build_open }
    ret looks.run_linux(a, &open)
}
