// The Windows dark combo box with its list open beside the native Windows 11 dark captures combo-edit-open, combo-edit-open-hover-row,
// combo-list-open and combo-list-open-hover-row (round 12). One variant per process, named by the first argument (0 to 3); the sheet
// is native_dark_open<n>. A list opens one at a time, so each variant is its own sheet.
// Run with NEPER_LOOKS_OUT=<scratch>; scripts/looks_strict_dark.py --open compares them.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

var variant: usize = 0

fn select_all(t: *const control.Theme, key: widget.Key, len: usize) {
    if mem.address_of(t.runtime) == 0usize { ret }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret }
    let unused = widget.edit_select(t.runtime, id, 0usize, len)
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

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_caret_hidden(true)
    let choices = [8]str{ "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel" }
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (0usize, buffer_error) }
    var hovered_row = variant >= 2usize
    var shown = "Bravo"
    var active = 1usize
    if variant % 2usize == 1usize { active = 4usize }
    if variant == 3usize { shown = "Echo" }
    let n = control.copy_text(buffer, shown)
    let (picks, picks_error) = pick_actions(a, 8usize)
    if picks_error != ok { ret (0usize, picks_error) }
    let (toggle, toggle_error) = pick_actions(a, 1usize)
    if toggle_error != ok { ret (0usize, toggle_error) }
    var options = control.field_options()
    options.width = 149.0
    options.read_only = variant / 2usize == 1usize
    let (combo, combo_error) = control.combo_box(a, 1000u64, t, "Combo", buffer, n, zero, choices[0usize..8usize], active, true, picks, zero, &toggle[0usize], options)
    if combo_error != ok { ret (0usize, combo_error) }
    // the head sits at (20, 8) of a 190 x 200 cell, so the cell's middle (the pointer of a driven cell) is over the fifth row
    var drive: looks.Drive = .None
    if variant % 2usize == 1usize { drive = .Hover }
    // round 13: the editable combo's head text is selected in both captures (the edit keeps the focus while the list is open), also with
    // the row under the pointer: the lit row is the `active` one, so the variant needs no pointer on the list
    if variant < 2usize {
        // the editable combo's text is selected in the capture: focus it from the head's text, then select all
        drive = .Focus
        looks.aim(0usize, 0.0 - 50.0, 0.0 - 80.0)
        select_all(t, 1000u64, 5usize)
    }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (0usize, inner_error) }
    inner[0usize] = widget.positioned(0u64, 20.0, 8.0, style.defaults(), control.mem_one_node(a, combo))
    let node = widget.stack(0u64, sized(190.0, 200.0), inner[0usize..1usize])
    cells[0usize] = looks.Cell { caption: "open", node: node, drive: drive }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize { variant = usize(args[1usize][0usize]) - 48usize }
    var name = "native_dark_open0"
    if variant == 1usize { name = "native_dark_open1" }
    if variant == 2usize { name = "native_dark_open2" }
    if variant == 3usize { name = "native_dark_open3" }
    let sheet = looks.Sheet { name: name, cells: 1usize, columns: 1usize, cell_w: 190.0, cell_h: 200.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
