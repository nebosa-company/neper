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

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// kind 0 button (flag: default), 1 label (flag: wrap), 2 bold #33486C label, 3 plain label, 4 disabled button, 5 focused button; `bg` the face behind
// the item when it is not the dialog's (v3's Filter page is #F9F9F9: a ring row blends with it), 0 for none
type Item = struct { kind: u32, x: f32, y: f32, w: f32, h: f32, text: str, flag: bool, bg: u32 }
// `tkind` the caption: 0 dialog (close only), 1 resizable with minimise disabled, 2 all three, 3 light, 4 tool window;
// `bottom` the #F5F5F5 row the captured Deck Legality, Deck Properties, About, Options and Customization windows end with
// `kx`, `ky`, `cx`, `cy` (looks5): the DPI-scaled forms (Deck Properties, About, Options, Deck Legality) draw every button moved by a
// sub-pixel offset (cx + x * kx, cy + y * ky) that grows with its position: fitted to the captured buttons (see e.ui.winbutton); the ring has
// its own exact phase (rcx + x * rkx, rcy + y * rky, looks9: scripts/looks_ref_a/fitring.py), the caption the old one
type Form = struct { title: str, width: f32, height: f32, active: bool, tkind: u32, bottom: bool, kx: f32, ky: f32, cx: f32, cy: f32, rkx: f32, rky: f32, rcx: f32, rcy: f32, items: [24]Item, count: usize }

fn item(kind: u32, x: f32, y: f32, w: f32, h: f32, text: str, flag: bool) -> Item {
    ret Item { kind: kind, x: x, y: y, w: w, h: h, text: text, flag: flag, bg: 0u32 }
}

fn itemb(kind: u32, x: f32, y: f32, w: f32, h: f32, text: str, flag: bool, bg: u32) -> Item {
    ret Item { kind: kind, x: x, y: y, w: w, h: h, text: text, flag: flag, bg: bg }
}

fn pad6(six: [6]Item) -> [24]Item {
    let none = item(0u32, 0.0, 0.0, 0.0, 0.0, "", false)
    var out = [24]Item{ none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none }
    var k = 0usize
    while k < 6usize {
        out[k] = six[k]
        k += 1usize
    }
    ret out
}

fn form(i: usize) -> Form {
    let none = item(0u32, 0.0, 0.0, 0.0, 0.0, "", false)
    var f = Form { title: "", width: 0.0, height: 0.0, active: true, tkind: 0u32, bottom: false, kx: 0.0, ky: 0.0, cx: 0.0, cy: 0.0, rkx: 0.0, rky: 0.0, rcx: 0.0, rcy: 0.0, items: pad6([6]Item{ none, none, none, none, none, none }), count: 0usize }
    if i == 0usize {
        f.title = "Search for Card"
        f.width = 309.0
        f.height = 249.0
        f.items = pad6([6]Item{ item(3u32, 20.0, 47.0, 289.0, 17.0, "Card:", false), item(0u32, 83.0, 215.0, 75.0, 23.0, "OK", true), item(0u32, 167.0, 215.0, 75.0, 23.0, "Cancel", false), none, none, none })
        f.count = 3usize
    }
    if i == 1usize {
        f.title = "Sort [Card Pool]"
        f.width = 351.0
        f.height = 339.0
        f.items = pad6([6]Item{ item(0u32, 18.0, 310.0, 75.0, 23.0, "Clear", false), item(0u32, 193.0, 310.0, 75.0, 23.0, "OK", true), item(0u32, 274.0, 310.0, 75.0, 23.0, "Cancel", false), none, none, none })
        f.count = 3usize
    }
    if i == 2usize {
        f.title = "Missing Set Cards"
        f.width = 250.0
        f.height = 495.0
        f.items = pad6([6]Item{ item(1u32, 16.0, 39.0, 234.0, 34.0, "Select which edition cards' availability to be checked:", true), item(0u32, 93.0, 465.0, 75.0, 23.0, "OK", true), item(0u32, 174.0, 465.0, 75.0, 23.0, "Cancel", false), none, none, none })
        f.count = 3usize
    }
    if i == 3usize {
        f.kx = 0.000746
        f.ky = 0.000935
        f.cx = 0.00
        f.cy = 0.00
        f.rkx = 0.000628
        f.rcx = 0.0
        f.rky = 0.000613
        f.rcy = 0.0
        f.bottom = true
        f.title = "Deck Properties"
        f.width = 348.0
        f.height = 545.0
        f.items = pad6([6]Item{ item(2u32, 56.0, 34.0, 291.0, 20.0, "MTG Studio", false), item(3u32, 56.0, 55.0, 291.0, 17.0, "C:\\Users\\gaddl\\Desktop\\New Deck.deck", false), item(0u32, 188.0, 514.0, 75.0, 23.0, "OK", true), item(0u32, 272.0, 514.0, 75.0, 23.0, "Cancel", false), none, none })
        f.count = 4usize
    }
    if i == 4usize {
        f.kx = 0.001053
        f.ky = 0.001377
        f.cx = 0.00
        f.cy = 0.00
        f.rkx = 0.000995
        f.rcx = 0.0
        f.rky = 0.000928
        f.rcy = 0.0
        f.bottom = true
        f.title = "About MTG Studio"
        f.width = 436.0
        f.height = 365.0
        f.active = false
        f.items = pad6([6]Item{ item(5u32, 360.0, 334.0, 75.0, 23.0, "OK", true), none, none, none, none, none })
        f.count = 1usize
    }
    if i == 6usize {
        f.kx = 0.000714
        f.ky = 0.000990
        f.cx = 0.03
        f.cy = 0.03
        f.rkx = 0.000738
        f.rcx = -0.005
        f.rky = 0.000742
        f.rcy = -0.0243
        f.bottom = true
        f.title = "Options"
        f.width = 712.0
        f.height = 487.0
        f.active = false
        f.items = pad6([6]Item{ item(0u32, 468.0, 456.0, 75.0, 23.0, "OK", true), item(0u32, 552.0, 456.0, 75.0, 23.0, "Cancel", false), item(0u32, 636.0, 456.0, 75.0, 23.0, "&Apply", false), none, none, none })
        f.count = 3usize
    }
    // looks4: the same About and Options windows ACTIVE (caption #1F2022), as the live rest grabs show them
    // (docs/ui/looks/ref/windows/states/dialog-about-rest, dialog-options-interface-rest).
    if i == 5usize {
        f.kx = 0.001053
        f.ky = 0.001377
        f.cx = 0.00
        f.cy = 0.00
        f.rkx = 0.000995
        f.rcx = 0.0
        f.rky = 0.000928
        f.rcy = 0.0
        f.bottom = true
        f.title = "About MTG Studio"
        f.width = 436.0
        f.height = 365.0
        f.items = pad6([6]Item{ item(5u32, 360.0, 334.0, 75.0, 23.0, "OK", true), none, none, none, none, none })
        f.count = 1usize
    }
    if i == 7usize {
        f.kx = 0.000714
        f.ky = 0.000990
        f.cx = 0.03
        f.cy = 0.03
        f.rkx = 0.000738
        f.rcx = -0.005
        f.rky = 0.000742
        f.rcy = -0.0243
        f.bottom = true
        f.title = "Options"
        f.width = 712.0
        f.height = 487.0
        f.items = pad6([6]Item{ item(0u32, 468.0, 456.0, 75.0, 23.0, "OK", true), item(0u32, 552.0, 456.0, 75.0, 23.0, "Cancel", false), item(0u32, 636.0, 456.0, 75.0, 23.0, "&Apply", false), none, none, none })
        f.count = 3usize
    }
    if i == 8usize {
        f.title = "Statistics"
        f.width = 941.0
        f.height = 501.0
        f.items = pad6([6]Item{ item(0u32, 865.0, 471.0, 75.0, 23.0, "Close", true), none, none, none, none, none })
        f.count = 1usize
    }
    if i == 9usize {
        f.title = "Filter Card Pool"
        f.width = 692.0
        f.height = 485.0
        f.tkind = 2u32
        f.items = [24]Item{ itemb(0u32, 109.0, 413.0, 75.0, 23.0, "None", false, 0xF9F9F9u32), itemb(0u32, 195.0, 413.0, 75.0, 23.0, "Invert", false, 0xF9F9F9u32), itemb(0u32, 28.0, 413.0, 75.0, 23.0, "All", false, 0xF9F9F9u32), itemb(0u32, 104.0, 455.0, 75.0, 23.0, "&Help", false, 0x000000u32), itemb(0u32, 616.0, 455.0, 75.0, 23.0, "&Apply", false, 0x000000u32), itemb(0u32, 532.0, 455.0, 75.0, 23.0, "Cancel", false, 0x000000u32), itemb(0u32, 23.0, 455.0, 75.0, 23.0, "C&lear", false, 0x000000u32), itemb(0u32, 451.0, 455.0, 75.0, 23.0, "OK", false, 0x000000u32), none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none }
        f.count = 8usize
    }
    if i == 10usize {
        f.title = "Advanced Filter"
        f.width = 544.0
        f.height = 347.0
        f.tkind = 3u32
        f.items = [24]Item{ itemb(0u32, 308.0, 315.0, 75.0, 25.0, "OK", false, 0x000000u32), itemb(0u32, 389.0, 315.0, 75.0, 25.0, "Cancel", false, 0x000000u32), itemb(0u32, 470.0, 315.0, 75.0, 25.0, "&Apply", false, 0x000000u32), itemb(0u32, 96.0, 315.0, 75.0, 25.0, "&Save As...", false, 0x000000u32), itemb(0u32, 15.0, 315.0, 75.0, 25.0, "&Open...", false, 0x000000u32), none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none }
        f.count = 5usize
    }
    if i == 11usize {
        f.title = "Conditional Formatting Rules Manager"
        f.width = 684.0
        f.height = 413.0
        f.tkind = 3u32
        f.items = [24]Item{ itemb(0u32, 18.0, 84.0, 125.0, 25.0, "&New Rule...", false, 0x000000u32), itemb(4u32, 280.0, 84.0, 125.0, 25.0, "&Delete Rule", false, 0x000000u32), itemb(4u32, 149.0, 84.0, 125.0, 25.0, "&Edit Rule...", false, 0x000000u32), itemb(4u32, 597.0, 378.0, 85.0, 25.0, "&Apply", false, 0x000000u32), itemb(0u32, 415.0, 378.0, 85.0, 25.0, "OK", true, 0x000000u32), itemb(0u32, 506.0, 378.0, 85.0, 25.0, "Cancel", false, 0x000000u32), none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none }
        f.count = 6usize
    }
    if i == 12usize {
        f.kx = 0.000769
        f.ky = 0.001099
        f.cx = 0.01
        f.cy = 0.00
        f.rkx = 0.000745
        f.rcx = -0.0027
        f.rky = 0.000748
        f.rcy = -0.0221
        f.title = "Deck Legality"
        f.width = 539.0
        f.height = 479.0
        f.tkind = 1u32
        f.bottom = true
        f.items = [24]Item{ itemb(0u32, 22.0, 448.0, 75.0, 23.0, "Help", false, 0x000000u32), itemb(3u32, 103.0, 451.0, 270.0, 17.0, "Last update on October 10, 2026", false, 0x000000u32), itemb(0u32, 460.0, 448.0, 75.0, 23.0, "Close", false, 0x000000u32), itemb(0u32, 446.0, 95.0, 75.0, 23.0, "P&easant", false, 0x000000u32), itemb(0u32, 365.0, 95.0, 75.0, 23.0, "&Brawl", false, 0x000000u32), itemb(0u32, 284.0, 95.0, 75.0, 23.0, "Comm &1v1", false, 0x000000u32), itemb(0u32, 203.0, 95.0, 75.0, 23.0, "&Commander", false, 0x000000u32), itemb(0u32, 122.0, 95.0, 75.0, 23.0, "&2HG", false, 0x000000u32), itemb(0u32, 41.0, 95.0, 75.0, 23.0, "&Pauper", false, 0x000000u32), itemb(0u32, 122.0, 66.0, 75.0, 23.0, "&Modern", false, 0x000000u32), itemb(0u32, 446.0, 66.0, 75.0, 23.0, "&All", false, 0x000000u32), itemb(0u32, 365.0, 66.0, 75.0, 23.0, "&Vintage", false, 0x000000u32), itemb(0u32, 284.0, 66.0, 75.0, 23.0, "&Legacy", false, 0x000000u32), itemb(0u32, 203.0, 66.0, 75.0, 23.0, "&Pioneer", false, 0x000000u32), itemb(0u32, 41.0, 66.0, 75.0, 23.0, "&Standard", false, 0x000000u32), none, none, none, none, none, none, none, none, none }
        f.count = 15usize
    }
    if i == 13usize {
        f.title = "Statistics"
        f.width = 941.0
        f.height = 501.0
        f.tkind = 0u32
        f.items = [24]Item{ itemb(0u32, 865.0, 471.0, 75.0, 23.0, "Close", true, 0x000000u32), none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none }
        f.count = 1usize
    }
    if i == 14usize {
        f.title = "Customization"
        f.width = 164.0
        f.height = 293.0
        f.tkind = 4u32
        f.bottom = true
        f.items = [24]Item{ none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none }
        f.count = 0usize
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
    options.minimizable = f.tkind == 2u32
    options.maximizable = f.tkind == 1u32 || f.tkind == 2u32
    options.light = f.tkind == 3u32
    options.tool = f.tkind == 4u32
    let base = u64(i + 1usize) * 100u64
    let (bar, bar_error) = navigation.title_bar(a, base, t, f.title, options, f.width)
    if bar_error != ok { ret (zero, bar_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, f.count * 2usize + 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = at(a, 0.0, 0.0, bar)
    var n = 1usize
    var k = 0usize
    while k < f.count {
        let it = f.items[k]
        let key = base + 10u64 + u64(k)
        if it.kind == 0u32 || it.kind == 4u32 || it.kind == 5u32 {
            var bo = control.button_options()
            if it.flag { bo.variant = .Default }
            bo.enabled = it.kind != 4u32
            bo.focused = it.kind == 5u32
            bo.width = it.w
            bo.height = it.h
            bo.shift_x = f.cx + it.x * f.kx
            bo.shift_y = f.cy + it.y * f.ky
            // the ring's exact phase (looks9): the buttons of the scaled forms only
            if f.rkx != 0.0 {
                bo.ring_x = f.rcx + it.x * f.rkx
                bo.ring_y = f.rcy + it.y * f.rky
            }
            let (b, b_error) = control.button(a, key, t, it.text, action, bo)
            if b_error != ok { ret (zero, b_error) }
            if it.bg != 0u32 {
                // the face of the page the button sits on, 4 px around it
                var back = control.sized_style(it.w + 8.0, it.h + 8.0)
                back.background = paint.Brush { Solid: style.hex(it.bg) }
                parts[n] = at(a, it.x - 8.0 - 4.0, it.y - 4.0, widget.box(0u64, back, zero))
                n += 1usize
            }
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
    let (win, win_error) = overlay.windows_window_with(a, t, f.width, f.height, parts[0usize..n], f.bottom)
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

// looks5: the other captured windows, in three sheets (the CPU backend cannot render a sheet of over about 3 million device
// pixels at 1.5x): Filter Card Pool, Advanced Filter and Conditional Formatting Rules Manager (dialog_more); Deck Legality
// and the Customization tool window (dialog_more2); Statistics (dialog_more3).
fn build_more(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (n, e) = build_set(a, t, cells, 9usize, 3usize, 692.0, 485.0)
    ret (n, e)
}

fn build_more2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    if t.tokens.profile != .Windows {
        let (card_count, card_error) = neper_card(a, t, cells)
        ret (card_count, card_error)
    }
    let (first, first_error) = build_set(a, t, cells, 12usize, 1usize, 539.0, 480.0)
    if first_error != ok { ret (0usize, first_error) }
    let (second, second_error) = build_set(a, t, cells[1usize..2usize], 14usize, 1usize, 539.0, 480.0)
    ret (first + second, second_error)
}

fn build_more3(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (n, e) = build_set(a, t, cells, 13usize, 1usize, 941.0, 501.0)
    ret (n, e)
}

// One process draws two sheets at most (every look and scale opens a CPU device and the process has 16 of them): no argument
// draws dialog and dialog_wide, `1` draws dialog_more and dialog_more2, `2` draws dialog_more3.
fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize && args[1usize][0usize] == 49u8 {
        let more = looks.Sheet { name: "dialog_more", cells: 3usize, columns: 1usize, cell_w: 692.0, cell_h: 485.0, ctx: zero, build: build_more }
        try looks.run_all(a, &more)
        let more2 = looks.Sheet { name: "dialog_more2", cells: 2usize, columns: 1usize, cell_w: 539.0, cell_h: 480.0, ctx: zero, build: build_more2 }
        ret looks.run_all(a, &more2)
    }
    if args.len > 1usize {
        let more3 = looks.Sheet { name: "dialog_more3", cells: 1usize, columns: 1usize, cell_w: 941.0, cell_h: 501.0, ctx: zero, build: build_more3 }
        ret looks.run_all(a, &more3)
    }
    let sheet = looks.Sheet { name: "dialog", cells: 6usize, columns: 3usize, cell_w: 440.0, cell_h: 548.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    let wide = looks.Sheet { name: "dialog_wide", cells: 2usize, columns: 1usize, cell_w: 714.0, cell_h: 488.0, ctx: zero, build: build_wide }
    ret looks.run_all(a, &wide)
}
