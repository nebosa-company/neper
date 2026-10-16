// The check list box as v3's Options pages draw it: docs/ui/looks/<look>/check_list_box_dialog.png.
// One cell reproduces a crop of the live 100 % Rules page (495 x 343, nineteen checked rows, the
// first row current with the list focused); a second is the bottom right corner of the same list.
// Reference: ref/windows/check_list_box_dialog.png.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn at(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    ret (widget.positioned(0u64, x, y, style.defaults(), held[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, 19usize)
    if toggles_error != ok { ret (0usize, toggles_error) }
    let (picked, picked_error) = mem.alloc[bool](a, 19usize)
    if picked_error != ok { ret (0usize, picked_error) }
    var i = 0usize
    while i < 19usize {
        toggles[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        picked[i] = true
        i += 1usize
    }
    let labels = [19]str{ "Card Details (Cost, Type, Rarity, Set, etc.)", "Rules Printed on Card", "Flavor Text", "User Card Notes", "Oracle™ Rules (latest card rules)", "Card Notes (Official FAQ, Card of the Day, Lexicon, Ask Wizards, etc.)", "Reprint Notes (promos and digital cards details)", "Cycles", "Similar Cards", "Lexicon", "Abilities", "Converted Mana Cost", "Legality", "Collector No", "Artist Details", "Combos", "Online Tools", "Copies in the collection and in the opened decks", "" }
    // Rules page: the list at (215,94), 495 x 343 (crop (213,92)-(713,440)); 18 rows are shown.
    let (list, list_error) = windows_or_other(a, t, labels[0usize..18usize], picked[0usize..18usize], toggles[0usize..18usize])
    if list_error != ok { ret (0usize, list_error) }
    let (placed, placed_error) = at(a, list, 2.0, 2.0)
    if placed_error != ok { ret (0usize, placed_error) }
    let (layer, layer_error) = mem.alloc[widget.Node](a, 1usize)
    if layer_error != ok { ret (0usize, layer_error) }
    layer[0usize] = placed
    cells[0usize] = looks.Cell { caption: "Options, Rules page (first row current)", node: widget.stack(0u64, looks.size_style(500.0, 348.0), layer[0usize..1usize]), drive: .None }
    // Prices page: the list at (215,94), 495 x 343 (crop (213,92)-(713,440)); five rows, the first current.
    let prices = [5]str{ "TCG Player (Aggregated)", "TCG Player", "Magic Traders", "Find Magic Cards", "Wizards Cupboard" }
    let (prices_list, prices_error) = windows_or_other(a, t, prices[0usize..5usize], picked[0usize..5usize], toggles[0usize..5usize])
    if prices_error != ok { ret (0usize, prices_error) }
    let (prices_placed, prices_placed_error) = at(a, prices_list, 2.0, 2.0)
    if prices_placed_error != ok { ret (0usize, prices_placed_error) }
    let (layer_two, layer_two_error) = mem.alloc[widget.Node](a, 1usize)
    if layer_two_error != ok { ret (0usize, layer_two_error) }
    layer_two[0usize] = prices_placed
    cells[1usize] = looks.Cell { caption: "Options, Prices page (first row current)", node: widget.stack(0u64, looks.size_style(500.0, 348.0), layer_two[0usize..1usize]), drive: .None }
    // Card Art page: the list at (215,71), 464 x 308 with a 16 px image before each of its two rows (crop (213,69)-(681,381)).
    let art = [2]str{ "C:\\Users\\gaddl\\AppData\\Roaming\\MTG Studio\\Card Art", "MTG Studio Download (all editions + promos)" }
    var art_list: widget.Node = zero
    if t.tokens.profile == .Windows {
        let (drawn, drawn_error) = control.windows_check_list_art(a, 2u64, t, "Card Art", art[0usize..2usize], picked[0usize..2usize], toggles[0usize..2usize], 464.0, 308.0, 0usize, 215.0, 71.0)
        if drawn_error != ok { ret (0usize, drawn_error) }
        art_list = drawn
    } else {
        let (drawn, drawn_error) = control.multi_select_list(a, 2u64, t, "Card Art", art[0usize..2usize], picked[0usize..2usize], toggles[0usize..2usize], 2u32, 464.0)
        if drawn_error != ok { ret (0usize, drawn_error) }
        art_list = drawn
    }
    let (art_placed, art_placed_error) = at(a, art_list, 2.0, 2.0)
    if art_placed_error != ok { ret (0usize, art_placed_error) }
    let (layer_three, layer_three_error) = mem.alloc[widget.Node](a, 1usize)
    if layer_three_error != ok { ret (0usize, layer_three_error) }
    layer_three[0usize] = art_placed
    cells[2usize] = looks.Cell { caption: "Options, Card Art page (first row current)", node: widget.stack(0u64, looks.size_style(500.0, 348.0), layer_three[0usize..1usize]), drive: .None }
    ret (3usize, ok)
}

fn windows_or_other(a: *mem.Arena, t: *const control.Theme, labels: []const str, picked: []const bool, toggles: []const widget.Submit) -> (widget.Node, err) {
    if t.tokens.profile == .Windows {
        let (list, list_error) = control.windows_check_list_at(a, 1u64, t, "Card details", labels, picked, toggles, 495.0, 343.0, 0usize, 215.0, 94.0)
        ret (list, list_error)
    }
    let (list, list_error) = control.multi_select_list(a, 1u64, t, "Card details", labels, picked, toggles, 18u32, 495.0)
    ret (list, list_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "check_list_box_dialog", cells: 3usize, columns: 1usize, cell_w: 500.0, cell_h: 348.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
