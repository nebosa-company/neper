// A dialog (v3's windows) under every look: docs/ui/looks/<look>/dialog.png and dialog_wide.png.
// Run from the repository root; see docs/ui/looks-howto.md.
//
// The Windows cells are real v3 dialogs reproduced from docs/ui/looks/ref/windows/dialogs: Search for Card, Sort, Missing
// Set Cards, Deck Properties and About MTG Studio (dialog.png), Options (dialog_wide.png). Each is a
// form window (e.ui.overlay.windows_window): the dark caption (e.ui.navigation.title_bar), the #F0F0F0 face, and the
// buttons and labels at the DFM's own positions (v3 forms are laid out by hand, so the button row differs per dialog:
// Options and Deck Properties 9 from the right edge and 7 from the bottom, Search for Card centred). What the other
// controls draw (the combo box, radio group, grid, page control, vertical grid) is left blank: those are other sheets.
// Under the Neper look the sheet shows the one card dialog the Neper look has.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// kind 0 button (flag: default), 1 label (flag: wrap), 2 bold #33486C label, 3 plain label
type Item = struct { kind: u32, x: f32, y: f32, w: f32, h: f32, text: str, flag: bool }
type Form = struct { title: str, width: f32, height: f32, active: bool, items: [6]Item, count: usize }

fn item(kind: u32, x: f32, y: f32, w: f32, h: f32, text: str, flag: bool) -> Item {
    ret Item { kind: kind, x: x, y: y, w: w, h: h, text: text, flag: flag }
}

fn form(i: usize) -> Form {
    let none = item(0u32, 0.0, 0.0, 0.0, 0.0, "", false)
    var f = Form { title: "", width: 0.0, height: 0.0, active: true, items: [6]Item{ none, none, none, none, none, none }, count: 0usize }
    if i == 0usize {
        f.title = "Search for Card"
        f.width = 309.0
        f.height = 249.0
        f.items = [6]Item{ item(3u32, 20.0, 47.0, 289.0, 17.0, "Card:", false), item(0u32, 83.0, 215.0, 75.0, 23.0, "OK", true), item(0u32, 167.0, 215.0, 75.0, 23.0, "Cancel", false), none, none, none }
        f.count = 3usize
    }
    if i == 1usize {
        f.title = "Sort [Card Pool]"
        f.width = 351.0
        f.height = 339.0
        f.items = [6]Item{ item(0u32, 18.0, 310.0, 75.0, 23.0, "Clear", false), item(0u32, 193.0, 310.0, 75.0, 23.0, "OK", true), item(0u32, 274.0, 310.0, 75.0, 23.0, "Cancel", false), none, none, none }
        f.count = 3usize
    }
    if i == 2usize {
        f.title = "Missing Set Cards"
        f.width = 250.0
        f.height = 495.0
        f.items = [6]Item{ item(1u32, 16.0, 39.0, 234.0, 34.0, "Select which edition cards' availability to be checked:", true), item(0u32, 93.0, 465.0, 75.0, 23.0, "OK", true), item(0u32, 174.0, 465.0, 75.0, 23.0, "Cancel", false), none, none, none }
        f.count = 3usize
    }
    if i == 3usize {
        f.title = "Deck Properties"
        f.width = 348.0
        f.height = 544.0
        f.items = [6]Item{ item(2u32, 56.0, 34.0, 291.0, 20.0, "MTG Studio", false), item(3u32, 56.0, 55.0, 291.0, 17.0, "C:\\Users\\gaddl\\Desktop\\New Deck.deck", false), item(0u32, 188.0, 514.0, 75.0, 23.0, "OK", true), item(0u32, 272.0, 514.0, 75.0, 23.0, "Cancel", false), none, none }
        f.count = 4usize
    }
    if i == 4usize {
        f.title = "About MTG Studio"
        f.width = 436.0
        f.height = 364.0
        f.active = false
        f.items = [6]Item{ item(0u32, 360.0, 334.0, 75.0, 23.0, "OK", true), none, none, none, none, none }
        f.count = 1usize
    }
    if i == 6usize {
        f.title = "Options"
        f.width = 712.0
        f.height = 486.0
        f.active = false
        f.items = [6]Item{ item(0u32, 468.0, 456.0, 75.0, 23.0, "OK", true), item(0u32, 552.0, 456.0, 75.0, 23.0, "Cancel", false), item(0u32, 636.0, 456.0, 75.0, 23.0, "&Apply", false), none, none, none }
        f.count = 3usize
    }
    // looks4: the same About and Options windows ACTIVE (caption #1F2022), as the live rest grabs show them
    // (docs/ui/looks/ref/windows/states/dialog-about-rest, dialog-options-interface-rest).
    if i == 5usize {
        f.title = "About MTG Studio"
        f.width = 436.0
        f.height = 364.0
        f.items = [6]Item{ item(0u32, 360.0, 334.0, 75.0, 23.0, "OK", true), none, none, none, none, none }
        f.count = 1usize
    }
    if i == 7usize {
        f.title = "Options"
        f.width = 712.0
        f.height = 486.0
        f.items = [6]Item{ item(0u32, 468.0, 456.0, 75.0, 23.0, "OK", true), item(0u32, 552.0, 456.0, 75.0, 23.0, "Cancel", false), item(0u32, 636.0, 456.0, 75.0, 23.0, "&Apply", false), none, none, none }
        f.count = 3usize
    }
    if i == 8usize {
        f.title = "Statistics"
        f.width = 941.0
        f.height = 501.0
        f.items = [6]Item{ item(0u32, 865.0, 471.0, 75.0, 23.0, "Close", true), none, none, none, none, none }
        f.count = 1usize
    }
    ret f
}

fn at(a: *mem.Arena, x: f32, y: f32, node: widget.Node) -> widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret node }
    held[0usize] = node
    ret widget.positioned(0u64, x, y, style.defaults(), held[0usize..1usize])
}

// The window of form `i`: the caption, the face and its controls at their DFM positions (the capture's x is 8 more
// than the window's, its invisible resize border; a button is drawn from (1, 1) inside its control rect).
fn window(a: *mem.Arena, t: *const control.Theme, i: usize, action: *const widget.Submit) -> (widget.Node, err) {
    let f = form(i)
    var options = navigation.title_bar_options(.Windows)
    options.active = f.active
    options.minimizable = false
    options.maximizable = false
    let base = u64(i + 1usize) * 100u64
    let (bar, bar_error) = navigation.title_bar(a, base, t, f.title, options, f.width)
    if bar_error != ok { ret (zero, bar_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, f.count + 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = at(a, 0.0, 0.0, bar)
    var n = 1usize
    var k = 0usize
    while k < f.count {
        let it = f.items[k]
        let key = base + 10u64 + u64(k)
        if it.kind == 0u32 {
            var bo = control.button_options()
            if it.flag { bo.variant = .Default }
            bo.width = it.w
            bo.height = it.h
            let (b, b_error) = control.button(a, key, t, it.text, action, bo)
            if b_error != ok { ret (zero, b_error) }
            parts[n] = at(a, it.x - 8.0 + 1.0, it.y + 1.0, b)
        } else {
            var size: f32 = 11.0
            var weight = 400u32
            var ink = style.hex(0u32)
            if it.kind == 2u32 {
                size = 13.0
                weight = 700u32
                ink = style.hex(0x33486Cu32)
            }
            var wrap: f32 = 0.0
            if it.flag { wrap = it.w }
            let (l, l_error) = control.windows_label(a, t, it.text, size, weight, ink, false, wrap)
            if l_error != ok { ret (zero, l_error) }
            parts[n] = at(a, it.x - 8.0, it.y, l)
        }
        n += 1usize
        k += 1usize
    }
    let (win, win_error) = overlay.windows_window(a, t, f.width, f.height, parts[0usize..n])
    ret (win, win_error)
}

fn neper_card(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (buttons, buttons_error) = mem.alloc[overlay.DialogButton](a, 3usize)
    if buttons_error != ok { ret (0usize, buttons_error) }
    let none = widget.Submit { ctx: zero, invoke: noop_submit }
    buttons[0usize] = overlay.DialogButton { label: "OK", action: none, kind: .Default }
    buttons[1usize] = overlay.DialogButton { label: "Cancel", action: none, kind: .Cancel }
    buttons[2usize] = overlay.DialogButton { label: "Apply", action: none, kind: .Plain }
    var words = control.text_options()
    let (body, body_error) = control.text(a, 0u64, "Hide splash screen on start", t, words)
    if body_error != ok { ret (0usize, body_error) }
    let (dialog, dialog_error) = overlay.dialog(a, 100u64, t, "Options", body, buttons[0usize..3usize], true, false)
    if dialog_error != ok { ret (0usize, dialog_error) }
    // The dialog's overlay centres in the whole sheet; the cell only reserves the room.
    cells[0usize] = looks.Cell { caption: "Options", node: dialog, drive: .None }
    ret (1usize, ok)
}

// A window of `width` x `height` in a cell of `cell_w` x `cell_h`, on whole pixels: a holder one larger when the margin
// would be odd.
fn whole(a: *mem.Arena, node: widget.Node, width: f32, height: f32, cell_w: f32, cell_h: f32) -> widget.Node {
    let holder = control.sized_style(width + f32(u32(cell_w - width) % 2u32), height + f32(u32(cell_h - height) % 2u32))
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret node }
    held[0usize] = node
    ret widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, holder, held[0usize..1usize])
}

fn build_set(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, first: usize, count: usize, cell_w: f32, cell_h: f32) -> (usize, err) {
    if t.tokens.profile != .Windows {
        let (n, e) = neper_card(a, t, cells)
        ret (n, e)
    }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < count {
        let f = form(first + i)
        let (win, win_error) = window(a, t, first + i, &actions[0usize])
        if win_error != ok { ret (0usize, win_error) }
        cells[i] = looks.Cell { caption: f.title, node: whole(a, win, f.width, f.height, cell_w, cell_h), drive: .None }
        i += 1usize
    }
    ret (count, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (n, e) = build_set(a, t, cells, 0usize, 6usize, 440.0, 548.0)
    ret (n, e)
}

fn build_wide(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (n, e) = build_set(a, t, cells, 6usize, 2usize, 714.0, 488.0)
    ret (n, e)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "dialog", cells: 6usize, columns: 3usize, cell_w: 440.0, cell_h: 548.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    let wide = looks.Sheet { name: "dialog_wide", cells: 2usize, columns: 1usize, cell_w: 714.0, cell_h: 488.0, ctx: zero, build: build_wide }
    ret looks.run_all(a, &wide)
}
