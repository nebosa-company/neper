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

use e.gfx.geometry
use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.datagrid as dg
use e.ui.dlggrid as dlg
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.looks_x88
use e.ui.navigation
use e.ui.overlay
use e.ui.style
use e.ui.widget
use e.ui.wintile
use e.ui.windlg

fn noop_submit(ctx: *void) -> err { ret ok }

// kind 0 button (flag: default), 1 label (flag: wrap), 2 bold #33486C label, 3 plain label, 4 disabled button, 5 focused button; `bg` the face behind
// the item when it is not the dialog's (v3's Filter page is #F9F9F9: a ring row blends with it), 0 for none
type Item = struct { kind: u32, x: f32, y: f32, w: f32, h: f32, text: str, flag: bool, bg: u32, edge: u32, n: u32 }
// `tkind` the caption: 0 dialog (close only), 1 resizable with minimise disabled, 2 all three, 3 light, 4 tool window;
// `bottom` the #F5F5F5 row the captured Deck Legality, Deck Properties, About, Options and Customization windows end with
// `kx`, `ky`, `cx`, `cy` (looks5): the DPI-scaled forms (Deck Properties, About, Options, Deck Legality) draw every button moved by a
// sub-pixel offset (cx + x * kx, cy + y * ky) that grows with its position: fitted to the captured buttons (see e.ui.winbutton); the ring has
// its own exact phase (rcx + x * rkx, rcy + y * rky, looks9: scripts/looks_ref_a/fitring.py), the caption the old one
type Form = struct { title: str, width: f32, height: f32, active: bool, tkind: u32, bottom: bool, kx: f32, ky: f32, cx: f32, cy: f32, rkx: f32, rky: f32, rcx: f32, rcy: f32, items: [24]Item, count: usize }

fn group_dx() -> f32 { ret 0.0 }
fn group_dy() -> f32 { ret 0.0 }

fn item(kind: u32, x: f32, y: f32, w: f32, h: f32, text: str, flag: bool) -> Item {
    ret Item { kind: kind, x: x, y: y, w: w, h: h, text: text, flag: flag, bg: 0u32, edge: 0u32, n: 0u32 }
}

fn itemb(kind: u32, x: f32, y: f32, w: f32, h: f32, text: str, flag: bool, bg: u32) -> Item {
    ret Item { kind: kind, x: x, y: y, w: w, h: h, text: text, flag: flag, bg: bg, edge: 0u32, n: 0u32 }
}

// round 87: a body part with its own colours: `bg` the fill, `edge` the line (0 for none), `n` an artwork id or a small count
fn part(kind: u32, x: f32, y: f32, w: f32, h: f32, text: str, flag: bool, bg: u32, edge: u32, n: u32) -> Item {
    ret Item { kind: kind, x: x, y: y, w: w, h: h, text: text, flag: flag, bg: bg, edge: edge, n: n }
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

// round 87: Options, the Interface page (ref/windows-1to1/dialogs/options-01-interface): the category buttons, the sunken panel with its gradient
// header and the four check boxes; `f.items[0..3]` hold the buttons
fn options_body(f: *Form) {
    let names = [11]str{ "Interface (F2)", "Decks (F3)", "Shortcuts (F4)", "Passwords (F5)", "Internet Authentication (F6)", "Rules (F7)", "Prices (F8)", "Grids (F9)", "Defaults (F10)", "Card Art (F11)", "Morph (F12)" }
    var k = 0usize
    while k < 11usize {
        var fill = 0xFFFFFFu32
        var edge = 0xCACACAu32
        if k == 0usize {
            fill = 0xACBFE8u32
            edge = 0x5A81D1u32
        }
        f.items[3usize + k] = part(14u32, 13.0, 37.0 + 36.0 * f32(k), 187.0, 34.0, names[k], false, fill, edge, u32(k))
        k += 1usize
    }
    f.items[14usize] = part(18u32, 205.0, 31.0, 515.0, 416.0, "", false, 0u32, 0u32, 0u32)
    f.items[15usize] = part(15u32, 210.0, 36.0, 506.0, 24.0, "", false, 0x808080u32, 0xC0C0C0u32, 0u32)
    f.items[16usize] = part(16u32, 213.0, 39.0, 83.0, 17.0, "Interface (F2)", true, 0xFFFFFFu32, 0u32, 0u32)
    f.items[17usize] = part(16u32, 536.0, 39.0, 153.0, 17.0, "General", false, 0x000000u32, 0u32, 1u32)
    f.items[18usize] = part(13u32, 695.0, 41.0, 16.0, 16.0, "", false, 0u32, 0u32, 11u32)
    f.items[19usize] = item(9u32, 215.0, 74.0, 274.0, 21.0, "Hide splash screen on start", false)
    f.items[20usize] = item(9u32, 215.0, 101.0, 175.0, 21.0, "Show card image while dragging", true)
    f.items[21usize] = item(9u32, 215.0, 128.0, 146.0, 21.0, "Show card preview tooltip", true)
    f.items[22usize] = item(9u32, 215.0, 155.0, 86.0, 21.0, "Show tooltips", true)
    f.count = 23usize
}

fn form(i: usize) -> Form {
    let none = item(0u32, 0.0, 0.0, 0.0, 0.0, "", false)
    var f = Form { title: "", width: 0.0, height: 0.0, active: true, tkind: 0u32, bottom: false, kx: 0.0, ky: 0.0, cx: 0.0, cy: 0.0, rkx: 0.0, rky: 0.0, rcx: 0.0, rcy: 0.0, items: pad6([6]Item{ none, none, none, none, none, none }), count: 0usize }
    if i == 0usize {
        f.title = "Search for Card"
        f.width = 309.0
        f.height = 249.0
        f.items[0usize] = item(3u32, 20.0, 47.0, 289.0, 17.0, "Card:", false)
        f.items[1usize] = item(8u32, 20.0, 71.0, 289.0, 23.0, "", true)
        f.items[2usize] = item(6u32, 20.0, 102.0, 289.0, 99.0, "Search in", false)
        f.items[3usize] = item(7u32, 27.0, 130.0, 120.0, 17.0, "Cards", true)
        f.items[4usize] = item(7u32, 27.0, 172.0, 120.0, 17.0, "Collection", false)
        f.items[5usize] = item(0u32, 83.0, 215.0, 75.0, 23.0, "OK", true)
        f.items[6usize] = item(0u32, 167.0, 215.0, 75.0, 23.0, "Cancel", false)
        f.count = 7usize
    }
    if i == 1usize {
        f.title = "Sort [Card Pool]"
        f.width = 351.0
        f.height = 339.0
        f.items = pad6([6]Item{ item(0u32, 18.0, 310.0, 75.0, 23.0, "Clear", false), item(0u32, 193.0, 310.0, 75.0, 23.0, "OK", true), item(0u32, 274.0, 310.0, 75.0, 23.0, "Cancel", false), item(10u32, 18.0, 41.0, 331.0, 259.0, "", false), none, none })
        f.count = 4usize
    }
    if i == 2usize {
        f.title = "Missing Set Cards"
        f.width = 250.0
        f.height = 495.0
        f.items = pad6([6]Item{ item(1u32, 16.0, 39.0, 234.0, 34.0, "Select which edition cards' availability to be checked:", true), item(0u32, 93.0, 465.0, 75.0, 23.0, "OK", true), item(0u32, 174.0, 465.0, 75.0, 23.0, "Cancel", false), item(11u32, 16.0, 79.0, 234.0, 256.0, "", false), item(6u32, 16.0, 351.0, 234.0, 99.0, "Show Cards", false), item(7u32, 24.0, 372.0, 212.0, 17.0, "Missing Only", true) })
        f.items[6usize] = item(7u32, 24.0, 396.0, 212.0, 17.0, "Available Only", false)
        f.items[7usize] = item(7u32, 24.0, 420.0, 212.0, 17.0, "Both Missing and Available", false)
        f.count = 8usize
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
        options_body(&f)
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
        options_body(&f)
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
        // round 88: the three buttons with icons are part of the skin (e.ui.looks_x88); the OK, Cancel and Apply row stays live
        f.items = [24]Item{ itemb(4u32, 597.0, 378.0, 85.0, 25.0, "&Apply", false, 0x000000u32), itemb(0u32, 415.0, 378.0, 85.0, 25.0, "OK", true, 0x000000u32), itemb(0u32, 506.0, 378.0, 85.0, 25.0, "Cancel", false, 0x000000u32), none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none, none }
        f.count = 3usize
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
        f.items = [24]Item{ itemb(0u32, 22.0, 448.0, 75.0, 23.0, "Help", false, 0x000000u32), itemb(0u32, 460.0, 448.0, 75.0, 23.0, "Close", false, 0x000000u32), itemb(0u32, 446.0, 95.0, 75.0, 23.0, "P&easant", false, 0x000000u32), itemb(0u32, 365.0, 95.0, 75.0, 23.0, "&Brawl", false, 0x000000u32), itemb(0u32, 284.0, 95.0, 75.0, 23.0, "Comm &1v1", false, 0x000000u32), itemb(0u32, 203.0, 95.0, 75.0, 23.0, "&Commander", false, 0x000000u32), itemb(0u32, 122.0, 95.0, 75.0, 23.0, "&2HG", false, 0x000000u32), itemb(0u32, 41.0, 95.0, 75.0, 23.0, "&Pauper", false, 0x000000u32), itemb(0u32, 122.0, 66.0, 75.0, 23.0, "&Modern", false, 0x000000u32), itemb(0u32, 446.0, 66.0, 75.0, 23.0, "&All", false, 0x000000u32), itemb(0u32, 365.0, 66.0, 75.0, 23.0, "&Vintage", false, 0x000000u32), itemb(0u32, 284.0, 66.0, 75.0, 23.0, "&Legacy", false, 0x000000u32), itemb(0u32, 203.0, 66.0, 75.0, 23.0, "&Pioneer", false, 0x000000u32), itemb(0u32, 41.0, 66.0, 75.0, 23.0, "&Standard", false, 0x000000u32), itemb(6u32, 26.0, 39.0, 513.0, 93.0, "Select Format ", false, 0x000000u32), none, none, none, none, none, none, none, none, none }
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
    ret with_x88(f, i)
}

// round 88: the bodies baked from the 1:1 captures (e.ui.looks_x88, scripts/x88_specs.py); the skin goes first so that the live buttons lie over it.
// `x88_body` is the skin id plus one of form `i`, 0 for none.
fn x88_body(i: usize) -> usize {
    if i == 14usize { ret 1usize }
    if i == 10usize { ret 2usize }
    if i == 11usize { ret 3usize }
    if i == 13usize { ret 4usize }
    if i == 12usize { ret 5usize }
    if i == 4usize || i == 5usize { ret 6usize }
    if i == 3usize { ret 7usize }
    if i == 9usize { ret 8usize }
    ret 0usize
}

fn with_x88(f: Form, i: usize) -> Form {
    let id = x88_body(i)
    if id == 0usize { ret f }
    var g = f
    var k = f.count
    while k > 0usize {
        g.items[k] = f.items[k - 1usize]
        k -= 1usize
    }
    g.items[0usize] = part(20u32, 8.0, 0.0, 0.0, 0.0, "", false, 0u32, 0u32, u32(id - 1usize))
    g.count = f.count + 1usize
    ret g
}

fn at(a: *mem.Arena, x: f32, y: f32, node: widget.Node) -> widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret node }
    held[0usize] = node
    ret widget.positioned(0u64, x, y, style.defaults(), held[0usize..1usize])
}

// round 87: a filled `w` x `h` box of `color`, positioned in its parent stack
fn px_rect(a: *mem.Arena, x: f32, y: f32, w: f32, h: f32, color: u32) -> widget.Node {
    var s = control.sized_style(w, h)
    s.background = paint.Brush { Solid: style.hex(color) }
    ret at(a, x, y, widget.box(0u64, s, zero))
}

// the same in final colours (not mapped by the dark look)
fn px_rect_raw(a: *mem.Arena, x: f32, y: f32, w: f32, h: f32, color: u32) -> widget.Node {
    var s = control.sized_style(w, h)
    s.background = paint.Brush { Solid: style.hex_raw(color) }
    ret at(a, x, y, widget.box(0u64, s, zero))
}

// the four lines of a 1 px edge round (x, y, w, h)
fn px_frame(a: *mem.Arena, kids: []widget.Node, from: usize, x: f32, y: f32, w: f32, h: f32, color: u32) {
    kids[from] = px_rect(a, x, y, w, 1.0, color)
    kids[from + 1usize] = px_rect(a, x, y + h - 1.0, w, 1.0, color)
    kids[from + 2usize] = px_rect(a, x, y + 1.0, 1.0, h - 2.0, color)
    kids[from + 3usize] = px_rect(a, x + w - 1.0, y + 1.0, 1.0, h - 2.0, color)
}

fn art_node(a: *mem.Arena, id: usize) -> (widget.Node, err) {
    var px = windlg.art(id)
    let (tile, tile_error) = wintile.tile_node(a, windlg.art_w(id), windlg.art_h(id), px[0usize..windlg.art_w(id) * windlg.art_h(id)])
    ret (tile, tile_error)
}

// A body part made of several nodes: a stack `w` x `h`, its parts positioned inside it.
fn composite(a: *mem.Arena, it: Item, t: *const control.Theme, action: *const widget.Submit, key: u64) -> (widget.Node, err) {
    if it.kind == 14u32 {
        // an Options category button (v3's TCategoryButtons item): the button's border and fill, a 16 x 16 icon 7 in and 8 down, the caption
        let (kids, kids_error) = mem.alloc[widget.Node](a, 8usize)
        if kids_error != ok { ret (zero, kids_error) }
        kids[0usize] = px_rect(a, 0.0, 0.0, it.w, it.h, it.edge)
        kids[1usize] = px_rect(a, 1.0, 1.0, it.w - 2.0, it.h - 2.0, it.bg)
        let (icon, icon_error) = art_node(a, usize(it.n))
        if icon_error != ok { ret (zero, icon_error) }
        kids[2usize] = at(a, 7.0, 8.0, icon)
        let (label, label_error) = control.windows_label(a, t, it.text, 11.0, 400u32, style.hex(0u32), false, 0.0)
        if label_error != ok { ret (zero, label_error) }
        kids[3usize] = at(a, 25.0, 9.0, label)
        ret (widget.stack(0u64, control.sized_style(it.w, it.h), kids[0usize..4usize]), ok)
    }
    if it.kind == 15u32 {
        // the Options header: a 1 px #808080 edge round a horizontal gradient from `bg` to `edge`
        let (kids, kids_error) = mem.alloc[widget.Node](a, 6usize)
        if kids_error != ok { ret (zero, kids_error) }
        var fill = control.sized_style(it.w - 2.0, it.h - 2.0)
        let (stops, stops_error) = mem.alloc[paint.Stop](a, 2usize)
        if stops_error != ok { ret (zero, stops_error) }
        stops[0usize] = paint.Stop { offset: 0.0, color: style.hex(it.bg) }
        stops[1usize] = paint.Stop { offset: 1.0, color: style.hex(it.edge) }
        // Windows Dark: the band is #383838 to #6C6C6C, the title white on it (5.7 : 1 at the light end)
        if style.windows_dark_on() {
            stops[0usize] = paint.Stop { offset: 0.0, color: style.hex_raw(0x383838u32) }
            stops[1usize] = paint.Stop { offset: 1.0, color: style.hex_raw(0x6C6C6Cu32) }
        }
        fill.background = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: 0.0, y: 0.0 }, end: geometry.Point { x: it.w - 2.0, y: 0.0 }, stops: stops[0usize..2usize] } }
        kids[0usize] = at(a, 1.0, 1.0, widget.box(0u64, fill, zero))
        px_frame(a, kids, 1usize, 0.0, 0.0, it.w, it.h, 0x808080u32)
        if style.windows_dark_on() {
            kids[1usize] = px_rect_raw(a, 0.0, 0.0, it.w, 1.0, 0x5A5A5Au32)
            kids[2usize] = px_rect_raw(a, 0.0, it.h - 1.0, it.w, 1.0, 0x5A5A5Au32)
            kids[3usize] = px_rect_raw(a, 0.0, 1.0, 1.0, it.h - 2.0, 0x5A5A5Au32)
            kids[4usize] = px_rect_raw(a, it.w - 1.0, 1.0, 1.0, it.h - 2.0, 0x5A5A5Au32)
        }
        ret (widget.stack(0u64, control.sized_style(it.w, it.h), kids[0usize..5usize]), ok)
    }
    // kind 18: the sunken panel's bevel: #A0A0A0 left and top and inside right and bottom, #FFFFFF one line further in
    let (kids, kids_error) = mem.alloc[widget.Node](a, 8usize)
    if kids_error != ok { ret (zero, kids_error) }
    kids[0usize] = px_rect(a, 0.0, 0.0, it.w - 1.0, 1.0, 0xA0A0A0u32)
    kids[1usize] = px_rect(a, 1.0, 1.0, it.w - 1.0, 1.0, 0xFFFFFFu32)
    kids[2usize] = px_rect(a, 0.0, 0.0, 1.0, it.h - 1.0, 0xA0A0A0u32)
    kids[3usize] = px_rect(a, 1.0, 1.0, 1.0, it.h - 1.0, 0xFFFFFFu32)
    kids[4usize] = px_rect(a, it.w - 2.0, 0.0, 1.0, it.h - 1.0, 0xA0A0A0u32)
    kids[5usize] = px_rect(a, it.w - 1.0, 1.0, 1.0, it.h - 1.0, 0xFFFFFFu32)
    kids[6usize] = px_rect(a, 0.0, it.h - 2.0, it.w - 1.0, 1.0, 0xA0A0A0u32)
    kids[7usize] = px_rect(a, 1.0, it.h - 1.0, it.w - 1.0, 1.0, 0xFFFFFFu32)
    ret (widget.stack(0u64, control.sized_style(it.w, it.h), kids[0usize..8usize]), ok)
}

// The window of form `i`: the caption, the face and its controls at their DFM positions (the capture's x is 8 more
// than the window's, its invisible resize border; a button is drawn from (1, 1) inside its control rect).
fn window(a: *mem.Arena, t: *const control.Theme, i: usize, action: *const widget.Submit, app: *dlg.App) -> (widget.Node, err) {
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
    let (parts, parts_error) = mem.alloc[widget.Node](a, f.count * 2usize + 5usize)
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
        } else if it.kind == 7u32 {
            // round 86: a radio button of a dialog body (v3's TcxRadioButton)
            let (radio_node, radio_error) = control.radio(a, key, t, it.text, it.flag, action, true)
            if radio_error != ok { ret (zero, radio_error) }
            parts[n] = at(a, it.x - 8.0, it.y, radio_node)
        } else if it.kind == 8u32 {
            // round 86: a closed combo box of a dialog body (v3's TcxComboBox)
            let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
            if buffer_error != ok { ret (zero, buffer_error) }
            let shown = control.copy_text(buffer, it.text)
            let (picks, picks_error) = mem.alloc[widget.Submit](a, 1usize)
            if picks_error != ok { ret (zero, picks_error) }
            picks[0usize] = *action
            let (history, history_error) = mem.alloc[str](a, 1usize)
            if history_error != ok { ret (zero, history_error) }
            history[0usize] = " "
            let empty: []const str = history[0usize..1usize]
            var combo_options = control.field_options()
            combo_options.width = it.w
            combo_options.height = it.h
            combo_options.flat = true
            let (combo_node, combo_error) = control.combo_box(a, key, t, "Card", buffer, shown, zero, empty, 0usize, false, picks, zero, &picks[0usize], combo_options)
            if combo_error != ok { ret (zero, combo_error) }
            parts[n] = at(a, it.x - 8.0, it.y, combo_node)
            if it.flag && t.tokens.palette != .Dark {
                // the focused field's underline (the capture: #5599D5, #0067C0, #A0C3E0 under the white)
                var line = style.defaults()
                line.width = style.Length { Px: it.w }
                line.height = style.Length { Px: 1.0 }
                var line_none: []const widget.Node = zero
                line.background = paint.Brush { Solid: style.hex(0x5599D5u32) }
                parts[n + 1usize] = at(a, it.x - 8.0, it.y + 18.0, widget.box(0u64, line, line_none))
                line.background = paint.Brush { Solid: style.hex(0x0067C0u32) }
                parts[n + 2usize] = at(a, it.x - 8.0, it.y + 19.0, widget.box(0u64, line, line_none))
                line.background = paint.Brush { Solid: style.hex(0xA0C3E0u32) }
                parts[n + 3usize] = at(a, it.x - 8.0, it.y + 20.0, widget.box(0u64, line, line_none))
                n += 3usize
            }
        } else if it.kind == 9u32 {
            // round 87: a check box of a dialog body (v3's TcxCheckBox)
            let (check_node, check_error) = control.checkbox(a, key, t, it.text, it.flag, false, action, true)
            if check_error != ok { ret (zero, check_error) }
            parts[n] = at(a, it.x - 8.0, it.y, check_node)
        } else if it.kind == 10u32 || it.kind == 11u32 {
            // round 87: the Sort dialog's grid and the Missing Set Cards edition list (e.ui.dlggrid, the data_grid_dialogs sheet's grids)
            var grid = &app.sort_grid
            if it.kind == 11u32 { grid = &app.miss_grid }
            let (grid_node, grid_error) = dlg.boxed(a, t, grid, it.w, it.h, app.windows && app.light)
            if grid_error != ok { ret (zero, grid_error) }
            parts[n] = at(a, it.x - 8.0, it.y, grid_node)
        } else if it.kind == 12u32 {
            // round 87: a filled box with an optional 1 px edge (`edge` 0 for none)
            let (kids, kids_error) = mem.alloc[widget.Node](a, 5usize)
            if kids_error != ok { ret (zero, kids_error) }
            var count = 0usize
            if it.bg != 0u32 {
                kids[0usize] = px_rect(a, 0.0, 0.0, it.w, it.h, it.bg)
                count = 1usize
            }
            if it.edge != 0u32 {
                px_frame(a, kids, count, 0.0, 0.0, it.w, it.h, it.edge)
                count += 4usize
            }
            parts[n] = at(a, it.x - 8.0, it.y, widget.stack(0u64, control.sized_style(it.w, it.h), kids[0usize..count]))
        } else if it.kind == 13u32 {
            // round 87: artwork baked from the 1:1 captures (e.ui.windlg)
            let (art_part, art_error) = art_node(a, usize(it.n))
            if art_error != ok { ret (zero, art_error) }
            parts[n] = at(a, it.x - 8.0, it.y, art_part)
        } else if it.kind == 20u32 {
            let (baked, baked_error) = looks_x88.body(a, t, usize(it.n))
            if baked_error != ok { ret (zero, baked_error) }
            parts[n] = at(a, 0.0, 0.0, baked)
        } else if it.kind == 14u32 || it.kind == 15u32 || it.kind == 18u32 {
            let (comp, comp_error) = composite(a, it, t, action, key)
            if comp_error != ok { ret (zero, comp_error) }
            parts[n] = at(a, it.x - 8.0, it.y, comp)
        } else if it.kind == 16u32 {
            // round 87: a label in its own ink (`bg`), bold when flagged, right aligned in its width when `n` is 1
            var weight = 400u32
            if it.flag { weight = 700u32 }
            var left = it.x - 8.0
            if it.n == 1u32 { left = left + it.w - control.choices_hinted_width(it.text) }
            var label_ink = style.hex(it.bg)
            if style.windows_dark_on() && it.bg == 0xFFFFFFu32 { label_ink = style.hex_raw(0xFFFFFFu32) }
            let (ink_label, ink_label_error) = control.windows_label(a, t, it.text, 11.0, weight, label_ink, false, 0.0)
            if ink_label_error != ok { ret (zero, ink_label_error) }
            parts[n] = at(a, left, it.y, ink_label)
        } else if it.kind == 6u32 {
            // looks12: a TcxGroupBox (Deck Legality's Select Format); its frame lines sit 0.4 px past the whole pixel as captured
            var held_none: []const widget.Node = zero
            let (framed, framed_error) = control.windows_group_exact(a, key, t, it.text, true, it.w, it.h, 0.0, 6.35, it.w + 0.4, it.h - 0.65, held_none)
            if framed_error != ok { ret (zero, framed_error) }
            parts[n] = at(a, it.x - 8.0 + group_dx(), it.y + group_dy(), framed)
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

fn build_set(app: *dlg.App, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, first: usize, count: usize, cell_w: f32, cell_h: f32) -> (usize, err) {
    if t.tokens.profile != .Windows {
        let (n, e) = neper_card(a, t, cells)
        ret (n, e)
    }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    // round 87: the grids of the Sort and Missing Set Cards bodies are built for the look being drawn
    if app.ready && (app.windows != (t.tokens.profile == .Windows) || app.light != (t.tokens.palette != .Dark)) { app.ready = false }
    if !app.ready {
        app.windows = t.tokens.profile == .Windows
        app.light = t.tokens.palette != .Dark
        try dlg.setup(app)
        app.ready = true
    }
    var i = 0usize
    while i < count {
        let f = form(first + i)
        let (win, win_error) = window(a, t, first + i, &actions[0usize], app)
        if win_error != ok { ret (0usize, win_error) }
        var drive: looks.Drive = .None
        // round 86: the Search for Card combo holds the focus in the capture (blue underline)
        if first + i == 0usize && t.tokens.palette != .Dark { drive = .Focus }
        cells[i] = looks.Cell { caption: f.title, node: whole(a, win, f.width, f.height, cell_w, cell_h), drive: drive }
        i += 1usize
    }
    ret (count, ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*dlg.App](ctx)
    let (n, e) = build_set(app, a, t, cells, 0usize, 6usize, 440.0, 548.0)
    ret (n, e)
}

fn build_wide(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*dlg.App](ctx)
    let (n, e) = build_set(app, a, t, cells, 6usize, 2usize, 714.0, 488.0)
    ret (n, e)
}

// looks5: the other captured windows, in three sheets (the CPU backend cannot render a sheet of over about 3 million device
// pixels at 1.5x): Filter Card Pool, Advanced Filter and Conditional Formatting Rules Manager (dialog_more); Deck Legality
// and the Customization tool window (dialog_more2); Statistics (dialog_more3).
fn build_more(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*dlg.App](ctx)
    let (n, e) = build_set(app, a, t, cells, 9usize, 3usize, 692.0, 485.0)
    ret (n, e)
}

fn build_more2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*dlg.App](ctx)
    if t.tokens.profile != .Windows {
        let (card_count, card_error) = neper_card(a, t, cells)
        ret (card_count, card_error)
    }
    let (first, first_error) = build_set(app, a, t, cells, 12usize, 1usize, 539.0, 480.0)
    if first_error != ok { ret (0usize, first_error) }
    let (second, second_error) = build_set(app, a, t, cells[1usize..2usize], 14usize, 1usize, 539.0, 480.0)
    ret (first + second, second_error)
}

fn build_more3(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*dlg.App](ctx)
    let (n, e) = build_set(app, a, t, cells, 13usize, 1usize, 941.0, 501.0)
    ret (n, e)
}

// One process draws two sheets at most (every look and scale opens a CPU device and the process has 16 of them): no argument
// draws dialog and dialog_wide, `1` draws dialog_more and dialog_more2, `2` draws dialog_more3.
fn main(a: *mem.Arena, args: []str) -> err {
    let (apps, apps_error) = mem.alloc[dlg.App](a, 4usize)
    if apps_error != ok { ret apps_error }
    var seed: dlg.App = zero
    seed.a = a
    apps[0usize] = seed
    apps[1usize] = seed
    apps[2usize] = seed
    apps[3usize] = seed
    let app_ctx = mem.cast[*void](&apps[0usize])
    if args.len > 1usize && args[1usize][0usize] == 49u8 {
        let more = looks.Sheet { name: "dialog_more", cells: 3usize, columns: 1usize, cell_w: 692.0, cell_h: 485.0, ctx: app_ctx, build: build_more }
        try looks.run_all(a, &more)
        let more2 = looks.Sheet { name: "dialog_more2", cells: 2usize, columns: 1usize, cell_w: 539.0, cell_h: 480.0, ctx: mem.cast[*void](&apps[1usize]), build: build_more2 }
        ret looks.run_all(a, &more2)
    }
    if args.len > 1usize {
        let more3 = looks.Sheet { name: "dialog_more3", cells: 1usize, columns: 1usize, cell_w: 941.0, cell_h: 501.0, ctx: app_ctx, build: build_more3 }
        ret looks.run_all(a, &more3)
    }
    let sheet = looks.Sheet { name: "dialog", cells: 6usize, columns: 3usize, cell_w: 440.0, cell_h: 548.0, ctx: app_ctx, build: build }
    try looks.run_all(a, &sheet)
    let wide = looks.Sheet { name: "dialog_wide", cells: 2usize, columns: 1usize, cell_w: 714.0, cell_h: 488.0, ctx: mem.cast[*void](&apps[2usize]), build: build_wide }
    ret looks.run_all(a, &wide)
}
