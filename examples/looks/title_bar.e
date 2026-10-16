// The window title bar (the dialog's caption) under every look:
// docs/ui/looks/<look>/title_bar.png. Part of the dialog control (see dialog.e).
// Run from the repository root; see docs/ui/looks-howto.md.
//
// The Windows cells are v3's real captions at their real widths (the visible width of the captured window: the PNG
// less the 8 px invisible resize border on each side and below), one per captured window: Search for Card, About and
// Options (active and inactive), Deck Legality (resizable: minimise disabled, maximise, close), Filter Card Pool (all
// three), Statistics, Deck Properties, Sort, Missing Set Cards, the two light captions of the DevExpress dialogs (Advanced
// Filter, Conditional Formatting Rules Manager), the Customization tool window, and the main window active and inactive.
// The last two cells (close hovered, maximised) have no capture. scripts/looks_ref_a/tb5.py builds the reference sheet.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.widget
use e.ui.window as win

fn cell_w() -> f32 { ret 941.0 }

// kind: 0 dialog (close only), 1 resizable with minimise disabled, 2 resizable with all three, 3 light, 4 tool window
fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, title: str, active: bool, kind: u32, restored: bool, width: f32) -> (widget.Node, err) {
    var options = navigation.title_bar_options(.Windows)
    options.active = active
    options.minimizable = kind == 2u32
    options.maximizable = kind == 1u32 || kind == 2u32
    options.light = kind == 3u32
    options.tool = kind == 4u32
    if restored { options.mode = .Maximized }
    let (node, node_error) = navigation.title_bar(a, key, t, title, options, width)
    ret (node, node_error)
}

fn t_titles() -> [18]str { ret [18]str{ "Search for Card", "About MTG Studio", "About MTG Studio", "Deck Legality", "Options", "Options", "Filter Card Pool", "Statistics", "Deck Properties", "Sort [Card Pool]", "Missing Set Cards", "Advanced Filter", "Conditional Formatting Rules Manager", "Customization", "MTG Studio - Card Pool [Assertions] [No Optimization]", "MTG Studio - Card Pool [Assertions] [No Optimization]", "Search for Card", "Deck Legality" } }
fn t_captions() -> [18]str { ret [18]str{ "Search for Card: dialog, active", "About: inactive", "About: active", "Deck Legality: resizable", "Options: inactive", "Options: active", "Filter Card Pool: min, max, close", "Statistics: dialog", "Deck Properties", "Sort", "Missing Set Cards", "Advanced Filter: light caption", "Cond. Formatting: light caption", "Customization: tool window", "Main window: long title", "Main window: inactive", "Close hovered (no capture)", "Maximised (no capture)" } }
fn t_widths() -> [18]f32 { ret [18]f32{ 309.0, 436.0, 436.0, 539.0, 712.0, 712.0, 692.0, 941.0, 348.0, 351.0, 250.0, 544.0, 684.0, 164.0, 784.0, 784.0, 309.0, 539.0 } }
fn t_actives() -> [18]bool { ret [18]bool{ true, false, true, true, false, true, true, true, true, true, true, true, true, true, true, false, true, true } }
fn t_kinds() -> [18]u32 { ret [18]u32{ 0u32, 0u32, 0u32, 1u32, 0u32, 0u32, 2u32, 0u32, 0u32, 0u32, 0u32, 3u32, 3u32, 4u32, 2u32, 2u32, 0u32, 1u32 } }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let titles = t_titles()
    let captions = t_captions()
    let widths = t_widths()
    let actives = t_actives()
    let kinds = t_kinds()
    var i = 0usize
    while i < 18usize {
        let (node, node_error) = one(a, t, u64(i + 1usize) * 10u64, titles[i], actives[i], kinds[i], i == 17usize, widths[i])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 16usize { drive = .Hover }
        // a bar of odd margin in the cell would sit on a half pixel: a holder one wider puts it on whole ones
        var holder = control.sized_style(widths[i] + f32(u32(cell_w() - widths[i]) % 2u32), 31.0)
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = node
        let boxed = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, holder, held[0usize..1usize])
        cells[i] = looks.Cell { caption: captions[i], node: boxed, drive: drive }
        i += 1usize
    }
    ret (18usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Hover is driven at the middle of the cell: for the close-only bar that is not the X, so the cell shows the rest bar.
    let sheet = looks.Sheet { name: "title_bar", cells: 18usize, columns: 1usize, cell_w: cell_w(), cell_h: 31.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
