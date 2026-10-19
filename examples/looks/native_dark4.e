// The Windows dark look beside the native Windows 11 dark captures, fourth sheet (round 13): list box, check list and popup menu, each at the
// capture's own geometry; scripts/looks_strict13.py (SHEET4) diffs every one.
// Only windows-dark matters: run with NEPER_LOOKS_OUT=<scratch> and copy <scratch>/windows-dark/native_dark2.png into docs/ui/looks/windows-dark.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.looks
use e.ui.style
use e.ui.widget

fn cell_w() -> f32 { ret 260.0 }
fn cell_h() -> f32 { ret 200.0 }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// `node` at a whole pixel (x, y) of a cell-sized holder.
fn placed(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
    ret (widget.stack(0u64, sized(cell_w(), cell_h()), inner[0usize..1usize]), ok)
}

fn noop_submit(ctx: *void) -> err { ret ok }

fn command(action: widget.Submit, label: str, shortcut: str, enabled: bool, separated: bool) -> navigation.BarCommand {
    var c: navigation.BarCommand = zero
    c.label = label
    c.shortcut = shortcut
    c.enabled = enabled
    c.separated = separated
    c.action = action
    ret c
}

fn pick_actions(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < n {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (picks, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var at = 0usize
    // 0: listbox-rest (118 x 110 at (16, 10)): seven rows of Alpha to Golf
    let words = [10]str{ "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet" }
    let (picks, picks_error) = pick_actions(a, 10usize)
    if picks_error != ok { ret (0usize, picks_error) }
    let (list, list_error) = control.list_box(a, 9000u64, t, "List", words[0usize..10usize], 9usize, picks, 7u32, 118.0)
    if list_error != ok { ret (0usize, list_error) }
    let (list_cell, list_cell_error) = placed(a, list, 16.0, 10.0)
    if list_cell_error != ok { ret (0usize, list_cell_error) }
    cells[at] = looks.Cell { caption: "listbox-rest", node: list_cell, drive: .None }
    at += 1usize
    // 1: listbox-selected-focused (Charlie chosen)
    let (picks2, picks2_error) = pick_actions(a, 10usize)
    if picks2_error != ok { ret (0usize, picks2_error) }
    let (list2, list2_error) = control.list_box(a, 9100u64, t, "List", words[0usize..10usize], 2usize, picks2, 7u32, 118.0)
    if list2_error != ok { ret (0usize, list2_error) }
    let (list2_cell, list2_cell_error) = placed(a, list2, 16.0, 10.0)
    if list2_cell_error != ok { ret (0usize, list2_cell_error) }
    looks.aim(at, 0.0 - 64.0, 0.0 - 51.0)
    cells[at] = looks.Cell { caption: "listbox-selected-focused", node: list2_cell, drive: .Focus }
    at += 1usize
    // 5: listbox-selected-unfocused (and -hover: the same pixels)
    let (picks3, picks3_error) = pick_actions(a, 10usize)
    if picks3_error != ok { ret (0usize, picks3_error) }
    let (list3, list3_error) = control.list_box(a, 9150u64, t, "List", words[0usize..10usize], 2usize, picks3, 7u32, 118.0)
    if list3_error != ok { ret (0usize, list3_error) }
    let (list3_cell, list3_cell_error) = placed(a, list3, 16.0, 10.0)
    if list3_cell_error != ok { ret (0usize, list3_cell_error) }
    cells[at] = looks.Cell { caption: "listbox-selected-unfocused", node: list3_cell, drive: .None }
    at += 1usize
    // 2 and 3: checklist-rest and -selected-focused (158 x 110 at (16, 10)); Bravo and Delta checked
    var c = 0usize
    while c < 2usize {
        let (toggles, toggles_error) = pick_actions(a, 9usize)
        if toggles_error != ok { ret (0usize, toggles_error) }
        let (chosen, chosen_error) = mem.alloc[bool](a, 9usize)
        if chosen_error != ok { ret (0usize, chosen_error) }
        var k = 0usize
        while k < 9usize {
            chosen[k] = k == 1usize || k == 3usize
            k += 1usize
        }
        var current = 9usize
        if c == 1usize { current = 1usize }
        let (check, check_error) = control.windows_check_list_sized(a, u64(9200usize + 100usize * c), t, "Check", words[0usize..9usize], chosen, toggles, 158.0, 110.0, current)
        if check_error != ok { ret (0usize, check_error) }
        let (check_cell, check_cell_error) = placed(a, check, 16.0, 10.0)
        if check_cell_error != ok { ret (0usize, check_cell_error) }
        let names = [2]str{ "checklist-rest", "checklist-selected-focused" }
        var drive: looks.Drive = .None
        if c == 1usize {
            drive = .Focus
            looks.aim(at, 0.0 - 70.0, 0.0 - 66.0)
        }
        cells[at] = looks.Cell { caption: names[c], node: check_cell, drive: drive }
        at += 1usize
        c += 1usize
    }
    // 5: checklist-selected-unfocused (Bravo current, no keyboard focus in the list)
    let (toggles5, toggles5_error) = pick_actions(a, 9usize)
    if toggles5_error != ok { ret (0usize, toggles5_error) }
    let (chosen5, chosen5_error) = mem.alloc[bool](a, 9usize)
    if chosen5_error != ok { ret (0usize, chosen5_error) }
    var k5 = 0usize
    while k5 < 9usize {
        chosen5[k5] = k5 == 1usize || k5 == 3usize
        k5 += 1usize
    }
    let (check5, check5_error) = control.windows_check_list_sized(a, 9400u64, t, "Check", words[0usize..9usize], chosen5, toggles5, 158.0, 110.0, 1usize)
    if check5_error != ok { ret (0usize, check5_error) }
    let (check5_cell, check5_cell_error) = placed(a, check5, 16.0, 10.0)
    if check5_cell_error != ok { ret (0usize, check5_cell_error) }
    cells[at] = looks.Cell { caption: "checklist-selected-unfocused", node: check5_cell, drive: .None }
    at += 1usize
    // 6: listbox-disabled (the chosen Charlie keeps its fill, the words are #6D6D6D)
    let (picks6, picks6_error) = pick_actions(a, 10usize)
    if picks6_error != ok { ret (0usize, picks6_error) }
    let (list6, list6_error) = control.windows_dark_list_box_disabled(a, 9500u64, t, "List", words[0usize..10usize], 2usize, picks6, 7u32, 118.0)
    if list6_error != ok { ret (0usize, list6_error) }
    let (list6_cell, list6_cell_error) = placed(a, list6, 16.0, 10.0)
    if list6_cell_error != ok { ret (0usize, list6_cell_error) }
    cells[at] = looks.Cell { caption: "listbox-disabled", node: list6_cell, drive: .None }
    at += 1usize
    ret (at, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark4", cells: 7usize, columns: 4usize, cell_w: cell_w(), cell_h: cell_h(), ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
