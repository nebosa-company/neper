// The native Windows 11 SysLink (a label with hot links) in the Windows light and dark looks, beside docs/ui/looks/ref/windows-native/{light,dark}/syslink-*
// (260 x 70: "Text with a link and another." at x 16, the 15 high control from row 14). One cell per capture: rest, hover (the capture is
// identical to rest), focus (the first link carries the dotted rectangle) and disabled. Neper has no link label: it shows the same words as plain text.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "syslink-rest", "syslink-hover", "syslink-focus", "syslink-disabled" }
    var i = 0usize
    while i < 4usize {
        var node: widget.Node = zero
        if t.tokens.profile == .Windows {
            let (link, link_error) = control.windows_syslink(a, t, "Text with ", "a link", " and ", "another", ".", i == 2usize, i != 3usize)
            if link_error != ok { ret (0usize, link_error) }
            node = link
        } else {
            let (plain, plain_error) = control.text(a, u64(i + 1usize), "Text with a link and another.", t, control.text_options())
            if plain_error != ok { ret (0usize, plain_error) }
            node = plain
        }
        let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
        if inner_error != ok { ret (0usize, inner_error) }
        inner[0usize] = widget.positioned(0u64, 16.0, 14.0, style.defaults(), control.mem_one_node(a, node))
        cells[i] = looks.Cell { caption: names[i], node: widget.stack(0u64, control.sized_style(260.0, 70.0), inner[0usize..1usize]), drive: .None }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "syslink", cells: 4usize, columns: 2usize, cell_w: 260.0, cell_h: 70.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
