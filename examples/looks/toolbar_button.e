// The toolbar button (TdxBarButton) in every state under every look, and a whole dxBar strip:
// docs/ui/looks/<look>/toolbar_button.png. Run from the repository root; see
// docs/ui/looks-howto.md. Under the Windows look the buttons are flat 22 squares with a 16
// glyph (the v3 bitmaps are not available, so a drawn glyph stands in) and the strip has the
// grip, the light/dark edge lines and the separators.

use e.mem
use e.str as strs
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn glyph(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: widget.Key, kind: control.GlyphKind, label: str, enabled: bool, checked: bool, along: f32) -> (widget.Node, err) {
    if t.tokens.profile == .Windows {
        let (flat, flat_error) = control.windows_glyph_toggle_at(a, key, t, kind, label, action, enabled, checked, along)
        ret (flat, flat_error)
    }
    let (round, round_error) = control.glyph_toggle(a, key, t, kind, label, action, 32.0, 18.0, checked)
    ret (round, round_error)
}

// One bar of `buttons` (a group of the sizes in `groups` between separators), `width` wide;
// under Windows a closed dxBar strip as v3 draws it, elsewhere a plain row.
// `mask` has a 1 for each enabled button; `bar_x` is the bar's x in the row (the greys of a hot box drift along the window).
fn strip(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, base: widget.Key, groups: []const usize, width: f32, lead: u32, mask: str, first_rule: usize, bar_x: f32) -> (widget.Node, err) {
    let kinds = [9]control.GlyphKind{ .Add, .Edit, .Search, .Filter, .Settings, .Refresh, .ArrowUp, .ArrowDown, .Check }
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 16usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    var n = 0usize
    var b = 0usize
    var g = 0usize
    while g < groups.len {
        if g > 0usize && t.tokens.profile == .Windows {
            // The greys of the separators along the live toolbar (dark, light), by separator.
            let darks = [5]u32{ 163u32, 165u32, 167u32, 175u32, 178u32 }
            let lights = [5]u32{ 252u32, 249u32, 247u32, 237u32, 234u32 }
            let (rule, rule_error) = navigation.windows_bar_separator_tone(a, darks[first_rule + g - 1usize], lights[first_rule + g - 1usize])
            if rule_error != ok { ret (zero, rule_error) }
            nodes[n] = rule
            n += 1usize
        }
        var j = 0usize
        while j < groups[g] {
            let along = 8.0 + bar_x + 11.0 + 23.0 * f32(b) + 6.0 * f32(g)
            let (button, button_error) = glyph(a, t, action, base + u64(b), kinds[b % 9usize], "Tool", b < mask.len && mask[b] == 49u8, false, along)
            if button_error != ok { ret (zero, button_error) }
            nodes[n] = button
            n += 1usize
            b += 1usize
            j += 1usize
        }
        g += 1usize
    }
    if t.tokens.profile == .Windows {
        let (bar, bar_error) = navigation.windows_bar_strip(a, nodes[0usize..n], 26.0, true, width, false, lead, true)
        ret (bar, bar_error)
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), nodes[0usize..n])
    ret (row[0usize], ok)
}

// The two bars at the left of v3's second toolbar row (the buttons disabled, as captured):
// 2 + 2 + 1 + 3 buttons, then 4 + 2 + 3.
fn bars(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, base: widget.Key, enabled: bool, full: bool) -> (widget.Node, err) {
    let first = [4]usize{ 2usize, 2usize, 1usize, 3usize }
    let second = [3]usize{ 4usize, 2usize, 3usize }
    if t.tokens.profile != .Windows {
        // the Neper look keeps its round glyph buttons in one row, no separators
        let (plain, plain_error) = strip(a, t, action, base, first[0usize..4usize], 215.0, 16777215u32, "111111111", 0usize, 0.0)
        ret (plain, plain_error)
    }
    // Standard: all disabled; Cards: the last three enabled (the first six are greyed, as captured)
    var left_mask = "000000000"
    var right_mask = "000000111"
    if enabled {
        left_mask = "111111111"
        right_mask = "111111111"
    }
    let (left, left_error) = strip(a, t, action, base, first[0usize..4usize], 215.0, 16777215u32, left_mask, 0usize, 0.0)
    if left_error != ok { ret (zero, left_error) }
    let (right, right_error) = strip(a, t, action, base + 20u64, second[0usize..3usize], 232.0, 15987699u32, right_mask, 3usize, 215.0)
    if right_error != ok { ret (zero, right_error) }
    let (both, both_error) = mem.alloc[widget.Node](a, 4usize)
    if both_error != ok { ret (zero, both_error) }
    both[0usize] = left
    both[1usize] = right
    if !full { ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), both[0usize..2usize]), ok) }
    // Search (6 buttons) and Help (2), at the right of those two in v3's row: enabled in the capture, the pictures stand-ins.
    let third = [1]usize{ 6usize }
    let fourth = [1]usize{ 2usize }
    let (search, search_error) = strip(a, t, action, base + 40u64, third[0usize..1usize], 151.0, 15132390u32, "111000", 0usize, 447.0)
    if search_error != ok { ret (zero, search_error) }
    let (help, help_error) = strip(a, t, action, base + 60u64, fourth[0usize..1usize], 59.0, 14540253u32, "11", 0usize, 598.0)
    if help_error != ok { ret (zero, help_error) }
    both[2usize] = search
    both[3usize] = help
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), both[0usize..4usize]), ok)
}

// Cells: the whole strip; then one button at rest, hovered, pressed, keyboard-focused, checked,
// disabled; then the captioned form (Windows) of a rest and a hovered button.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let (bar, bar_error) = bars(a, t, action, 100u64, false, false)
    if bar_error != ok { ret (0usize, bar_error) }
    cells[0usize] = looks.Cell { caption: "Bars (Windows: v3 second toolbar row, disabled as captured)", node: bar, drive: .None }
    let captions = [9]str{ "Rest", "Hover", "Pressed", "Focus", "Checked", "Disabled", "Caption", "Caption hover", "Caption disabled" }
    var i = 0usize
    while i < 9usize {
        var node: widget.Node = zero
        var node_error: err = ok
        if i < 6usize {
            let (g, g_error) = glyph(a, t, action, 200u64 + u64(i), .Search, "Search", i != 5usize, i == 4usize, 466.0)
            node = g
            node_error = g_error
        } else if t.tokens.profile == .Windows {
            let (b, b_error) = control.windows_bar_button(a, 200u64 + u64(i), t, "Print", action, i != 8usize, false)
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
    ret (10usize, ok)
}

fn placed(a: *mem.Arena, node: widget.Node, x: f32, w: f32, h: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = node
    ret (widget.padded(0u64, x, 0.0, 0.0, 0.0, control.sized_style(w, h), inner[0usize..1usize]), ok)
}

// The hot and pressed buttons of the live grabs (ref/windows/states/hover-toolbar-button-*): the whole toolbar row, one
// cell per grab, shifted so that the button under v3's pointer sits at the cell's centre (where the harness's pointer goes).
fn build_hot(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let names = [9]str{ "Cards expand hot", "Cards F hot", "Search filter hot", "Search filter plus hot", "Search binoculars hot", "Help home hot", "Help discord hot", "Search filter pressed", "Search binoculars pressed" }
    let xs = [9]f32{ 384.0, 407.0, 466.0, 489.0, 512.0, 617.0, 640.0, 466.0, 512.0 }
    var i = 0usize
    while i < 9usize {
        let (row, row_error) = bars(a, t, &actions[0usize], 1000u64 * u64(i + 1usize), false, true)
        if row_error != ok { ret (0usize, row_error) }
        let dx = 657.0 - (xs[i] - 8.0) - 11.0
        let (shown, shown_error) = placed(a, row, dx, 1314.0, 26.0)
        if shown_error != ok { ret (0usize, shown_error) }
        var drive: looks.Drive = .Hover
        if i >= 7usize { drive = .Press }
        cells[i] = looks.Cell { caption: names[i], node: shown, drive: drive }
        i += 1usize
    }
    ret (10usize, ok)
}

// The whole toolbar row of the main window: Standard and Cards (disabled as captured), Search and Help (enabled).
fn build_row(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let (bar, bar_error) = bars(a, t, &actions[0usize], 100u64, false, true)
    if bar_error != ok { ret (0usize, bar_error) }
    cells[0usize] = looks.Cell { caption: "Toolbar row (Standard, Cards, Search, Help)", node: bar, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize && strs.eq(args[1usize], "toolbar_button_hot") {
        let hot = looks.Sheet { name: "toolbar_button_hot", cells: 9usize, columns: 1usize, cell_w: 1314.0, cell_h: 26.0, ctx: zero, build: build_hot }
        ret looks.run_all(a, &hot)
    }
    if args.len > 1usize {
        let row = looks.Sheet { name: "toolbar_button_row", cells: 1usize, columns: 1usize, cell_w: 657.0, cell_h: 26.0, ctx: zero, build: build_row }
        ret looks.run_all(a, &row)
    }
    let sheet = looks.Sheet { name: "toolbar_button", cells: 10usize, columns: 1usize, cell_w: 447.0, cell_h: 26.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
