// The autocomplete in every look: docs/ui/looks/<look>/autocomplete.png (the field closed: empty, typed, hover, keyboard focus,
// disabled) and autocomplete_open.png (open, with three suggestions and the first one active). Run from the repository root; see
// docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_a
use e.ui.style
use e.ui.widget
use e.ui.looks_y85

fn noop_typed(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_pick(ctx: *void, index: usize) -> err { ret ok }

fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, value: str, open: bool, enabled: bool) -> (widget.Node, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    let len = control.copy_text(buffer, value)
    let (words, words_error) = mem.alloc[str](a, 3usize)
    if words_error != ok { ret (zero, words_error) }
    words[0usize] = "Berlin"
    words[1usize] = "Bergen"
    words[2usize] = "Bern"
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 3usize)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < 3usize {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    let (dismiss, dismiss_error) = mem.alloc[widget.Submit](a, 1usize)
    if dismiss_error != ok { ret (zero, dismiss_error) }
    dismiss[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var options = control.field_options()
    options.width = 200.0
    options.placeholder = "City"
    options.enabled = enabled
    let typed = widget.Change[str] { ctx: zero, invoke: noop_typed }
    let activate = widget.Change[usize] { ctx: zero, invoke: noop_pick }
    let (node, node_error) = control.autocomplete(a, key, t, "City", buffer, len, typed, words[0usize..3usize], 0usize, open, picks[0usize..3usize], activate, &dismiss[0usize], options)
    ret (node, node_error)
}

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: accent text, selected tint and keyboard ring hold the contrast rule (0045E6 light, 409CFF dark); other looks unchanged.
    let (tokens, tokens_error) = looks_y85.tinted_ring(a, base.tokens, 0x0045E6u32, 0x409CFFu32)
    if tokens_error != ok { ret (0usize, tokens_error) }
    var local = *base
    local.tokens = tokens
    let t = &local
    let names = [5]str{ "empty", "typed", "hover", "focus", "disabled" }
    let values = [5]str{ "", "Ber", "Ber", "Ber", "Ber" }
    var i = 0usize
    while i < 5usize {
        let (node, node_error) = one(a, t, u64((i + 1usize) * 100usize), values[i], false, i != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn one_node(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

fn build_open(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: accent text, selected tint and keyboard ring hold the contrast rule (0045E6 light, 409CFF dark); other looks unchanged.
    let (tokens, tokens_error) = looks_y85.tinted_ring(a, base.tokens, 0x0045E6u32, 0x409CFFu32)
    if tokens_error != ok { ret (0usize, tokens_error) }
    var local = *base
    local.tokens = tokens
    let t = &local
    let (node, node_error) = one(a, t, 100u64, "Ber", true, true)
    if node_error != ok { ret (0usize, node_error) }
    var room = looks.size_style(260.0, 230.0)
    room.padding = style.EdgeLengths { left: style.Length { Px: 20.0 }, top: style.Length { Px: 20.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, room, one_node(a, node))
    cells[0usize] = looks.Cell { caption: "open", node: column, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let closed = looks.Sheet { name: "autocomplete", cells: 5usize, columns: 3usize, cell_w: 236.0, cell_h: 60.0, ctx: zero, build: build }
    try looks_a.run_every(a, &closed)
    let open = looks.Sheet { name: "autocomplete_open", cells: 1usize, columns: 1usize, cell_w: 260.0, cell_h: 230.0, ctx: zero, build: build_open }
    ret looks_a.run_every(a, &open)
}
