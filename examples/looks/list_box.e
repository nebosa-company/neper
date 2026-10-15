// The list box (TcxListBox) in every state under every look: docs/ui/looks/<look>/list_box.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.layout as ui_layout
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

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

fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, items: []const str, selected: usize, rows: u32) -> (widget.Node, err) {
    let (picks, picks_error) = pick_actions(a, items.len)
    if picks_error != ok { ret (zero, picks_error) }
    let (made, made_error) = control.list_box(a, key, t, "Format", items, selected, picks, rows, 130.0)
    ret (made, made_error)
}

// Eight cells: a short list with one row chosen, the pointer over a row, keyboard focus, a list
// past its rows (the viewport scrolls), the last row chosen, no rows, long rows, no choice.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Normal", "Hover", "Focus", "Scrolling", "Last row chosen", "Empty", "Long rows", "No choice" }
    let formats = [6]str{ "Standard", "Modern", "Pioneer", "Commander", "Vintage", "Legacy" }
    let many = [14]str{ "Alchemy", "Brawl", "Commander", "Explorer", "Freeform", "Historic", "Legacy", "Modern", "Momir", "Pauper", "Pioneer", "Standard", "Timeless", "Vintage" }
    let long = [4]str{ "Two-Headed Giant Constructed", "Commander 1v1", "Tribal Wars with a name too long to fit", "Singleton" }
    let none: []const str = zero
    var i = 0usize
    while i < 8usize {
        var items: []const str = formats[0usize..6usize]
        var selected = 1usize
        var rows = 6u32
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Focus }
        if i == 3usize {
            items = many[0usize..14usize]
            selected = 3usize
        }
        if i == 4usize { selected = 5usize }
        if i == 5usize { items = none }
        if i == 6usize {
            items = long[0usize..4usize]
            selected = 2usize
        }
        if i == 7usize { selected = 99usize }
        let (node, node_error) = one(a, t, u64(i + 1usize) * 100u64, items, selected, rows)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

// The Columns list of v3's Customization window (ref/windows/dialogs/view-show-columns): eight rows,
// the first chosen and focused. The control stands at (0, 133) of a 152 x 287 cell so that the
// harness's pointer (the cell's centre) taps the first row. `list_box.exe dialog` writes
// list_box_dialog.png, which compares pixel for pixel with ref/windows/list_box_dialog.png
// (scripts/looks_refs_d.py).
fn build_dialog(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [8]str{ "Artist", "Edition Name", "Flavor", "Legal", "No", "Power", "Row", "Toughness" }
    let (picks, picks_error) = pick_actions(a, 8usize)
    if picks_error != ok { ret (0usize, picks_error) }
    let (list, list_error) = control.list_box(a, 100u64, t, "Columns", names[0usize..8usize], 0usize, picks, 8u32, 152.0)
    if list_error != ok { ret (0usize, list_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = widget.box(0u64, looks.size_style(1.0, 133.0), zero)
    parts[1usize] = list
    let column = looks.size_style(152.0, 287.0)
    cells[0usize] = looks.Cell { caption: "", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..2usize]), drive: .Focus }
    ret (1usize, ok)
}

// The Columns list with its second row chosen: `s1` keyboard focus on it (the harness taps the cell
// centre, which falls on row 2), `s2` the list unfocused (the chosen row shows no fill). Compared with
// ref/windows/states/list-box-row-selected-{focused,unfocused}-customization.
fn build_state(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, drive: looks.Drive) -> (usize, err) {
    let names = [8]str{ "Artist", "Edition Name", "Flavor", "Legal", "No", "Power", "Row", "Toughness" }
    let (picks, picks_error) = pick_actions(a, 8usize)
    if picks_error != ok { ret (0usize, picks_error) }
    let (list, list_error) = control.list_box(a, 100u64, t, "Columns", names[0usize..8usize], 1usize, picks, 8u32, 152.0)
    if list_error != ok { ret (0usize, list_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = widget.box(0u64, looks.size_style(1.0, 117.0), zero)
    parts[1usize] = list
    var column = looks.size_style(164.0, 300.0)
    column.padding = style.EdgeLengths { left: style.Length { Px: 4.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    cells[0usize] = looks.Cell { caption: "", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..2usize]), drive: drive }
    ret (1usize, ok)
}

fn build_s1(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_state(a, t, cells, .Focus)
    ret (m, e)
}

fn build_s2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_state(a, t, cells, .None)
    ret (m, e)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize && args[1usize][0usize] == 115u8 {
        if args[1usize][1usize] == 49u8 {
            let focus = looks.Sheet { name: "list_box_focus", cells: 1usize, columns: 1usize, cell_w: 164.0, cell_h: 300.0, ctx: zero, build: build_s1 }
            ret looks.run_all(a, &focus)
        }
        let blurred = looks.Sheet { name: "list_box_blur", cells: 1usize, columns: 1usize, cell_w: 164.0, cell_h: 300.0, ctx: zero, build: build_s2 }
        ret looks.run_all(a, &blurred)
    }
    if args.len == 2usize {
        let dialog = looks.Sheet { name: "list_box_dialog", cells: 1usize, columns: 1usize, cell_w: 152.0, cell_h: 287.0, ctx: zero, build: build_dialog }
        ret looks.run_all(a, &dialog)
    }
    let sheet = looks.Sheet { name: "list_box", cells: 8usize, columns: 4usize, cell_w: 150.0, cell_h: 124.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
