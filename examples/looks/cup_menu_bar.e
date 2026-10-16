// The Cupertino menu bar (the macOS menu bar): docs/ui/looks/cupertino/menu_bar.png and menu_bar-open.png (and cupertino-dark).
// The Apple logo, the app menu in bold, then the menus at 13 pt on the 24 tall bar; a title holds a translucent grey chip while its
// menu is open or pressed (macOS has no hover on the bar). Run `cup_menu_bar menu_bar_open` for the open menu (a modal overlay renders
// one per process).

use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn placed(a: *mem.Arena, node: widget.Node, x: f32, y: f32, w: f32, h: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = node
    ret (widget.padded(0u64, x, y, 0.0, 0.0, control.sized_style(w, h), inner[0usize..1usize]), ok)
}

fn command(label: str, shortcut: str, enabled: bool, separated: bool, action: widget.Submit) -> navigation.BarCommand {
    var c: navigation.BarCommand = zero
    c.label = label
    c.shortcut = shortcut
    c.enabled = enabled
    c.separated = separated
    c.action = action
    ret c
}

fn bar(a: *mem.Arena, t: *const control.Theme, action: widget.Submit, base: widget.Key, open: usize) -> (widget.Node, err) {
    let titles = [7]str{ "MTG Studio", "File", "Edit", "View", "Cards", "Window", "Help" }
    let (cards, cards_error) = mem.alloc[navigation.BarCommand](a, 6usize)
    if cards_error != ok { ret (zero, cards_error) }
    cards[0usize] = command("Add to Deck", "", false, false, action)
    cards[1usize] = command("Add 4 to Deck", "Ctrl+Ins", false, false, action)
    cards[2usize] = command("Add to Collection", "", true, true, action)
    cards[3usize] = command("Increase Quantity", "Num +", true, false, action)
    cards[4usize] = command("Cut", "Cmd+X", true, true, action)
    cards[5usize] = command("Select All", "Cmd+A", true, false, action)
    let (menus, menus_error) = mem.alloc[navigation.BarMenu](a, 7usize)
    if menus_error != ok { ret (zero, menus_error) }
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, 7usize)
    if toggles_error != ok { ret (zero, toggles_error) }
    var i = 0usize
    while i < 7usize {
        toggles[i] = action
        menus[i] = navigation.BarMenu { label: titles[i], commands: cards[0usize..6usize] }
        i += 1usize
    }
    let (made, made_error) = navigation.menu_bar_of(a, base, t, "Main menu", menus[0usize..7usize], open, toggles[0usize..7usize])
    ret (made, made_error)
}

fn actions_of(a: *mem.Arena) -> (*widget.Submit, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    ret (&actions[0usize], ok)
}

// Three cells: the bar at rest, the pointer on a title (no hover look on macOS), a title pressed (the grey chip).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let captions = [3]str{ "Rest", "Hover (Edit)", "Pressed (Edit)" }
    var i = 0usize
    while i < 3usize {
        let (menu_bar, bar_error) = bar(a, t, *action, 10000u64 * u64(i + 1usize), 99usize)
        if bar_error != ok { ret (0usize, bar_error) }
        var drive: looks.Drive = .None
        var x: f32 = 0.0
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i != 0usize { x = 350.0 - 188.0 }
        let (shifted, shifted_error) = placed(a, menu_bar, x, 0.0, 700.0, 24.0)
        if shifted_error != ok { ret (0usize, shifted_error) }
        cells[i] = looks.Cell { caption: captions[i], node: shifted, drive: drive }
        i += 1usize
    }
    ret (3usize, ok)
}

fn build_open(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (menu_bar, bar_error) = bar(a, t, *action, 10000u64, 4usize)
    if bar_error != ok { ret (0usize, bar_error) }
    let (shifted, shifted_error) = placed(a, menu_bar, 0.0, 0.0, 700.0, 200.0)
    if shifted_error != ok { ret (0usize, shifted_error) }
    cells[0usize] = looks.Cell { caption: "Open (Cards)", node: shifted, drive: .Hover }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let open_sheet = looks.Sheet { name: "menu_bar-open", cells: 1usize, columns: 1usize, cell_w: 700.0, cell_h: 200.0, ctx: zero, build: build_open }
        ret looks.run_cupertino(a, &open_sheet)
    }
    let sheet = looks.Sheet { name: "menu_bar", cells: 3usize, columns: 1usize, cell_w: 700.0, cell_h: 24.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
