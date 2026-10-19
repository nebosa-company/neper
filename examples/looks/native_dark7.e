// The Windows dark look beside the native Windows 11 dark captures, seventh sheet (round 35): the bare header (x-header-itemsview-rest,
// -hot, -pressed, -sort-up; 250 x 40), a Win32 header themed DarkMode_ItemsView: a #191919 band 226 x 24 at (10, 8) on #202020, #636363
// column lines, black captions (unreadable, as natively), the pressed cell #838383 and, sorted, a 9 x 5 chevron over the Size column.
// scripts/looks_dark_whole.py diffs each cell. Only windows-dark matters. Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn at(a: *mem.Arena, x: f32, y: f32, node: widget.Node) -> widget.Node {
    ret widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
}

fn solid(a: *mem.Arena, x: f32, y: f32, w: f32, h: f32, value: u32) -> widget.Node {
    var s = control.sized_style(w, h)
    s.background = paint.Brush { Solid: style.hex_raw(value) }
    ret at(a, x, y, widget.box(0u64, s, zero))
}

fn word(a: *mem.Arena, t: *const control.Theme, value: str) -> (widget.Node, err) {
    var options = control.text_options()
    options.face = 7u32
    options.size = 12.0
    options.wrap = .None
    let (dark_t, dark_error) = control.windows_edit_theme(a, t, 13.0)
    if dark_error != ok { ret (zero, dark_error) }
    let (made, made_error) = control.colored_text(a, 0u64, value, &dark_t, options, style.hex_raw(0x000000u32))
    ret (made, made_error)
}

fn header(a: *mem.Arena, t: *const control.Theme, pressed: bool, sorted: bool) -> (widget.Node, err) {
    let (name, name_error) = word(a, t, "Name")
    if name_error != ok { ret (zero, name_error) }
    let (size, size_error) = word(a, t, "Size")
    if size_error != ok { ret (zero, size_error) }
    let (kind, kind_error) = word(a, t, "Kind")
    if kind_error != ok { ret (zero, kind_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 13usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = solid(a, 0.0, 0.0, 250.0, 40.0, 0x202020u32)
    parts[1usize] = solid(a, 10.0, 8.0, 226.0, 24.0, 0x191919u32)
    var n = 2usize
    if pressed {
        parts[n] = solid(a, 100.0, 8.0, 60.0, 24.0, 0x838383u32)
        n += 1usize
    }
    parts[n] = solid(a, 99.0, 8.0, 1.0, 24.0, 0x636363u32)
    parts[n + 1usize] = solid(a, 219.0, 8.0, 1.0, 24.0, 0x636363u32)
    n += 2usize
    if !pressed {
        parts[n] = solid(a, 159.0, 8.0, 1.0, 24.0, 0x636363u32)
        n += 1usize
    }
    // a pressed item's caption moves one pixel right and down
    var shift: f32 = 0.0
    if pressed { shift = 1.0 }
    parts[n] = at(a, 16.0, 11.0, name)
    parts[n + 1usize] = at(a, 106.0 + shift, 11.0 + shift, size)
    parts[n + 2usize] = at(a, 166.0, 11.0, kind)
    n += 3usize
    if sorted {
        // the sort chevron, a 1 px line pair over the Size column: apex (130.5, 8.9), feet (126.5, 12.2) and (134.5, 12.2)
        let (chevron, chevron_error) = control.cup_mark(a, 4u32, style.hex_raw(0xBCBCBCu32), style.hex_raw(0xBCBCBCu32), 1.0, 0.0, 12.5, 11.8)
        if chevron_error != ok { ret (zero, chevron_error) }
        parts[n] = at(a, 124.25, 4.65, chevron)
        n += 1usize
    }
    ret (widget.stack(0u64, control.sized_style(250.0, 40.0), parts[0usize..n]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [3]str{ "x-header-itemsview-rest", "x-header-itemsview-pressed", "x-header-itemsview-sort-up" }
    var i = 0usize
    while i < 3usize {
        let (node, node_error) = header(a, t, i == 1usize, i == 2usize)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark7", cells: 3usize, columns: 1usize, cell_w: 254.0, cell_h: 42.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
