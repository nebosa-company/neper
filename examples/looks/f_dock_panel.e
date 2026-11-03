// navigation.dock_panel under all ten looks: docs/ui/looks/<look>/dock_panel.png. A docked panel (header with title and
// close button over its content) at rest, focused, floating, busy and empty, and its close button hovered and pressed.
// Derived: every look draws the panel from the shared tokens (no platform reference is captured for it).
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_f
use e.ui.navigation
use e.ui.widget

fn no_press(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [7]str{ "Rest", "Focused", "Floating", "Busy", "Empty", "Close hovered", "Close pressed" }
    let (press, press_error) = mem.alloc[widget.Submit](a, 1usize)
    if press_error != ok { ret (0usize, press_error) }
    press[0usize] = widget.Submit { ctx: zero, invoke: no_press }
    var i = 0usize
    while i < 7usize {
        let (body, body_error) = control.text(a, 0u64, "Build succeeded", t, control.text_options())
        if body_error != ok { ret (0usize, body_error) }
        var options = navigation.dock_panel_options()
        options.focused = i == 1usize
        options.floating = i == 2usize
        options.busy = i == 3usize
        if i == 4usize { options.empty = "Nothing to show" }
        let (panel, panel_error) = navigation.dock_panel_of(a, u64((i + 1usize) * 100usize), t, "Output", body, &press[0usize], options)
        if panel_error != ok { ret (0usize, panel_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = panel
        let boxed = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, control.sized_style(260.0, 120.0), held[0usize..1usize])
        var drive: looks.Drive = .None
        if i == 5usize {
            drive = .Hover
            looks.aim(i, 110.0, -46.0)
        }
        if i == 6usize {
            drive = .Press
            looks.aim(i, 110.0, -46.0)
        }
        cells[i] = looks.Cell { caption: captions[i], node: boxed, drive: drive }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "dock_panel", cells: 7usize, columns: 4usize, cell_w: 290.0, cell_h: 150.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
