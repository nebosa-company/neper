// Round 62 c: the toast in all ten looks. A toast is an overlay pinned to the top right of its window, so one window shows
// one toast stack: three sheets, toast (titled info over a stack of four, the head with an action and a dismiss),
// toast_error (a titled error) and toast_plain (a message alone). Hover and pressed are not driven: the pointer aims at a
// cell's centre and the toast stands in the corner. Derived from the shared tokens, no platform capture. Run from the
// repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn made(a: *mem.Arena, t: *const control.Theme, count: usize, title: str, severity: control.Severity, action: bool, caption: str, cells: []looks.Cell) -> (usize, err) {
    let (notices, notices_error) = mem.alloc[control.Notice](a, count)
    if notices_error != ok { ret (0usize, notices_error) }
    let go = widget.Submit { ctx: zero, invoke: noop_submit }
    let words = [4]str{ "Card removed from the deck", "Prices refreshed", "Deck saved", "Import finished" }
    var i = 0usize
    while i < count {
        var notice: control.Notice = zero
        notice.text = words[i]
        notice.dismiss = go
        if action && i == 0usize {
            notice.action_label = "Undo"
            notice.action = go
        }
        notices[i] = notice
        i += 1usize
    }
    var options: control.ToastOptions = zero
    options.title = title
    options.severity = severity
    let (node, node_error) = control.toast_with(a, 8u64, t, notices[0usize..count], 360.0, options)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: caption, node: node, drive: .None }
    ret (1usize, ok)
}

fn build_stack(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (count, failure) = made(a, t, 4usize, "Undo available", .Info, true, "Titled, action, dismiss, stack of four", cells)
    ret (count, failure)
}

fn build_error(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (count, failure) = made(a, t, 1usize, "Import failed", .Error, false, "Titled error, dismiss", cells)
    ret (count, failure)
}

fn build_plain(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (count, failure) = made(a, t, 1usize, "", .Info, true, "Message, action, dismiss", cells)
    ret (count, failure)
}

fn run(a: *mem.Arena, sheet: *const looks.Sheet) -> err {
    try looks.run_all(a, sheet)
    try looks.run_material(a, sheet)
    try looks.run_cupertino(a, sheet)
    ret looks.run_linux(a, sheet)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let stack = looks.Sheet { name: "toast", cells: 1usize, columns: 1usize, cell_w: 660.0, cell_h: 250.0, ctx: zero, build: build_stack }
    try run(a, &stack)
    let failed = looks.Sheet { name: "toast_error", cells: 1usize, columns: 1usize, cell_w: 660.0, cell_h: 130.0, ctx: zero, build: build_error }
    try run(a, &failed)
    let plain = looks.Sheet { name: "toast_plain", cells: 1usize, columns: 1usize, cell_w: 660.0, cell_h: 130.0, ctx: zero, build: build_plain }
    ret run(a, &plain)
}
