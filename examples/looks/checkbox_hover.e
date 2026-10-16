// The check box with the pointer over it, as the live v3 hover grabs show it (docs/ui/looks/ref/windows/states/hover-checkbox-*,
// taken with a fake pointer): docs/ui/looks/<look>/checkbox_hover.png. Seven cells, every hover grab of the Options pages: the
// face of an unchecked box lightens by up to 9 levels, a checked box's changes by up to 25; hovering the caption shows the same
// box look. Reference composite: ref/windows/checkbox_hover.png (scripts/looks_refs_b.py).

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget
use e.ui.winbutton

fn plain(a: *mem.Arena, label: str) -> str {
    let (shown, mark, shown_error) = winbutton.mnemonic(a, label)
    if shown_error != ok { ret label }
    ret shown
}

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let labels = [7]str{ "Hide splash screen on start", "Hide splash screen on start", "Show card preview tooltip", "Show tooltips", "Show Filter &Row", "Show Foil &Symbol", "&Use Morph effect" }
    let captions = [7]str{ "Hide splash, box", "Hide splash, caption", "Card preview, caption", "Show tooltips", "Show Filter Row", "Show Foil Symbol", "Use Morph" }
    let checked = [7]bool{ false, false, true, true, false, true, true }
    let window_xs = [7]f32{ 215.0, 215.0, 215.0, 215.0, 224.0, 224.0, 215.0 }
    let window_ys = [7]f32{ 74.0, 74.0, 128.0, 155.0, 132.0, 102.0, 71.0 }
    let (held, held_error) = mem.alloc[widget.Node](a, 14usize)
    if held_error != ok { ret (0usize, held_error) }
    let first = looks.size_style(160.0, 29.0)
    var i = 0usize
    while i < 7usize {
        var box: widget.Node = zero
        if t.tokens.profile == .Windows {
            let (made, made_error) = control.windows_checkbox_phase(a, u64(i + 1usize), t, labels[i], checked[i], false, action, true, 21.0, false, 0u32, window_xs[i], window_ys[i])
            if made_error != ok { ret (0usize, made_error) }
            box = made
        } else {
            let (made, made_error) = control.checkbox(a, u64(i + 1usize), t, plain(a, labels[i]), checked[i], false, action, true)
            if made_error != ok { ret (0usize, made_error) }
            box = made
        }
        held[i] = box
        held[7usize + i] = widget.positioned(0u64, 4.0, 4.0, style.defaults(), held[i..i + 1usize])
        cells[i] = looks.Cell { caption: captions[i], node: widget.stack(0u64, first, held[7usize + i..8usize + i]), drive: .Hover }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "checkbox_hover", cells: 7usize, columns: 3usize, cell_w: 160.0, cell_h: 29.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
