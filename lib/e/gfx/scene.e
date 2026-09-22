// `e.gfx.scene` (D796): a display list, compiled into a renderer's scene and drawn
// into a presentation target. This is the CPU reference renderer the UI proposal
// names first: every command rasterises through one signed-area accumulation
// rasteriser -- fills, strokes as outlines, glyphs as outlines from the font's
// `glyf`, clips as coverage masks -- into a premultiplied RGBA canvas the frame's
// image receives as packed pixels. A driver backend draws the same list with the
// same arithmetic in kernels, which is what the proposal's per-pixel tolerance is
// measured between; here the tile loop is host code.
//
// Bounds: a scene holds up to `SCENE_BYTES` of copied commands, paths, stops and
// glyph runs; a command flattens into at most `MAX_EDGES` edges; clip masks nest
// eight deep and opacity layers four. Past any of them the answer is `TooLarge`,
// and the last presented frame stands. Fonts are registered by the caller: a
// `DrawText` names a font by its shaper id, and the renderer holds the bytes it was
// handed for that id (`register_font`).
//
// ponytail: no glyph cache -- every glyph is flattened at every render; a texture's
// storage is not reclaimed on release until the renderer closes; a scene's arena
// is one fixed block per slot. Each is the upgrade the proposal's frame-time
// numbers will name.

use e.gpu
use e.math
use e.mem
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.text.layout
use e.text.shape

type TextureId = struct { slot: u32, generation: u32 }
type SceneId = struct { slot: u32, generation: u32 }
type Clip = union enum u8 { Rect: geometry.Rect, Rounded: geometry.RRect, Path: geometry.Path }
type Command = union enum u8 { Save, Restore, Transform: geometry.Transform, Clip: Clip, FillRect: FillRect, FillPath: FillPath, StrokePath: StrokePath, Image: DrawImage, Text: DrawText, OpacityLayer: OpacityLayer }
type FillRect = struct { rect: geometry.Rect, brush: paint.Brush }
type FillPath = struct { path: geometry.Path, brush: paint.Brush }
type StrokePath = struct { path: geometry.Path, brush: paint.Brush, stroke: paint.Stroke }
type DrawImage = struct { texture: TextureId, source: geometry.Rect, destination: geometry.Rect, opacity: f32 }
type DrawText = struct { layout: *const layout.Layout, origin: geometry.Point, brush: paint.Brush }
type OpacityLayer = struct { bounds: geometry.Rect, opacity: f32 }
type DisplayList = struct { commands: []const Command }
type Builder = struct { state: *void }
type Renderer = struct { state: *void }
type Target = struct { state: *void }
error Invalid
error TooLarge
error OutOfMemory
error Lost

const SCENE_BYTES: usize = 262144usize
const MAX_EDGES: usize = 65536usize
const MAX_MASKS: usize = 8usize
const MAX_LAYERS: usize = 4usize
const MAX_FONTS: usize = 16usize
const MAX_STATES: usize = 32usize

type BuilderState = struct { commands: []Command, count: usize, finished: bool }

// A texture is premultiplied RGBA, four floats per pixel.
type Texture = struct { live: bool, generation: u32, width: u32, height: u32, pixels: []f32 }
type Scene = struct { live: bool, released: bool, generation: u32, storage: []u8, has_storage: bool, arena: mem.Arena, commands: []Command, count: usize }
type FontEntry = struct { id: shape.FontId, data: []const u8, upem: f32, loca: usize, glyf: usize, glyf_len: usize, long_loca: bool, glyph_count: usize }
type Edge = struct { x0: f32, y0: f32, x1: f32, y1: f32 }
type Floats = struct { data: []f32, len: usize }
// The state a Save pushes: the transform, the scissor, the mask in use and whether
// this entry opened an opacity layer.
type DrawState = struct { transform: geometry.Transform, scissor: geometry.Rect, mask: usize, has_mask: bool, layer: usize, opens_layer: bool, opacity: f32, layer_x0: usize, layer_y0: usize, layer_x1: usize, layer_y1: usize }
type RendererState = struct { arena: *mem.Arena, device: *gpu.Device, queue: *gpu.Queue, scenes: []Scene, textures: []Texture, fonts: [16]FontEntry, font_count: usize, edges: []Edge, edge_count: usize, canvases: [4]Floats, masks: [8]Floats, acc: []f32, coverage: []f32, pixels: []u32, width: usize, height: usize, scale: f32, box_x0: usize, box_y0: usize, box_x1: usize, box_y1: usize, last_scene: usize, has_last: bool, retiring: bool, last_width: usize, last_height: usize, last_scale: f32, dx0: usize, dy0: usize, dx1: usize, dy1: usize, wrote_y0: usize, wrote_y1: usize, skip: []bool, closed: bool }
type TargetState = struct { target: *gpu.Target }

// ------------------------------------------------------------------ the builder

fn builder(a: *mem.Arena, max_commands: usize) -> (Builder, err) {
    if max_commands == 0usize { ret (zero, Invalid) }
    let (states, states_error) = mem.alloc[BuilderState](a, 1usize)
    if states_error != ok { ret (zero, OutOfMemory) }
    let (commands, commands_error) = mem.alloc[Command](a, max_commands)
    if commands_error != ok { ret (zero, OutOfMemory) }
    states[0usize] = BuilderState { commands: commands, count: 0usize, finished: false }
    ret (Builder { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn push(b: *Builder, command: Command) -> err {
    let s = mem.cast[*BuilderState](b.state)
    if mem.address_of(s) == 0usize || s.finished { ret Invalid }
    if s.count >= s.commands.len { ret TooLarge }
    var accepted = true
    switch command {
    case .Save:
        accepted = true
    case .Restore:
        accepted = true
    case .Transform as t:
        if !finite(t.m00) || !finite(t.m01) || !finite(t.m02) || !finite(t.m10) || !finite(t.m11) || !finite(t.m12) { ret Invalid }
    case .Clip as clip:
        switch clip {
        case .Rect as r:
            if !rect_ok(r) { ret Invalid }
        case .Rounded as rr:
            if !rect_ok(rr.rect) { ret Invalid }
        case .Path as p:
            if !path_ok(p) { ret Invalid }
        }
    case .FillRect as fill:
        if !rect_ok(fill.rect) || paint.validate(&fill.brush) != ok { ret Invalid }
    case .FillPath as fill:
        if !path_ok(fill.path) || paint.validate(&fill.brush) != ok { ret Invalid }
    case .StrokePath as stroke:
        if !path_ok(stroke.path) || paint.validate(&stroke.brush) != ok || !(stroke.stroke.width > 0.0) || !finite(stroke.stroke.width) { ret Invalid }
    case .Image as draw:
        if !rect_ok(draw.source) || !rect_ok(draw.destination) || !unit(draw.opacity) { ret Invalid }
    case .Text as text:
        if mem.address_of(text.layout) == 0usize || paint.validate(&text.brush) != ok { ret Invalid }
    case .OpacityLayer as layer:
        if !rect_ok(layer.bounds) || !unit(layer.opacity) { ret Invalid }
    }
    if !accepted { ret Invalid }
    s.commands[s.count] = command
    s.count += 1usize
    ret ok
}

fn finish(b: *Builder) -> DisplayList {
    let s = mem.cast[*BuilderState](b.state)
    var nothing: []const Command = zero
    if mem.address_of(s) == 0usize { ret DisplayList { commands: nothing } }
    s.finished = true
    ret DisplayList { commands: s.commands[0usize..s.count] }
}

fn finite(v: f32) -> bool {
    ret v == v && v < 3.4e38 && v > -3.4e38
}

fn unit(v: f32) -> bool {
    ret v >= 0.0 && v <= 1.0
}

fn rect_ok(r: geometry.Rect) -> bool {
    ret finite(r.x) && finite(r.y) && finite(r.width) && finite(r.height) && r.width >= 0.0 && r.height >= 0.0
}

// Every verb's points are there and finite; a path is a sequence of contours.
fn path_ok(p: geometry.Path) -> bool {
    var needed = 0usize
    var i = 0usize
    while i < p.verbs.len {
        let verb = p.verbs[i]
        if verb == .Move || verb == .Line { needed += 1usize }
        if verb == .Quad { needed += 2usize }
        if verb == .Cubic { needed += 3usize }
        i += 1usize
    }
    if needed != p.points.len { ret false }
    i = 0usize
    while i < p.points.len {
        if !finite(p.points[i].x) || !finite(p.points[i].y) { ret false }
        i += 1usize
    }
    ret true
}

// ----------------------------------------------------------------- the renderer

fn renderer(a: *mem.Arena, device: *gpu.Device, queue: *gpu.Queue, max_scenes: u32, max_textures: u32) -> (Renderer, err) {
    if max_scenes == 0u32 || max_textures == 0u32 || max_scenes > 4096u32 || max_textures > 4096u32 { ret (zero, Invalid) }
    let (states, states_error) = mem.alloc[RendererState](a, 1usize)
    if states_error != ok { ret (zero, OutOfMemory) }
    let (scenes, scenes_error) = mem.alloc[Scene](a, usize(max_scenes))
    if scenes_error != ok { ret (zero, OutOfMemory) }
    let (textures, textures_error) = mem.alloc[Texture](a, usize(max_textures))
    if textures_error != ok { ret (zero, OutOfMemory) }
    let (edges, edges_error) = mem.alloc[Edge](a, MAX_EDGES)
    if edges_error != ok { ret (zero, OutOfMemory) }
    var empty_scene: Scene = zero
    var empty_texture: Texture = zero
    var i = 0usize
    while i < scenes.len {
        scenes[i] = empty_scene
        i += 1usize
    }
    i = 0usize
    while i < textures.len {
        textures[i] = empty_texture
        i += 1usize
    }
    var state: RendererState = zero
    state.arena = a
    state.device = device
    state.queue = queue
    state.scenes = scenes
    state.textures = textures
    state.edges = edges
    states[0usize] = state
    ret (Renderer { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn renderer_state(r: *Renderer) -> (*RendererState, err) {
    let s = mem.cast[*RendererState](r.state)
    if mem.address_of(s) == 0usize || s.closed { ret (s, Invalid) }
    ret (s, ok)
}

// A `DrawText` names its font by the shaper's id; the bytes behind it are given
// here once, and `head`'s unitsPerEm, `loca` and `glyf` are found at that time.
fn register_font(r: *Renderer, font: shape.Font) -> err {
    let (s, state_error) = renderer_state(r)
    if state_error != ok { ret state_error }
    if shape.validate_font(font) != ok { ret Invalid }
    var entry: FontEntry = zero
    entry.id = font.id
    entry.data = font.data
    let (head_at, head_len, has_head) = font_table(font.data, font.face_index, 1751474532u32)
    let (loca_at, loca_len, has_loca) = font_table(font.data, font.face_index, 1819239265u32)
    let (glyf_at, glyf_len, has_glyf) = font_table(font.data, font.face_index, 1735162214u32)
    let (maxp_at, maxp_len, has_maxp) = font_table(font.data, font.face_index, 1835104368u32)
    if !has_head || !has_loca || !has_glyf || !has_maxp || head_len < 54usize || maxp_len < 6usize { ret Invalid }
    entry.upem = f32(be16(font.data, head_at + 18usize))
    if !(entry.upem > 0.0) { ret Invalid }
    entry.long_loca = be16(font.data, head_at + 50usize) == 1u32
    entry.loca = loca_at
    entry.glyf = glyf_at
    entry.glyf_len = glyf_len
    entry.glyph_count = usize(be16(font.data, maxp_at + 4usize))
    var unit_size = 2usize
    if entry.long_loca { unit_size = 4usize }
    if (entry.glyph_count + 1usize) * unit_size > loca_len { ret Invalid }
    // A registered id is replaced, not doubled.
    var i = 0usize
    while i < s.font_count {
        if s.fonts[i].id == font.id {
            s.fonts[i] = entry
            ret ok
        }
        i += 1usize
    }
    if s.font_count >= MAX_FONTS { ret TooLarge }
    s.fonts[s.font_count] = entry
    s.font_count += 1usize
    ret ok
}

fn be16(d: []const u8, at: usize) -> u32 {
    if at + 2usize > d.len { ret 0u32 }
    ret (u32(d[at]) << 8u32) | u32(d[at + 1usize])
}

fn be32(d: []const u8, at: usize) -> u32 {
    if at + 4usize > d.len { ret 0u32 }
    ret (u32(d[at]) << 24u32) | (u32(d[at + 1usize]) << 16u32) | (u32(d[at + 2usize]) << 8u32) | u32(d[at + 3usize])
}

fn font_table(d: []const u8, face: u32, tag: u32) -> (usize, usize, bool) {
    var base = 0usize
    if be32(d, 0usize) == 1953784678u32 {
        if face >= be32(d, 8usize) { ret (0usize, 0usize, false) }
        base = usize(be32(d, 12usize + 4usize * usize(face)))
    }
    let count = usize(be16(d, base + 4usize))
    var i = 0usize
    while i < count {
        let record = base + 12usize + 16usize * i
        if be32(d, record) == tag {
            let at = usize(be32(d, record + 8usize))
            let len = usize(be32(d, record + 12usize))
            if at + len > d.len { ret (0usize, 0usize, false) }
            ret (at, len, true)
        }
        i += 1usize
    }
    ret (0usize, 0usize, false)
}

// ------------------------------------------------------------------- textures

fn texture_slot(s: *RendererState, id: TextureId) -> (usize, err) {
    if usize(id.slot) >= s.textures.len { ret (0usize, Invalid) }
    let t = &s.textures[usize(id.slot)]
    if !t.live || t.generation != id.generation { ret (0usize, Invalid) }
    ret (usize(id.slot), ok)
}

// One pixel of a host image as straight RGBA in 0..1.
fn read_pixel(view: image.ConstImage, x: usize, y: usize) -> (f32, f32, f32, f32) {
    let bytes = image.bytes_per_pixel(view.format)
    let at = y * view.stride + x * bytes
    if view.format == .R8 {
        let v = f32(view.pixels[at]) / 255.0
        ret (v, v, v, 1.0)
    }
    if view.format == .Rgba8 {
        ret (f32(view.pixels[at]) / 255.0, f32(view.pixels[at + 1usize]) / 255.0, f32(view.pixels[at + 2usize]) / 255.0, f32(view.pixels[at + 3usize]) / 255.0)
    }
    if view.format == .Bgra8 {
        ret (f32(view.pixels[at + 2usize]) / 255.0, f32(view.pixels[at + 1usize]) / 255.0, f32(view.pixels[at]) / 255.0, f32(view.pixels[at + 3usize]) / 255.0)
    }
    ret (half_of(view.pixels, at), half_of(view.pixels, at + 2usize), half_of(view.pixels, at + 4usize), half_of(view.pixels, at + 6usize))
}

// A little-endian half float as an f32, normals and subnormals; NaN and infinity
// become 0, which a colour has no use for.
fn half_of(d: []const u8, at: usize) -> f32 {
    let bits = u32(d[at]) | (u32(d[at + 1usize]) << 8u32)
    let sign = (bits >> 15u32) & 1u32
    let exponent = (bits >> 10u32) & 31u32
    let mantissa = bits & 1023u32
    var value: f32 = 0.0
    if exponent == 31u32 { ret 0.0 }
    if exponent == 0u32 {
        value = f32(mantissa) / 1024.0 * math.exp2[f32](-14.0)
    } else {
        value = (1.0 + f32(mantissa) / 1024.0) * math.exp2[f32](f32(exponent) - 15.0)
    }
    if sign != 0u32 { value = 0.0 - value }
    ret value
}

fn fill_texture(t: *Texture, view: image.ConstImage) {
    var y = 0usize
    while y < usize(view.height) {
        var x = 0usize
        while x < usize(view.width) {
            let (red, green, blue, alpha) = read_pixel(view, x, y)
            let at = (y * usize(view.width) + x) * 4usize
            var a = alpha
            if view.alpha == .Opaque { a = 1.0 }
            var r = red
            var g = green
            var b = blue
            if view.alpha != .Premultiplied {
                r = red * a
                g = green * a
                b = blue * a
            }
            t.pixels[at] = r
            t.pixels[at + 1usize] = g
            t.pixels[at + 2usize] = b
            t.pixels[at + 3usize] = a
            x += 1usize
        }
        y += 1usize
    }
}

fn upload_image(r: *Renderer, image_view: image.ConstImage) -> (TextureId, err) {
    let (s, state_error) = renderer_state(r)
    if state_error != ok { ret (zero, state_error) }
    if image_view.width == 0u32 || image_view.height == 0u32 || image_view.width > 16384u32 || image_view.height > 16384u32 { ret (zero, Invalid) }
    let (needed, needed_error) = image.required_bytes(image_view.width, image_view.height, image_view.format, image_view.stride)
    if needed_error != ok || image_view.pixels.len < needed { ret (zero, Invalid) }
    var slot = 0usize
    while slot < s.textures.len && s.textures[slot].live { slot += 1usize }
    if slot >= s.textures.len { ret (zero, TooLarge) }
    let count = usize(image_view.width) * usize(image_view.height) * 4usize
    let t = &s.textures[slot]
    if t.pixels.len < count {
        let (pixels, pixels_error) = mem.alloc[f32](s.arena, count)
        if pixels_error != ok { ret (zero, OutOfMemory) }
        t.pixels = pixels
    }
    t.live = true
    t.generation += 1u32
    t.width = image_view.width
    t.height = image_view.height
    fill_texture(t, image_view)
    ret (TextureId { slot: u32(slot), generation: t.generation }, ok)
}

fn update_image(r: *Renderer, texture: TextureId, image_view: image.ConstImage) -> err {
    let (s, state_error) = renderer_state(r)
    if state_error != ok { ret state_error }
    let (slot, slot_error) = texture_slot(s, texture)
    if slot_error != ok { ret slot_error }
    let t = &s.textures[slot]
    if image_view.width != t.width || image_view.height != t.height { ret Invalid }
    let (needed, needed_error) = image.required_bytes(image_view.width, image_view.height, image_view.format, image_view.stride)
    if needed_error != ok || image_view.pixels.len < needed { ret Invalid }
    fill_texture(t, image_view)
    ret ok
}

fn release_image(r: *Renderer, texture: TextureId) -> err {
    let (s, state_error) = renderer_state(r)
    if state_error != ok { ret state_error }
    let (slot, slot_error) = texture_slot(s, texture)
    if slot_error != ok { ret slot_error }
    s.textures[slot].live = false
    ret ok
}

// --------------------------------------------------------------------- scenes

fn scene_slot(s: *RendererState, id: SceneId) -> (usize, err) {
    if usize(id.slot) >= s.scenes.len { ret (0usize, Invalid) }
    let scene = &s.scenes[usize(id.slot)]
    if !scene.live || scene.released || scene.generation != id.generation { ret (0usize, Invalid) }
    ret (usize(id.slot), ok)
}

fn copy_points(a: *mem.Arena, points: []const geometry.Point) -> ([]const geometry.Point, err) {
    var nothing: []const geometry.Point = zero
    if points.len == 0usize { ret (nothing, ok) }
    let (copied, copy_error) = mem.alloc[geometry.Point](a, points.len)
    if copy_error != ok { ret (nothing, TooLarge) }
    mem.copy[geometry.Point](copied, points)
    ret (copied, ok)
}

fn copy_path(a: *mem.Arena, path: geometry.Path) -> (geometry.Path, err) {
    var copied: geometry.Path = zero
    if path.verbs.len != 0usize {
        let (verbs, verbs_error) = mem.alloc[geometry.PathVerb](a, path.verbs.len)
        if verbs_error != ok { ret (copied, TooLarge) }
        mem.copy[geometry.PathVerb](verbs, path.verbs)
        copied.verbs = verbs
    }
    let (points, points_error) = copy_points(a, path.points)
    if points_error != ok { ret (copied, points_error) }
    copied.points = points
    ret (copied, ok)
}

fn copy_brush(a: *mem.Arena, brush: paint.Brush) -> (paint.Brush, err) {
    switch brush {
    case .Solid as color:
        ret (brush, ok)
    case .Linear as linear:
        let (stops, stops_error) = mem.alloc[paint.Stop](a, linear.stops.len)
        if stops_error != ok { ret (brush, TooLarge) }
        mem.copy[paint.Stop](stops, linear.stops)
        ret (paint.Brush { Linear: paint.LinearGradient { start: linear.start, end: linear.end, stops: stops } }, ok)
    case .Radial as radial:
        let (stops, stops_error) = mem.alloc[paint.Stop](a, radial.stops.len)
        if stops_error != ok { ret (brush, TooLarge) }
        mem.copy[paint.Stop](stops, radial.stops)
        ret (paint.Brush { Radial: paint.RadialGradient { center: radial.center, radius: radial.radius, stops: stops } }, ok)
    }
    ret (brush, ok)
}

// A layout is copied down to its glyphs; the source text is not needed to draw it.
fn copy_layout(a: *mem.Arena, source: *const layout.Layout) -> (*const layout.Layout, err) {
    var none: *const layout.Layout = zero
    let (lines, lines_error) = mem.alloc[layout.Line](a, source.lines.len)
    if lines_error != ok { ret (none, TooLarge) }
    var l = 0usize
    while l < source.lines.len {
        let line = &source.lines[l]
        let (runs, runs_error) = mem.alloc[layout.GlyphRun](a, line.runs.len)
        if runs_error != ok { ret (none, TooLarge) }
        var ri = 0usize
        while ri < line.runs.len {
            let run = &line.runs[ri]
            let (glyphs, glyphs_error) = mem.alloc[shape.Glyph](a, run.run.glyphs.len)
            if glyphs_error != ok { ret (none, TooLarge) }
            mem.copy[shape.Glyph](glyphs, run.run.glyphs)
            runs[ri] = layout.GlyphRun { run: shape.Run { font: run.run.font, direction: run.run.direction, script: run.run.script, language: "", glyphs: glyphs }, origin: run.origin, size: run.size }
            ri += 1usize
        }
        lines[l] = layout.Line { runs: runs, bounds: line.bounds, baseline: line.baseline, start: line.start, end: line.end }
        l += 1usize
    }
    let (copies, copies_error) = mem.alloc[layout.Layout](a, 1usize)
    if copies_error != ok { ret (none, TooLarge) }
    copies[0usize] = layout.Layout { source: "", lines: lines, bounds: source.bounds }
    ret (&copies[0usize], ok)
}

fn copy_command(a: *mem.Arena, command: Command) -> (Command, err) {
    switch command {
    case .Save:
        ret (command, ok)
    case .Restore:
        ret (command, ok)
    case .Transform as t:
        ret (command, ok)
    case .Clip as clip:
        switch clip {
        case .Rect as rect:
            ret (command, ok)
        case .Rounded as rr:
            ret (command, ok)
        case .Path as p:
            let (path, path_error) = copy_path(a, p)
            if path_error != ok { ret (command, path_error) }
            ret (Command { Clip: Clip { Path: path } }, ok)
        }
    case .FillRect as fill:
        let (brush, brush_error) = copy_brush(a, fill.brush)
        if brush_error != ok { ret (command, brush_error) }
        ret (Command { FillRect: FillRect { rect: fill.rect, brush: brush } }, ok)
    case .FillPath as fill:
        let (path, path_error) = copy_path(a, fill.path)
        if path_error != ok { ret (command, path_error) }
        let (brush, brush_error) = copy_brush(a, fill.brush)
        if brush_error != ok { ret (command, brush_error) }
        ret (Command { FillPath: FillPath { path: path, brush: brush } }, ok)
    case .StrokePath as stroke:
        let (path, path_error) = copy_path(a, stroke.path)
        if path_error != ok { ret (command, path_error) }
        let (brush, brush_error) = copy_brush(a, stroke.brush)
        if brush_error != ok { ret (command, brush_error) }
        ret (Command { StrokePath: StrokePath { path: path, brush: brush, stroke: stroke.stroke } }, ok)
    case .Image as draw:
        ret (command, ok)
    case .Text as text:
        let (copied, layout_error) = copy_layout(a, text.layout)
        if layout_error != ok { ret (command, layout_error) }
        let (brush, brush_error) = copy_brush(a, text.brush)
        if brush_error != ok { ret (command, brush_error) }
        ret (Command { Text: DrawText { layout: copied, origin: text.origin, brush: brush } }, ok)
    case .OpacityLayer as layer:
        ret (command, ok)
    }
    ret (command, ok)
}

fn compile(r: *Renderer, list: DisplayList) -> (SceneId, err) {
    let (s, state_error) = renderer_state(r)
    if state_error != ok { ret (zero, state_error) }
    var slot = 0usize
    while slot < s.scenes.len && s.scenes[slot].live { slot += 1usize }
    if slot >= s.scenes.len { ret (zero, TooLarge) }
    let scene = &s.scenes[slot]
    if !scene.has_storage {
        let (storage, storage_error) = mem.alloc[u8](s.arena, SCENE_BYTES)
        if storage_error != ok { ret (zero, OutOfMemory) }
        scene.storage = storage
        scene.has_storage = true
    }
    scene.arena = mem.arena_from(scene.storage)
    let (commands, commands_error) = mem.alloc[Command](&scene.arena, list.commands.len)
    if commands_error != ok { ret (zero, TooLarge) }
    // Every Save has its Restore and no Restore is unmatched; a layer is a Save.
    var depth = 0usize
    var i = 0usize
    while i < list.commands.len {
        let command = list.commands[i]
        if command.tag == .Save || command.tag == .OpacityLayer { depth += 1usize }
        if command.tag == .Restore {
            if depth == 0usize { ret (zero, Invalid) }
            depth = depth - 1usize
        }
        if depth > MAX_STATES { ret (zero, TooLarge) }
        let (copied, copy_error) = copy_command(&scene.arena, command)
        if copy_error != ok { ret (zero, copy_error) }
        commands[i] = copied
        i += 1usize
    }
    if depth != 0usize { ret (zero, Invalid) }
    scene.live = true
    scene.released = false
    scene.generation += 1u32
    scene.commands = commands
    scene.count = list.commands.len
    ret (SceneId { slot: u32(slot), generation: scene.generation }, ok)
}

fn release_scene(r: *Renderer, scene: SceneId) -> err {
    let (s, state_error) = renderer_state(r)
    if state_error != ok { ret state_error }
    let (slot, slot_error) = scene_slot(s, scene)
    if slot_error != ok { ret slot_error }
    // The last rendered scene's storage stays until the next render has compared
    // against it (D914); to its caller it is released, and its slot is freed then.
    if s.has_last && slot == s.last_scene {
        s.retiring = true
        s.scenes[slot].released = true
        ret ok
    }
    s.scenes[slot].live = false
    ret ok
}

fn close(r: *Renderer) -> err {
    let (s, state_error) = renderer_state(r)
    if state_error != ok { ret state_error }
    s.closed = true
    ret ok
}

// The queue a renderer draws on, for a target made beside it.
fn queue_of(r: *Renderer) -> *gpu.Queue {
    let s = mem.cast[*RendererState](r.state)
    ret s.queue
}

// A presentation target over `e.gpu`'s: a window's, or an offscreen one for a test.
fn target_of(a: *mem.Arena, t: *gpu.Target) -> (Target, err) {
    let (states, states_error) = mem.alloc[TargetState](a, 1usize)
    if states_error != ok { ret (zero, OutOfMemory) }
    states[0usize] = TargetState { target: t }
    ret (Target { state: mem.cast[*void](&states[0usize]) }, ok)
}

// ------------------------------------------------------------------ rendering

fn transform_compose(outer: geometry.Transform, inner: geometry.Transform) -> geometry.Transform {
    ret geometry.Transform {
        m00: outer.m00 * inner.m00 + outer.m01 * inner.m10,
        m01: outer.m00 * inner.m01 + outer.m01 * inner.m11,
        m02: outer.m00 * inner.m02 + outer.m01 * inner.m12 + outer.m02,
        m10: outer.m10 * inner.m00 + outer.m11 * inner.m10,
        m11: outer.m10 * inner.m01 + outer.m11 * inner.m11,
        m12: outer.m10 * inner.m02 + outer.m11 * inner.m12 + outer.m12,
    }
}

fn transform_invert(t: geometry.Transform) -> (geometry.Transform, bool) {
    let det = t.m00 * t.m11 - t.m01 * t.m10
    if det == 0.0 || !finite(det) { ret (t, false) }
    let inv_det = 1.0 / det
    let m00 = t.m11 * inv_det
    let m01 = 0.0 - t.m01 * inv_det
    let m10 = 0.0 - t.m10 * inv_det
    let m11 = t.m00 * inv_det
    ret (geometry.Transform { m00: m00, m01: m01, m02: 0.0 - (m00 * t.m02 + m01 * t.m12), m10: m10, m11: m11, m12: 0.0 - (m10 * t.m02 + m11 * t.m12) }, true)
}

fn ensure_canvas(s: *RendererState, index: usize) -> err {
    let count = s.width * s.height * 4usize
    if s.canvases[index].len < count {
        let (data, data_error) = mem.alloc[f32](s.arena, count)
        if data_error != ok { ret OutOfMemory }
        s.canvases[index] = Floats { data: data, len: count }
    }
    ret ok
}

fn ensure_mask(s: *RendererState, index: usize) -> err {
    let count = s.width * s.height
    if s.masks[index].len < count {
        let (data, data_error) = mem.alloc[f32](s.arena, count)
        if data_error != ok { ret OutOfMemory }
        s.masks[index] = Floats { data: data, len: count }
    }
    ret ok
}

fn clear_floats(data: []f32, count: usize) {
    var i = 0usize
    while i + 2usize <= count {
        let pair = mem.cast[*u64](&data[i])
        *pair = 0u64
        i += 2usize
    }
    while i < count {
        data[i] = 0.0
        i += 1usize
    }
}

// Edges: the flattened outline of whatever is being drawn, in pixel space.
fn add_edge(s: *RendererState, x0: f32, y0: f32, x1: f32, y1: f32) -> err {
    if y0 == y1 { ret ok }
    if s.edge_count >= s.edges.len { ret TooLarge }
    s.edges[s.edge_count] = Edge { x0: x0, y0: y0, x1: x1, y1: y1 }
    s.edge_count += 1usize
    ret ok
}

fn segments_for(length: f32) -> usize {
    var n = math.ceil[f32](math.sqrt[f32](length * 2.0))
    if !(n >= 1.0) { n = 1.0 }
    if n > 48.0 { n = 48.0 }
    ret usize(n)
}

fn distance(a: geometry.Point, b: geometry.Point) -> f32 {
    let dx = b.x - a.x
    let dy = b.y - a.y
    ret math.sqrt[f32](dx * dx + dy * dy)
}

// A path flattened under `t` into a polyline per contour, handed to `emit` as edges:
// `stroke` false closes every contour, as a fill does.
type Flattener = struct { s: *RendererState, t: geometry.Transform, current: geometry.Point, start: geometry.Point, open: bool, stroke: bool, hw: f32, cap: paint.StrokeCap, join: paint.StrokeJoin, miter_limit: f32, previous: geometry.Point, has_previous: bool, first_dir: geometry.Point, has_first: bool, last_dir: geometry.Point, segment_count: usize }

fn flat_point(f: *Flattener, p: geometry.Point) -> geometry.Point {
    ret geometry.transform_point(f.t, p)
}

fn flat_line(f: *Flattener, to: geometry.Point) -> err {
    if !f.stroke {
        try add_edge(f.s, f.current.x, f.current.y, to.x, to.y)
        f.current = to
        ret ok
    }
    try stroke_segment(f, f.current, to)
    f.current = to
    ret ok
}

fn flat_quad(f: *Flattener, control: geometry.Point, end: geometry.Point) -> err {
    let n = segments_for(distance(f.current, control) + distance(control, end))
    let p0 = f.current
    var i = 1usize
    while i <= n {
        let u = f32(i) / f32(n)
        let v = 1.0 - u
        let x = v * v * p0.x + 2.0 * v * u * control.x + u * u * end.x
        let y = v * v * p0.y + 2.0 * v * u * control.y + u * u * end.y
        try flat_line(f, geometry.Point { x: x, y: y })
        i += 1usize
    }
    ret ok
}

fn flat_cubic(f: *Flattener, c1: geometry.Point, c2: geometry.Point, end: geometry.Point) -> err {
    let n = segments_for(distance(f.current, c1) + distance(c1, c2) + distance(c2, end))
    let p0 = f.current
    var i = 1usize
    while i <= n {
        let u = f32(i) / f32(n)
        let v = 1.0 - u
        let x = v * v * v * p0.x + 3.0 * v * v * u * c1.x + 3.0 * v * u * u * c2.x + u * u * u * end.x
        let y = v * v * v * p0.y + 3.0 * v * v * u * c1.y + 3.0 * v * u * u * c2.y + u * u * u * end.y
        try flat_line(f, geometry.Point { x: x, y: y })
        i += 1usize
    }
    ret ok
}

fn flat_close(f: *Flattener) -> err {
    if !f.open { ret ok }
    if f.stroke {
        if f.current.x != f.start.x || f.current.y != f.start.y { try stroke_segment(f, f.current, f.start) }
        // The closing join, between the last segment and the first.
        if f.has_previous && f.has_first { try stroke_join(f, f.start, f.last_dir, f.first_dir) }
    } else {
        try add_edge(f.s, f.current.x, f.current.y, f.start.x, f.start.y)
    }
    f.current = f.start
    f.open = false
    f.has_previous = false
    f.has_first = false
    ret ok
}

// An open stroked contour ends with its caps.
fn flat_end(f: *Flattener) -> err {
    if !f.open { ret ok }
    if f.stroke {
        if f.has_first {
            try stroke_cap(f, f.start, geometry.Point { x: 0.0 - f.first_dir.x, y: 0.0 - f.first_dir.y })
            try stroke_cap(f, f.current, f.last_dir)
        }
    } else {
        try add_edge(f.s, f.current.x, f.current.y, f.start.x, f.start.y)
    }
    f.open = false
    f.has_previous = false
    f.has_first = false
    ret ok
}

fn flatten(f: *Flattener, path: geometry.Path) -> err {
    var at = 0usize
    var i = 0usize
    while i < path.verbs.len {
        let verb = path.verbs[i]
        if verb == .Move {
            try flat_end(f)
            f.current = flat_point(f, path.points[at])
            f.start = f.current
            f.open = true
            at += 1usize
        }
        if verb == .Line {
            try flat_line(f, flat_point(f, path.points[at]))
            at += 1usize
        }
        if verb == .Quad {
            try flat_quad(f, flat_point(f, path.points[at]), flat_point(f, path.points[at + 1usize]))
            at += 2usize
        }
        if verb == .Cubic {
            try flat_cubic(f, flat_point(f, path.points[at]), flat_point(f, path.points[at + 1usize]), flat_point(f, path.points[at + 2usize]))
            at += 3usize
        }
        if verb == .Close { try flat_close(f) }
        i += 1usize
    }
    ret flat_end(f)
}

// A polygon, given as its corners in order, as edges oriented counter-clockwise
// whatever the order given: a stroke is the union of its pieces, and a consistent
// orientation is what makes the accumulated winding a union.
fn add_polygon(s: *RendererState, corners: []const geometry.Point) -> err {
    var area: f32 = 0.0
    var i = 0usize
    while i < corners.len {
        let a = corners[i]
        let b = corners[(i + 1usize) % corners.len]
        area = area + a.x * b.y - b.x * a.y
        i += 1usize
    }
    i = 0usize
    while i < corners.len {
        let a = corners[i]
        let b = corners[(i + 1usize) % corners.len]
        if area >= 0.0 {
            try add_edge(s, a.x, a.y, b.x, b.y)
        } else {
            try add_edge(s, b.x, b.y, a.x, a.y)
        }
        i += 1usize
    }
    ret ok
}

fn stroke_segment(f: *Flattener, a: geometry.Point, b: geometry.Point) -> err {
    let len = distance(a, b)
    if len == 0.0 { ret ok }
    let dir = geometry.Point { x: (b.x - a.x) / len, y: (b.y - a.y) / len }
    let nx = 0.0 - dir.y * f.hw
    let ny = dir.x * f.hw
    var corners: [4]geometry.Point = zero
    corners[0] = geometry.Point { x: a.x + nx, y: a.y + ny }
    corners[1] = geometry.Point { x: b.x + nx, y: b.y + ny }
    corners[2] = geometry.Point { x: b.x - nx, y: b.y - ny }
    corners[3] = geometry.Point { x: a.x - nx, y: a.y - ny }
    try add_polygon(f.s, corners[0..])
    if f.has_previous { try stroke_join(f, a, f.last_dir, dir) }
    if !f.has_first {
        f.first_dir = dir
        f.has_first = true
    }
    f.last_dir = dir
    f.has_previous = true
    ret ok
}

fn add_disc(s: *RendererState, center: geometry.Point, radius: f32) -> err {
    var corners: [16]geometry.Point = zero
    var i = 0usize
    while i < 16usize {
        let angle = f32(i) * 0.39269908
        corners[i] = geometry.Point { x: center.x + radius * math.cos[f32](angle), y: center.y + radius * math.sin[f32](angle) }
        i += 1usize
    }
    ret add_polygon(s, corners[0..])
}

// The join at `p` between a segment arriving along `d0` and one leaving along `d1`.
fn stroke_join(f: *Flattener, p: geometry.Point, d0: geometry.Point, d1: geometry.Point) -> err {
    if f.join == .Round { ret add_disc(f.s, p, f.hw) }
    let cross = d0.x * d1.y - d0.y * d1.x
    if cross == 0.0 { ret ok }
    // The outer side is the one the turn leaves behind.
    var side: f32 = 1.0
    if cross > 0.0 { side = -1.0 }
    let o0 = geometry.Point { x: p.x - d0.y * f.hw * side, y: p.y + d0.x * f.hw * side }
    let o1 = geometry.Point { x: p.x - d1.y * f.hw * side, y: p.y + d1.x * f.hw * side }
    var corners: [4]geometry.Point = zero
    corners[0] = p
    corners[1] = o0
    corners[2] = o1
    if f.join == .Miter {
        let dot = d0.x * d1.x + d0.y * d1.y
        let cos_half = math.sqrt[f32]((1.0 + dot) * 0.5)
        if cos_half > 0.0 && 1.0 / cos_half <= f.miter_limit {
            let mx = (o0.x + o1.x) * 0.5 - p.x
            let my = (o0.y + o1.y) * 0.5 - p.y
            let mlen = math.sqrt[f32](mx * mx + my * my)
            if mlen > 0.0 {
                let reach = f.hw / cos_half
                corners[1] = o0
                corners[2] = geometry.Point { x: p.x + mx / mlen * reach, y: p.y + my / mlen * reach }
                corners[3] = o1
                ret add_polygon(f.s, corners[0..])
            }
        }
    }
    ret add_polygon(f.s, corners[0usize..3usize])
}

fn stroke_cap(f: *Flattener, p: geometry.Point, dir: geometry.Point) -> err {
    if f.cap == .Butt { ret ok }
    if f.cap == .Round { ret add_disc(f.s, p, f.hw) }
    let nx = 0.0 - dir.y * f.hw
    let ny = dir.x * f.hw
    let ex = dir.x * f.hw
    let ey = dir.y * f.hw
    var corners: [4]geometry.Point = zero
    corners[0] = geometry.Point { x: p.x + nx, y: p.y + ny }
    corners[1] = geometry.Point { x: p.x + nx + ex, y: p.y + ny + ey }
    corners[2] = geometry.Point { x: p.x - nx + ex, y: p.y - ny + ey }
    corners[3] = geometry.Point { x: p.x - nx, y: p.y - ny }
    ret add_polygon(f.s, corners[0..])
}

// The signed-area accumulation of one edge into `acc`, `width + 2` cells per row:
// each cell takes the area the edge sweeps in it and the cover it carries to the
// cells on its right, so a prefix sum along the row is the winding coverage.
fn accumulate_edge(acc: []f32, width: usize, height: usize, e: Edge) {
    var dir: f32 = 1.0
    var x0 = e.x0
    var y0 = e.y0
    var x1 = e.x1
    var y1 = e.y1
    if y0 > y1 {
        dir = -1.0
        x0 = e.x1
        y0 = e.y1
        x1 = e.x0
        y1 = e.y0
    }
    let limit = f32(width)
    if x0 < 0.0 { x0 = 0.0 }
    if x1 < 0.0 { x1 = 0.0 }
    if x0 > limit { x0 = limit }
    if x1 > limit { x1 = limit }
    let dxdy = (x1 - x0) / (y1 - y0)
    var x = x0
    var row_start = 0usize
    if y0 > 0.0 { row_start = usize(math.floor[f32](y0)) }
    var row_end = height
    if y1 < f32(height) {
        let ceiling = math.ceil[f32](y1)
        if ceiling > 0.0 { row_end = usize(ceiling) } else { row_end = 0usize }
    }
    if y0 < 0.0 { x = x0 + dxdy * (0.0 - y0) }
    let stride = width + 2usize
    var y = row_start
    while y < row_end {
        let line = y * stride
        let fy = f32(y)
        var dy = fy + 1.0
        if y1 < dy { dy = y1 }
        var top = fy
        if y0 > top { top = y0 }
        dy = dy - top
        let xnext = x + dxdy * dy
        let d = dy * dir
        var xa = x
        var xb = xnext
        if xa > xb {
            xa = xnext
            xb = x
        }
        // A row's span is kept inside the surface: an edge clipped in y, or one a
        // rounding away from the left edge, would otherwise reach a column before 0.
        if xa < 0.0 { xa = 0.0 }
        if xb < 0.0 { xb = 0.0 }
        if xa > limit { xa = limit }
        if xb > limit { xb = limit }
        let xa_floor = math.floor[f32](xa)
        let xa_i = usize(xa_floor)
        var xb_ceil = math.ceil[f32](xb)
        let xb_i = usize(xb_ceil)
        if xb_i <= xa_i + 1usize {
            let xmf = 0.5 * (x + xnext) - xa_floor
            acc[line + xa_i] = acc[line + xa_i] + d - d * xmf
            acc[line + xa_i + 1usize] = acc[line + xa_i + 1usize] + d * xmf
        } else {
            let s = 1.0 / (xb - xa)
            let xa_f = xa - xa_floor
            let a0 = 0.5 * s * (1.0 - xa_f) * (1.0 - xa_f)
            let xb_f = xb - xb_ceil + 1.0
            let am = 0.5 * s * xb_f * xb_f
            acc[line + xa_i] = acc[line + xa_i] + d * a0
            if xb_i == xa_i + 2usize {
                acc[line + xa_i + 1usize] = acc[line + xa_i + 1usize] + d * (1.0 - a0 - am)
            } else {
                let a1 = s * (1.5 - xa_f)
                acc[line + xa_i + 1usize] = acc[line + xa_i + 1usize] + d * (a1 - a0)
                var xi = xa_i + 2usize
                while xi < xb_i - 1usize {
                    acc[line + xi] = acc[line + xi] + d * s
                    xi += 1usize
                }
                let a2 = a1 + f32(xb_i - xa_i - 3usize) * s
                acc[line + xb_i - 1usize] = acc[line + xb_i - 1usize] + d * (1.0 - a2 - am)
            }
            acc[line + xb_i] = acc[line + xb_i] + d * am
        }
        x = xnext
        y += 1usize
    }
}

// The coverage of the accumulated edges, row by row, into `out` (`width * height`),
// within the edges' box alone: outside it `out` is stale and never read (D913).
fn resolve_coverage(s: *RendererState, out: []f32) {
    let stride = s.width + 2usize
    var y = s.box_y0
    while y < s.box_y1 {
        var sum: f32 = 0.0
        var x = s.box_x0
        while x < s.box_x1 {
            sum = sum + s.acc[y * stride + x]
            var c = sum
            if c < 0.0 { c = 0.0 - c }
            if c > 1.0 { c = 1.0 }
            out[y * s.width + x] = c
            x += 1usize
        }
        y += 1usize
    }
}

// The pixel box the edges reach, clamped to the frame; a command clears, resolves
// and paints that box and not the frame (D913: a frame of a few hundred commands
// was three whole-frame passes each).
fn edge_box(s: *RendererState) {
    var x0: f32 = f32(s.width)
    var y0: f32 = f32(s.height)
    var x1: f32 = 0.0
    var y1: f32 = 0.0
    var i = 0usize
    while i < s.edge_count {
        let e = s.edges[i]
        if e.x0 < x0 { x0 = e.x0 }
        if e.x1 < x0 { x0 = e.x1 }
        if e.x0 > x1 { x1 = e.x0 }
        if e.x1 > x1 { x1 = e.x1 }
        if e.y0 < y0 { y0 = e.y0 }
        if e.y1 < y0 { y0 = e.y1 }
        if e.y0 > y1 { y1 = e.y0 }
        if e.y1 > y1 { y1 = e.y1 }
        i += 1usize
    }
    if s.edge_count == 0usize || !(x1 > x0) || !(y1 > y0) {
        s.box_x0 = 0usize
        s.box_y0 = 0usize
        s.box_x1 = 0usize
        s.box_y1 = 0usize
        ret
    }
    s.box_x0 = 0usize
    s.box_y0 = 0usize
    if x0 > 0.0 { s.box_x0 = usize(math.floor[f32](x0)) }
    if y0 > 0.0 { s.box_y0 = usize(math.floor[f32](y0)) }
    // The row's running sum ends one pixel past the last edge.
    s.box_x1 = s.width
    s.box_y1 = s.height
    if x1 + 2.0 < f32(s.width) { s.box_x1 = usize(math.ceil[f32](x1)) + 1usize }
    if y1 < f32(s.height) { s.box_y1 = usize(math.ceil[f32](y1)) }
    if s.box_x0 > s.width { s.box_x0 = s.width }
    if s.box_y0 > s.height { s.box_y0 = s.height }
    // Nothing outside the frame's damage is painted, so nothing there is resolved.
    if s.box_x0 < s.dx0 { s.box_x0 = s.dx0 }
    if s.box_y0 < s.dy0 { s.box_y0 = s.dy0 }
    if s.box_x1 > s.dx1 { s.box_x1 = s.dx1 }
    if s.box_y1 > s.dy1 { s.box_y1 = s.dy1 }
    if s.box_x1 < s.box_x0 { s.box_x1 = s.box_x0 }
    if s.box_y1 < s.box_y0 { s.box_y1 = s.box_y0 }
}

fn rasterize_edges(s: *RendererState, coverage: []f32) {
    edge_box(s)
    let stride = s.width + 2usize
    clear_floats(s.acc[s.box_y0 * stride..s.box_y1 * stride], (s.box_y1 - s.box_y0) * stride)
    var i = 0usize
    while i < s.edge_count {
        accumulate_edge(s.acc, s.width, s.height, s.edges[i])
        i += 1usize
    }
    resolve_coverage(s, coverage)
    s.edge_count = 0usize
}

// The brush's colour at a pixel centre, premultiplied; gradients are in the
// command's user space, reached through the inverse transform.
fn brush_at(brush: *const paint.Brush, inverse: geometry.Transform, px: f32, py: f32) -> paint.Color {
    switch *brush {
    case .Solid as color:
        ret paint.premultiply(color)
    case .Linear as linear:
        let p = geometry.transform_point(inverse, geometry.Point { x: px, y: py })
        let dx = linear.end.x - linear.start.x
        let dy = linear.end.y - linear.start.y
        let len2 = dx * dx + dy * dy
        var t: f32 = 0.0
        if len2 > 0.0 { t = ((p.x - linear.start.x) * dx + (p.y - linear.start.y) * dy) / len2 }
        ret paint.premultiply(stops_at(linear.stops, t))
    case .Radial as radial:
        let p = geometry.transform_point(inverse, geometry.Point { x: px, y: py })
        var t: f32 = 1.0
        if radial.radius > 0.0 { t = distance(p, radial.center) / radial.radius }
        ret paint.premultiply(stops_at(radial.stops, t))
    }
    ret paint.rgba(0.0, 0.0, 0.0, 0.0)
}

fn stops_at(stops: []const paint.Stop, t: f32) -> paint.Color {
    if t <= stops[0usize].offset { ret stops[0usize].color }
    var i = 1usize
    while i < stops.len {
        if t <= stops[i].offset {
            let a = stops[i - 1usize]
            let b = stops[i]
            var u: f32 = 1.0
            if b.offset > a.offset { u = (t - a.offset) / (b.offset - a.offset) }
            ret paint.Color { red: a.color.red + (b.color.red - a.color.red) * u, green: a.color.green + (b.color.green - a.color.green) * u, blue: a.color.blue + (b.color.blue - a.color.blue) * u, alpha: a.color.alpha + (b.color.alpha - a.color.alpha) * u }
        }
        i += 1usize
    }
    ret stops[stops.len - 1usize].color
}

// Source-over of a premultiplied colour scaled by `weight` into a canvas pixel.
fn blend_pixel(canvas: []f32, at: usize, color: paint.Color, weight: f32) {
    if weight <= 0.0 { ret }
    let a = color.alpha * weight
    let keep = 1.0 - a
    canvas[at] = color.red * weight + canvas[at] * keep
    canvas[at + 1usize] = color.green * weight + canvas[at + 1usize] * keep
    canvas[at + 2usize] = color.blue * weight + canvas[at + 2usize] * keep
    canvas[at + 3usize] = a + canvas[at + 3usize] * keep
}

// The coverage buffer painted with a brush through the state's scissor and mask.
fn paint_coverage(s: *RendererState, state: DrawState, coverage: []f32, brush: *const paint.Brush) {
    let (inverse, invertible) = transform_invert(state.transform)
    if !invertible { ret }
    let canvas = s.canvases[state.layer].data
    let (sx0, sy0, sx1, sy1) = scissor_bounds(s, state.scissor)
    var x0 = sx0
    var y0 = sy0
    var x1 = sx1
    var y1 = sy1
    if s.box_x0 > x0 { x0 = s.box_x0 }
    if s.box_y0 > y0 { y0 = s.box_y0 }
    if s.box_x1 < x1 { x1 = s.box_x1 }
    if s.box_y1 < y1 { y1 = s.box_y1 }
    // A solid brush is one colour: premultiplied once, stored where it covers a
    // pixel whole and opaque, blended elsewhere (D914).
    var solid: paint.Color = zero
    var is_solid = false
    switch *brush {
    case .Solid as color:
        solid = paint.premultiply(color)
        is_solid = true
    default:
        is_solid = false
    }
    let opaque = is_solid && solid.alpha >= 1.0
    var y = y0
    while y < y1 {
        var x = x0
        var index = y * s.width + x0
        while x < x1 {
            var c = coverage[index]
            if state.has_mask { c = c * s.masks[state.mask].data[index] }
            if c > 0.0 {
                if opaque && c >= 1.0 {
                    let at = index * 4usize
                    canvas[at] = solid.red
                    canvas[at + 1usize] = solid.green
                    canvas[at + 2usize] = solid.blue
                    canvas[at + 3usize] = 1.0
                } else if is_solid {
                    blend_pixel(canvas, index * 4usize, solid, c)
                } else {
                    let color = brush_at(brush, inverse, f32(x) + 0.5, f32(y) + 0.5)
                    blend_pixel(canvas, index * 4usize, color, c)
                }
            }
            x += 1usize
            index += 1usize
        }
        y += 1usize
    }
}

fn scissor_bounds(s: *RendererState, r: geometry.Rect) -> (usize, usize, usize, usize) {
    var x0: f32 = math.floor[f32](r.x)
    var y0: f32 = math.floor[f32](r.y)
    var x1: f32 = math.ceil[f32](r.x + r.width)
    var y1: f32 = math.ceil[f32](r.y + r.height)
    if x0 < 0.0 { x0 = 0.0 }
    if y0 < 0.0 { y0 = 0.0 }
    if x1 > f32(s.width) { x1 = f32(s.width) }
    if y1 > f32(s.height) { y1 = f32(s.height) }
    if x1 <= x0 || y1 <= y0 { ret (0usize, 0usize, 0usize, 0usize) }
    ret (usize(x0), usize(y0), usize(x1), usize(y1))
}

fn rect_path(r: geometry.Rect) -> ([5]geometry.PathVerb, [4]geometry.Point) {
    var verbs: [5]geometry.PathVerb = zero
    verbs[0] = .Move
    verbs[1] = .Line
    verbs[2] = .Line
    verbs[3] = .Line
    verbs[4] = .Close
    var points: [4]geometry.Point = zero
    points[0] = geometry.Point { x: r.x, y: r.y }
    points[1] = geometry.Point { x: r.x + r.width, y: r.y }
    points[2] = geometry.Point { x: r.x + r.width, y: r.y + r.height }
    points[3] = geometry.Point { x: r.x, y: r.y + r.height }
    ret (verbs, points)
}

// A rounded rectangle as four lines and four quarter-ellipse cubics.
fn rrect_edges(f: *Flattener, rr: geometry.RRect) -> err {
    let r = rr.rect
    let k: f32 = 0.5522848
    let x0 = r.x
    let y0 = r.y
    let x1 = r.x + r.width
    let y1 = r.y + r.height
    let tl = clamp_radius(rr.top_left, r)
    let tr = clamp_radius(rr.top_right, r)
    let br = clamp_radius(rr.bottom_right, r)
    let bl = clamp_radius(rr.bottom_left, r)
    f.current = flat_point(f, geometry.Point { x: x0 + tl.x, y: y0 })
    f.start = f.current
    f.open = true
    try flat_line(f, flat_point(f, geometry.Point { x: x1 - tr.x, y: y0 }))
    try flat_cubic(f, flat_point(f, geometry.Point { x: x1 - tr.x + tr.x * k, y: y0 }), flat_point(f, geometry.Point { x: x1, y: y0 + tr.y - tr.y * k }), flat_point(f, geometry.Point { x: x1, y: y0 + tr.y }))
    try flat_line(f, flat_point(f, geometry.Point { x: x1, y: y1 - br.y }))
    try flat_cubic(f, flat_point(f, geometry.Point { x: x1, y: y1 - br.y + br.y * k }), flat_point(f, geometry.Point { x: x1 - br.x + br.x * k, y: y1 }), flat_point(f, geometry.Point { x: x1 - br.x, y: y1 }))
    try flat_line(f, flat_point(f, geometry.Point { x: x0 + bl.x, y: y1 }))
    try flat_cubic(f, flat_point(f, geometry.Point { x: x0 + bl.x - bl.x * k, y: y1 }), flat_point(f, geometry.Point { x: x0, y: y1 - bl.y + bl.y * k }), flat_point(f, geometry.Point { x: x0, y: y1 - bl.y }))
    try flat_line(f, flat_point(f, geometry.Point { x: x0, y: y0 + tl.y }))
    try flat_cubic(f, flat_point(f, geometry.Point { x: x0, y: y0 + tl.y - tl.y * k }), flat_point(f, geometry.Point { x: x0 + tl.x - tl.x * k, y: y0 }), flat_point(f, geometry.Point { x: x0 + tl.x, y: y0 }))
    ret flat_close(f)
}

fn clamp_radius(radius: geometry.Radius, r: geometry.Rect) -> geometry.Radius {
    var x = radius.x
    var y = radius.y
    if !(x >= 0.0) { x = 0.0 }
    if !(y >= 0.0) { y = 0.0 }
    if x > r.width * 0.5 { x = r.width * 0.5 }
    if y > r.height * 0.5 { y = r.height * 0.5 }
    ret geometry.Radius { x: x, y: y }
}

fn fill_flattener(s: *RendererState, t: geometry.Transform) -> Flattener {
    var f: Flattener = zero
    f.s = s
    f.t = t
    f.stroke = false
    ret f
}

fn stroke_flattener(s: *RendererState, t: geometry.Transform, stroke: paint.Stroke) -> Flattener {
    var f: Flattener = zero
    f.s = s
    f.t = t
    f.stroke = true
    // The width is scaled by the transform's mean scale; an anisotropic stroke is
    // the outline-then-transform upgrade.
    let scale = math.sqrt[f32](math.abs[f32](t.m00 * t.m11 - t.m01 * t.m10))
    f.hw = stroke.width * 0.5 * scale
    f.cap = stroke.cap
    f.join = stroke.join
    f.miter_limit = stroke.miter_limit
    if !(f.miter_limit >= 1.0) { f.miter_limit = 4.0 }
    ret f
}

// The glyph's outline from `glyf`, offset and scaled into pixel space, into the
// flattener as quadratic contours; a composite glyph places its components.
fn glyph_outline(f: *Flattener, font: *const FontEntry, glyph: u32, ox: f32, oy: f32, sx: f32, sy: f32, depth: usize) -> err {
    if usize(glyph) >= font.glyph_count || depth > 4usize { ret ok }
    var start = 0usize
    var end = 0usize
    if font.long_loca {
        start = usize(be32(font.data, font.loca + 4usize * usize(glyph)))
        end = usize(be32(font.data, font.loca + 4usize * usize(glyph) + 4usize))
    } else {
        start = 2usize * usize(be16(font.data, font.loca + 2usize * usize(glyph)))
        end = 2usize * usize(be16(font.data, font.loca + 2usize * usize(glyph) + 2usize))
    }
    if end <= start || end > font.glyf_len || end - start < 10usize { ret ok }
    let d = font.data
    let g = font.glyf + start
    let contours = be16(d, g)
    if contours >= 32768u32 { ret composite_outline(f, font, g, end - start, ox, oy, sx, sy, depth) }
    let count = usize(contours)
    var end_points: [64]usize = zero
    if count > 64usize { ret TooLarge }
    var i = 0usize
    var point_count = 0usize
    while i < count {
        end_points[i] = usize(be16(d, g + 10usize + 2usize * i))
        point_count = end_points[i] + 1usize
        i += 1usize
    }
    if point_count > 1024usize { ret TooLarge }
    let instruction_length = usize(be16(d, g + 10usize + 2usize * count))
    var at = g + 12usize + 2usize * count + instruction_length
    // Flags, with repeats.
    var flags: [1024]u8 = zero
    i = 0usize
    while i < point_count {
        if at >= d.len { ret ok }
        let flag = d[at]
        at += 1usize
        flags[i] = flag
        i += 1usize
        if flag & 8u8 != 0u8 {
            if at >= d.len { ret ok }
            var repeats = usize(d[at])
            at += 1usize
            while repeats > 0usize && i < point_count {
                flags[i] = flag
                i += 1usize
                repeats = repeats - 1usize
            }
        }
    }
    var xs: [1024]f32 = zero
    var ys: [1024]f32 = zero
    var value = 0i32
    i = 0usize
    while i < point_count {
        let flag = flags[i]
        if flag & 2u8 != 0u8 {
            if at >= d.len { ret ok }
            let delta = i32(d[at])
            at += 1usize
            if flag & 16u8 != 0u8 { value = value + delta } else { value = value - delta }
        } else {
            if flag & 16u8 == 0u8 {
                if at + 2usize > d.len { ret ok }
                value = value + i32(mem.bitcast[i16](u16(be16(d, at))))
                at += 2usize
            }
        }
        xs[i] = f32(value)
        i += 1usize
    }
    value = 0i32
    i = 0usize
    while i < point_count {
        let flag = flags[i]
        if flag & 4u8 != 0u8 {
            if at >= d.len { ret ok }
            let delta = i32(d[at])
            at += 1usize
            if flag & 32u8 != 0u8 { value = value + delta } else { value = value - delta }
        } else {
            if flag & 32u8 == 0u8 {
                if at + 2usize > d.len { ret ok }
                value = value + i32(mem.bitcast[i16](u16(be16(d, at))))
                at += 2usize
            }
        }
        ys[i] = f32(value)
        i += 1usize
    }
    // Each contour: on-curve points are line targets, off-curve ones quadratic
    // controls, two off-curve in a row implying the on-curve midpoint.
    var first = 0usize
    var c = 0usize
    while c < count {
        let last = end_points[c]
        if last >= first {
            let n = last - first + 1usize
            // The start: the first on-curve point, or the midpoint of the first two.
            var start_index = first
            var start_point = geometry.Point { x: ox + xs[first] * sx, y: oy - ys[first] * sy }
            var start_on = flags[first] & 1u8 != 0u8
            if !start_on {
                let next = first + 1usize
                if n > 1usize && flags[next] & 1u8 != 0u8 {
                    start_index = next
                    start_point = geometry.Point { x: ox + xs[next] * sx, y: oy - ys[next] * sy }
                } else {
                    start_point = geometry.Point { x: ox + (xs[first] + xs[first + (1usize % n)]) * 0.5 * sx, y: oy - (ys[first] + ys[first + (1usize % n)]) * 0.5 * sy }
                }
            }
            try flat_end(f)
            f.current = start_point
            f.start = start_point
            f.open = true
            var control = geometry.Point { x: 0.0, y: 0.0 }
            var has_control = false
            var k = 1usize
            while k <= n {
                let index = first + (start_index - first + k) % n
                let p = geometry.Point { x: ox + xs[index] * sx, y: oy - ys[index] * sy }
                let on = flags[index] & 1u8 != 0u8
                if on {
                    if has_control { try flat_quad(f, control, p) } else { try flat_line(f, p) }
                    has_control = false
                } else {
                    if has_control {
                        let mid = geometry.Point { x: (control.x + p.x) * 0.5, y: (control.y + p.y) * 0.5 }
                        try flat_quad(f, control, mid)
                    }
                    control = p
                    has_control = true
                }
                k += 1usize
            }
            if has_control { try flat_quad(f, control, start_point) }
            try flat_close(f)
        }
        first = last + 1usize
        c += 1usize
    }
    ret ok
}

fn composite_outline(f: *Flattener, font: *const FontEntry, g: usize, len: usize, ox: f32, oy: f32, sx: f32, sy: f32, depth: usize) -> err {
    let d = font.data
    var at = g + 10usize
    var more = true
    while more && at + 4usize <= g + len {
        let flags = be16(d, at)
        let component = be16(d, at + 2usize)
        at += 4usize
        var dx: f32 = 0.0
        var dy: f32 = 0.0
        if flags & 1u32 != 0u32 {
            dx = f32(mem.bitcast[i16](u16(be16(d, at))))
            dy = f32(mem.bitcast[i16](u16(be16(d, at + 2usize))))
            at += 4usize
        } else {
            dx = f32(mem.bitcast[i8](d[at]))
            dy = f32(mem.bitcast[i8](d[at + 1usize]))
            at += 2usize
        }
        var scale_x: f32 = 1.0
        var scale_y: f32 = 1.0
        if flags & 8u32 != 0u32 {
            scale_x = f2dot14(d, at)
            scale_y = scale_x
            at += 2usize
        }
        if flags & 64u32 != 0u32 {
            scale_x = f2dot14(d, at)
            scale_y = f2dot14(d, at + 2usize)
            at += 4usize
        }
        if flags & 128u32 != 0u32 {
            // A 2x2 transform: its diagonal is honoured, the shear is not (ponytail).
            scale_x = f2dot14(d, at)
            scale_y = f2dot14(d, at + 6usize)
            at += 8usize
        }
        if flags & 2u32 == 0u32 {
            dx = 0.0
            dy = 0.0
        }
        try glyph_outline(f, font, component, ox + dx * sx, oy - dy * sy, sx * scale_x, sy * scale_y, depth + 1usize)
        more = flags & 32u32 != 0u32
    }
    ret ok
}

fn f2dot14(d: []const u8, at: usize) -> f32 {
    ret f32(mem.bitcast[i16](u16(be16(d, at)))) / 16384.0
}

fn font_of(s: *RendererState, id: shape.FontId) -> (usize, bool) {
    var i = 0usize
    while i < s.font_count {
        if s.fonts[i].id == id { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// A text layout: every glyph of every run of every line, at the run's pen.
fn text_edges(s: *RendererState, f: *Flattener, text: DrawText) -> err {
    var l = 0usize
    while l < text.layout.lines.len {
        let line = &text.layout.lines[l]
        var ri = 0usize
        while ri < line.runs.len {
            let run = &line.runs[ri]
            let (font_index, has_font) = font_of(s, run.run.font)
            if has_font {
                let font = &s.fonts[font_index]
                let scale = run.size / font.upem
                var pen = text.origin.x + run.origin.x
                let baseline = text.origin.y + run.origin.y
                var g = 0usize
                while g < run.run.glyphs.len {
                    let glyph = run.run.glyphs[g]
                    let origin = geometry.transform_point(f.t, geometry.Point { x: pen + glyph.offset_x * run.size, y: baseline - glyph.offset_y * run.size })
                    // The glyph's own scale under the transform's axes.
                    try glyph_outline(f, font, glyph.id, origin.x, origin.y, scale * f.t.m00, scale * f.t.m11, 0usize)
                    pen = pen + glyph.advance_x * run.size
                    g += 1usize
                }
            }
            ri += 1usize
        }
        l += 1usize
    }
    ret ok
}

fn draw_image(s: *RendererState, state: DrawState, draw: DrawImage) -> err {
    let (slot, slot_error) = texture_slot(s, draw.texture)
    if slot_error != ok { ret slot_error }
    let t = &s.textures[slot]
    let (inverse, invertible) = transform_invert(state.transform)
    if !invertible || draw.destination.width <= 0.0 || draw.destination.height <= 0.0 { ret ok }
    // The destination's corners under the transform bound the pixels visited.
    let (verbs, points) = rect_path(draw.destination)
    var bx0: f32 = 3.4e38
    var by0: f32 = 3.4e38
    var bx1: f32 = -3.4e38
    var by1: f32 = -3.4e38
    var i = 0usize
    while i < 4usize {
        let p = geometry.transform_point(state.transform, points[i])
        if p.x < bx0 { bx0 = p.x }
        if p.y < by0 { by0 = p.y }
        if p.x > bx1 { bx1 = p.x }
        if p.y > by1 { by1 = p.y }
        i += 1usize
    }
    let bounds = geometry.intersect(state.scissor, geometry.Rect { x: bx0, y: by0, width: bx1 - bx0, height: by1 - by0 })
    let (x0, y0, x1, y1) = scissor_bounds(s, bounds)
    let canvas = s.canvases[state.layer].data
    var y = y0
    while y < y1 {
        var x = x0
        while x < x1 {
            let p = geometry.transform_point(inverse, geometry.Point { x: f32(x) + 0.5, y: f32(y) + 0.5 })
            let u = (p.x - draw.destination.x) / draw.destination.width
            let v = (p.y - draw.destination.y) / draw.destination.height
            if u >= 0.0 && u < 1.0 && v >= 0.0 && v < 1.0 {
                let sx = draw.source.x + u * draw.source.width
                let sy = draw.source.y + v * draw.source.height
                let color = sample_texture(t, sx, sy)
                let index = y * s.width + x
                var weight = draw.opacity
                if state.has_mask { weight = weight * s.masks[state.mask].data[index] }
                blend_pixel(canvas, index * 4usize, color, weight)
            }
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// Bilinear, the texture's edge clamped; premultiplied in and out.
fn sample_texture(t: *const Texture, sx: f32, sy: f32) -> paint.Color {
    var fx = sx - 0.5
    var fy = sy - 0.5
    let max_x = f32(t.width) - 1.0
    let max_y = f32(t.height) - 1.0
    if !(fx >= 0.0) { fx = 0.0 }
    if !(fy >= 0.0) { fy = 0.0 }
    if fx > max_x { fx = max_x }
    if fy > max_y { fy = max_y }
    let x0 = usize(math.floor[f32](fx))
    let y0 = usize(math.floor[f32](fy))
    var x1 = x0 + 1usize
    var y1 = y0 + 1usize
    if x1 >= usize(t.width) { x1 = x0 }
    if y1 >= usize(t.height) { y1 = y0 }
    let u = fx - f32(x0)
    let v = fy - f32(y0)
    var out: [4]f32 = zero
    var c = 0usize
    while c < 4usize {
        let p00 = t.pixels[(y0 * usize(t.width) + x0) * 4usize + c]
        let p10 = t.pixels[(y0 * usize(t.width) + x1) * 4usize + c]
        let p01 = t.pixels[(y1 * usize(t.width) + x0) * 4usize + c]
        let p11 = t.pixels[(y1 * usize(t.width) + x1) * 4usize + c]
        out[c] = (p00 * (1.0 - u) + p10 * u) * (1.0 - v) + (p01 * (1.0 - u) + p11 * u) * v
        c += 1usize
    }
    ret paint.Color { red: out[0], green: out[1], blue: out[2], alpha: out[3] }
}

// A layer composited onto the one below it at its opacity.
fn merge_layer(s: *RendererState, from: usize, into: usize, opacity: f32, x0: usize, y0: usize, x1: usize, y1: usize) {
    let src = s.canvases[from].data
    let dst = s.canvases[into].data
    if x1 <= x0 { ret }
    var y = y0
    while y < y1 {
        var i = y * s.width + x0
        let end = y * s.width + x1
        while i < end {
            let at = i * 4usize
            let a = src[at + 3usize] * opacity
            let keep = 1.0 - a
            dst[at] = src[at] * opacity + dst[at] * keep
            dst[at + 1usize] = src[at + 1usize] * opacity + dst[at + 1usize] * keep
            dst[at + 2usize] = src[at + 2usize] * opacity + dst[at + 2usize] * keep
            dst[at + 3usize] = a + dst[at + 3usize] * keep
            i += 1usize
        }
        y += 1usize
    }
}

// ------------------------------------------------------------ damage (D914)
//
// What a frame changes is found by comparing its commands with the last rendered
// scene's: with the same structure (every Save, Restore, Transform, Clip and layer
// alike), the damage is the union of the device bounds of the drawing commands that
// differ, old and new; a structural difference, a first frame or a resize damages
// the frame. A command clear of the damage is skipped, the canvas and the pixels are
// touched inside it alone, and the rows written to the frame are the damage's plus
// the previous frame's (the back image missed that one).

fn color_eq(a: paint.Color, b: paint.Color) -> bool {
    ret a.red == b.red && a.green == b.green && a.blue == b.blue && a.alpha == b.alpha
}

fn stops_eq(a: []const paint.Stop, b: []const paint.Stop) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i].offset != b[i].offset || !color_eq(a[i].color, b[i].color) { ret false }
        i += 1usize
    }
    ret true
}

fn point_eq(a: geometry.Point, b: geometry.Point) -> bool {
    ret a.x == b.x && a.y == b.y
}

fn rect_eq(a: geometry.Rect, b: geometry.Rect) -> bool {
    ret a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height
}

fn brush_eq(a: *const paint.Brush, b: *const paint.Brush) -> bool {
    if a.tag != b.tag { ret false }
    switch *a {
    case .Solid as ca:
        switch *b {
        case .Solid as cb:
            ret color_eq(ca, cb)
        default:
            ret false
        }
    case .Linear as la:
        switch *b {
        case .Linear as lb:
            ret point_eq(la.start, lb.start) && point_eq(la.end, lb.end) && stops_eq(la.stops, lb.stops)
        default:
            ret false
        }
    case .Radial as ra:
        switch *b {
        case .Radial as rb:
            ret point_eq(ra.center, rb.center) && ra.radius == rb.radius && stops_eq(ra.stops, rb.stops)
        default:
            ret false
        }
    }
    ret false
}

fn path_eq(a: geometry.Path, b: geometry.Path) -> bool {
    if a.verbs.len != b.verbs.len || a.points.len != b.points.len { ret false }
    var i = 0usize
    while i < a.verbs.len {
        if a.verbs[i] != b.verbs[i] { ret false }
        i += 1usize
    }
    i = 0usize
    while i < a.points.len {
        if !point_eq(a.points[i], b.points[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn rrect_eq(a: geometry.RRect, b: geometry.RRect) -> bool {
    ret rect_eq(a.rect, b.rect) && a.top_left.x == b.top_left.x && a.top_left.y == b.top_left.y && a.top_right.x == b.top_right.x && a.top_right.y == b.top_right.y && a.bottom_right.x == b.bottom_right.x && a.bottom_right.y == b.bottom_right.y && a.bottom_left.x == b.bottom_left.x && a.bottom_left.y == b.bottom_left.y
}

fn transform_eq(a: geometry.Transform, b: geometry.Transform) -> bool {
    ret a.m00 == b.m00 && a.m01 == b.m01 && a.m02 == b.m02 && a.m10 == b.m10 && a.m11 == b.m11 && a.m12 == b.m12
}

fn layout_eq(a: *const layout.Layout, b: *const layout.Layout) -> bool {
    if !rect_eq(a.bounds, b.bounds) || a.lines.len != b.lines.len { ret false }
    var l = 0usize
    while l < a.lines.len {
        let la = &a.lines[l]
        let lb = &b.lines[l]
        if la.runs.len != lb.runs.len || la.baseline != lb.baseline || !rect_eq(la.bounds, lb.bounds) { ret false }
        var r = 0usize
        while r < la.runs.len {
            let ra = &la.runs[r]
            let rb = &lb.runs[r]
            if ra.size != rb.size || !point_eq(ra.origin, rb.origin) || ra.run.font != rb.run.font || ra.run.glyphs.len != rb.run.glyphs.len { ret false }
            var g = 0usize
            while g < ra.run.glyphs.len {
                let ga = ra.run.glyphs[g]
                let gb = rb.run.glyphs[g]
                if ga.id != gb.id || ga.advance_x != gb.advance_x || ga.advance_y != gb.advance_y || ga.offset_x != gb.offset_x || ga.offset_y != gb.offset_y { ret false }
                g += 1usize
            }
            r += 1usize
        }
        l += 1usize
    }
    ret true
}

fn command_eq(a: *const Command, b: *const Command) -> bool {
    if a.tag != b.tag { ret false }
    switch *a {
    case .Save:
        ret true
    case .Restore:
        ret true
    case .Transform as ta:
        switch *b {
        case .Transform as tb:
            ret transform_eq(ta, tb)
        default:
            ret false
        }
    case .Clip as ca:
        switch *b {
        case .Clip as cb:
            if ca.tag != cb.tag { ret false }
            switch ca {
            case .Rect as ra:
                switch cb {
                case .Rect as rb:
                    ret rect_eq(ra, rb)
                default:
                    ret false
                }
            case .Rounded as ra:
                switch cb {
                case .Rounded as rb:
                    ret rrect_eq(ra, rb)
                default:
                    ret false
                }
            case .Path as pa:
                switch cb {
                case .Path as pb:
                    ret path_eq(pa, pb)
                default:
                    ret false
                }
            }
            ret false
        default:
            ret false
        }
    case .FillRect as fa:
        switch *b {
        case .FillRect as fb:
            ret rect_eq(fa.rect, fb.rect) && brush_eq(&fa.brush, &fb.brush)
        default:
            ret false
        }
    case .FillPath as fa:
        switch *b {
        case .FillPath as fb:
            ret path_eq(fa.path, fb.path) && brush_eq(&fa.brush, &fb.brush)
        default:
            ret false
        }
    case .StrokePath as sa:
        switch *b {
        case .StrokePath as sb:
            ret path_eq(sa.path, sb.path) && brush_eq(&sa.brush, &sb.brush) && sa.stroke.width == sb.stroke.width && sa.stroke.cap == sb.stroke.cap && sa.stroke.join == sb.stroke.join && sa.stroke.miter_limit == sb.stroke.miter_limit
        default:
            ret false
        }
    case .Image as ia:
        switch *b {
        case .Image as ib:
            ret ia.texture.slot == ib.texture.slot && ia.texture.generation == ib.texture.generation && rect_eq(ia.source, ib.source) && rect_eq(ia.destination, ib.destination) && ia.opacity == ib.opacity
        default:
            ret false
        }
    case .Text as ta:
        switch *b {
        case .Text as tb:
            ret point_eq(ta.origin, tb.origin) && brush_eq(&ta.brush, &tb.brush) && layout_eq(ta.layout, tb.layout)
        default:
            ret false
        }
    case .OpacityLayer as la:
        switch *b {
        case .OpacityLayer as lb:
            ret rect_eq(la.bounds, lb.bounds) && la.opacity == lb.opacity
        default:
            ret false
        }
    }
    ret false
}

// The device-space box of a rect under a transform.
fn transform_rect(t: geometry.Transform, r: geometry.Rect) -> geometry.Rect {
    let p0 = geometry.transform_point(t, geometry.Point { x: r.x, y: r.y })
    let p1 = geometry.transform_point(t, geometry.Point { x: r.x + r.width, y: r.y })
    let p2 = geometry.transform_point(t, geometry.Point { x: r.x, y: r.y + r.height })
    let p3 = geometry.transform_point(t, geometry.Point { x: r.x + r.width, y: r.y + r.height })
    var x0 = p0.x
    var x1 = p0.x
    var y0 = p0.y
    var y1 = p0.y
    if p1.x < x0 { x0 = p1.x }
    if p2.x < x0 { x0 = p2.x }
    if p3.x < x0 { x0 = p3.x }
    if p1.x > x1 { x1 = p1.x }
    if p2.x > x1 { x1 = p2.x }
    if p3.x > x1 { x1 = p3.x }
    if p1.y < y0 { y0 = p1.y }
    if p2.y < y0 { y0 = p2.y }
    if p3.y < y0 { y0 = p3.y }
    if p1.y > y1 { y1 = p1.y }
    if p2.y > y1 { y1 = p2.y }
    if p3.y > y1 { y1 = p3.y }
    ret geometry.Rect { x: x0, y: y0, width: x1 - x0, height: y1 - y0 }
}

fn path_bounds(p: geometry.Path) -> geometry.Rect {
    if p.points.len == 0usize { ret geometry.Rect { x: 0.0, y: 0.0, width: 0.0, height: 0.0 } }
    var x0 = p.points[0usize].x
    var x1 = x0
    var y0 = p.points[0usize].y
    var y1 = y0
    var i = 1usize
    while i < p.points.len {
        let q = p.points[i]
        if q.x < x0 { x0 = q.x }
        if q.x > x1 { x1 = q.x }
        if q.y < y0 { y0 = q.y }
        if q.y > y1 { y1 = q.y }
        i += 1usize
    }
    ret geometry.Rect { x: x0, y: y0, width: x1 - x0, height: y1 - y0 }
}

// A drawing command's device box, padded for anti-aliasing and glyphs past their
// line box; a structural command has none.
fn command_bounds(t: geometry.Transform, c: *const Command) -> (geometry.Rect, bool) {
    var user: geometry.Rect = zero
    var pad: f32 = 2.0
    switch *c {
    case .FillRect as fill:
        user = fill.rect
    case .FillPath as fill:
        user = path_bounds(fill.path)
    case .StrokePath as stroke:
        user = path_bounds(stroke.path)
        pad = pad + stroke.stroke.width * 2.0
    case .Image as draw:
        user = draw.destination
    case .Text as text:
        let b = text.layout.bounds
        user = geometry.Rect { x: text.origin.x + b.x, y: text.origin.y + b.y, width: b.width, height: b.height }
        pad = pad + 12.0
    default:
        ret (zero, false)
    }
    let device = transform_rect(t, user)
    ret (geometry.Rect { x: device.x - pad, y: device.y - pad, width: device.width + 2.0 * pad, height: device.height + 2.0 * pad }, true)
}

// The damage of `scene` against the last rendered one, as a pixel box; `full`
// when the frame is damaged whole. `s.skip` is set for the drawing commands the
// damage misses.
// One list's walk from a prefix's end: the bounds of every drawing command in
// `commands[from..to)` joined into `damage`, the transform stack kept from `t`
// at `base` depth. Answers false when the stretch is not self-contained -- it
// ends at another depth, restores past its start, or moves the transform or the
// clip at its own depth, which the commands after it would feel.
fn damage_stretch(commands: []const Command, from: usize, to: usize, t: geometry.Transform, damage: *geometry.Rect) -> bool {
    var stack: [32]geometry.Transform = zero
    var depth = 0usize
    var current = t
    var i = from
    while i < to {
        let c = &commands[i]
        let (bounds, drawing) = command_bounds(current, c)
        if drawing {
            *damage = geometry.union_rect(*damage, bounds)
        } else {
            switch *c {
            case .Save:
                if depth >= 32usize { ret false }
                stack[depth] = current
                depth += 1usize
            case .OpacityLayer as layer:
                if depth >= 32usize { ret false }
                stack[depth] = current
                depth += 1usize
                *damage = geometry.union_rect(*damage, transform_rect(current, layer.bounds))
            case .Restore:
                if depth == 0usize { ret false }
                depth = depth - 1usize
                current = stack[depth]
            case .Transform as change:
                if depth == 0usize { ret false }
                current = transform_compose(current, change)
            case .Clip as clip:
                if depth == 0usize { ret false }
            default:
                current = current
            }
        }
        i += 1usize
    }
    ret depth == 0usize
}

// The damage of `scene` against the last rendered one, as a pixel box; `full`
// when the frame is damaged whole. The lists are aligned by their longest equal
// prefix and suffix; what lies between in either list is the damage, when that
// middle is self-contained (`damage_stretch`), so a tooltip appearing, a menu
// opening or a row added repaint their own box. `s.skip` is set for the drawing
// commands the damage misses.
fn damage_of(s: *RendererState, scene: *const Scene) -> bool {
    var full = !s.has_last || s.last_width != s.width || s.last_height != s.height || s.last_scale != s.scale
    var old: *const Scene = scene
    if !full { old = &s.scenes[s.last_scene] }
    var damage: geometry.Rect = zero
    var stack: [32]geometry.Transform = zero
    var depth = 0usize
    var t = geometry.transform_scale(s.scale, s.scale)
    // The prefix: equal commands, the transform followed.
    var i = 0usize
    while !full && i < scene.count && i < old.count {
        let c = &scene.commands[i]
        if !command_eq(c, &old.commands[i]) { break }
        switch *c {
        case .Save:
            if depth >= 32usize {
                full = true
                break
            }
            stack[depth] = t
            depth += 1usize
        case .OpacityLayer as layer:
            if depth >= 32usize {
                full = true
                break
            }
            stack[depth] = t
            depth += 1usize
        case .Restore:
            if depth == 0usize {
                full = true
                break
            }
            depth = depth - 1usize
            t = stack[depth]
        case .Transform as change:
            t = transform_compose(t, change)
        default:
            t = t
        }
        i += 1usize
    }
    if !full && (i < scene.count || i < old.count) {
        // The suffix: equal commands from the ends, never past the prefix.
        var tail = 0usize
        while i + tail < scene.count && i + tail < old.count {
            if !command_eq(&scene.commands[scene.count - 1usize - tail], &old.commands[old.count - 1usize - tail]) { break }
            tail += 1usize
        }
        if !damage_stretch(scene.commands, i, scene.count - tail, t, &damage) { full = true }
        if !full && !damage_stretch(old.commands, i, old.count - tail, t, &damage) { full = true }
    }
    if full {
        s.dx0 = 0usize
        s.dy0 = 0usize
        s.dx1 = s.width
        s.dy1 = s.height
    } else {
        let (x0, y0, x1, y1) = scissor_bounds(s, damage)
        s.dx0 = x0
        s.dy0 = y0
        s.dx1 = x1
        s.dy1 = y1
    }
    // Skips: only inside a partial frame; recomputed against the final damage.
    if s.skip.len < scene.count {
        let (grown, grown_error) = mem.alloc[bool](s.arena, scene.count + 256usize)
        if grown_error == ok { s.skip = grown }
    }
    let box = geometry.Rect { x: f32(s.dx0), y: f32(s.dy0), width: f32(s.dx1 - s.dx0), height: f32(s.dy1 - s.dy0) }
    depth = 0usize
    t = geometry.transform_scale(s.scale, s.scale)
    i = 0usize
    while i < scene.count && i < s.skip.len {
        let c = &scene.commands[i]
        s.skip[i] = false
        let (bounds, drawing) = command_bounds(t, c)
        if drawing {
            if !full {
                let hit = geometry.intersect(bounds, box)
                if hit.width <= 0.0 || hit.height <= 0.0 { s.skip[i] = true }
            }
        } else {
            switch *c {
            case .Save:
                if depth < 32usize {
                    stack[depth] = t
                    depth += 1usize
                }
            case .OpacityLayer as layer:
                if depth < 32usize {
                    stack[depth] = t
                    depth += 1usize
                }
            case .Restore:
                if depth > 0usize {
                    depth = depth - 1usize
                    t = stack[depth]
                }
            case .Transform as change:
                t = transform_compose(t, change)
            default:
                t = t
            }
        }
        i += 1usize
    }
    ret full
}

// Clears a canvas inside a pixel box.
fn clear_box(s: *RendererState, data: []f32, x0: usize, y0: usize, x1: usize, y1: usize) {
    if x1 <= x0 { ret }
    var y = y0
    while y < y1 {
        let from = (y * s.width + x0) * 4usize
        clear_floats(data[from..from + (x1 - x0) * 4usize], (x1 - x0) * 4usize)
        y += 1usize
    }
}

// An axis-aligned rect with one colour and no mask, painted without the
// rasteriser (D914): the pixels it covers whole take the colour by two eight-byte
// stores each, the rim blends its fractional overlap. Answers false when the
// general path is needed.
fn fill_rect_fast(s: *RendererState, state: DrawState, fill: FillRect) -> bool {
    if state.has_mask || state.transform.m01 != 0.0 || state.transform.m10 != 0.0 { ret false }
    var color: paint.Color = zero
    switch fill.brush {
    case .Solid as c:
        color = paint.premultiply(c)
    default:
        ret false
    }
    let device = geometry.intersect(transform_rect(state.transform, fill.rect), state.scissor)
    if !(device.width > 0.0) || !(device.height > 0.0) { ret true }
    let (px0, py0, px1, py1) = scissor_bounds(s, device)
    if px1 <= px0 || py1 <= py0 { ret true }
    let right = device.x + device.width
    let bottom = device.y + device.height
    let opaque = color.alpha >= 1.0
    let rg = u64(mem.bitcast[u32](color.red)) | (u64(mem.bitcast[u32](color.green)) << 32u64)
    let ba = u64(mem.bitcast[u32](color.blue)) | (u64(mem.bitcast[u32](color.alpha)) << 32u64)
    let canvas = s.canvases[state.layer].data
    var y = py0
    while y < py1 {
        var row_cover: f32 = 1.0
        let top = f32(y)
        if device.y > top { row_cover = row_cover - (device.y - top) }
        if bottom < top + 1.0 { row_cover = row_cover - (top + 1.0 - bottom) }
        if row_cover > 0.0 {
            var x = px0
            var index = y * s.width + px0
            while x < px1 {
                var cover = row_cover
                let left = f32(x)
                if device.x > left { cover = cover - (device.x - left) }
                if right < left + 1.0 { cover = cover - (left + 1.0 - right) }
                if cover >= 1.0 && opaque {
                    let first = mem.cast[*u64](&canvas[index * 4usize])
                    *first = rg
                    let second = mem.cast[*u64](&canvas[index * 4usize + 2usize])
                    *second = ba
                } else if cover > 0.0 {
                    blend_pixel(canvas, index * 4usize, color, cover)
                }
                x += 1usize
                index += 1usize
            }
        }
        y += 1usize
    }
    ret true
}

fn run_commands(s: *RendererState, scene: *const Scene, coverage: []f32) -> err {
    var states: [32]DrawState = zero
    var depth = 0usize
    var current: DrawState = zero
    current.transform = geometry.transform_scale(s.scale, s.scale)
    current.scissor = geometry.Rect { x: f32(s.dx0), y: f32(s.dy0), width: f32(s.dx1 - s.dx0), height: f32(s.dy1 - s.dy0) }
    current.opacity = 1.0
    var mask_count = 0usize
    var layer_count = 1usize
    var i = 0usize
    while i < scene.count {
        let command = scene.commands[i]
        if i < s.skip.len && s.skip[i] {
            i += 1usize
            continue
        }
        switch command {
        case .Save:
            if depth >= MAX_STATES { ret TooLarge }
            states[depth] = current
            depth += 1usize
            current.opens_layer = false
        case .Restore:
            if depth == 0usize { ret Invalid }
            depth = depth - 1usize
            if current.opens_layer {
                merge_layer(s, current.layer, states[depth].layer, current.opacity, current.layer_x0, current.layer_y0, current.layer_x1, current.layer_y1)
                layer_count = layer_count - 1usize
            }
            if current.has_mask && !states[depth].has_mask { mask_count = 0usize }
            if current.has_mask && states[depth].has_mask { mask_count = states[depth].mask + 1usize }
            current = states[depth]
        case .Transform as t:
            current.transform = transform_compose(current.transform, t)
        case .Clip as clip:
            switch clip {
            case .Rect as r:
                if current.transform.m01 == 0.0 && current.transform.m10 == 0.0 {
                    let p0 = geometry.transform_point(current.transform, geometry.Point { x: r.x, y: r.y })
                    let p1 = geometry.transform_point(current.transform, geometry.Point { x: r.x + r.width, y: r.y + r.height })
                    var x0 = p0.x
                    var x1 = p1.x
                    if x1 < x0 {
                        x0 = p1.x
                        x1 = p0.x
                    }
                    var y0 = p0.y
                    var y1 = p1.y
                    if y1 < y0 {
                        y0 = p1.y
                        y1 = p0.y
                    }
                    current.scissor = geometry.intersect(current.scissor, geometry.Rect { x: x0, y: y0, width: x1 - x0, height: y1 - y0 })
                } else {
                    let (verbs, points) = rect_path(r)
                    var f = fill_flattener(s, current.transform)
                    try flatten(&f, geometry.Path { verbs: verbs[0..], points: points[0..] })
                    try push_mask(s, &current, &mask_count, coverage)
                }
            case .Rounded as rr:
                var f = fill_flattener(s, current.transform)
                try rrect_edges(&f, rr)
                try push_mask(s, &current, &mask_count, coverage)
            case .Path as p:
                var f = fill_flattener(s, current.transform)
                try flatten(&f, p)
                try push_mask(s, &current, &mask_count, coverage)
            }
        case .FillRect as fill:
            if !fill_rect_fast(s, current, fill) {
                let (verbs, points) = rect_path(fill.rect)
                var f = fill_flattener(s, current.transform)
                try flatten(&f, geometry.Path { verbs: verbs[0..], points: points[0..] })
                rasterize_edges(s, coverage)
                paint_coverage(s, current, coverage, &fill.brush)
            }
        case .FillPath as fill:
            var f = fill_flattener(s, current.transform)
            try flatten(&f, fill.path)
            rasterize_edges(s, coverage)
            paint_coverage(s, current, coverage, &fill.brush)
        case .StrokePath as stroke:
            var f = stroke_flattener(s, current.transform, stroke.stroke)
            try flatten(&f, stroke.path)
            rasterize_edges(s, coverage)
            paint_coverage(s, current, coverage, &stroke.brush)
        case .Image as draw:
            try draw_image(s, current, draw)
        case .Text as text:
            var f = fill_flattener(s, current.transform)
            try text_edges(s, &f, text)
            rasterize_edges(s, coverage)
            paint_coverage(s, current, coverage, &text.brush)
        case .OpacityLayer as layer:
            if depth >= MAX_STATES { ret TooLarge }
            if layer_count >= MAX_LAYERS { ret TooLarge }
            states[depth] = current
            depth += 1usize
            try ensure_canvas(s, layer_count)
            // The layer lives inside its bounds (under the transform and the
            // scissor): cleared and merged there and nowhere else.
            let device = transform_rect(current.transform, layer.bounds)
            let (lx0, ly0, lx1, ly1) = scissor_bounds(s, geometry.intersect(current.scissor, geometry.Rect { x: device.x - 1.0, y: device.y - 1.0, width: device.width + 2.0, height: device.height + 2.0 }))
            current.layer_x0 = lx0
            current.layer_y0 = ly0
            current.layer_x1 = lx1
            current.layer_y1 = ly1
            current.scissor = geometry.Rect { x: f32(lx0), y: f32(ly0), width: f32(lx1 - lx0), height: f32(ly1 - ly0) }
            clear_box(s, s.canvases[layer_count].data, lx0, ly0, lx1, ly1)
            current.layer = layer_count
            current.opens_layer = true
            current.opacity = layer.opacity
            layer_count += 1usize
        }
        i += 1usize
    }
    ret ok
}

// The accumulated edges become the next mask: the current mask times this coverage.
fn push_mask(s: *RendererState, current: *DrawState, mask_count: *usize, coverage: []f32) -> err {
    if *mask_count >= MAX_MASKS { ret TooLarge }
    rasterize_edges(s, coverage)
    try ensure_mask(s, *mask_count)
    let mask = s.masks[*mask_count].data
    var y = s.dy0
    while y < s.dy1 {
        var x = s.dx0
        while x < s.dx1 {
            let i = y * s.width + x
            var c: f32 = 0.0
            if x >= s.box_x0 && x < s.box_x1 && y >= s.box_y0 && y < s.box_y1 { c = coverage[i] }
            if current.has_mask { c = c * s.masks[current.mask].data[i] }
            mask[i] = c
            x += 1usize
        }
        y += 1usize
    }
    current.mask = *mask_count
    current.has_mask = true
    *mask_count += 1usize
    ret ok
}

fn from_gpu(e: err) -> err {
    if e == gpu.Lost { ret Lost }
    if e == gpu.OutOfMemory { ret OutOfMemory }
    if e == gpu.TooLarge { ret TooLarge }
    ret Invalid
}

fn render(r: *Renderer, scene: SceneId, render_target: Target, size: geometry.Size) -> err {
    ret render_scaled(r, scene, render_target, size, 1.0)
}

// `render` under a device scale: `size` is logical, the frame is `size * scale`
// pixels, and every command is drawn through that scale (D913).
fn render_scaled(r: *Renderer, scene: SceneId, render_target: Target, size: geometry.Size, scale: f32) -> err {
    let (s, state_error) = renderer_state(r)
    if state_error != ok { ret state_error }
    let (slot, slot_error) = scene_slot(s, scene)
    if slot_error != ok { ret slot_error }
    let target_state = mem.cast[*TargetState](render_target.state)
    if mem.address_of(target_state) == 0usize { ret Invalid }
    if !(size.width >= 1.0) || !(size.height >= 1.0) || !finite(size.width) || !finite(size.height) { ret Invalid }
    if !(scale > 0.0) || !finite(scale) { ret Invalid }
    let (extent_width, extent_height) = gpu.extent(target_state.target)
    var width = usize(math.ceil[f32](size.width * scale))
    var height = usize(math.ceil[f32](size.height * scale))
    if width > usize(extent_width) { width = usize(extent_width) }
    if height > usize(extent_height) { height = usize(extent_height) }
    s.scale = scale
    // The buffers, each remade when a frame outgrows it.
    s.width = width
    s.height = height
    if s.acc.len < (width + 2usize) * height {
        let (acc, acc_error) = mem.alloc[f32](s.arena, (width + 2usize) * height)
        if acc_error != ok { ret OutOfMemory }
        s.acc = acc
    }
    if s.coverage.len < width * height {
        let (coverage, coverage_error) = mem.alloc[f32](s.arena, width * height)
        if coverage_error != ok { ret OutOfMemory }
        s.coverage = coverage
    }
    if s.pixels.len < width * height {
        let (pixels, pixels_error) = mem.alloc[u32](s.arena, width * height)
        if pixels_error != ok { ret OutOfMemory }
        s.pixels = pixels
    }
    try ensure_canvas(s, 0usize)
    let coverage = s.coverage
    let full = damage_of(s, &s.scenes[slot])
    let changed = s.dx1 > s.dx0 && s.dy1 > s.dy0
    if changed {
        clear_box(s, s.canvases[0usize].data, s.dx0, s.dy0, s.dx1, s.dy1)
        s.edge_count = 0usize
        let run_error = run_commands(s, &s.scenes[slot], coverage)
        if run_error != ok { ret run_error }
    }
    // The last rendered scene has been compared against; this one takes its place.
    if s.has_last && s.retiring && s.last_scene != slot { s.scenes[s.last_scene].live = false }
    s.retiring = false
    s.has_last = true
    s.last_scene = slot
    s.last_width = width
    s.last_height = height
    s.last_scale = scale
    if !changed { ret ok }
    let (frame, acquire_error) = gpu.acquire(target_state.target)
    if acquire_error != ok { ret from_gpu(acquire_error) }
    // The damaged canvas as packed pixels in the frame's channel order.
    let canvas = s.canvases[0usize].data
    let bgra = frame.image.format == .Bgra8
    var y = s.dy0
    while y < s.dy1 {
        var i = y * s.width + s.dx0
        let end = y * s.width + s.dx1
        while i < end {
            let at = i * 4usize
            let r8 = channel_byte(canvas[at])
            let g8 = channel_byte(canvas[at + 1usize])
            let b8 = channel_byte(canvas[at + 2usize])
            let a8 = channel_byte(canvas[at + 3usize])
            if bgra {
                s.pixels[i] = b8 | (g8 << 8u32) | (r8 << 16u32) | (a8 << 24u32)
            } else {
                s.pixels[i] = r8 | (g8 << 8u32) | (b8 << 16u32) | (a8 << 24u32)
            }
            i += 1usize
        }
        y += 1usize
    }
    // The rows written cover this damage and the last one: the back image is two
    // frames old.
    var wy0 = s.dy0
    var wy1 = s.dy1
    if full || s.wrote_y1 > s.wrote_y0 {
        if s.wrote_y0 < wy0 { wy0 = s.wrote_y0 }
        if s.wrote_y1 > wy1 { wy1 = s.wrote_y1 }
    }
    if full {
        wy0 = 0usize
        wy1 = height
    }
    if wy1 > height { wy1 = height }
    let write_error = gpu.write_image(s.queue, frame.image, 0u32, u32(wy0), u32(width), u32(wy1 - wy0), s.pixels[wy0 * width..wy1 * width])
    if write_error != ok { ret from_gpu(write_error) }
    s.wrote_y0 = s.dy0
    s.wrote_y1 = s.dy1
    let (shown, present_error) = gpu.present(s.queue, target_state.target, frame)
    if present_error != ok { ret from_gpu(present_error) }
    ret ok
}

fn channel_byte(v: f32) -> u32 {
    // A positive float truncates to its floor; the clamps make it positive.
    if !(v > 0.0) { ret 0u32 }
    if v >= 1.0 { ret 255u32 }
    ret u32(v * 255.0 + 0.5)
}

// ------------------------------------------------------------ 3-D techniques (algos.md)
// CPU passes over caller buffers, the reference the driver backend's kernels are
// measured against. Images are row-major, `width * height` pixels, `k` floats per
// pixel; a `[16]f32` matrix is row-major over column vectors (`p' = M p`); a depth
// buffer holds NDC z (`z / w`, -1 near .. 1 far, less is nearer) and is cleared by
// the caller to `1.0`; view space has the eye at the origin looking down -z, and
// `tan_x`/`tan_y` are the tangents of the half field of view. A vertex is `x y z w`
// in clip space followed by its attributes.

fn v3_norm(x: f32, y: f32, z: f32) -> (f32, f32, f32) {
    let l = math.sqrt[f32](x * x + y * y + z * z)
    if !(l > 0.0) { ret (0.0, 0.0, 0.0) }
    ret (x / l, y / l, z / l)
}

fn saturate(v: f32) -> f32 {
    if !(v > 0.0) { ret 0.0 }
    if v > 1.0 { ret 1.0 }
    ret v
}

fn smoothstep01(v: f32) -> f32 {
    let t = saturate(v)
    ret t * t * (3.0 - 2.0 * t)
}

// `out = a * b`, sixteen floats each, row-major.
fn mat4_mul(a: []const f32, b: []const f32, out: []f32) -> err {
    if a.len < 16usize || b.len < 16usize || out.len < 16usize { ret Invalid }
    var r = 0usize
    while r < 4usize {
        var c = 0usize
        while c < 4usize {
            out[r * 4usize + c] = a[r * 4usize] * b[c] + a[r * 4usize + 1usize] * b[4usize + c] + a[r * 4usize + 2usize] * b[8usize + c] + a[r * 4usize + 3usize] * b[12usize + c]
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

// `m * (x, y, z, 1)`, homogeneous.
fn mat4_apply(m: []const f32, x: f32, y: f32, z: f32) -> (f32, f32, f32, f32) {
    ret (m[0] * x + m[1] * y + m[2] * z + m[3], m[4] * x + m[5] * y + m[6] * z + m[7], m[8] * x + m[9] * y + m[10] * z + m[11], m[12] * x + m[13] * y + m[14] * z + m[15])
}

// A clip-space point's pixel coordinates: x right, y down, the centre of pixel
// (i, j) at (i + 0.5, j + 0.5).
fn screen_of(cx: f32, cy: f32, cw: f32, width: usize, height: usize) -> (f32, f32) {
    ret ((cx / cw * 0.5 + 0.5) * f32(width), (0.5 - cy / cw * 0.5) * f32(height))
}

fn clamp_index(v: f32, count: usize) -> usize {
    let f = math.floor[f32](v)
    if !(f > 0.0) { ret 0usize }
    if f >= f32(count) { ret count - 1usize }
    ret usize(f)
}

// Bilinear fetch of channel `c` at continuous pixel coordinates, edges clamped.
fn bilinear(buf: []const f32, channels: usize, width: usize, height: usize, fx: f32, fy: f32, c: usize) -> f32 {
    var x = fx - 0.5
    var y = fy - 0.5
    if !(x > 0.0) { x = 0.0 }
    if !(y > 0.0) { y = 0.0 }
    if x > f32(width - 1usize) { x = f32(width - 1usize) }
    if y > f32(height - 1usize) { y = f32(height - 1usize) }
    let x0 = usize(math.floor[f32](x))
    let y0 = usize(math.floor[f32](y))
    var x1 = x0 + 1usize
    var y1 = y0 + 1usize
    if x1 >= width { x1 = x0 }
    if y1 >= height { y1 = y0 }
    let u = x - f32(x0)
    let v = y - f32(y0)
    let p00 = buf[(y0 * width + x0) * channels + c]
    let p10 = buf[(y0 * width + x1) * channels + c]
    let p01 = buf[(y1 * width + x0) * channels + c]
    let p11 = buf[(y1 * width + x1) * channels + c]
    ret (p00 * (1.0 - u) + p10 * u) * (1.0 - v) + (p01 * (1.0 - u) + p11 * u) * v
}

// ------------------------------------------------------------ triangle rasterizer

fn edge_fn(ax: f32, ay: f32, bx: f32, by: f32, px: f32, py: f32) -> f32 {
    ret (bx - ax) * (py - ay) - (by - ay) * (px - ax)
}

// The top-left rule: a pixel centre exactly on an edge belongs to the triangle on
// one side only, and an edge and its reverse never agree.
fn top_left(ax: f32, ay: f32, bx: f32, by: f32) -> bool {
    let dx = bx - ax
    let dy = by - ay
    ret dy < 0.0 || (dy == 0.0 && dx > 0.0)
}

fn covers(w: f32, tl: bool) -> bool {
    ret w > 0.0 || (w == 0.0 && tl)
}

// One triangle: three vertices of `stride` floats each (`x y z w` then attributes)
// through the depth test into `out` (`stride - 4` floats per pixel), attributes
// perspective-correct. `peel` non-empty admits only fragments strictly behind it.
fn raster_tri(v: []const f32, stride: usize, width: usize, height: usize, depth: []f32, out: []f32, peel: []const f32, cull: bool) {
    let attrs = stride - 4usize
    var sx: [3]f32 = zero
    var sy: [3]f32 = zero
    var sz: [3]f32 = zero
    var iw: [3]f32 = zero
    var i = 0usize
    while i < 3usize {
        let w = v[i * stride + 3usize]
        // ponytail: no near-plane clipping; a vertex behind the eye drops the triangle.
        if !(w > 0.0) { ret }
        let (fx, fy) = screen_of(v[i * stride], v[i * stride + 1usize], w, width, height)
        sx[i] = fx
        sy[i] = fy
        sz[i] = v[i * stride + 2usize] / w
        iw[i] = 1.0 / w
        i += 1usize
    }
    var area = edge_fn(sx[0], sy[0], sx[1], sy[1], sx[2], sy[2])
    // Counter-clockwise in NDC is front-facing; y points down here, so that is negative.
    if area == 0.0 || (cull && area > 0.0) { ret }
    var i1 = 1usize
    var i2 = 2usize
    if area < 0.0 {
        i1 = 2usize
        i2 = 1usize
        area = 0.0 - area
    }
    let ax = sx[0]
    let ay = sy[0]
    let bx = sx[i1]
    let by = sy[i1]
    let cx = sx[i2]
    let cy = sy[i2]
    var x_lo = math.floor[f32](math.min[f32](ax, math.min[f32](bx, cx)))
    var y_lo = math.floor[f32](math.min[f32](ay, math.min[f32](by, cy)))
    var x_hi = math.ceil[f32](math.max[f32](ax, math.max[f32](bx, cx)))
    var y_hi = math.ceil[f32](math.max[f32](ay, math.max[f32](by, cy)))
    if !(x_lo > 0.0) { x_lo = 0.0 }
    if !(y_lo > 0.0) { y_lo = 0.0 }
    if x_hi > f32(width) { x_hi = f32(width) }
    if y_hi > f32(height) { y_hi = f32(height) }
    if !(x_lo < x_hi) || !(y_lo < y_hi) { ret }
    let tl0 = top_left(bx, by, cx, cy)
    let tl1 = top_left(cx, cy, ax, ay)
    let tl2 = top_left(ax, ay, bx, by)
    var py = usize(y_lo)
    while py < usize(y_hi) {
        var px = usize(x_lo)
        while px < usize(x_hi) {
            let pxf = f32(px) + 0.5
            let pyf = f32(py) + 0.5
            let w0 = edge_fn(bx, by, cx, cy, pxf, pyf)
            let w1 = edge_fn(cx, cy, ax, ay, pxf, pyf)
            let w2 = edge_fn(ax, ay, bx, by, pxf, pyf)
            if covers(w0, tl0) && covers(w1, tl1) && covers(w2, tl2) {
                let l0 = w0 / area
                let l1 = w1 / area
                let l2 = w2 / area
                let z = l0 * sz[0] + l1 * sz[i1] + l2 * sz[i2]
                let p = py * width + px
                var pass = z < depth[p]
                if peel.len != 0usize && !(z > peel[p]) { pass = false }
                if pass {
                    depth[p] = z
                    let q = l0 * iw[0] + l1 * iw[i1] + l2 * iw[i2]
                    var k = 0usize
                    while k < attrs {
                        out[p * attrs + k] = (l0 * v[4usize + k] * iw[0] + l1 * v[i1 * stride + 4usize + k] * iw[i1] + l2 * v[i2 * stride + 4usize + k] * iw[i2]) / q
                        k += 1usize
                    }
                }
            }
            px += 1usize
        }
        py += 1usize
    }
}

fn raster_core(v: []const f32, stride: usize, width: usize, height: usize, depth: []f32, out: []f32, peel: []const f32, cull: bool) -> err {
    let pixels = width * height
    if stride < 4usize || width == 0usize || height == 0usize || v.len % (3usize * stride) != 0usize { ret Invalid }
    if depth.len < pixels || out.len < pixels * (stride - 4usize) || (peel.len != 0usize && peel.len < pixels) { ret Invalid }
    var t = 0usize
    while t < v.len {
        raster_tri(v[t..t + 3usize * stride], stride, width, height, depth, out, peel, cull)
        t += 3usize * stride
    }
    ret ok
}

// Triangles of `x y z w r g b` per vertex through the depth test (less) into a
// caller depth buffer and an RGB colour buffer (three floats per pixel), the
// top-left rule deciding shared edges; `cull` drops back faces (clockwise in NDC).
fn rasterize(tris: []const f32, width: usize, height: usize, depth: []f32, color: []f32, cull: bool) -> err {
    var none: []const f32 = zero
    ret raster_core(tris, 7usize, width, height, depth, color, none, cull)
}

// The painter's order: object indices from the farthest to the nearest view-space
// depth of their centres (`x y z` each) under `view`, ties keeping their order.
fn paint_order(centres: []const f32, view: []const f32, order: []u32, depths: []f32) -> err {
    let n = centres.len / 3usize
    if centres.len % 3usize != 0usize || view.len < 16usize || order.len < n || depths.len < n { ret Invalid }
    var i = 0usize
    while i < n {
        depths[i] = 0.0 - (view[8] * centres[3usize * i] + view[9] * centres[3usize * i + 1usize] + view[10] * centres[3usize * i + 2usize] + view[11])
        order[i] = u32(i)
        i += 1usize
    }
    // ponytail: insertion sort, O(n^2); e.algo.sort's stable sort is the upgrade
    // past a few thousand objects.
    i = 1usize
    while i < n {
        let key = order[i]
        var j = i
        while j > 0usize && depths[usize(order[j - 1usize])] < depths[usize(key)] {
            order[j] = order[j - 1usize]
            j = j - 1usize
        }
        order[j] = key
        i += 1usize
    }
    ret ok
}

// ------------------------------------------------------------- deferred shading

fn shade_pixel(g: []const f32, lights: []const f32, eye: []const f32, ambient: f32, out: []f32) {
    let px = g[0]
    let py = g[1]
    let pz = g[2]
    let ar = g[3]
    let ag = g[4]
    let ab = g[5]
    let (nx, ny, nz) = v3_norm(g[6], g[7], g[8])
    let ks = g[9]
    let shine = g[10]
    let (vx, vy, vz) = v3_norm(eye[0] - px, eye[1] - py, eye[2] - pz)
    var r = ar * ambient
    var gr = ag * ambient
    var b = ab * ambient
    var l = 0usize
    while l < lights.len {
        let (lx, ly, lz) = v3_norm(lights[l] - px, lights[l + 1usize] - py, lights[l + 2usize] - pz)
        let diff = nx * lx + ny * ly + nz * lz
        if diff > 0.0 {
            let (hx, hy, hz) = v3_norm(lx + vx, ly + vy, lz + vz)
            var nh = nx * hx + ny * hy + nz * hz
            if nh < 0.0 { nh = 0.0 }
            let spec = ks * math.pow[f32](nh, shine)
            r = r + (ar * diff + spec) * lights[l + 3usize]
            gr = gr + (ag * diff + spec) * lights[l + 4usize]
            b = b + (ab * diff + spec) * lights[l + 5usize]
        }
        l += 6usize
    }
    out[0] = r
    out[1] = gr
    out[2] = b
}

// Deferred shading: a G-buffer pass rasterises vertices of `x y z w | px py pz |
// r g b | nx ny nz | ks shininess` into eleven floats per pixel (world position,
// albedo, normal, material) beside the depth buffer, then a lighting pass shades
// every covered pixel with Lambert diffuse and Blinn-Phong specular from point
// lights of `x y z r g b` and an ambient factor, into an RGB colour buffer.
fn deferred(tris: []const f32, width: usize, height: usize, depth: []f32, gbuffer: []f32, lights: []const f32, eye: []const f32, ambient: f32, color: []f32, cull: bool) -> err {
    let pixels = width * height
    if eye.len < 3usize || lights.len % 6usize != 0usize || color.len < pixels * 3usize { ret Invalid }
    var none: []const f32 = zero
    try raster_core(tris, 15usize, width, height, depth, gbuffer, none, cull)
    var p = 0usize
    while p < pixels {
        if depth[p] < 1.0 {
            shade_pixel(gbuffer[p * 11usize..p * 11usize + 11usize], lights, eye, ambient, color[p * 3usize..p * 3usize + 3usize])
        } else {
            color[p * 3usize] = 0.0
            color[p * 3usize + 1usize] = 0.0
            color[p * 3usize + 2usize] = 0.0
        }
        p += 1usize
    }
    ret ok
}

// ------------------------------------------------------------- clustered lights

fn axis_gap(v: f32, lo: f32, hi: f32) -> f32 {
    if v < lo { ret lo - v }
    if v > hi { ret v - hi }
    ret 0.0
}

// The view frustum as `nx * ny * nz` clusters -- uniform tiles in x and y,
// exponential slices in depth from `near` to `far` -- and every point light
// (`x y z radius`, view space) assigned to the clusters whose box its sphere
// reaches: `counts[c]` lights, listed at `lists[c * max_per ..]`. Cluster
// `(i, j, k)` is index `(k * ny + j) * nx + i`, tile `j = 0` at the bottom.
fn clustered_lights(tan_x: f32, tan_y: f32, near: f32, far: f32, nx: usize, ny: usize, nz: usize, lights: []const f32, max_per: usize, counts: []u32, lists: []u32) -> err {
    let clusters = nx * ny * nz
    if nx == 0usize || ny == 0usize || nz == 0usize || !(near > 0.0) || !(far > near) { ret Invalid }
    if lights.len % 4usize != 0usize || counts.len < clusters || lists.len < clusters * max_per { ret Invalid }
    let ratio = far / near
    var k = 0usize
    while k < nz {
        let d0 = near * math.pow[f32](ratio, f32(k) / f32(nz))
        let d1 = near * math.pow[f32](ratio, f32(k + 1usize) / f32(nz))
        var j = 0usize
        while j < ny {
            let y0 = (f32(j) * 2.0 / f32(ny) - 1.0) * tan_y
            let y1 = (f32(j + 1usize) * 2.0 / f32(ny) - 1.0) * tan_y
            var i = 0usize
            while i < nx {
                let x0 = (f32(i) * 2.0 / f32(nx) - 1.0) * tan_x
                let x1 = (f32(i + 1usize) * 2.0 / f32(nx) - 1.0) * tan_x
                let min_x = math.min[f32](x0 * d0, x0 * d1)
                let max_x = math.max[f32](x1 * d0, x1 * d1)
                let min_y = math.min[f32](y0 * d0, y0 * d1)
                let max_y = math.max[f32](y1 * d0, y1 * d1)
                let min_z = 0.0 - d1
                let max_z = 0.0 - d0
                let c = (k * ny + j) * nx + i
                var n = 0usize
                var l = 0usize
                while l < lights.len {
                    let gx = axis_gap(lights[l], min_x, max_x)
                    let gy = axis_gap(lights[l + 1usize], min_y, max_y)
                    let gz = axis_gap(lights[l + 2usize], min_z, max_z)
                    let radius = lights[l + 3usize]
                    if gx * gx + gy * gy + gz * gz <= radius * radius {
                        if n >= max_per { ret TooLarge }
                        lists[c * max_per + n] = u32(l / 4usize)
                        n += 1usize
                    }
                    l += 4usize
                }
                counts[c] = u32(n)
                i += 1usize
            }
            j += 1usize
        }
        k += 1usize
    }
    ret ok
}

// ------------------------------------------------------------- cascaded shadows

// Cascaded shadow maps: the view range split by the practical scheme (`lambda`
// between logarithmic and uniform) into `splits.len - 1` cascades, each with the
// orthographic light matrix (`16` floats at `matrices[c * 16 ..]`) that bounds its
// frustum slice in light space. The camera is `cam_to_world` with the half-angle
// tangents; the light is a direction; the answer's `splits[0]` is `near`.
fn shadow_cascades(near: f32, far: f32, lambda: f32, cam_to_world: []const f32, tan_x: f32, tan_y: f32, light_dir: []const f32, splits: []f32, matrices: []f32) -> err {
    if splits.len < 2usize || !(near > 0.0) || !(far > near) || cam_to_world.len < 16usize || light_dir.len < 3usize { ret Invalid }
    let n = splits.len - 1usize
    if matrices.len < 16usize * n { ret Invalid }
    splits[0] = near
    var i = 1usize
    while i <= n {
        let t = f32(i) / f32(n)
        let uniform = near + (far - near) * t
        let logarithmic = near * math.pow[f32](far / near, t)
        splits[i] = lambda * logarithmic + (1.0 - lambda) * uniform
        i += 1usize
    }
    let (fx, fy, fz) = v3_norm(light_dir[0], light_dir[1], light_dir[2])
    var ux: f32 = 0.0
    var uy: f32 = 1.0
    if math.abs[f32](fy) > 0.99 {
        ux = 1.0
        uy = 0.0
    }
    // right = up x forward, up' = forward x right; the light looks along `forward`.
    let (rx, ry, rz) = v3_norm(uy * fz, 0.0 - ux * fz, ux * fy - uy * fx)
    let px = fy * rz - fz * ry
    let py = fz * rx - fx * rz
    let pz = fx * ry - fy * rx
    var view: [16]f32 = zero
    view[0] = rx
    view[1] = ry
    view[2] = rz
    view[4] = px
    view[5] = py
    view[6] = pz
    view[8] = 0.0 - fx
    view[9] = 0.0 - fy
    view[10] = 0.0 - fz
    view[15] = 1.0
    var c = 0usize
    while c < n {
        var min_x: f32 = 3.4e38
        var min_y: f32 = 3.4e38
        var min_z: f32 = 3.4e38
        var max_x: f32 = -3.4e38
        var max_y: f32 = -3.4e38
        var max_z: f32 = -3.4e38
        var corner = 0usize
        while corner < 8usize {
            var d = splits[c]
            if corner >= 4usize { d = splits[c + 1usize] }
            var sx: f32 = -1.0
            if (corner & 1usize) == 1usize { sx = 1.0 }
            var sy: f32 = -1.0
            if (corner & 2usize) == 2usize { sy = 1.0 }
            let (wx, wy, wz, ww) = mat4_apply(cam_to_world, sx * d * tan_x, sy * d * tan_y, 0.0 - d)
            let (lx, ly, lz, lw) = mat4_apply(view[0..], wx, wy, wz)
            if lx < min_x { min_x = lx }
            if ly < min_y { min_y = ly }
            if lz < min_z { min_z = lz }
            if lx > max_x { max_x = lx }
            if ly > max_y { max_y = ly }
            if lz > max_z { max_z = lz }
            corner += 1usize
        }
        var ortho: [16]f32 = zero
        ortho[0] = 2.0 / (max_x - min_x)
        ortho[3] = 0.0 - (max_x + min_x) / (max_x - min_x)
        ortho[5] = 2.0 / (max_y - min_y)
        ortho[7] = 0.0 - (max_y + min_y) / (max_y - min_y)
        ortho[10] = -2.0 / (max_z - min_z)
        ortho[11] = (max_z + min_z) / (max_z - min_z)
        ortho[15] = 1.0
        try mat4_mul(ortho[0..], view[0..], matrices[c * 16usize..c * 16usize + 16usize])
        c += 1usize
    }
    ret ok
}

// Percentage-closer filtering: each fragment (`u v z` in shadow-map space, `z`
// the light-space depth) is compared, less `bias`, against the `taps x taps`
// texels around its own, and the answer is the lit fraction.
fn shadow_pcf(map: []const f32, map_width: usize, map_height: usize, frags: []const f32, taps: usize, bias: f32, out: []f32) -> err {
    if map_width == 0usize || map_height == 0usize || taps == 0usize || taps % 2usize == 0usize { ret Invalid }
    if map.len < map_width * map_height || frags.len % 3usize != 0usize || out.len < frags.len / 3usize { ret Invalid }
    let half = taps / 2usize
    var f = 0usize
    while f < frags.len {
        let tx = clamp_index(frags[f] * f32(map_width), map_width)
        let ty = clamp_index(frags[f + 1usize] * f32(map_height), map_height)
        let z = frags[f + 2usize] - bias
        var lit = 0usize
        var dy = 0usize
        while dy < taps {
            var dx = 0usize
            while dx < taps {
                var sx = tx + dx
                var sy = ty + dy
                if sx < half { sx = 0usize } else { sx = sx - half }
                if sy < half { sy = 0usize } else { sy = sy - half }
                if sx >= map_width { sx = map_width - 1usize }
                if sy >= map_height { sy = map_height - 1usize }
                if z <= map[sy * map_width + sx] { lit += 1usize }
                dx += 1usize
            }
            dy += 1usize
        }
        out[f / 3usize] = f32(lit) / f32(taps * taps)
        f += 3usize
    }
    ret ok
}

// ------------------------------------------------------------ screen-space passes

// Screen-space ambient occlusion over view-space position and normal buffers
// (three floats per pixel each): every pixel's hemisphere `kernel` (`x y z` per
// sample, z along the normal) is rotated by the 4x4 `noise` tile (`x y z` per
// entry), offset by `radius`, projected through `proj`, and counted as occluding
// when the surface there is nearer than the sample by more than `bias`, weighted
// by the range check; a 4x4 box blur of the raw answer (kept in `scratch`) is `ao`.
fn ssao(positions: []const f32, normals: []const f32, width: usize, height: usize, kernel: []const f32, noise: []const f32, proj: []const f32, radius: f32, bias: f32, ao: []f32, scratch: []f32) -> err {
    let pixels = width * height
    if width == 0usize || height == 0usize || positions.len < pixels * 3usize || normals.len < pixels * 3usize { ret Invalid }
    if kernel.len == 0usize || kernel.len % 3usize != 0usize || noise.len < 48usize || proj.len < 16usize || ao.len < pixels || scratch.len < pixels { ret Invalid }
    let samples = kernel.len / 3usize
    var y = 0usize
    while y < height {
        var x = 0usize
        while x < width {
            let p = y * width + x
            let px = positions[p * 3usize]
            let py = positions[p * 3usize + 1usize]
            let pz = positions[p * 3usize + 2usize]
            let (nx, ny, nz) = v3_norm(normals[p * 3usize], normals[p * 3usize + 1usize], normals[p * 3usize + 2usize])
            let ni = ((y % 4usize) * 4usize + (x % 4usize)) * 3usize
            let rx = noise[ni]
            let ry = noise[ni + 1usize]
            let rz = noise[ni + 2usize]
            let rn = rx * nx + ry * ny + rz * nz
            let (t0, t1, t2) = v3_norm(rx - nx * rn, ry - ny * rn, rz - nz * rn)
            var tx = t0
            var ty = t1
            var tz = t2
            if tx == 0.0 && ty == 0.0 && tz == 0.0 {
                let (ax, ay, az) = v3_norm(1.0 - nx * nx, 0.0 - nx * ny, 0.0 - nx * nz)
                tx = ax
                ty = ay
                tz = az
            }
            let bx = ny * tz - nz * ty
            let by = nz * tx - nx * tz
            let bz = nx * ty - ny * tx
            var occlusion: f32 = 0.0
            var s = 0usize
            while s < samples {
                let kx = kernel[s * 3usize]
                let ky = kernel[s * 3usize + 1usize]
                let kz = kernel[s * 3usize + 2usize]
                let sx = px + (tx * kx + bx * ky + nx * kz) * radius
                let sy = py + (ty * kx + by * ky + ny * kz) * radius
                let sz = pz + (tz * kx + bz * ky + nz * kz) * radius
                let (cx, cy, cz, cw) = mat4_apply(proj, sx, sy, sz)
                if cw != 0.0 {
                    let (fx, fy) = screen_of(cx, cy, cw, width, height)
                    let q = clamp_index(fy, height) * width + clamp_index(fx, width)
                    let sample_depth = positions[q * 3usize + 2usize]
                    let gap = math.abs[f32](pz - sample_depth)
                    var range: f32 = 1.0
                    if gap > 0.0 { range = smoothstep01(radius / gap) }
                    if sample_depth >= sz + bias { occlusion = occlusion + range }
                }
                s += 1usize
            }
            scratch[p] = 1.0 - occlusion / f32(samples)
            x += 1usize
        }
        y += 1usize
    }
    y = 0usize
    while y < height {
        var x = 0usize
        while x < width {
            var sum: f32 = 0.0
            var dy = 0usize
            while dy < 4usize {
                var dx = 0usize
                while dx < 4usize {
                    var sx = x + dx
                    var sy = y + dy
                    if sx < 2usize { sx = 0usize } else { sx = sx - 2usize }
                    if sy < 2usize { sy = 0usize } else { sy = sy - 2usize }
                    if sx >= width { sx = width - 1usize }
                    if sy >= height { sy = height - 1usize }
                    sum = sum + scratch[sy * width + sx]
                    dx += 1usize
                }
                dy += 1usize
            }
            ao[y * width + x] = sum / 16.0
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// Screen-space reflections over the same view-space position and normal buffers:
// the eye ray reflects at each pixel and marches `max_steps` steps of `step` in
// view space, projecting through `proj`; a march point behind the surface at its
// pixel by less than `thickness` is a hit, refined by `refine` bisections. The
// answers are the hit's pixel coordinates (`u v`, in pixels) and a 0/1 mask.
fn ssr(positions: []const f32, normals: []const f32, width: usize, height: usize, proj: []const f32, step: f32, max_steps: usize, thickness: f32, refine: usize, hit_uv: []f32, mask: []f32) -> err {
    let pixels = width * height
    if width == 0usize || height == 0usize || positions.len < pixels * 3usize || normals.len < pixels * 3usize { ret Invalid }
    if proj.len < 16usize || !(step > 0.0) || hit_uv.len < pixels * 2usize || mask.len < pixels { ret Invalid }
    var p = 0usize
    while p < pixels {
        let px = positions[p * 3usize]
        let py = positions[p * 3usize + 1usize]
        let pz = positions[p * 3usize + 2usize]
        let (nx, ny, nz) = v3_norm(normals[p * 3usize], normals[p * 3usize + 1usize], normals[p * 3usize + 2usize])
        let (vx, vy, vz) = v3_norm(px, py, pz)
        let vn = vx * nx + vy * ny + vz * nz
        let rx = vx - 2.0 * vn * nx
        let ry = vy - 2.0 * vn * ny
        let rz = vz - 2.0 * vn * nz
        var lo: f32 = 0.0
        var hi: f32 = 0.0
        var found = false
        var stop = false
        var i = 1usize
        while i <= max_steps && !stop {
            let t = step * f32(i)
            let (behind, inside) = ssr_probe(positions, width, height, proj, px + rx * t, py + ry * t, pz + rz * t, thickness)
            if !inside { stop = true }
            if inside && behind {
                found = true
                stop = true
                hi = t
                lo = t - step
            }
            i += 1usize
        }
        var hx: f32 = 0.0
        var hy: f32 = 0.0
        if found {
            var r = 0usize
            while r < refine {
                let mid = (lo + hi) * 0.5
                let (behind, inside) = ssr_probe(positions, width, height, proj, px + rx * mid, py + ry * mid, pz + rz * mid, thickness)
                if inside && behind { hi = mid } else { lo = mid }
                r += 1usize
            }
            let (cx, cy, cz, cw) = mat4_apply(proj, px + rx * hi, py + ry * hi, pz + rz * hi)
            let (fx, fy) = screen_of(cx, cy, cw, width, height)
            hx = fx
            hy = fy
        }
        hit_uv[p * 2usize] = hx
        hit_uv[p * 2usize + 1usize] = hy
        if found { mask[p] = 1.0 } else { mask[p] = 0.0 }
        p += 1usize
    }
    ret ok
}

// A view-space march point against the surface at its pixel: (behind it within
// `thickness`, inside the image and in front of the eye).
fn ssr_probe(positions: []const f32, width: usize, height: usize, proj: []const f32, x: f32, y: f32, z: f32, thickness: f32) -> (bool, bool) {
    let (cx, cy, cz, cw) = mat4_apply(proj, x, y, z)
    if !(cw > 0.0) { ret (false, false) }
    let (fx, fy) = screen_of(cx, cy, cw, width, height)
    if !(fx >= 0.0) || !(fy >= 0.0) || fx >= f32(width) || fy >= f32(height) { ret (false, false) }
    let scene_z = positions[(usize(fy) * width + usize(fx)) * 3usize + 2usize]
    let gap = scene_z - z
    ret (gap > 0.0 && gap < thickness, true)
}

// Temporal anti-aliasing: each pixel's NDC position (its depth from `depth`) goes
// back to the world through `inv_view_proj` and forward through `prev_view_proj`
// to the previous frame, whose `history` is fetched bilinearly, clamped to the
// colour box of the current 3x3 neighbourhood and blended: `alpha` of the current
// frame. A reprojection off the image, or behind the previous eye, keeps the
// current colour. RGB, three floats per pixel.
fn taa(current: []const f32, history: []const f32, depth: []const f32, width: usize, height: usize, inv_view_proj: []const f32, prev_view_proj: []const f32, alpha: f32, out: []f32) -> err {
    let pixels = width * height
    if width == 0usize || height == 0usize || current.len < pixels * 3usize || history.len < pixels * 3usize || depth.len < pixels { ret Invalid }
    if inv_view_proj.len < 16usize || prev_view_proj.len < 16usize || out.len < pixels * 3usize { ret Invalid }
    var y = 0usize
    while y < height {
        var x = 0usize
        while x < width {
            let p = y * width + x
            let ndc_x = (f32(x) + 0.5) / f32(width) * 2.0 - 1.0
            let ndc_y = 1.0 - (f32(y) + 0.5) / f32(height) * 2.0
            let (wx, wy, wz, ww) = mat4_apply(inv_view_proj, ndc_x, ndc_y, depth[p])
            var use_history = ww != 0.0
            var fx: f32 = 0.0
            var fy: f32 = 0.0
            if use_history {
                let (cx, cy, cz, cw) = mat4_apply(prev_view_proj, wx / ww, wy / ww, wz / ww)
                if cw > 0.0 {
                    let (sx, sy) = screen_of(cx, cy, cw, width, height)
                    fx = sx
                    fy = sy
                    if !(fx >= 0.0) || !(fy >= 0.0) || fx > f32(width) || fy > f32(height) { use_history = false }
                } else {
                    use_history = false
                }
            }
            var c = 0usize
            while c < 3usize {
                let cur = current[p * 3usize + c]
                var value = cur
                if use_history {
                    var lo = cur
                    var hi = cur
                    var dy = 0usize
                    while dy < 3usize {
                        var dx = 0usize
                        while dx < 3usize {
                            var sx = x + dx
                            var sy = y + dy
                            if sx == 0usize { sx = 1usize }
                            if sy == 0usize { sy = 1usize }
                            sx = sx - 1usize
                            sy = sy - 1usize
                            if sx >= width { sx = width - 1usize }
                            if sy >= height { sy = height - 1usize }
                            let v = current[(sy * width + sx) * 3usize + c]
                            if v < lo { lo = v }
                            if v > hi { hi = v }
                            dx += 1usize
                        }
                        dy += 1usize
                    }
                    var h = bilinear(history, 3usize, width, height, fx, fy, c)
                    if h < lo { h = lo }
                    if h > hi { h = hi }
                    value = h * (1.0 - alpha) + cur * alpha
                }
                out[p * 3usize + c] = value
                c += 1usize
            }
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// --------------------------------------------------------------------- FXAA 3.11

fn luma_at(luma: []const f32, width: usize, height: usize, x: usize, y: usize, dx: usize, dy: usize) -> f32 {
    // `dx`, `dy` are offsets plus one: 0 is left/up, 1 here, 2 right/down.
    var sx = x + dx
    var sy = y + dy
    if sx == 0usize { sx = 1usize }
    if sy == 0usize { sy = 1usize }
    sx = sx - 1usize
    sy = sy - 1usize
    if sx >= width { sx = width - 1usize }
    if sy >= height { sy = height - 1usize }
    ret luma[sy * width + sx]
}

fn fxaa_quality_step(index: usize) -> f32 {
    if index == 0usize { ret 1.0 }
    if index == 1usize { ret 1.5 }
    if index == 2usize { ret 2.0 }
    if index == 3usize { ret 4.0 }
    ret 12.0
}

// FXAA 3.11, quality preset 12 (five edge-search steps of 1, 1.5, 2, 4, 12 texels),
// sub-pixel quality 0.75, edge threshold 0.166, minimum 0.0833: the luma of every
// pixel (Rec. 601 weights) is written into `luma`, then each pixel above the local
// contrast threshold finds its edge direction, searches both ways along the edge
// for its ends, and refetches the colour offset towards the edge, at least by the
// sub-pixel blend. The answer is the filtered RGB buffer; both are three floats
// per pixel with bilinear fetches at the half-texel search points.
fn fxaa(rgb: []const f32, width: usize, height: usize, luma: []f32, out: []f32) -> err {
    let pixels = width * height
    if width == 0usize || height == 0usize || rgb.len < pixels * 3usize || luma.len < pixels || out.len < pixels * 3usize { ret Invalid }
    var p = 0usize
    while p < pixels {
        luma[p] = rgb[p * 3usize] * 0.299 + rgb[p * 3usize + 1usize] * 0.587 + rgb[p * 3usize + 2usize] * 0.114
        p += 1usize
    }
    var y = 0usize
    while y < height {
        var x = 0usize
        while x < width {
            fxaa_pixel(rgb, luma, width, height, x, y, out[(y * width + x) * 3usize..(y * width + x) * 3usize + 3usize])
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

fn fxaa_pixel(rgb: []const f32, luma: []const f32, width: usize, height: usize, x: usize, y: usize, out: []f32) {
    let p = y * width + x
    let luma_m = luma[p]
    var luma_s = luma_at(luma, width, height, x, y, 1usize, 2usize)
    var luma_e = luma_at(luma, width, height, x, y, 2usize, 1usize)
    var luma_n = luma_at(luma, width, height, x, y, 1usize, 0usize)
    var luma_w = luma_at(luma, width, height, x, y, 0usize, 1usize)
    let max_sm = math.max[f32](luma_s, luma_m)
    let min_sm = math.min[f32](luma_s, luma_m)
    let max_esm = math.max[f32](luma_e, max_sm)
    let min_esm = math.min[f32](luma_e, min_sm)
    let max_wn = math.max[f32](luma_n, luma_w)
    let min_wn = math.min[f32](luma_n, luma_w)
    let range_max = math.max[f32](max_wn, max_esm)
    let range_min = math.min[f32](min_wn, min_esm)
    let range = range_max - range_min
    let threshold_min: f32 = 0.0833
    let range_max_clamped = math.max[f32](threshold_min, range_max * 0.166)
    if range < range_max_clamped {
        out[0] = rgb[p * 3usize]
        out[1] = rgb[p * 3usize + 1usize]
        out[2] = rgb[p * 3usize + 2usize]
        ret
    }
    let luma_nw = luma_at(luma, width, height, x, y, 0usize, 0usize)
    let luma_se = luma_at(luma, width, height, x, y, 2usize, 2usize)
    let luma_ne = luma_at(luma, width, height, x, y, 2usize, 0usize)
    let luma_sw = luma_at(luma, width, height, x, y, 0usize, 2usize)
    let luma_ns = luma_n + luma_s
    let luma_we = luma_w + luma_e
    let subpix_rcp_range = 1.0 / range
    let subpix_nswe = luma_ns + luma_we
    let edge_horz1 = -2.0 * luma_m + luma_ns
    let edge_vert1 = -2.0 * luma_m + luma_we
    let luma_nese = luma_ne + luma_se
    let luma_nwne = luma_nw + luma_ne
    let edge_horz2 = -2.0 * luma_e + luma_nese
    let edge_vert2 = -2.0 * luma_n + luma_nwne
    let luma_nwsw = luma_nw + luma_sw
    let luma_swse = luma_sw + luma_se
    let edge_horz4 = math.abs[f32](edge_horz1) * 2.0 + math.abs[f32](edge_horz2)
    let edge_vert4 = math.abs[f32](edge_vert1) * 2.0 + math.abs[f32](edge_vert2)
    let edge_horz3 = -2.0 * luma_w + luma_nwsw
    let edge_vert3 = -2.0 * luma_s + luma_swse
    let edge_horz = math.abs[f32](edge_horz3) + edge_horz4
    let edge_vert = math.abs[f32](edge_vert3) + edge_vert4
    let subpix_nwswnese = luma_nwsw + luma_nese
    let horz_span = edge_horz >= edge_vert
    var length_sign = 1.0 / f32(width)
    let subpix_a = subpix_nswe * 2.0 + subpix_nwswnese
    if !horz_span {
        luma_n = luma_w
        luma_s = luma_e
    }
    if horz_span { length_sign = 1.0 / f32(height) }
    let subpix_b = subpix_a * (1.0 / 12.0) - luma_m
    let gradient_n = luma_n - luma_m
    let gradient_s = luma_s - luma_m
    var luma_nn = luma_n + luma_m
    let luma_ss = luma_s + luma_m
    let pair_n = math.abs[f32](gradient_n) >= math.abs[f32](gradient_s)
    let gradient = math.max[f32](math.abs[f32](gradient_n), math.abs[f32](gradient_s))
    if pair_n { length_sign = 0.0 - length_sign }
    let subpix_c = saturate(math.abs[f32](subpix_b) * subpix_rcp_range)
    // Positions are in texture units, 0..1 across the image.
    let pos_m_x = (f32(x) + 0.5) / f32(width)
    let pos_m_y = (f32(y) + 0.5) / f32(height)
    var pos_b_x = pos_m_x
    var pos_b_y = pos_m_y
    var off_x: f32 = 0.0
    var off_y: f32 = 0.0
    if horz_span { off_x = 1.0 / f32(width) } else { off_y = 1.0 / f32(height) }
    if !horz_span { pos_b_x = pos_b_x + length_sign * 0.5 }
    if horz_span { pos_b_y = pos_b_y + length_sign * 0.5 }
    var pos_n_x = pos_b_x - off_x * fxaa_quality_step(0usize)
    var pos_n_y = pos_b_y - off_y * fxaa_quality_step(0usize)
    var pos_p_x = pos_b_x + off_x * fxaa_quality_step(0usize)
    var pos_p_y = pos_b_y + off_y * fxaa_quality_step(0usize)
    let subpix_d = -2.0 * subpix_c + 3.0
    var luma_end_n = fxaa_luma_tex(luma, width, height, pos_n_x, pos_n_y)
    let subpix_e = subpix_c * subpix_c
    var luma_end_p = fxaa_luma_tex(luma, width, height, pos_p_x, pos_p_y)
    if !pair_n { luma_nn = luma_ss }
    let gradient_scaled = gradient * 0.25
    let luma_mm = luma_m - luma_nn * 0.5
    let subpix_f = subpix_d * subpix_e
    let luma_m_lt_zero = luma_mm < 0.0
    luma_end_n = luma_end_n - luma_nn * 0.5
    luma_end_p = luma_end_p - luma_nn * 0.5
    var done_n = math.abs[f32](luma_end_n) >= gradient_scaled
    var done_p = math.abs[f32](luma_end_p) >= gradient_scaled
    if !done_n {
        pos_n_x = pos_n_x - off_x * fxaa_quality_step(1usize)
        pos_n_y = pos_n_y - off_y * fxaa_quality_step(1usize)
    }
    var done_np = !done_n || !done_p
    if !done_p {
        pos_p_x = pos_p_x + off_x * fxaa_quality_step(1usize)
        pos_p_y = pos_p_y + off_y * fxaa_quality_step(1usize)
    }
    var s = 2usize
    while s < 5usize && done_np {
        if !done_n { luma_end_n = fxaa_luma_tex(luma, width, height, pos_n_x, pos_n_y) - luma_nn * 0.5 }
        if !done_p { luma_end_p = fxaa_luma_tex(luma, width, height, pos_p_x, pos_p_y) - luma_nn * 0.5 }
        done_n = math.abs[f32](luma_end_n) >= gradient_scaled
        done_p = math.abs[f32](luma_end_p) >= gradient_scaled
        if !done_n {
            pos_n_x = pos_n_x - off_x * fxaa_quality_step(s)
            pos_n_y = pos_n_y - off_y * fxaa_quality_step(s)
        }
        done_np = !done_n || !done_p
        if !done_p {
            pos_p_x = pos_p_x + off_x * fxaa_quality_step(s)
            pos_p_y = pos_p_y + off_y * fxaa_quality_step(s)
        }
        s += 1usize
    }
    var dst_n = pos_m_x - pos_n_x
    var dst_p = pos_p_x - pos_m_x
    if !horz_span {
        dst_n = pos_m_y - pos_n_y
        dst_p = pos_p_y - pos_m_y
    }
    let good_span_n = (luma_end_n < 0.0) != luma_m_lt_zero
    let span_length = dst_p + dst_n
    let good_span_p = (luma_end_p < 0.0) != luma_m_lt_zero
    let span_length_rcp = 1.0 / span_length
    let direction_n = dst_n < dst_p
    let dst = math.min[f32](dst_n, dst_p)
    var good_span = good_span_p
    if direction_n { good_span = good_span_n }
    let subpix_g = subpix_f * subpix_f
    let pixel_offset = dst * (0.0 - span_length_rcp) + 0.5
    let subpix_h = subpix_g * 0.75
    var pixel_offset_good: f32 = 0.0
    if good_span { pixel_offset_good = pixel_offset }
    let pixel_offset_subpix = math.max[f32](pixel_offset_good, subpix_h)
    var final_x = pos_m_x
    var final_y = pos_m_y
    if !horz_span { final_x = final_x + pixel_offset_subpix * length_sign }
    if horz_span { final_y = final_y + pixel_offset_subpix * length_sign }
    var c = 0usize
    while c < 3usize {
        out[c] = bilinear(rgb, 3usize, width, height, final_x * f32(width), final_y * f32(height), c)
        c += 1usize
    }
}

fn fxaa_luma_tex(luma: []const f32, width: usize, height: usize, u: f32, v: f32) -> f32 {
    ret bilinear(luma, 1usize, width, height, u * f32(width), v * f32(height), 0usize)
}

// --------------------------------------------------------------- depth peeling

fn fill_floats(data: []f32, count: usize, v: f32) {
    var i = 0usize
    while i < count {
        data[i] = v
        i += 1usize
    }
}

// Order-independent transparency by depth peeling: `layers` passes over vertices
// of `x y z w r g b a`, each pass rasterising only fragments strictly behind the
// previous layer's depth and keeping the nearest, composited front to back into
// `out` (premultiplied RGBA, four floats per pixel). `depth_a`, `depth_b` and
// `layer_color` (four floats per pixel) are the passes' scratch.
fn depth_peel(tris: []const f32, width: usize, height: usize, layers: usize, depth_a: []f32, depth_b: []f32, layer_color: []f32, out: []f32) -> err {
    let pixels = width * height
    if width == 0usize || height == 0usize || depth_a.len < pixels || depth_b.len < pixels || layer_color.len < pixels * 4usize || out.len < pixels * 4usize { ret Invalid }
    fill_floats(out, pixels * 4usize, 0.0)
    fill_floats(depth_a, pixels, -2.0)
    var pass = 0usize
    while pass < layers {
        fill_floats(depth_b, pixels, 1.0)
        fill_floats(layer_color, pixels * 4usize, 0.0)
        try raster_core(tris, 8usize, width, height, depth_b, layer_color, depth_a, false)
        var p = 0usize
        while p < pixels {
            if depth_b[p] < 1.0 {
                let a = layer_color[p * 4usize + 3usize]
                let keep = 1.0 - out[p * 4usize + 3usize]
                out[p * 4usize] = out[p * 4usize] + keep * a * layer_color[p * 4usize]
                out[p * 4usize + 1usize] = out[p * 4usize + 1usize] + keep * a * layer_color[p * 4usize + 1usize]
                out[p * 4usize + 2usize] = out[p * 4usize + 2usize] + keep * a * layer_color[p * 4usize + 2usize]
                out[p * 4usize + 3usize] = out[p * 4usize + 3usize] + keep * a
            }
            depth_a[p] = depth_b[p]
            p += 1usize
        }
        pass += 1usize
    }
    ret ok
}

// ----------------------------------------------------------------- ray marching

// Sphere tracing of a signed distance field: a ray per pixel from `eye` (looking
// down -z with the half-angle tangents) advances by the field's distance until
// it is under `epsilon` (a hit) or past `max_dist` or `max_steps` (a miss).
// `hits` is the hit distance or -1; `normals` (three per pixel) the central
// difference gradient at the hit, zero at a miss.
fn sdf_raymarch[Ctx: type](ctx: *Ctx, sdf: fn(*Ctx, f32, f32, f32) -> f32, width: usize, height: usize, eye: []const f32, tan_x: f32, tan_y: f32, max_steps: usize, epsilon: f32, max_dist: f32, hits: []f32, normals: []f32) -> err {
    let pixels = width * height
    if width == 0usize || height == 0usize || eye.len < 3usize || !(epsilon > 0.0) || hits.len < pixels || normals.len < pixels * 3usize { ret Invalid }
    var y = 0usize
    while y < height {
        var x = 0usize
        while x < width {
            let p = y * width + x
            let (dx, dy, dz) = v3_norm(((f32(x) + 0.5) / f32(width) * 2.0 - 1.0) * tan_x, (1.0 - (f32(y) + 0.5) / f32(height) * 2.0) * tan_y, -1.0)
            var t: f32 = 0.0
            var hit = false
            var stop = false
            var s = 0usize
            while s < max_steps && !stop {
                let d = sdf(ctx, eye[0] + dx * t, eye[1] + dy * t, eye[2] + dz * t)
                if d < epsilon {
                    hit = true
                    stop = true
                } else {
                    t = t + d
                    if t > max_dist { stop = true }
                }
                s += 1usize
            }
            hits[p] = -1.0
            normals[p * 3usize] = 0.0
            normals[p * 3usize + 1usize] = 0.0
            normals[p * 3usize + 2usize] = 0.0
            if hit {
                hits[p] = t
                let hx = eye[0] + dx * t
                let hy = eye[1] + dy * t
                let hz = eye[2] + dz * t
                let gx = sdf(ctx, hx + epsilon, hy, hz) - sdf(ctx, hx - epsilon, hy, hz)
                let gy = sdf(ctx, hx, hy + epsilon, hz) - sdf(ctx, hx, hy - epsilon, hz)
                let gz = sdf(ctx, hx, hy, hz + epsilon) - sdf(ctx, hx, hy, hz - epsilon)
                let (nx, ny, nz) = v3_norm(gx, gy, gz)
                normals[p * 3usize] = nx
                normals[p * 3usize + 1usize] = ny
                normals[p * 3usize + 2usize] = nz
            }
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// Volumetric fog: the eye ray to each pixel's view-space position is marched in
// `steps` equal segments; the density at a point is `density * exp(-falloff * y)`
// (an exponential height fog), the in-scattering from the point `light` (`x y z r
// g b`, view space) is isotropic (`albedo / 4pi`) with `1 / (1 + d^2)` falloff, and
// Beer-Lambert transmittance accumulates along the ray. The answers are the
// scattered colour (three per pixel) and the transmittance to the surface.
// ponytail: one march per pixel rather than a froxel volume, and no shadowing
// of the light; a froxel grid with a shadow test is the upgrade.
fn volumetric_fog(positions: []const f32, width: usize, height: usize, steps: usize, density: f32, falloff: f32, light: []const f32, albedo: f32, fog: []f32, transmittance: []f32) -> err {
    let pixels = width * height
    if width == 0usize || height == 0usize || steps == 0usize || positions.len < pixels * 3usize || light.len < 6usize { ret Invalid }
    if fog.len < pixels * 3usize || transmittance.len < pixels { ret Invalid }
    let inv_4pi: f32 = 0.079577472
    var p = 0usize
    while p < pixels {
        let px = positions[p * 3usize]
        let py = positions[p * 3usize + 1usize]
        let pz = positions[p * 3usize + 2usize]
        let dist = math.sqrt[f32](px * px + py * py + pz * pz)
        var tr: f32 = 1.0
        var fr: f32 = 0.0
        var fg: f32 = 0.0
        var fb: f32 = 0.0
        if dist > 0.0 {
            let dt = dist / f32(steps)
            var s = 0usize
            while s < steps {
                let t = (f32(s) + 0.5) * dt
                let qx = px / dist * t
                let qy = py / dist * t
                let qz = pz / dist * t
                let rho = density * math.exp[f32](0.0 - falloff * qy)
                let lx = light[0] - qx
                let ly = light[1] - qy
                let lz = light[2] - qz
                let attenuation = 1.0 / (1.0 + lx * lx + ly * ly + lz * lz)
                let scatter = tr * albedo * inv_4pi * rho * attenuation * dt
                fr = fr + scatter * light[3]
                fg = fg + scatter * light[4]
                fb = fb + scatter * light[5]
                tr = tr * math.exp[f32](0.0 - rho * dt)
                s += 1usize
            }
        }
        fog[p * 3usize] = fr
        fog[p * 3usize + 1usize] = fg
        fog[p * 3usize + 2usize] = fb
        transmittance[p] = tr
        p += 1usize
    }
    ret ok
}
