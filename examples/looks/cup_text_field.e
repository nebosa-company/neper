// The Cupertino text field and search field: docs/ui/looks/cupertino/text_edit.png and search_field.png (and
// cupertino-dark). States: empty (placeholder), filled, hover, keyboard focus (halo, clear button), selected text,
// disabled, invalid, read only, three rows, prefix and suffix.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

fn fill(a: *mem.Arena, words: str) -> ([]u8, usize, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
    if buffer_error != ok { ret (zero, 0usize, buffer_error) }
    var i = 0usize
    while i < words.len {
        buffer[i] = words[i]
        i += 1usize
    }
    ret (buffer, words.len, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [12]str{ "empty", "filled", "hover", "focus (clear button)", "selected", "disabled", "invalid", "read only", "three rows", "prefix, suffix", "password", "tall 44" }
    let values = [12]str{ "", "Alex Appleseed", "Alex Appleseed", "Alex Appleseed", "Alex Appleseed", "Alex Appleseed", "alex@", "Alex Appleseed", "Notes go here\nand wrap onto\nthree rows", "42", "hunter2", "Alex Appleseed" }
    var i = 0usize
    while i < 12usize {
        let (buffer, len, buffer_error) = fill(a, values[i])
        if buffer_error != ok { ret (0usize, buffer_error) }
        var options = control.field_options()
        options.width = 190.0
        options.placeholder = "Full name"
        if i == 5usize { options.enabled = false }
        if i == 6usize { options.invalid = true }
        if i == 7usize { options.read_only = true }
        if i == 8usize { options.rows = 3u32 }
        if i == 9usize {
            options.prefix = "$"
            options.suffix = "USD"
        }
        if i == 11usize { options.height = 44.0 }
        let change = widget.Change[str] { ctx: zero, invoke: noop_change }
        let submit = widget.Submit { ctx: zero, invoke: noop_submit }
        var node: widget.Node = zero
        if i == 10usize {
            let (made, made_error) = control.password_field(a, u64((i + 1usize) * 10usize), t, "Password", buffer, len, change, submit, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else {
            let (made, made_error) = control.text_field(a, u64((i + 1usize) * 10usize), t, "Name", buffer, len, change, submit, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Focus }
        if i == 4usize { drive = .Select }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (12usize, ok)
}

fn build_search(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "empty", "filled (clear)", "hover", "focus", "disabled", "custom prompt" }
    let values = [6]str{ "", "mana curve", "", "mana curve", "", "" }
    let (cleared, cleared_error) = mem.alloc[widget.Submit](a, 1usize)
    if cleared_error != ok { ret (0usize, cleared_error) }
    cleared[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < 6usize {
        let (buffer, len, buffer_error) = fill(a, values[i])
        if buffer_error != ok { ret (0usize, buffer_error) }
        var options = control.field_options()
        options.width = 220.0
        if i == 4usize { options.enabled = false }
        if i == 5usize { options.placeholder = "Search cards" }
        let change = widget.Change[str] { ctx: zero, invoke: noop_change }
        let submit = widget.Submit { ctx: zero, invoke: noop_submit }
        let (node, node_error) = control.search_field(a, u64((i + 1usize) * 10usize), t, buffer, len, change, submit, &cleared[0usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "text_edit", cells: 12usize, columns: 4usize, cell_w: 204.0, cell_h: 80.0, ctx: zero, build: build }
    try looks.run_cupertino(a, &sheet)
    let search = looks.Sheet { name: "search_field", cells: 6usize, columns: 3usize, cell_w: 236.0, cell_h: 50.0, ctx: zero, build: build_search }
    ret looks.run_cupertino(a, &search)
}
