// Round 62, worker e: helpers the navigation sheets share (examples/looks/nav_*.e). A sheet app renders its sheet under all
// ten looks; the nodes are the library's own, nothing here draws.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

// All ten looks, one runner after the other (each opens and closes its own rigs).
fn run_ten(a: *mem.Arena, s: *const looks.Sheet) -> err {
    try looks.run_all(a, s)
    try looks.run_cupertino(a, s)
    try looks.run_material(a, s)
    ret looks.run_linux(a, s)
}

fn noop_submit(ctx: *void) -> err { ret ok }

fn noop_size(ctx: *void, value: f32) -> err { ret ok }

fn submits(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < n {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (picks, ok)
}

// `node` in a box of exactly `w` by `h`.
fn framed(a: *mem.Arena, key: widget.Key, w: f32, h: f32, node: widget.Node) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    ret (widget.box(key, control.sized_style(w, h), held[0usize..1usize]), ok)
}

// A page of text for a stack or a split pane.
fn page(a: *mem.Arena, t: *const control.Theme, words: str) -> (widget.Node, err) {
    let (made, made_error) = control.text(a, 0u64, words, t, control.text_options())
    ret (made, made_error)
}

fn drive_of(i: usize, hover: usize, press: usize, focus: usize) -> looks.Drive {
    if i == hover { ret .Hover }
    if i == press { ret .Press }
    if i == focus { ret .Focus }
    ret .None
}
