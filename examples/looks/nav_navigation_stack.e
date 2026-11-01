// The navigation stack, docs/ui/looks/<look>/navigation_stack.png: the root page (no back button), a pushed page and a third level, each
// under its app bar. Derived: the library's stack through each look's app bar; no platform capture. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_e
use e.ui.navigation
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (subs, subs_error) = looks_e.submits(a, 1usize)
    if subs_error != ok { ret (0usize, subs_error) }
    let titles = [3]str{ "Settings", "General", "About" }
    let (pages, pages_error) = mem.alloc[widget.Node](a, 3usize)
    if pages_error != ok { ret (0usize, pages_error) }
    let words = [3]str{ "Root page", "Second page", "Third page" }
    var p = 0usize
    while p < 3usize {
        let (made, made_error) = looks_e.page(a, t, words[p])
        if made_error != ok { ret (0usize, made_error) }
        pages[p] = made
        p += 1usize
    }
    let names = [4]str{ "depth 1", "depth 2", "depth 3", "depth 2, back focused" }
    var i = 0usize
    while i < 4usize {
        var depth = i + 1usize
        if i == 3usize { depth = 2usize }
        let (stack, stack_error) = navigation.navigation_stack(a, u64((i + 1usize) * 100usize), t, titles[0usize..depth], pages[0usize..depth], &subs[0usize], 300.0)
        if stack_error != ok { ret (0usize, stack_error) }
        let (boxed, boxed_error) = looks_e.framed(a, u64((i + 1usize) * 100usize + 90usize), 300.0, 130.0, stack)
        if boxed_error != ok { ret (0usize, boxed_error) }
        var drive: looks.Drive = .None
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: boxed, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "navigation_stack", cells: 4usize, columns: 2usize, cell_w: 320.0, cell_h: 170.0, ctx: zero, build: build }
    ret looks_e.run_ten(a, &sheet)
}
