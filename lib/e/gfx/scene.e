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
type Scene = struct { live: bool, generation: u32, storage: []u8, has_storage: bool, arena: mem.Arena, commands: []Command, count: usize }
type FontEntry = struct { id: shape.FontId, data: []const u8, upem: f32, loca: usize, glyf: usize, glyf_len: usize, long_loca: bool, glyph_count: usize }
type Edge = struct { x0: f32, y0: f32, x1: f32, y1: f32 }
type Floats = struct { data: []f32, len: usize }
// The state a Save pushes: the transform, the scissor, the mask in use and whether
// this entry opened an opacity layer.
type DrawState = struct { transform: geometry.Transform, scissor: geometry.Rect, mask: usize, has_mask: bool, layer: usize, opens_layer: bool, opacity: f32 }
type RendererState = struct {
    arena: *mem.Arena,
    device: *gpu.Device,
    queue: *gpu.Queue,
    scenes: []Scene,
    textures: []Texture,
    fonts: [16]FontEntry,
    font_count: usize,
    edges: []Edge,
    edge_count: usize,
    // The canvases: layer 0 is the frame, the rest opacity layers; `width * height`
    // premultiplied RGBA floats each, remade when a frame is larger than the last.
    canvases: [4]Floats,
    masks: [8]Floats,
    acc: []f32,
    coverage: []f32,
    pixels: []u32,
    width: usize,
    height: usize,
    closed: bool,
}
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
    if !scene.live || scene.generation != id.generation { ret (0usize, Invalid) }
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

// The coverage of the accumulated edges, row by row, into `out` (`width * height`).
fn resolve_coverage(s: *RendererState, out: []f32) {
    let stride = s.width + 2usize
    var y = 0usize
    while y < s.height {
        var sum: f32 = 0.0
        var x = 0usize
        while x < s.width {
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

fn rasterize_edges(s: *RendererState, coverage: []f32) {
    clear_floats(s.acc, (s.width + 2usize) * s.height)
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
    let (x0, y0, x1, y1) = scissor_bounds(s, state.scissor)
    var y = y0
    while y < y1 {
        var x = x0
        while x < x1 {
            let index = y * s.width + x
            var c = coverage[index]
            if state.has_mask { c = c * s.masks[state.mask].data[index] }
            if c > 0.0 {
                let color = brush_at(brush, inverse, f32(x) + 0.5, f32(y) + 0.5)
                blend_pixel(canvas, index * 4usize, color, c)
            }
            x += 1usize
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
fn merge_layer(s: *RendererState, from: usize, into: usize, opacity: f32) {
    let src = s.canvases[from].data
    let dst = s.canvases[into].data
    let count = s.width * s.height
    var i = 0usize
    while i < count {
        let at = i * 4usize
        let a = src[at + 3usize] * opacity
        let keep = 1.0 - a
        dst[at] = src[at] * opacity + dst[at] * keep
        dst[at + 1usize] = src[at + 1usize] * opacity + dst[at + 1usize] * keep
        dst[at + 2usize] = src[at + 2usize] * opacity + dst[at + 2usize] * keep
        dst[at + 3usize] = a + dst[at + 3usize] * keep
        i += 1usize
    }
}

fn run_commands(s: *RendererState, scene: *const Scene, coverage: []f32) -> err {
    var states: [32]DrawState = zero
    var depth = 0usize
    var current: DrawState = zero
    current.transform = geometry.transform_identity()
    current.scissor = geometry.Rect { x: 0.0, y: 0.0, width: f32(s.width), height: f32(s.height) }
    current.opacity = 1.0
    var mask_count = 0usize
    var layer_count = 1usize
    var i = 0usize
    while i < scene.count {
        let command = scene.commands[i]
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
                merge_layer(s, current.layer, states[depth].layer, current.opacity)
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
            let (verbs, points) = rect_path(fill.rect)
            var f = fill_flattener(s, current.transform)
            try flatten(&f, geometry.Path { verbs: verbs[0..], points: points[0..] })
            rasterize_edges(s, coverage)
            paint_coverage(s, current, coverage, &fill.brush)
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
            clear_floats(s.canvases[layer_count].data, s.width * s.height * 4usize)
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
    let count = s.width * s.height
    var i = 0usize
    while i < count {
        var c = coverage[i]
        if current.has_mask { c = c * s.masks[current.mask].data[i] }
        mask[i] = c
        i += 1usize
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
    let (s, state_error) = renderer_state(r)
    if state_error != ok { ret state_error }
    let (slot, slot_error) = scene_slot(s, scene)
    if slot_error != ok { ret slot_error }
    let target_state = mem.cast[*TargetState](render_target.state)
    if mem.address_of(target_state) == 0usize { ret Invalid }
    if !(size.width >= 1.0) || !(size.height >= 1.0) || !finite(size.width) || !finite(size.height) { ret Invalid }
    let (frame, acquire_error) = gpu.acquire(target_state.target)
    if acquire_error != ok { ret from_gpu(acquire_error) }
    var width = usize(math.ceil[f32](size.width))
    var height = usize(math.ceil[f32](size.height))
    if width > usize(frame.image.width) { width = usize(frame.image.width) }
    if height > usize(frame.image.height) { height = usize(frame.image.height) }
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
    clear_floats(s.canvases[0usize].data, width * height * 4usize)
    s.edge_count = 0usize
    let run_error = run_commands(s, &s.scenes[slot], coverage)
    if run_error != ok { ret run_error }
    // The canvas as packed pixels in the frame's channel order.
    let canvas = s.canvases[0usize].data
    var i = 0usize
    while i < width * height {
        let at = i * 4usize
        let r8 = channel_byte(canvas[at])
        let g8 = channel_byte(canvas[at + 1usize])
        let b8 = channel_byte(canvas[at + 2usize])
        let a8 = channel_byte(canvas[at + 3usize])
        if frame.image.format == .Bgra8 {
            s.pixels[i] = b8 | (g8 << 8u32) | (r8 << 16u32) | (a8 << 24u32)
        } else {
            s.pixels[i] = r8 | (g8 << 8u32) | (b8 << 16u32) | (a8 << 24u32)
        }
        i += 1usize
    }
    let write_error = gpu.write_image(s.queue, frame.image, 0u32, 0u32, u32(width), u32(height), s.pixels[0usize..width * height])
    if write_error != ok { ret from_gpu(write_error) }
    let (shown, present_error) = gpu.present(s.queue, target_state.target, frame)
    if present_error != ok { ret from_gpu(present_error) }
    ret ok
}

fn channel_byte(v: f32) -> u32 {
    var c = v
    if !(c >= 0.0) { c = 0.0 }
    if c > 1.0 { c = 1.0 }
    ret u32(math.floor[f32](c * 255.0 + 0.5))
}
