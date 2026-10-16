// The Android look's status bar: a bottom app bar style strip (surface-container, 80 dp at touch density) holding the status
// panels as supporting text, with the progress, pressable and error forms (docs/ui/looks/material/status_bar.png).
// Run from the repository root.

use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn placed(a: *mem.Arena, node: widget.Node, x: f32, y: f32, w: f32, h: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = node
    ret (widget.padded(0u64, x, y, 0.0, 0.0, control.sized_style(w, h), inner[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [5]str{ "Enabled", "Progress panel", "Pressable panel, hovered", "Error", "Narrow" }
    var i = 0usize
    while i < 5usize {
        let (items, items_error) = mem.alloc[navigation.StatusItem](a, 3usize)
        if items_error != ok { ret (0usize, items_error) }
        items[0usize] = navigation.status_item("Sel: 0 Fil: 120 283 Shown: 120 283 All: 120 283 Rec: 1")
        items[1usize] = navigation.status_item("")
        items[2usize] = navigation.status_item("Idle")
        var width: f32 = 640.0
        var x: f32 = 0.0
        var drive: looks.Drive = .None
        if i == 1usize {
            items[0usize] = navigation.status_item("Updating prices")
            items[1usize].progress = 0.45
        }
        if i == 2usize {
            items[0usize] = navigation.status_item("Where are the card images?")
            items[0usize].action = actions[0usize]
            drive = .Hover
            // the first panel's centre under the pointer (the cell's centre)
            x = 170.0
            width = 470.0
        }
        if i == 3usize {
            items[0usize] = navigation.status_item("Could not reach the price server")
            items[0usize].tone = .Error
        }
        if i == 4usize { width = 300.0 }
        // v3's three panels at 100 %: 282 centred, 153, the rest (the DFM: 200 centred, 150, rest).
        if i != 4usize {
            items[0usize].panel_width = 300.0
            items[1usize].panel_width = 120.0
            items[2usize].fills = true
        }
        let (bar, bar_error) = navigation.status_bar_of(a, 1000u64 * u64(i + 1usize), t, items[0usize..3usize], false, width)
        if bar_error != ok { ret (0usize, bar_error) }
        let (shown, shown_error) = placed(a, bar, x, 0.0, 640.0, 56.0)
        if shown_error != ok { ret (0usize, shown_error) }
        cells[i] = looks.Cell { caption: captions[i], node: shown, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "status_bar", cells: 5usize, columns: 2usize, cell_w: 640.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
