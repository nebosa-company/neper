// The Android look's chips, docs/ui/looks/material/chips.png: assist (outlined, with a leading icon, elevated), filter (off and
// on), input (off and selected) and suggestion (outlined and elevated) in enabled, hovered, focused and pressed, then every
// kind disabled. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn drive_of(column: usize) -> looks.Drive {
    if column == 1usize { ret .Hover }
    if column == 2usize { ret .Focus }
    if column == 3usize { ret .Press }
    ret .None
}

// Rows 0 to 4 are the first sheet's (assist, filter, filter selected, input, suggestion); rows 5 to 8 the further forms
// (assist with icon, assist elevated, suggestion elevated, input selected); row 9 on the disabled ones, four to a row.
type Spec = struct { kind: control.ChipKind, selected: bool, elevated: bool, icon: bool, enabled: bool, word: str }

fn spec_of(i: usize) -> Spec {
    var s = Spec { kind: .Assist, selected: false, elevated: false, icon: false, enabled: true, word: "Assist" }
    if i < 36usize {
        let row = i / 4usize
        if row == 1usize || row == 2usize {
            s.kind = .Filter
            s.word = "Filter"
            s.selected = row == 2usize
        }
        if row == 3usize || row == 8usize {
            s.kind = .Input
            s.word = "Input"
            s.selected = row == 8usize
        }
        if row == 4usize || row == 7usize {
            s.kind = .Suggestion
            s.word = "Suggestion"
            s.elevated = row == 7usize
        }
        if row == 5usize { s.icon = true }
        if row == 6usize { s.elevated = true }
        ret s
    }
    // The disabled ones: assist, assist elevated, assist with icon, filter, filter selected, input, input selected, suggestion,
    // suggestion elevated.
    s.enabled = false
    let k = i - 36usize
    if k == 1usize { s.elevated = true }
    if k == 2usize { s.icon = true }
    if k == 3usize || k == 4usize {
        s.kind = .Filter
        s.word = "Filter"
        s.selected = k == 4usize
    }
    if k == 5usize || k == 6usize {
        s.kind = .Input
        s.word = "Input"
        s.selected = k == 6usize
    }
    if k == 7usize || k == 8usize {
        s.kind = .Suggestion
        s.word = "Suggestion"
        s.elevated = k == 8usize
    }
    ret s
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let states = [4]str{ "Enabled", "Hovered", "Focused", "Pressed" }
    var i = 0usize
    while i < 45usize {
        let s = spec_of(i)
        let column = i % 4usize
        let (node, node_error) = control.chip_styled(a, u64((i + 1usize) * 4usize), t, s.word, s.kind, s.selected, &actions[0usize], &actions[1usize], s.enabled, s.elevated, .Add, s.icon)
        if node_error != ok { ret (0usize, node_error) }
        var caption = states[column]
        var drive = drive_of(column)
        if i >= 36usize {
            caption = "Disabled"
            drive = .None
        }
        cells[i] = looks.Cell { caption: caption, node: node, drive: drive }
        i += 1usize
    }
    ret (45usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "chips", cells: 45usize, columns: 4usize, cell_w: 130.0, cell_h: 48.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
