// The button in every state under every look: docs/ui/looks/<look>/button.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn one(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: widget.Key, variant: style.ControlVariant, enabled: bool) -> (widget.Node, err) {
    var options = control.button_options()
    options.variant = variant
    options.enabled = enabled
    let (node, node_error) = control.button(a, key, t, "Cancel", action, options)
    ret (node, node_error)
}

// Eight cells: the plain button at rest, hovered, pressed, keyboard-focused and disabled, then
// the default button (the one Enter presses) at rest, hovered and focused.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let captions = [8]str{ "Normal", "Hover", "Pressed", "Focus", "Disabled", "Default", "Default hover", "Default focus" }
    var i = 0usize
    while i < 8usize {
        var variant: style.ControlVariant = .Filled
        if i >= 5usize { variant = .Default }
        let (node, node_error) = one(a, t, action, u64(i + 1usize), variant, i != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize || i == 6usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize || i == 7usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

// The other button kinds, button_kinds.png: a picture before the caption (rest, hover, pressed,
// focused, disabled), a picture alone, the split button closed and open, the toggle off and on,
// the busy button, a long caption and the plain (borderless) button. Pictures are drawn glyphs.
fn kind(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, i: usize) -> (widget.Node, looks.Drive, str, err) {
    var options = control.button_options()
    let key = u64((i + 1usize) * 10usize)
    if i == 0usize || i == 1usize || i == 2usize || i == 3usize || i == 4usize {
        options.enabled = i != 4usize
        let (node, node_error) = control.button_with_glyph(a, key, t, .Refresh, "Refresh", action, options)
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        let captions = [5]str{ "Icon + caption", "Hover", "Pressed", "Focus", "Disabled" }
        ret (node, drive, captions[i], node_error)
    }
    if i == 5usize || i == 6usize || i == 7usize {
        options.enabled = i != 7usize
        let (node, node_error) = control.button_with_glyph(a, key, t, .Refresh, "", action, options)
        var drive: looks.Drive = .None
        if i == 6usize { drive = .Hover }
        let captions = [3]str{ "Icon only", "Hover", "Disabled" }
        ret (node, drive, captions[i - 5usize], node_error)
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
    let sheet = looks.Sheet { name: "button", cells: 8usize, columns: 4usize, cell_w: 110.0, cell_h: 40.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    let kinds = looks.Sheet { name: "button_kinds", cells: 16usize, columns: 4usize, cell_w: 130.0, cell_h: 40.0, ctx: zero, build: build_kinds }
    ret looks.run_all(a, &kinds)
}
