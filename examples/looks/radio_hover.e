// The radio button with the pointer over it, as the live v3 hover grabs show it (docs/ui/looks/ref/windows/states/hover-radio-*,
// taken with a fake pointer): docs/ui/looks/<look>/radio_hover.png. Ten cells, every hover grab: the Filter window's Blocks and
// Formats, the Missing Set Cards radios, the Options Grids groups' radios and the Search for Card group's. A radio shows no
// hover look (every grab is its rest look to within a level). Reference composite: ref/windows/radio_hover.png
// (scripts/looks_refs_b.py).

use e.mem
use e.gfx.paint
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
    let labels = [10]str{ "Blocks", "Formats", "&Available Only", "&Missing Only", "Move to next row", "Search from start (typing \"War\" would not find \"Fog of War\")", "Search within (typing \"War\" would find \"Fog of War\")", "Search within (typing \"War\" would find \"Fog of War\")", "Cards", "Collection" }
    let captions = [10]str{ "Filter, Blocks", "Filter, Formats", "Missing, Available Only", "Missing, caption", "Options, next row", "Options, from start", "Options, within caption", "Options, within", "Search, Cards", "Search, Collection" }
    let selected = [10]bool{ true, false, false, true, false, true, false, false, true, false }
    let contexts = [10]u32{ 4u32, 4u32, 2u32, 2u32, 6u32, 6u32, 6u32, 6u32, 3u32, 3u32 }
    let window_xs = [10]f32{ 21.0, 109.0, 24.0, 24.0, 232.0, 232.0, 232.0, 232.0, 28.0, 28.0 }
    let window_ys = [10]f32{ 65.0, 65.0, 396.0, 372.0, 365.0, 212.0, 254.0, 254.0, 120.0, 162.0 }
    let highs = [10]f32{ 17.0, 17.0, 17.0, 17.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0 }
    let xs = [10]f32{ 140.0, 140.0, 140.0, 140.0, 140.0, 4.0, 4.0, 4.0, 140.0, 140.0 }
    let (held, held_error) = mem.alloc[widget.Node](a, 20usize)
    if held_error != ok { ret (0usize, held_error) }
    var i = 0usize
    while i < 10usize {
        var cell_style = looks.size_style(340.0, 50.0)
        if t.tokens.profile == .Windows && i < 2usize { cell_style.background = paint.Brush { Solid: style.hex(16382457u32) } }
        var made: widget.Node = zero
        if t.tokens.profile == .Windows {
            let (radio, radio_error) = control.windows_radio_phase(a, u64(i + 1usize), t, labels[i], selected[i], action, true, highs[i], contexts[i], window_xs[i], window_ys[i])
            if radio_error != ok { ret (0usize, radio_error) }
            made = radio
        } else {
            let (radio, radio_error) = control.radio(a, u64(i + 1usize), t, plain(a, labels[i]), selected[i], action, true)
            if radio_error != ok { ret (0usize, radio_error) }
            made = radio
        }
        held[i] = made
        held[10usize + i] = widget.positioned(0u64, xs[i], 4.0, style.defaults(), held[i..i + 1usize])
        cells[i] = looks.Cell { caption: captions[i], node: widget.stack(0u64, cell_style, held[10usize + i..11usize + i]), drive: .Hover }
        i += 1usize
    }
    ret (10usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "radio_hover", cells: 10usize, columns: 2usize, cell_w: 340.0, cell_h: 50.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
