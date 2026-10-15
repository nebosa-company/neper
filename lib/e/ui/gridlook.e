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
    group_flat: bool
}

// A colour from 0xRRGGBB.
fn rgb(value: u32) -> paint.Color {
    let r = f32((value >> 16u32) & 255u32) / 255.0
    let g = f32((value >> 8u32) & 255u32) / 255.0
    let b = f32(value & 255u32) / 255.0
    ret paint.rgba(r, g, b, 1.0)
}

// MTG Studio v3's grid.
fn v3() -> Look {
    ret Look {
        on: true,
        row_height: 19.0,
        header_height: 21.0,
        pad: 4.0,
        text_size: 10.35,
        header: rgb(0xFFFFFFu32),
        header_hover: rgb(0xD9EBF9u32),
        header_line: rgb(0xC6C6C6u32),
        even: rgb(0xFFFFFFu32),
        odd: rgb(0xEFEFEFu32),
        selected: rgb(0xA6D2FFu32),
        selected_line: rgb(0x83878Bu32),
        line: rgb(0xDEDEDEu32),
        group_row: rgb(0xF0F0F0u32),
        footer_band: rgb(0xFFFFDDu32),
        footer_cell: rgb(0xE7EAEAu32),
        frame: rgb(0x828790u32),
        track: rgb(0xF0F0F0u32),
        thumb: rgb(0x858585u32),
        scroll_width: 16.0,
        group_flat: true
    }
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

type Shape = enum u8 { StarOutline, StarFilled, Left, Right, FirstBar, LastBar, UpOutline, PlusBox, MinusBox, DoubleLeft, DoubleRight, ArrowDown, ArrowUp, Check, ListGlyph, Minus, ArrowLong, DotLine, DotEdges }

type Mark = struct { arena: *mem.Arena, color: paint.Color, inner: paint.Color, shape: Shape }

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
            try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x, y: ry, width: area.width * 0.2, height: area.height * 0.12 }, brush: paint.Brush { Solid: m.color } } })
            try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x + area.width * 0.35, y: ry, width: area.width * 0.65, height: area.height * 0.12 }, brush: paint.Brush { Solid: m.inner } } })
            row_at += 1.0
        }
        ret ok
    }
    if m.shape == Shape.ArrowLong {
        // v3's editing indicator: a shaft with a solid head, pointing right
        try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x, y: area.y + area.height * 0.38, width: area.width * 0.62, height: area.height * 0.24 }, brush: paint.Brush { Solid: m.color } } })
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
            try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x + dx, y: area.y, width: 1.0, height: 1.0 }, brush: paint.Brush { Solid: m.color } } })
            try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x + dx, y: area.y + area.height - 1.0, width: 1.0, height: 1.0 }, brush: paint.Brush { Solid: m.color } } })
            dx += 2.0
        }
        if m.shape == Shape.DotEdges {
            var dy: f32 = 0.0
            while dy < area.height {
                try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x, y: area.y + dy, width: 1.0, height: 1.0 }, brush: paint.Brush { Solid: m.color } } })
                dy += 2.0
            }
        }
        ret ok
    }
    if m.shape == Shape.Minus {
        try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x, y: area.y + area.height * 0.4, width: area.width, height: area.height * 0.2 }, brush: paint.Brush { Solid: m.color } } })
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
    marks[0usize] = Mark { arena: a, color: color, inner: inner, shape: shape }
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
