// The window title bar with the pointer on a caption button, as the hover grabs of the live v3 show it
// (docs/ui/looks/ref/windows/states/hover-caption-*): the main window with its close, maximise and minimise button hot,
// the main window and Options inactive with the pointer left on the close button (the grabs keep it hot). Hover is
// driven at the middle of the cell, so each bar is placed in the cell with the button under it.
// Run from the repository root; see docs/ui/looks-howto.md. scripts/looks_ref_a/tbh.py builds the reference sheet.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn cell_w() -> f32 { ret 1600.0 }

fn t_widths() -> [6]f32 { ret [6]f32{ 784.0, 784.0, 784.0, 784.0, 712.0, 712.0 } }
// the x of the bar in the 1600 wide cell: the middle of the cell (800) falls on the hot button
fn t_offsets() -> [6]f32 { ret [6]f32{ 39.0, 85.0, 131.0, 39.0, 105.0, 105.0 } }
fn t_actives() -> [6]bool { ret [6]bool{ true, true, true, false, true, false } }
fn t_titles() -> [6]str { ret [6]str{ "MTG Studio - Card Pool [Assertions] [No Optimization]", "MTG Studio - Card Pool [Assertions] [No Optimization]", "MTG Studio - Card Pool [Assertions] [No Optimization]", "MTG Studio - Card Pool [Assertions] [No Optimization]", "Options", "Options" } }
fn t_captions() -> [6]str { ret [6]str{ "Main: close hot", "Main: maximise hot", "Main: minimise hot", "Main inactive: close hot", "Options: close hot", "Options inactive: close hot" } }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let widths = t_widths()
    let offsets = t_offsets()
    let actives = t_actives()
    let titles = t_titles()
    let captions = t_captions()
    var i = 0usize
    while i < 6usize {
        var options = navigation.title_bar_options(.Windows)
        options.active = actives[i]
        options.minimizable = i < 4usize
        options.maximizable = i < 4usize
        let (bar, bar_error) = navigation.title_bar(a, u64(i + 1usize) * 10u64, t, titles[i], options, widths[i])
        if bar_error != ok { ret (0usize, bar_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = widget.positioned(0u64, offsets[i], 0.0, style.defaults(), control.mem_one_node(a, bar))
        let holder = control.sized_style(cell_w(), 31.0)
        let boxed = widget.stack(0u64, holder, held[0usize..1usize])
        cells[i] = looks.Cell { caption: captions[i], node: boxed, drive: .Hover }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "title_bar_hover", cells: 6usize, columns: 1usize, cell_w: cell_w(), cell_h: 31.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
