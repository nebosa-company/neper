// Pixel art at any device scale. The Windows look draws controls from tiles baked from 100 % captures; at a render
// scale of 1.25, 1.5 or 2 a 1 px rectangle lands on fractional device pixels and shows as a dotted seam, a lost
// border or blur. `fill` places a rectangle on whole device pixels instead: each edge is rounded to the nearest
// device pixel, so the tile's neighbours share edges (no seams, no overlaps) and every pixel of the tile is a
// nearest-neighbour scaled block. At scale 1 it is the plain rectangle, so the 100 % renders are unchanged.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.math
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

fn edge(v: f32, scale: f32) -> f32 {
    ret math.floor[f32](v * scale + 0.5) / scale
}

// The origin of a tile at logical `v`, moved to a whole device pixel (at scale 1 itself, unless the scale check forces it):
// a tile painted from its own snapped origin is the nearest-neighbour scaling of the 1.0 tile wherever the layout put it, so
// its 1 px lines (a button's ring, the focus dots) have the same device thickness on all four sides.
fn origin(b: *scene.Builder, v: f32) -> f32 {
    let scale = scene.builder_scale(b)
    if scale == 1.0 && !scene.pixel_exact_at_one_on() { ret v }
    ret edge(v, scale)
}

// A solid rectangle in logical px, its edges moved to whole device pixels (at least one device pixel wide and high).
fn fill(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, color: paint.Color) -> err {
    let scale = scene.builder_scale(b)
    var rect = geometry.Rect { x: x, y: y, width: w, height: h }
    if scale != 1.0 || scene.pixel_exact_at_one_on() {
        let x0 = edge(x, scale)
        let y0 = edge(y, scale)
        var x1 = edge(x + w, scale)
        var y1 = edge(y + h, scale)
        if x1 <= x0 { x1 = x0 + 1.0 / scale }
        if y1 <= y0 { y1 = y0 + 1.0 / scale }
        rect = geometry.Rect { x: x0, y: y0, width: x1 - x0, height: y1 - y0 }
    }
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: rect, brush: paint.Brush { Solid: color } } })
}

// ---- nodes ------------------------------------------------------------------------------------------------------

type Dots = struct { count: usize, codes: []const u8, colors: []const paint.Color, parity: u32, color: paint.Color, across: u32, down: u32, dither: bool }

fn dots_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

// The pixels of a dots node or a dither, each on whole device pixels (`fill`), from the node's origin.
fn dots_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let d = mem.cast[*Dots](ctx)
    if d.dither {
        var y = 0u32
        while y < d.down {
            var x = 0u32
            while x < d.across {
                if (x + y) % 2u32 == d.parity { try fill(b, area.x + f32(x), area.y + f32(y), 1.0, 1.0, d.color) }
                x += 1u32
            }
            y += 1u32
        }
        ret ok
    }
    var i = 0usize
    while i < d.count {
        let code = u32(d.codes[i])
        try fill(b, area.x + f32(code / 16u32), area.y + f32(code % 16u32), 1.0, 1.0, d.colors[i])
        i += 1usize
    }
    ret ok
}

fn dots_node(a: *mem.Arena, d: Dots, w: f32, h: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[Dots](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = d
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&held[0usize]), measure: dots_measure, paint: dots_paint, state: widget.bytes_of[Dots](&held[0usize]) } }, style: s, children: none }, ok)
}

// A bitmap of single pixels: pixel i at (codes[i] / 16, codes[i] % 16) in colors[i], painted in order.
fn sprite(a: *mem.Arena, codes: []const u8, colors: []const paint.Color, w: f32, h: f32) -> (widget.Node, err) {
    let (node, node_error) = dots_node(a, Dots { count: codes.len, codes: codes, colors: colors, parity: 0u32, color: colors[0usize], across: 0u32, down: 0u32, dither: false }, w, h)
    ret (node, node_error)
}

// Every other pixel of a `w` x `h` box, those where x + y has `parity` (0 or 1), in `color`.
fn dither(a: *mem.Arena, w: u32, h: u32, parity: u32, color: paint.Color) -> (widget.Node, err) {
    var none: []const u8 = zero
    var none_colors: []const paint.Color = zero
    let (node, node_error) = dots_node(a, Dots { count: 0usize, codes: none, colors: none_colors, parity: parity, color: color, across: w, down: h, dither: true }, f32(w), f32(h))
    ret (node, node_error)
}

// ---- the dark palette: light tiles mapped to Windows 11 dark ------------------------------------------------------
// The baked tiles (marks, button ring, edit chrome) are the Light captures. A dark control paints the same tiles with
// every pixel's colour mapped, so the anti-aliasing and bevel structure and the coverage (alpha) are those of the
// captures and only the colours change: a grey `l` goes through a monotone-in-sections curve of its family (a light face
// becomes the dark control face, the darkest border pixel becomes the dark stroke, the ink becomes light), and an accent
// blue (blue clearly above red) is read as the mix t = red / 255 of the light accent (red 0) and a base colour (white
// for a tick, the face for an underline) and painted as the same mix of the dark accent #4CC2FF and the dark `base`.
// Families: 0 check box and radio marks, 1 edit chrome, 2 button ring, 3 ink and dotted focus rectangle.
const DARK_ACCENT: u32 = 0x4CC2FFu32

// Linear interpolation of `l` through the points (xs[i], ys[i]), i < n, xs ascending.
fn curve(l: i32, xs: [12]i32, ys: [12]i32, n: usize) -> i32 {
    if l <= xs[0usize] { ret ys[0usize] }
    var i = 1usize
    while i < n {
        if l <= xs[i] {
            let x0 = xs[i - 1usize]
            let x1 = xs[i]
            let y0 = ys[i - 1usize]
            let y1 = ys[i]
            ret y0 + ((y1 - y0) * (l - x0) * 2 + (x1 - x0)) / ((x1 - x0) * 2)
        }
        i += 1usize
    }
    ret ys[n - 1usize]
}

fn dark_grey(l: i32, family: u32) -> i32 {
    if family == 0u32 {
        // marks: face #F3 -> #2B, the rest border #78 -> #9A, the pressed border #C8 -> #68, the bevel in between
        ret curve(l, [12]i32{ 0, 120, 160, 190, 200, 215, 226, 243, 255, 255, 255, 255 }, [12]i32{ 255, 154, 128, 110, 104, 74, 58, 43, 43, 43, 43, 43 }, 9usize)
    }
    if family == 1u32 {
        // edit chrome: face #FF -> #2B, the dialog's #F0 -> #20, the rim between, the foot line #AB -> #9A
        ret curve(l, [12]i32{ 0, 100, 171, 190, 215, 230, 237, 240, 250, 255, 255, 255 }, [12]i32{ 255, 200, 154, 120, 80, 58, 40, 32, 40, 43, 43, 43 }, 10usize)
    }
    if family == 2u32 {
        // button ring: the ring line #D0 -> #6B, the bottom shadow #BA -> #46, the disabled line #E9 -> #3A, face #FD -> #33
        ret curve(l, [12]i32{ 0, 140, 186, 208, 233, 249, 253, 255, 255, 255, 255, 255 }, [12]i32{ 255, 160, 70, 107, 58, 48, 51, 51, 51, 51, 51, 51 }, 8usize)
    }
    // ink: the dotted focus rectangle's #55 -> #BF, #AA -> #7F
    ret 255 - (l * 3) / 4
}

fn byte_of(v: i32) -> u32 {
    if v < 0 { ret 0u32 }
    if v > 255 { ret 255u32 }
    ret u32(v)
}

// `argb` (0xAARRGGBB, alpha kept) mapped to the dark palette. `base` is the 0xRRGGBB the
// accent mixes toward (see above).
fn dark_argb(argb: u32, family: u32, base: u32) -> u32 {
    let alpha = argb & 0xFF000000u32
    let r = i32((argb >> 16u32) & 255u32)
    let g = i32((argb >> 8u32) & 255u32)
    let b = i32(argb & 255u32)
    if b > r + 36 && b > g + 16 {
        var t = r
        if t > 255 { t = 255 }
        let ar = i32((DARK_ACCENT >> 16u32) & 255u32)
        let ag = i32((DARK_ACCENT >> 8u32) & 255u32)
        let ab = i32(DARK_ACCENT & 255u32)
        let br = i32((base >> 16u32) & 255u32)
        let bg = i32((base >> 8u32) & 255u32)
        let bb = i32(base & 255u32)
        let or = ar + ((br - ar) * t + 127) / 255
        let og = ag + ((bg - ag) * t + 127) / 255
        let ob = ab + ((bb - ab) * t + 127) / 255
        ret alpha | (byte_of(or) << 16u32) | (byte_of(og) << 8u32) | byte_of(ob)
    }
    let v = byte_of(dark_grey((r + g + b) / 3, family))
    ret alpha | (v << 16u32) | (v << 8u32) | v
}
