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

use e.mem
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
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
    frame: paint.Color
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
        line: rgb(0xE6E6E6u32),
        group_row: rgb(0xF0F0F0u32),
        footer_band: rgb(0xFFFFDDu32),
        footer_cell: rgb(0xE7EAEAu32),
        frame: rgb(0x828790u32)
    }
}

// The theme's own look: `on` false, nothing overridden.
fn theme() -> Look {
    var look: Look = zero
    ret look
}

// ---- small marks the grid draws itself (the favourite star, the navigator's arrows) --------

type Shape = enum u8 { StarOutline, StarFilled, Left, Right, FirstBar, LastBar }

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
    let x0 = area.x
    let x1 = area.x + area.width
    let y0 = area.y
    let y1 = area.y + area.height
    let bar = area.width * 0.18
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
