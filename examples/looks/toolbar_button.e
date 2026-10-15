// The toolbar button (TdxBarButton) in every state under every look, and a whole dxBar strip:
// docs/ui/looks/<look>/toolbar_button.png. Run from the repository root; see
// docs/ui/looks-howto.md. Under the Windows look the buttons are flat 22 squares with a 16
// glyph (the v3 bitmaps are not available, so a drawn glyph stands in) and the strip has the
// grip, the light/dark edge lines and the separators.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn glyph(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: widget.Key, kind: control.GlyphKind, label: str, enabled: bool, checked: bool) -> (widget.Node, err) {
    if t.tokens.profile == .Windows {
        let (flat, flat_error) = control.windows_glyph_toggle(a, key, t, kind, label, action, enabled, checked)
        ret (flat, flat_error)
    }
    let (round, round_error) = control.glyph_toggle(a, key, t, kind, label, action, 32.0, 18.0, checked)
    ret (round, round_error)
}

fn strip(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, base: widget.Key) -> (widget.Node, err) {
    let kinds = [8]control.GlyphKind{ .Add, .Edit, .Search, .Filter, .Settings, .Refresh, .ArrowUp, .ArrowDown }
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 10usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    var n = 0usize
    var i = 0usize
    while i < 8usize {
        if i == 3usize || i == 6usize {
            let (rule, rule_error) = navigation.windows_bar_separator(a, 22.0)
            if rule_error != ok { ret (zero, rule_error) }
            nodes[n] = rule
            n += 1usize
        }
        let (button, button_error) = glyph(a, t, action, base + u64(i), kinds[i], "Tool", i != 5usize, i == 2usize)
        if button_error != ok { ret (zero, button_error) }
        nodes[n] = button
        n += 1usize
        i += 1usize
    }
    if t.tokens.profile == .Windows {
        let (bar, bar_error) = navigation.windows_bar_strip(a, nodes[0usize..n], 24.0, true, 300.0)
        ret (bar, bar_error)
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, nodes_error) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), nodes[0usize..n])
    ret (row[0usize], ok)
}

// Cells: the whole strip; then one button at rest, hovered, pressed, keyboard-focused, checked,
// disabled; then the captioned form (Windows) of a rest and a hovered button.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let (bar, bar_error) = strip(a, t, action, 100u64)
    if bar_error != ok { ret (0usize, bar_error) }
    cells[0usize] = looks.Cell { caption: "Strip", node: bar, drive: .None }
    let captions = [8]str{ "Rest", "Hover", "Pressed", "Focus", "Checked", "Disabled", "Caption", "Caption hover" }
    var i = 0usize
    while i < 8usize {
        var node: widget.Node = zero
        var node_error: err = ok
        if i < 6usize {
            let (g, g_error) = glyph(a, t, action, 200u64 + u64(i), .Search, "Search", i != 5usize, i == 4usize)
            node = g
            node_error = g_error
        } else if t.tokens.profile == .Windows {
            let (b, b_error) = control.windows_bar_button(a, 200u64 + u64(i), t, "Print", action, true, false)
            node = b
            node_error = b_error
        } else {
            let (b, b_error) = control.button(a, 200u64 + u64(i), t, "Print", action, control.button_options())
            node = b
            node_error = b_error
        }
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize || i == 7usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        cells[i + 1usize] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (9usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "toolbar_button", cells: 9usize, columns: 3usize, cell_w: 320.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
