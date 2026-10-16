// The Android look's date pickers, docs/ui/looks/material/date_picker.png (the modal calendar) and date_input.png (the
// modal in input mode: a text field and the date format hint). An open modal covers the window, so each sheet holds one.
// Run from the repository root.

use e.mem
use e.time
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_date(ctx: *void, value: time.Date) -> err { ret ok }
fn noop_text(ctx: *void, value: str) -> err { ret ok }

fn picker(a: *mem.Arena, t: *const control.Theme, typing: bool) -> (widget.Node, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let day = time.Date { year: 2026i32, month: 10u8, day: 16u8 }
    let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    let words = "2026-10-16"
    var n = 0usize
    while n < words.len {
        buffer[n] = words[n]
        n += 1usize
    }
    var options: overlay.DateModalOptions = zero
    options.typing = typing
    options.toggle_mode = &actions[0usize]
    options.buffer = buffer
    options.len = 0usize
    if typing { options.len = n }
    options.typed = widget.Change[str] { ctx: zero, invoke: noop_text }
    options.today = day
    let (node, node_error) = overlay.date_picker_modal(a, 300u64, t, day, true, day, widget.Change[time.Date] { ctx: zero, invoke: noop_date }, widget.Change[time.Date] { ctx: zero, invoke: noop_date }, true, &actions[0usize], &actions[1usize], options)
    ret (node, node_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = picker(a, t, false)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Modal date picker", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_input(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = picker(a, t, true)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Modal date input", node: node, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let calendar = looks.Sheet { name: "date_picker", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 560.0, ctx: zero, build: build }
    try looks.run_material(a, &calendar)
    let entry = looks.Sheet { name: "date_input", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 320.0, ctx: zero, build: build_input }
    ret looks.run_material(a, &entry)
}
