// The look of the data grid as measured from MTG Studio v3 (docs/grid-parity/tokens.json):
// metrics in logical pixels (physical at 100 % DPI) and colours. `e.ui.datagrid` reads one
// `Look` through `set_look`; `e.ui.collection` draws a table with its `TableLook` part. Both
// are plain data: a different application look is another `Look`, not another widget.
//
// Measured at 150 % DPI from mtgstudio.exe 3.234 (the recordings are in docs/grid-parity):
// a row is 28.5 physical px (19), the header 32 (21), rows alternate #FFFFFF / #EFEFEF with no
// line between them, the selected row is #A6D2FF with a 1 px #83878B edge, a group row is
// #F0F0F0, the footer a #FFFFDD band with #E7EAEA summary cells, the frame #828790.
//
// ponytail: only what the recordings give is here; hover and pressed rows, the focus
// rectangle and unfocused-window selection colours wait for their recordings.

use e.fs
use e.io
use e.mem
use e.str
use e.fmt.png as png
use e.gfx.image
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.winpx
use e.ui.widget

type Look = struct {
    on: bool,
    row_height: f32,
    header_height: f32,
    pad: f32,
    text_size: f32,
    header: paint.Color,
    header_hover: paint.Color,
    header_line: paint.Color,
    even: paint.Color,
    odd: paint.Color,
    selected: paint.Color,
    selected_line: paint.Color,
    line: paint.Color,
    group_row: paint.Color,
    footer_band: paint.Color,
    footer_cell: paint.Color,
    frame: paint.Color,
    track: paint.Color,
    thumb: paint.Color,
    scroll_width: f32,
    // looks2-grid2 (live 100 % capture, docs/ui/looks/ref/windows/main-window@1x.png): a group row's
    // label starts in the first column after the indicator, and carries no "(Count: n)"
    group_flat: bool,
    // looks4-e: no frame of its own (a dialog draws the grid's frame round it)
    frame_none: bool,
    // looks5-e: a dialog grid's lines (one crisp column line, its own row-foot pixels)
    dialog_lines: bool,
    // looks5-e: the two pixels at the foot of a grey and of a white row, when set
    foot_set: bool,
    // looks5-e: the foot pixels drift with the row's place down the grid (levels per 100 px, 1.0 as measured on the Shortcuts and top grids)
    foot_drift: f32,
    // looks5-e: a grid without the focus paints its selected row in this fill and edge (the Options grids), else as focused
    // looks5-e: a group row carries "(Count: n)" (the View > Group by captures; the main window's Rarity groups do not)
    group_counts: bool,
    // round 12: the group row focus rectangle drawn over the whole row (the pool grid of the main window shows no counts)
    group_rect: bool,
    // round 12: the current group row's focus rectangle is the solid one of the pointer states (hover grabs), not the dotted one
    group_solid: bool,
    // round 13: the vertical bar's track starts this far above the header (the main window's pool grid: over its group box) and its thumb is this long (0 = from the rows)
    bar_up: f32,
    thumb_len: f32,
    thumb_top: f32,
    // round 13: more one pixel marks (as `ring_marks`) stamped over the grid: the bar's part over the group box
    bar_marks: str,
    // round 13: the navigator row's horizontal thumb: its width and its start differ from the computed ones by these (px)
    hthumb_adj: f32,
    hthumb_dx: f32,
    hthumb_flat: bool,
    idle_on: bool,
    idle_fill: paint.Color,
    idle_edge: paint.Color,
    idle_top: paint.Color,
    foot_g1: paint.Color,
    foot_g2: paint.Color,
    foot_w1: paint.Color,
    foot_w2: paint.Color,
    // looks5-e: the TcxGrid's own 2 px frame (live capture, top grid of the main window): outer and inner line of the
    // top and left sides, one line at the bottom and the right; the lines differ a little with the grid's content
    ring: bool,
    ring_top_o: paint.Color,
    ring_top_i: paint.Color,
    ring_left_o: paint.Color,
    ring_left_i: paint.Color,
    ring_bottom: paint.Color,
    ring_right: paint.Color,
    // looks9-w1: the live footer's cells carry their own edge pixels (the green collection footer)
    footer_edges: bool,
    nav_rule: bool,
    // looks9-w1: the column (1-based) whose cells never take the selection's fill (the collection grid's Edition column)
    plain_col: usize,
    // looks9-w1: the column lines are a 1 px DCDCDC line at a fractional place: coverage soft_a0 at x = soft_x0 of the row, falling soft_slope per px (0 = the old ramp)
    soft_a0: f32,
    soft_x0: f32,
    soft_slope: f32,
    // looks9-w1: one pixel marks over the frame ring (the live ring's colours change along its length): "x y h rrggbb;...", from the grid's top-left
    ring_marks: str
}

// A colour from 0xRRGGBB; under the Windows dark map (`style.set_windark`) the dark counterpart of a light literal.
fn rgb(value: u32) -> paint.Color {
    let r = (value >> 16u32) & 255u32
    let g = (value >> 8u32) & 255u32
    let b = value & 255u32
    if style.neperdark_active() {
        // a light fill or rule of the v3 grid (white, greys, pale tints) is a dark tint of itself on the Neper dark page
        if (r + g + b) / 3u32 >= 200u32 { ret style.hex_raw(((14u32 + r / 10u32) * 65536u32) + ((15u32 + g / 10u32) * 256u32) + (20u32 + b / 10u32)) }
        ret style.hex_raw(value)
    }
    if !style.windark_active() { ret style.hex_raw(value) }
    if r == g && g == b { ret style.hex(value) }
    if value == 0x0078D7u32 || value == 0xA6D2FFu32 { ret style.hex_raw(0x264F78u32) }
    if value == 0xD9EBF9u32 { ret style.hex_raw(0x3A3A3Au32) }
    if value == 0x99D1FFu32 { ret style.hex_raw(0x1F4668u32) }
    let mean = (r + g + b) / 3u32
    // a light tint (footer band, hover blues): the face's dark with a trace of the hue; a dark ink hue (blue, red, green
    // of a card's colour): the same hue lifted towards white so that it reads on #2B2B2B
    if mean >= 200u32 { ret style.hex_raw(((24u32 + r / 8u32) * 65536u32) + ((24u32 + g / 8u32) * 256u32) + (24u32 + b / 8u32)) }
    if mean <= 110u32 {
        let lift = 128u32
        ret style.hex_raw(((r + lift * 2u32) / 3u32) * 65536u32 + ((g + lift * 2u32) / 3u32) * 256u32 + (b + lift * 2u32) / 3u32)
    }
    ret style.hex_raw(value)
}

// A colour from 0xRRGGBB, exactly (a Windows dark value).
fn raw(value: u32) -> paint.Color {
    ret style.hex_raw(value)
}

// MTG Studio v3's grid.
fn v3() -> Look {
    ret Look {
        on: true,
        row_height: 19.0,
        header_height: 19.0,
        pad: 2.0,
        text_size: 11.0,
        header: rgb(0xFFFFFFu32),
        header_hover: rgb(0xD9EBF9u32),
        header_line: rgb(0xF7F7F7u32),
        even: rgb(0xFFFFFFu32),
        odd: rgb(0xEFEFEFu32),
        selected: rgb(0xA6D2FFu32),
        selected_line: rgb(0x83878Bu32),
        line: rgb(0xE5E5E5u32),
        group_row: rgb(0xF0F0F0u32),
        footer_band: rgb(0xFFFFDDu32),
        footer_cell: rgb(0xE7EAEAu32),
        frame: rgb(0x9599A0u32),
        track: rgb(0xF0F0F0u32),
        thumb: rgb(0x858585u32),
        scroll_width: 16.0,
        group_flat: true,
        frame_none: false,
        dialog_lines: false,
        foot_set: false,
        foot_drift: 0.0,
        group_counts: false,
        group_rect: false,
        group_solid: false,
        bar_up: 0.0,
        thumb_len: 0.0,
        thumb_top: 0.0 - 1.0,
        bar_marks: "",
        hthumb_adj: 0.0,
        hthumb_dx: 0.0,
        hthumb_flat: false,
        idle_on: false,
        idle_fill: rgb(0xD5E4EEu32),
        idle_edge: rgb(0xD9DFE3u32),
        idle_top: rgb(0xE5EEF4u32),
        foot_g1: rgb(0xE7E7E7u32),
        foot_g2: rgb(0xEBEBEBu32),
        foot_w1: rgb(0xF0F0F0u32),
        foot_w2: rgb(0xE5E5E5u32),
        ring: true,
        ring_top_o: rgb(0x8D9096u32),
        ring_top_i: rgb(0xC6C8CCu32),
        ring_left_o: rgb(0x9599A0u32),
        ring_left_i: rgb(0xDDDEDFu32),
        ring_bottom: rgb(0xB9BCC0u32),
        ring_right: rgb(0xB5B8BDu32),
        footer_edges: false,
        nav_rule: false,
        plain_col: 0usize,
        soft_a0: 0.0,
        soft_x0: 0.0,
        soft_slope: 0.0,
        ring_marks: ""
    }
}

// The v3 grid under the Neper look's Dark palette: the same metrics, the surfaces and lines in the Neper dark
// tokens (page #12131A, header #1E2027, selection #34435F with the accent #B3C5FF as its edge, text from the theme).
// A footer band the application coloured itself keeps its hue, darkened; the stock yellow becomes a dark olive.
fn neper_dark_of(current: Look, base: Look) -> Look {
    var look = current
    look.header = rgb(0x1E2027u32)
    look.header_hover = rgb(0x2C3A4Fu32)
    look.header_line = rgb(0x32343Bu32)
    look.even = rgb(0x12131Au32)
    look.odd = rgb(0x1A1C23u32)
    look.selected = rgb(0x34435Fu32)
    look.selected_line = raw(0xB3C5FFu32)
    look.line = rgb(0x363840u32)
    look.group_row = rgb(0x22242Bu32)
    look.footer_cell = rgb(0x24262Du32)
    look.frame = rgb(0x6B6F7Au32)
    look.track = rgb(0x1E2027u32)
    look.thumb = rgb(0x7D818Cu32)
    look.footer_band = rgb(0x3A3920u32)
    let stock = rgb(0xFFFFDDu32)
    let off = base.footer_band.red - stock.red + base.footer_band.green - stock.green + base.footer_band.blue - stock.blue
    if off > 0.01 || off < 0.0 - 0.01 {
        look.footer_band = style.mix(base.footer_band, rgb(0x12131Au32), 0.65)
    }
    ret look
}

// (round 7) The Windows 11 dark grid: the same metrics, rows #2B2B2B / #262626, header #333333, selection #264F78,
// group rows #2F2F2F, a footer of dark panels, the scroll bar's #2B2B2B track with a #8A8A8A thumb.
fn v3_dark() -> Look {
    var look = v3()
    // (round 10) the native Windows 11 dark list view (ref/windows-native/dark/listview-*): header #191919 with a #636363
    // separator, frame #828790, selected focused row #1A364D under a #0078D4 dotted edge, unfocused selection #1B1B1B
    // (edge #131313), body column lines #414141, track #171717 with a #858585 thumb. Rows: the gallery's list is #202020
    // and its alternating notify-customdraw rows #2B2B2B (app-chosen colours, not the theme's), which v3's stripes take.
    // Hover over a header is pixel-identical to rest in the capture, so header_hover is a guess; the pressed header
    // (#838383) is drawn in collection.e.
    look.header = raw(0x191919u32)
    look.header_hover = raw(0x2B2B2Bu32)
    look.header_line = raw(0x636363u32)
    look.even = raw(0x202020u32)
    look.odd = raw(0x2B2B2Bu32)
    look.selected = raw(0x1A364Du32)
    look.selected_line = raw(0x0078D4u32)
    look.line = raw(0x414141u32)
    look.group_row = raw(0x2F2F2Fu32)
    look.footer_band = raw(0x2F2F2Fu32)
    look.footer_cell = raw(0x383838u32)
    look.frame = raw(0x828790u32)
    look.track = raw(0x171717u32)
    look.thumb = raw(0x858585u32)
    look.idle_fill = raw(0x1B1B1Bu32)
    look.idle_edge = raw(0x131313u32)
    look.idle_top = raw(0x1B1B1Bu32)
    ret look
}

// The ink v3 draws a card's row in, by the card's colour letter (`card_color.pas`, GetForegroundColor):
// W dirty white, U blue, B black, R red, G green, M multicolour orange, N colourless grey.
fn card_ink(letter: u8) -> (paint.Color, bool) {
    if letter == 87u8 { ret (rgb(0x646464u32), true) }
    if letter == 85u8 { ret (rgb(0x0000FFu32), true) }
    if letter == 66u8 { ret (rgb(0x000000u32), true) }
    if letter == 82u8 { ret (rgb(0xFF0000u32), true) }
    if letter == 71u8 { ret (rgb(0x008000u32), true) }
    if letter == 77u8 { ret (rgb(0xFF5F11u32), true) }
    if letter == 78u8 { ret (rgb(0x858585u32), true) }
    ret (rgb(0x000000u32), false)
}

// The ink v3 draws a rarity in (`card_rarity.pas`): common black, uncommon silver, rare dark gold,
// timeshift purple, mythic red-orange, bonus brick red, special pale orange.
fn rarity_ink(letter: u8) -> (paint.Color, bool) {
    if letter == 67u8 { ret (rgb(0x000000u32), true) }
    if letter == 85u8 { ret (rgb(0x8C8C8Cu32), true) }
    if letter == 82u8 { ret (rgb(0xA07D00u32), true) }
    if letter == 84u8 { ret (rgb(0x845D99u32), true) }
    if letter == 77u8 { ret (rgb(0xED9030u32), true) }
    if letter == 66u8 { ret (rgb(0xB63426u32), true) }
    if letter == 83u8 { ret (rgb(0xE69D54u32), true) }
    ret (rgb(0x000000u32), false)
}

// The theme's own look: `on` false, nothing overridden.
fn theme() -> Look {
    var look: Look = zero
    ret look
}

// ---- small marks the grid draws itself (the favourite star, the navigator's arrows) --------

type Shape = enum u8 { StarOutline, StarFilled, Left, Right, FirstBar, LastBar, UpOutline, PlusBox, MinusBox, DoubleLeft, DoubleRight, ArrowDown, ArrowUp, Check, ListGlyph, Minus, ArrowLong, DotLine, DotEdges, TreePlus, TreeMinus, TreeBox, Pixels, DotsSoft, DotsSoftLeft, SelDots, GroupRect, ChipRing, TreeFocus }

type Mark = struct { arena: *mem.Arena, color: paint.Color, inner: paint.Color, shape: Shape, pix: str, cols: usize, skip: usize }

fn mark_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

// A five-point star about (cx, cy): outer radius `r`, the inner one 0.382 of it.
fn star_path(a: *mem.Arena, cx: f32, cy: f32, r: f32) -> (geometry.Path, err) {
    let (pb, pb_error) = geometry.path_builder(a, 12usize, 12usize)
    if pb_error != ok { ret (zero, pb_error) }
    var builder = pb
    let ri = r * 0.382
    try geometry.move_to(&builder, geometry.Point { x: cx, y: cy - r })
    try geometry.line_to(&builder, geometry.Point { x: cx + ri * 0.5878, y: cy - ri * 0.8090 })
    try geometry.line_to(&builder, geometry.Point { x: cx + r * 0.9511, y: cy - r * 0.3090 })
    try geometry.line_to(&builder, geometry.Point { x: cx + ri * 0.9511, y: cy + ri * 0.3090 })
    try geometry.line_to(&builder, geometry.Point { x: cx + r * 0.5878, y: cy + r * 0.8090 })
    try geometry.line_to(&builder, geometry.Point { x: cx, y: cy + ri })
    try geometry.line_to(&builder, geometry.Point { x: cx - r * 0.5878, y: cy + r * 0.8090 })
    try geometry.line_to(&builder, geometry.Point { x: cx - ri * 0.9511, y: cy + ri * 0.3090 })
    try geometry.line_to(&builder, geometry.Point { x: cx - r * 0.9511, y: cy - r * 0.3090 })
    try geometry.line_to(&builder, geometry.Point { x: cx - ri * 0.5878, y: cy - ri * 0.8090 })
    try geometry.close_path(&builder)
    ret (geometry.finish(&builder), ok)
}

fn triangle_path(a: *mem.Arena, x0: f32, y0: f32, x1: f32, y1: f32, left: bool) -> (geometry.Path, err) {
    let (pb, pb_error) = geometry.path_builder(a, 4usize, 4usize)
    if pb_error != ok { ret (zero, pb_error) }
    var builder = pb
    let ym = (y0 + y1) * 0.5
    if left {
        try geometry.move_to(&builder, geometry.Point { x: x1, y: y0 })
        try geometry.line_to(&builder, geometry.Point { x: x0, y: ym })
        try geometry.line_to(&builder, geometry.Point { x: x1, y: y1 })
    } else {
        try geometry.move_to(&builder, geometry.Point { x: x0, y: y0 })
        try geometry.line_to(&builder, geometry.Point { x: x1, y: ym })
        try geometry.line_to(&builder, geometry.Point { x: x0, y: y1 })
    }
    try geometry.close_path(&builder)
    ret (geometry.finish(&builder), ok)
}

fn bar_path(a: *mem.Arena, x0: f32, y0: f32, x1: f32, y1: f32) -> (geometry.Path, err) {
    let (pb, pb_error) = geometry.path_builder(a, 5usize, 5usize)
    if pb_error != ok { ret (zero, pb_error) }
    var builder = pb
    try geometry.move_to(&builder, geometry.Point { x: x0, y: y0 })
    try geometry.line_to(&builder, geometry.Point { x: x1, y: y0 })
    try geometry.line_to(&builder, geometry.Point { x: x1, y: y1 })
    try geometry.line_to(&builder, geometry.Point { x: x0, y: y1 })
    try geometry.close_path(&builder)
    ret (geometry.finish(&builder), ok)
}

fn mark_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let m = mem.cast[*Mark](ctx)
    let cx = area.x + area.width * 0.5
    let cy = area.y + area.height * 0.5
    var side = area.width
    if area.height < side { side = area.height }
    if m.shape == Shape.TreePlus || m.shape == Shape.TreeMinus || m.shape == Shape.TreeBox { ret tree_mark_paint(m, b, area) }
    if m.shape == Shape.Pixels { ret pixels_paint(m, b, area) }
    if m.shape == Shape.DotsSoft || m.shape == Shape.DotsSoftLeft { ret dots_soft_paint(m, b, area) }
    if m.shape == Shape.SelDots { ret sel_dots_paint(m, b, area) }
    if m.shape == Shape.TreeFocus { ret tree_focus_paint(m, b, area) }
    if m.shape == Shape.GroupRect { ret group_rect_paint(m, b, area) }
    if m.shape == Shape.ChipRing { ret chip_ring_paint(m, b, area) }
    if m.shape == Shape.StarOutline || m.shape == Shape.StarFilled {
        let (outer, outer_error) = star_path(m.arena, cx, cy, side * 0.5)
        if outer_error != ok { ret outer_error }
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: outer, brush: paint.Brush { Solid: m.color } } })
        if m.shape == Shape.StarOutline {
            let (hole, hole_error) = star_path(m.arena, cx, cy, side * 0.5 * 0.6)
            if hole_error != ok { ret hole_error }
            try scene.push(b, scene.Command { FillPath: scene.FillPath { path: hole, brush: paint.Brush { Solid: m.inner } } })
        }
        ret ok
    }
    if m.shape == Shape.ListGlyph {
        // v3's customization glyph: four short rows, a dot and a line each, in the header's blue-grey
        var row_at: f32 = 0.0
        while row_at < 4.0 {
            let ry = area.y + area.height * (0.14 + 0.24 * row_at)
            try winpx.fill(b, area.x, ry, area.width * 0.2, area.height * 0.12, m.color)
            try winpx.fill(b, area.x + area.width * 0.35, ry, area.width * 0.65, area.height * 0.12, m.inner)
            row_at += 1.0
        }
        ret ok
    }
    if m.shape == Shape.ArrowLong {
        // v3's editing indicator: a shaft with a solid head, pointing right
        try winpx.fill(b, area.x, area.y + area.height * 0.38, area.width * 0.62, area.height * 0.24, m.color)
        let (apb, apb_error) = geometry.path_builder(m.arena, 4usize, 4usize)
        if apb_error != ok { ret apb_error }
        var ab = apb
        try geometry.move_to(&ab, geometry.Point { x: area.x + area.width * 0.55, y: area.y })
        try geometry.line_to(&ab, geometry.Point { x: area.x + area.width, y: area.y + area.height * 0.5 })
        try geometry.line_to(&ab, geometry.Point { x: area.x + area.width * 0.55, y: area.y + area.height })
        try geometry.close_path(&ab)
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&ab), brush: paint.Brush { Solid: m.color } } })
        ret ok
    }
    if m.shape == Shape.DotLine || m.shape == Shape.DotEdges {
        // v3's dotted focus rectangle of a group row: 1 px dots every 2 px along the top and bottom
        // edges (DotEdges also its left and right ends)
        var dx: f32 = 0.0
        while dx < area.width {
            try winpx.fill(b, area.x + dx, area.y, 1.0, 1.0, m.color)
            try winpx.fill(b, area.x + dx, area.y + area.height - 1.0, 1.0, 1.0, m.color)
            dx += 2.0
        }
        if m.shape == Shape.DotEdges {
            var dy: f32 = 0.0
            while dy < area.height {
                try winpx.fill(b, area.x, area.y + dy, 1.0, 1.0, m.color)
                dy += 2.0
            }
        }
        ret ok
    }
    if m.shape == Shape.Minus {
        try winpx.fill(b, area.x, area.y + area.height * 0.4, area.width, area.height * 0.2, m.color)
        ret ok
    }
    if m.shape == Shape.Check {
        let (cpb, cpb_error) = geometry.path_builder(m.arena, 8usize, 8usize)
        if cpb_error != ok { ret cpb_error }
        var cb = cpb
        let cx0 = area.x
        let cy0 = area.y
        let cw = area.width
        let ch = area.height
        try geometry.move_to(&cb, geometry.Point { x: cx0, y: cy0 + ch * 0.55 })
        try geometry.line_to(&cb, geometry.Point { x: cx0 + cw * 0.18, y: cy0 + ch * 0.4 })
        try geometry.line_to(&cb, geometry.Point { x: cx0 + cw * 0.4, y: cy0 + ch * 0.62 })
        try geometry.line_to(&cb, geometry.Point { x: cx0 + cw * 0.82, y: cy0 + ch * 0.1 })
        try geometry.line_to(&cb, geometry.Point { x: cx0 + cw, y: cy0 + ch * 0.28 })
        try geometry.line_to(&cb, geometry.Point { x: cx0 + cw * 0.4, y: cy0 + ch })
        try geometry.close_path(&cb)
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&cb), brush: paint.Brush { Solid: m.color } } })
        ret ok
    }
    if m.shape == Shape.ArrowDown || m.shape == Shape.ArrowUp {
        // v3's drop marker: a fat arrow, black outline, `color` fill (bright green)
        var pass = 0usize
        while pass < 2usize {
            var inset: f32 = 0.0
            var brush = paint.rgba(0.0, 0.0, 0.0, 1.0)
            if pass == 1usize {
                inset = 1.0
                brush = m.color
            }
            let w = area.width - 2.0 * inset
            let h = area.height - 2.0 * inset
            let left = area.x + inset
            var top = area.y + inset
            var tip = top + h
            var neck = top + h * 0.5
            if m.shape == Shape.ArrowUp {
                tip = top
                top = top + h
                neck = tip + h * 0.5
            }
            let (pb, pb_error) = geometry.path_builder(m.arena, 8usize, 8usize)
            if pb_error != ok { ret pb_error }
            var builder = pb
            try geometry.move_to(&builder, geometry.Point { x: left + w * 0.3, y: top })
            try geometry.line_to(&builder, geometry.Point { x: left + w * 0.7, y: top })
            try geometry.line_to(&builder, geometry.Point { x: left + w * 0.7, y: neck })
            try geometry.line_to(&builder, geometry.Point { x: left + w, y: neck })
            try geometry.line_to(&builder, geometry.Point { x: left + w * 0.5, y: tip })
            try geometry.line_to(&builder, geometry.Point { x: left, y: neck })
            try geometry.line_to(&builder, geometry.Point { x: left + w * 0.3, y: neck })
            try geometry.close_path(&builder)
            try scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&builder), brush: paint.Brush { Solid: brush } } })
            pass += 1usize
        }
        ret ok
    }
    let x0 = area.x
    let x1 = area.x + area.width
    let y0 = area.y
    let y1 = area.y + area.height
    let bar = area.width * 0.18
    if m.shape == Shape.PlusBox || m.shape == Shape.MinusBox {
        // the group row's expander: a framed square with a plus (collapsed) or a minus (open)
        let (frame, frame_error) = bar_path(m.arena, x0, y0, x1, y1)
        if frame_error != ok { ret frame_error }
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: frame, brush: paint.Brush { Solid: m.color } } })
        let (fill, fill_error) = bar_path(m.arena, x0 + 1.0, y0 + 1.0, x1 - 1.0, y1 - 1.0)
        if fill_error != ok { ret fill_error }
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: fill, brush: paint.Brush { Solid: m.inner } } })
        let (dash, dash_error) = bar_path(m.arena, x0 + 2.5, cy - 0.5, x1 - 2.5, cy + 0.5)
        if dash_error != ok { ret dash_error }
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: dash, brush: paint.Brush { Solid: paint.rgba(0.0, 0.0, 0.0, 1.0) } } })
        if m.shape == Shape.MinusBox { ret ok }
        let (upright, upright_error) = bar_path(m.arena, cx - 0.5, y0 + 2.5, cx + 0.5, y1 - 2.5)
        if upright_error != ok { ret upright_error }
        ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: upright, brush: paint.Brush { Solid: paint.rgba(0.0, 0.0, 0.0, 1.0) } } })
    }
    if m.shape == Shape.UpOutline {
        // an outlined triangle, the sort direction mark of a group chip
        let (pb, pb_error) = geometry.path_builder(m.arena, 4usize, 4usize)
        if pb_error != ok { ret pb_error }
        var outer = pb
        try geometry.move_to(&outer, geometry.Point { x: cx, y: y0 })
        try geometry.line_to(&outer, geometry.Point { x: x1, y: y1 })
        try geometry.line_to(&outer, geometry.Point { x: x0, y: y1 })
        try geometry.close_path(&outer)
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&outer), brush: paint.Brush { Solid: m.color } } })
        let (qb, qb_error) = geometry.path_builder(m.arena, 4usize, 4usize)
        if qb_error != ok { ret qb_error }
        var hole = qb
        let w = area.width * 0.22
        let h = area.height * 0.26
        try geometry.move_to(&hole, geometry.Point { x: cx, y: y0 + h })
        try geometry.line_to(&hole, geometry.Point { x: x1 - w, y: y1 - h * 0.45 })
        try geometry.line_to(&hole, geometry.Point { x: x0 + w, y: y1 - h * 0.45 })
        try geometry.close_path(&hole)
        ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&hole), brush: paint.Brush { Solid: m.inner } } })
    }
    if m.shape == Shape.DoubleLeft || m.shape == Shape.DoubleRight {
        let half = area.width * 0.5
        let left_side = m.shape == Shape.DoubleLeft
        let (first_tri, first_error) = triangle_path(m.arena, x0, y0, x0 + half, y1, left_side)
        if first_error != ok { ret first_error }
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: first_tri, brush: paint.Brush { Solid: m.color } } })
        let (second_tri, second_error) = triangle_path(m.arena, x0 + half, y0, x1, y1, left_side)
        if second_error != ok { ret second_error }
        ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: second_tri, brush: paint.Brush { Solid: m.color } } })
    }
    if m.shape == Shape.Left || m.shape == Shape.Right {
        let (tri, tri_error) = triangle_path(m.arena, x0, y0, x1, y1, m.shape == Shape.Left)
        if tri_error != ok { ret tri_error }
        ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: tri, brush: paint.Brush { Solid: m.color } } })
    }
    if m.shape == Shape.FirstBar {
        let (stem, stem_error) = bar_path(m.arena, x0, y0, x0 + bar, y1)
        if stem_error != ok { ret stem_error }
        try scene.push(b, scene.Command { FillPath: scene.FillPath { path: stem, brush: paint.Brush { Solid: m.color } } })
        let (tri, tri_error) = triangle_path(m.arena, x0 + bar * 1.6, y0, x1, y1, true)
        if tri_error != ok { ret tri_error }
        ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: tri, brush: paint.Brush { Solid: m.color } } })
    }
    let (stem, stem_error) = bar_path(m.arena, x1 - bar, y0, x1, y1)
    if stem_error != ok { ret stem_error }
    try scene.push(b, scene.Command { FillPath: scene.FillPath { path: stem, brush: paint.Brush { Solid: m.color } } })
    let (tri, tri_error) = triangle_path(m.arena, x0, y0, x1 - bar * 1.6, y1, false)
    if tri_error != ok { ret tri_error }
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: tri, brush: paint.Brush { Solid: m.color } } })
}

// A mark `width` by `height` in `color` (a star's hole in `inner`).
fn mark(a: *mem.Arena, shape: Shape, color: paint.Color, inner: paint.Color, width: f32, height: f32) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    marks[0usize] = Mark { arena: a, color: color, inner: inner, shape: shape, pix: "", cols: 0usize, skip: 0usize }
    var size = style.defaults()
    size.width = style.Length { Px: width }
    size.height = style.Length { Px: height }
    size.min_width = style.Length { Px: width }
    size.min_height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: size, children: none }, ok)
}

// ---- pictures from MTG Studio v3's data folder ---------------------------------------------

error BadPicture

fn ends_with_bmp(path: str) -> bool {
    if path.len < 4usize { ret false }
    let n = path.len
    ret (path[n - 3usize] == 98u8 || path[n - 3usize] == 66u8) && (path[n - 2usize] == 109u8 || path[n - 2usize] == 77u8) && (path[n - 1usize] == 112u8 || path[n - 1usize] == 80u8)
}

fn le32(b: []const u8, at: usize) -> u32 {
    ret u32(b[at]) | (u32(b[at + 1usize]) << 8u32) | (u32(b[at + 2usize]) << 16u32) | (u32(b[at + 3usize]) << 24u32)
}

// An uncompressed 24-bit Windows bitmap (what v3's legality letters are) as straight RGBA.
fn bmp24(a: *mem.Arena, bytes: []const u8) -> (image.ConstImage, err) {
    if bytes.len < 54usize || bytes[0usize] != 66u8 || bytes[1usize] != 77u8 { ret (zero, BadPicture) }
    let data_at = usize(le32(bytes, 10usize))
    let width = usize(le32(bytes, 18usize))
    let height_raw = le32(bytes, 22usize)
    var height = usize(height_raw)
    var bottom_up = true
    if height_raw >= 2147483648u32 {
        height = usize(0u32 - height_raw)
        bottom_up = false
    }
    let bits = u32(bytes[28usize]) | (u32(bytes[29usize]) << 8u32)
    if bits != 24u32 || le32(bytes, 30usize) != 0u32 || width == 0usize || height == 0usize || width > 4096usize || height > 4096usize { ret (zero, BadPicture) }
    let stride_in = ((width * 3usize + 3usize) / 4usize) * 4usize
    if data_at + stride_in * height > bytes.len { ret (zero, BadPicture) }
    let (px, px_error) = mem.alloc[u8](a, width * height * 4usize)
    if px_error != ok { ret (zero, px_error) }
    var y = 0usize
    while y < height {
        var src_row = y
        if bottom_up { src_row = height - 1usize - y }
        var x = 0usize
        while x < width {
            let from = data_at + src_row * stride_in + x * 3usize
            let to = (y * width + x) * 4usize
            px[to] = bytes[from + 2usize]
            px[to + 1usize] = bytes[from + 1usize]
            px[to + 2usize] = bytes[from]
            px[to + 3usize] = 255u8
            x += 1usize
        }
        y += 1usize
    }
    let (view, view_error) = image.make_const(px, u32(width), u32(height), width * 4usize, .Rgba8, .Straight)
    if view_error != ok { ret (zero, BadPicture) }
    ret (view, ok)
}

// One .png or .bmp file decoded and uploaded to the renderer (`a` may be reset afterwards).
fn load_picture(a: *mem.Arena, r: *scene.Renderer, path: str) -> (scene.TextureId, err) {
    let (bytes, read_error) = fs.read_file(a, path, 1048576usize)
    if read_error != ok { ret (zero, read_error) }
    if ends_with_bmp(path) {
        let (bitmap, bitmap_error) = bmp24(a, bytes)
        if bitmap_error != ok { ret (zero, BadPicture) }
        let (bitmap_texture, bitmap_upload_error) = scene.upload_image(r, bitmap)
        ret (bitmap_texture, bitmap_upload_error)
    }
    var state: io.SliceReader = zero
    state.data = bytes
    state.off = 0usize
    let (decoded, decode_error) = png.decode(a, io.slice_reader(&state), png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 0u64, verify_crc: true })
    if decode_error != ok { ret (zero, BadPicture) }
    let (view, view_error) = image.make_const(decoded.pixels, decoded.width, decoded.height, decoded.stride, decoded.format, decoded.alpha)
    if view_error != ok { ret (zero, BadPicture) }
    let (texture, upload_error) = scene.upload_image(r, view)
    ret (texture, upload_error)
}

// ---- vector pictures (v3's edition symbols are SVG) -------------------------------------------

type SvgMark = struct { arena: *mem.Arena, text: str, color: paint.Color }

fn svg_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let m = mem.cast[*SvgMark](ctx)
    ret svg.draw(m.arena, b, m.text, area, m.color)
}

// An SVG document drawn into a `width` by `height` box; `text` must stay valid while the node
// is in the tree (a malformed document draws nothing).
fn svg_mark(a: *mem.Arena, text: str, color: paint.Color, width: f32, height: f32) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[SvgMark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    marks[0usize] = SvgMark { arena: a, text: text, color: color }
    var size = style.defaults()
    size.width = style.Length { Px: width }
    size.height = style.Length { Px: height }
    size.min_width = style.Length { Px: width }
    size.min_height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: svg_paint, state: widget.bytes_of[SvgMark](&marks[0usize]) } }, style: size, children: none }, ok)
}

// ---- vector pictures fitted to their ink ----------------------------------------------------
//
// An edition symbol's drawing sits inside a viewBox with a margin that differs from symbol to
// symbol, but v3 shows each at the size of its row. `svg_fit_mark` measures the drawing extent
// (the points of its path data, control points included) and scales it so that extent fills
// the box.

type Ink = struct { x0: f32, y0: f32, x1: f32, y1: f32, any: bool }

fn ink_add(b: *Ink, x: f32, y: f32) {
    if !b.any {
        b.x0 = x
        b.x1 = x
        b.y0 = y
        b.y1 = y
        b.any = true
        ret
    }
    if x < b.x0 { b.x0 = x }
    if x > b.x1 { b.x1 = x }
    if y < b.y0 { b.y0 = y }
    if y > b.y1 { b.y1 = y }
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn is_sep(c: u8) -> bool { ret c == 32u8 || c == 44u8 || c == 10u8 || c == 13u8 || c == 9u8 }

// Skips separators, then reads one number; false when none follows.
fn num_at(d: str, at: *usize, out: *f32) -> bool {
    var i = *at
    while i < d.len && is_sep(d[i]) { i += 1usize }
    if i >= d.len { ret false }
    var negative = false
    if d[i] == 45u8 {
        negative = true
        i += 1usize
    } else if d[i] == 43u8 {
        i += 1usize
    }
    var whole: f32 = 0.0
    var any = false
    while i < d.len && is_digit(d[i]) {
        whole = whole * 10.0 + f32(d[i] - 48u8)
        i += 1usize
        any = true
    }
    if i < d.len && d[i] == 46u8 {
        i += 1usize
        var scale: f32 = 0.1
        while i < d.len && is_digit(d[i]) {
            whole += f32(d[i] - 48u8) * scale
            scale = scale * 0.1
            i += 1usize
            any = true
        }
    }
    if !any { ret false }
    if i < d.len && (d[i] == 101u8 || d[i] == 69u8) {
        var j = i + 1usize
        var exp_negative = false
        if j < d.len && (d[j] == 45u8 || d[j] == 43u8) {
            exp_negative = d[j] == 45u8
            j += 1usize
        }
        var e: i32 = 0
        var has_e = false
        while j < d.len && is_digit(d[j]) {
            e = e * 10 + i32(d[j] - 48u8)
            j += 1usize
            has_e = true
        }
        if has_e {
            var k: i32 = 0
            while k < e {
                if exp_negative { whole = whole * 0.1 } else { whole = whole * 10.0 }
                k += 1
            }
            i = j
        }
    }
    if negative { whole = 0.0 - whole }
    *at = i
    *out = whole
    ret true
}

fn flag_at(d: str, at: *usize) -> bool {
    var i = *at
    while i < d.len && is_sep(d[i]) { i += 1usize }
    if i >= d.len || (d[i] != 48u8 && d[i] != 49u8) { ret false }
    *at = i + 1usize
    ret true
}

// The extent of one path data string.
fn path_ink(d: str, b: *Ink) {
    var i = 0usize
    var cx: f32 = 0.0
    var cy: f32 = 0.0
    var sx: f32 = 0.0
    var sy: f32 = 0.0
    var cmd: u8 = 0u8
    var guard = 0usize
    while i < d.len && guard < 40000usize {
        guard += 1usize
        while i < d.len && is_sep(d[i]) { i += 1usize }
        if i >= d.len { break }
        let c = d[i]
        if (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) {
            cmd = c
            i += 1usize
            if c == 90u8 || c == 122u8 {
                cx = sx
                cy = sy
                continue
            }
        }
        let relative = cmd >= 97u8
        var upper = cmd
        if relative { upper = cmd - 32u8 }
        var p1: f32 = 0.0
        var p2: f32 = 0.0
        var p3: f32 = 0.0
        var p4: f32 = 0.0
        var p5: f32 = 0.0
        var p6: f32 = 0.0
        var ox: f32 = 0.0
        var oy: f32 = 0.0
        if relative {
            ox = cx
            oy = cy
        }
        if upper == 72u8 {
            if !num_at(d, &i, &p1) { break }
            cx = ox + p1
            ink_add(b, cx, cy)
        } else if upper == 86u8 {
            if !num_at(d, &i, &p1) { break }
            cy = oy + p1
            ink_add(b, cx, cy)
        } else if upper == 77u8 || upper == 76u8 || upper == 84u8 {
            if !num_at(d, &i, &p1) || !num_at(d, &i, &p2) { break }
            cx = ox + p1
            cy = oy + p2
            if upper == 77u8 {
                sx = cx
                sy = cy
                if relative { cmd = 108u8 } else { cmd = 76u8 }
            }
            ink_add(b, cx, cy)
        } else if upper == 67u8 {
            if !num_at(d, &i, &p1) || !num_at(d, &i, &p2) || !num_at(d, &i, &p3) || !num_at(d, &i, &p4) || !num_at(d, &i, &p5) || !num_at(d, &i, &p6) { break }
            ink_add(b, ox + p1, oy + p2)
            ink_add(b, ox + p3, oy + p4)
            cx = ox + p5
            cy = oy + p6
            ink_add(b, cx, cy)
        } else if upper == 83u8 || upper == 81u8 {
            if !num_at(d, &i, &p1) || !num_at(d, &i, &p2) || !num_at(d, &i, &p3) || !num_at(d, &i, &p4) { break }
            ink_add(b, ox + p1, oy + p2)
            cx = ox + p3
            cy = oy + p4
            ink_add(b, cx, cy)
        } else if upper == 65u8 {
            // rx ry rotation large-arc sweep x y
            if !num_at(d, &i, &p1) || !num_at(d, &i, &p2) || !num_at(d, &i, &p3) { break }
            if !flag_at(d, &i) || !flag_at(d, &i) { break }
            if !num_at(d, &i, &p5) || !num_at(d, &i, &p6) { break }
            cx = ox + p5
            cy = oy + p6
            ink_add(b, cx, cy)
        } else {
            break
        }
    }
}

// The value of the first ` name="..."` at or after `from` (and where it ended).
fn attr_value(text: str, name: str, from: usize) -> (str, usize, bool) {
    var i = from
    while i + name.len + 2usize < text.len {
        var hit = text[i] == 32u8
        var k = 0usize
        while hit && k < name.len {
            if text[i + 1usize + k] != name[k] { hit = false }
            k += 1usize
        }
        if hit && i + name.len + 2usize < text.len && text[i + 1usize + name.len] == 61u8 && text[i + 2usize + name.len] == 34u8 {
            let start = i + name.len + 3usize
            var end = start
            while end < text.len && text[end] != 34u8 { end += 1usize }
            ret (text[start..end], end, true)
        }
        i += 1usize
    }
    ret ("", from, false)
}

// The ink extent of a document's paths and its viewBox size (0 when it has none).
fn svg_ink(text: str) -> (Ink, f32, f32) {
    var ink: Ink = zero
    var at = 0usize
    var found = true
    while found {
        let (d, end, has) = attr_value(text, "d", at)
        found = has
        if has {
            path_ink(d, &ink)
            at = end
        }
    }
    let (view, view_end, has_view) = attr_value(text, "viewBox", 0usize)
    if has_view {
        var i = 0usize
        var skip: f32 = 0.0
        var vw: f32 = 0.0
        var vh: f32 = 0.0
        if num_at(view, &i, &skip) && num_at(view, &i, &skip) && num_at(view, &i, &vw) && num_at(view, &i, &vh) {
            ret (ink, vw, vh)
        }
    }
    ret (ink, 0.0, 0.0)
}

type FitMark = struct { arena: *mem.Arena, text: str, color: paint.Color, x0: f32, y0: f32, x1: f32, y1: f32, vw: f32, vh: f32 }

fn fit_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let m = mem.cast[*FitMark](ctx)
    let iw = m.x1 - m.x0
    let ih = m.y1 - m.y0
    if !(iw > 0.0) || !(ih > 0.0) || !(m.vw > 0.0) || !(m.vh > 0.0) { ret svg.draw(m.arena, b, m.text, area, m.color) }
    var k = area.width / iw
    if area.height / ih < k { k = area.height / ih }
    let dest = geometry.Rect { x: area.x + area.width * 0.5 - (m.x0 + m.x1) * 0.5 * k, y: area.y + area.height * 0.5 - (m.y0 + m.y1) * 0.5 * k, width: m.vw * k, height: m.vh * k }
    let save: scene.Command = .Save
    try scene.push(b, save)
    try scene.push(b, scene.Command { Clip: scene.Clip { Rect: area } })
    try svg.draw(m.arena, b, m.text, dest, m.color)
    let restore: scene.Command = .Restore
    ret scene.push(b, restore)
}

// An SVG document drawn so that its own extent fills `width` by `height`.
fn svg_fit_mark(a: *mem.Arena, text: str, color: paint.Color, width: f32, height: f32) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[FitMark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    let (ink, vw, vh) = svg_ink(text)
    marks[0usize] = FitMark { arena: a, text: text, color: color, x0: ink.x0, y0: ink.y0, x1: ink.x1, y1: ink.y1, vw: vw, vh: vh }
    var size = style.defaults()
    size.width = style.Length { Px: width }
    size.height = style.Length { Px: height }
    size.min_width = style.Length { Px: width }
    size.min_height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: fit_paint, state: widget.bytes_of[FitMark](&marks[0usize]) } }, style: size, children: none }, ok)
}

// ---- looks3-e: the tree list's marks, pixel for pixel from the live Filter dialog capture --------
// TreePlus / TreeMinus: the 9 x 10 expander (a #919191 frame, a light gradient, a navy cross);
// TreeBox: the 13 x 13 unchecked check box of the node (the capture's grey values, row by row).
fn tpx(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, value: u32) -> err {
    ret winpx.fill(b, x, y, w, h, rgb(value))
}

fn tree_box_grays() -> str {
    ret "ba9ec0c3c3c3c3c3c3c3ba9bc07cc9f0f3f3f3f3f3f3f3edcf8065edf3f3f3f3f3f3f3f3f3f06562f3f3f3f3f3f3f3f3f3f3f36262f3f3f3f3f3f3f3f3f3f3f36262f3f3f3f3f3f3f3f3f3f3f36262f3f3f3f3f3f3f3f3f3f3f36262f3f3f3f3f3f3f3f3f3f3f36262f3f3f3f3f3f3f3f3f3f3f36268edf3f3f3f3f3f3f3f3f3e76894b3e7f3f3f3f3f3f3f3edb08ed89d929292929292929294a3d4efd5c3c0c0c0c0c0c0c0c3d7ef"
}

fn hex_digit(c: u8) -> u32 {
    if c >= 97u8 { ret u32(c) - 87u32 }
    ret u32(c) - 48u32
}

fn tree_mark_paint(m: *Mark, b: *scene.Builder, area: geometry.Rect) -> err {
    let x = area.x
    let y = area.y
    if m.shape == Shape.TreeBox {
        let grays = tree_box_grays()
        var r = 0usize
        while r < 13usize {
            var c = 0usize
            while c < 13usize {
                let i = (r * 13usize + c) * 2usize
                let g = hex_digit(grays[i]) * 16u32 + hex_digit(grays[i + 1usize])
                try tpx(b, x + f32(c), y + f32(r), 1.0, 1.0, g * 65793u32)
                c += 1usize
            }
            r += 1usize
        }
        ret ok
    }
    // the expander: 9 wide, 10 tall
    try tpx(b, x, y, 9.0, 10.0, 0x919191u32)
    try tpx(b, x + 1.0, y, 7.0, 1.0, 0xB0B0B0u32)
    try tpx(b, x, y, 1.0, 1.0, 0xCCCCCDu32)
    try tpx(b, x + 8.0, y, 1.0, 1.0, 0xCCCCCDu32)
    try tpx(b, x + 1.0, y + 1.0, 7.0, 1.0, 0xD8D8D8u32)
    try tpx(b, x, y + 1.0, 1.0, 1.0, 0x9F9F9Fu32)
    try tpx(b, x + 8.0, y + 1.0, 1.0, 1.0, 0x9F9F9Fu32)
    // the light gradient between the frame's sides, rows 2..7
    try tpx(b, x + 1.0, y + 2.0, 7.0, 1.0, 0xFCFCFCu32)
    try tpx(b, x + 1.0, y + 3.0, 7.0, 1.0, 0xFBFBFBu32)
    try tpx(b, x + 1.0, y + 4.0, 7.0, 1.0, 0xFAFAFAu32)
    try tpx(b, x + 1.0, y + 5.0, 7.0, 1.0, 0xF1F1F1u32)
    try tpx(b, x + 1.0, y + 6.0, 7.0, 1.0, 0xE6E6E6u32)
    try tpx(b, x + 1.0, y + 7.0, 7.0, 1.0, 0xE3E3E3u32)
    try tpx(b, x, y + 8.0, 9.0, 1.0, 0xACACACu32)
    try tpx(b, x + 1.0, y + 9.0, 7.0, 1.0, 0xD0D0D0u32)
    try tpx(b, x, y + 9.0, 1.0, 1.0, 0xDDDEDEu32)
    try tpx(b, x + 8.0, y + 9.0, 1.0, 1.0, 0xDDDEDEu32)
    // the cross: a two-row bar and, for a plus, a one-wide stem
    try tpx(b, x + 2.0, y + 4.0, 5.0, 1.0, 0x8595C3u32)
    try tpx(b, x + 2.0, y + 5.0, 5.0, 1.0, 0xB7BFD5u32)
    try tpx(b, x + 4.0, y + 4.0, 1.0, 1.0, 0x405895u32)
    try tpx(b, x + 4.0, y + 5.0, 1.0, 1.0, 0x344D84u32)
    if m.shape == Shape.TreePlus {
        try tpx(b, x + 4.0, y + 2.0, 1.0, 1.0, 0x6F80A0u32)
        try tpx(b, x + 4.0, y + 3.0, 1.0, 1.0, 0x294272u32)
        try tpx(b, x + 4.0, y + 6.0, 1.0, 1.0, 0x294272u32)
        try tpx(b, x + 4.0, y + 7.0, 1.0, 1.0, 0xA5AEBDu32)
    }
    ret ok
}
// ---- end looks3-e ------------------------------------------------------------------------------

fn pix_digit(c: u8) -> f32 {
    if c >= 65u8 { ret f32(c - 55u8) }
    ret f32(c - 48u8)
}

// looks4-e: a bitmap glyph, one opaque pixel per six hex digits (RRGGBB), `cols` pixels to a row,
// drawn one logical pixel each from the top-left of the area.
fn pixels_paint(m: *Mark, b: *scene.Builder, area: geometry.Rect) -> err {
    var at = 0usize
    var n = 0usize
    // looks13-r2: runs of equal pixels in a row are one rectangle (the same pixels, far fewer commands: v3's bitmaps are mostly flat)
    while at + 6usize <= m.pix.len {
        let col = n % m.cols
        var run = 1usize
        if col >= m.skip {
            while col + run < m.cols && at + (run + 1usize) * 6usize <= m.pix.len {
                var same = true
                var d = 0usize
                while d < 6usize {
                    if m.pix[at + d] != m.pix[at + run * 6usize + d] { same = false }
                    d += 1usize
                }
                if !same { break }
                run += 1usize
            }
        }
        let ri = u32(pix_digit(m.pix[at]) * 16.0 + pix_digit(m.pix[at + 1usize]))
        let gi = u32(pix_digit(m.pix[at + 2usize]) * 16.0 + pix_digit(m.pix[at + 3usize]))
        let bi = u32(pix_digit(m.pix[at + 4usize]) * 16.0 + pix_digit(m.pix[at + 5usize]))
        // (round 7) under the Windows dark map the bitmap's pixels take their dark counterpart (a no-op in light)
        var shown = rgb(ri * 65536u32 + gi * 256u32 + bi)
        // Neper dark: a dark glyph pixel of the bitmap (the row arrow, the star's outline) is drawn in light ink so that it reads on the dark tile
        if style.neperdark_active() && (ri + gi + bi) / 3u32 < 110u32 { shown = style.hex_raw((225u32 - ri / 2u32) * 65536u32 + (226u32 - gi / 2u32) * 256u32 + (233u32 - bi / 2u32)) }
        let px = f32(col) - f32(m.skip)
        let py = f32(n / m.cols)
        // round 18: 'ZZZZZZ' is a transparent pixel
        if col >= m.skip && m.pix[at] != 90u8 { try winpx.fill(b, f32(i64(area.x + 0.5)) + px, f32(i64(area.y + 0.5)) + py, f32(run), 1.0, shown) }
        at += 6usize * run
        n += run
    }
    ret ok
}

// A `w` x `h` pixel glyph from `pix` (see the gx_ functions).
fn pixels(a: *mem.Arena, pix: str, w: f32, h: f32) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    marks[0usize] = Mark { arena: a, color: rgb(0u32), inner: rgb(0u32), shape: Shape.Pixels, pix: pix, cols: usize(w), skip: 0usize }
    var size = style.defaults()
    size.width = style.Length { Px: w }
    size.height = style.Length { Px: h }
    size.min_width = style.Length { Px: w }
    size.min_height = style.Length { Px: h }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: size, children: none }, ok)
}

// looks9-w1: the same glyph without its first `skip` columns (the node is `w - skip` wide)
fn pixels_skip(a: *mem.Arena, pix: str, w: f32, h: f32, skip: usize) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    marks[0usize] = Mark { arena: a, color: rgb(0u32), inner: rgb(0u32), shape: Shape.Pixels, pix: pix, cols: usize(w), skip: skip }
    var size = style.defaults()
    size.width = style.Length { Px: w - f32(skip) }
    size.height = style.Length { Px: h }
    size.min_width = style.Length { Px: w - f32(skip) }
    size.min_height = style.Length { Px: h }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: size, children: none }, ok)
}

// ---- looks4-e: pixel glyphs cut from the live 100 % main window capture (data_grid_main.png), colours as seen on the
// header (white) or group row (#F0F0F0) they stand on ----
fn gx_expander() -> str { ret "D7D7D8BEBEBEBABABABABABABABABABABABABABABABABABACDCDCEEAEAEAB1B1B1C6C6C6CECECECECECECECECECECECECECECECECECEABABABE1E2E2A2A2A2E9E9E9FCFCFCFCFCFC9AA6BCE6E9EEFCFCFCFCFCFCA5A5A5DEDEDEA2A2A2E8E8E8FBFBFBFBFBFB50648BD4D9E2FBFBFBFBFBFBA4A5A5DEDEDEA2A2A2E7E8E8A9B4D497A5CB4D639B8696C197A5CBE8EBF2A4A4A4DEDEDEA2A2A2E1E1E1B4BDD5A7B1CE4C6296929FC1A7B1CEE5E7ECA3A3A3DEDEDEA2A2A2D8D8D7E7E7E7E7E7E74C6087C4C9D1E7E7E7E7E7E7A1A1A1DEDEDEA2A2A2D4D4D4E3E3E3E3E3E3A1AABBD4D6DAE3E3E3E3E3E3A0A0A0DEDEDEB5B5B6B3B3B3B5B5B5B5B5B5B5B5B5B5B5B5B5B5B5B5B5B5AAABABE3E3E3DDDDDDCACACAC6C6C6C6C6C6C6C6C6C6C6C6C6C6C6C6C6C6D5D5D6ECECEC" }
fn gx_expander_w() -> f32 { ret 10.0 }
fn gx_expander_h() -> f32 { ret 10.0 }
fn gx_sort_down() -> str { ret "DCDCDCC7C7C7C7C7C7C7C7C7C7C7C7C7C7C7C7C7C7E9E9E9C4C4C4C3C3C3D8D8D8D8D8D8D8D8D8D8D8D8B6B6B6DBDBDBE7E7E7CDCDCDE9E9E9FFFFFFFFFFFFDCDCDCD2D2D2F0F0F0FFFFFFC4C4C4DBDBDBFFFFFFFFFFFFC4C4C4DBDBDBFFFFFFFFFFFFE7E7E7CDCDCDE9E9E9DCDCDCD2D2D2F0F0F0FFFFFFFFFFFFFFFFFFC4C4C4DBDBDBC4C4C4DBDBDBFFFFFFFFFFFFFFFFFFFFFFFFE7E7E7CDCDCDD2D2D2F0F0F0FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC4C4C4DBDBDBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE7E7E7F0F0F0FFFFFFFFFFFFFFFFFF" }
fn gx_sort_down_w() -> f32 { ret 8.0 }
fn gx_sort_down_h() -> f32 { ret 9.0 }
fn gx_sort_up() -> str { ret "FFFFFFFFFFFFFFFFFFD1D1D1F3F3F3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFB4B4B4EBEBEBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFD1D1D1D6D6D6C9C9C9F3F3F3FFFFFFFFFFFFFFFFFFFFFFFFB4B4B4EBEBEBB4B4B4EBEBEBFFFFFFFFFFFFFFFFFFD1D1D1D6D6D6F7F7F7E2E2E2C9C9C9F3F3F3FFFFFFFFFFFFB3B3B3EBEBEBFFFFFFFFFFFFB4B4B4EBEBEBFFFFFFD1D1D1D6D6D6F7F7F7FFFFFFFFFFFFE2E2E2C9C9C9F3F3F3B3B3B3BEBEBEC5C5C5C5C5C5C5C5C5C5C5C5A8A8A8EBEBEBE1E1E1DADADADADADADADADADADADADADADADADADAF7F7F7" }
fn gx_sort_up_w() -> f32 { ret 8.0 }
// looks5-e: the scroll bar's pressed lower arrow, cut from states/scroll-bar-arrow-pressed-main-vertical (on #F0F0F0)
fn gx_arrow_down() -> str { ret "E8E8E8D1D1D1C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3D4D4D4EAEAEAD6D6D69D9D9D7F7F7F7F7F7F7F7F7F7F7F7F7F7F7FA2A2A2DADADADCDCDC9A9A9A6A6A6A6666666666666666666B6B6BA1A1A1DFDFDFEEEEEEC6C6C6838383666666666666666666888888CCCCCCEEEEEEF0F0F0E8E8E8B1B1B1767676666666787878B8B8B8E9E9E9F0F0F0F0F0F0F0F0F0DCDCDCA7A7A7888888ACACACDFDFDFF0F0F0F0F0F0F0F0F0F0F0F0EFEFEFDCDCDCCDCDCDDFDFDFEFEFEFF0F0F0F0F0F0" }
fn gx_arrow_down_w() -> f32 { ret 9.0 }
fn gx_arrow_down_h() -> f32 { ret 7.0 }
// the hot upper and lower arrow of the scroll bar, 11 x 9 on #F0F0F0 (states/hover-scroll-bar-vertical-arrow-up and -down)
fn gx_arrow_hot_up() -> str { ret "F0F0F0F0F0F0F0F0F0F0F0F0E2E2E2D7D7D7E4E4E4F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0D7D7D7A5A5A58B8B8BA9A9A9DBDBDBF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0E5E5E5AAAAAA727272666666747474B1B1B1E6E6E6F0F0F0F0F0F0F0F0F0EDEDEDBEBEBE7D7D7D666666666666666666818181C5C5C5EEEEEEF0F0F0F0F0F0D1D1D18E8E8E696969666666666666666666696969949494D5D5D5F0F0F0E2E2E2A4A4A46F6F6F666666666666666666666666666666707070ABABABE4E4E4D0D0D08A8A8A666666666666666666666666666666666666666666909090D4D4D4DFDFDFB4B4B49B9B9B9B9B9B9B9B9B9B9B9B9B9B9B9B9B9B9B9B9BB8B8B8E1E1E1EFEFEFE4E4E4DCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCE6E6E6EFEFEF" }
fn gx_arrow_hot_down() -> str { ret "EEEEEEE0E0E0D6D6D6D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D6D6D6E2E2E2EEEEEEDBDBDBAAAAAA909090909090909090909090909090909090909090AFAFAFDEDEDED2D2D28B8B8B666666666666666666666666666666666666666666929292D6D6D6E5E5E5AAAAAA727272666666666666666666666666666666747474B1B1B1E6E6E6F0F0F0D6D6D69494946A6A6A6666666666666666666A6A6A9B9B9BDADADAF0F0F0F0F0F0EEEEEEC4C4C4828282666666666666666666878787CACACAEEEEEEF0F0F0F0F0F0F0F0F0E7E7E7B0B0B0767676666666787878B7B7B7E8E8E8F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0DDDDDDB0B0B0989898B4B4B4DFDFDFF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0E5E5E5DCDCDCE7E7E7F0F0F0F0F0F0F0F0F0F0F0F0" }
fn gx_arrow_hot_w() -> f32 { ret 11.0 }
fn gx_arrow_hot_h() -> f32 { ret 9.0 }
fn gx_sort_up_h() -> f32 { ret 9.0 }
fn gx_list() -> str { ret "818181E4E4E4818181676767676767676767E4E4E4A9A9A9EDEDEDAAAAAA979797979797979797EDEDEDFFFFFFFFFFFF828282686868686868686868E4E4E4FFFFFFFFFFFFAAAAAA979797979797979797EDEDED828282E4E4E4828282686868686868686868E4E4E4A9A9A9EDEDEDAAAAAA979797979797979797EDEDEDFFFFFFFFFFFF828282686868686868686868E4E4E4FFFFFFFFFFFFAAAAAA979797979797979797EDEDED828282E5E5E5838383696969696969696969E5E5E5A8A8A8EDEDEDA9A9A9969696969696969696EDEDED" }
fn gx_list_w() -> f32 { ret 7.0 }
fn gx_list_h() -> f32 { ret 10.0 }
fn gx_funnel() -> str { ret "BBBBBB7676766B6B6B6B6B6B6B6B6B6B6B6B6B6B6B9E9E9EF0F0F0CDCDCD4B4B4B090909000000000000000000272727A7A7A7F4F4F4FEFEFEC1C1C13F3F3F0707070000001D1D1D989898F1F1F1FFFFFFFFFFFFFDFDFDB5B5B53333331919198A8A8AECECECFEFEFEFFFFFFFFFFFFFFFFFFF9F9F97F7F7F636363DDDDDDFEFEFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFA3A3A38D8D8DEBEBEBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFA3A3A38D8D8DEBEBEBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFA3A3A38D8D8DEBEBEBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFD8D8D8CFCFCFF6F6F6FFFFFFFFFFFFFFFFFF" }
fn gx_funnel_w() -> f32 { ret 9.0 }
fn gx_funnel_h() -> f32 { ret 9.0 }
fn gx_row_arrow() -> str { ret "C4C4C4F2F2F2FFFFFFFFFFFFFFFFFFFFFFFF5B5B5BA1A1A1F2F2F2FFFFFFFFFFFFFFFFFF2D2D2D2E2E2EA1A1A1F2F2F2FFFFFFFFFFFF2D2D2D0000002E2E2EA1A1A1F2F2F2FFFFFF2D2D2D0000000000002E2E2EA1A1A1F2F2F22D2D2D000000000000030303757575EBEBEB2D2D2D0000000B0B0B606060C1C1C1F7F7F72D2D2D1A1A1A797979D6D6D6FBFBFBFFFFFF5B5B5B919191E5E5E5FDFDFDFFFFFFFFFFFFC7C7C7F1F1F1FEFEFEFFFFFFFFFFFFFFFFFF" }
fn gx_row_arrow_w() -> f32 { ret 6.0 }
fn gx_row_arrow_h() -> f32 { ret 10.0 }
fn gx_equals() -> str { ret "8686866B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6BE3E3E3A8A8A8949494949494949494949494949494949494949494949494EBEBEB8686866B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6BE3E3E3A7A7A7939393939393939393939393939393939393939393939393EBEBEB" }
fn gx_equals_w() -> f32 { ret 10.0 }
fn gx_equals_h() -> f32 { ret 4.0 }
fn gx_star() -> str { ret "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF8F8F8F6F6F6FDFDFDFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFEFEFECECECFBFBFBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFDFDECECECE8E8E8F8F8F8FEFEFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF6F6F6ECECECEBEBEBF2F2F2FDFDFDFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEDEDEDF1F1F1F2F2F2EBEBEBFBFBFBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFCFCFCE7E7E7F3F3F3F7F7F7E6E6E6F7F7F7FEFEFEFFFFFFFFFFFFFFFFFFFFFFFFEEEEEEEAEAEAEAEAEAEAEAEAEAEAEAE8E8E8E5E5E5F1F1F1F4F4F4E7E7E7E7E7E7E9E9E9EAEAEAEAEAEAEAEAEAEAEAEAF0F0F0E2E2E2DFDFDFE8E8E8EBEBEBEAEAEAEDEDEDF0F0F0F0F0F0EEEEEEEAEAEAEAEAEAE8E8E8E0E0E0DFDFDFEAEAEAFDFDFDF5F5F5EBEBEBE7E7E7EDEDEDF2F2F2F0F0F0ECECECEAEAEAE9E9E9EAEAEAE9E9E9E5E5E5E8E8E8F1F1F1FBFBFBFFFFFFFFFFFFF9F9F9F0F0F0E6E6E6EAEAEAE9E9E9E7E7E7E5E5E5E4E4E4E4E4E4E1E1E1EBEBEBF6F6F6FEFEFEFFFFFFFFFFFFFFFFFFFFFFFFFDFDFDE3E3E3E4E4E4E7E7E7E7E7E7E7E7E7E7E7E7E4E4E4DFDFDFF7F7F7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFEFEDCDCDCE5E5E5EAEAEAEBEBEBEBEBEBEAEAEAE8E8E8D7D7D7F6F6F6FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF8F8F8D8D8D8E9E9E9ECECECDFDFDFDCDCDCE8E8E8EDEDEDD5D5D5EFEFEFFDFDFDFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEDEDEDD9D9D9E2E2E2DBDBDBDCDCDCDDDDDDD9D9D9E2E2E2D8D8D8E5E5E5FBFBFBFFFFFFFFFFFFFFFFFFFCFCFCF9F9F9DFDFDFD2D2D2D3D3D3DADADAEBEBEBEFEFEFE0E0E0D5D5D5D1D1D1D8D8D8F2F2F2FBFBFBFEFEFEFEFEFEF7F7F7EEEEEED1D1D1CECECED8D8D8E6E6E6F0F0F0F2F2F2ECECECDFDFDFD1D1D1CCCCCCE6E6E6F4F4F4FCFCFCFEFEFEFBFBFBF6F6F6EAEAEAEBEBEBF3F3F3F6F6F6F8F8F8F8F8F8F7F7F7F5F5F5EEEEEEE8E8E8F3F3F3F9F9F9FDFDFD" }
fn gx_star_w() -> f32 { ret 16.0 }
fn gx_star_h() -> f32 { ret 17.0 }

// looks4-e: the navigator buttons, cut from the live capture (the lower grid, 23 rows): slot 0 First, 1 Previous page,
// 2 Previous, 3 Next, 4 Next page, 5 Last, 6 the editing grid's undo arrow, 7 the filter funnel. Disabled First, Previous
// page and Previous and the enabled Next, Next page, Last, undo and funnel are captured; the other two sets are their mirror
// images (not captured).
fn gx_nav(slot: usize, enabled: bool) -> str {
    if slot == 0usize && !enabled { ret "F0F0F0EEEEEEEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFEDEDEDF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F5F5F5EDEDEDEDEDEDF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4EBEBEBF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8ECECECF6F6F6F9F9F9F0F0F0ECECECEEEEEEF7F7F7F9F9F9F9F9F9F4F4F4EFEFEFF7F7F7F9F9F9F9F9F9F4F4F4EFEFEFF7F7F7F9F9F9F9F9F9ECECECF6F6F6F9F9F9DDDDDDDADADAD7D7D7F3F3F3F9F9F9F3F3F3E2E2E2D8D8D8F3F3F3F9F9F9F3F3F3E2E2E2D8D8D8F3F3F3F9F9F9F9F9F9ECECECF6F6F6F9F9F9D6D6D6E5E5E5D3D3D3F1F1F1F3F3F3E1E1E1DADADAD0D0D0F1F1F1F3F3F3E1E1E1D9D9D9D0D0D0F1F1F1F9F9F9F9F9F9ECECECF6F6F6F9F9F9D4D4D4E2E2E2D0D0D0EAEAEADEDEDED8D8D8E6E6E6D1D1D1EAEAEADEDEDED7D7D7E4E4E4D1D1D1F1F1F1F9F9F9F9F9F9ECECECF6F6F6F9F9F9D0D0D0DFDFDFCCCCCCD5D5D5D5D5D5E0E0E0E0E0E0CCCCCCD5D5D5D1D1D1D8D8D8DADADACBCBCBF0F0F0F9F9F9F9F9F9ECECECF6F6F6F9F9F9CCCCCCDBDBDBC8C8C8CDCDCDDADADAD0D0D0D4D4D4C6C6C6CACACAD0D0D0C3C3C3CACACAC4C4C4EFEFEFF9F9F9F9F9F9ECECECF6F6F6F9F9F9C9C9C9D8D8D8C4C4C4D2D2D2D0D0D0C4C4C4CCCCCCC1C1C1CBCBCBC8C8C8C2C2C2C8C8C8C1C1C1EFEFEFF9F9F9F9F9F9ECECECF6F6F6F9F9F9C5C5C5D5D5D5C0C0C0C5C5C5CDCDCDCCCCCCCECECEBEBEBEC5C5C5C9C9C9C9C9C9CBCBCBBDBDBDEEEEEEF9F9F9F9F9F9ECECECF6F6F6F9F9F9C1C1C1D1D1D1BBBBBBDDDDDDC9C9C9CACACAD2D2D2BBBBBBDDDDDDC9C9C9C7C7C7CFCFCFBABABAEDEDEDF9F9F9F9F9F9ECECECF6F6F6F9F9F9BEBEBED1D1D1B8B8B8ECECECE8E8E8C5C5C5C8C8C8B6B6B6ECECECE9E9E9C5C5C5C5C5C5B5B5B5ECECECF9F9F9F9F9F9ECECECF6F6F6F4F4F4BCBCBCC4C4C4B4B4B4E4E4E4EFEFEFDADADABCBCBCB1B1B1E4E4E4EFEFEFDBDBDBBDBDBDB2B2B2E7E7E7F8F8F8F9F9F9ECECECF6F6F6EEEEEECDCDCDC3C3C3C5C5C5DCDCDCE1E1E1E1E1E1D4D4D4C8C8C8DCDCDCE1E1E1E1E1E1D5D5D5C9C9C9E4E4E4F6F6F6F9F9F9ECECECF6F6F6F5F5F5F2F2F2F0F0F0EFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFF1F1F1F3F3F3F8F8F8F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECEEEEEEF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F1F1F1ECECECECECECEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3EFEFEFECECECEFEFEFEFEFEFEDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEFEFEFF0F0F0" }
    if slot == 0usize && enabled { ret "F0F0F0F0F0F0EDEDEDE7E7E7E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E5E5E5E6E6E6E9E9E9EFEFEFF0F0F0F0F0F0F0F0F0EBEBEBE2E2E2DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE6E6E6EFEFEFF0F0F0EDEDEDE2E2E2DFDFDFF3F3F3FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF8F8F8EAEAEADDDDDDE8E8E8F0F0F0E9E9E9DCDCDCF1F1F1FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFAFAFAE9E9E9DDDDDDF0F0F0E8E8E8DDDDDDFCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF0F0F0D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDF2F8FCD1E7F8CBE4F8DFEEFAFDFDFDFDFDFDF7FAFCE0EFFADFEEFAFDFDFDFDFDFDF7FAFCE1EFFADFEEFAFDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDDAEBF97ABDF077C0F29FCDF2FDFDFDF6FAFCD0E6F892C7F19FCDF2FDFDFDF6FAFCD0E6F892C7F19ECDF2FDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDD3E7F76DB8ED82CEF88BC1EDF6F9FCCFE5F68EC6EF6FBBEE8AC1EDF6F9FCCFE5F68EC6EF70BBEE8AC1EDFDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDD2E5F668B2E87BC6F480B9E7CEE3F48BC1EB79C4F182CEF680B9E7CEE3F48BC1EB7BC6F284D0F686BCE9FDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDD0E4F45FA8E06DB7EA67A7DE86BAE56BB5E67BC7F173BDEE67A7DD88BDE674BEED87D3FA79C3F183B7E4FDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDCFE2F2549CD558A3D9559BD55FA9DD60ADDE53A0D863ADE0579DD76BB5E67AC7F56FBBF272BDEE7FB2DEFDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDCDDFF04D95D04E9ED65196D05AA6D9489CD5459AD554A4D9559AD26BB6E565B5EC66B5EE6EB7EA7BACD8FDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDCCDEEE4491CD3E9FDB518FC765A1D34DA5DC3DA7E345A4DD518EC768A4D45EB0E35CB7EE62B2E777A7D3FDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDCADBEC398DCB2AA2E36598C9ADC8E25D9DCF3FA9E336A7E46598C9ADC8E2619ED052B1E54DAFE772A1CDFDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFDFDFDC9DAEA308AC91CA4E9709DC9EEF3F8ABC5DE5597C83599D66F9DC9EEF3F8ABC5DE5998C9419ED66E9CC8FDFDFDF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFAFAFAC4D2E03A84BC2694D47198BEEBEBEBDCDFE399B0C65182B27197BDEBEBEBDCDFE399B0C65282B2739AC0F6F6F6F1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDF6F6F6CDD4DA86A2BD789BBE9DAEC0D3D3D3D3D3D3C8CCCFA1B2C39DAEC0D3D3D3D3D3D3C8CCD0A3B4C5A5B6C7ECECECF1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFDFDFDFAFAFAF2F2F2EFEFEFEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECEEEEEEF1F1F1F6F6F6F1F1F1D8D8D8F0F0F0E7E7E7DCDCDCFCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF1F1F1D9D9D9F0F0F0E8E8E8DCDCDCF7F7F7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFAFAFAEBEBEBDBDBDBF0F0F0ECECECE0E0E0E6E6E6F7F7F7FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFAFAFAF0F0F0DFDFDFE3E3E3F0F0F0EFEFEFE8E8E8DCDCDCDFDFDFE5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5E3E3E3DEDEDEE0E0E0EEEEEEF0F0F0F0F0F0EFEFEFE8E8E8D6D6D6CECECECDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDD0D0D0DEDEDEEEEEEEF0F0F0F0F0F0" }
    if slot == 1usize && !enabled { ret "F0F0F0EEEEEEEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFEDEDEDF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F5F5F5EEEEEEEDEDEDF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5ECECECF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4EFEFEFF7F7F7F9F9F9F9F9F9F9F9F9F4F4F4EFEFEFF7F7F7F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4E2E2E2D8D8D8F2F2F2F9F9F9F9F9F9F4F4F4E2E2E2D8D8D8F2F2F2F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F3F3F3E1E1E1DBDBDBD1D1D1F1F1F1F9F9F9F3F3F3E1E1E1DADADAD0D0D0F1F1F1F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F2F2F2DFDFDFD8D8D8E7E7E7D1D1D1F0F0F0F2F2F2DFDFDFD7D7D7E5E5E5D1D1D1F0F0F0F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F2F2F2DCDCDCD5D5D5E1E1E1E2E2E2CCCCCCE9E9E9DCDCDCD1D1D1D8D8D8DADADACBCBCBEFEFEFF9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9DCDCDCD2D2D2DFDFDFD4D4D4D7D7D7C7C7C7D2D2D2CDCDCDD1D1D1C4C4C4C9C9C9C4C4C4EEEEEEF9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9D3D3D3D6D6D6D7D7D7CACACACFCFCFC2C2C2C8C8C8CDCDCDC9C9C9C4C4C4C8C8C8C1C1C1EEEEEEF9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9EBEBEBCDCDCDCFCFCFCFCFCFD1D1D1BFBFBFDFDFDFCDCDCDC9C9C9CBCBCBCDCDCDBEBEBEEDEDEDF9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9E9E9E9CACACACCCCCCD4D4D4BCBCBCECECECE9E9E9CACACAC7C7C7D0D0D0BBBBBBECECECF9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9E9E9E9C5C5C5C8C8C8B6B6B6EBEBEBF9F9F9E9E9E9C6C6C6C5C5C5B6B6B6EBEBEBF9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F8F8F8F7F7F7F4F4F4DEDEDEBEBEBEB1B1B1E3E3E3EFEFEFEFEFEFDBDBDBBDBDBDB2B2B2E5E5E5F8F8F8F9F9F9ECECECF6F6F6F9F9F9F9F9F9F7F7F7F3F3F3EEEEEEE8E8E8D8D8D8C8C8C8DCDCDCE1E1E1E1E1E1E1E1E1D5D5D5C9C9C9E3E3E3F6F6F6F9F9F9ECECECF6F6F6F9F9F9F9F9F9F8F8F8F7F7F7F4F4F4F2F2F2F1F1F1EFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFF0F0F0F3F3F3F8F8F8F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7ECECECEEEEEEF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F1F1F1ECECECECECECEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3EFEFEFECECECEFEFEFEFEFEFEDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEFEFEFF0F0F0" }
    if slot == 1usize && enabled { ret "F0F0F0F0F0F0EDEDEDE7E7E7E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E5E5E5E6E6E6E9E9E9EFEFEFF0F0F0F0F0F0F0F0F0EBEBEBE2E2E2DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE6E6E6EFEFEFF0F0F0EDEDEDE2E2E2DFDFDFF3F3F3FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF8F8F8EAEAEADDDDDDE8E8E8F0F0F0E9E9E9DCDCDCF1F1F1FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFAFAFAE9E9E9DDDDDDF0F0F0E8E8E8DCDCDCFCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF0F0F0D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF7FAFCE1EFFADFEEFAFDFDFDFDFDFDFDFDFDF7FAFCE1EFFADFEEFAFDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF7FAFCD1E7F893C7F19DCCF2FDFDFDFDFDFDF7FAFCD2E7F893C7F19DCCF2FDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDFDFDFDFDFDFDF6F9FCD0E5F68FC6EF70BBEE88C0EDFDFDFDF6F9FCD0E5F68FC6EF70BBEE88C0EDFDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDFDFDFDF6F9FCCEE3F48BC1EB79C4F184D0F685BCE8F6F9FCCFE3F48CC2EB7BC6F286D1F784BBE8FDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDF6F9FBCDE1F285BAE468B2E477C3ED72BCEC7AB3E2CEE1F288BDE674BEED89D5FA7BC6F381B6E3FDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDE0ECF680B4DF5BA6DB5AA8DB4A98D25CA8DC61A0D782B6E068B2E475C3F16EBBF174BEEE7DB1DEFDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDD8E6F369A5D753A2D8409CD83E9BD84EA3DB5595CE6EA9D965B2E254ACE457B0EA69B7EA78ABD8FDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDEFF4F9B0CCE662A0D340A3DE2DA9E939A5E2689DCFB1CDE667A4D453AFE340B2ED50B0E874A5D2FDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDFDFDFDEFF4F8AEC9E2599CD02DA8E726A8EA71A0CDEFF4F8AFC9E25F9FD045B2E93AB0EB70A0CDFDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDFDFDFDFDFDFDEFF3F8ACC6DE5296C92A98D86D9BC8FDFDFDEFF3F8ACC6DE5898C93B9ED86C9BC8FDFDFDFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDFCFCFCF9F9F9F5F5F5E3E6EA9DB3C95282B26F96BDEBEBEBEBEBEBDDE0E39AB1C65283B37198BFF6F6F6FDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDFAFAFAF3F3F3EBEBEBE2E2E2D0D3D7A3B4C49CAEC0D3D3D3D3D3D3D3D3D3C9CDD0A4B5C5A4B6C7ECECECFDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DCDCDCFDFDFDFDFDFDFCFCFCF9F9F9F6F6F6F2F2F2EFEFEFEDEDEDECECECECECECECECECECECECECECECEEEEEEF1F1F1F6F6F6FDFDFDF2F2F2D8D8D8F0F0F0E8E8E8DBDBDBFCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF1F1F1D8D8D8F0F0F0E9E9E9DCDCDCF6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFBFBFBEBEBEBDBDBDBF0F0F0ECECECE0E0E0E6E6E6F7F7F7FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFAFAFAF0F0F0DFDFDFE3E3E3F0F0F0EFEFEFE9E9E9DCDCDCDFDFDFE5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5E3E3E3DEDEDEE0E0E0EEEEEEF0F0F0F0F0F0EFEFEFE8E8E8D6D6D6CECECECDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDD0D0D0DEDEDEEEEEEEF0F0F0F0F0F0" }
    if slot == 2usize && !enabled { ret "F0F0F0EEEEEEEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFEDEDEDF2F2F2F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F5F5F5EEEEEEEDEDEDF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5ECECECF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4EFEFEFF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4E3E3E3D9D9D9F2F2F2F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F3F3F3E2E2E2DBDBDBD1D1D1F0F0F0F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F3F3F3E0E0E0D9D9D9E6E6E6D2D2D2F0F0F0F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F2F2F2DFDFDFD7D7D7E2E2E2E4E4E4CFCFCFEFEFEFF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F2F2F2DDDDDDD4D4D4DFDFDFD9D9D9DDDDDDCCCCCCEFEFEFF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9DDDDDDD1D1D1DCDCDCD4D4D4CFCFCFD5D5D5C7C7C7EEEEEEF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9D4D4D4D4D4D4D4D4D4CACACAC4C4C4CACACAC1C1C1EDEDEDF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBCECECECCCCCCC9C9C9C4C4C4C9C9C9BEBEBEECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EAEAEACBCBCBC9C9C9CCCCCCCDCDCDBCBCBCEBEBEBF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9E9E9E9C9C9C9C7C7C7D1D1D1BABABAEBEBEBF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9E8E8E8C5C5C5C6C6C6B5B5B5EAEAEAF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6F4F4F4F2F2F2DDDDDDBEBEBEB1B1B1E6E6E6F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F3F3F3ECECECE8E8E8E5E5E5D6D6D6C8C8C8E4E4E4F6F6F6F9F9F9F9F9F9F9F9F9F9F9F9ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F6F6F6F4F4F4F2F2F2F1F1F1EFEFEFEFEFEFF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9ECECECF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7ECECECEEEEEEF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F1F1F1ECECECECECECEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F0F0F0ECECECEFEFEFEFEFEFEDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEFEFEFF0F0F0" }
    if slot == 2usize && enabled { ret "F0F0F0F0F0F0EDEDEDE7E7E7E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E5E5E5E6E6E6E9E9E9EFEFEFF0F0F0F4F4F4F0F0F0ECECECE2E2E2DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE5E5E5EFEFEFF4F4F4EDEDEDE2E2E2DFDFDFF3F3F3FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF9F9F9EAEAEADDDDDDE8E8E8F4F4F4EAEAEADCDCDCF1F1F1FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFAFAFAEAEAEADCDCDCF4F4F4E8E8E8DCDCDCFCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF7FAFCE1EFFADEEEFAFDFDFDFDFDFDFDFDFDFDFDFDF1F1F1D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF7FAFCD3E8F893C7F19BCCF2FDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF7FAFCD2E6F790C7F071BDEF87C0EDFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF7FAFCD0E5F58EC4ED7BC6F286D2F884BCEAFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF7F9FCCFE3F48AC0E974BFEF86D2FA7BC6F381B8E6FDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF6F9FBCEE1F286BAE46BB5E777C3F16CB8F074BFEF7EB4E1FDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE2EDF682B5DF60AADE64B1E2529EDA5EAAE36BB6E97AAFDDFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBE8F46CA7D75DA8DB499DD63E94D1469BD65AAADF76AAD7FDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF0F5F9B2CDE666A2D350A7DD38A4E133A1E148A6E073A5D2FDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF0F5F9B0CBE4609ED03EA9E328AFF135A9E770A0CEFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF0F4F8AEC9E2599ACE32ABE929ACEC6C9BC9FDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDEFF4F8ACC5DE5494C72F9AD86997C5FDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF9F9F9F4F4F4F1F1F1E0E4E79CB1C75182B27098BFFBFBFBFDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4E8E8E8E1E1E1DADADACBCED2A3B3C4A6B8CAF8F8F8FDFDFDFDFDFDFDFDFDF2F2F2D7D7D7F4F4F4E8E8E8DBDBDBFCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF9F9F9F5F5F5F2F2F2EFEFEFEDEDEDEDEDEDF1F1F1FBFBFBFDFDFDFDFDFDFDFDFDF2F2F2D8D8D8F4F4F4E9E9E9DBDBDBF6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFBFBFBECECECDBDBDBF4F4F4ECECECE0E0E0E6E6E6F7F7F7FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFBFBFBF1F1F1DFDFDFE3E3E3F4F4F4EFEFEFE9E9E9DCDCDCDFDFDFE5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5E3E3E3DEDEDEDFDFDFEEEEEEF4F4F4F0F0F0EFEFEFE8E8E8D6D6D6CECECECDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDD0D0D0DEDEDEEEEEEEF0F0F0F4F4F4" }
    if slot == 3usize && !enabled { ret "F0F0F0EFEFEFEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEEEEEEEEEEEEF0F0F0EFEFEFEDEDEDEEEEEEEEEEEEEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEDEDEDEEEEEEEDEDEDEEEEEEF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F2F2F2EDEDEDECECECF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F2F2F2ECECECF8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7EFEFEFF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F2F2F2D9D9D9E3E3E3F4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F0F0F0D1D1D1DBDBDBE2E2E2F3F3F3F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F0F0F0D2D2D2E6E6E6D9D9D9E0E0E0F3F3F3F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EFEFEFCFCFCFE4E4E4E2E2E2D7D7D7DFDFDFF2F2F2F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EFEFEFCCCCCCDDDDDDD9D9D9DFDFDFD4D4D4DDDDDDF2F2F2F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EEEEEEC7C7C7D5D5D5CFCFCFD4D4D4DCDCDCD1D1D1DDDDDDF9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDC1C1C1CACACAC4C4C4CACACAD4D4D4D4D4D4D4D4D4F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECBEBEBEC9C9C9C4C4C4C9C9C9CCCCCCCECECEEBEBEBF9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBBCBCBCCDCDCDCCCCCCC9C9C9CBCBCBEAEAEAF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBBABABAD1D1D1C7C7C7C9C9C9E9E9E9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EAEAEAB5B5B5C6C6C6C5C5C5E8E8E8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F8F8F8E6E6E6B1B1B1BEBEBEDDDDDDF2F2F2F4F4F4F6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F6F6F6E4E4E4C8C8C8D6D6D6E5E5E5E8E8E8ECECECF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F3F3F3EFEFEFEFEFEFF1F1F1F2F2F2F4F4F4F6F6F6F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F3F3F3ECECECF1F1F1F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F5F5F5EEEEEEEFEFEFECECECF0F0F0F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F2F2F2EFEFEFECECECF0F0F0EFEFEFECECECECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECEDEDEDEFEFEF" }
    if slot == 3usize && enabled { ret "F4F4F4F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0F4F4F4EFEFEFE5E5E5DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2ECECECF0F0F0F4F4F4E8E8E8DDDDDDEAEAEAF9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3DFDFDFE2E2E2EDEDEDF4F4F4DCDCDCEAEAEAFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF1F1F1DCDCDCEAEAEAF4F4F4D7D7D7F1F1F1FDFDFDFDFDFDFDFDFDFDFDFDDEEEFAE1EFFAF7FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDCDCDCE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD9BCCF293C7F1D3E8F8F7FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD87C0ED71BDEF90C7F0D2E6F7F7FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD84BCEA86D2F87BC6F28EC4EDD0E5F5F7FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD81B8E67BC6F386D2FA74BFEF8AC0E9CFE3F4F7F9FCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD7EB4E174BFEF6CB8F077C3F16BB5E786BAE4CEE1F2F6F9FBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD7AAFDD6BB6E95EAAE3529EDA64B1E260AADE82B5DFE2EDF6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD76AAD75AAADF469BD63E94D1499DD65DA8DB6CA7D7DBE8F4FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD73A5D248A6E033A1E138A4E150A7DD66A2D3B2CDE6F0F5F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD70A0CE35A9E728AFF13EA9E3609ED0B0CBE4F0F5F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD6C9BC929ACEC32ABE9599ACEAEC9E2F0F4F8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFD6997C52F9AD85494C7ACC5DEEFF4F8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFBFBFB7098BF5182B29CB1C7E0E4E7F1F1F1F4F4F4F9F9F9FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDF8F8F8A6B8CAA3B3C4CBCED2DADADAE1E1E1E8E8E8F4F4F4FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8F4F4F4D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFBFBFBF1F1F1EDEDEDEDEDEDEFEFEFF2F2F2F5F5F5F9F9F9FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDBDBDBE8E8E8F4F4F4DBDBDBECECECFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF6F6F6DBDBDBE9E9E9F4F4F4E3E3E3DFDFDFF1F1F1FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF7F7F7E6E6E6E0E0E0ECECECF4F4F4EEEEEEDFDFDFDEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDCDCDCE9E9E9EFEFEFF4F4F4F0F0F0EEEEEEDEDEDED0D0D0CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED6D6D6E8E8E8EFEFEFF0F0F0" }
    if slot == 4usize && !enabled { ret "F0F0F0EFEFEFEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEEEEEEEEEEEEF0F0F0EFEFEFEDEDEDEEEEEEEEEEEEEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEDEDEDEEEEEEEDEDEDEEEEEEF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F3F3F3EDEDEDECECECF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F2F2F2ECECECF8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5ECECECF9F9F9F9F9F9F7F7F7EFEFEFF4F4F4F9F9F9F9F9F9F9F9F9F7F7F7EFEFEFF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F2F2F2D8D8D8E2E2E2F4F4F4F9F9F9F9F9F9F2F2F2D8D8D8E2E2E2F4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F1F1F1D0D0D0DADADAE1E1E1F3F3F3F9F9F9F1F1F1D1D1D1DBDBDBE1E1E1F3F3F3F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F0F0F0D1D1D1E5E5E5D7D7D7DFDFDFF2F2F2F0F0F0D1D1D1E7E7E7D8D8D8DFDFDFF2F2F2F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9EFEFEFCBCBCBDADADAD8D8D8D1D1D1DCDCDCE9E9E9CCCCCCE2E2E2E1E1E1D5D5D5DCDCDCF2F2F2F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9EEEEEEC4C4C4C9C9C9C4C4C4D1D1D1CDCDCDD2D2D2C7C7C7D7D7D7D4D4D4DFDFDFD2D2D2DCDCDCF9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9EEEEEEC1C1C1C8C8C8C4C4C4C9C9C9CDCDCDC8C8C8C2C2C2CFCFCFCACACAD7D7D7D6D6D6D3D3D3F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9EDEDEDBEBEBECDCDCDCBCBCBC9C9C9CDCDCDDFDFDFBFBFBFD1D1D1CFCFCFCFCFCFCDCDCDEBEBEBF9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9ECECECBBBBBBD0D0D0C7C7C7CACACAE9E9E9ECECECBCBCBCD4D4D4CCCCCCCACACAE9E9E9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9EBEBEBB6B6B6C5C5C5C6C6C6E9E9E9F9F9F9EBEBEBB6B6B6C8C8C8C5C5C5E9E9E9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F8F8F8E5E5E5B2B2B2BDBDBDDBDBDBEFEFEFEFEFEFE3E3E3B1B1B1BEBEBEDEDEDEF4F4F4F7F7F7F8F8F8F9F9F9F9F9F9F6F6F6ECECECF9F9F9F6F6F6E3E3E3C9C9C9D5D5D5E1E1E1E1E1E1E1E1E1DCDCDCC8C8C8D8D8D8E8E8E8EEEEEEF3F3F3F7F7F7F9F9F9F9F9F9F6F6F6ECECECF9F9F9F8F8F8F3F3F3F0F0F0EFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFF1F1F1F2F2F2F4F4F4F7F7F7F8F8F8F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F3F3F3ECECECF1F1F1F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F5F5F5EEEEEEEFEFEFECECECEFEFEFF3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F2F2F2EFEFEFECECECF0F0F0EFEFEFECECECECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECEDEDEDEFEFEF" }
    if slot == 4usize && enabled { ret "F0F0F0F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0F0F0F0EFEFEFE6E6E6DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2EBEBEBF0F0F0F0F0F0E8E8E8DDDDDDEAEAEAF8F8F8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3DFDFDFE2E2E2EDEDEDF0F0F0DDDDDDE9E9E9FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF1F1F1DCDCDCE9E9E9F0F0F0D8D8D8F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFDDFEEFAE1EFFAF7FAFCFDFDFDFDFDFDFDFDFDDFEEFAE1EFFAF7FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFD9DCCF293C7F1D2E7F8F7FAFCFDFDFDFDFDFD9DCCF293C7F1D1E7F8F7FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFD88C0ED70BBEE8FC6EFD0E5F6F6F9FCFDFDFD88C0ED70BBEE8FC6EFD0E5F6F6F9FCFDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFD84BBE886D1F77BC6F28CC2EBCFE3F4F6F9FC85BCE884D0F679C4F18BC1EBCEE3F4F6F9FCFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFD81B6E37BC6F389D5FA74BEED88BDE6CEE1F27AB3E272BCEC77C3ED68B2E485BAE4CDE1F2F6F9FBFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFD7DB1DE74BEEE6EBBF175C3F168B2E482B6E061A0D75CA8DC4A98D25AA8DB5BA6DB80B4DFE0ECF6FDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFD78ABD869B7EA57B0EA54ACE465B2E26EA9D95595CE4EA3DB3E9BD8409CD853A2D869A5D7D8E6F3FDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFD74A5D250B0E840B2ED53AFE367A4D4B1CDE6689DCF39A5E22DA9E940A3DE62A0D3B0CCE6EFF4F9FDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFD70A0CD3AB0EB45B2E95F9FD0AFC9E2EFF4F871A0CD26A8EA2DA8E7599CD0AEC9E2EFF4F8FDFDFDFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFD6C9BC83B9ED85898C9ACC6DEEFF3F8FDFDFD6D9BC82A98D85296C9ACC6DEEFF3F8FDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDF6F6F67198BF5283B39AB1C6DDE0E3EBEBEBEBEBEB6F96BD5282B29DB3C9E3E6EAF5F5F5F9F9F9FCFCFCFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDECECECA4B6C7A4B5C5C9CDD0D3D3D3D3D3D3D3D3D39CAEC0A3B4C4D0D3D7E2E2E2EBEBEBF3F3F3FAFAFAFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDF6F6F6F1F1F1EEEEEEECECECECECECECECECECECECECECECEDEDEDEFEFEFF2F2F2F6F6F6F9F9F9FCFCFCFDFDFDFDFDFDDCDCDCE8E8E8F0F0F0D8D8D8F1F1F1FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDBDBDBE8E8E8F0F0F0DBDBDBEBEBEBFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF6F6F6DCDCDCE9E9E9F0F0F0E3E3E3DFDFDFF0F0F0FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF7F7F7E6E6E6E0E0E0ECECECF0F0F0EEEEEEE0E0E0DEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDCDCDCE9E9E9EFEFEFF0F0F0F0F0F0EEEEEEDEDEDED0D0D0CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED6D6D6E8E8E8EFEFEFF0F0F0" }
    if slot == 5usize && !enabled { ret "F0F0F0EFEFEFEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEEEEEEEEEEEEF0F0F0EFEFEFEDEDEDEEEEEEEEEEEEEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEDEDEDEEEEEEEDEDEDEDEDEDF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F3F3F3EDEDEDEBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F2F2F2ECECECF8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF9F9F9F9F9F9F7F7F7EFEFEFF4F4F4F9F9F9F9F9F9F7F7F7EFEFEFF4F4F4F9F9F9F9F9F9F7F7F7EEEEEEECECECF0F0F0F9F9F9F6F6F6ECECECF9F9F9F9F9F9F3F3F3D8D8D8E2E2E2F3F3F3F9F9F9F3F3F3D8D8D8E2E2E2F3F3F3F9F9F9F3F3F3D7D7D7DADADADDDDDDF9F9F9F6F6F6ECECECF9F9F9F9F9F9F1F1F1D0D0D0D9D9D9E1E1E1F3F3F3F1F1F1D0D0D0DADADAE1E1E1F3F3F3F1F1F1D3D3D3E5E5E5D6D6D6F9F9F9F6F6F6ECECECF9F9F9F9F9F9F1F1F1D1D1D1E4E4E4D7D7D7DEDEDEEAEAEAD1D1D1E6E6E6D8D8D8DEDEDEEAEAEAD0D0D0E2E2E2D4D4D4F9F9F9F6F6F6ECECECF9F9F9F9F9F9F0F0F0CBCBCBDADADAD8D8D8D1D1D1D5D5D5CCCCCCE0E0E0E0E0E0D5D5D5D5D5D5CCCCCCDFDFDFD0D0D0F9F9F9F6F6F6ECECECF9F9F9F9F9F9EFEFEFC4C4C4CACACAC3C3C3D0D0D0CACACAC6C6C6D4D4D4D0D0D0DADADACDCDCDC8C8C8DBDBDBCCCCCCF9F9F9F6F6F6ECECECF9F9F9F9F9F9EFEFEFC1C1C1C8C8C8C2C2C2C8C8C8CBCBCBC1C1C1CCCCCCC4C4C4D0D0D0D2D2D2C4C4C4D8D8D8C9C9C9F9F9F9F6F6F6ECECECF9F9F9F9F9F9EEEEEEBDBDBDCBCBCBC9C9C9C9C9C9C5C5C5BEBEBECECECECCCCCCCDCDCDC5C5C5C0C0C0D5D5D5C5C5C5F9F9F9F6F6F6ECECECF9F9F9F9F9F9EDEDEDBABABACFCFCFC7C7C7C9C9C9DDDDDDBBBBBBD2D2D2CACACAC9C9C9DDDDDDBBBBBBD1D1D1C1C1C1F9F9F9F6F6F6ECECECF9F9F9F9F9F9ECECECB5B5B5C5C5C5C5C5C5E9E9E9ECECECB6B6B6C8C8C8C5C5C5E8E8E8ECECECB8B8B8D1D1D1BEBEBEF9F9F9F6F6F6ECECECF9F9F9F8F8F8E7E7E7B2B2B2BDBDBDDBDBDBEFEFEFE4E4E4B1B1B1BCBCBCDADADAEFEFEFE4E4E4B4B4B4C4C4C4BCBCBCF4F4F4F6F6F6ECECECF9F9F9F6F6F6E4E4E4C9C9C9D5D5D5E1E1E1E1E1E1DCDCDCC8C8C8D4D4D4E1E1E1E1E1E1DCDCDCC5C5C5C3C3C3CDCDCDEEEEEEF6F6F6ECECECF9F9F9F8F8F8F3F3F3F1F1F1EFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFF0F0F0F2F2F2F5F5F5F6F6F6ECECECF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F4F4F4ECECECF1F1F1F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F5F5F5EEEEEEEFEFEFECECECEFEFEFF3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F2F2F2EFEFEFECECECF0F0F0EFEFEFECECECECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECEDEDEDEFEFEF" }
    if slot == 5usize && enabled { ret "F0F0F0F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0F0F0F0EFEFEFE6E6E6DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2EBEBEBF0F0F0F0F0F0E8E8E8DDDDDDEAEAEAF8F8F8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3DFDFDFE2E2E2EDEDEDF0F0F0DDDDDDE9E9E9FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF1F1F1DCDCDCE9E9E9F0F0F0D8D8D8F0F0F0FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDDDDDDE8E8E8F0F0F0D8D8D8F1F1F1FDFDFDDFEEFAE1EFFAF7FAFCFDFDFDFDFDFDDFEEFAE0EFFAF7FAFCFDFDFDFDFDFDDFEEFACBE4F8D1E7F8F2F8FCFDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1FDFDFD9ECDF292C7F1D0E6F8F6FAFCFDFDFD9FCDF292C7F1D0E6F8F6FAFCFDFDFD9FCDF277C0F27ABDF0DAEBF9FDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1FDFDFD8AC1ED70BBEE8EC6EFCFE5F6F6F9FC8AC1ED6FBBEE8EC6EFCFE5F6F6F9FC8BC1ED82CEF86DB8EDD3E7F7FDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1FDFDFD86BCE984D0F67BC6F28BC1EBCEE3F480B9E782CEF679C4F18BC1EBCEE3F480B9E77BC6F468B2E8D2E5F6FDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1FDFDFD83B7E479C3F187D3FA74BEED88BDE667A7DD73BDEE7BC7F16BB5E686BAE567A7DE6DB7EA5FA8E0D0E4F4FDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1FDFDFD7FB2DE72BDEE6FBBF27AC7F56BB5E6579DD763ADE053A0D860ADDE5FA9DD559BD558A3D9549CD5CFE2F2FDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1FDFDFD7BACD86EB7EA66B5EE65B5EC6BB6E5559AD254A4D9459AD5489CD55AA6D95196D04E9ED64D95D0CDDFF0FDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1FDFDFD77A7D362B2E75CB7EE5EB0E368A4D4518EC745A4DD3DA7E34DA5DC65A1D3518FC73E9FDB4491CDCCDEEEFDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1FDFDFD72A1CD4DAFE752B1E5619ED0ADC8E26598C936A7E43FA9E35D9DCFADC8E26598C92AA2E3398DCBCADBECFDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1FDFDFD6E9CC8419ED65998C9ABC5DEEEF3F86F9DC93599D65597C8ABC5DEEEF3F8709DC91CA4E9308AC9C9DAEAFDFDFDFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1F6F6F6739AC05282B299B0C6DCDFE3EBEBEB7197BD5182B299B0C6DCDFE3EBEBEB7198BE2694D43A84BCC4D2E0FAFAFAFDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1ECECECA5B6C7A3B4C5C8CCD0D3D3D3D3D3D39DAEC0A1B2C3C8CCCFD3D3D3D3D3D39DAEC0789BBE86A2BDCDD4DAF6F6F6FDFDFDDCDCDCE7E7E7F0F0F0D8D8D8F1F1F1F6F6F6F1F1F1EEEEEEECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEFEFEFF2F2F2FAFAFAFDFDFDDCDCDCE7E7E7F0F0F0D9D9D9F1F1F1FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDCDCDCE7E7E7F0F0F0DBDBDBEBEBEBFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF7F7F7DCDCDCE8E8E8F0F0F0E3E3E3DFDFDFF0F0F0FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF7F7F7E6E6E6E0E0E0ECECECF0F0F0EEEEEEE0E0E0DEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDCDCDCE8E8E8EFEFEFF0F0F0F0F0F0EEEEEEDEDEDED0D0D0CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED6D6D6E8E8E8EFEFEFF0F0F0" }
    if slot == 6usize && !enabled { ret "F0F0F0F0F0F0F0F0F0EFEFEFEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0EEEEEEEDEDEDF2F2F2F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EEEEEEEDEDEDEFEFEFF0F0F0F0F0F0ECECECF1F1F1F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5ECECECEEEEEEF0F0F0F0F0F0EBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F1F1F1EFEFEFF6F6F6F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9DEDEDEC0C0C0E0E0E0F6F6F6F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F2F2F2E0E0E0D6D6D6D5D5D5D5D5D5D5D5D5BDBDBD818181A3A3A3E0E0E0F6F6F6F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5EFEFEFC5C5C59999998686868383838383838383837D7D7D6C6C6C6B6B6BAAAAAAE9E9E9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5C9C9C97E7E7E6D6D6D7B7B7B8080808080808080807A7A7A6B6B6B6C6C6C9C9C9CE4E4E4F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F59D9D9D6C6C6C8F8F8FBDBDBDC9C9C9C9C9C9C9C9C9B4B4B4808080969696DBDBDBF7F7F7F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F59898986A6A6AB2B2B2EDEDEDF9F9F9F9F9F9F9F9F9DEDEDEB2B2B2DBDBDBF7F7F7F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5BEBEBE7C7C7C9B9B9BE3E3E3F9F9F9F9F9F9F9F9F9EEEEEEEFEFEFF7F7F7F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5EFEFEFB6B6B6979797C7C7C7EFEFEFF8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F5F5F5D6D6D6C8C8C8E8E8E8F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0ECECECF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7EDEDEDEEEEEEF0F0F0F0F0F0EDEDEDEEEEEEF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F1F1F1EDEDEDEFEFEFF0F0F0F0F0F0F0F0F0EDEDEDEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F0F0F0EDEDEDEEEEEEF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0EDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEEEEEEF0F0F0F0F0F0F0F0F0" }
    if slot == 6usize && enabled { ret "F0F0F0F0F0F0F0F0F0EFEFEFEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0EEEEEEEDEDEDF2F2F2F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EEEEEEEDEDEDEFEFEFF0F0F0F0F0F0ECECECF1F1F1F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5ECECECEEEEEEF0F0F0F0F0F0EBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F1F1F1EFEFEFF6F6F6F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9DEDEDEC0C0C0E0E0E0F6F6F6F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F2F2F2E0E0E0D6D6D6D5D5D5D5D5D5D5D5D5BDBDBD818181A3A3A3E0E0E0F6F6F6F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5EFEFEFC5C5C59999998686868383838383838383837D7D7D6C6C6C6B6B6BAAAAAAE9E9E9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5C9C9C97E7E7E6D6D6D7B7B7B8080808080808080807A7A7A6B6B6B6C6C6C9C9C9CE4E4E4F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F59D9D9D6C6C6C8F8F8FBDBDBDC9C9C9C9C9C9C9C9C9B4B4B4808080969696DBDBDBF7F7F7F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F59898986A6A6AB2B2B2EDEDEDF9F9F9F9F9F9F9F9F9DEDEDEB2B2B2DBDBDBF7F7F7F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5BEBEBE7C7C7C9B9B9BE3E3E3F9F9F9F9F9F9F9F9F9EEEEEEEFEFEFF7F7F7F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5EFEFEFB6B6B6979797C7C7C7EFEFEFF8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F5F5F5D6D6D6C8C8C8E8E8E8F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0ECECECF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7EDEDEDEEEEEEF0F0F0F0F0F0EDEDEDEEEEEEF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F1F1F1EDEDEDEFEFEFF0F0F0F0F0F0F0F0F0EDEDEDEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F0F0F0EDEDEDEEEEEEF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0EDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEEEEEEF0F0F0F0F0F0F0F0F0" }
    if slot == 7usize && !enabled { ret "F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0EFEFEFE6E6E6DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2EBEBEBF0F0F0E9E9E9DEDEDEE9E9E9F8F8F8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4E0E0E0E1E1E1EDEDEDDEDEDEE8E8E8F9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2DDDDDDE8E8E8D9D9D9EFEFEFFCFCFCF0F0F0E3E3E3DCDCDCD9D9D9D8D8D8D3D3D3CECECECECECED1D1D1D6D6D6DADADADFDFDFE7E7E7F7F7F7FDFDFDFCFCFCDEDEDEE7E7E7D9D9D9F0F0F0FDFDFDD4D4D4C1C1C1B9B9B9B2B2B2ADADADA1A1A29191958F8F9598989FA5A5ABB2B2B9BEBEC4C1C1C3EBEBEBFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDCCCCCCCBCBCBD7D7D7D2D2D2C8C8C8BDBDBFABABB5A8A8B6B2B2C1C0C0CFCFCFDDD3D3DFBEBEC2E8E8E8FDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDDDDDDDB5B5B5C3C3C3C2C2C2B4B4B4A8A8A996969E94949FA0A0ACB2B2BEC2C2CEB4B4B7C5C5C5F0F0F0FDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDCFCFCFC5C5C5CECECEC4C4C4B9B9BAA4A4AFA1A1B3B2B2C4C5C5D7C7C7D4C1C1C4EBEBEBFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDEFEFEFC1C1C1BABABAC3C3C3BFBFC0A7A7B1A5A5B6B9B9CBBABAC8B6B6B9DBDBDBF7F7F7FDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDEDEDEDBFBFBFB5B5B5BFBFC0ABABB4ABABBBAFAFBCACACAFD6D6D6F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDECECECBCBCBCAEAEAEABABB4A2A2AEA0A0A3D0D0D0F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDEBEBEB9F9F9FA7A7B18C8C90C3C3C3F5F5F5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA6A6A6A7A7B18C8C90D7D7D7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA7A7A7A7A7B18C8C91D7D7D7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA8A8A8A7A7B28F8F93D8D8D8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDACACACA9A9B4939397DADADAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFCFCFCF9F9F9F5F5F5F4F4F4A9A9A9ACACB796969AD4D4D4F4F4F4F6F6F6FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6DADADAF0F0F0FDFDFDFDFDFDFAFAFAEEEEEEDFDFDFDBDBDB9C9C9C9E9EA59A9A9DC6C6C6DADADAE3E3E3F2F2F2FBFBFBFDFDFDFDFDFDFCFCFCDDDDDDE6E6E6DCDCDCEAEAEAFAFAFAFDFDFDFBFBFBEEEEEEE0E0E0DCDCDCB8B8B8A8A8A8C1C1C1D7D7D7DCDCDCE4E4E4F3F3F3FBFBFBFDFDFDFDFDFDF7F7F7DDDDDDE8E8E8E4E4E4DFDFDFEFEFEFFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF7F7F7E7E7E7E0E0E0EBEBEBEEEEEEE0E0E0DEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDCDCDCE8E8E8EFEFEFF0F0F0EEEEEEDFDFDFD1D1D1CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED5D5D5E7E7E7EFEFEFF0F0F0" }
    if slot == 7usize && enabled { ret "F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0EFEFEFE6E6E6DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2EBEBEBF0F0F0E9E9E9DEDEDEE9E9E9F8F8F8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4E0E0E0E1E1E1EDEDEDDEDEDEE8E8E8F9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2DDDDDDE8E8E8D9D9D9EFEFEFFCFCFCF0F0F0E3E3E3DCDCDCD9D9D9D8D8D8D3D3D3CECECECECECED1D1D1D6D6D6DADADADFDFDFE7E7E7F7F7F7FDFDFDFCFCFCDEDEDEE7E7E7D9D9D9F0F0F0FDFDFDD4D4D4C1C1C1B9B9B9B2B2B2ADADADA1A1A29191958F8F9598989FA5A5ABB2B2B9BEBEC4C1C1C3EBEBEBFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDCCCCCCCBCBCBD7D7D7D2D2D2C8C8C8BDBDBFABABB5A8A8B6B2B2C1C0C0CFCFCFDDD3D3DFBEBEC2E8E8E8FDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDDDDDDDB5B5B5C3C3C3C2C2C2B4B4B4A8A8A996969E94949FA0A0ACB2B2BEC2C2CEB4B4B7C5C5C5F0F0F0FDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDCFCFCFC5C5C5CECECEC4C4C4B9B9BAA4A4AFA1A1B3B2B2C4C5C5D7C7C7D4C1C1C4EBEBEBFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDEFEFEFC1C1C1BABABAC3C3C3BFBFC0A7A7B1A5A5B6B9B9CBBABAC8B6B6B9DBDBDBF7F7F7FDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDEDEDEDBFBFBFB5B5B5BFBFC0ABABB4ABABBBAFAFBCACACAFD6D6D6F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDECECECBCBCBCAEAEAEABABB4A2A2AEA0A0A3D0D0D0F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDEBEBEB9F9F9FA7A7B18C8C90C3C3C3F5F5F5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA6A6A6A7A7B18C8C90D7D7D7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA7A7A7A7A7B18C8C91D7D7D7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA8A8A8A7A7B28F8F93D8D8D8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDACACACA9A9B4939397DADADAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFCFCFCF9F9F9F5F5F5F4F4F4A9A9A9ACACB796969AD4D4D4F4F4F4F6F6F6FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6DADADAF0F0F0FDFDFDFDFDFDFAFAFAEEEEEEDFDFDFDBDBDB9C9C9C9E9EA59A9A9DC6C6C6DADADAE3E3E3F2F2F2FBFBFBFDFDFDFDFDFDFCFCFCDDDDDDE6E6E6DCDCDCEAEAEAFAFAFAFDFDFDFBFBFBEEEEEEE0E0E0DCDCDCB8B8B8A8A8A8C1C1C1D7D7D7DCDCDCE4E4E4F3F3F3FBFBFBFDFDFDFDFDFDF7F7F7DDDDDDE8E8E8E4E4E4DFDFDFEFEFEFFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF7F7F7E7E7E7E0E0E0EBEBEBEEEEEEE0E0E0DEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDCDCDCE8E8E8EFEFEFF0F0F0EEEEEEDFDFDFD1D1D1CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED5D5D5E7E7E7EFEFEFF0F0F0" }
    ret ""
}
fn gx_nav_w(slot: usize, enabled: bool) -> f32 {
    if slot == 0usize && !enabled { ret 19.0 }
    if slot == 0usize && enabled { ret 22.0 }
    if slot == 1usize && !enabled { ret 19.0 }
    if slot == 1usize && enabled { ret 22.0 }
    if slot == 2usize && !enabled { ret 19.0 }
    if slot == 2usize && enabled { ret 22.0 }
    if slot == 3usize && !enabled { ret 19.0 }
    if slot == 3usize && enabled { ret 22.0 }
    if slot == 4usize && !enabled { ret 19.0 }
    if slot == 4usize && enabled { ret 22.0 }
    if slot == 5usize && !enabled { ret 19.0 }
    if slot == 5usize && enabled { ret 22.0 }
    if slot == 6usize && !enabled { ret 19.0 }
    if slot == 6usize && enabled { ret 19.0 }
    if slot == 7usize && !enabled { ret 21.0 }
    if slot == 7usize && enabled { ret 21.0 }
    ret 19.0
}
// looks9-w1: the Windows look's navigator buttons, cut from the live 100 % collection grid (ref/windows/data_grid_bottom.png, 23 rows): the
// slots it shows (First, Previous page, Previous enabled and disabled, Next, Next page, Last, undo and funnel enabled) are exact; a slot not
// captured (the disabled Next, Next page, Last, undo and funnel) keeps the old bitmap and width.
fn gx_nav_win(slot: usize, enabled: bool) -> str {
    if slot == 0usize && !enabled { ret "F0F0F0F0F0F0EEEEEEEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFF0F0F0EEEEEEEDEDEDF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F5F5F5EDEDEDEDEDEDF0F0F0EBEBEBF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4EBEBEBEFEFEFEAEAEAF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9F0F0F0ECECECEEEEEEF8F8F8F9F9F9F9F9F9F3F3F3EFEFEFF8F8F8F9F9F9F9F9F9F3F3F3EFEFEFF8F8F8F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9DBDBDBDADADAD7D7D7F5F5F5F9F9F9F3F3F3E1E1E1D8D8D8F4F4F4F9F9F9F3F3F3E1E1E1D8D8D8F4F4F4F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9D4D4D4E6E6E6D2D2D2F3F3F3F2F2F2E0E0E0DADADAD0D0D0F3F3F3F3F3F3E0E0E0D9D9D9D0D0D0F3F3F3F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9D1D1D1E3E3E3CFCFCFECECECDDDDDDD8D8D8E7E7E7CFCFCFECECECDDDDDDD7D7D7E5E5E5CFCFCFF3F3F3F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9CDCDCDE0E0E0CBCBCBD5D5D5D4D4D4E1E1E1E0E0E0CACACAD5D5D5D0D0D0D9D9D9DBDBDBCACACAF2F2F2F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9C9C9C9DCDCDCC6C6C6CECECEDBDBDBCFCFCFD4D4D4C5C5C5CACACAD1D1D1C2C2C2CACACAC4C4C4F2F2F2F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9C6C6C6DADADAC3C3C3D3D3D3CFCFCFC4C4C4CCCCCCC1C1C1CCCCCCC8C8C8C2C2C2C8C8C8C0C0C0F1F1F1F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9C2C2C2D7D7D7BEBEBEC5C5C5CDCDCDCCCCCCCFCFCFBDBDBDC5C5C5C9C9C9C9C9C9CBCBCBBDBDBDF1F1F1F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9BEBEBED3D3D3BABABADFDFDFC8C8C8CBCBCBD2D2D2BABABADFDFDFC8C8C8C7C7C7CFCFCFB9B9B9F0F0F0F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9BBBBBBD2D2D2B6B6B6F0F0F0E7E7E7C3C3C3C8C8C8B5B5B5F0F0F0E8E8E8C3C3C3C6C6C6B4B4B4F0F0F0F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F4F4F4B9B9B9C6C6C6B3B3B3E7E7E7EFEFEFD9D9D9BBBBBBB1B1B1E7E7E7EFEFEFD9D9D9BBBBBBB1B1B1EAEAEAF8F8F8F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7EDEDEDCCCCCCC2C2C2C5C5C5DDDDDDE1E1E1E1E1E1D4D4D4C7C7C7DDDDDDE1E1E1E1E1E1D4D4D4C9C9C9E6E6E6F7F7F7F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F4F4F4F1F1F1EFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFF1F1F1F3F3F3F8F8F8F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBEFEFEFEBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EBEBEBEFEFEFEDEDEDEEEEEEF6F6F6F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F0F0F0ECECECEFEFEFEFEFEFECECECEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3EFEFEFECECECEFEFEFF0F0F0F0F0F0EFEFEFEDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEFEFEFF0F0F0F0F0F0" }
    if slot == 0usize && enabled { ret "F0F0F0EFEFEFE8E8E8E5E5E5E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E8E8E8EEEEEEF0F0F0F0F0F0EFEFEFE4E4E4DEDEDEE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2EDEDEDF0F0F0E7E7E7DCDCDCECECECFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF2F2F2DCDCDCE3E3E3EEEEEEDADADAEDEDEDFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDEFEFEFD9D9D9ECECECD4D4D4F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFBFBFBD7D7D7ECECECD4D4D4F7F7F7FDFDFDDAEBF9C9E3F7D3E8F9F8FAFCFDFDFDFDFDFDE8F2FBD7EAF9F8FAFCFDFDFDFDFDFDE8F3FBD7EAF9F8FAFCFDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD8CC4F077C1F37CBDEFECF5FBFDFDFDE7F2FAA4CFF280BEEFECF4FBFDFDFDE7F2FAA4D0F280BEEFECF4FBFDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD74B5EA8BD7FB67B2EAE9F2FAE7F1F9A1CDF079C1F063AEE8E8F2FAE7F1F9A1CDF078C0F063AEE8E8F2FAFDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD70B0E584D0F962ACE5D1E5F59EC9EC75BDED8CD8FB63ADE5D1E4F59FC9EC74BBEC88D4FA63ACE5E8F1F9FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD6CAADF7FCAF55DA5DF8ABBE471B7E880CCF67ECAF55CA4DE8ABBE46AAFE272BDEA74C0EE5BA3DDE7F0F8FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD67A4D878C3F2589ED864ACE076C2EE5EABE368B5E6559BD65CA4DB64B0E04995D057A4D85399D4E6EFF7FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD629DD273BEEF5296D16EB5E45CACE24297D453A8DD4E93CE5FA7DA4E9FD73F95D24CA1D94C92CDE6EEF6FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD5E97CB67BAED4C8FCA669DCF5FABDC42A7E242ACE6468DC9669DCF55A3D83AA3E03AA6E3458CC8E5EDF5FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD5890C546B3EE4288C4B6CEE573A2CE4CA6DC35B3F03F87C4B5CEE573A2CE419FD928ADEE3D87C3E4ECF4FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD548ABF2BB4F33982BFE4ECF4CCDCEB6E9AC539A2DD3A80BCE3ECF4CDDCEC6E9BC52F9EDC397FBCE3ECF4FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7F4F4F45B89B62F9EDC417EB4D6DDE3EBEBEBB9C5D0618CB7477AAED5DCE3EBEBEBB9C5D0628DB7487BAEDCE3EAFCFCFCFDFDFDD6D6D6ECECECD4D4D4F7F7F7E9E9E999ADC2759BC087A0BAC9CCCFD3D3D3D3D3D3AFBBC88EA4BBC9CCCFD3D3D3D3D3D3B0BCC991A7BED9DCDFFAFAFAFDFDFDD6D6D6ECECECD4D4D4F7F7F7F5F5F5F0F0F0EDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEFEFEFF3F3F3FCFCFCFDFDFDD6D6D6ECECECD5D5D5F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD6D6D6ECECECD8D8D8EFEFEFFCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF5F5F5D8D8D8ECECECE1E1E1DFDFDFF3F3F3FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF6F6F6E4E4E4E0E0E0EEEEEEEEEEEEDDDDDDDFDFDFE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DEDEDEDBDBDBEBEBEBF0F0F0F0F0F0EEEEEEDCDCDCCFCFCFCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED7D7D7EBEBEBF0F0F0F0F0F0" }
    if slot == 1usize && !enabled { ret "F0F0F0F0F0F0F0F0F0EEEEEEEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFF0F0F0F0F0F0EEEEEEEDEDEDF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F5F5F5EDEDEDEDEDEDF0F0F0F0F0F0EBEBEBF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4EBEBEBEFEFEFF0F0F0EAEAEAF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4EFEFEFF7F7F7F9F9F9F9F9F9F9F9F9F4F4F4EFEFEFF7F7F7F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F3F3F3E1E1E1D8D8D8F4F4F4F9F9F9F9F9F9F3F3F3E1E1E1D8D8D8F4F4F4F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F3F3F3E0E0E0DADADAD0D0D0F3F3F3F9F9F9F3F3F3E0E0E0DADADAD0D0D0F3F3F3F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F2F2F2DEDEDED8D8D8E8E8E8D0D0D0F2F2F2F2F2F2DEDEDED7D7D7E6E6E6D0D0D0F2F2F2F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F2F2F2DBDBDBD5D5D5E2E2E2E2E2E2CBCBCBEBEBEBDBDBDBD1D1D1D8D8D8DBDBDBCACACAF2F2F2F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9DADADAD2D2D2DFDFDFD3D3D3D7D7D7C6C6C6D3D3D3CDCDCDD1D1D1C3C3C3CACACAC4C4C4F1F1F1F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9D1D1D1D7D7D7D6D6D6CACACACFCFCFC1C1C1C9C9C9CECECEC9C9C9C4C4C4C9C9C9C0C0C0F0F0F0F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9EAEAEACBCBCBD0D0D0CFCFCFD2D2D2BEBEBEE1E1E1CCCCCCC9C9C9CBCBCBCDCDCDBDBDBDF0F0F0F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9E8E8E8C8C8C8CCCCCCD5D5D5BABABAEFEFEFE8E8E8C8C8C8C8C8C8D0D0D0BABABAEFEFEFF9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9E8E8E8C4C4C4C8C8C8B5B5B5EFEFEFF9F9F9E8E8E8C4C4C4C6C6C6B5B5B5EEEEEEF9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F8F8F8F6F6F6F4F4F4DDDDDDBCBCBCB1B1B1E6E6E6EFEFEFEFEFEFDADADABBBBBBB1B1B1E9E9E9F8F8F8F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F7F7F7F3F3F3EDEDEDE8E8E8D7D7D7C8C8C8DDDDDDE1E1E1E1E1E1E1E1E1D5D5D5C9C9C9E4E4E4F7F7F7F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F8F8F8F7F7F7F4F4F4F2F2F2F1F1F1EFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFF0F0F0F3F3F3F8F8F8F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EBEBEBEFEFEFF0F0F0EDEDEDEEEEEEF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F0F0F0ECECECEFEFEFF0F0F0EFEFEFECECECEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3EFEFEFECECECEFEFEFF0F0F0F0F0F0F0F0F0EFEFEFEDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEFEFEFF0F0F0F0F0F0" }
    if slot == 1usize && enabled { ret "F0F0F0F0F0F0EFEFEFE8E8E8E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E8E8E8EEEEEEF0F0F0F0F0F0F0F0F0EFEFEFE4E4E4DEDEDEE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2EDEDEDF0F0F0F0F0F0E7E7E7DCDCDCECECECFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF2F2F2DDDDDDE3E3E3EEEEEEF0F0F0DADADAECECECFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDEFEFEFD9D9D9ECECECF0F0F0D4D4D4F5F5F5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFBFBFBD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE8F3FBD7EAF9F7FAFCFDFDFDFDFDFDFDFDFDE8F3FBD7EAF9F7FAFCFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE8F2FAA5D0F381BEEFEAF4FBFDFDFDFDFDFDE8F2FAA5D0F381BEEFEAF3FBFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDE7F1F9A2CDF07AC2F064AEE9E6F1FAFDFDFDE7F1F9A2CDF079C1F063AEE9E6F1FAFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDE6F0F89FC9EC77BEED8ED9FB64AEE6E6F0F9E6F0F8A0C9EC75BBEC8AD6FB64ADE6E5F0F9FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDE6EFF89DC5E873B8E883CFF782CEF85DA5DFCEE2F39DC6E86BB0E273BEEA75C1EF5CA4DEE4EFF8FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFD9DC4E56EB2E37ECAF463B1EA6DBBEC569DD785B5DF64A9DD63B1E04896D155A3D95399D4E4EEF7FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFD83B2DC76BCE768B9ED45A2DF52ACE24E94CF6AA2D562AADB49A0D93A97D645A1DB4B92CEE3EDF6FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDD0E1F078A8D462AFDF3BADE83AB1ED458ECAB6D0E779A8D44FA3DA2DA6E62BA9EA438DCAE2ECF5FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDCFDEED74A2CF4AA9DF2CB8F63D89C5E2EBF4CFDEED74A3CF37A0DE19AFF63A88C6E1EBF3FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDCDDDEC6F9BC535A3DF3A80BDE1EAF3FDFDFDCDDDEC709CC5289EDF3780BDE0EAF2FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFCFCFCF9F9F9F5F5F5BFCBD6658FB9477BAED3DBE2EBEBEBEBEBEBBAC5D0638EB8487CAED8E0E8FBFBFBFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDF9F9F9F2F2F2E9E9E9E1E1E1B5C1CD8FA5BCC8CCCFD3D3D3D3D3D3D3D3D3B0BDC991A7BED6D9DDF9F9F9FDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFBFBFBF9F9F9F5F5F5F2F2F2EFEFEFECECECECECECECECECECECECECECECEDEDEDEEEEEEF2F2F2FBFBFBFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD7D7D7EBEBEBF0F0F0D8D8D8EFEFEFFCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF5F5F5D8D8D8ECECECF0F0F0E1E1E1DFDFDFF3F3F3FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF6F6F6E4E4E4E0E0E0EEEEEEF0F0F0EEEEEEDEDEDEDFDFDFE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DEDEDEDBDBDBEBEBEBF0F0F0F0F0F0F0F0F0EEEEEEDCDCDCCFCFCFCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED7D7D7EAEAEAF0F0F0F0F0F0" }
    if slot == 2usize && !enabled { ret "F0F0F0F0F0F0F0F0F0EEEEEEEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFF0F0F0F0F0F0EEEEEEEDEDEDF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F5F5F5EDEDEDEDEDEDF0F0F0F0F0F0EBEBEBF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4EBEBEBEFEFEFF0F0F0EAEAEAF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4EFEFEFF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F4F4F4E2E2E2D8D8D8F4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F3F3F3E1E1E1DBDBDBD1D1D1F2F2F2F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F3F3F3DFDFDFD9D9D9E7E7E7D1D1D1F2F2F2F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F2F2F2DEDEDED6D6D6E3E3E3E3E3E3CECECEF1F1F1F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F2F2F2DBDBDBD4D4D4DFDFDFD8D8D8DDDDDDCACACAF1F1F1F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9DBDBDBD1D1D1DDDDDDD3D3D3CFCFCFD5D5D5C6C6C6F0F0F0F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9D2D2D2D5D5D5D4D4D4C9C9C9C4C4C4CBCBCBC1C1C1F0F0F0F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9EAEAEACCCCCCCCCCCCC9C9C9C4C4C4CACACABDBDBDEFEFEFF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9E9E9E9CACACAC9C9C9CCCCCCCECECEBBBBBBEEEEEEF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9E9E9E9C7C7C7C8C8C8D1D1D1B9B9B9EEEEEEF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9E7E7E7C3C3C3C7C7C7B4B4B4EDEDEDF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6F4F4F4F2F2F2DCDCDCBCBCBCB1B1B1E9E9E9F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F2F2F2ECECECE8E8E8E5E5E5D5D5D5C8C8C8E6E6E6F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F6F6F6F4F4F4F2F2F2F1F1F1EFEFEFEFEFEFF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EBEBEBF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EBEBEBEFEFEFF0F0F0EDEDEDEEEEEEF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F0F0F0ECECECEFEFEFF0F0F0EFEFEFECECECEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3EFEFEFECECECEFEFEFF0F0F0F0F0F0F0F0F0EFEFEFEDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEFEFEFF0F0F0F0F0F0" }
    if slot == 2usize && enabled { ret "F0F0F0F0F0F0EFEFEFE8E8E8E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E8E8E8EEEEEEF0F0F0F0F0F0F0F0F0EFEFEFE4E4E4DEDEDEE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2EDEDEDF0F0F0F0F0F0E7E7E7DCDCDCECECECFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF2F2F2DDDDDDE3E3E3EEEEEEF0F0F0DADADAECECECFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF0F0F0DADADAECECECF0F0F0D5D5D5F5F5F5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE9F3FBD7EAF9F7FAFCFDFDFDFDFDFDFDFDFDFDFDFDFBFBFBD8D8D8EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE8F3FBA6D1F382BFEFE8F3FBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE8F2FAA4CFF17BC2F165B0EAE4F0FAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE7F1F9A2CCEE78BFEE8DD9FB67B1E8E4EFF9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE7F0F8A0C9EB75BAEB83CFF785D1FA61AAE3E3EFF8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDE6EFF89DC5E770B5E67ECAF56EBAF279C5F55CA4DEE2EEF7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFD9FC4E56CB0E279C5F265B1EB5EAAE66BB7EB569CD7E1EDF6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFD85B3DC72B8E568B4E952A0DC4998D457A4DA4E93CEE1EBF5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDD1E1F07AA9D561A8D94AA1D93A98D647A2DC488DC9E0EAF4FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD0DFEE77A5D150A3D830A7E62FABEB4089C6DFE9F3FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDCEDEED73A1CC3CA1DC1FB1F53986C3DFE8F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDCDDDEB709AC42C9FDE377EBBDEE8F1FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF8F8F8F4F4F4F1F1F1BDC8D4648EB8467AADD8E0E9FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF2F2F2E7E7E7E0E0E0DADADAB2BECA8EA5BBD9DDE1FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F5F5F5FDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF8F8F8F4F4F4F2F2F2EFEFEFEDEDEDECECECF3F3F3FCFCFCFDFDFDFDFDFDFDFDFDFCFCFCD7D7D7EBEBEBF0F0F0D8D8D8EEEEEEFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF6F6F6D9D9D9EBEBEBF0F0F0E2E2E2DFDFDFF3F3F3FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF6F6F6E4E4E4E0E0E0EDEDEDF0F0F0EEEEEEDEDEDEDFDFDFE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DEDEDEDBDBDBEAEAEAF0F0F0F0F0F0F0F0F0EEEEEEDCDCDCCFCFCFCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED7D7D7EAEAEAF0F0F0F0F0F0" }
    if slot == 3usize && !enabled { ret "F3F3F3F0F0F0F0F0F0EEEEEEEDEDEDEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEFEFEFF0F0F0F0F0F0F3F3F3F0F0F0EDEDEDEEEEEEF0F0F0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EFEFEFEDEDEDEFEFEFF0F0F0F3F3F3EEEEEEEEEEEEF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EFEFEFEDEDEDEFEFEFF3F3F3EBEBEBF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEFEFEFF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9DEDEDEDADADAEBEBEBF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9D8D8D8DBDBDBDBDBDBEAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9D6D6D6E3E3E3E0E0E0D9D9D9E9E9E9F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9D4D4D4DDDDDDE1E1E1DCDCDCD7D7D7E8E8E8F6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9D2D2D2DADADAD6D6D6D8D8D8D5D5D5D3D3D3E7E7E7F6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9CECECED4D4D4CDCDCDC6C6C6CDCDCDCECECED0D0D0F0F0F0F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9CBCBCBCDCDCDC6C6C6C2C2C2C9C9C9CACACACECECEEFEFEFF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9C8C8C8CCCCCCC9C9C9CCCCCCC9C9C9CBCBCBE4E4E4F6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9C6C6C6CDCDCDD2D2D2C9C9C9C9C9C9E3E3E3F6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9C3C3C3CECECEC9C9C9C7C7C7E2E2E2F6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9C1C1C1BFBFBFC2C2C2E0E0E0F5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F7F7F7C1C1C1B8B8B8D2D2D2E9E9E9EFEFEFF1F1F1F6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F6F6F6D8D8D8D6D6D6E1E1E1E7E7E7EAEAEAEEEEEEF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F8F8F8F4F4F4F2F2F2F2F2F2F3F3F3F4F4F4F5F5F5F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF3F3F3ECECECF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECEEEEEEF3F3F3EEEEEEEDEDEDF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6F0F0F0EDEDEDEFEFEFF3F3F3F0F0F0EDEDEDEEEEEEF0F0F0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EEEEEEEDEDEDEFEFEFF0F0F0F3F3F3F0F0F0F0F0F0EEEEEEEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEDEDEDEFEFEFF0F0F0F0F0F0" }
    if slot == 3usize && enabled { ret "F3F3F3F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0F3F3F3EFEFEFE5E5E5DEDEDEE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2ECECECF0F0F0F3F3F3E8E8E8DDDDDDEBEBEBF9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF2F2F2DEDEDEE3E3E3EEEEEEF3F3F3DBDBDBEBEBEBFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF0F0F0DADADAEBEBEBF3F3F3D6D6D6F3F3F3FDFDFDFDFDFDFDFDFDFDFDFDDCEDFAE2EFFAF8FBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFBFBFBDADADAEAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD95C9F195C8F1D6E9F9F8FBFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD80BCEC72BEF092C8F0D5E8F7F8FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD7DB8E989D4F97AC5F28FC4EDD4E7F6F8FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD7AB4E57DC8F487D3FA73BEEE8CC0E9D3E5F4F8FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD76AFE076C1F16BB7F078C4F26AB4E688BBE4D2E4F3F8FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD72AADB6DB8EA5CA9E3519EDA65B2E260A9DD84B6E0E7F0F7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD6EA4D55BABE0449AD53E94D14A9DD65EA9DB6CA7D7E1ECF5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD6A9FD048A8E131A0E139A4E151A8DD67A2D3B6D0E8F3F7FAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD679ACB34ABE927AFF140A8E2619ED0B5CEE5F2F6FAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD6395C628AFEF33AAE75B9ACCB3CCE3F2F6F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFD6091C22E9DDB5693C5B1C9E0F2F5F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFBFBFB6892BC5282B2A0B4C8E3E6E9F1F1F1F4F4F4F9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDF8F8F8A1B4C7A4B4C4CDD0D2DBDBDBE1E1E1E8E8E8F4F4F4FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9EAEAEAF3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFBFBFBF1F1F1EDEDEDEDEDEDEFEFEFF2F2F2F5F5F5F9F9F9FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD9D9D9EAEAEAF3F3F3D9D9D9EDEDEDFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF6F6F6DADADAEAEAEAF3F3F3E2E2E2DFDFDFF2F2F2FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF6F6F6E5E5E5E0E0E0EDEDEDF3F3F3EEEEEEDEDEDEDEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDBDBDBEAEAEAEFEFEFF3F3F3F0F0F0EEEEEEDDDDDDCFCFCFCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED6D6D6E9E9E9EFEFEFF0F0F0" }
    if slot == 4usize && !enabled { ret "F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EDEDEDEEEEEEF0F0F0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EFEFEFEDEDEDEFEFEFF0F0F0F0F0F0EEEEEEEEEEEEF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EFEFEFEDEDEDEFEFEFF0F0F0EBEBEBF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9EDEDEDEEEEEEF7F7F7F9F9F9F9F9F9F9F9F9EEEEEEEEEEEEF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9DEDEDED9D9D9EAEAEAF7F7F7F9F9F9F9F9F9DEDEDED9D9D9EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9D8D8D8DBDBDBDBDBDBE9E9E9F6F6F6F9F9F9D8D8D8DADADADBDBDBE9E9E9F6F6F6F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9D6D6D6E3E3E3E1E1E1D8D8D8E8E8E8F6F6F6D6D6D6E2E2E2DEDEDED8D8D8E8E8E8F6F6F6F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9D3D3D3DDDDDDE3E3E3DCDCDCD5D5D5E7E7E7D0D0D0D6D6D6D6D6D6D2D2D2D2D2D2E6E6E6F6F6F6F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9CFCFCFD9D9D9D7D7D7D8D8D8D3D3D3D1D1D1C5C5C5CBCBCBC4C4C4CACACACBCBCBCFCFCFEFEFEFF9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9CCCCCCD4D4D4D0D0D0D1D1D1CFCFCFCFCFCFC2C2C2CACACAC6C6C6C8C8C8C7C7C7CDCDCDEFEFEFF9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9C9C9C9D1D1D1D4D4D4CCCCCCCBCBCBE4E4E4C6C6C6CBCBCBCFCFCFC7C7C7CACACAE4E4E4F6F6F6F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9C5C5C5D1D1D1CDCDCDC8C8C8E2E2E2F5F5F5C5C5C5CCCCCCC8C8C8C7C7C7E2E2E2F5F5F5F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9C2C2C2C1C1C1C4C4C4E0E0E0F5F5F5F9F9F9C2C2C2BEBEBEC3C3C3E0E0E0F5F5F5F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F3F3F3C1C1C1B8B8B8D0D0D0E6E6E6EAEAEAEAEAEABFBFBFB8B8B8D3D3D3EBEBEBF3F3F3F6F6F6F8F8F8F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9EFEFEFD8D8D8D7D7D7E0E0E0E3E3E3E3E3E3E3E3E3D3D3D3D6D6D6E4E4E4EBEBEBEFEFEFF4F4F4F7F7F7F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F6F6F6F4F4F4F2F2F2F2F2F2F1F1F1F1F1F1F1F1F1F1F1F1F2F2F2F3F3F3F4F4F4F6F6F6F7F7F7F8F8F8F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0ECECECF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECEEEEEEF0F0F0EEEEEEEDEDEDF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6F0F0F0EDEDEDEFEFEFF0F0F0F0F0F0EDEDEDEEEEEEF0F0F0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EEEEEEEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEDEDEDEFEFEFF0F0F0F0F0F0" }
    if slot == 4usize && enabled { ret "F0F0F0F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0F0F0F0EFEFEFE5E5E5DEDEDEE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2ECECECF0F0F0F0F0F0E8E8E8DDDDDDEBEBEBF9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3DEDEDEE2E2E2EEEEEEF0F0F0DCDCDCEBEBEBFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF0F0F0DBDBDBEAEAEAF0F0F0D6D6D6F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFBFBFBDADADAE9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFDDDEDFAE2EFFAF8FBFCFDFDFDFDFDFDFDFDFDDDEDFAE1EFFAF8FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFD97C9F194C8F1D5E9F8F8FAFCFDFDFDFDFDFD97C9F194C8F1D5E8F8F8FAFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFD80BCEC71BCEF90C6EFD4E7F7F8FAFCFDFDFD81BCEC71BCEF90C6EFD4E7F7F8FAFCFDFDFDFDFDFDFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFD7DB7E788D4F87AC5F18DC2EBD2E5F5F8FAFC7EB8E787D2F877C2F08DC1EBD2E5F5F7FAFCFDFDFDFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFD79B2E27DC8F489D5FA73BDEC8ABDE6D1E4F374AFE073BEED77C3ED67B1E388BBE5D1E3F3F7FAFCFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFD75ACDC76C1F06DBAF176C4F167B1E384B7E05E9ED65DA9DC4997D15BAADC5AA5DB82B5DFE5EFF7FDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFD70A6D66BB9EB55AFEA55ACE465B2E26EA9D85394CE4FA4DC3D9AD7419CD854A2D86AA5D6DFEBF5FDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFD6CA0D050B2EA3FB1EC55AFE268A3D3B5CFE7629ACD38A7E42CA9E941A3DE63A0D2B5CFE7F2F6FAFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFD679ACA39B2EE46B1E8609ECFB3CCE4F2F6F9689ACA25ABED2EA7E65B9BCFB3CCE4F2F5F9FDFDFDFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDFDFDFD6395C43BA1DB5997C7B1C9E0F1F5F9FDFDFD6495C5299ADA5495C7B1C9E0F1F5F9FDFDFDFDFDFDFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDF5F5F56992BC5383B39FB3C7DFE2E5EBEBEBEBEBEB6790BA5383B3A1B6CAE6E9EBF6F6F6F9F9F9FCFCFCFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDEBEBEBA0B3C5A6B6C6CBCED1D3D3D3D3D3D3D3D3D399ABBFA5B5C5D2D5D8E3E3E3EBEBEBF4F4F4FAFAFAFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D6D6D6F4F4F4FDFDFDF6F6F6F1F1F1EEEEEEECECECECECECECECECECECECECECECEDEDEDEFEFEFF3F3F3F6F6F6F9F9F9FCFCFCFDFDFDFDFDFDD9D9D9E9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD9D9D9E9E9E9F0F0F0DADADAEDEDEDFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF6F6F6DADADAEAEAEAF0F0F0E2E2E2DFDFDFF1F1F1FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF6F6F6E5E5E5E0E0E0EDEDEDF0F0F0EEEEEEDFDFDFDEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDBDBDBEAEAEAEFEFEFF0F0F0F0F0F0EEEEEEDDDDDDD0D0D0CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED6D6D6E9E9E9EFEFEFF0F0F0" }
    if slot == 5usize && !enabled { ret "F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EDEDEDEEEEEEF0F0F0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EFEFEFEDEDEDEFEFEFF0F0F0F0F0F0EEEEEEEEEEEEF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EFEFEFEDEDEDEFEFEFF0F0F0EBEBEBF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6ECECECEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9EEEEEEEEEEEEF7F7F7F9F9F9F9F9F9EEEEEEEEEEEEF7F7F7F9F9F9F9F9F9EEEEEEE7E7E7E9E9E9F5F5F5F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9DEDEDED9D9D9EAEAEAF7F7F7F9F9F9DEDEDED9D9D9EAEAEAF7F7F7F9F9F9DEDEDEDCDCDCD7D7D7F0F0F0F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9D9D9D9DADADADBDBDBE9E9E9F6F6F6D9D9D9DADADADADADAE9E9E9F6F6F6D9D9D9E1E1E1D5D5D5EEEEEEF9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9D6D6D6E2E2E2E0E0E0D8D8D8E8E8E8D4D4D4E0E0E0DEDEDED8D8D8E7E7E7D4D4D4DEDEDED1D1D1EDEDEDF9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9D3D3D3DCDCDCE2E2E2DBDBDBD4D4D4CACACAD7D7D7D9D9D9D5D5D5D3D3D3CACACAD3D3D3CBCBCBECECECF9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9D0D0D0D8D8D8D8D8D8DBDBDBD5D5D5C6C6C6CECECEC7C7C7CCCCCCCECECEC5C5C5C9C9C9C5C5C5EBEBEBF9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9CDCDCDD5D5D5D4D4D4D6D6D6D1D1D1C2C2C2CACACAC5C5C5C8C8C8C9C9C9C1C1C1C7C7C7C1C1C1EAEAEAF9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9C9C9C9D2D2D2D6D6D6CDCDCDCBCBCBBEBEBECACACACECECEC8C8C8CACACABEBEBEC8C8C8BEBEBEE9E9E9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9C6C6C6D1D1D1CCCCCCC8C8C8E1E1E1C2C2C2CCCCCCC9C9C9C8C8C8E1E1E1C3C3C3C9C9C9BCBCBCE7E7E7F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9C3C3C3C1C1C1C4C4C4E0E0E0F5F5F5C3C3C3BFBFBFC3C3C3E0E0E0F5F5F5C4C4C4CACACABABABAE6E6E6F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F3F3F3C1C1C1B8B8B8D0D0D0E6E6E6EAEAEABFBFBFB8B8B8D0D0D0E6E6E6EAEAEABFBFBFBCBCBCB5B5B5E0E0E0F7F7F7F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F0F0F0D7D7D7D6D6D6E0E0E0E3E3E3E3E3E3D3D3D3D5D5D5E0E0E0E3E3E3E3E3E3D3D3D3CCCCCCCFCFCFE5E5E5F6F6F6F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F6F6F6F3F3F3F2F2F2F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F3F3F3F4F4F4F8F8F8F9F9F9EDEDEDEEEEEEF0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0ECECECF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EDEDEDEEEEEEF0F0F0EEEEEEEDEDEDF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6F0F0F0EDEDEDEFEFEFF0F0F0F0F0F0EDEDEDEEEEEEF0F0F0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EEEEEEEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEDEDEDEFEFEFF0F0F0F0F0F0" }
    if slot == 5usize && enabled { ret "F0F0F0F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0F0F0F0EFEFEFE5E5E5DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2ECECECF0F0F0F0F0F0E8E8E8DDDDDDEAEAEAF9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3DEDEDEE2E2E2EDEDEDF0F0F0DCDCDCEAEAEAFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF1F1F1DBDBDBEAEAEAF0F0F0D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFBFBFBDBDBDBE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDDDEDFAE1EFFAF8FAFCFDFDFDFDFDFDDDEDFAE1EFFAF8FAFCFDFDFDFDFDFDDDEDFACAE3F8D1E7F8F4F8FCFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFD98CAF194C7F1D4E8F8F8FAFCFDFDFD99CAF194C7F1D4E8F8F8FAFCFDFDFD99CAF177C0F27BBDEFE0EEFAFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFD82BDEC71BCEF90C6EFD3E6F6F7FAFC83BDEC70BCEF90C6EFD3E6F6F7FAFC83BDEC85D0F96BB6ECDAEBF8FDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFD7FB8E787D2F779C4F18DC2EBD2E5F57AB5E685D0F777C2F08CC1EBD1E5F57AB6E67DC8F566AFE7D9EAF7FDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFD7BB3E27BC6F387D3FA72BCEC8ABDE664A6DD74BFEF7BC7F16AB4E688BBE564A6DD6EB9EB5EA6DFD8E8F5FDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFD77ADDC74BFEF6FBBF17BC8F56AB3E5569CD664AFE1529FD761AEDF5FA8DD549AD559A4D9549BD5D7E6F4FDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFD72A7D670BAEC65B4EE65B5EC6BB6E55398D155A5DA4399D4499CD55BA7DA5195CF4E9FD74D94CFD6E5F2FDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFD6EA1D064B5E95BB6EE5EB0E269A3D34F8DC745A6DF3CA7E24EA5DB66A1D24F8DC73EA0DD448FCBD4E3F0FDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFD699BCA4EB2E952B0E4629ECFB2CBE45E94C736AAE73FA9E25E9CCEB2CBE45F94C729A4E53A8BC8D3E1EFFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFD6596C542A0D95B97C7AFC8E0F1F5F96697C5359BD85796C7AFC8E0F1F5F96797C61AA7EC3287C5D2E0EDFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3F5F5F56B94BC5283B39DB2C7DFE2E4EBEBEB6992BA5282B29DB2C7DFE2E4EBEBEB6A92BB2496D73C82B9CCD8E3FBFBFBFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3EBEBEBA1B3C5A4B5C5CACDD0D3D3D3D3D3D39AACBFA3B3C3CACDD0D3D3D3D3D3D39AACBF779BBF87A2BDD1D7DCF8F8F8FDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3F6F6F6F1F1F1EDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEFEFEFF2F2F2FBFBFBFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDADADAE9E9E9F0F0F0DADADAECECECFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF6F6F6DBDBDBEAEAEAF0F0F0E3E3E3DFDFDFF1F1F1FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF7F7F7E6E6E6E0E0E0ECECECF0F0F0EEEEEEDFDFDFDEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDBDBDBE9E9E9EFEFEFF0F0F0F0F0F0EEEEEEDDDDDDD0D0D0CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED6D6D6E9E9E9EFEFEFF0F0F0" }
    if slot == 6usize && !enabled { ret "F0F0F0F0F0F0F0F0F0EFEFEFEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0EEEEEEEDEDEDF2F2F2F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EEEEEEEDEDEDEFEFEFF0F0F0F0F0F0ECECECF1F1F1F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5ECECECEEEEEEF0F0F0F0F0F0EBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F1F1F1EFEFEFF6F6F6F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9DEDEDEC0C0C0E0E0E0F6F6F6F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F2F2F2E0E0E0D6D6D6D5D5D5D5D5D5D5D5D5BDBDBD818181A3A3A3E0E0E0F6F6F6F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5EFEFEFC5C5C59999998686868383838383838383837D7D7D6C6C6C6B6B6BAAAAAAE9E9E9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5C9C9C97E7E7E6D6D6D7B7B7B8080808080808080807A7A7A6B6B6B6C6C6C9C9C9CE4E4E4F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F59D9D9D6C6C6C8F8F8FBDBDBDC9C9C9C9C9C9C9C9C9B4B4B4808080969696DBDBDBF7F7F7F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F59898986A6A6AB2B2B2EDEDEDF9F9F9F9F9F9F9F9F9DEDEDEB2B2B2DBDBDBF7F7F7F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5BEBEBE7C7C7C9B9B9BE3E3E3F9F9F9F9F9F9F9F9F9EEEEEEEFEFEFF7F7F7F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5EFEFEFB6B6B6979797C7C7C7EFEFEFF8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F5F5F5D6D6D6C8C8C8E8E8E8F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0ECECECF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7EDEDEDEEEEEEF0F0F0F0F0F0EDEDEDEEEEEEF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F1F1F1EDEDEDEFEFEFF0F0F0F0F0F0F0F0F0EDEDEDEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F0F0F0EDEDEDEEEEEEF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0EDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEEEEEEF0F0F0F0F0F0F0F0F0" }
    if slot == 6usize && enabled { ret "F0F0F0F0F0F0F0F0F0EFEFEFEEEEEEEEEEEEEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEDEEEEEEEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEEEEEEEEEEEEEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0EEEEEEEDEDEDF2F2F2F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5EEEEEEEDEDEDEFEFEFF0F0F0F0F0F0ECECECF2F2F2F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5ECECECEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F0F0F0EFEFEFF7F7F7F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9DDDDDDBFBFBFE3E3E3F7F7F7F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F2F2F2DFDFDFD6D6D6D5D5D5D5D5D5D5D5D5BBBBBB7E7E7EA6A6A6E3E3E3F7F7F7F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5EFEFEFC2C2C29797978686868383838383838383837D7D7D6B6B6B6B6B6BAEAEAEECECECF9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5C6C6C67A7A7A6E6E6E7C7C7C8080808080808080807A7A7A6A6A6A6D6D6D9E9E9EE7E7E7F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F59797976B6B6B919191BFBFBFC9C9C9C9C9C9C9C9C9B2B2B27D7D7D999999DFDFDFF7F7F7F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5929292696969B7B7B7EFEFEFF9F9F9F9F9F9F9F9F9DDDDDDB0B0B0DFDFDFF7F7F7F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5BABABA7A7A7A9E9E9EE7E7E7F9F9F9F9F9F9F9F9F9EDEDEDEFEFEFF7F7F7F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5EEEEEEB2B2B2969696CBCBCBF0F0F0F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F4F4F4D4D4D4C8C8C8EAEAEAF8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0EBEBEBF5F5F5F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDEEEEEEF0F0F0F0F0F0ECECECF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7ECECECEEEEEEF0F0F0F0F0F0EDEDEDEEEEEEF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F1F1F1EDEDEDEFEFEFF0F0F0F0F0F0EFEFEFEDEDEDEFEFEFF2F2F2F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F0F0F0ECECECEEEEEEF0F0F0F0F0F0F0F0F0F0F0F0EFEFEFEDEDEDECECECEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBECECECECECECEFEFEFF0F0F0F0F0F0F0F0F0" }
    if slot == 7usize && !enabled { ret "F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0EFEFEFE6E6E6DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2EBEBEBF0F0F0E9E9E9DEDEDEE9E9E9F8F8F8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4E0E0E0E1E1E1EDEDEDDEDEDEE8E8E8F9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2DDDDDDE8E8E8D9D9D9EFEFEFFCFCFCF0F0F0E3E3E3DCDCDCD9D9D9D8D8D8D3D3D3CECECECECECED1D1D1D6D6D6DADADADFDFDFE7E7E7F7F7F7FDFDFDFCFCFCDEDEDEE7E7E7D9D9D9F0F0F0FDFDFDD4D4D4C1C1C1B9B9B9B2B2B2ADADADA1A1A29191958F8F9598989FA5A5ABB2B2B9BEBEC4C1C1C3EBEBEBFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDCCCCCCCBCBCBD7D7D7D2D2D2C8C8C8BDBDBFABABB5A8A8B6B2B2C1C0C0CFCFCFDDD3D3DFBEBEC2E8E8E8FDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDDDDDDDB5B5B5C3C3C3C2C2C2B4B4B4A8A8A996969E94949FA0A0ACB2B2BEC2C2CEB4B4B7C5C5C5F0F0F0FDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDCFCFCFC5C5C5CECECEC4C4C4B9B9BAA4A4AFA1A1B3B2B2C4C5C5D7C7C7D4C1C1C4EBEBEBFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDEFEFEFC1C1C1BABABAC3C3C3BFBFC0A7A7B1A5A5B6B9B9CBBABAC8B6B6B9DBDBDBF7F7F7FDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDEDEDEDBFBFBFB5B5B5BFBFC0ABABB4ABABBBAFAFBCACACAFD6D6D6F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDECECECBCBCBCAEAEAEABABB4A2A2AEA0A0A3D0D0D0F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDEBEBEB9F9F9FA7A7B18C8C90C3C3C3F5F5F5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA6A6A6A7A7B18C8C90D7D7D7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA7A7A7A7A7B18C8C91D7D7D7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA8A8A8A7A7B28F8F93D8D8D8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDACACACA9A9B4939397DADADAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6D9D9D9F0F0F0FDFDFDFDFDFDFCFCFCF9F9F9F5F5F5F4F4F4A9A9A9ACACB796969AD4D4D4F4F4F4F6F6F6FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDDDDDDDE6E6E6DADADAF0F0F0FDFDFDFDFDFDFAFAFAEEEEEEDFDFDFDBDBDB9C9C9C9E9EA59A9A9DC6C6C6DADADAE3E3E3F2F2F2FBFBFBFDFDFDFDFDFDFCFCFCDDDDDDE6E6E6DCDCDCEAEAEAFAFAFAFDFDFDFBFBFBEEEEEEE0E0E0DCDCDCB8B8B8A8A8A8C1C1C1D7D7D7DCDCDCE4E4E4F3F3F3FBFBFBFDFDFDFDFDFDF7F7F7DDDDDDE8E8E8E4E4E4DFDFDFEFEFEFFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF7F7F7E7E7E7E0E0E0EBEBEBEEEEEEE0E0E0DEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDCDCDCE8E8E8EFEFEFF0F0F0EEEEEEDFDFDFD1D1D1CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED5D5D5E7E7E7EFEFEFF0F0F0" }
    if slot == 7usize && enabled { ret "F0F0F0EFEFEFE9E9E9E6E6E6E5E5E5E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E4E7E7E7EDEDEDF0F0F0F0F0F0EFEFEFE5E5E5DFDFDFE0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0DFDFDFE2E2E2ECECECF0F0F0E8E8E8DDDDDDEAEAEAF9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3DFDFDFE2E2E2EDEDEDDDDDDDEAEAEAFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF1F1F1DCDCDCE9E9E9D8D8D8F1F1F1FDFDFDEFEFEFE2E2E2DBDBDBD9D9D9D8D8D8D3D3D3CECECECECECED1D1D1D6D6D6DBDBDBDFDFDFE7E7E7F8F8F8FDFDFDFCFCFCDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDD1D1D1C1C1C1B8B8B8B2B2B2ADADADA0A0A190909590909699999FA5A5ACB3B3B9BFBFC5C1C1C3EEEEEEFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDC8C8C8CDCDCDD7D7D7D1D1D1C8C8C8BCBCBFABABB4A8A8B6B3B3C1C1C1D0CFCFDDD3D3DEBDBDC0ECECECFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDDBDBDBB3B3B3C4C4C4C1C1C1B3B3B3A8A8A995959D9494A0A1A1ADB3B3BFC3C3CFB3B3B5C7C7C7F2F2F2FDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDCCCCCCC6C6C6CECECEC3C3C3B9B9BAA3A3AFA2A2B3B3B3C5C6C6D8C7C7D3C0C0C3EEEEEEFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDEEEEEEBFBFBFBABABAC4C4C4BEBEBFA6A6B1A6A6B7BABACCBABAC7B6B6B9DDDDDDF8F8F8FDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDECECECBCBCBCB6B6B6C0C0C0AAAAB3ABABBCAFAFBCACACAED9D9D9F8F8F8FDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDEBEBEBBABABAAEAEAEABABB5A1A1ADA0A0A3D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDEAEAEA9B9B9BA9A9B489898DC8C8C8F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA1A1A1A9A9B489898DDDDDDDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA1A1A1A9A9B48A8A8DDDDDDDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA3A3A3AAAAB58C8C90DEDEDEFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA7A7A7ABABB6919195E0E0E0FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFCFCFCF9F9F9F5F5F5F4F4F4A4A4A4AEAEBA939397D9D9D9F4F4F4F6F6F6FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDDBDBDBE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFAFAFAEDEDEDDFDFDFDBDBDB989898A0A0A799999BC9C9C9DADADAE3E3E3F3F3F3FCFCFCFDFDFDFDFDFDFCFCFCDBDBDBE8E8E8DBDBDBECECECFBFBFBFDFDFDFBFBFBEDEDEDE0E0E0DCDCDCB5B5B5A8A8A8C2C2C2D8D8D8DCDCDCE4E4E4F4F4F4FCFCFCFDFDFDFDFDFDF6F6F6DCDCDCE9E9E9E3E3E3DFDFDFF1F1F1FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF7F7F7E6E6E6E0E0E0ECECECEEEEEEDFDFDFDEDEDEE3E3E3E5E5E5E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E5E5E5DFDFDFDCDCDCE9E9E9EFEFEFF0F0F0EEEEEEDEDEDED0D0D0CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCECECED6D6D6E8E8E8EFEFEFF0F0F0" }
    ret ""
}
fn gx_nav_win_w(slot: usize, enabled: bool) -> f32 {
    if slot == 0usize && !enabled { ret 21.0 }
    if slot == 0usize && enabled { ret 21.0 }
    if slot == 1usize && !enabled { ret 22.0 }
    if slot == 1usize && enabled { ret 22.0 }
    if slot == 2usize && !enabled { ret 22.0 }
    if slot == 2usize && enabled { ret 22.0 }
    if slot == 3usize && !enabled { ret 22.0 }
    if slot == 3usize && enabled { ret 22.0 }
    if slot == 4usize && !enabled { ret 22.0 }
    if slot == 4usize && enabled { ret 22.0 }
    if slot == 5usize && !enabled { ret 22.0 }
    if slot == 5usize && enabled { ret 22.0 }
    if slot == 6usize && !enabled { ret 19.0 }
    if slot == 6usize && enabled { ret 19.0 }
    if slot == 7usize && !enabled { ret 21.0 }
    if slot == 7usize && enabled { ret 21.0 }
    ret 19.0
}
// the width of a slot's enabled bitmap in the Windows set when `win`, else in the old one
fn gx_nav_win_w_if(win: bool, slot: usize) -> f32 {
    if win { ret gx_nav_win_w(slot, true) }
    ret gx_nav_w(slot, true)
}
fn gx_nav_h() -> f32 { ret 23.0 }
// looks5-e: the navigator buttons as v3 draws them under the pointer (a blue frame over #E0EEF9), cut from
// states/hover-grid-navigator-next, -last and -filter: slot 3 (next), slot 4 (next page) and 7 (the funnel)
fn gx_nav_hot(slot: usize) -> str {
    if slot == 3usize { ret "F3F3F3F0F0F0E4EAEFA4CAE782B9E378B4E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E294C2E5D2E1EDEDEEF0F0F0F0F3F3F3E4EAEF87BBE45BA7E16CB1E672B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E76CB1E666ADE46DAEE2C8DCECEDEEF0F3F3F3A2C9E756A4E195C6EDCFE5F6DFEDF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF8B9D9F358A6E277B4E3D9E4EDF3F3F34FA0DD8DC2EBD5E8F7E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9AFD4F14099DDC4DAEBF3F3F33291DAACD3F1DFEDF9E0EEF9E0EEF9E0EEF9BADBF5BFDDF6DAEBF8E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF83594DDBDD7EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF986C1EF7DBCEEB5D8F4DAEBF8E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF977B8EB75C2F17EBEEDB3D6F2DAEAF8E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF975B4E785D1F77ECAF47BBAEAB2D5F1D9EAF8E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF972B0E379C5F381CDF876C2F178B6E6B0D3EED9EAF7E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF96EABDE73BEEF6AB6EF70BCEE6BB7E773B0E0AFD0EDD9EAF7E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF96AA6D968B4E759A6DF4E9BD75DAADD5FAADE6EAADBC8DFF2E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF966A0D456A9DF439BD73C95D34DA2DA57A3D86BA6D7C8DFF2E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF9639BCE44A7E12EA2E33AA8E54CA1D867A2D3ABCCE8D8E9F7E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF95F96CA30AAE929B2F33DA1DC629ED0AACAE6D8E9F6E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF95B92C527ADEE31A1DF5C9ACDA9C8E4D8E9F6E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9E0EEF9588EC12D91D05893C4A7C5E1D8E8F6E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9DDEBF6638FBA5282B193ADC5C5D4E0D1DEE9D5E2EDDBE9F4DFEDF8E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33291DAB2D6F1E0EEF9E0EEF9E0EEF9DCEAF49FB7CE9EB4C9BAC8D3C4D1DACAD6E0CFDCE6D9E6F1DFEDF8E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93192DCBBD6EAF3F3F33894DBAED4F1DFEDF9E0EEF9E0EEF9DEECF7D8E5F0D5E2EDD5E3EDD7E4EFD9E6F1DAE8F3DDEBF6E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF82F91DCBBD6EAF3F3F34FA0DD88BFEAD3E7F7E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9B4D7F2429ADEC4DAEBF3F3F39CC6E64EA1DF98C8EDD0E6F7DFEDF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF8B3D6F15CA8E37EB7E3DBE5EDF3F3F3E4EAEE87BCE467AADD69AADB6FACDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC5CA3DB6AADE0C8DCEBEDEEF0F3F3F3F0F0F0E4EAEEABCAE37FB2D977ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD77DB0D890BCDED1E0EBEDEEF0F0F0F0" }
    if slot == 4usize { ret "F0F0F0F0F0F0E4EAEFA5CBE783BAE378B4E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E293C2E5D1E0EDECEEF0F0F0F0F0F0F0E4EAEF88BCE45CA7E16CB1E672B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E76CB1E666ADE46DAEE2C7DBEBECEEF0F0F0F0A3CAE757A5E194C6EDCFE5F6DEEDF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF8B9DAF35AA7E376B3E3D8E4EDF0F0F051A1DE8CC1EBD4E8F7E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9B0D5F1429ADEC1D9EBF0F0F03492DAAAD1F0DEEDF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF83895DDBAD5EAF0F0F03492DAAFD4F1E0EEF9E0EEF9BADBF5BFDDF6D9EBF8E0EEF9E0EEF9E0EEF9BBDBF5BEDDF6D9EBF8E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9E0EEF987C1EF7DBBEDB3D7F3D9EBF8E0EEF9E0EEF988C1EF7CBBEDB3D7F3D9EAF8E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9E0EEF978B7EA73C1F07DBDECB2D5F1D9EAF8E0EEF978B7EA73C0F07DBDECB2D5F1D9EAF8E0EEF9E0EEF9E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9E0EEF974B3E584D0F77ECBF47AB8E8B0D3EFD9EAF775B3E582CEF67BC7F379B8E7B0D3EFD9EAF7E0EEF9E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9E0EEF970ADE07AC6F384D0F976C2EF76B3E3AED0ED69A9DE6DB9E96DB9E765B1E372B0E1AED0EDD8E9F7E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9E0EEF96CA7DA73BEEE6CB9F06DBBEC67B4E56FACDC5498D35AA6DB4997D255A4D958A5DB6CA9DBC7DFF2E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9E0EEF968A1D466B6EA50ADE956B0E65EABDE6DA8D84F92CD4AA3DC3A9CDA41A0DB4F9ED66AA5D7C7DEF1E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9E0EEF9649CCE49B0E942B6EF4FA7DD67A2D3ABCBE75C97CC33A6E42CACEC3D9DD963A0D2AACBE7D8E9F6E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9E0EEF95F96C839B2ED41A8E0609DCFA9C8E5D8E8F66096C923A9EC2D9FDF5C9CCFA9C8E4D8E8F6E0EEF9E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9E0EEF95B91C33794D05A96C6A7C5E1D8E8F6E0EEF95C91C4298FD05695C6A7C5E1D7E8F6E0EEF9E0EEF9E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9D6E4EE648FB95384B292ACC4C1CFDBC9D6E0C9D6E0608CB65383B295B0C8C9D8E4D6E4EEDBE9F3DEECF7E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9D2DFE99FB6CCA0B6CBB8C6D2BECAD3BECAD3BECAD398AFC59FB5CABECCD8CBD7E1D2DFE9D8E6F0DDEBF6E0EEF9E0EEF93493DDB9D4EAF0F0F03492DAAFD4F1E0EEF9DBE9F3D8E5F0D6E3EED5E2EDD4E2ECD4E2ECD4E2ECD4E2ECD5E3EDD7E4EFD9E6F1DBE9F3DDEBF6DFEDF8E0EEF9E0EEF93493DDB9D4EAF0F0F03A95DBABD2F0DEEDF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF83292DCB9D4EAF0F0F052A1DE86BFEAD2E7F7E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9B5D7F2439ADEC1D9EBF0F0F09EC7E64FA1DF97C7EDD0E6F6DEEDF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF8B4D6F25DA9E37EB7E3D9E5EDF0F0F0E4EAEE88BCE467AADE69AADC6FACDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC5CA4DB6AADDFC7DBEBEDEEF0F0F0F0F0F0F0E4EAEEACCBE37FB2D977ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD77DB0D890BCDECFDFEBEDEEF0F0F0F0" }
    if slot == 7usize { ret "F0F0F0E5EAEFA7CCE883BAE378B4E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E276B3E293C1E5CFE0ECECEEF0F0F0F0E5EAEF8BBEE55CA7E16BB0E572B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E772B4E76CB1E666ADE46CAEE2C3DAEBECEEF0A6CBE859A6E191C4ECCDE4F6DEEDF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF8BADAF35DA8E374B2E2D5E2ED57A4DE88C0EAD2E7F7E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9B2D5F1459BDEBCD6EA3B96DBA4CEEFDEEDF9CFDCE6BFCBD4B6C1CAB3BFC7B2BDC5ABB6BFA5B0B8A6B0B8AAB4BCB0BAC2B6C1C9BCC7D0C6D2DBDAE8F2E0EEF9DBEBF83D98DEB4D2E93B96DBA9D1F0E0EEF9BAC4CCBCC2C6BABFC2B4B8BBAEB2B5A3A6AB93969F9295A09B9FAAA7ABB7B5B8C4BFC3CFB1B9C1D3DFE9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9B4BFC6BAC0C3CFD0D1CBCBCBC1C1C1B6B6B8A4A4ADA2A2AEADADBABBBBC9CACAD7C4C7D4ACB3BBD1DDE7E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9CAD6E0A3ACB3C3C6C7C6C6C6B7B7B7ABABAC9898A19797A4A4A4B2B7B7C4C7C7D4A7ADB6B9C3CBD9E6F0E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9BBC7CFB4BABEC9CACBC4C4C4BABABBA4A4AFA2A2B3B3B3C5C7C7D9BABECBB2BBC4D4E1EBE0EEF9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9D6E4EEB1BCC4AAB0B4C0C1C2C0C0C0A7A7B1A7A7B8BBBBCDAEB1BEAAB2BBC9D6DFDDEBF5E0EEF9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9E0EEF9D4E2ECAFBAC2A6ABB0BCBDBEABABB4ACACBCA3A5B2A1A9B1C6D2DBDCEAF5E0EEF9E0EEF9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9E0EEF9E0EEF9D4E1ECADB7C09EA3A8A9A9B49799A5979EA6C2CED7DCEAF4E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9D4E1EB8B939AA5A6B380848CB6C0C9DBE9F4E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF98F989FA5A6B380848CC3CFD9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF98F989FA5A7B380858CC4D0D9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9929BA2A6A7B4838890C4D1DAE0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9959EA5A7A9B5868C94C6D2DCE0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF93A96DEB2D1E93B96DBA9D1F0E0EEF9E0EEF9DFEDF8DBE8F3D6E4EED5E2ED919AA1ABADBA888E96BDC9D3D5E2EDD8E5F0DDEBF5DFEDF8E0EEF9E0EEF9E0EEF93A96DEB2D1E94199DCA5CFEFDEEDF9E0EEF9DDEBF6D0DDE7C2CFD8BECAD4858E948F939C8C939BB1BCC5BECAD4C7D3DDD6E4EEDFEDF7E0EEF9E0EEF9DBEBF83895DDB2D1E957A4DE83BDE9D1E6F6E0EEF9DEECF7D6E3EDCCD9E3C9D6E0AFBAC3A6B1B9B7C3CCC6D3DDC9D6E0CFDCE6DAE7F2DFEDF8E0EEF9E0EEF9B6D8F2479CDEBCD6EAA0C8E751A2DF94C6ECCFE5F6DEEDF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9E0EEF9DBEBF8B5D7F260AAE37CB6E3D7E3EDE5EAEE8CBEE467AADE69AADC6FACDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC71ADDC5DA4DB69ACDFC4DAEBECEEEFF0F0F0E5EAEEAECCE380B3D977ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD777ADD77DB0D890BCDECEDEEAECEEEFF0F0F0" }
    ret ""
}


// looks4-e: the live capture's focus rectangle of a group row: alternate dark (`color`) and light (`inner`) pixels along the
// top edge (1 px in from the row's top) and the bottom edge (1 px up from its foot); DotsSoftLeft also its left edge.
fn dots_soft_paint(m: *Mark, b: *scene.Builder, area: geometry.Rect) -> err {
    let top = f32(i64(area.y + 0.5)) + 1.0
    let foot = f32(i64(area.y + 0.5)) + f32(i64(area.height + 0.5)) - 1.0
    let left = f32(i64(area.x + 0.5))
    var dx: f32 = 0.0
    while dx < area.width {
        var ink = m.color
        if i64(dx) % 2i64 == 1i64 { ink = m.inner }
        try winpx.fill(b, left + dx, top, 1.0, 1.0, ink)
        try winpx.fill(b, left + dx, foot, 1.0, 1.0, ink)
        dx += 1.0
    }
    if m.shape == Shape.DotsSoftLeft {
        var dy: f32 = 0.0
        while top + dy <= foot {
            var ink = m.color
            if i64(dy) % 2i64 == 1i64 { ink = m.inner }
            try winpx.fill(b, left, top + dy, 1.0, 1.0, ink)
            dy += 1.0
        }
    }
    ret ok
}

fn dot_px(b: *scene.Builder, x: f32, y: f32, c: u32) -> err {
    ret winpx.fill(b, x, y, 1.0, 1.0, rgb(c))
}

// looks4-e: the focus rectangle of a selected row, measured on the live capture (states/grid-row-selected-focused-main):
// two dotted lines along the top and the bottom and along the left edge `cols` px in, 1 px dots alternating dark and light.
fn sel_dots_paint(m: *Mark, b: *scene.Builder, area: geometry.Rect) -> err {
    let x0 = f32(i64(area.x + 0.5)) + f32(m.cols)
    let y0 = f32(i64(area.y + 0.5))
    let h = f32(i64(area.height + 0.5))
    var dx: f32 = 0.0
    while dx < area.width - f32(m.cols) {
        let odd = i64(dx) % 2i64 == 1i64
        // top: the outer line (brown dark, very light), the inner (grey dark, light blue); phases as measured
        if odd { try dot_px(b, x0 + dx, y0, 0x9C8670u32) } else { try dot_px(b, x0 + dx, y0, 0xB7CADDu32) }
        if odd { try dot_px(b, x0 + dx, y0 + 1.0, 0x8A95A1u32) } else { try dot_px(b, x0 + dx, y0 + 1.0, 0xA2C9F1u32) }
        if odd { try dot_px(b, x0 + dx, y0 + h - 2.0, 0xA0C6ECu32) } else { try dot_px(b, x0 + dx, y0 + h - 2.0, 0x808283u32) }
        if odd { try dot_px(b, x0 + dx, y0 + h - 1.0, 0xC0CEDCu32) } else { try dot_px(b, x0 + dx, y0 + h - 1.0, 0xA7998Bu32) }
        dx += 1.0
    }
    var dy: f32 = 2.0
    while dy < h - 2.0 {
        let odd = i64(dy) % 2i64 == 1i64
        if odd { try dot_px(b, x0, y0 + dy, 0x91969Bu32) } else { try dot_px(b, x0, y0 + dy, 0x89837Eu32) }
        if odd { try dot_px(b, x0 + 1.0, y0 + dy, 0xA2C8F0u32) } else { try dot_px(b, x0 + 1.0, y0 + dy, 0xA0C6ECu32) }
        dy += 1.0
    }
    ret ok
}

// looks13-r2: the tree list's focus rectangle as the Filter dialog captures show it, two pixels thick along the top and the bottom (outer
// then inner rows) and one along the sides, dots of opposite phase on the two rows: `m.cols` 0 on the inactive cream selection, 1 on the
// focused blue one. The area is `height` rows from the outer top row; x counts from the rectangle's left edge (even x = the left edge).
fn tree_focus_paint(m: *Mark, b: *scene.Builder, area: geometry.Rect) -> err {
    let x0 = f32(i64(area.x + 0.5))
    let y0 = f32(i64(area.y + 0.5))
    let w = i64(area.width + 0.5)
    let h = i64(area.height + 0.5)
    var t_even: u32 = 0x61636Fu32
    var t_odd: u32 = 0xF2F0E5u32
    var i_even: u32 = 0xA4A39Du32
    var i_odd: u32 = 0xECE9D8u32
    var u_even: u32 = 0x5B5C62u32
    var u_odd: u32 = 0xECE9D8u32
    var o_even: u32 = 0xB1B2B7u32
    var o_odd: u32 = 0xF9F8F2u32
    var side_a: u32 = 0x5B5C62u32
    var side_b: u32 = 0xA4A39Du32
    var left_top: u32 = 0xA4A39Du32
    if m.cols == 1usize {
        t_even = 0xBEDCFAu32
        t_odd = 0x8B6D4Fu32
        i_even = 0xA6D2FFu32
        i_odd = 0x8C9BAAu32
        u_even = 0xA6D2FFu32
        u_odd = 0x736455u32
        o_even = 0xD7E5F4u32
        o_odd = 0xBDAFA0u32
        side_a = 0x736455u32
        side_b = 0x8C9BAAu32
        left_top = 0x736455u32
    }
    var dx: i64 = 0i64
    while dx < w {
        let even = dx % 2i64 == 0i64
        var tc = t_odd
        var ic = i_odd
        var uc = u_odd
        var oc = o_odd
        if even {
            tc = t_even
            ic = i_even
            uc = u_even
            oc = o_even
        }
        try winpx.fill(b, x0 + f32(dx), y0, 1.0, 1.0, rgb(tc))
        try winpx.fill(b, x0 + f32(dx), y0 + 1.0, 1.0, 1.0, rgb(ic))
        try winpx.fill(b, x0 + f32(dx), y0 + f32(h) - 2.0, 1.0, 1.0, rgb(uc))
        try winpx.fill(b, x0 + f32(dx), y0 + f32(h) - 1.0, 1.0, 1.0, rgb(oc))
        dx += 1i64
    }
    // the sides, from the inner top row down to the inner bottom row (rows are counted from the first inner row)
    var dy: i64 = 1i64
    while dy < h - 1i64 {
        let from_top = dy - 1i64
        var left_c = side_a
        var right_c = side_a
        if m.cols == 1usize {
            // blue: the left edge is #736455 on the first inner row and every other row after it, #8C9BAA between; the right edge the other way
            if from_top % 2i64 == 1i64 { left_c = side_b }
            right_c = side_b
            if from_top % 2i64 == 1i64 { right_c = side_a }
        } else {
            // cream: the left edge starts #A4A39D, then #5B5C62; the right edge starts #5B5C62
            left_c = left_top
            if from_top % 2i64 == 1i64 { left_c = side_a }
            right_c = side_a
            if from_top % 2i64 == 1i64 { right_c = side_b }
        }
        try winpx.fill(b, x0, y0 + f32(dy), 1.0, 1.0, rgb(left_c))
        try winpx.fill(b, x0 + f32(w) - 1.0, y0 + f32(dy), 1.0, 1.0, rgb(right_c))
        dy += 1i64
    }
    ret ok
}

// A tree list's focus rectangle (see `tree_focus_paint`), `width` x `height` from its outer top row.
fn tree_focus(a: *mem.Arena, blue: bool, width: f32, height: f32) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    var kind = 0usize
    if blue { kind = 1usize }
    marks[0usize] = Mark { arena: a, color: rgb(0u32), inner: rgb(0u32), shape: Shape.TreeFocus, pix: "", cols: kind, skip: 0usize }
    var size = style.defaults()
    size.width = style.Length { Px: width }
    size.height = style.Length { Px: height }
    size.min_width = style.Length { Px: width }
    size.min_height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: size, children: none }, ok)
}

// A selected row's focus rectangle: `width` x `height`, its left edge `left` px in.
fn sel_dots(a: *mem.Arena, width: f32, height: f32, left: usize) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    marks[0usize] = Mark { arena: a, color: rgb(0u32), inner: rgb(0u32), shape: Shape.SelDots, pix: "", cols: left, skip: 0usize }
    var size = style.defaults()
    size.width = style.Length { Px: width }
    size.height = style.Length { Px: height }
    size.min_width = style.Length { Px: width }
    size.min_height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: size, children: none }, ok)
}

// looks4-e: the current data row's arrow in the indicator column (live capture, states/grid-row-selected-focused-main), 9 x 10
fn gx_row_arrow_long() -> str { ret "FFFFFFFFFFFFFFFFFFFFFFFFE8E8E8D2D2D2F9F9F9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFD4D4D45D5D5DBFBFBFF9F9F9FFFFFFEEEEEEEBEBEBEBEBEBEBEBEBC2C2C21A1A1A434343BFBFBFF9F9F97373735F5F5F5F5F5F5F5F5F4F4F4F0A0A0A020202444444E8E8E83B3B3B1F1F1F1F1F1F1F1F1F191919030303000000151515E1E1E1B3B3B3A8A8A8A8A8A8A8A8A88B8B8B111111131313828282F1F1F1FFFFFFFFFFFFFFFFFFFFFFFFD3D3D32D2D2D828282E7E7E7FDFDFDFFFFFFFFFFFFFFFFFFFFFFFFDEDEDE9B9B9BE7E7E7FDFDFDFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF4F4F4F3F3F3FDFDFDFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" }
fn gx_row_arrow_long_w() -> f32 { ret 9.0 }
fn gx_row_arrow_long_h() -> f32 { ret 10.0 }

// looks4-e: the tree list's plus and minus boxes and check box (unchecked, and checked), cut from the live Filter dialog captures
fn gx_tree_plus() -> str { ret "D1D2D2B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6D1D2D29F9F9FD8D8D8D8D8D8D8D8D8D8D8D8D8D8D8D8D8D8D8D8D89F9F9F919191FCFCFCFCFCFCFCFCFC6F80A0FCFCFCFCFCFCFCFCFC919191919191FBFBFBFBFBFBFBFBFB294272FBFBFBFBFBFBFBFBFB919191919191FAFBFB8595C38595C34058958595C38595C3FAFBFB919191919191F1F2F1B7BFD5B7BFD5344D84B7BFD5B7BFD5F1F2F1919191919191E6E6E6E6E6E6E6E6E6294272E6E6E6E6E6E6E6E6E6919191919191E3E3E3E3E3E3E3E3E3A5AEBDE3E3E3E3E3E3E3E3E3919191ACADAEACACACACACACACACACACACACACACACACACACACACACACADAEE8E8E9DADADADADADADADADADADADADADADADADADADADADAE8E8E9" }
fn gx_tree_plus_w() -> f32 { ret 9.0 }
fn gx_tree_plus_h() -> f32 { ret 10.0 }
fn gx_tree_minus() -> str { ret "D1D2D2B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6D1D2D29F9F9FD7D8D8D7D8D8D7D8D8D7D8D8D7D8D8D7D8D8D7D8D89F9F9F919191FAFBFBFAFBFBFAFBFBFAFBFBFAFBFBFAFBFBFAFBFB919191919191FAFBFBFAFBFBFAFBFBFAFBFBFAFBFBFAFBFBFAFBFB919191919191F1F2F18595C38595C38595C38595C38595C3F1F2F1919191919191EDEDECB7BFD5B7BFD5B7BFD5B7BFD5B7BFD5EDEDEC919191919191E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6E6919191919191E3E3E3E3E3E3E3E3E3E3E3E3E3E3E3E3E3E3E3E3E3919191ACADAEACACACACACACACACACACACACACACACACACACACACACACADAEE8E8E9DADADADADADADADADADADADADADADADADADADADADAE8E8E9" }
fn gx_tree_minus_w() -> f32 { ret 9.0 }
fn gx_tree_minus_h() -> f32 { ret 10.0 }
fn gx_tree_check() -> str { ret "FFFFFFCACACA9D9D9D9696969696969696969696969696969696969696969D9D9DC4C4C4FFFFFFC4C4C4A1A1A1C0C0C0C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3BABABA9D9D9DCBCBCB7F7F7FC9C9C9F0F0F0F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3EDEDEDCFCFCF838383656565EDEDEDF3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F0F0F0656565626262F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3626262626262F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3626262626262F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3626262626262F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3626262626262F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3626262626262F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3626262696969EDEDEDF3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3E7E7E76969699A9A9AB3B3B3E7E7E7F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3F3EDEDEDB0B0B0939393E5E5E5A2A2A2929292929292929292929292929292929292929292929292959595A8A8A8E1E1E1FFFFFFE2E2E2CECECECBCBCBCBCBCBCBCBCBCBCBCBCBCBCBCBCBCBCBCBCBCECECEE5E5E5FFFFFF" }
fn gx_tree_check_w() -> f32 { ret 13.0 }
fn gx_tree_check_h() -> f32 { ret 14.0 }
fn gx_tree_check_on() -> str { ret "FFFFFFA9CAE75F9BD35594D05594D05594D05594D05594D05594D05594D05F9BD39FC4E5FFFFFF9FC3E42A7AC40562BA005FB8005FB8005FB8005FB8005FB8005FB8005FB80562BA2577C3AACAE8307DC6005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB83581C70562BA005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB80562B9005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB83F87CA005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB86BA2D65F9BD2005FB8005FB8005FB8005FB8005FB8005FB83580C7005FB8005FB8005FB86BA2D675A8D82073C1005FB8005FB8005FB8005FB8005FB8005FB85B98D16AA2D5005FB86BA2D675A8D82073C1005FB8005FB8005FB8005FB8005FB8005FB8005FB82073C175A8D995BDE175A8D82073C1005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB82073C15594CF2073C1005FB8005FB8005FB8005FB8005FB8005FB80B66BB005FB8005FB8005FB8005FB80562B9005FB8005FB8005FB8005FB8005FB8005FB80B66BB5B98D2005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB8005FB85091CED5E5F34B8ECD0B66BB005FB8005FB8005FB8005FB8005FB8005FB8005FB80B66BB5594D0D0E1F2FFFFFFD0E1F2B0CDE9AACAE7AACAE7AACAE7AACAE7AACAE7AACAE7AACAE7B0CDE9D5E4F3FFFFFF" }
fn gx_tree_check_on_w() -> f32 { ret 13.0 }
fn gx_tree_check_on_h() -> f32 { ret 14.0 }

// looks4-e: the filter button a hot header shows, 11 x 11 on the pressed header's #BCDCF4 (states/grid-header-pressed-main)
fn gx_header_filter() -> str { ret "ABC5D9A2B9CBA1B8C9A1B8C9A1B8C9A1B8C9A1B8C9A1B8C9A1B8C9A5BDCFB7D5EB9DB2C2A6BED0ACC5D9ACC5D9ACC5D9ACC5D9ACC5D9ACC5D9ACC5D99AADBDB2CFE49BAFBFAFCADF9BAFBF9EB3C3A1B8C9A1B8C9A1B8C996A9B7B2CFE49CB0BFB1CDE39BAFBFB0CCE19AAFBD94A5B2A6BED0ABC4D896A8B695A8B6B3D0E69CB0BFB1CDE39BAFBFB2CEE3B4D1E7A6BED0A2B9CA9EB4C4A2B9CAB1CDE2BADAF19CB0BFB1CDE39BAFBFB2CEE3BCDCF4B7D5EB9AAEBC8F9FACAEC9DDBBDBF2BCDCF49CB0BFB1CDE39BAFBFB2CEE3BCDCF4BCDCF499ADBC92A4B1B2CFE4BCDCF4BCDCF49CB0BFB1CDE39BAFBFB2CEE3BCDCF4BCDCF497AAB895A8B6B3D0E6BCDCF4BCDCF49CB0BFB1CDE39BAFBFB2CEE3BCDCF4BCDCF4ADC8DCADC8DDB9D8EFBCDCF4BCDCF49CB0BFB1CDE39FB4C49FB4C4A2B8C9A2B8C9A2B8C9A2B8C9A2B8C9A2B8C9A2B8C999ACBBB3CFE5B1CEE3ACC6DAABC5D9ABC5D9ABC5D9ABC5D9ABC5D9ABC5D9ABC5D9AEC9DDB9D8EF" }
fn gx_header_filter_w() -> f32 { ret 11.0 }
fn gx_header_filter_h() -> f32 { ret 11.0 }

// looks4-e: the ellipsis button of an open text editor, cut from states/vertical-grid-editor-open-deck-properties-description (16 x 15)
fn gx_ellipsis_button() -> str { ret "FFFFFFFCFCFCEFEFEFE8E8E8E6E6E6E5E5E5E5E5E5E5E5E5E5E5E5E5E5E5E5E5E5E5E5E5ECECECF9F9F9FEFEFEFFFFFFFCFCFCE9E9E9E2E2E2E7E7E7E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E5E5E5E4E4E4F7F7F7FEFEFEEFEFEFE2E2E2EFEFEFFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF6F6F6E2E2E2E7E7E7FAFAFADFDFDFEDEDEDFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF4F4F4DDDDDDF6F6F6DADADAF2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDBDBDBF5F5F5DADADAF4F4F4FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAF5F5F5DADADAF4F4F4FDFDFDFDFDFD919191E0E0E0FDFDFD919191DFDFDFFDFDFD919191DFDFDFFDFDFDFDFDFDDADADAF5F5F5DADADAF4F4F4FDFDFDFDFDFDA1A1A1E4E4E4FDFDFDA1A1A1E4E4E4FDFDFDA1A1A1E4E4E4FDFDFDFDFDFDDADADAF5F5F5DADADAF4F4F4FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAF5F5F5DADADAF4F4F4FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAF5F5F5DBDBDBF3F3F3FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD9D9D9F5F5F5E0E0E0EAEAEAFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF3F3F3DDDDDDF6F6F6F0F0F0DFDFDFEDEDEDF9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3E1E1E1EAEAEAFBFBFBFDFDFDECECECDFDFDFD9D9D9D9D9D9D9D9D9D9D9D9D9D9D9D9D9D9D9D9D9D9D9D9DADADADADADAE4E4E4F8F8F8FEFEFEFFFFFFFDFDFDEEEEEEE2E2E2DFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFE0E0E0E7E7E7F8F8F8FEFEFEFFFFFF" }
fn gx_ellipsis_button_w() -> f32 { ret 16.0 }
fn gx_ellipsis_button_h() -> f32 { ret 15.0 }

// ---- round 12: the live capture's focus rectangle of a group row (ref/windows/data_grid_group*) ------------------------------
// Two pixels thick, from the row's top (one pixel above its content) to its foot (one pixel below). Dotted (flags bit 0 clear):
// alternate dark and light pixels along each line, the two tones drifting together along the row (end values measured at x = 542
// from the rect's left); solid (bit 0): one tone per line. Bit 1: this cell is the first the rectangle crosses, so it draws the left edge.
// `cols` is the cell's offset from the rectangle's left edge. Grays are written as one byte.
fn gx_gray(v: f32) -> paint.Color {
    let n = u32(v + 0.5)
    ret rgb(n * 65793u32)
}

fn gx_drift(v0: f32, v1: f32, at: f32) -> paint.Color { ret gx_gray(v0 + (v1 - v0) * at / 542.0) }

fn group_rect_paint(m: *Mark, b: *scene.Builder, area: geometry.Rect) -> err {
    // the node is 18 tall: the outer lines are its first and last rows, the content rows (16) between
    let top = f32(i64(area.y + 0.5)) + 1.0
    let h = f32(i64(area.height + 0.5)) - 2.0
    let left = f32(i64(area.x + 0.5))
    let solid = (m.skip & 1usize) != 0usize
    let edge = (m.skip & 2usize) != 0usize
    var dx: f32 = 0.0
    while dx < area.width {
        let at = f32(m.cols) + dx
        let odd = i64(at) % 2i64 == 1i64
        let x = left + dx
        if solid {
            var outer = gx_gray(113.0)
            var inner = gx_gray(132.0)
            var base = gx_gray(125.0)
            var foot = gx_gray(120.0)
            if at < 1.0 {
                outer = gx_gray(128.0)
                inner = gx_gray(43.0)
                base = gx_gray(43.0)
                foot = gx_gray(134.0)
            } else if at < 2.0 {
                inner = gx_gray(116.0)
                base = gx_gray(110.0)
            }
            try winpx.fill(b, x, top - 1.0, 1.0, 1.0, outer)
            try winpx.fill(b, x, top, 1.0, 1.0, inner)
            try winpx.fill(b, x, top + h - 1.0, 1.0, 1.0, base)
            try winpx.fill(b, x, top + h, 1.0, 1.0, foot)
        } else {
            var a0 = gx_drift(128.0, 166.0, at)
            var a1 = gx_drift(145.0, 181.0, at)
            var a2 = gx_drift(139.0, 177.0, at)
            var a3 = gx_drift(134.0, 170.0, at)
            if odd {
                a0 = gx_drift(215.0, 177.0, at)
                a1 = gx_drift(226.0, 191.0, at)
                a2 = gx_drift(225.0, 188.0, at)
                a3 = gx_drift(215.0, 180.0, at)
            }
            try winpx.fill(b, x, top - 1.0, 1.0, 1.0, a0)
            try winpx.fill(b, x, top, 1.0, 1.0, a1)
            try winpx.fill(b, x, top + h - 1.0, 1.0, 1.0, a2)
            try winpx.fill(b, x, top + h, 1.0, 1.0, a3)
        }
        dx += 1.0
    }
    if edge {
        var dy: f32 = 1.0
        while dy < h - 1.0 {
            let odd = i64(dy) % 2i64 == 1i64
            if solid {
                try winpx.fill(b, left, top + dy, 1.0, 1.0, gx_gray(43.0))
                try winpx.fill(b, left + 1.0, top + dy, 1.0, 1.0, gx_gray(210.0))
            } else {
                var dark = gx_gray(145.0)
                var light = gx_gray(226.0)
                if odd {
                    dark = gx_gray(137.0)
                    light = gx_gray(224.0)
                }
                try winpx.fill(b, left, top + dy, 1.0, 1.0, dark)
                try winpx.fill(b, left + 1.0, top + dy, 1.0, 1.0, light)
            }
            dy += 1.0
        }
    }
    ret ok
}

// A group row's focus rectangle for the cell `cols` px along it (flags as above).
fn group_rect(a: *mem.Arena, flags: usize, cols: usize, width: f32, height: f32) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    marks[0usize] = Mark { arena: a, color: rgb(0u32), inner: rgb(0u32), shape: Shape.GroupRect, pix: "", cols: cols, skip: flags }
    var size = style.defaults()
    size.width = style.Length { Px: width }
    size.height = style.Length { Px: height }
    size.min_width = style.Length { Px: width }
    size.min_height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: size, children: none }, ok)
}

// ---- round 12: the group box chip (ref/windows states hover-grid-grouped-rest, hover-grid-groupbox-chip, hover-grid-group-chip-pressed) ----
// A white chip with a one pixel soft ring (rest), or the hot / pressed chip with its filter button. The ring pixels (11: TL T TRa TRb L Ra Rb BL B BRa BRb)
// and the 8 x 9 sort triangles and 12 x 11 filter buttons of each state are cut from the live captures.
fn gx_chip_ring_rest() -> str { ret "F8F8F8F9F9F9ECECECEFEFEFFDFDFDE9E9E9EEEEEEF5F5F5F6F6F6EDEDEDEFEFEF" }
fn gx_chip_ring_hover() -> str { ret "E4EDF5E2EDF6EEEFF1F0F0F0DCECF8ECEFF2F0F0F0E8EEF3E7EEF4EEF0F1F0F0F0" }
fn gx_chip_ring_pressed() -> str { ret "D4E5F2D0E4F2EBEEF0F0F0F0C3DFF3E7EDF1F0F0F0DEE9F1DBE8F2EDEFF0F0F0F0" }
fn gx_chip_tri_rest() -> str { ret "FFFFFFFFFFFFFFFFFFCECECEF6F6F6FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFAFAFAFF0F0F0FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFCECECED7D7D7C8C8C8F6F6F6FFFFFFFFFFFFFFFFFFFFFFFFAFAFAFF0F0F0AFAFAFF0F0F0FFFFFFFFFFFFFFFFFFCECECED7D7D7F9F9F9E0E0E0C8C8C8F5F5F5FFFFFFFFFFFFAFAFAFF0F0F0FFFFFFFFFFFFAFAFAFEFEFEFFFFFFFCECECED7D7D7F9F9F9FFFFFFFFFFFFE0E0E0C9C9C9F5F5F5AFAFAFBFBFBFC5C5C5C5C5C5C5C5C5C5C5C5A6A6A6EFEFEFE0E0E0DADADADADADADADADADADADADADADADADADAF9F9F9" }
fn gx_chip_tri_hover() -> str { ret "D9EBF9D9EBF9D9EBF9BBC4CBD4E4F0D9EBF9D9EBF9D9EBF9D9EBF9D9EBF9D9EBF9A9ACAED0DFEBD9EBF9D9EBF9D9EBF9D9EBF9D9EBF9BBC4CBC1CBD3B8C0C6D4E4F0D9EBF9D9EBF9D9EBF9D9EBF9A9ABAED0DFEBA9ACAED0DFEBD9EBF9D9EBF9D9EBF9BCC4CBC1CBD3D6E6F4C6D2DCB8C0C6D4E4F1D9EBF9D9EBF9A9ABAED0E0EBD9EBF9D9EBF9A9ACAED0DFEBD9EBF9BCC4CBC1CBD3D6E7F4D9EBF9D9EBF9C6D2DCB8C0C6D4E4F1A9ABAEB3B9BDB6BDC3B6BDC3B6BDC3B6BDC3A3A5A5D0DFEBC6D2DCC3CED6C3CED6C3CED6C3CED6C3CED6C3CED6D6E6F4" }
fn gx_chip_tri_pressed() -> str { ret "BCDCF4BCDCF4BCDCF4AEBDC9B9D6ECBCDCF4BCDCF4BCDCF4BCDCF4BCDCF4BCDCF4A4A9ADB8D3E7BCDCF4BCDCF4BCDCF4BCDCF4BCDCF4ADBDC8B0C3D1ACB9C3B9D6ECBCDCF4BCDCF4BCDCF4BCDCF4A4A9ADB8D3E7A4A9ADB8D3E7BCDCF4BCDCF4BCDCF4AEBDC9B0C3D0BAD8EFB3C8D8ACB9C4B9D6ECBCDCF4BCDCF4A4A9ADB8D3E7BCDCF4BCDCF4A4A9ADB8D3E7BCDCF4AEBDC9B0C3D0BAD8EFBCDCF4BCDCF4B3C8D8ACB9C4B9D6ECA4A9ADA9B4BCABB7C1ABB7C1ABB7C1ABB7C1A2A4A5B8D3E7B3C8D8B1C5D3B1C5D3B1C5D3B1C5D3B1C5D3B1C5D3BAD8EF" }
fn gx_chip_filter_hover() -> str { ret "D9EBF9C1CFDAB7C4CEB6C3CDB6C3CDB6C3CDB6C3CDB6C3CDB6C3CDB6C3CDBCCAD4D4E6F3D9EBF9ACB7C0BECCD7C3D1DDC3D1DDC3D1DDC3D1DDC3D1DDC3D1DDC3D1DDA9B4BDD0E1EED9EBF9A9B4BDCCDCE8AAB5BDB3BFC9B6C3CDB6C3CDB6C3CDA6B1B8D0E1EEA9B4BDD0E0EDD9EBF9A9B4BDCEDEEAA8B3BBA4AEB5BECCD7C2D0DCA3ADB5A6B1B9D1E2EFA9B4BDD0E0EDD9EBF9A9B4BDD0E0EDCDDDEABAC7D2B7C4CEB1BDC6B7C4CFCCDCE9D7E9F7A9B4BDD0E0EDD9EBF9A9B4BDD0E0EDD9EBF9D1E2EFA8B2BB9EA7AECBDAE7D8EAF8D9EBF9A9B4BDD0E0EDD9EBF9A9B4BDD0E0EDD9EBF9D9EBF9A6B0B9A3ACB5D0E1EED9EBF9D9EBF9A9B4BDD0E0EDD9EBF9A9B4BDD0E0EDD9EBF9D9EBF9A3ACB4A7B2BAD1E2EFD9EBF9D9EBF9A9B4BDD0E0EDD9EBF9A9B4BDD0E0EDD9EBF9D9EBF9C3D2DDC6D5E1D6E8F5D9EBF9D9EBF9A9B4BDD0E0EDD9EBF9AEBAC3B4C0CAB6C3CDB6C3CDB6C3CDB6C3CDB6C3CDB6C3CDB6C3CDA9B4BDD1E2EFD9EBF9CAD9E5C3D2DEC3D1DDC3D1DDC3D1DDC3D1DDC3D1DDC3D1DDC3D1DDC6D6E1D6E8F5" }
fn gx_chip_filter_pressed() -> str { ret "BCDCF4A9C3D6A2B9CAA2B8C9A2B8C9A2B8C9A2B8C9A2B8C9A2B8C9A2B8C9A6BED0B8D7EEBCDCF49AAEBDA8C0D3ABC5D9ABC5D9ABC5D9ABC5D9ABC5D9ABC5D9ABC5D998ABBAB5D3E9BCDCF498AAB9B2CEE498ABBA9FB4C5A2B8C9A2B8C9A2B8C995A8B6B5D3E998ABB9B5D2E9BCDCF498AAB9B3D0E697AAB894A5B3A8C0D3AAC4D794A5B396A9B6B6D4EA98ABB9B5D2E9BCDCF498AAB9B5D3E9B3D0E5A5BCCEA2B9CA9EB3C3A3BACBB2CFE4BBDAF298ABB9B5D2E9BCDCF498AAB9B5D3E9BCDCF4B6D4EA97AAB78F9FABB1CDE2BBDBF3BCDCF498ABB9B5D2E9BCDCF498AAB9B5D3E9BCDCF4BCDCF496A8B693A4B2B5D3E9BCDCF4BCDCF498ABB9B5D2E9BCDCF498AAB9B5D3E9BCDCF4BCDCF493A4B296A9B7B6D4EBBCDCF4BCDCF498ABB9B5D2E9BCDCF498AAB9B5D3E9BCDCF4BCDCF4ACC6D9AEC9DDBAD9F1BCDCF4BCDCF498ABB9B5D2E9BCDCF49BB0BFA0B5C6A2B8C9A2B8C9A2B8C9A2B8C9A2B8C9A2B8C9A2B8C998ABBAB6D4EABCDCF4B0CCE1ACC6D9ABC5D9ABC5D9ABC5D9ABC5D9ABC5D9ABC5D9ABC5D9AEC9DDBAD9F0" }

fn chip_px(pix: str, i: usize) -> paint.Color {
    let at = i * 6usize
    let ri = u32(pix_digit(pix[at]) * 16.0 + pix_digit(pix[at + 1usize]))
    let gi = u32(pix_digit(pix[at + 2usize]) * 16.0 + pix_digit(pix[at + 3usize]))
    let bi = u32(pix_digit(pix[at + 4usize]) * 16.0 + pix_digit(pix[at + 5usize]))
    ret rgb(ri * 65536u32 + gi * 256u32 + bi)
}

// The chip's fill (`color`) and ring, over the node's area: `cols` right ring columns (2 at rest, 1 hot), the ring table in `pix`.
fn chip_ring_paint(m: *Mark, b: *scene.Builder, area: geometry.Rect) -> err {
    let x0 = f32(i64(area.x + 0.5))
    let y0 = f32(i64(area.y + 0.5))
    let w = f32(i64(area.width + 0.5))
    let h = f32(i64(area.height + 0.5))
    let rr = f32(m.cols)
    let right = x0 + w - rr
    try winpx.fill(b, x0 + 1.0, y0 + 1.0, right - x0 - 1.0, h - 2.0, m.color)
    var x = x0 + 1.0
    while x < right {
        try winpx.fill(b, x, y0, 1.0, 1.0, chip_px(m.pix, 1usize))
        try winpx.fill(b, x, y0 + h - 1.0, 1.0, 1.0, chip_px(m.pix, 8usize))
        x += 1.0
    }
    var y = y0 + 1.0
    while y < y0 + h - 1.0 {
        try winpx.fill(b, x0, y, 1.0, 1.0, chip_px(m.pix, 4usize))
        try winpx.fill(b, right, y, 1.0, 1.0, chip_px(m.pix, 5usize))
        if m.cols == 2usize { try winpx.fill(b, right + 1.0, y, 1.0, 1.0, chip_px(m.pix, 6usize)) }
        y += 1.0
    }
    try winpx.fill(b, x0, y0, 1.0, 1.0, chip_px(m.pix, 0usize))
    try winpx.fill(b, right, y0, 1.0, 1.0, chip_px(m.pix, 2usize))
    try winpx.fill(b, x0, y0 + h - 1.0, 1.0, 1.0, chip_px(m.pix, 7usize))
    try winpx.fill(b, right, y0 + h - 1.0, 1.0, 1.0, chip_px(m.pix, 9usize))
    if m.cols == 2usize {
        try winpx.fill(b, right + 1.0, y0, 1.0, 1.0, chip_px(m.pix, 3usize))
        try winpx.fill(b, right + 1.0, y0 + h - 1.0, 1.0, 1.0, chip_px(m.pix, 10usize))
    }
    ret ok
}

fn chip_ring(a: *mem.Arena, fill: paint.Color, ring: str, right_cols: usize, width: f32, height: f32) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, marks_error) }
    marks[0usize] = Mark { arena: a, color: fill, inner: fill, shape: Shape.ChipRing, pix: ring, cols: right_cols, skip: 0usize }
    var size = style.defaults()
    size.width = style.Length { Px: width }
    size.height = style.Length { Px: height }
    size.min_width = style.Length { Px: width }
    size.min_height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: size, children: none }, ok)
}

// round 12: the picture column's header when it is marked (the live capture's data_grid_group, x 49 to 67, y 69 to 89): an orange bar
// and the outlined down triangle, 19 x 21
fn gx_picture_header() -> str { ret "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEDC7FFFCF5FFFFFFFFFFFFFFFFFFCFCFCFC7C7C7C7C7C7C7C7C7C7C7C7C7C7C7C7C7C7F6F6F6FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0A0FFFAEFFFFFFFFFFFFFFFFFFFAEAEAED0D0D0D8D8D8D8D8D8D8D8D8D8D8D8A9A9A9F1F1F1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0A0FFFAEFFFFFFFFFFFFFFFFFFFDEDEDEC9C9C9F6F6F6FFFFFFFFFFFFCFCFCFD6D6D6F9F9F9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0A0FFFAEFFFFFFFFFFFFFFFFFFFFFFFFFAEAEAEF1F1F1FFFFFFFFFFFFAEAEAEF1F1F1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0A0FFFAEFFFFFFFFFFFFFFFFFFFFFFFFFDEDEDEC9C9C9F6F6F6CFCFCFD6D6D6F9F9F9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0A0FFFAEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFAEAEAEF1F1F1AEAEAEF1F1F1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0A0FFFAEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDEDEDEC9C9C9D6D6D6F9F9F9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0A0FFFAEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFAEAEAEF1F1F1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF2D8FFFDF8FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDEDEDEF9F9F9FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" }
fn gx_picture_header_w() -> f32 { ret 19.0 }
fn gx_picture_header_h() -> f32 { ret 21.0 }

// round 12: a one pixel row of `base` as wide as the grid with a hot header's tint over its column: `blend` the pixel before it (x - 1),
// `main` the column's w - 1 pixels from x, `tint` the pixel after
fn ring_row(a: *mem.Arena, base: paint.Brush, x: f32, w: f32, blend: paint.Color, main: paint.Color, tint: paint.Color) -> widget.Node {
    var kids: [6]widget.Node = zero
    var before = control_dummy_box(a, base, x - 1.0)
    kids[0usize] = before
    kids[1usize] = control_dummy_box(a, paint.Brush { Solid: blend }, 1.0)
    kids[2usize] = control_dummy_box(a, paint.Brush { Solid: main }, w - 1.0)
    kids[3usize] = control_dummy_box(a, paint.Brush { Solid: tint }, 1.0)
    kids[4usize] = control_dummy_box(a, base, 0.0)
    kids[4usize].style.width = style.Length { Flex: 1.0 }
    let (held, held_error) = mem.alloc[widget.Node](a, 5usize)
    if held_error != ok { ret kids[0usize] }
    var at = 0usize
    while at < 5usize {
        held[at] = kids[at]
        at += 1usize
    }
    ret widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), held[0usize..5usize])
}

fn control_dummy_box(a: *mem.Arena, brush: paint.Brush, w: f32) -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: 1.0 }
    s.background = brush
    ret widget.box(0u64, s, zero)
}

// BEGIN GENERATED (scripts/looks_nav_top.py)
fn gx_nav_top(slot: usize, enabled: bool) -> str {
    if slot == 0usize && !enabled { ret "F0F0F0F0F0F0EEEEEEEDEDEDEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0EDEDEDEEEEEEF1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EFEFEFECECECEFEFEFF0F0F0EDEDEDEEEEEEF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EEEEEEEDEDEDF0F0F0EBEBEBF4F4F4F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9ECECECE6E6E6E9E9E9F7F7F7F9F9F9F9F9F9F1F1F1EBEBEBF7F7F7F9F9F9F9F9F9F1F1F1EBEBEBF7F7F7F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9D9D9D9DDDDDDD6D6D6F4F4F4F9F9F9F1F1F1DEDEDED6D6D6F4F4F4F9F9F9F1F1F1DEDEDED6D6D6F4F4F4F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9D3D3D3E5E5E5D1D1D1F3F3F3F0F0F0DCDCDCDDDDDDD0D0D0F3F3F3F0F0F0DCDCDCDCDCDCD0D0D0F3F3F3F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9D1D1D1E3E3E3CECECEE9E9E9D9D9D9DBDBDBE6E6E6CFCFCFE9E9E9D9D9D9DADADAE4E4E4CFCFCFF3F3F3F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9CDCDCDDFDFDFCACACAD1D1D1D8D8D8DFDFDFDEDEDECACACAD1D1D1D2D2D2D4D4D4D7D7D7C9C9C9F2F2F2F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9C9C9C9DCDCDCC6C6C6D2D2D2D7D7D7CCCCCCD2D2D2C4C4C4CCCCCCCDCDCDC2C2C2CACACAC3C3C3F2F2F2F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9C5C5C5D9D9D9C2C2C2CECECED1D1D1C4C4C4CDCDCDC0C0C0C8C8C8CACACAC3C3C3C9C9C9C0C0C0F1F1F1F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9C1C1C1D6D6D6BEBEBEC9C9C9C9C9C9CECECECFCFCFBCBCBCC9C9C9C6C6C6CBCBCBCCCCCCBCBCBCF1F1F1F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9BDBDBDD3D3D3B9B9B9E3E3E3CDCDCDC6C6C6D3D3D3B9B9B9E3E3E3CDCDCDC4C4C4CFCFCFB9B9B9F0F0F0F9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9BABABAD3D3D3B6B6B6F0F0F0EBEBEBC8C8C8C3C3C3B3B3B3EFEFEFECECECC8C8C8C2C2C2B3B3B3EFEFEFF9F9F9F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F2F2F2B9B9B9C0C0C0B3B3B3E3E3E3EAEAEADADADABEBEBEB2B2B2E3E3E3EAEAEADADADABEBEBEB2B2B2E8E8E8F8F8F8F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7EEEEEED4D4D4CCCCCCCECECEE0E0E0E3E3E3E3E3E3D9D9D9CFCFCFE0E0E0E3E3E3E3E3E3D9D9D9D1D1D1E8E8E8F7F7F7F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F5F5F5F3F3F3F2F2F2F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F3F3F3F4F4F4F8F8F8F9F9F9EBEBEBEFEFEFEAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBEFEFEFEBEBEBF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EBEBEBEFEFEFEDEDEDEDEDEDF5F5F5F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EFEFEFEDEDEDF0F0F0F0F0F0EDEDEDEEEEEEF0F0F0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EEEEEEEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0EEEEEEEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEDEDEDEFEFEFF0F0F0F0F0F0" }
    if slot == 0usize && enabled { ret "F0F0F0EEEEEEE5E5E5E1E1E1E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E4E4E4EDEDEDF0F0F0F0F0F0EEEEEEE1E1E1E0E0E0E6E6E6E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E6E6E6E2E2E2DFDFDFECECECF0F0F0E4E4E4DFDFDFF0F0F0FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4DFDFDFE1E1E1EEEEEED8D8D8EEEEEEFCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D9D9D9ECECECD4D4D4F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD7D7D7ECECECD4D4D4F7F7F7FDFDFDCBE4F8B3D8F5C1DFF7F6F9FCFDFDFDFDFDFDDFEEFAC7E2F7F5F9FCFDFDFDFDFDFDDFEEFAC7E2F7F5F9FCFDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD87C1EF7CC7F577BBEEECF4FBFDFDFDDEEDF997C9F179BAEDEBF4FBFDFDFDDEEDF997C9F179BAEDEBF4FBFDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD74B5E98AD6FB66B1EAE9F2FADDECF894C6ED7EC7F364AEE8E8F2FADEECF895C6ED7CC5F363AEE8E8F2FAFDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD70B0E484CFF861ABE4C8DFF391C1E97BC3F08BD7FB62ABE4C7DFF391C1E978C0EF87D3FA62ABE4E8F1F9FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD6BA9DE7EC9F55CA4DE7DB3E176BDEB7BC7F47BC7F35BA3DD7DB3E16CB3E469B4E46EBAEA5AA1DCE7F0F8FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD66A3D777C2F2579DD76BB3E56FBBEA58A5DF65B2E3549AD45FA8DD5DAADC4794CF56A3D85298D3E6EFF7FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD629CD173BEEF5196D065ACDD5FB0E34099D651A8DE4D92CD5AA1D550A3DA3E97D449A1DA4B91CDE5EEF6FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD5D96CA63B8ED4A8EC973A4D25CA4D744ABE440ADE8458CC873A4D2549ED33AA5E237A7E5448BC8E5EDF5FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD588FC440B3EF4087C3C0D5E881ABD34C9ED534B4F13E87C3C0D4E882ABD34499D327ADEF3C86C3E4ECF4FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7FDFDFD5389BE2AB4F43982BEE4ECF4D8E4EF7DA3C83C9AD43A7DB9E3EBF3D8E4F07DA4C83497D3397DB9E3EBF3FDFDFDFDFDFDD6D6D6ECECECD4D4D4F7F7F7F1F1F15F8AB43194D1467EB0D0D6DCE3E3E3BDC6CF6D92B74D7CACCFD5DCE3E3E3BDC6CF6E93B84E7EADD9DFE6FBFBFBFDFDFDD6D6D6ECECECD4D4D4F7F7F7EBEBEBACBBCB8FACC89CB0C4CFD2D4D6D6D6D6D6D6BBC5CEA2B3C4CFD1D4D6D6D6D6D6D6BCC6CFA5B6C7DEE0E3FAFAFAFDFDFDD6D6D6ECECECD4D4D4F7F7F7F7F7F7F3F3F3F1F1F1F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F2F2F2F5F5F5FCFCFCFDFDFDD6D6D6ECECECD5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD6D6D6ECECECD8D8D8EDEDEDFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF3F3F3D9D9D9ECECECE4E4E4DDDDDDF0F0F0FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3E0E0E0E2E2E2EEEEEEEEEEEEE1E1E1DCDCDCDBDBDBDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCD9D9D9DEDEDEECECECF0F0F0F0F0F0EEEEEEE0E0E0D6D6D6D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D6D6D6DDDDDDECECECF0F0F0F0F0F0" }
    if slot == 1usize && !enabled { ret "F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EDEDEDEEEEEEF1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EFEFEFECECECEFEFEFF0F0F0F0F0F0EDEDEDEEEEEEF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EEEEEEEDEDEDEFEFEFF0F0F0EBEBEBF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5EBEBEBEFEFEFF0F0F0EAEAEAF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F1F1F1EBEBEBF7F7F7F9F9F9F9F9F9F9F9F9F1F1F1EBEBEBF7F7F7F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F1F1F1DEDEDED6D6D6F4F4F4F9F9F9F9F9F9F1F1F1DEDEDED6D6D6F4F4F4F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F0F0F0DCDCDCDEDEDED0D0D0F3F3F3F9F9F9F0F0F0DCDCDCDDDDDDD0D0D0F3F3F3F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9EFEFEFDADADADCDCDCE7E7E7CFCFCFF2F2F2EFEFEFDADADADADADAE5E5E5CFCFCFF2F2F2F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9EFEFEFD7D7D7D9D9D9E0E0E0E0E0E0CACACAE7E7E7D7D7D7D3D3D3D4D4D4D7D7D7C9C9C9F1F1F1F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9D6D6D6D6D6D6DDDDDDD1D1D1D5D5D5C5C5C5CECECECECECECECECEC3C3C3C9C9C9C3C3C3F1F1F1F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9D5D5D5D2D2D2D7D7D7CACACACFCFCFC1C1C1CDCDCDCBCBCBCACACAC5C5C5C9C9C9C0C0C0F0F0F0F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9EDEDEDD0D0D0CBCBCBD1D1D1D2D2D2BDBDBDE4E4E4D0D0D0C6C6C6CCCCCCCDCDCDBCBCBCF0F0F0F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9ECECECCDCDCDC8C8C8D4D4D4BABABAEFEFEFECECECCDCDCDC4C4C4D0D0D0B9B9B9EFEFEFF9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9ECECECC8C8C8C4C4C4B4B4B4EFEFEFF9F9F9ECECECC9C9C9C2C2C2B3B3B3EEEEEEF9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F8F8F8F5F5F5F2F2F2DFDFDFC0C0C0B2B2B2E2E2E2EAEAEAEAEAEADADADABFBFBFB2B2B2E6E6E6F8F8F8F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F7F7F7F3F3F3EEEEEEEAEAEADCDCDCD0D0D0E0E0E0E3E3E3E3E3E3E3E3E3DADADAD1D1D1E7E7E7F7F7F7F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F8F8F8F7F7F7F5F5F5F4F4F4F3F3F3F2F2F2F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F2F2F2F4F4F4F8F8F8F9F9F9EBEBEBEFEFEFF0F0F0EAEAEAF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBEFEFEFF0F0F0EBEBEBF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EBEBEBEFEFEFF0F0F0EDEDEDEDEDEDF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EFEFEFEDEDEDEFEFEFF0F0F0F0F0F0EDEDEDEEEEEEF0F0F0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EEEEEEEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEDEDEDEFEFEFF0F0F0F0F0F0" }
    if slot == 1usize && enabled { ret "F0F0F0F0F0F0EEEEEEE5E5E5E1E1E1E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E4E4E4EDEDEDF0F0F0F0F0F0F0F0F0EEEEEEE1E1E1DFDFDFE6E6E6E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E6E6E6E2E2E2DFDFDFECECECF0F0F0F0F0F0E5E5E5DFDFDFEFEFEFFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4E0E0E0E1E1E1EEEEEEF0F0F0D9D9D9EEEEEEFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D9D9D9ECECECF0F0F0D4D4D4F5F5F5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE0EEFAC7E2F7F5F9FCFDFDFDFDFDFDFDFDFDE0EEFAC7E2F7F4F9FCFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDFEDF998C9F17ABAEDEAF3FBFDFDFDFDFDFDDFEDF998C9F17ABAEDE9F3FBFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDDEECF895C6ED80C8F364AFE8E6F1FAFDFDFDDEECF896C6EE7EC6F364AFE8E6F1FAFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDDDEBF792C2E97CC4F08CD8FB63ACE5E6F0F9DDEBF792C2E979C1EF88D4FB63ACE5E5F0F9FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDDCEAF58FBDE478BFEC7ECAF67FCBF75CA4DEC4DCF08FBDE56CB3E46AB5E46EBAEA5AA2DCE4EFF8FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFD90BBE174BAE779C5F25EADE769B7E9559BD578ADDB65ACDF5CABDD4695D053A2D85298D3E3EEF7FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFD8FB9DE6FB3E069BBEE41A2E04FADE34C93CE76A9D760A5D84AA3DC379AD841A2DD4A92CDE3EDF5FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDDAE7F386B1D85EA7D93EB0EA37B3EF448DC9C0D6EA87B1D8509ED52DA8E827AAED418CC9E2EBF4FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDD9E5F182ACD34AA1D72CB8F63D88C5E2EBF4D9E5F183ACD33C9AD618AFF53987C5E1EAF3FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFDFDFDFDFDFDD8E4F07EA4C93A9BD5397EBAE1EAF3FDFDFDD8E4F07FA5C92F97D5387DBAE0E9F2FDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFBFBFBF7F7F7F1F1F1C6CFD87196BA4D7DACCDD4DBE3E3E3E3E3E3BDC6CF6F94B84E7EADD5DCE3FBFBFBFDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFAFAFAF3F3F3EBEBEBE4E4E4C1CAD3A3B4C5CED1D4D6D6D6D6D6D6D6D6D6BCC6CFA5B6C7DBDEE0F9F9F9FDFDFDD7D7D7EBEBEBF0F0F0D4D4D4F7F7F7FDFDFDFDFDFDFCFCFCFAFAFAF7F7F7F4F4F4F2F2F2F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F2F2F2F4F4F4FCFCFCFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD6D6D6EBEBEBF0F0F0D9D9D9ECECECFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF3F3F3D9D9D9ECECECF0F0F0E4E4E4DDDDDDF0F0F0FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3E1E1E1E2E2E2EEEEEEF0F0F0EEEEEEE1E1E1DCDCDCDBDBDBDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCD9D9D9DEDEDEECECECF0F0F0F0F0F0F0F0F0EEEEEEE1E1E1D7D7D7D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D6D6D6DDDDDDECECECF0F0F0F0F0F0" }
    if slot == 2usize && !enabled { ret "F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EDEDEDEEEEEEF1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EFEFEFECECECEFEFEFF0F0F0F0F0F0EDEDEDEEEEEEF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EEEEEEEDEDEDEFEFEFF0F0F0EBEBEBF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5EBEBEBEFEFEFF0F0F0EAEAEAF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F1F1F1EBEBEBF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F1F1F1DFDFDFD6D6D6F3F3F3F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F0F0F0DDDDDDDEDEDED1D1D1F2F2F2F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F0F0F0DBDBDBDCDCDCE7E7E7D1D1D1F2F2F2F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EFEFEFDADADAD9D9D9E1E1E1E2E2E2CDCDCDF1F1F1F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9EFEFEFD7D7D7D7D7D7DDDDDDD7D7D7DDDDDDCACACAF1F1F1F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9D7D7D7D4D4D4DBDBDBD1D1D1CDCDCDD3D3D3C5C5C5F0F0F0F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9D6D6D6D0D0D0D4D4D4C8C8C8C3C3C3CACACAC0C0C0F0F0F0F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9EEEEEED1D1D1C9C9C9CBCBCBC5C5C5CACACABDBDBDEFEFEFF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EDEDEDCFCFCFC6C6C6CDCDCDCECECEBABABAEEEEEEF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECCCCCCCC4C4C4D1D1D1B8B8B8EEEEEEF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9EBEBEBC8C8C8C2C2C2B3B3B3EDEDEDF9F9F9F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F5F5F5F1F1F1EFEFEFDDDDDDBFBFBFB2B2B2E7E7E7F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF7F7F7F9F9F9F9F9F9F9F9F9F9F9F9F8F8F8F3F3F3EDEDEDE9E9E9E6E6E6DADADACFCFCFE8E8E8F7F7F7F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EAEAEAF6F6F6F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F7F7F7F5F5F5F4F4F4F3F3F3F2F2F2F1F1F1F4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9ECECECEFEFEFF0F0F0EBEBEBF3F3F3F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EBEBEBEFEFEFF0F0F0EDEDEDEDEDEDF4F4F4F8F8F8F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F9F6F6F6EFEFEFEDEDEDEFEFEFF0F0F0F0F0F0EDEDEDEEEEEEF0F0F0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1EEEEEEEDEDEDEFEFEFF0F0F0F0F0F0F0F0F0F0F0F0EEEEEEEDEDEDECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECECEDEDEDEDEDEDEFEFEFF0F0F0F0F0F0" }
    if slot == 2usize && enabled { ret "F0F0F0F0F0F0EEEEEEE5E5E5E1E1E1E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E4E4E4EDEDEDF0F0F0F0F0F0F0F0F0EEEEEEE1E1E1DFDFDFE6E6E6E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E6E6E6E2E2E2DFDFDFEBEBEBF0F0F0F0F0F0E5E5E5DFDFDFEFEFEFFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF5F5F5E0E0E0E1E1E1EEEEEEF0F0F0D9D9D9EEEEEEFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF2F2F2D9D9D9ECECECF0F0F0D5D5D5F5F5F5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE0EFFAC7E2F7F4F8FCFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCD8D8D8EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDE0EEFA9ACAF17ABBEEE8F2FBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDFEDF898C8EF80C8F366B1EAE4F0FAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDEECF795C5EB7DC4F18DD8FB66B0E8E4EFF9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDDEBF692C1E879C0EE7FCBF783CFF961A9E2E3EEF8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDDCE9F58FBDE475BBEA7AC6F46CB8F177C3F55BA3DDE2EDF7FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFD92BCE171B6E675C1F062AEE85AA6E267B3E7549BD5E1ECF6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFD91BADF6CB0DF68B4E8509FDA4796D355A3D94D92CDE1EBF5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDDBE7F388B2D95EA2D54CA5DC389AD843A3DE478DC8E0EAF4FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDAE6F285AFD5509DD331A9E82CACED3F89C6DFE9F3FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD9E5F182ABD1409BD41EB1F53885C3DEE8F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD8E4EF7FA4C83298D4377CB9DEE8F1FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF6F6F6F0F0F0ECECECC2CBD37094B94D7CACD6DDE5FBFBFBFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D5D5D5F6F6F6FDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3E9E9E9E3E3E3DDDDDDBDC7D0A2B3C5DEE1E4FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDD7D7D7EBEBEBF0F0F0D6D6D6F5F5F5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFAFAFAF6F6F6F4F4F4F2F2F2F1F1F1F0F0F0F5F5F5FCFCFCFDFDFDFDFDFDFDFDFDFCFCFCD7D7D7EBEBEBF0F0F0D9D9D9ECECECFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF3F3F3DADADAECECECF0F0F0E4E4E4DDDDDDF0F0F0FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF3F3F3E1E1E1E2E2E2EEEEEEF0F0F0EEEEEEE1E1E1DCDCDCDBDBDBDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDADADADEDEDEECECECF0F0F0F0F0F0F0F0F0EEEEEEE1E1E1D7D7D7D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D6D6D6DDDDDDEBEBEBF0F0F0F0F0F0" }
    if slot == 3usize && enabled { ret "F3F3F3F0F0F0EEEEEEE6E6E6E1E1E1E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E4E4E4ECECECF0F0F0F0F0F0F3F3F3EEEEEEE2E2E2DFDFDFE5E5E5E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E6E6E6E3E3E3DFDFDFEBEBEBF0F0F0F3F3F3E6E6E6DFDFDFEEEEEEFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF5F5F5E1E1E1E1E1E1EDEDEDF3F3F3DBDBDBECECECFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF3F3F3DBDBDBEAEAEAF3F3F3D7D7D7F3F3F3FDFDFDFDFDFDFDFDFDFDFDFDD0E6F8D6E9F9F6F9FCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD93C7F189C2EFCAE3F7F6F9FCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD82BDEC78C3F289C3EFC9E1F5F5F9FCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD80BAE986D1F880CBF586C0EBC7E0F4F5F9FCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD7CB5E57BC6F381CDF878C3F182BBE7C6DEF2F5F8FBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD79B0E074BFF06AB6EF70BCEE6EB8E87DB5E2C4DBF0F5F8FBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD75ABDB69B5E759A6DF4E9BD75DAADD61ABDE78AFDDE2EDF6FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD71A6D558AADF439BD73C95D34DA2DA5AA4D876ACD9E1ECF5FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD6DA1D045A8E22EA2E33AA8E54EA2D971A7D5C1D7EBF4F8FAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD6A9CCB32ABE929B2F33FA2DC6CA4D2C0D5E9F4F7FAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD6697C729AEEE34A3E067A0CFBED3E7F4F7FAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFDFDFD6393C33193D06299C6BDD1E4F4F7FAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDFAFAFA6F96BB5D88B2A6B7C8DFE1E3ECECECF0F0F0F8F8F8FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F4F4F4FDFDFDFDFDFDFDFDFDF8F8F8B3C2D0B2BFCBD2D4D6DEDEDEE4E4E4EAEAEAF5F5F5FCFCFCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F3F3F3D7D7D7F3F3F3FDFDFDFDFDFDFDFDFDFBFBFBF4F4F4F0F0F0F1F1F1F2F2F2F5F5F5F7F7F7FAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDADADAE9E9E9F3F3F3DBDBDBEAEAEAFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF4F4F4DBDBDBEAEAEAF3F3F3E5E5E5DDDDDDEEEEEEFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4E2E2E2E2E2E2EDEDEDF3F3F3EEEEEEE2E2E2DCDCDCDBDBDBDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDADADADEDEDEEBEBEBF0F0F0F3F3F3F0F0F0EEEEEEE2E2E2D7D7D7D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D6D6D6DCDCDCEBEBEBF0F0F0F0F0F0" }
    if slot == 4usize && enabled { ret "F0F0F0F0F0F0EEEEEEE6E6E6E1E1E1E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E4E4E4ECECECF0F0F0F0F0F0F0F0F0EEEEEEE2E2E2DFDFDFE5E5E5E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E6E6E6E3E3E3DFDFDFEAEAEAF0F0F0F0F0F0E6E6E6DFDFDFEEEEEEFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF5F5F5E1E1E1E1E1E1EDEDEDF0F0F0DBDBDBECECECFBFBFBFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF3F3F3DBDBDBEAEAEAF0F0F0D7D7D7F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDBDBDBE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFDD0E7F8D6E9F9F5F9FCFDFDFDFDFDFDFDFDFDD1E7F8D5E9F9F5F9FCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFD94C8F188C1EFC9E2F6F5F9FCFDFDFDFDFDFD95C8F188C1EFC8E2F6F5F9FCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFD83BDEB77C2F187C2EEC7E0F4F5F9FCFDFDFD84BDEC77C2F187C2EEC7E0F4F5F9FCFDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFD7FB8E785D1F781CCF484BEE9C6DEF2F5F8FB80B9E784CFF77DC8F383BDE9C5DEF2F5F8FBFDFDFDFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFD7CB3E17BC6F384D0F979C3F080B8E4C4DCF073AEDF6EB9E96DB9E768B2E37DB5E2C3DBF0F4F8FBFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFD77ADDC74BFEE6CB9F06DBBEC69B5E57AB1DE5B9CD45BA7DB4997D255A4D95AA6DC76AEDCE0ECF6FDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFD73A7D667B7EA50ADE956B0E660ACDE77ADDA5796CE4BA4DC3A9CDA41A0DB519FD674AAD8E0EBF5FDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFD6FA1D04BB1E942B6EF51A8DD72A8D5C0D6EB669CCD35A6E52CACEC409FDA6EA5D4C0D6EAF4F7FAFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFD6A9BCA3AB2ED44A9E16BA3D1BED4E8F4F7FA6B9CCA24AAEC2FA0DF66A1D1BED3E8F4F7FAFDFDFDFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDFDFDFD6696C53B96D1649BC7BCD1E4F3F7FAFDFDFD6797C52D91D0609AC7BCD0E4F3F6F9FDFDFDFDFDFDFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDF2F2F27095BB5E89B3A4B6C7DADCDEE3E3E3E3E3E36C92B75D88B3A8BACBE3E5E7F2F2F2F7F7F7FBFBFBFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDEDEDEDB3C1CFB4C1CDD0D2D5D6D6D6D6D6D6D6D6D6ABB9C7B3C0CCD6D9DBE5E5E5EDEDEDF4F4F4FAFAFAFDFDFDFDFDFDDADADAE9E9E9F0F0F0D7D7D7F3F3F3FDFDFDF7F7F7F4F4F4F1F1F1F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F1F1F1F2F2F2F5F5F5F7F7F7FAFAFAFCFCFCFDFDFDFDFDFDDADADAE9E9E9F0F0F0D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDADADAE9E9E9F0F0F0DBDBDBEAEAEAFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF4F4F4DCDCDCEAEAEAF0F0F0E5E5E5DDDDDDEEEEEEFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4E2E2E2E2E2E2EDEDEDF0F0F0EEEEEEE2E2E2DCDCDCDBDBDBDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDADADADEDEDEEBEBEBF0F0F0F0F0F0F0F0F0EEEEEEE2E2E2D7D7D7D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D6D6D6DCDCDCEAEAEAF0F0F0F0F0F0" }
    if slot == 5usize && enabled { ret "F0F0F0F0F0F0EEEEEEE6E6E6E1E1E1E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E4E4E4ECECECF0F0F0F0F0F0F0F0F0EEEEEEE2E2E2DFDFDFE5E5E5E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E6E6E6E3E3E3DFDFDFEAEAEAF0F0F0F0F0F0E6E6E6DFDFDFEDEDEDFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF5F5F5E2E2E2E0E0E0EDEDEDF0F0F0DBDBDBEBEBEBFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF3F3F3DCDCDCE9E9E9F0F0F0D7D7D7F1F1F1FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFDD1E7F8D5E9F9F5F9FCFDFDFDFDFDFDD1E7F8D5E9F9F5F9FCFDFDFDFDFDFDD1E7F8B5D9F5BFDEF6EFF6FCFDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFD96C8F188C1EFC8E2F6F5F9FCFDFDFD96C9F188C1EFC7E2F6F5F9FCFDFDFD96C9F17AC4F478BCEFDCECF9FDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFD85BEEC77C2F187C2EEC6E0F4F4F8FC85BEEC76C1F187C2EEC6E0F4F4F8FC85BEEC82CEF86BB6ECD7E9F8FDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFD81B9E784CFF67FCBF484BEE9C5DDF279B5E582CDF67DC8F383BDE9C4DDF279B5E57BC6F466AFE7D6E8F6FDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFD7EB4E279C4F281CDF878C2F080B8E561A3DB71BCEC72BEEC6CB6E77DB6E361A3DB69B4E75DA5DED5E6F4FDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFD79AEDC73BDEE6EBAF175C2F36EB8E8579DD661ACDF509DD65AA7DB60AADE559BD557A2D8539AD4D3E4F3FDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFD75A8D66EB8EB63B3ED66B8ED66AFE05196CF53A5DA429AD64BA1D958A3D74F93CD4C9FD74C94CFD2E2F1FDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFD71A3D15FB2E85BB9EF59A9DD72A8D5528FC742A5DF3EABE64BA0D86FA6D4528FC73BA0DD428FCBD1E0EFFDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFD6C9DCB4CB2E94EA8DE6CA3D0BDD3E76397C835AAE73EA2DC69A1D0BDD3E76397C827A3E6388BC9CFDFEDFDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2FDFDFD6898C64096CF659BC7BBD0E3F3F6F96998C63692CF629AC7BBCFE3F3F6F96998C61AA6EB3087C6CEDDECFDFDFDFDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2F2F2F27197BB5D88B3A3B5C6D9DCDEE3E3E36E93B85C87B2A3B5C6D9DBDEE3E3E36E93B82A8DCB4181B6C7D3DEF9F9F9FDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2EDEDEDB3C1CFB3C0CCCFD2D5D6D6D6D6D6D6ACBAC8B1BECBCFD2D4D6D6D6D6D6D6ACBAC891ACC79DB2C7D6DBDFF8F8F8FDFDFDDBDBDBE8E8E8F0F0F0D7D7D7F2F2F2F8F8F8F4F4F4F1F1F1F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F2F2F2F5F5F5FBFBFBFDFDFDDBDBDBE8E8E8F0F0F0D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCDBDBDBE8E8E8F0F0F0DBDBDBEAEAEAFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF4F4F4DCDCDCE9E9E9F0F0F0E5E5E5DDDDDDEEEEEEFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4E2E2E2E2E2E2EDEDEDF0F0F0EEEEEEE2E2E2DCDCDCDBDBDBDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDADADADDDDDDEAEAEAF0F0F0F0F0F0F0F0F0EEEEEEE2E2E2D7D7D7D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D6D6D6DCDCDCEAEAEAF0F0F0F0F0F0" }
    if slot == 7usize && enabled { ret "F0F0F0EEEEEEE6E6E6E2E2E2E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E0E4E4E4ECECECEFEFEFF0F0F0EEEEEEE3E3E3DFDFDFE5E5E5E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E7E6E6E6E3E3E3E0E0E0EAEAEAEFEFEFE6E6E6DFDFDFEDEDEDFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF5F5F5E2E2E2E0E0E0ECECECDCDCDCEBEBEBFAFAFAFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDF3F3F3DCDCDCE9E9E9D8D8D8F1F1F1FDFDFDE9E9E9D7D7D7CDCDCDCACACAC9C9C9C2C2C2BBBBBBBBBBBBBFBFBFC5C5C5CCCCCCD3D3D3DEDEDEF6F6F6FDFDFDFCFCFCDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDCFCFCFC8C8C8C3C3C3BDBDBDB6B6B6AAAAAC9A9AA09999A1A2A2ABAFAFB8BCBCC5C8C8D0C1C1C4EDEDEDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDC9C9C9C5C5C5D1D1D1CBCBCBC1C1C1B6B6B8A4A4ADA2A2AEADADBABBBBC9CACAD7CBCBD4BBBBBDEBEBEBFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDE3E3E3B6B6B6C8C8C8C6C6C6B7B7B7ABABAC9898A19797A4A4A4B2B7B7C4C7C7D4B4B4B7CECECEF4F4F4FDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDD3D3D3C0C0C0CCCCCCC4C4C4BABABBA4A4AFA2A2B3B3B3C5C7C7D9C1C1CBC4C4C6EFEFEFFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDF2F2F2C7C7C7B6B6B6C2C2C2C0C0C0A7A7B1A7A7B8BBBBCDB4B4BFBABABDE2E2E2F9F9F9FDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDF0F0F0C5C5C5B2B2B2BEBEBFABABB4ACACBCA8A8B3B1B1B3DEDEDEF9F9F9FDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDEFEFEFC3C3C3A9A9A9AAAAB49C9CA6A6A6A8DADADAF8F8F8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDEFEFEF9D9D9DA8A8B489898DCCCCCCF8F8F8FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA1A1A1A8A8B489898DDCDCDCFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA2A2A2A9A9B48A8A8EDDDDDDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA4A4A4A9A9B58E8E91DEDEDEFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDA8A8A8ABABB6929295DFDFDFFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D8D8D8F2F2F2FDFDFDFDFDFDFCFCFCF7F7F7F2F2F2F0F0F0A3A3A3AFAFBA949497D6D6D6F0F0F0F3F3F3F9F9F9FCFCFCFDFDFDFDFDFDFDFDFDDCDCDCE8E8E8D9D9D9F1F1F1FDFDFDFDFDFDFAFAFAEBEBEBDBDBDBD7D7D796969697979D9B9B9DC8C8C8D7D7D7E0E0E0F2F2F2FBFBFBFDFDFDFDFDFDFCFCFCDBDBDBE8E8E8DCDCDCE9E9E9FAFAFAFDFDFDFBFBFBF1F1F1E6E6E6E3E3E3C6C6C6BCBCBCD0D0D0E0E0E0E3E3E3EAEAEAF6F6F6FCFCFCFDFDFDFDFDFDF4F4F4DCDCDCE9E9E9E5E5E5DEDEDEEDEDEDF9F9F9FDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFCFCFCF4F4F4E3E3E3E2E2E2EDEDEDEEEEEEE3E3E3DCDCDCDBDBDBDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDADADADDDDDDEAEAEAEFEFEFF0F0F0EEEEEEE2E2E2D8D8D8D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D5D6D6D6DCDCDCEAEAEAEFEFEFF0F0F0" }
    ret ""
}
// END GENERATED
