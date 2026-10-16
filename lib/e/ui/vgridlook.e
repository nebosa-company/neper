// The Windows look of the vertical grid (v3's TcxVerticalGrid, Deck Properties): the frame, the
// category bands and the row cells as one painted node, measured pixel for pixel from the live
// 100 % capture docs/ui/looks/ref/windows/dialogs/deck-properties@1x.png (the grid crop is
// docs/ui/looks/ref/windows/vertical_grid.png). The grid's text and editors are laid over this
// node by `collection.property_grid_of`; this module only paints.
//
// Geometry (logical px = capture px; every y is relative to the node, the frame is 1 px):
//   band      22 tall: a top line, 20 rows of a left-to-right gradient #D2D2D2 .. #B7B7B7, a bottom
//             line, the grid's double chevron at x 312 (pointing up open, down shut)
//   row       the content `row_h` - 2 = 17 tall, then a dark and a light hairline; a 1 px hairline
//             also tops the first row of a group; the left 14 px is a #F0F0F0 gutter, header cells
//             are white (the selected row's #0078D7), a 2 px dark/light line separates the value
//   selected  the header #0078D7 with a lighter top and bottom line, a dotted focus rectangle
//             round the value cell
//
// ponytail: the hairline pair is one fixed colour; the capture drifts 0.013 px per row (its
// lines sit at fractional positions) which shows as up to 8 levels difference; the frame's side
// colours are measured, they look like the classic edit-control bevel.

use e.mem
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.winpx
use e.ui.widget

// What to paint: band tops, whether each is the first band and open; row content tops, whether
// each is selected, first in its group, last in its group; the overall size.
type Frame = struct { width: f32, height: f32, bands: []const f32, firsts: []const bool, opens: []const bool, rows: []const f32, selected: []const bool, tops: []const bool, lasts: []const bool, name_width: f32, stops: []const paint.Stop, heights: []const f32, hs1: []const f32, hs2: []const f32, vs1: []const f32, vs2: []const f32 }

fn measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

fn fill(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, value: u32) -> err {
    ret winpx.fill(b, x, y, w, h, style.hex(value))
}

// A rectangle filled with a left-to-right gradient of `stops` (offsets 0..1 across x .. x + span).
fn across(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, span: f32, stops: []const paint.Stop) -> err {
    let brush = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: x, y: y }, end: geometry.Point { x: x + span, y: y }, stops: stops } }
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: x, y: y, width: w, height: h }, brush: brush } })
}

fn stop(offset: f32, value: u32) -> paint.Stop {
    ret paint.Stop { offset: offset, color: style.hex(value) }
}

fn hexval(c: u8) -> u32 {
    if c >= 97u8 { ret u32(c) - 87u32 }
    ret u32(c) - 48u32
}

// The double chevron's coverage: 11 rows by 11 columns of alpha, two hex digits each, #767676 over
// the band (the capture's pixels, the two chevrons overlapping in the middle row).
fn chevron_alpha() -> str {
    ret "00000000007e2300000000000000007eebb4230000000000007eebffffb423000000007eebff81dcffb423000000c8ff81144bdcff370000004b5e147e234b5e1400000000007eebb4230000000000007eebffffb423000000007eebff81dcffb423000000c8ff81144bdcff370000004b5e1400004b5e1400"
}

// The double chevron at (x, y); `down` turns it over.
fn chevron(b: *scene.Builder, x: f32, y: f32, down: bool) -> err {
    let alpha = chevron_alpha()
    var row = 0usize
    while row < 11usize {
        var at = row
        if down { at = 10usize - row }
        var column = 0usize
        while column < 11usize {
            let i = (at * 11usize + column) * 2usize
            let v = hexval(alpha[i]) * 16u32 + hexval(alpha[i + 1usize])
            if v > 0u32 {
                var ink: f32 = 0.4627
                if style.windark_active() { ink = 0.72 }
                try winpx.fill(b, x + f32(column), y + f32(row), 1.0, 1.0, paint.rgba(ink, ink, ink, f32(v) / 255.0))
            }
            column += 1usize
        }
        row += 1usize
    }
    ret ok
}

// A dotted rectangle: 1 px dots every 2 px along the four edges.
fn dotted(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, value: u32) -> err {
    var dx: f32 = 0.0
    while dx < w {
        try fill(b, x + dx, y, 1.0, 1.0, value)
        try fill(b, x + dx + 1.0, y + h - 1.0, 1.0, 1.0, value)
        dx += 2.0
    }
    var dy: f32 = 1.0
    while dy < h {
        try fill(b, x, y + dy, 1.0, 1.0, value)
        try fill(b, x + w - 1.0, y + dy, 1.0, 1.0, value)
        dy += 2.0
    }
    ret ok
}

fn frame_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let f = mem.cast[*Frame](ctx)
    let x = area.x
    let y = area.y
    let w = area.width
    let h = area.height
    let value_x = f.name_width + 1.0
    try fill(b, x, y, w, h, 0xFFFFFFu32)
    var r = 0usize
    var k = 0u32
    while r < f.rows.len {
        let top = y + f.rows[r]
        let dark_x = x + value_x
        // the capture's hairlines drift 0.013 px a row (fractional layout): dark C6 -> CE, light D9 -> D2
        // looks5-e: the drift follows the row's place down the grid, not the category (live capture: #C5C5C8 over #DADADB
        // at the first row, #D1D1D3 over #CECED0 at y 234, #D8D8D9 over #C7C7CA at y 337)
        // looks13-r2: refitted on both Deck Properties states (the first row 0, #C7 at row top 62, #D8 at 320): +2 at row top 62, 0.0659 a pixel
        var drift = (f.rows[r] - 62.0) * 0.0659 + 2.0
        if drift < 0.0 { drift = 0.0 }
        k = u32(drift + 0.5)
        let dark = 0xC5C5C8u32 + k * 0x010101u32
        let light = 0xDADADBu32 - k * 0x010101u32
        // looks5-e: a row may be taller than 17 (Deck Properties' Computed rows), with extra cell lines in its header and value
        var rh: f32 = 17.0
        if r < f.heights.len { rh = f.heights[r] }
        var tall = rh + 3.0
        // looks13-r2: the grid's last row ends its gutter at its own hairline (live capture: the gutter stops at y 338)
        if r + 1 == f.rows.len { tall = rh + 1.0 }
        // the gutter and its line, over the whole row (hairline row included)
        try fill(b, x + 1.0, top - 1.0, 13.0, tall, 0xF0F0F0u32)
        try fill(b, x + 1.0, top - 1.0, 1.0, tall, 0xEFEFEFu32)
        try fill(b, x + 14.0, top - 1.0, 1.0, tall, 0xA1A1A5u32)
        // the line between the header and the value cell
        try fill(b, dark_x, top - 1.0, 1.0, tall, 0xABABAEu32)
        try fill(b, dark_x + 1.0, top - 1.0, 1.0, tall, 0xF4F4F5u32)
        if r < f.hs1.len && f.hs1[r] > 0.0 {
            try fill(b, x + f.hs1[r], top, 1.0, rh, 0xA6A6AAu32)
            try fill(b, x + f.hs1[r] + 1.0, top, 1.0, rh, 0xF8F8F9u32)
        }
        if r < f.hs2.len && f.hs2[r] > 0.0 {
            try fill(b, x + f.hs2[r], top, 1.0, rh, 0xA8A8ABu32)
            try fill(b, x + f.hs2[r] + 1.0, top, 1.0, rh, 0xF7F7F8u32)
        }
        if r < f.vs1.len && f.vs1[r] > 0.0 {
            try fill(b, x + f.vs1[r], top, 1.0, rh, 0xB0B0B3u32)
            try fill(b, x + f.vs1[r] + 1.0, top, 1.0, rh, 0xEFEFF0u32)
        }
        if r < f.vs2.len && f.vs2[r] > 0.0 {
            try fill(b, x + f.vs2[r], top, 1.0, rh, 0xB3B3B6u32)
            try fill(b, x + f.vs2[r] + 1.0, top, 1.0, rh, 0xEEEEEFu32)
        }
        // looks11-g1: the first row's top hairline drifts too (live capture: #DBDBDD at y 23, #CFCFD1 at y 216)
        var top_drift = (f.rows[r] - 24.0) * 0.0622
        if top_drift < 0.0 { top_drift = 0.0 }
        if f.tops[r] { try fill(b, x + 15.0, top - 1.0, w - 16.0, 1.0, 0xDBDBDDu32 - u32(top_drift + 0.5) * 0x010101u32) }
        if f.selected[r] {
            if style.windark_active() {
                // (round 7) the focused row's header: #264F78 between #3A6EA5 lines
                try winpx.fill(b, x + 15.0, top - 1.0, value_x - 15.0, 1.0, style.hex_raw(0x3A6EA5u32))
                try winpx.fill(b, x + 15.0, top, value_x - 15.0, rh, style.hex_raw(0x264F78u32))
                try winpx.fill(b, x + 15.0, top + rh, value_x - 15.0, 1.0, style.hex_raw(0x3A6EA5u32))
            } else {
                // looks11-g1: the selected header's two lines drift towards each other down the grid (live capture: #3D87C4 / #6190B8 at the
                // first row, #488AC0 / #568DBC at y 137): 0.0965 levels a pixel, green by a quarter and blue by a third of that
                var sel_k = (f.rows[r] - 24.0) * 0.0965
                if sel_k < 0.0 { sel_k = 0.0 }
                let kr = u32(sel_k + 0.5)
                let kg = u32(sel_k * 0.27 + 0.5)
                let kb = u32(sel_k * 0.36 + 0.5)
                try fill(b, x + 15.0, top - 1.0, value_x - 15.0, 1.0, ((0x3Du32 + kr) << 16u32) | ((0x87u32 + kg) << 8u32) | (0xC4u32 - kb))
                try fill(b, x + 15.0, top, value_x - 15.0, rh, 0x0078D7u32)
                try fill(b, x + 15.0, top + rh, value_x - 15.0, 1.0, ((0x61u32 - kr) << 16u32) | ((0x90u32 - kg) << 8u32) | (0xB8u32 + kb))
            }
        }
        // the hairlines under the row; the last row's light one is the next band's top line
        if f.selected[r] {
            try fill(b, dark_x + 2.0, top + rh, w - value_x - 3.0, 1.0, 0xB7B7BAu32)
        } else {
            try fill(b, x + 15.0, top + rh, w - 16.0, 1.0, dark)
        }
        if f.lasts[r] { try fill(b, x + 1.0, top + rh, 13.0, 1.0, 0xC7C7C9u32) }
        if r + 1 == f.rows.len {
            // looks13-r2: the grid's last row: the gutter's hairline pair (live capture: #CFCFD1 at y 337, #C7C7CA across the gutter and its line at y 338)
            try fill(b, x + 1.0, top + rh, 13.0, 1.0, 0xCFCFD1u32)
            try fill(b, x + 1.0, top + rh + 1.0, 14.0, 1.0, 0xC7C7CAu32)
        }
        // looks11-g1: the grid's last row has no band under it, so its light hairline is its own (live capture: #C7C7CA at y 338)
        if !f.lasts[r] || r + 1 == f.rows.len { try fill(b, x + 15.0, top + rh + 1.0, w - 16.0, 1.0, light) }
        r += 1usize
    }
    // the frame: classic edit-control bevel colours, measured
    try fill(b, x, y, w, 1.0, 0xAAADB3u32)
    try fill(b, x, y + 1.0, 1.0, h - 1.0, 0x828790u32)
    try fill(b, x + w - 1.0, y + 1.0, 1.0, h - 1.0, 0x9DA1A8u32)
    try fill(b, x + 1.0, y + h - 1.0, w - 2.0, 1.0, 0xD2D4D7u32)
    var i = 0usize
    while i < f.bands.len {
        let top = y + f.bands[i]
        var edge = 0xB8B8BAu32
        var seam = 0xE0E0E0u32
        var base = 0xB8B8BAu32
        if f.firsts[i] {
            edge = 0xB4B5B9u32
            seam = 0xE4E4E4u32
            base = 0xB2B2B5u32
        }
        // looks13-r2: a band right under a shut band (live capture, General pressed): its top line #BEBEBF and the first band's seam and
        // base; a shut band keeps no gutter seam when another band follows it directly
        var stacked = false
        if i > 0usize && !f.opens[i - 1usize] && f.bands[i] - f.bands[i - 1usize] < 22.5 {
            stacked = true
            edge = 0xBEBEBFu32
            seam = 0xE4E4E4u32
            base = 0xB2B2B5u32
        }
        var gutter_seam = true
        if !f.opens[i] && i + 1usize < f.bands.len && f.bands[i + 1usize] - f.bands[i] < 22.5 { gutter_seam = false }
        // the gradient: constant to x 230, down to #B7B7B7 at 318, constant after
        try across(b, x + 1.0, top + 1.0, w - 2.0, 20.0, 328.0, f.stops)
        try fill(b, x + 1.0, top, w - 2.0, 1.0, edge)
        if gutter_seam { try fill(b, x + 1.0, top + 21.0, 13.0, 1.0, seam) } else { try fill(b, x + 1.0, top + 21.0, 13.0, 1.0, base) }
        try fill(b, x + 14.0, top + 21.0, w - 15.0, 1.0, base)
        // looks13-r2: the base line darkens with the gradient from x 230 (live capture: #B2 -> #A9 at x 328 in the first band, #B8 -> #AC in the others)
        var shade: f32 = 12.0
        if f.firsts[i] || stacked { shade = 9.0 }
        var gx: f32 = 230.0
        while gx < w - 1.0 {
            var kk = (gx - 230.0) * shade / 98.0
            if kk > shade { kk = shade }
            let dd = u32(kk + 0.5)
            if dd > 0u32 { try fill(b, x + gx, top + 21.0, 1.0, 1.0, base - dd * 0x010101u32) }
            gx += 1.0
        }
        try fill(b, x + w - 1.0, top, 1.0, 22.0, 0x8E9199u32)
        try chevron(b, x + 312.0, top + 5.0, !f.opens[i])
        i += 1usize
    }
    // the focus rectangle of the selected row: dots round its value cell, over the frame's edge
    r = 0usize
    while r < f.rows.len {
        if f.selected[r] {
            var dh: f32 = 17.0
            if r < f.heights.len { dh = f.heights[r] }
            try dotted(b, x + value_x + 1.0, y + f.rows[r] - 1.0, w - value_x - 2.0, dh + 1.0, 0x6A6A6Au32)
        }
        r += 1usize
    }
    ret ok
}

// The painted node, `f.width` by `f.height`; `f` outlives the frame like any widget context.
fn node(a: *mem.Arena, f: Frame) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[Frame](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    let (ramp, ramp_error) = mem.alloc[paint.Stop](a, 4usize)
    if ramp_error != ok { ret (zero, ramp_error) }
    // the band's gradient: constant to x 230, down to #B7B7B7 at 318, constant after (of 328)
    ramp[0usize] = stop(0.0, 0xD2D2D2u32)
    ramp[1usize] = stop(100.0 / 328.0, 0xD1D1D1u32)
    ramp[2usize] = stop(230.0 / 328.0, 0xD0D0D0u32)
    ramp[3usize] = stop(318.0 / 328.0, 0xB7B7B7u32)
    held[0usize] = f
    held[0usize].stops = ramp[0usize..4usize]
    var s = style.defaults()
    s.width = style.Length { Px: f.width }
    s.height = style.Length { Px: f.height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&held[0usize]), measure: measure, paint: frame_paint, state: widget.bytes_of[Frame](&held[0usize]) } }, style: s, children: none }, ok)
}
