// The Linux look's image combo box (a GtkDropDown whose items carry a picture) against the real GTK 4.14 / libadwaita 1.5 drop down with
// a long text (scripts/linux_cmp_l2.py): the first cell has no picture and is the captured state; the others (a picture, hovered, focused,
// disabled) have no GTK reference. docs/ui/looks/linux[-dark]/image_combo_box.png. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn actions(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < n {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (picks, ok)
}

fn one_node(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_native_caret_off(true)
    let captions = [5]str{ "long text", "with picture", "hover", "focus", "disabled" }
    let (names, names_error) = mem.alloc[str](a, 2usize)
    if names_error != ok { ret (0usize, names_error) }
    names[0usize] = "A very long entry that is cut off"
    names[1usize] = "B"
    var i = 0usize
    while i < 5usize {
        let (icons, icons_error) = mem.alloc[widget.Node](a, 2usize)
        if icons_error != ok { ret (0usize, icons_error) }
        var k = 0usize
        while k < 2usize {
            let (pic, pic_error) = control.mark_glyph(a, t.tokens.colors[0usize], .Person, 16.0)
            if pic_error != ok { ret (0usize, pic_error) }
            icons[k] = pic
            k += 1usize
        }
        var shown: []const widget.Node = icons[0usize..0usize]
        if i >= 1usize { shown = icons[0usize..2usize] }
        let (picks, picks_error) = actions(a, 2usize)
        if picks_error != ok { ret (0usize, picks_error) }
        let (toggle, toggle_error) = actions(a, 1usize)
        if toggle_error != ok { ret (0usize, toggle_error) }
        let (combo, combo_error) = control.image_select(a, u64(10usize * (i + 1usize)), t, "Image", names[0usize..2usize], shown, 0usize, false, i != 4usize, &toggle[0usize], picks)
        if combo_error != ok { ret (0usize, combo_error) }
        // Every control sits at the left of a 270 px box, which the harness centres, so none lands on a half pixel.
        var row = looks.size_style(270.0, 34.0)
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: widget.aligned(0u64, .Start, .Center, row, one_node(a, combo)), drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "image_combo_box", cells: 5usize, columns: 2usize, cell_w: 280.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
