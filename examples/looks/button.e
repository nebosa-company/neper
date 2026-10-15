// The button in every state under every look: docs/ui/looks/<look>/button.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn one(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: widget.Key, caption: str, variant: style.ControlVariant, enabled: bool, wide: bool) -> (widget.Node, err) {
    var options = control.button_options()
    options.variant = variant
    options.enabled = enabled
    if wide {
        options.width = 85.0
        options.height = 25.0
    }
    let (node, node_error) = control.button(a, key, t, caption, action, options)
    ret (node, node_error)
}

// Twelve cells. The plain button at rest (v3's Cancel, 75 x 23), the default (OK), a caption with a mnemonic
// (&Apply), the disabled one (v3's 85 x 25 Apply of the conditional formatting manager), the interaction states of
// the live captures (docs/ui/looks/ref/windows/states: pressed Cancel of Search for Card, the focused non-default
// Invert of Filter Card Pool, the focused default OK and the pressed OK of the conditional formatting manager, the
// pressed OK of Sort), and hover, which no capture can show (DevExpress reads the real pointer).
// The control rect is the DFM size, the visible box one less each way (see e.ui.winbutton).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let captions = [12]str{ "Normal", "Default", "Mnemonic", "Disabled 85x25", "Hover", "Pressed", "Focus", "Default focus 85x25", "Default 85x25", "Normal 85x25", "Pressed default", "Pressed 85x25" }
    let words = [12]str{ "Cancel", "OK", "&Apply", "&Apply", "Cancel", "Cancel", "Invert", "OK", "OK", "Cancel", "OK", "OK" }
    var i = 0usize
    while i < 12usize {
        var variant: style.ControlVariant = .Filled
        if i == 1usize || i == 7usize || i == 8usize || i == 10usize || i == 11usize { variant = .Default }
        let wide = i == 3usize || i == 7usize || i == 8usize || i == 9usize || i == 11usize
        let (node, node_error) = one(a, t, action, u64(i + 1usize), words[i], variant, i != 3usize, wide)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 4usize { drive = .Hover }
        if i == 5usize || i == 10usize || i == 11usize { drive = .Press }
        if i == 6usize || i == 7usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (12usize, ok)
}

// The other button kinds, button_kinds.png: a picture before the caption (v3's 125 x 25 New Rule button, rest,
// disabled, then hover, pressed and focused which no capture shows), a picture alone (the 30 x 25 up arrow, rest and
// disabled), the split button closed and open, the toggle off and on, the busy button, a long caption and the plain
// (borderless) button. Pictures are drawn glyphs; v3's are bitmaps from its image list.
fn kind(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, i: usize) -> (widget.Node, looks.Drive, str, err) {
    var options = control.button_options()
    let key = u64((i + 1usize) * 10usize)
    if i < 5usize {
        options.width = 125.0
        options.height = 25.0
        options.enabled = i != 1usize
        let words = [5]str{ "&New Rule...", "&Delete Rule", "&New Rule...", "&New Rule...", "&New Rule..." }
        let (node, node_error) = control.button_with_glyph(a, key, t, .Refresh, words[i], action, options)
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Press }
        if i == 4usize { drive = .Focus }
        let captions = [5]str{ "Icon + caption", "Disabled", "Hover", "Pressed", "Focus" }
        ret (node, drive, captions[i], node_error)
    }
    if i == 5usize || i == 6usize || i == 7usize {
        options.width = 30.0
        options.height = 25.0
        options.enabled = i != 7usize
        let (node, node_error) = control.button_with_glyph(a, key, t, .Refresh, "", action, options)
        // an even box in an odd cell: a 29 wide holder keeps it on whole pixels
        var holder = style.defaults()
        holder.width = style.Length { Px: 29.0 }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
        if parts_error != ok { ret (node, looks.Drive.None, "", parts_error) }
        parts[0usize] = node
        let held = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, holder, parts[0usize..1usize])
        var drive: looks.Drive = .None
        if i == 6usize { drive = .Hover }
        let captions = [3]str{ "Icon only", "Hover", "Disabled" }
        ret (held, drive, captions[i - 5usize], node_error)
    }
    if i == 8usize || i == 9usize {
        let (node, node_error) = control.split_button(a, key, t, "Save", action, i == 9usize, action)
        var caption = "Split"
        if i == 9usize { caption = "Split open" }
        ret (node, looks.Drive.None, caption, node_error)
    }
    if i == 10usize || i == 11usize || i == 12usize {
        let (node, node_error) = control.toggle_button(a, key, t, "Bold", i != 10usize, action, options)
        var drive: looks.Drive = .None
        if i == 12usize { drive = .Hover }
        let captions = [3]str{ "Toggle off", "Toggle on", "On, hover" }
        ret (node, drive, captions[i - 10usize], node_error)
    }
    if i == 13usize {
        options.loading = true
        let (node, node_error) = control.button(a, key, t, "Download", action, options)
        ret (node, looks.Drive.None, "Loading", node_error)
    }
    if i == 14usize {
        options.width = 151.0
        let (node, node_error) = control.button(a, key, t, "Footnote Properties...", action, options)
        ret (node, looks.Drive.None, "Long caption", node_error)
    }
    options.variant = .Plain
    let (node, node_error) = control.button(a, key, t, "Plain", action, options)
    ret (node, looks.Drive.None, "Plain", node_error)
}

fn build_kinds(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < 16usize {
        let (node, drive, caption, node_error) = kind(a, t, &actions[0usize], i)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: caption, node: node, drive: drive }
        i += 1usize
    }
    ret (16usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button", cells: 12usize, columns: 4usize, cell_w: 133.0, cell_h: 40.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    let kinds = looks.Sheet { name: "button_kinds", cells: 16usize, columns: 4usize, cell_w: 133.0, cell_h: 40.0, ctx: zero, build: build_kinds }
    ret looks.run_all(a, &kinds)
}
