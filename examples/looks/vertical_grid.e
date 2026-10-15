// The vertical grid / property grid (TcxVerticalGrid) under every look:
// docs/ui/looks/<look>/vertical_grid.png. Run from the repository root; see docs/ui/looks-howto.md.
//
// The rows of v3's Deck Properties form (deck_properties.vcl.form.dfm): a General category with a
// text row (the selected one, editing), read-only text, a combo box, a button edit, an Options
// category with a spin edit and a check box, and a Computed category. Left: all open. Right: General
// shut, to show the category rows' two states. Row header 164 px, 330 px in all, as in the DFM.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.widget

const COUNT: usize = 8usize
const NAME_KEY: u64 = 101u64

fn noop_key(ctx: *void, value: widget.Key) -> err { ret ok }
fn noop_text(ctx: *void, value: str) -> err { ret ok }
fn noop_int(ctx: *void, value: i64) -> err { ret ok }
fn noop_index(ctx: *void, value: usize) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

fn property_at(ctx: *void, index: usize) -> collection.Property {
    if index == 0usize { ret collection.Property { key: NAME_KEY, name: "Name", group: "General" } }
    if index == 1usize { ret collection.Property { key: 102u64, name: "Companion", group: "General" } }
    if index == 2usize { ret collection.Property { key: 103u64, name: "Format", group: "General" } }
    if index == 3usize { ret collection.Property { key: 104u64, name: "Description", group: "General" } }
    if index == 4usize { ret collection.Property { key: 105u64, name: "Copies", group: "Options" } }
    if index == 5usize { ret collection.Property { key: 106u64, name: "Show in list", group: "Options" } }
    if index == 6usize { ret collection.Property { key: 107u64, name: "Deck", group: "Computed" } }
    ret collection.Property { key: 108u64, name: "Sideboard", group: "Computed" }
}

fn count_of(ctx: *void) -> usize { ret COUNT }

// A buffer holding `text`, in the build arena.
fn filled(a: *mem.Arena, text: str) -> ([]u8, usize, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (buffer, 0usize, buffer_error) }
    var i = 0usize
    while i < text.len && i < 64usize {
        buffer[i] = text[i]
        i += 1usize
    }
    ret (buffer, i, ok)
}

fn editor_of(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    var field = control.field_options()
    field.height = 19.0
    field.width = 160.0
    if index == 0usize {
        let (buffer, len, buffer_error) = filled(a, "Mono-Red Burn")
        if buffer_error != ok { ret buffer_error }
        let (made, made_error) = control.text_field(a, 9001u64, t, "Name", buffer, len, widget.Change[str] { ctx: zero, invoke: noop_text }, widget.Submit { ctx: zero, invoke: noop_submit }, field)
        if made_error != ok { ret made_error }
        *out = made
        ret ok
    }
    if index == 2usize {
        let (buffer, len, buffer_error) = filled(a, "Modern")
        if buffer_error != ok { ret buffer_error }
        let (choices, choices_error) = mem.alloc[str](a, 2usize)
        if choices_error != ok { ret choices_error }
        choices[0usize] = "Modern"
        choices[1usize] = "Standard"
        let (picks, picks_error) = mem.alloc[widget.Submit](a, 2usize)
        if picks_error != ok { ret picks_error }
        picks[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        picks[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        let (toggle, toggle_error) = mem.alloc[widget.Submit](a, 1usize)
        if toggle_error != ok { ret toggle_error }
        toggle[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        field.read_only = true
        let (made, made_error) = control.combo_box(a, 9003u64, t, "Format", buffer, len, widget.Change[str] { ctx: zero, invoke: noop_text }, choices[0usize..2usize], 0usize, false, picks[0usize..2usize], widget.Change[usize] { ctx: zero, invoke: noop_index }, &toggle[0usize], field)
        if made_error != ok { ret made_error }
        *out = made
        ret ok
    }
    if index == 4usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
        if buffer_error != ok { ret buffer_error }
        let (made, made_error) = control.spin_box_sized(a, 9005u64, t, "Copies", buffer, 4i64, 1i64, 99i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_int }, widget.Change[str] { ctx: zero, invoke: noop_text }, 80.0)
        if made_error != ok { ret made_error }
        *out = made
        ret ok
    }
    if index == 5usize {
        let (action, action_error) = mem.alloc[widget.Submit](a, 1usize)
        if action_error != ok { ret action_error }
        action[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        let (made, made_error) = control.checkbox(a, 9006u64, t, "", true, false, &action[0usize], true)
        if made_error != ok { ret made_error }
        *out = made
        ret ok
    }
    var value = "Lurrus of the Dream-Den"
    if index == 3usize { value = "Aggressive red deck ..." }
    if index == 6usize { value = "60" }
    if index == 7usize { value = "15" }
    let (made, made_error) = control.text(a, 0u64, value, t, control.text_options())
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn grid(a: *mem.Arena, t: *const control.Theme, key: widget.Key, collapsed: []const widget.Key) -> (widget.Node, err) {
    let source = collection.PropertySource { ctx: mem.cast[*void](t), count: count_of, property: property_at, editor: editor_of }
    var options = collection.property_grid_options()
    options.selected = NAME_KEY
    let (made, made_error) = collection.property_grid_of(a, key, t, "Deck properties", source, collapsed, widget.Change[widget.Key] { ctx: zero, invoke: noop_key }, 164.0, 330.0, options)
    ret (made, made_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (shut, shut_error) = mem.alloc[widget.Key](a, 2usize)
    if shut_error != ok { ret (0usize, shut_error) }
    shut[0usize] = collection.property_group_key("General")
    shut[1usize] = collection.property_group_key("Computed")
    let (left, left_error) = grid(a, t, 1000u64, shut[0usize..0usize])
    if left_error != ok { ret (0usize, left_error) }
    let (right, right_error) = grid(a, t, 2000u64, shut[0usize..2usize])
    if right_error != ok { ret (0usize, right_error) }
    cells[0usize] = looks.Cell { caption: "All categories open, Name selected", node: left, drive: .None }
    cells[1usize] = looks.Cell { caption: "General and Computed shut", node: right, drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "vertical_grid", cells: 2usize, columns: 2usize, cell_w: 340.0, cell_h: 300.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
