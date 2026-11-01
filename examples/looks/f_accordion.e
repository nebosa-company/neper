// control.accordion under all ten looks: docs/ui/looks/<look>/accordion.png. Three sections with the first, the second or
// none open, a disabled section, a section header hovered, pressed and keyboard-focused.
// Derived from the shared tokens; no platform reference is captured. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_f
use e.ui.widget

fn no_press(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [7]str{ "First open", "Second open", "All shut", "Disabled section", "Header hovered", "Header pressed", "Keyboard focus" }
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, 3usize)
    if toggles_error != ok { ret (0usize, toggles_error) }
    var p = 0usize
    while p < 3usize {
        toggles[p] = widget.Submit { ctx: zero, invoke: no_press }
        p += 1usize
    }
    let labels = [3]str{ "General", "Appearance", "Advanced" }
    let enabled = [3]bool{ true, true, false }
    var i = 0usize
    while i < 7usize {
        let (contents, contents_error) = mem.alloc[widget.Node](a, 3usize)
        if contents_error != ok { ret (0usize, contents_error) }
        var c = 0usize
        while c < 3usize {
            let (words, words_error) = control.text(a, 0u64, "Section content", t, control.text_options())
            if words_error != ok { ret (0usize, words_error) }
            contents[c] = words
            c += 1usize
        }
        var open = 0usize
        if i == 1usize { open = 1usize }
        if i == 2usize { open = 3usize }
        var options = control.accordion_options()
        options.width = 280.0
        if i == 3usize { options.enabled = enabled[0usize..3usize] }
        let (node, node_error) = control.accordion_of(a, u64((i + 1usize) * 1000usize), t, "Settings", labels[0usize..3usize], contents[0usize..3usize], open_flags(a, open), toggles[0usize..3usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 4usize || i == 5usize {
            drive = .Hover
            looks.aim(i, 0.0, -50.0)
        }
        if i == 5usize { drive = .Press }
        if i == 6usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (7usize, ok)
}

fn open_flags(a: *mem.Arena, open: usize) -> []const bool {
    let (flags, flags_error) = mem.alloc[bool](a, 3usize)
    if flags_error != ok { ret zero }
    var i = 0usize
    while i < 3usize {
        flags[i] = i == open
        i += 1usize
    }
    ret flags[0usize..3usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "accordion", cells: 7usize, columns: 4usize, cell_w: 300.0, cell_h: 190.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
