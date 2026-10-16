// Scale test sheets for the Windows look's baked tiles: docs/ui/looks/<look>/scale_button.png, scale_marks.png and
// scale_edits.png, at 1.0 and 1.5 (and 1.25 or 2 with NEPER_LOOKS_SCALE, see e.ui.looks). Cell sizes are not whole
// numbers, so every control lands on a fractional logical position and the tiles must still sit on whole device
// pixels (e.ui.winpx). Review the @1.5x sheets by eye: no dotted seam, no lost border, no blur on a 1 px edge.
// One sheet per run: scale_tiles.exe [scale_button|scale_marks|scale_edits]. Run from the repository root; see
// docs/ui/looks-howto.md.

use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_number(ctx: *void, value: i64) -> err { ret ok }

fn action_of(a: *mem.Arena) -> (*const widget.Submit, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    ret (&actions[0usize], ok)
}

// Buttons: rest, default, pressed, focused, the 85 x 25 default focused and disabled.
fn build_button(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = action_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let captions = [6]str{ "Rest", "Default", "Pressed", "Focused", "Default focused", "Disabled" }
    let words = [6]str{ "Cancel", "OK", "Cancel", "Invert", "OK", "&Apply" }
    var i = 0usize
    while i < 6usize {
        var options = control.button_options()
        if i == 1usize || i == 4usize { options.variant = .Default }
        if i == 4usize || i == 5usize {
            options.width = 85.0
            options.height = 25.0
        }
        options.enabled = i != 5usize
        let (node, node_error) = control.button(a, u64(i + 1usize), t, words[i], action, options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Press }
        if i == 3usize || i == 4usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

// Check boxes and radios: unchecked, checked, pressed and focused each.
fn build_marks(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = action_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let captions = [8]str{ "Check off", "Check on", "Check pressed", "Check focus", "Radio off", "Radio on", "Radio pressed", "Radio focus" }
    var i = 0usize
    while i < 8usize {
        let column = i % 4usize
        let chosen = column == 1usize
        var drive: looks.Drive = .None
        if column == 2usize { drive = .Press }
        if column == 3usize { drive = .Focus }
        if i < 4usize {
            let (node, node_error) = control.checkbox(a, u64(i + 1usize), t, "Show tooltips", chosen, false, action, true)
            if node_error != ok { ret (0usize, node_error) }
            cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        } else {
            let (node, node_error) = control.radio(a, u64(i + 1usize), t, "Move to next column", chosen, action, true)
            if node_error != ok { ret (0usize, node_error) }
            cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        }
        i += 1usize
    }
    ret (8usize, ok)
}

// A text edit at rest and focused, a spin edit at rest and focused, a button edit at rest and focused.
fn build_edits(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (submits, submits_error) = mem.alloc[widget.Submit](a, 1usize)
    if submits_error != ok { ret (0usize, submits_error) }
    submits[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [6]str{ "Text", "Text focus", "Spin", "Spin focus", "Button edit", "Button edit focus" }
    var i = 0usize
    while i < 6usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let words = "D:/Decks"
        var n = 0usize
        while n < words.len {
            buffer[n] = words[n]
            n += 1usize
        }
        let key = u64(10usize * (i + 1usize))
        var drive: looks.Drive = .None
        if i % 2usize == 1usize { drive = .Focus }
        if i < 2usize {
            var options = control.field_options()
            options.width = 120.0
            options.placeholder = ""
            let (node, node_error) = control.text_field(a, key, t, "Card name", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
            if node_error != ok { ret (0usize, node_error) }
            cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        } else if i < 4usize {
            let (node, node_error) = control.spin_box_sized(a, key, t, "Quantity", buffer, 7i64, 1i64, 99i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_number }, widget.Change[str] { ctx: zero, invoke: noop_change }, 70.0)
            if node_error != ok { ret (0usize, node_error) }
            cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        } else {
            var options = control.field_options()
            options.width = 110.0
            options.placeholder = ""
            let (node, node_error) = control.button_edit(a, key, t, "Folder", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, submits[0usize], &submits[0usize], "Browse", options)
            if node_error != ok { ret (0usize, node_error) }
            cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        }
        i += 1usize
    }
    ret (6usize, ok)
}

// One sheet per process (the CPU gpu backend opens at most 16 devices and a sheet opens six): the argument names it,
// scale_button when none is given.
fn main(a: *mem.Arena, args: []str) -> err {
    var only = "scale_button"
    if args.len > 1usize { only = args[1usize] }
    if strs.eq(only, "scale_marks") {
        let marks = looks.Sheet { name: "scale_marks", cells: 8usize, columns: 4usize, cell_w: 150.4, cell_h: 32.6, ctx: zero, build: build_marks }
        ret looks.run_all(a, &marks)
    }
    if strs.eq(only, "scale_edits") {
        let edits = looks.Sheet { name: "scale_edits", cells: 6usize, columns: 3usize, cell_w: 160.3, cell_h: 56.7, ctx: zero, build: build_edits }
        ret looks.run_all(a, &edits)
    }
    let buttons = looks.Sheet { name: "scale_button", cells: 6usize, columns: 3usize, cell_w: 133.3, cell_h: 40.7, ctx: zero, build: build_button }
    ret looks.run_all(a, &buttons)
}
