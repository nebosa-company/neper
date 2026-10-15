// The status bar (TdxStatusBar) in its states under every look: docs/ui/looks/<look>/status_bar.png.
// Run from the repository root; see docs/ui/looks-howto.md. Cells: v3's three panels (the
// counts, an empty one, "Idle"), the progress container panel, a pressable panel hovered, and
// an error-tone message. The Windows look draws sunken panels and the size grip.

use e.mem
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
    let captions = [5]str{ "Rest", "Progress panel", "Pressable panel (hover)", "Error tone", "Narrow (panels hug their text)" }
    var i = 0usize
    while i < 5usize {
        let (items, items_error) = mem.alloc[navigation.StatusItem](a, 3usize)
        if items_error != ok { ret (0usize, items_error) }
        items[0usize] = navigation.status_item("Sel: 0 Fil: 120 283 Shown: 120 283 All: 120 283 Rec: 1")
        items[1usize] = navigation.status_item("")
        items[2usize] = navigation.status_item("Idle")
        var width: f32 = 784.0
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
            x = 251.0
            width = 533.0
        }
        if i == 3usize {
            items[0usize] = navigation.status_item("Could not reach the price server")
            items[0usize].tone = .Error
        }
        if i == 4usize { width = 300.0 }
        // v3's three panels at 100 %: 282 centred, 153, the rest (the DFM: 200 centred, 150, rest).
        if i != 4usize {
            items[0usize].panel_width = 282.0
            items[0usize].centered = true
            items[1usize].panel_width = 153.0
            items[2usize].fills = true
        }
        let (bar, bar_error) = navigation.status_bar_of(a, 1000u64 * u64(i + 1usize), t, items[0usize..3usize], false, width)
        if bar_error != ok { ret (0usize, bar_error) }
        let (shown, shown_error) = placed(a, bar, x, 0.0, 784.0, 19.0)
        if shown_error != ok { ret (0usize, shown_error) }
        cells[i] = looks.Cell { caption: captions[i], node: shown, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

// The report preview window's status bar (ref/windows/status_bar_report.png: 1280 x 19 at (8, 742) of
// dialogs/reports-combos-from-collection@1x.png): "Page 1 of 1" in a first panel, one panel for the rest.
fn build_report(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (items, items_error) = mem.alloc[navigation.StatusItem](a, 3usize)
    if items_error != ok { ret (0usize, items_error) }
    items[0usize] = navigation.status_item("Page 1 of 1")
    items[0usize].drop_order = 77u8
    items[0usize].panel_width = 199.0
    items[1usize] = navigation.status_item("")
    items[1usize].panel_width = 538.0
    items[2usize] = navigation.status_item("")
    items[2usize].fills = true
    let (bar, bar_error) = navigation.status_bar_of(a, 9000u64, t, items[0usize..3usize], false, 1280.0)
    if bar_error != ok { ret (0usize, bar_error) }
    let (shown, shown_error) = placed(a, bar, 0.0, 0.0, 1280.0, 19.0)
    if shown_error != ok { ret (0usize, shown_error) }
    cells[0usize] = looks.Cell { caption: "Report preview window", node: shown, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let report = looks.Sheet { name: "status_bar_report", cells: 1usize, columns: 1usize, cell_w: 1280.0, cell_h: 19.0, ctx: zero, build: build_report }
        ret looks.run_all(a, &report)
    }
    let sheet = looks.Sheet { name: "status_bar", cells: 5usize, columns: 1usize, cell_w: 784.0, cell_h: 19.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
