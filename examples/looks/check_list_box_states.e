// The check list box with its current row moved, as the live v3 captures show it: docs/ui/looks/<look>/check_list_box_states.png.
// The top four rows of the Options Rules list (current row 1, 2, 3 and 3 again: the unfocused grab and the focused
// grab of the 2nd row are identical, so is the pressed check box grab to the 3rd row) and of the Prices list (3rd row).
// Reference composite: ref/windows/check_list_box_states.png (scripts/looks_refs_b.py).

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn list(a: *mem.Arena, t: *const control.Theme, key: u64, labels: []const str, current: usize, art: bool) -> (widget.Node, err) {
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, labels.len)
    if toggles_error != ok { ret (zero, toggles_error) }
    let (picked, picked_error) = mem.alloc[bool](a, labels.len)
    if picked_error != ok { ret (zero, picked_error) }
    var i = 0usize
    while i < labels.len {
        toggles[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        picked[i] = true
        i += 1usize
    }
    var made: widget.Node = zero
    if t.tokens.profile == .Windows && art {
        let (drawn, drawn_error) = control.windows_check_list_art(a, key, t, "list", labels, picked, toggles, 464.0, 80.0, current, 71.0)
        if drawn_error != ok { ret (zero, drawn_error) }
        made = drawn
    } else if t.tokens.profile == .Windows {
        let (drawn, drawn_error) = control.windows_check_list_at(a, key, t, "list", labels, picked, toggles, 495.0, 80.0, current, 94.0)
        if drawn_error != ok { ret (zero, drawn_error) }
        made = drawn
    } else {
        let (drawn, drawn_error) = control.multi_select_list(a, key, t, "list", labels, picked, toggles, 4u32, 495.0)
        if drawn_error != ok { ret (zero, drawn_error) }
        made = drawn
    }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = made
    let (layer, layer_error) = mem.alloc[widget.Node](a, 1usize)
    if layer_error != ok { ret (zero, layer_error) }
    layer[0usize] = widget.positioned(0u64, 2.0, 2.0, style.defaults(), held[0usize..1usize])
    ret (widget.stack(0u64, looks.size_style(500.0, 90.0), layer[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let rules = [4]str{ "Card Details (Cost, Type, Rarity, Set, etc.)", "Rules Printed on Card", "Flavor Text", "User Card Notes" }
    let prices = [4]str{ "TCG Player (Aggregated)", "TCG Player", "Magic Traders", "Find Magic Cards" }
    let (n0, e0) = list(a, t, 100u64, rules[0usize..4usize], 0usize, false)
    if e0 != ok { ret (0usize, e0) }
    let (n1, e1) = list(a, t, 200u64, rules[0usize..4usize], 1usize, false)
    if e1 != ok { ret (0usize, e1) }
    let (n2, e2) = list(a, t, 300u64, rules[0usize..4usize], 1usize, false)
    if e2 != ok { ret (0usize, e2) }
    let (n3, e3) = list(a, t, 400u64, rules[0usize..4usize], 2usize, false)
    if e3 != ok { ret (0usize, e3) }
    let (n4, e4) = list(a, t, 500u64, prices[0usize..4usize], 2usize, false)
    if e4 != ok { ret (0usize, e4) }
    let art = [2]str{ "C:\\Users\\gaddl\\AppData\\Roaming\\MTG Studio\\Card Art", "MTG Studio Download (all editions + promos)" }
    let (n5, e5) = list(a, t, 600u64, art[0usize..2usize], 1usize, true)
    if e5 != ok { ret (0usize, e5) }
    let (n6, e6) = list(a, t, 700u64, rules[0usize..4usize], 2usize, false)
    if e6 != ok { ret (0usize, e6) }
    cells[0usize] = looks.Cell { caption: "Rules, rest (row 1 current)", node: n0, drive: .None }
    cells[1usize] = looks.Cell { caption: "Rules, row 2 selected, list focused", node: n1, drive: .None }
    cells[2usize] = looks.Cell { caption: "Rules, row 2 selected, list not focused", node: n2, drive: .None }
    cells[3usize] = looks.Cell { caption: "Rules, row 3 selected (focused / check box pressed grabs)", node: n3, drive: .None }
    cells[4usize] = looks.Cell { caption: "Prices, row 3 selected", node: n4, drive: .None }
    cells[5usize] = looks.Cell { caption: "Card Art (item images), row 2 selected", node: n5, drive: .None }
    cells[6usize] = looks.Cell { caption: "Rules, row 3, check box pressed grab", node: n6, drive: .None }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "check_list_box_states", cells: 7usize, columns: 1usize, cell_w: 500.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
