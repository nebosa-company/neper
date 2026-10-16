// The page control (TcxPageControl tabs) in every state under every look:
// docs/ui/looks/<look>/page_control.png. Run from the repository root.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// A page: the dialog face with a frame, standing for the tab sheet.
fn page() -> widget.Node {
    var s = style.defaults()
    s.height = style.Length { Px: 60.0 }
    ret widget.box(0u64, s, zero)
}

// Six cells: the tab bar with the second tab selected, with the pointer over an unselected tab,
// pressed on it, keyboard-focused, with a disabled tab and the last selected, and the tab view
// (bar over a page). The harness holds 128 element states, which caps a sheet at about six bars.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 4usize)
    if actions_error != ok { ret (0usize, actions_error) }
    var k = 0usize
    while k < 4usize {
        actions[k] = widget.Submit { ctx: zero, invoke: noop_submit }
        k += 1usize
    }
    let labels = [4]str{ "Colors", "Rarity", "Card Type", "Editions" }
    let (off, off_error) = mem.alloc[bool](a, 4usize)
    if off_error != ok { ret (0usize, off_error) }
    off[0usize] = false
    off[1usize] = false
    off[2usize] = true
    off[3usize] = false
    let captions = [6]str{ "Rest", "Hover", "Pressed", "Focus", "Disabled, last selected", "Tab view" }
    var i = 0usize
    while i < 6usize {
        var options = control.tabs_options()
        options.width = 300.0
        var selected = 1usize
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        if i == 1usize || i == 2usize || i == 3usize { selected = 0usize }
        if i == 4usize {
            options.disabled = off[0usize..4usize]
            selected = 3usize
        }
        
        
        
        let key = u64(1000usize * (i + 1usize))
        var bar: widget.Node = zero
        if i == 5usize {
            let (pages, pages_error) = mem.alloc[widget.Node](a, 4usize)
            if pages_error != ok { ret (0usize, pages_error) }
            k = 0usize
            while k < 4usize {
                pages[k] = page()
                k += 1usize
            }
            let (view, view_error) = control.tab_view(a, key, t, labels[0usize..4usize], 1usize, actions[0usize..4usize], pages[0usize..4usize])
            if view_error != ok { ret (0usize, view_error) }
            bar = view
        } else {
            let (made, bar_error) = control.tabs_of(a, key, t, labels[0usize..4usize], selected, actions[0usize..4usize], options)
            if bar_error != ok { ret (0usize, bar_error) }
            bar = made
        }
        cells[i] = looks.Cell { caption: captions[i], node: bar, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

// The native tab strips of v3's lfOffice11 page controls (ref/windows/dialogs): the Filter window's
// (Blocks / Formats / Editions chosen and focused, then Cards and Options) and the Customization window's
// (Bands, Columns chosen). One strip per cell at (0, 0); the cells are as large as the captures' crops.
// `page_control.exe filter` and `page_control.exe custom` write page_control_filter.png and
// page_control_custom.png, which compare pixel for pixel with ref/windows/page_control_*.png
// (scripts/looks_refs_d.py).
fn build_native(a: *mem.Arena, cells: []looks.Cell, t: *const control.Theme, labels: []const str, selected: usize, width: f32, drive: looks.Drive, high: f32, cell_wide: f32) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, labels.len)
    if actions_error != ok { ret (0usize, actions_error) }
    var k = 0usize
    while k < labels.len {
        actions[k] = widget.Submit { ctx: zero, invoke: noop_submit }
        k += 1usize
    }
    var options = control.tabs_options()
    options.native = true
    options.width = width
    let (bar, bar_error) = control.tabs_of(a, 1000u64, t, labels, selected, actions[0usize..labels.len], options)
    if bar_error != ok { ret (0usize, bar_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = bar
    parts[1usize] = widget.spacer(0u64, 0.0)
    var column = looks.size_style(cell_wide, high)
    cells[0usize] = looks.Cell { caption: "", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..1usize]), drive: drive }
    ret (1usize, ok)
}

fn build_filter(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let labels = [3]str{ "Blocks / Formats / Editions", "Cards", "Options" }
    let (made, made_error) = build_native(a, cells, t, labels[0usize..3usize], 0usize, 229.0, .Focus, 22.0, 229.0)
    ret (made, made_error)
}

fn build_custom(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let labels = [2]str{ "Bands", "Columns" }
    let (made, made_error) = build_native(a, cells, t, labels[0usize..2usize], 1usize, 96.0, .None, 22.0, 96.0)
    ret (made, made_error)
}

// The ultra-flat tab strips (lfUltraFlat, NativeStyle = False) of the Statistics window (a picture before
// every tab, Colors chosen and focused) and the About window (two tabs, MTG Studio chosen): one strip
// per cell at (0, 0). `page_control.exe stats` and `page_control.exe about` write page_control_stats.png
// and page_control_about.png (compared with ref/windows/page_control_*.png). The pictures are v3's
// bitmaps; a drawn glyph stands in.
fn build_ultra(a: *mem.Arena, cells: []looks.Cell, t: *const control.Theme, labels: []const str, width: f32, pictures: bool, drive: looks.Drive) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, labels.len)
    if actions_error != ok { ret (0usize, actions_error) }
    var k = 0usize
    while k < labels.len {
        actions[k] = widget.Submit { ctx: zero, invoke: noop_submit }
        k += 1usize
    }
    let glyphs = [3]control.GlyphKind{ .Picture, .Picture, .Picture }
    var options = control.tabs_options()
    options.width = width
    if pictures { options.icons = glyphs[0usize..labels.len] }
    let (bar, bar_error) = control.tabs_of(a, 1000u64, t, labels, 0usize, actions[0usize..labels.len], options)
    if bar_error != ok { ret (0usize, bar_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = bar
    var column = looks.size_style(width, 24.0)
    cells[0usize] = looks.Cell { caption: "", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..1usize]), drive: drive }
    ret (1usize, ok)
}

fn build_stats(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let labels = [2]str{ "Colors", "Rarity" }
    let (made, made_error) = build_ultra(a, cells, t, labels[0usize..2usize], 126.0, true, .Focus)
    ret (made, made_error)
}

fn build_about(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let labels = [2]str{ "MTG Studio", "Details" }
    let (made, made_error) = build_ultra(a, cells, t, labels[0usize..2usize], 120.0, false, .None)
    ret (made, made_error)
}

// The Statistics window's eleven tabs (v3 bitmaps stand in as drawn pictures), tab `n` (1 to 11) chosen and
// not focused, as ref/windows/states/tab-selected-statistics-<n>. `page_control.exe t<n>` writes
// page_control_stats_<n>.png; t12 and t13 the Filter tabs with Cards or Options chosen, t14 the
// Customization tabs with Bands held down (the press selects at once, so it is the Bands-chosen strip).
fn build_stat_n(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, n: usize) -> (usize, err) {
    let labels = [11]str{ "Colors", "Rarity", "Card Type", "Editions", "Mana Analyser", "Mana Product", "Power Analyser", "Probability", "Mana Slots", "Start Hand", "Advanced" }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 11usize)
    if actions_error != ok { ret (0usize, actions_error) }
    var k = 0usize
    while k < 11usize {
        actions[k] = widget.Submit { ctx: zero, invoke: noop_submit }
        k += 1usize
    }
    let glyphs = [11]control.GlyphKind{ .Picture, .Picture, .Picture, .Picture, .Picture, .Picture, .Picture, .Picture, .Picture, .Picture, .Picture }
    var options = control.tabs_options()
    options.width = 905.0
    options.icons = glyphs[0usize..11usize]
    let (bar, bar_error) = control.tabs_of(a, 1000u64, t, labels[0usize..11usize], n - 1usize, actions[0usize..11usize], options)
    if bar_error != ok { ret (0usize, bar_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = bar
    let column = looks.size_style(905.0, 24.0)
    cells[0usize] = looks.Cell { caption: "", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..1usize]), drive: .None }
    ret (1usize, ok)
}

fn build_t1(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 1usize)
    ret (m, e)
}

fn build_t2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 2usize)
    ret (m, e)
}

fn build_t3(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 3usize)
    ret (m, e)
}

fn build_t4(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 4usize)
    ret (m, e)
}

fn build_t5(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 5usize)
    ret (m, e)
}

fn build_t6(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 6usize)
    ret (m, e)
}

fn build_t7(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 7usize)
    ret (m, e)
}

fn build_t8(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 8usize)
    ret (m, e)
}

fn build_t9(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 9usize)
    ret (m, e)
}

fn build_t10(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 10usize)
    ret (m, e)
}

fn build_t11(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_stat_n(a, t, cells, 11usize)
    ret (m, e)
}

fn build_p2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let labels = [3]str{ "Blocks / Formats / Editions", "Cards", "Options" }
    let (made, made_error) = build_native(a, cells, t, labels[0usize..3usize], 1usize, 229.0, .Focus, 22.0, 318.0)
    ret (made, made_error)
}

fn build_p3(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let labels = [3]str{ "Blocks / Formats / Editions", "Cards", "Options" }
    let (made, made_error) = build_native(a, cells, t, labels[0usize..3usize], 2usize, 229.0, .Focus, 22.0, 407.0)
    ret (made, made_error)
}

fn build_p4(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let labels = [2]str{ "Bands", "Columns" }
    let (made, made_error) = build_native(a, cells, t, labels[0usize..2usize], 0usize, 96.0, .None, 22.0, 96.0)
    ret (made, made_error)
}

fn run_tab(a: *mem.Arena, which: usize) -> err {
    if which == 12usize {
        let sheet = looks.Sheet { name: "page_control_cards", cells: 1usize, columns: 1usize, cell_w: 318.0, cell_h: 22.0, ctx: zero, build: build_p2 }
        ret looks.run_all(a, &sheet)
    }
    if which == 13usize {
        let sheet = looks.Sheet { name: "page_control_options", cells: 1usize, columns: 1usize, cell_w: 407.0, cell_h: 22.0, ctx: zero, build: build_p3 }
        ret looks.run_all(a, &sheet)
    }
    if which == 14usize {
        let sheet = looks.Sheet { name: "page_control_held", cells: 1usize, columns: 1usize, cell_w: 96.0, cell_h: 22.0, ctx: zero, build: build_p4 }
        ret looks.run_all(a, &sheet)
    }
    var maker: looks.Build = build_t1
    var name = "page_control_stats_1"
    if which == 1usize { maker = build_t1
        name = "page_control_stats_1" }
    if which == 2usize { maker = build_t2
        name = "page_control_stats_2" }
    if which == 3usize { maker = build_t3
        name = "page_control_stats_3" }
    if which == 4usize { maker = build_t4
        name = "page_control_stats_4" }
    if which == 5usize { maker = build_t5
        name = "page_control_stats_5" }
    if which == 6usize { maker = build_t6
        name = "page_control_stats_6" }
    if which == 7usize { maker = build_t7
        name = "page_control_stats_7" }
    if which == 8usize { maker = build_t8
        name = "page_control_stats_8" }
    if which == 9usize { maker = build_t9
        name = "page_control_stats_9" }
    if which == 10usize { maker = build_t10
        name = "page_control_stats_10" }
    if which == 11usize { maker = build_t11
        name = "page_control_stats_11" }
    let sheet = looks.Sheet { name: name, cells: 1usize, columns: 1usize, cell_w: 905.0, cell_h: 24.0, ctx: zero, build: maker }
    ret looks.run_all(a, &sheet)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize && args[1usize][0usize] == 116u8 {
        var which = usize(args[1usize][1usize]) - 48usize
        if args[1usize].len > 2usize { which = which * 10usize + usize(args[1usize][2usize]) - 48usize }
        ret run_tab(a, which)
    }
    if args.len == 2usize {
        let first_byte = args[1usize][0usize]
        if first_byte == 115u8 {
            let stats = looks.Sheet { name: "page_control_stats", cells: 1usize, columns: 1usize, cell_w: 126.0, cell_h: 24.0, ctx: zero, build: build_stats }
            ret looks.run_all(a, &stats)
        }
        if first_byte == 97u8 {
            let about = looks.Sheet { name: "page_control_about", cells: 1usize, columns: 1usize, cell_w: 120.0, cell_h: 24.0, ctx: zero, build: build_about }
            ret looks.run_all(a, &about)
        }
    }
    if args.len == 2usize {
        let first = args[1usize][0usize]
        if first == 102u8 {
            let filter = looks.Sheet { name: "page_control_filter", cells: 1usize, columns: 1usize, cell_w: 229.0, cell_h: 22.0, ctx: zero, build: build_filter }
            ret looks.run_all(a, &filter)
        }
        if first == 99u8 {
            let custom = looks.Sheet { name: "page_control_custom", cells: 1usize, columns: 1usize, cell_w: 96.0, cell_h: 22.0, ctx: zero, build: build_custom }
            ret looks.run_all(a, &custom)
        }
    }
    if args.len == 2usize && args[1usize][0usize] == 98u8 {
        // `b1`, `b2`: the v3 main window's card strip at (8, 546), 282 x 29, the first or the second tab chosen.
        var maker: looks.Build = build_b1
        var name = "page_control_bottom"
        if args[1usize].len > 1usize && args[1usize][1usize] == 50u8 {
            maker = build_b2
            name = "page_control_bottom2"
        }
        var strip = looks.Sheet { name: name, cells: 1usize, columns: 1usize, cell_w: 282.0, cell_h: 29.0, ctx: zero, build: maker }
        if name.len > 19usize {
            strip.cell_w = 192.0
            strip.cell_h = 23.0
        }
        ret looks.run_all(a, &strip)
    }
    if args.len > 1usize {
        let bottom = looks.Sheet { name: "page_control_bottom_states", cells: 4usize, columns: 2usize, cell_w: 300.0, cell_h: 60.0, ctx: zero, build: build_bottom }
        ret looks.run_all(a, &bottom)
    }
    let sheet = looks.Sheet { name: "page_control", cells: 6usize, columns: 3usize, cell_w: 310.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}

// The card info strip of the v3 main window (tpBottom, two picture tabs, no captions) as the
// live capture ref/windows/page_control_bottom.png shows it: the preview tab chosen, the other
// chosen, the pointer over the unchosen one, and a strip with captions (the decks strip).
// v3's pictures are bitmaps; glyphs stand in.
fn build_bottom(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 3usize)
    if actions_error != ok { ret (0usize, actions_error) }
    var k = 0usize
    while k < 3usize {
        actions[k] = widget.Submit { ctx: zero, invoke: noop_submit }
        k += 1usize
    }
    let pictures = [3]control.GlyphKind{ .Picture, .Calendar, .Search }
    let blank = [3]str{ "", "", "" }
    let named = [3]str{ "Deck", "Collection", "Notes" }
    let captions = [4]str{ "Preview chosen", "Prices chosen", "Hover", "With captions" }
    var i = 0usize
    while i < 4usize {
        var options = control.tabs_options()
        options.bottom = true
        options.width = 280.0
        var selected = 0usize
        var drive: looks.Drive = .None
        if i == 1usize { selected = 1usize }
        if i == 2usize { drive = .Hover }
        var labels = blank[0usize..2usize]
        if i == 3usize { labels = named[0usize..3usize] }
        if i != 3usize { options.icons = pictures[0usize..2usize] }
        let (bar, bar_error) = control.tabs_of(a, u64(1000usize * (i + 1usize)), t, labels, selected, actions[0usize..labels.len], options)
        if bar_error != ok { ret (0usize, bar_error) }
        cells[i] = looks.Cell { caption: captions[i], node: bar, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn build_bottom_one(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, selected: usize, framed: bool) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    actions[1usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let pictures = [2]control.GlyphKind{ .Picture, .Calendar }
    let blank = [2]str{ "", "" }
    var options = control.tabs_options()
    options.bottom = true
    options.width = 280.0
    if !framed { options.width = 192.0 }
    options.icons = pictures[0usize..2usize]
    let (bar, bar_error) = control.tabs_of(a, 1000u64, t, blank[0usize..2usize], selected, actions[0usize..2usize], options)
    if bar_error != ok { ret (0usize, bar_error) }
    // The rows round the strip in the capture belong to the neighbouring grid frame: three above, three below.
    let (parts, parts_error) = mem.alloc[widget.Node](a, 8usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = rule(0.0, 0.0, 1.0, 12763842u32)
    parts[1usize] = rule(1.0, 0.0, 277.0, 14934492u32)
    parts[2usize] = rule(0.0, 1.0, 280.0, 16448250u32)
    parts[3usize] = rule(0.0, 26.0, 280.0, 16448250u32)
    parts[4usize] = rule(0.0, 28.0, 280.0, 13948116u32)
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (0usize, held_error) }
    held[0usize] = bar
    parts[5usize] = widget.positioned(0u64, 0.0, 3.0, style.defaults(), held[0usize..1usize])
    if !framed {
        // The second tab chosen, as captured: only the strip's own rows (the data navigator stands at its right).
        cells[0usize] = looks.Cell { caption: "", node: widget.positioned(0u64, 0.0, 0.0, looks.size_style(192.0, 23.0), held[0usize..1usize]), drive: .None }
        ret (1usize, ok)
    }
    var strip = looks.size_style(282.0, 29.0)
    strip.background = paint.Brush { Solid: style.hex(15790320u32) }
    cells[0usize] = looks.Cell { caption: "", node: widget.stack(0u64, strip, parts[0usize..6usize]), drive: .None }
    ret (1usize, ok)
}

fn rule(x: f32, y: f32, w: f32, rgb: u32) -> widget.Node {
    var line = looks.size_style(w, 1.0)
    line.background = paint.Brush { Solid: style.hex(rgb) }
    ret widget.positioned(0u64, x, y, line, zero)
}

fn build_b1(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_bottom_one(a, t, cells, 0usize, true)
    ret (m, e)
}

fn build_b2(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (m, e) = build_bottom_one(a, t, cells, 1usize, false)
    ret (m, e)
}
