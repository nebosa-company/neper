// The hint (tooltip) in its forms under every look: docs/ui/looks/<look>/hint.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// An anchor button with its hint shown (the cell is tall enough to hold the overlay).
fn anchored(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, i: usize, rich: bool, text: str, subhead: str, shortcut: str) -> (widget.Node, err) {
    let anchor_key = u64(100usize + i)
    var options = control.button_options()
    let (button, button_error) = control.button(a, anchor_key, t, "Anchor", action, options)
    if button_error != ok { ret (zero, button_error) }
    var tip: widget.Node = zero
    if rich {
        let (items, items_error) = mem.alloc[overlay.MenuItem](a, 1usize)
        if items_error != ok { ret (zero, items_error) }
        items[0usize] = overlay.MenuItem { label: "Learn more", action: *action, enabled: true }
        var shown_items = items[0usize..1usize]
        shown_items = items[0usize..0usize]
        let (made, made_error) = overlay.rich_tooltip(a, u64(5000usize + i * 100usize), t, anchor_key, subhead, text, shown_items, true)
        if made_error != ok { ret (zero, made_error) }
        tip = made
    } else {
        let (made, made_error) = overlay.tooltip_of(a, u64(5000usize + i * 100usize), t, anchor_key, text, shortcut, true)
        if made_error != ok { ret (zero, made_error) }
        tip = made
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = button
    parts[1usize] = tip
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

// Five cells, each an anchor with its hint shown: one line, wrapped lines, a shortcut, the rich
// hint with a subhead, and the v3 header hint's text. (The harness runtime holds 16384 paint
// commands: a sixth overlay makes the frame an InvalidTree.)
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [5]str{ "Plain", "Wrapped", "With shortcut", "Rich, subhead", "Short" }
    let texts = [5]str{ "Save the deck", "Cards that share a name are counted once,\nwhatever their edition or condition", "Save", "Prices are refreshed every night from TCGplayer.", "Edition" }
    var i = 0usize
    while i < 5usize {
        let rich = i == 3usize
        var subhead = ""
        if i == 3usize { subhead = "Price refresh" }
        var shortcut = ""
        if i == 2usize { shortcut = "Ctrl+S" }
        let (node, node_error) = anchored(a, t, &actions[0usize], i, rich, texts[i], subhead, shortcut)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "hint", cells: 5usize, columns: 3usize, cell_w: 260.0, cell_h: 110.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
