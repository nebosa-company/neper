// Round 84, lane y: the Cupertino swipe actions drawn as the collection's real tiles (collection.swipe_actions_of): the row slides over
// full-height tiles flush to the trailing edge, Archive in the accent, Delete destructive (red). Writes only docs/ui/looks/cupertino*/swipe_actions*.png;
// the shared h_swipe_actions.e sheet keeps drawing the other eight looks.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.layout as ui_layout
use e.ui.looks_h as h
use e.ui.style
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "rest", "revealed", "hover", "focus" }
    var i = 0usize
    while i < 4usize {
        let (word, word_error) = h.word(a, t, "Message from Ada about the new deck")
        if word_error != ok { ret (0usize, word_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (0usize, held_error) }
        held[0usize] = word
        var row = style.defaults()
        row.width = style.Length { Px: 360.0 }
        row.height = style.Length { Px: 64.0 }
        row.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 0.0 } }
        let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, row, held[0usize..1usize])
        let tiles = [2]collection.SwipeAction{
            collection.SwipeAction { label: "Archive", glyph: .ArrowDown, tone: .Accent, action: widget.Submit { ctx: zero, invoke: h.noop_submit } },
            collection.SwipeAction { label: "Delete", glyph: .Cross, tone: .Destructive, action: widget.Submit { ctx: zero, invoke: h.noop_submit } } }
        var options = collection.swipe_options()
        options.width = 360.0
        options.height = 64.0
        let (node, node_error) = collection.swipe_actions_of(a, u64((i + 1usize) * 100usize), t, content, tiles[0usize..2usize], i == 1usize, widget.Change[bool] { ctx: zero, invoke: h.noop_bool }, options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "swipe_actions", cells: 4usize, columns: 2usize, cell_w: 380.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
