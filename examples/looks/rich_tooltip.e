// Round 62 c: the rich tooltip in all ten looks: subhead, text and an action; text only; subhead and text; two actions.
// The anchors are left unpainted so each cell holds the tooltip alone. Derived from the shared tokens, no platform capture.
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_y85
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn anchored(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, i: usize, subhead: str, text: str, actions: usize) -> (widget.Node, err) {
    let anchor_key = u64(100usize + i)
    var options = control.button_options()
    options.variant = .Outlined
    let (button, button_error) = control.button(a, anchor_key, t, "Anchor", action, options)
    if button_error != ok { ret (zero, button_error) }
    var unseen = button
    unseen.style.opacity = 0.0
    let (items, items_error) = mem.alloc[overlay.MenuItem](a, 2usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = overlay.MenuItem { label: "Learn more", action: *action, enabled: true }
    items[1usize] = overlay.MenuItem { label: "Dismiss", action: *action, enabled: true }
    let (tip, tip_error) = overlay.rich_tooltip(a, u64(5000usize + i * 100usize), t, anchor_key, subhead, text, items[0usize..actions], true)
    if tip_error != ok { ret (zero, tip_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = unseen
    parts[1usize] = tip
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = column
    // The tooltip hangs from the anchor's right edge, so the anchor sits at the cell's right and the card stays inside the image; the
    // space under the anchor holds the card, so the pair centres in the cell instead of the anchor alone.
    ret (widget.padded(0u64, 250.0, 0.0, 0.0, 170.0, style.defaults(), held[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: accent text and the keyboard ring take the increased-contrast blue (0x0040DD, 0x409CFF); other looks get their own tokens back.
    let (tokens, tokens_error) = looks_y85.tinted_ring(a, base.tokens, 0x0040DDu32, 0x409CFFu32)
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *base
    themed.tokens = tokens
    let t = &themed
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [6]str{ "Subhead, text, action", "Text only", "Subhead, text", "Two actions", "Wrapped text, no action", "Subhead, wrapped text, no action" }
    let heads = [6]str{ "Price refresh", "", "Price refresh", "Price refresh", "", "Price refresh" }
    let counts = [6]usize{ 1usize, 0usize, 0usize, 2usize, 0usize, 0usize }
    let long = "Prices are refreshed every night and can lag a day."
    let texts = [6]str{ long, "Refreshed nightly.", "Refreshed nightly.", long, long, long }
    var i = 0usize
    while i < 6usize {
        let (node, node_error) = anchored(a, t, &actions[0usize], i, heads[i], texts[i], counts[i])
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "rich_tooltip", cells: 6usize, columns: 2usize, cell_w: 360.0, cell_h: 270.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
