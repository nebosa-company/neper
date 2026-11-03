// Round 62 c: the card in all ten looks: elevated, filled and outlined; selected; disabled; loading (skeleton media and
// lines); a pressable card at rest, hovered, pressed and focused. Derived from the shared tokens, no platform capture.
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_y85
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: the selected outline, check disc and keyboard ring take the 4.5:1 blue (0A60FF light, 409CFF dark); other looks unchanged.
    let (tokens, tokens_error) = looks_y85.tinted_ring(a, base.tokens, 0x0A60FFu32, 0x409CFFu32)
    if tokens_error != ok { ret (0usize, tokens_error) }
    var local = *base
    local.tokens = tokens
    let t = &local
    let go = widget.Submit { ctx: zero, invoke: noop_submit }
    let (hold, hold_error) = mem.alloc[widget.Submit](a, 1usize)
    if hold_error != ok { ret (0usize, hold_error) }
    hold[0usize] = go
    let captions = [11]str{ "Elevated", "Filled", "Outlined", "Selected", "Disabled", "Loading", "Pressable", "Hovered", "Pressed", "Focused", "Dragged" }
    var i = 0usize
    while i < 11usize {
        let key = u64((i + 1usize) * 32usize)
        var options = control.card_options()
        options.width = 220.0
        options.title = "Modern Horizons 3"
        options.description = "Draft, 2024"
        if i == 1usize { options.variant = .Filled }
        if i == 2usize { options.variant = .Outlined }
        if i == 3usize {
            options.selected = true
            options.select = &hold[0usize]
        }
        if i == 4usize { options.enabled = false }
        if i == 5usize {
            options.loading = true
            options.phase = 0.5
        }
        if i >= 6usize && i <= 9usize { options.action = &hold[0usize] }
        if i == 10usize { options.dragged = true }
        var title = control.text_options()
        title.role = .TitleMedium
        let (head, head_error) = control.text(a, key + 1u64, "Modern Horizons 3", t, title)
        if head_error != ok { ret (0usize, head_error) }
        var body = control.text_options()
        body.role = .BodyMedium
        let (words, words_error) = control.text(a, key + 2u64, "Draft, 2024", t, body)
        if words_error != ok { ret (0usize, words_error) }
        let (kids, kids_error) = mem.alloc[widget.Node](a, 2usize)
        if kids_error != ok { ret (0usize, kids_error) }
        kids[0usize] = head
        kids[1usize] = words
        let (node, node_error) = control.card_of(a, key, t, options, kids[0usize..2usize])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 7usize { drive = .Hover }
        if i == 8usize { drive = .Press }
        if i == 9usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (11usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "card", cells: 11usize, columns: 4usize, cell_w: 250.0, cell_h: 190.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
