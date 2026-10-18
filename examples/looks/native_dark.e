// The Windows dark look beside the native Windows 11 dark captures (docs/ui/looks/ref/windows-native/dark), round 12.
// One cell per captured state of the edit, spin edit and combo box, each at the capture's text and geometry (a native edit is
// 150 x 24: DFM width 149, the control paints one pixel more), so scripts/looks_strict_dark.py can diff every one without
// cutting rows. Only the windows-dark look is of interest: run with NEPER_LOOKS_OUT=<scratch> and copy
// <scratch>/windows-dark/native_dark.png into docs/ui/looks/windows-dark.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_value(ctx: *void, value: i64) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

fn cell_w() -> f32 { ret 200.0 }
fn cell_h() -> f32 { ret 100.0 }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

fn select_all(t: *const control.Theme, key: widget.Key, len: usize) {
    if mem.address_of(t.runtime) == 0usize { ret }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret }
    let unused = widget.edit_select(t.runtime, id, 0usize, len)
}

// `node` with a spacer to its right (and below) so that the middle of the whole box, where the harness puts the pointer, lands `x` px
// from the control's left edge and `y` px from its top.
fn aimed(a: *mem.Arena, node: widget.Node, w: f32, h: f32, x: f32, y: f32) -> (widget.Node, err) {
    let (column, column_error) = mem.alloc[widget.Node](a, 2usize)
    if column_error != ok { ret (zero, column_error) }
    // below the control when y is past the middle, above it otherwise
    if 2.0 * y >= h {
        column[0usize] = node
        column[1usize] = widget.box(0u64, sized(1.0, 2.0 * y - h), zero)
    } else {
        column[0usize] = widget.box(0u64, sized(1.0, h - 2.0 * y), zero)
        column[1usize] = node
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 2usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), column[0usize..2usize])
    row[1usize] = widget.box(0u64, sized(max_f(0.0, 2.0 * x - w), 1.0), zero)
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), row[0usize..2usize]), ok)
}

// `node` at a whole pixel (x, y) of a cell-sized holder, so an odd sized control does not land on a half pixel.
fn placed(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
    ret (widget.stack(0u64, sized(cell_w(), cell_h()), inner[0usize..1usize]), ok)
}

fn max_f(a: f32, b: f32) -> f32 {
    if a > b { ret a }
    ret b
}

fn edit_cell(a: *mem.Arena, t: *const control.Theme, i: usize) -> (widget.Node, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    var text = "Text value"
    if i == 6usize { text = "secret" }
    let n = control.copy_text(buffer, text)
    var options = control.field_options()
    options.width = 149.0
    if i == 5usize { options.enabled = false }
    if i == 4usize { options.read_only = true }
    let key = u64(i + 1usize)
    if i == 6usize {
        let (word, word_error) = control.password_field(a, key, t, "Edit", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
        if word_error != ok { ret (zero, word_error) }
        let (whole_word, whole_word_error) = placed(a, word, 25.0, 38.0)
        ret (whole_word, whole_word_error)
    }
    let (field, field_error) = control.text_field(a, key, t, "Edit", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
    if field_error != ok { ret (zero, field_error) }
    // round 13: on a whole pixel, as the control sits in the capture (149 wide centred in 200 would land on x + 0.5)
    let (whole_field, whole_field_error) = placed(a, field, 25.0, 38.0)
    ret (whole_field, whole_field_error)
}

fn spin_cell(a: *mem.Arena, t: *const control.Theme, i: usize) -> (widget.Node, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 24usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    var value = 5i64
    if i == 3usize { value = 6i64 }
    let key = u64(100usize + 10usize * i)
    let (spin, spin_error) = control.spin_box_full(a, key, t, "Spin", buffer, value, 0i64, 99i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_value }, widget.Change[str] { ctx: zero, invoke: noop_change }, 73.0, i != 6usize, false)
    if spin_error != ok { ret (zero, spin_error) }
    if i == 1usize {
        let (moved, moved_error) = aimed(a, spin, 74.0, 24.0, 67.0, 6.0)
        ret (moved, moved_error)
    }
    if i == 2usize {
        let (moved, moved_error) = aimed(a, spin, 74.0, 24.0, 67.0, 18.0)
        ret (moved, moved_error)
    }
    if i == 3usize {
        let (moved, moved_error) = aimed(a, spin, 74.0, 24.0, 67.0, 6.0)
        ret (moved, moved_error)
    }
    if i == 4usize {
        let (moved, moved_error) = aimed(a, spin, 74.0, 24.0, 67.0, 18.0)
        ret (moved, moved_error)
    }
    ret (spin, ok)
}

fn pick_actions(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < n {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (picks, ok)
}

// kind: 0 editable (CBS_DROPDOWN), 1 list (CBS_DROPDOWNLIST).
fn combo_cell(a: *mem.Arena, t: *const control.Theme, kind: usize, i: usize) -> (widget.Node, err) {
    let choices = [5]str{ "Alpha", "Bravo", "Charlie", "Delta", "Echo" }
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    // round 13: the native capture of the editable combo with the pointer on its arrow (combo-edit-hover-arrow) shows the edit EMPTY
    // (its window text is Bravo, the child edit paints nothing), so that cell is set empty too.
    var shown = "Bravo"
    if kind == 0usize && i == 2usize { shown = "" }
    let n = control.copy_text(buffer, shown)
    let (picks, picks_error) = pick_actions(a, 5usize)
    if picks_error != ok { ret (zero, picks_error) }
    let (toggle, toggle_error) = pick_actions(a, 1usize)
    if toggle_error != ok { ret (zero, toggle_error) }
    var options = control.field_options()
    options.width = 149.0
    options.read_only = kind == 1usize
    if i == 5usize { options.enabled = false }
    let key = u64(1000usize + 100usize * kind + 10usize * i)
    let (combo, combo_error) = control.combo_box(a, key, t, "Combo", buffer, n, zero, choices[0usize..5usize], 1usize, false, picks, zero, &toggle[0usize], options)
    if combo_error != ok { ret (zero, combo_error) }
    if i == 2usize {
        let (moved, moved_error) = aimed(a, combo, 150.0, 23.0, 140.0, 11.0)
        ret (moved, moved_error)
    }
    // on a whole pixel, as the control sits in the capture (a 149 wide control centred in a 200 wide cell would land on x + 0.5)
    let (whole, whole_error) = placed(a, combo, 25.0, 38.0)
    ret (whole, whole_error)
}

// Cells, row by row: 7 edits, 7 spins, 6 + 6 combos (rest, hover, hover arrow, focus, open is not here, disabled).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // a native capture shows no caret (the caret is a system overlay), so neither do the cells
    control.set_caret_hidden(true)
    let edit_names = [7]str{ "edit-rest", "edit-hover", "edit-focus", "edit-selected", "edit-readonly", "edit-disabled", "edit-password" }
    let spin_names = [7]str{ "spin-rest", "spin-hover-up", "spin-hover-down", "spin-pressed-up", "spin-pressed-down", "spin-focus", "spin-disabled" }
    let combo_names = [6]str{ "rest", "hover", "hover-arrow", "focus", "", "disabled" }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var at = 0usize
    var i = 0usize
    while i < 7usize {
        let (node, node_error) = edit_cell(a, t, i)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Focus }
        if i == 3usize {
            drive = .Focus
            select_all(t, u64(i + 1usize), 4usize)
        }
        cells[at] = looks.Cell { caption: edit_names[i], node: node, drive: drive }
        at += 1usize
        i += 1usize
    }
    i = 0usize
    while i < 7usize {
        // spin: 0 rest, 1 hover up, 2 hover down, 3 pressed up, 4 pressed down, 5 focus, 6 disabled
        // round 15: spin-focus was captured in the blink-off phase of the caret (no orange column); the edit captures show it
        control.set_native_caret_off(i == 5usize)
        // round 22: the two pressed captures were taken in the caret's on phase (a #DFDFDF line left of the text)
        control.set_caret_hidden(i != 3usize && i != 4usize)
        let (node, node_error) = spin_cell(a, t, i)
        control.set_caret_hidden(true)
        control.set_native_caret_off(false)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize || i == 2usize { drive = .Hover }
        if i == 3usize || i == 4usize { drive = .FocusPress }
        if i == 5usize { drive = .Select }
        cells[at] = looks.Cell { caption: spin_names[i], node: node, drive: drive }
        at += 1usize
        i += 1usize
    }
    var kind = 0usize
    while kind < 2usize {
        i = 0usize
        while i < 6usize {
            if i != 4usize {
                let (node, node_error) = combo_cell(a, t, kind, i)
                if node_error != ok { ret (0usize, node_error) }
                var drive: looks.Drive = .None
                if i == 1usize || i == 2usize { drive = .Hover }
                if i == 3usize && kind == 0usize { drive = .Select }
                if i == 3usize && kind == 1usize { drive = .Focus }
                cells[at] = looks.Cell { caption: combo_names[i], node: node, drive: drive }
                at += 1usize
            }
            i += 1usize
        }
        kind += 1usize
    }
    // buttons: rest, default, focus, default-focus, pressed, default-pressed, disabled (native 110 x 32: DFM 111 x 33)
    let button_default = [7]bool{ false, true, false, true, false, true, false }
    var b = 0usize
    while b < 7usize {
        var options = control.button_options()
        options.width = 110.0
        options.height = 31.0
        if button_default[b] { options.variant = .Default }
        if b == 6usize { options.enabled = false }
        let (node, node_error) = control.button(a, u64(2000usize + 10usize * b), t, "Button", &actions[0usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if b == 2usize || b == 3usize { drive = .Focus }
        if b == 4usize || b == 5usize { drive = .Press }
        let (boxed, boxed_error) = placed(a, node, 45.0, 34.0)
        if boxed_error != ok { ret (0usize, boxed_error) }
        cells[at] = looks.Cell { caption: "button", node: boxed, drive: drive }
        at += 1usize
        b += 1usize
    }
    // check boxes then radios: rest, focus, pressed, disabled of unchecked and checked (check boxes also indeterminate)
    var kind2 = 0usize
    while kind2 < 2usize {
        var state = 0usize
        while state < 3usize {
            if kind2 == 1usize && state == 2usize {
                state += 1usize
                continue
            }
            var col = 0usize
            while col < 4usize {
                var node: widget.Node = zero
                var node_error: err = ok
                let key = u64(3000usize + 500usize * kind2 + 40usize * state + 10usize * col)
                if kind2 == 0usize {
                    let (made, made_error) = control.checkbox(a, key, t, "Sample label", state == 1usize, state == 2usize, &actions[0usize], col != 3usize)
                    node = made
                    node_error = made_error
                } else {
                    let (made, made_error) = control.radio(a, key, t, "Sample label", state == 1usize, &actions[0usize], col != 3usize)
                    node = made
                    node_error = made_error
                }
                if node_error != ok { ret (0usize, node_error) }
                var drive: looks.Drive = .None
                if col == 1usize { drive = .Focus }
                if col == 2usize { drive = .Press }
                let (boxed, boxed_error) = placed(a, node, 40.0, 39.0)
                if boxed_error != ok { ret (0usize, boxed_error) }
                cells[at] = looks.Cell { caption: "choice", node: boxed, drive: drive }
                at += 1usize
                col += 1usize
            }
            state += 1usize
        }
        kind2 += 1usize
    }
    // multi-line edit with a vertical scroll bar (native 168 x 90, six lines, the bar is the light unthemed one: compared left of it)
    if at < 1000usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let n = control.copy_text(buffer, "Line one\nLine two\nLine three\nLine four\nLine five\nLine six\nLine seven\nLine eight")
        var options = control.field_options()
        options.width = 167.0
        options.height = 90.0
        options.rows = 5u32
        let (memo, memo_error) = control.text_area(a, 4000u64, t, "Notes", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, options)
        if memo_error != ok { ret (0usize, memo_error) }
        let (boxed, boxed_error) = placed(a, memo, 15.0, 5.0)
        if boxed_error != ok { ret (0usize, boxed_error) }
        cells[at] = looks.Cell { caption: "memo", node: boxed, drive: .None }
        at += 1usize
    }
    // labels: label-rest and label-disabled (native static text, white Segoe UI 9 pt; the disabled capture is white too: the app colours it)
    var l = 0usize
    while l < 2usize {
        let (word, word_error) = control.windows_label_faced(a, t, "Static text label", 12.0, 400u32, style.hex_raw(0xFFFFFFu32), false, 0.0, 7u32, 0.0, 0.0, false)
        if word_error != ok { ret (0usize, word_error) }
        let (boxed, boxed_error) = placed(a, word, 40.0, 39.0)
        if boxed_error != ok { ret (0usize, boxed_error) }
        cells[at] = looks.Cell { caption: "label", node: boxed, drive: .None }
        at += 1usize
        l += 1usize
    }
    // round 13: button-hover-pressed (the held button also shows the dotted focus rectangle)
    var held = control.button_options()
    held.width = 110.0
    held.height = 31.0
    held.focused = true
    let (held_node, held_error) = control.button(a, 2100u64, t, "Button", &actions[0usize], held)
    if held_error != ok { ret (0usize, held_error) }
    let (held_boxed, held_boxed_error) = placed(a, held_node, 45.0, 34.0)
    if held_boxed_error != ok { ret (0usize, held_boxed_error) }
    cells[at] = looks.Cell { caption: "button-hover-pressed", node: held_boxed, drive: .Press }
    at += 1usize
    // round 15: the multi-line edit without a bar in its five states (edit-multiline-rest, -focus, -selected, -readonly, -disabled), 168 x 90
    var m = 0usize
    while m < 5usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let n = control.copy_text(buffer, "Line one\nLine two\nLine three")
        var options = control.field_options()
        options.width = 167.0
        options.height = 90.0
        options.rows = 5u32
        if m == 3usize { options.read_only = true }
        if m == 4usize { options.enabled = false }
        let (memo, memo_error) = control.text_area(a, u64(4100usize + 10usize * m), t, "Notes", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, options)
        if memo_error != ok { ret (0usize, memo_error) }
        let (boxed, boxed_error) = placed(a, memo, 15.0, 5.0)
        if boxed_error != ok { ret (0usize, boxed_error) }
        var drive: looks.Drive = .None
        if m == 1usize || m == 2usize { drive = .Focus }
        if m == 2usize { select_all(t, u64(4100usize + 10usize * m), 8usize) }
        cells[at] = looks.Cell { caption: "memo-state", node: boxed, drive: drive }
        at += 1usize
        m += 1usize
    }
    ret (at, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark", cells: 60usize, columns: 7usize, cell_w: cell_w(), cell_h: cell_h(), ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
