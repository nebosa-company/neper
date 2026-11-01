// Round 70 b: the modal date picker (Neper pair) and the modal time picker with its dial (Neper pair and Android pair), the
// controls the Flutter references showDatePicker and showTimePicker stand for. Run from the repository root.

use e.mem
use e.time
use e.ui.control
use e.ui.looks
use e.ui.looks_b70
use e.ui.overlay
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_date(ctx: *void, value: time.Date) -> err { ret ok }
fn noop_text(ctx: *void, value: str) -> err { ret ok }

fn picker(a: *mem.Arena, theme: *const control.Theme, typing: bool) -> (widget.Node, err) {
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
    options.today = time.Date { year: 2026i32, month: 2u8, day: 14u8 }
    let (node, node_error) = overlay.date_picker_modal(a, 300u64, t, day, true, day, widget.Change[time.Date] { ctx: zero, invoke: noop_date }, widget.Change[time.Date] { ctx: zero, invoke: noop_date }, true, &actions[0usize], &actions[1usize], options)
    ret (node, node_error)
}

fn noop_time(ctx: *void, value: overlay.TimeChoice) -> err { ret ok }

fn build_date(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (node, node_error) = picker(a, t, false)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Modal date picker", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_time(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let (node, node_error) = overlay.time_picker_modal(a, 300u64, t, 10u8, 30u8, false, true, true, widget.Change[overlay.TimeChoice] { ctx: zero, invoke: noop_time }, &actions[0usize], &actions[1usize])
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Modal time picker", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_wheels(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (clock, clock_error) = overlay.time_wheels(a, 400u64, t, 10u8, 30u8, true, widget.Change[overlay.TimeChoice] { ctx: zero, invoke: noop_time })
    if clock_error != ok { ret (0usize, clock_error) }
    cells[0usize] = looks.Cell { caption: "Time wheels", node: clock, drive: .None }
    let (days, days_error) = overlay.date_wheels(a, 500u64, t, time.Date { year: 2026i32, month: 10u8, day: 20u8 }, widget.Change[time.Date] { ctx: zero, invoke: noop_date })
    if days_error != ok { ret (0usize, days_error) }
    cells[1usize] = looks.Cell { caption: "Date wheels", node: days, drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let date = looks.Sheet { name: "date_picker_modal", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 480.0, ctx: zero, build: build_date }
    try looks_b70.run_neper(a, &date)
    let clock = looks.Sheet { name: "time_picker_dial", cells: 1usize, columns: 1usize, cell_w: 360.0, cell_h: 520.0, ctx: zero, build: build_time }
    try looks_b70.run_neper(a, &clock)
    try looks.run_material(a, &clock)
    let wheels = looks.Sheet { name: "picker_wheels", cells: 2usize, columns: 2usize, cell_w: 260.0, cell_h: 200.0, ctx: zero, build: build_wheels }
    try looks_b70.run_neper(a, &wheels)
    ret looks.run_cupertino(a, &wheels)
}
