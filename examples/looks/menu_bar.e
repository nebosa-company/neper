// The main menu bar (TdxBarSubItem) in its states under every look: docs/ui/looks/<look>/menu_bar.png.
// Run from the repository root; see docs/ui/looks-howto.md. The bar is v3's main menu
// (File Cards Search View Card Art Online Reports Tools Admin Help); the Windows look draws it on
// the dxBar strip with Tahoma 11 titles, a sunken open title and the popup menu below it.

use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// `node` at (x, y) inside a `w` x `h` box, so that a driven pointer at the box's centre lands
// where the cell wants it.
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

fn bar(a: *mem.Arena, t: *const control.Theme, action: widget.Submit, base: widget.Key, open: usize, only_cards: bool) -> (widget.Node, err) {
    let plain = [10]str{ "File", "Cards", "Search", "View", "Card Art", "Online", "Reports", "Tools", "Admin", "Help" }
    // The Windows look underlines the letter after the `&` (v3's mnemonics: Card &Art, A&dmin).
    let marked = [10]str{ "&File", "&Cards", "&Search", "&View", "Card &Art", "&Online", "&Reports", "&Tools", "A&dmin", "&Help" }
    var titles = plain
    if t.tokens.profile == .Windows { titles = marked }
    var count = 10usize
    if only_cards { count = 4usize }
    let (cards, cards_error) = mem.alloc[navigation.BarCommand](a, 6usize)
    if cards_error != ok { ret (zero, cards_error) }
    cards[0usize] = command("Add to Deck", "", false, false, action)
    cards[1usize] = command("Add 4 to Deck", "Ctrl+Ins", false, false, action)
    cards[2usize] = command("Add to Collection", "", true, true, action)
    cards[3usize] = command("Increase Quantity", "Num +", true, false, action)
    cards[4usize] = command("Cut", "Ctrl+X", true, true, action)
    cards[5usize] = command("Select All", "Ctrl+A", true, false, action)
    let (menus, menus_error) = mem.alloc[navigation.BarMenu](a, count)
    if menus_error != ok { ret (zero, menus_error) }
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, count)
    if toggles_error != ok { ret (zero, toggles_error) }
    var i = 0usize
    while i < count {
        toggles[i] = action
        var commands: []const navigation.BarCommand = zero
        commands = cards[0usize..6usize]
        menus[i] = navigation.BarMenu { label: titles[i], commands: commands }
        i += 1usize
    }
    let (made, made_error) = navigation.menu_bar_of(a, base, t, "Main menu", menus[0usize..count], open, toggles[0usize..count])
    ret (made, made_error)
}

fn actions_of(a: *mem.Arena) -> (*widget.Submit, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    ret (&actions[0usize], ok)
}

// Three cells, 44 high with the bar's Cards title under the pointer when driven: the bar at
// rest, a hovered title and a pressed title. (An open menu is modal, so it has its own sheet.)
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let captions = [3]str{ "Rest", "Hover (Cards)", "Pressed (Cards)" }
    var i = 0usize
    while i < 3usize {
        let (menu_bar, bar_error) = bar(a, t, *action, 10000u64 * u64(i + 1usize), 99usize, i != 0usize)
        if bar_error != ok { ret (0usize, bar_error) }
        var drive: looks.Drive = .None
        var x: f32 = 0.0
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i != 0usize { x = 331.0 }
        let (shifted, shifted_error) = placed(a, menu_bar, x, 0.0, 782.0, 26.0)
        if shifted_error != ok { ret (0usize, shifted_error) }
        cells[i] = looks.Cell { caption: captions[i], node: shifted, drive: drive }
        i += 1usize
    }
    ret (3usize, ok)
}

// The Cards title open, its menu hanging below it.
fn build_open(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (menu_bar, bar_error) = bar(a, t, *action, 10000u64, 1usize, true)
    if bar_error != ok { ret (0usize, bar_error) }
    let (shifted, shifted_error) = placed(a, menu_bar, 0.0, 4.0, 520.0, 190.0)
    if shifted_error != ok { ret (0usize, shifted_error) }
    cells[0usize] = looks.Cell { caption: "Open (Cards)", node: shifted, drive: .None }
    ret (1usize, ok)
}

// The captured title states (ref/windows/menu_bar_open_<title>.png: the bar strip of
// states/menu-bar-open-title-*, and menu_bar_hot_view.png: the left 298 px of the rest grab, where the
// pointer rested on View). One cell, the strip 26 tall; an open title shows its menu below (clipped).
type State = struct { open: usize, hot: bool }

fn build_state(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let state = mem.cast[*State](ctx)
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (menu_bar, bar_error) = bar(a, t, *action, 10000u64, state.open, false)
    if bar_error != ok { ret (0usize, bar_error) }
    var drive: looks.Drive = .None
    var w: f32 = 782.0
    var x: f32 = 0.0
    var h: f32 = 260.0
    if state.hot {
        // The pointer is driven to the cell's centre: a cell 1266 wide puts View (149 in the strip)
        // there with the bar at x 484 and its full 782 px.
        drive = .Hover
        w = 1266.0
        x = 484.0
        h = 26.0
    }
    let (shifted, shifted_error) = placed(a, menu_bar, x, 0.0, w, h)
    if shifted_error != ok { ret (0usize, shifted_error) }
    cells[0usize] = looks.Cell { caption: "", node: shifted, drive: drive }
    ret (1usize, ok)
}

// The ten hot titles of the live grabs (ref/windows/states/hover-menubar-title-*): the bar strip, one cell per grab, shifted so
// that the title under v3's pointer sits at the cell's centre (where the harness's pointer goes).
fn build_hot(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let names = [10]str{ "File hot", "Cards hot", "Search hot", "View hot", "Card Art hot", "Online hot", "Reports hot", "Tools hot", "Admin hot", "Help hot" }
    // each title's centre in the strip (box left and right edges measured on the grabs)
    let centres = [10]f32{ 25.0, 60.0, 105.0, 149.0, 197.0, 249.0, 299.0, 346.0, 389.0, 430.0 }
    var i = 0usize
    while i < 10usize {
        let (menu_bar, bar_error) = bar(a, t, *action, 10000u64 * u64(i + 1usize), 99usize, false)
        if bar_error != ok { ret (0usize, bar_error) }
        let (shifted, shifted_error) = placed(a, menu_bar, 782.0 - centres[i], 0.0, 1564.0, 26.0)
        if shifted_error != ok { ret (0usize, shifted_error) }
        cells[i] = looks.Cell { caption: names[i], node: shifted, drive: .Hover }
        i += 1usize
    }
    ret (10usize, ok)
}

fn run_state(a: *mem.Arena, name: str, open: usize, hot: bool) -> err {
    let (state, state_error) = mem.alloc[State](a, 1usize)
    if state_error != ok { ret state_error }
    state[0usize] = State { open: open, hot: hot }
    var w: f32 = 782.0
    if hot { w = 1266.0 }
    // An open title's menu hangs below the strip (the sheet is tall enough for it to stay put).
    var h: f32 = 26.0
    if !hot { h = 260.0 }
    let sheet = looks.Sheet { name: name, cells: 1usize, columns: 1usize, cell_w: w, cell_h: h, ctx: mem.cast[*void](&state[0usize]), build: build_state }
    ret looks.run_all(a, &sheet)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var only = ""
    if args.len > 1usize { only = args[1usize] }
    if only.len > 0usize {
        let names = [10]str{ "file", "cards", "search", "view", "cardart", "online", "reports", "tools", "admin", "help" }
        var k = 0usize
        while k < 10usize {
            let pieces = [2]str{ "menu_bar_open_", names[k] }
            let (full, full_error) = strs.join(a, pieces[0usize..2usize], "")
            if full_error != ok { ret full_error }
            if strs.eq(only, full) { ret run_state(a, full, k, false) }
            k += 1usize
        }
        if strs.eq(only, "menu_bar_hot_view") { ret run_state(a, only, 99usize, true) }
        if strs.eq(only, "menu_bar_hot") {
            let hot = looks.Sheet { name: "menu_bar_hot", cells: 10usize, columns: 1usize, cell_w: 1564.0, cell_h: 26.0, ctx: zero, build: build_hot }
            ret looks.run_all(a, &hot)
        }
    }
    let sheet = looks.Sheet { name: "menu_bar", cells: 3usize, columns: 1usize, cell_w: 782.0, cell_h: 26.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    let open_sheet = looks.Sheet { name: "menu_bar-open", cells: 1usize, columns: 1usize, cell_w: 520.0, cell_h: 190.0, ctx: zero, build: build_open }
    ret looks.run_all(a, &open_sheet)
}
