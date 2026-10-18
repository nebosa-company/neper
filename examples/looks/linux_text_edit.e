// The Linux look's text entry against the real GTK 4.14 / libadwaita 1.5 ones (docs/ui/looks/ref/linux, scripts/linux_cmp_l2.py):
// rest, hover, focus ring, selected text, disabled, placeholder, error, error focused, warning, success, password, search.
// docs/ui/looks/linux[-dark]/text_edit.png. Run from the repository root; see docs/ui/looks-howto.md.

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

fn select_all(t: *const control.Theme, key: widget.Key, len: usize) {
    if mem.address_of(t.runtime) == 0usize { ret }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret }
    let unused = widget.edit_select(t.runtime, id, 0usize, len)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_native_caret_off(true)
    let names = [12]str{ "rest", "hover", "focus", "selected", "disabled", "placeholder", "error", "error focus", "warning", "success", "password", "search" }
    let values = [12]str{ "Some text", "Some text", "Some text", "Some text", "Some text", "", "Error", "Error", "Warning", "Success", "", "query" }
    let (cleared, cleared_error) = mem.alloc[widget.Submit](a, 1usize)
    if cleared_error != ok { ret (0usize, cleared_error) }
    cleared[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < 12usize {
        let (buffer, len, buffer_error) = fill(a, values[i])
        if buffer_error != ok { ret (0usize, buffer_error) }
        var options = control.field_options()
        options.width = 200.0
        if i == 4usize { options.enabled = false }
        if i == 5usize { options.placeholder = "Placeholder" }
        if i == 6usize || i == 7usize { options.invalid = true }
        if i == 8usize { options.chrome_kind = 1u32 }
        if i == 9usize { options.chrome_kind = 2u32 }
        if i == 11usize { options.width = 212.0 }
        let change = widget.Change[str] { ctx: zero, invoke: noop_change }
        let submit = widget.Submit { ctx: zero, invoke: noop_submit }
        let key = u64((i + 1usize) * 10usize)
        var node: widget.Node = zero
        if i == 10usize {
            let (made, made_error) = control.password_field_with(a, key, t, "Password", buffer, len, change, submit, options, false, &cleared[0usize])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else if i == 11usize {
            let (made, made_error) = control.search_field(a, key, t, buffer, len, change, submit, &cleared[0usize], options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else {
            let (made, made_error) = control.text_field(a, key, t, "Entry", buffer, len, change, submit, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize || i == 7usize { drive = .Focus }
        if i == 3usize {
            drive = .Select
            select_all(t, key, len)
        }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "text_edit", cells: 12usize, columns: 3usize, cell_w: 222.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
