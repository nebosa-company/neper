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

fn picker(a: *mem.Arena, theme: *const control.Theme, typing: bool, words: str) -> (widget.Node, err) {
    // An Android phone in the United States: the week starts on Sunday.
    let (held, held_error) = mem.alloc[control.Theme](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = *theme
    held[0usize].language = "en-US"
    let t = &held[0usize]
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    // February 2026 starts on a Sunday and has 28 days, like the grid of the spec-derived capture (a 28 day month from Sunday); 21 is chosen and 14 is today.
    let day = time.Date { year: 2026i32, month: 2u8, day: 21u8 }
    let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
    if buffer_error != ok { ret (zero, buffer_error) }
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
    options.today = time.Date { year: 2026i32, month: 2u8, day: 14u8 }
    let (node, node_error) = overlay.date_picker_modal(a, 300u64, t, day, true, day, widget.Change[time.Date] { ctx: zero, invoke: noop_date }, widget.Change[time.Date] { ctx: zero, invoke: noop_date }, true, &actions[0usize], &actions[1usize], options)
    ret (node, node_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = picker(a, t, false, "")
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Modal date picker", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_input(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = picker(a, t, true, "02/21/2026")
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Modal date input", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_input_focus(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = picker(a, t, true, "02/21/2026")
    if node_error != ok { ret (0usize, node_error) }
    looks.aim(0usize, 60.0, 30.0)
    cells[0usize] = looks.Cell { caption: "Modal date input, field focused", node: node, drive: .FocusHover }
    ret (1usize, ok)
}

fn build_input_error(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = picker(a, t, true, "13/45/2026")
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Modal date input, not a date", node: node, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let calendar = looks.Sheet { name: "date_picker", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 480.0, ctx: zero, build: build }
    try looks.run_material(a, &calendar)
    let entry = looks.Sheet { name: "date_input", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 320.0, ctx: zero, build: build_input }
    try looks.run_material(a, &entry)
    let focus = looks.Sheet { name: "date_input_focus", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 320.0, ctx: zero, build: build_input_focus }
    try looks.run_material(a, &focus)
    looks.aim(0usize, 0.0, 0.0)
    let wrong = looks.Sheet { name: "date_input_error", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 320.0, ctx: zero, build: build_input_error }
    ret looks.run_material(a, &wrong)
}
