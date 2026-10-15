// The page control (TcxPageControl tabs) in every state under every look:
// docs/ui/looks/<look>/page_control.png. Run from the repository root.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// A page: the dialog face with a frame, standing for the tab sheet.
fn page() -> widget.Node {
    var s = style.defaults()
    s.height = style.Length { Px: 60.0 }
    ret widget.box(0u64, s, zero)
}

// Six cells: the tab bar with the second tab selected, with the pointer over an unselected tab,
// pressed on it, keyboard-focused, with a disabled tab and the last selected, and the tab view
// (bar over a page). The harness holds 128 element states, which caps a sheet at about six bars.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 4usize)
    if actions_error != ok { ret (0usize, actions_error) }
    var k = 0usize
    while k < 4usize {
        actions[k] = widget.Submit { ctx: zero, invoke: noop_submit }
        k += 1usize
    }
    let labels = [4]str{ "Colors", "Rarity", "Card Type", "Editions" }
    let (off, off_error) = mem.alloc[bool](a, 4usize)
    if off_error != ok { ret (0usize, off_error) }
    off[0usize] = false
    off[1usize] = false
    off[2usize] = true
    off[3usize] = false
    let captions = [6]str{ "Rest", "Hover", "Pressed", "Focus", "Disabled, last selected", "Tab view" }
    var i = 0usize
    while i < 6usize {
        var options = control.tabs_options()
        options.width = 300.0
        var selected = 1usize
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        if i == 1usize || i == 2usize || i == 3usize { selected = 0usize }
        if i == 4usize {
            options.disabled = off[0usize..4usize]
            selected = 3usize
        }
        
        
        
        let key = u64(1000usize * (i + 1usize))
        var bar: widget.Node = zero
        if i == 5usize {
            let (pages, pages_error) = mem.alloc[widget.Node](a, 4usize)
            if pages_error != ok { ret (0usize, pages_error) }
            k = 0usize
            while k < 4usize {
                pages[k] = page()
                k += 1usize
            }
            let (view, view_error) = control.tab_view(a, key, t, labels[0usize..4usize], 1usize, actions[0usize..4usize], pages[0usize..4usize])
            if view_error != ok { ret (0usize, view_error) }
            bar = view
        } else {
            let (made, bar_error) = control.tabs_of(a, key, t, labels[0usize..4usize], selected, actions[0usize..4usize], options)
            if bar_error != ok { ret (0usize, bar_error) }
            bar = made
        }
        cells[i] = looks.Cell { caption: captions[i], node: bar, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let bottom = looks.Sheet { name: "page_control_bottom", cells: 4usize, columns: 2usize, cell_w: 300.0, cell_h: 60.0, ctx: zero, build: build_bottom }
        ret looks.run_all(a, &bottom)
    }
    let sheet = looks.Sheet { name: "page_control", cells: 6usize, columns: 3usize, cell_w: 310.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}

// The card info strip of the v3 main window (tpBottom, two picture tabs, no captions) as the
// live capture ref/windows/page_control_bottom.png shows it: the preview tab chosen, the other
// chosen, the pointer over the unchosen one, and a strip with captions (the decks strip).
// v3's pictures are bitmaps; glyphs stand in.
fn build_bottom(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 3usize)
    if actions_error != ok { ret (0usize, actions_error) }
    var k = 0usize
    while k < 3usize {
        actions[k] = widget.Submit { ctx: zero, invoke: noop_submit }
        k += 1usize
    }
    let pictures = [3]control.GlyphKind{ .Picture, .Calendar, .Search }
    let blank = [3]str{ "", "", "" }
    let named = [3]str{ "Deck", "Collection", "Notes" }
    let captions = [4]str{ "Preview chosen", "Prices chosen", "Hover", "With captions" }
    var i = 0usize
    while i < 4usize {
        var options = control.tabs_options()
        options.bottom = true
        options.width = 280.0
        var selected = 0usize
        var drive: looks.Drive = .None
        if i == 1usize { selected = 1usize }
        if i == 2usize { drive = .Hover }
        var labels = blank[0usize..2usize]
        if i == 3usize { labels = named[0usize..3usize] }
        if i != 3usize { options.icons = pictures[0usize..2usize] }
        let (bar, bar_error) = control.tabs_of(a, u64(1000usize * (i + 1usize)), t, labels, selected, actions[0usize..labels.len], options)
        if bar_error != ok { ret (0usize, bar_error) }
        cells[i] = looks.Cell { caption: captions[i], node: bar, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}
