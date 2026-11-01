// Round 63, lane z: platform shapes for the range slider and the dial (Windows, Linux, Cupertino) and the menu surface of the speed dial.
// Derived from the public design rules (WinUI 3 Slider thumb, libadwaita 1.5 GtkScale, AppKit circular slider); nothing here is compared
// with a real screen. control.e calls this file, so it cannot import control: it takes tokens and plain values.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.math
use e.mem
use e.ui.layout as ui_layout
use e.ui.linuxsoft_lb as linuxsoft
use e.ui.style
use e.ui.widget

error TooLarge

fn no_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

fn clear() -> paint.Color {
    ret paint.rgba(0.0, 0.0, 0.0, 0.0)
}

fn fixed(width: f32, height: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    ret s
}

fn one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

// A circle as four cubic arcs: the Cupertino look turns a rounded rectangle's corners into continuous ones, which makes a round knob
// a squircle, so the knobs and their rings are traced here. `reversed` winds the other way (the hole of a ring).
fn circle_trace(builder: *geometry.PathBuilder, cx: f32, cy: f32, r: f32, reversed: bool) -> err {
    let k = 0.5522848 * r
    try geometry.move_to(builder, geometry.Point { x: cx + r, y: cy })
    if !reversed {
        try geometry.cubic_to(builder, geometry.Point { x: cx + r, y: cy + k }, geometry.Point { x: cx + k, y: cy + r }, geometry.Point { x: cx, y: cy + r })
        try geometry.cubic_to(builder, geometry.Point { x: cx - k, y: cy + r }, geometry.Point { x: cx - r, y: cy + k }, geometry.Point { x: cx - r, y: cy })
        try geometry.cubic_to(builder, geometry.Point { x: cx - r, y: cy - k }, geometry.Point { x: cx - k, y: cy - r }, geometry.Point { x: cx, y: cy - r })
        try geometry.cubic_to(builder, geometry.Point { x: cx + k, y: cy - r }, geometry.Point { x: cx + r, y: cy - k }, geometry.Point { x: cx + r, y: cy })
    } else {
        try geometry.cubic_to(builder, geometry.Point { x: cx + r, y: cy - k }, geometry.Point { x: cx + k, y: cy - r }, geometry.Point { x: cx, y: cy - r })
        try geometry.cubic_to(builder, geometry.Point { x: cx - k, y: cy - r }, geometry.Point { x: cx - r, y: cy - k }, geometry.Point { x: cx - r, y: cy })
        try geometry.cubic_to(builder, geometry.Point { x: cx - r, y: cy + k }, geometry.Point { x: cx - k, y: cy + r }, geometry.Point { x: cx, y: cy + r })
        try geometry.cubic_to(builder, geometry.Point { x: cx + k, y: cy + r }, geometry.Point { x: cx + r, y: cy + k }, geometry.Point { x: cx + r, y: cy })
    }
    ret geometry.close_path(builder)
}

fn disc(a: *mem.Arena, b: *scene.Builder, cx: f32, cy: f32, radius: f32, color: paint.Color) -> err {
    let (pb, pb_error) = geometry.path_builder(a, 16usize, 32usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    try circle_trace(&builder, cx, cy, radius, false)
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&builder), brush: paint.Brush { Solid: color } } })
}

// A ring of `width` inside the circle of radius `outer`.
fn ring(a: *mem.Arena, b: *scene.Builder, cx: f32, cy: f32, outer: f32, width: f32, color: paint.Color) -> err {
    let (pb, pb_error) = geometry.path_builder(a, 16usize, 32usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    try circle_trace(&builder, cx, cy, outer, false)
    try circle_trace(&builder, cx, cy, outer - width, true)
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&builder), brush: paint.Brush { Solid: color } } })
}

// A round Cupertino thumb: the soft shadow, a hairline, the face.
type Thumb = struct { arena: *mem.Arena, face: paint.Color, edge: paint.Color }

fn thumb_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let t = mem.cast[*Thumb](ctx)
    let r = area.width * 0.5
    let cx = area.x + r
    let cy = area.y + area.height * 0.5
    try linuxsoft.soft_disc(t.arena, b, geometry.Rect { x: cx - r, y: cy - r, width: r * 2.0, height: r * 2.0 }, r, 2.0, 0.22, 4.0)
    try disc(t.arena, b, cx, cy, r, t.edge)
    ret disc(t.arena, b, cx, cy, r - 0.5, t.face)
}

fn thumb_node(a: *mem.Arena, side: f32, face: paint.Color, edge: paint.Color) -> (widget.Node, err) {
    let (thumbs, thumbs_error) = mem.alloc[Thumb](a, 1usize)
    if thumbs_error != ok { ret (zero, TooLarge) }
    thumbs[0usize] = Thumb { arena: a, face: face, edge: edge }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&thumbs[0usize]), measure: no_measure, paint: thumb_paint, state: widget.bytes_of[Thumb](&thumbs[0usize]) } }, style: fixed(side, side), children: none }, ok)
}

fn bar(a: *mem.Arena, b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, color: paint.Color) -> err {
    if w <= 0.0 { ret ok }
    let (path, path_error) = widget.rounded_path(a, geometry.Rect { x: x, y: y, width: w, height: h }, radius)
    if path_error != ok { ret path_error }
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: color } } })
}

// ---- range slider: the Linux look (GtkScale with two knobs) -------------------------------------------------------------------
// The scale's 34 x 200 box: a 4 high trough 12 in from each end, the accent between the knobs, 20 px knobs (white; #d2d2d2 Dark until
// hovered) that travel from 10 to 190, each with the 1 px ring and the soft shadow; the keyboard ring (the accent at 50 %, 2 px) on the
// knob `hot` names. `hot` is 0 for none, 1 for the first knob and 2 for the second.
type RangeLook = struct { arena: *mem.Arena, lo: f32, hi: f32, dark: bool, hot: u8, ring: bool, enabled: bool, accent: paint.Color, focus: paint.Color }

fn linux_range_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let s = mem.cast[*RangeLook](ctx)
    let top = area.y + 15.0
    let left = area.x + 12.0
    let right = area.x + 188.0
    let cy = area.y + 17.0
    let x1 = area.x + 10.0 + s.lo * 180.0
    let x2 = area.x + 10.0 + s.hi * 180.0
    var ink = paint.rgba(0.0, 0.0, 0.0, 0.116)
    if s.hot != 0u8 { ink = paint.rgba(0.0, 0.0, 0.0, 0.156) }
    if s.dark {
        ink = paint.rgba(1.0, 1.0, 1.0, 0.15)
        if s.hot != 0u8 { ink = paint.rgba(1.0, 1.0, 1.0, 0.2) }
    }
    try bar(s.arena, b, left, top, right - left, 4.0, 2.0, ink)
    try bar(s.arena, b, x1, top, x2 - x1, 4.0, 0.0, s.accent)
    var k = 1u8
    while k <= 2u8 {
        var cx = x1
        if k == 2u8 { cx = x2 }
        let hot = s.hot == k
        var knob = style.hex_raw(0xFFFFFFu32)
        if s.dark && !hot { knob = style.hex_raw(0xD2D2D2u32) }
        try ring(s.arena, b, cx, cy, 11.0, 1.0, paint.rgba(0.0, 0.0, 0.0, 0.1))
        if s.enabled { try linuxsoft.soft_disc(s.arena, b, geometry.Rect { x: cx - 10.0, y: cy - 10.0, width: 20.0, height: 20.0 }, 10.0, 2.0, 0.2, 3.0) }
        try disc(s.arena, b, cx, cy, 10.0, knob)
        if s.ring && hot { try ring(s.arena, b, cx, cy, 12.0, 2.0, paint.rgba(s.focus.red, s.focus.green, s.focus.blue, 0.5)) }
        k += 1u8
    }
    ret ok
}

// The two-knob scale over the runtime's own slider (`hidden`, transparent, 200 wide), which takes the pointer and keys.
fn linux_range(a: *mem.Arena, tokens: *const style.ThemeTokens, lo: f32, hi: f32, hot: u8, ring_on: bool, enabled: bool, hidden: widget.Node) -> (widget.Node, err) {
    let (looks, looks_error) = mem.alloc[RangeLook](a, 1usize)
    if looks_error != ok { ret (zero, TooLarge) }
    looks[0usize] = RangeLook { arena: a, lo: lo, hi: hi, dark: tokens.palette == .Dark, hot: hot, ring: ring_on && enabled, enabled: enabled, accent: style.hex_raw(0x3584E4u32), focus: style.color(tokens, .Focus) }
    var none: []const widget.Node = zero
    var seen = fixed(200.0, 34.0)
    if !enabled { seen.opacity = 0.5 }
    let drawn = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&looks[0usize]), measure: no_measure, paint: linux_range_paint, state: widget.bytes_of[RangeLook](&looks[0usize]) } }, style: seen, children: none }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = drawn
    layers[1usize] = hidden
    ret (widget.stack(0u64, fixed(200.0, 34.0), layers[0usize..2usize]), ok)
}

// ---- range slider: the Cupertino look (UISlider with two thumbs) -------------------------------------------------------------
// The iOS slider's metrics: a 4 px track of the fill colour (#787880 at 16 %, 32 % Dark) from 14 to 198, the accent between the thumbs, and
// two 28 px white thumbs with a hairline and the level 1 shade, the thumb centre 14 in from the end at 0.
fn cup_range(a: *mem.Arena, tokens: *const style.ThemeTokens, lo: f32, hi: f32, enabled: bool, hidden: widget.Node) -> (widget.Node, err) {
    var rest = style.hexa(0x787880u32, 0.16)
    if tokens.palette == .Dark { rest = style.hexa(0x787880u32, 0.32) }
    let accent = style.color(tokens, .Primary)
    var track = fixed(184.0, 4.0)
    track.radius = 2.0
    track.background = paint.Brush { Solid: rest }
    var lit = fixed((hi - lo) * 184.0, 4.0)
    lit.radius = 2.0
    lit.background = paint.Brush { Solid: accent }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 5usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = widget.positioned(0u64, 14.0, 12.0, style.defaults(), one(a, widget.box(0u64, track, zero)))
    layers[1usize] = widget.positioned(0u64, 14.0 + lo * 184.0, 12.0, style.defaults(), one(a, widget.box(0u64, lit, zero)))
    var k = 0usize
    while k < 2usize {
        let (grip, grip_error) = thumb_node(a, 28.0, style.hex(0xFFFFFFu32), paint.rgba(0.0, 0.0, 0.0, 0.06))
        if grip_error != ok { ret (zero, grip_error) }
        var share = lo
        if k == 1usize { share = hi }
        layers[2usize + k] = widget.positioned(0u64, share * 184.0, 0.0, style.defaults(), one(a, grip))
        k += 1usize
    }
    layers[4usize] = widget.positioned(0u64, 6.0, 0.0, style.defaults(), one(a, hidden))
    var frame = fixed(212.0, 28.0)
    if !enabled { frame.opacity = 0.4 }
    ret (widget.stack(0u64, frame, layers[0usize..5usize]), ok)
}

// ---- dial ---------------------------------------------------------------------------------------------------------------------
// kind 1: WinUI 3 (a 4 px track in ControlStrongFill, the accent arc, the Slider thumb: a 20 px disc with a 12 px accent dot, 14 hovered,
// 10 pressed); 2: libadwaita (a 4 px trough arc, the accent arc, the GtkScale knob with its ring and soft shadow); 3: AppKit circular
// slider (tick marks round a white knob with a dot at the value).
type DialLook = struct { arena: *mem.Arena, kind: u8, share: f32, dark: bool, hot: bool, pressed: bool, ring: bool, accent: paint.Color, focus: paint.Color, ink: paint.Color }

// An open arc as chords, from `start` (radians clockwise from the top) through `sweep`.
fn sweep_path(a: *mem.Arena, cx: f32, cy: f32, radius: f32, start: f32, sweep: f32) -> (geometry.Path, err) {
    var steps = usize(sweep / 0.19634955) + 2usize
    if steps > 40usize { steps = 40usize }
    let (pb, pb_error) = geometry.path_builder(a, steps + 2usize, steps + 2usize)
    if pb_error != ok { ret (zero, TooLarge) }
    var builder = pb
    if geometry.move_to(&builder, geometry.Point { x: cx + math.sin[f32](start) * radius, y: cy - math.cos[f32](start) * radius }) != ok { ret (zero, TooLarge) }
    var i = 1usize
    while i <= steps {
        let angle = start + sweep * f32(i) / f32(steps)
        if geometry.line_to(&builder, geometry.Point { x: cx + math.sin[f32](angle) * radius, y: cy - math.cos[f32](angle) * radius }) != ok { ret (zero, TooLarge) }
        i += 1usize
    }
    ret (geometry.finish(&builder), ok)
}

fn arc(a: *mem.Arena, b: *scene.Builder, cx: f32, cy: f32, radius: f32, sweep: f32, width: f32, color: paint.Color) -> err {
    if sweep < 0.001 { ret ok }
    let (path, path_error) = sweep_path(a, cx, cy, radius, 0.0 - 2.3561945, sweep)
    if path_error != ok { ret path_error }
    let stroke = paint.Stroke { width: width, cap: .Round, join: .Round, miter_limit: 4.0 }
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: path, brush: paint.Brush { Solid: color }, stroke: stroke } })
}

fn tick(a: *mem.Arena, b: *scene.Builder, cx: f32, cy: f32, from: f32, to: f32, angle: f32, width: f32, color: paint.Color) -> err {
    let (pb, pb_error) = geometry.path_builder(a, 2usize, 2usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    let s = math.sin[f32](angle)
    let c = math.cos[f32](angle)
    if geometry.move_to(&builder, geometry.Point { x: cx + s * from, y: cy - c * from }) != ok { ret TooLarge }
    if geometry.line_to(&builder, geometry.Point { x: cx + s * to, y: cy - c * to }) != ok { ret TooLarge }
    let stroke = paint.Stroke { width: width, cap: .Round, join: .Round, miter_limit: 4.0 }
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: geometry.finish(&builder), brush: paint.Brush { Solid: color }, stroke: stroke } })
}

fn dial_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let d = mem.cast[*DialLook](ctx)
    let cx = area.x + area.width * 0.5
    let cy = area.y + area.height * 0.5
    var face = area.width
    if area.height < face { face = area.height }
    let sweep = d.share * 4.712389
    let end = 0.0 - 2.3561945 + sweep
    if d.kind == 3u8 {
        // AppKit: eleven ticks over the three quarter turn, the knob 30 % of the face in radius, its dot at 70 % of that.
        let knob = face * 0.3
        var tick_ink = paint.rgba(0.0, 0.0, 0.0, 0.3)
        var face_ink = style.hex_raw(0xFFFFFFu32)
        var edge = paint.rgba(0.0, 0.0, 0.0, 0.14)
        if d.dark {
            tick_ink = paint.rgba(1.0, 1.0, 1.0, 0.3)
            face_ink = style.hex_raw(0x636366u32)
            edge = paint.rgba(0.0, 0.0, 0.0, 0.4)
        }
        var i = 0usize
        while i < 11usize {
            let angle = 0.0 - 2.3561945 + 4.712389 * f32(i) / 10.0
            try tick(d.arena, b, cx, cy, knob + face * 0.07, knob + face * 0.13, angle, 1.5, tick_ink)
            i += 1usize
        }
        try linuxsoft.soft_disc(d.arena, b, geometry.Rect { x: cx - knob, y: cy - knob, width: knob * 2.0, height: knob * 2.0 }, knob, 1.5, 0.2, 3.0)
        try disc(d.arena, b, cx, cy, knob, edge)
        try disc(d.arena, b, cx, cy, knob - 0.5, face_ink)
        if d.pressed { try disc(d.arena, b, cx, cy, knob - 0.5, paint.rgba(0.0, 0.0, 0.0, 0.06)) }
        var dot = d.ink
        if d.dark { dot = style.hex_raw(0xEBEBF5u32) }
        try disc(d.arena, b, cx + math.sin[f32](end) * knob * 0.68, cy - math.cos[f32](end) * knob * 0.68, face * 0.03 + 1.0, paint.rgba(dot.red, dot.green, dot.blue, 0.8))
        ret ok
    }
    let radius = face * 0.4
    var width: f32 = 4.0
    var thumb: f32 = 10.0
    if face < 100.0 {
        width = 3.0
        thumb = 8.0
    }
    let hx = cx + math.sin[f32](end) * radius
    let hy = cy - math.cos[f32](end) * radius
    if d.kind == 1u8 {
        var track = paint.rgba(0.0, 0.0, 0.0, 0.447)
        var rim = paint.rgba(0.0, 0.0, 0.0, 0.058)
        var plate = style.hex_raw(0xFFFFFFu32)
        if d.dark {
            track = paint.rgba(1.0, 1.0, 1.0, 0.545)
            rim = paint.rgba(0.0, 0.0, 0.0, 0.2)
            plate = style.hex_raw(0x454545u32)
        }
        try arc(d.arena, b, cx, cy, radius, 4.712389, width, track)
        try arc(d.arena, b, cx, cy, radius, sweep, width, d.accent)
        try disc(d.arena, b, hx, hy, thumb + 1.0, rim)
        try disc(d.arena, b, hx, hy, thumb, plate)
        var dot = thumb * 0.6
        if d.hot && !d.pressed { dot = thumb * 0.7 }
        if d.pressed { dot = thumb * 0.5 }
        try disc(d.arena, b, hx, hy, dot, d.accent)
        if d.ring {
            var focus = paint.rgba(0.0, 0.0, 0.0, 0.9)
            if d.dark { focus = paint.rgba(1.0, 1.0, 1.0, 0.9) }
            try ring(d.arena, b, hx, hy, thumb + 4.0, 2.0, focus)
        }
        ret ok
    }
    var ink = paint.rgba(0.0, 0.0, 0.0, 0.116)
    if d.hot { ink = paint.rgba(0.0, 0.0, 0.0, 0.156) }
    if d.dark {
        ink = paint.rgba(1.0, 1.0, 1.0, 0.15)
        if d.hot { ink = paint.rgba(1.0, 1.0, 1.0, 0.2) }
    }
    try arc(d.arena, b, cx, cy, radius, 4.712389, width, ink)
    try arc(d.arena, b, cx, cy, radius, sweep, width, d.accent)
    var knob = style.hex_raw(0xFFFFFFu32)
    if d.dark && !d.hot { knob = style.hex_raw(0xD2D2D2u32) }
    try ring(d.arena, b, hx, hy, thumb + 1.0, 1.0, paint.rgba(0.0, 0.0, 0.0, 0.1))
    try linuxsoft.soft_disc(d.arena, b, geometry.Rect { x: hx - thumb, y: hy - thumb, width: thumb * 2.0, height: thumb * 2.0 }, thumb, 2.0, 0.2, 3.0)
    try disc(d.arena, b, hx, hy, thumb, knob)
    if d.ring { try ring(d.arena, b, hx, hy, thumb + 2.0, 2.0, paint.rgba(d.focus.red, d.focus.green, d.focus.blue, 0.5)) }
    ret ok
}

// The dial's face for `kind` (1 Windows, 2 Linux, 3 Cupertino), `size` square.
fn dial_face(a: *mem.Arena, tokens: *const style.ThemeTokens, kind: u8, share: f32, size: f32, hot: bool, pressed: bool, ring_on: bool) -> (widget.Node, err) {
    let (looks, looks_error) = mem.alloc[DialLook](a, 1usize)
    if looks_error != ok { ret (zero, TooLarge) }
    var accent = style.color(tokens, .Primary)
    if kind == 2u8 { accent = style.hex_raw(0x3584E4u32) }
    looks[0usize] = DialLook { arena: a, kind: kind, share: share, dark: tokens.palette == .Dark, hot: hot, pressed: pressed, ring: ring_on, accent: accent, focus: style.color(tokens, .Focus), ink: style.color(tokens, .Text) }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&looks[0usize]), measure: no_measure, paint: dial_paint, state: widget.bytes_of[DialLook](&looks[0usize]) } }, style: fixed(size, size), children: none }, ok)
}

// ---- speed dial menu surface ------------------------------------------------------------------------------------------------------
// The panel the speed dial's actions sit on: a WinUI 3 MenuFlyout (#FCFCFC, #2C2C2C Dark, a 1 px stroke, 8 px corners, 4 px of padding),
// a libadwaita popover menu (the popover colour, 12 px corners, 6 px of padding) or an iOS context menu (14 px corners, rows 44 high with
// hairlines between).
fn menu_panel(tokens: *const style.ThemeTokens) -> style.Style {
    var s = style.defaults()
    let dark = tokens.palette == .Dark
    var inset: f32 = 0.0
    if tokens.profile == .Windows {
        var face = style.hex_raw(0xFCFCFCu32)
        var edge = paint.rgba(0.0, 0.0, 0.0, 0.06)
        if dark {
            face = style.hex_raw(0x2C2C2Cu32)
            edge = paint.rgba(0.0, 0.0, 0.0, 0.45)
        }
        s.background = paint.Brush { Solid: face }
        s.border = style.Border { width: 1.0, color: edge }
        s.radius = 8.0
        s.shade = 3u8
        s.min_width = style.Length { Px: 168.0 }
        inset = 4.0
    }
    if tokens.profile == .Linux {
        var edge = paint.rgba(0.0, 0.0, 0.0, 0.05)
        if dark { edge = paint.rgba(0.0, 0.0, 0.0, 0.4) }
        s.background = paint.Brush { Solid: style.color(tokens, .SurfaceBright) }
        s.border = style.Border { width: 1.0, color: edge }
        s.radius = 12.0
        s.shade = 3u8
        s.min_width = style.Length { Px: 180.0 }
        inset = 6.0
    }
    if tokens.profile == .CupertinoLike {
        var face = style.hex_raw(0xF6F6F6u32)
        if dark { face = style.hex_raw(0x2C2C2Eu32) }
        s.background = paint.Brush { Solid: face }
        s.radius = 14.0
        s.shade = 3u8
        s.min_width = style.Length { Px: 220.0 }
    }
    let pad = style.Length { Px: inset }
    s.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    s.overflow = .Clip
    ret s
}

// The hairline between two iOS menu rows.
fn menu_rule(tokens: *const style.ThemeTokens) -> widget.Node {
    var s = style.defaults()
    s.height = style.Length { Px: 0.5 }
    var ink = paint.rgba(0.0, 0.0, 0.0, 0.12)
    if tokens.palette == .Dark { ink = paint.rgba(1.0, 1.0, 1.0, 0.16) }
    s.background = paint.Brush { Solid: ink }
    ret widget.box(0u64, s, zero)
}

// ---- popover ----------------------------------------------------------------------------------------------------------------------
// The popover's surface per look (overlay.popover_state calls this; Neper keeps the v2 card, `styled` false): a WinUI 3 Flyout (#FCFCFC,
// #2C2C2C Dark, a 1 px stroke, 8 px corners, 16 px of padding, 8 off the anchor, no arrow), a libadwaita GtkPopover (the popover colour,
// 12 px corners, an arrow), an iOS popover (white, #2C2C2E Dark, 13 px corners, a 22 x 11 arrow) and an M3 menu surface (surface-container,
// 4 px corners, level 2, no arrow). `plate` is the v2 card's style; the width stays its own.
type PopoverFace = struct { styled: bool, plate: style.Style, beak: bool, beak_w: f32, beak_h: f32, gap: f32, fill: paint.Color }

fn popover_face(tokens: *const style.ThemeTokens, plate: style.Style) -> PopoverFace {
    var out = PopoverFace { styled: false, plate: plate, beak: true, beak_w: 12.0, beak_h: 6.0, gap: 4.0, fill: style.color(tokens, .SurfaceContainerHigh) }
    let dark = tokens.palette == .Dark
    var inset: f32 = 16.0
    if tokens.profile == .Windows {
        var face = style.hex_raw(0xFCFCFCu32)
        var edge = paint.rgba(0.0, 0.0, 0.0, 0.06)
        if dark {
            face = style.hex_raw(0x2C2C2Cu32)
            edge = paint.rgba(0.0, 0.0, 0.0, 0.45)
        }
        out.styled = true
        out.beak = false
        out.gap = 8.0
        out.fill = face
        out.plate.background = paint.Brush { Solid: face }
        out.plate.border = style.Border { width: 1.0, color: edge }
        out.plate.radius = 8.0
        out.plate.shade = 3u8
    }
    if tokens.profile == .Linux {
        var edge = paint.rgba(0.0, 0.0, 0.0, 0.05)
        if dark { edge = paint.rgba(0.0, 0.0, 0.0, 0.4) }
        out.styled = true
        out.beak_w = 14.0
        out.beak_h = 7.0
        out.fill = style.color(tokens, .SurfaceBright)
        out.plate.background = paint.Brush { Solid: out.fill }
        out.plate.border = style.Border { width: 1.0, color: edge }
        out.plate.radius = 12.0
        out.plate.shade = 3u8
        inset = 12.0
    }
    if tokens.profile == .CupertinoLike {
        var face = style.hex_raw(0xFFFFFFu32)
        if dark { face = style.hex_raw(0x2C2C2Eu32) }
        out.styled = true
        out.beak_w = 22.0
        out.beak_h = 11.0
        out.gap = 2.0
        out.fill = face
        out.plate.background = paint.Brush { Solid: face }
        out.plate.radius = 13.0
        out.plate.shade = 3u8
    }
    if tokens.profile == .MaterialLike {
        out.styled = true
        out.beak = false
        out.fill = style.color(tokens, .SurfaceContainer)
        out.plate.background = paint.Brush { Solid: out.fill }
        out.plate.radius = tokens.radii.xs
        out.plate.shade = 2u8
    }
    if out.styled {
        let pad = style.Length { Px: inset }
        out.plate.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
        out.plate.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: 0.0 }, color: paint.rgba(0.0, 0.0, 0.0, 0.0) }
    }
    ret out
}
