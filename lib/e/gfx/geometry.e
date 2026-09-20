// Plain 2D geometry in logical pixels: points, sizes, rectangles, rounded rectangles,
// insets, affine transforms and paths, with nothing that renders. Values are the
// caller's to keep finite; a rectangle or size is never given a negative dimension
// here -- `rect` clamps one to zero, and an intersection with nothing in it is a
// zero-sized rectangle at the corner the two would have met.
//
// A transform is the 2x3 affine matrix `[m00 m01 m02; m10 m11 m12]` acting on column
// vectors: `x' = m00*x + m01*y + m02`. `transform_multiply(a, b)` is the matrix product
// `a * b`, the transform that applies `b` first and `a` after. `transform_rotate` turns
// counter-clockwise in a y-up frame, which is clockwise on a y-down screen.
//
// A path is built into caller-bounded storage: `path_builder` takes the arena once for
// `max_verbs` verbs and `max_points` points, every `*_to` after that allocates nothing
// and answers `TooLarge` when the bound is reached, and `finish` views what was built.
// `contains` takes the left and top edges and leaves the right and bottom, so two
// rectangles sharing an edge never both contain a point on it.

use e.math
use e.mem

type Point = struct { x: f32, y: f32 }
type Size = struct { width: f32, height: f32 }
type Rect = struct { x: f32, y: f32, width: f32, height: f32 }
type Insets = struct { left: f32, top: f32, right: f32, bottom: f32 }
type Radius = struct { x: f32, y: f32 }
type RRect = struct { rect: Rect, top_left: Radius, top_right: Radius, bottom_right: Radius, bottom_left: Radius }
type Transform = struct { m00: f32, m01: f32, m02: f32, m10: f32, m11: f32, m12: f32 }
type PathVerb = enum u8 { Move, Line, Quad, Cubic, Close }
type Path = struct { verbs: []const PathVerb, points: []const Point }
type PathBuilder = struct { state: *void }
error Invalid
error TooLarge

type BuilderState = struct { verbs: []PathVerb, points: []Point, verb_count: usize, point_count: usize, open: bool }

fn rect(x: f32, y: f32, width: f32, height: f32) -> Rect {
    var w = width
    var h = height
    if w < 0.0 { w = 0.0 }
    if h < 0.0 { h = 0.0 }
    ret Rect { x: x, y: y, width: w, height: h }
}

fn contains(r: Rect, p: Point) -> bool {
    ret p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height
}

fn intersect(a: Rect, b: Rect) -> Rect {
    var left = a.x
    if b.x > left { left = b.x }
    var top = a.y
    if b.y > top { top = b.y }
    var right = a.x + a.width
    if b.x + b.width < right { right = b.x + b.width }
    var bottom = a.y + a.height
    if b.y + b.height < bottom { bottom = b.y + b.height }
    ret rect(left, top, right - left, bottom - top)
}

fn union_rect(a: Rect, b: Rect) -> Rect {
    if a.width <= 0.0 || a.height <= 0.0 { ret b }
    if b.width <= 0.0 || b.height <= 0.0 { ret a }
    var left = a.x
    if b.x < left { left = b.x }
    var top = a.y
    if b.y < top { top = b.y }
    var right = a.x + a.width
    if b.x + b.width > right { right = b.x + b.width }
    var bottom = a.y + a.height
    if b.y + b.height > bottom { bottom = b.y + b.height }
    ret rect(left, top, right - left, bottom - top)
}

fn transform_identity() -> Transform {
    ret Transform { m00: 1.0, m01: 0.0, m02: 0.0, m10: 0.0, m11: 1.0, m12: 0.0 }
}

fn transform_translate(x: f32, y: f32) -> Transform {
    ret Transform { m00: 1.0, m01: 0.0, m02: x, m10: 0.0, m11: 1.0, m12: y }
}

fn transform_scale(x: f32, y: f32) -> Transform {
    ret Transform { m00: x, m01: 0.0, m02: 0.0, m10: 0.0, m11: y, m12: 0.0 }
}

fn transform_rotate(radians: f32) -> Transform {
    let c = math.cos[f32](radians)
    let s = math.sin[f32](radians)
    ret Transform { m00: c, m01: 0.0 - s, m02: 0.0, m10: s, m11: c, m12: 0.0 }
}

fn transform_multiply(a: Transform, b: Transform) -> Transform {
    ret Transform {
        m00: a.m00 * b.m00 + a.m01 * b.m10,
        m01: a.m00 * b.m01 + a.m01 * b.m11,
        m02: a.m00 * b.m02 + a.m01 * b.m12 + a.m02,
        m10: a.m10 * b.m00 + a.m11 * b.m10,
        m11: a.m10 * b.m01 + a.m11 * b.m11,
        m12: a.m10 * b.m02 + a.m11 * b.m12 + a.m12,
    }
}

fn transform_point(t: Transform, p: Point) -> Point {
    ret Point { x: t.m00 * p.x + t.m01 * p.y + t.m02, y: t.m10 * p.x + t.m11 * p.y + t.m12 }
}

fn path_builder(a: *mem.Arena, max_verbs: usize, max_points: usize) -> (PathBuilder, err) {
    if max_verbs == 0usize || max_points == 0usize { ret (zero, Invalid) }
    let (states, state_error) = mem.alloc[BuilderState](a, 1usize)
    if state_error != ok { ret (zero, state_error) }
    let (verbs, verbs_error) = mem.alloc[PathVerb](a, max_verbs)
    if verbs_error != ok { ret (zero, verbs_error) }
    let (points, points_error) = mem.alloc[Point](a, max_points)
    if points_error != ok { ret (zero, points_error) }
    states[0usize] = BuilderState { verbs: verbs, points: points, verb_count: 0usize, point_count: 0usize, open: false }
    ret (PathBuilder { state: mem.cast[*void](&states[0usize]) }, ok)
}

// Appends one verb and its points, or answers TooLarge with nothing changed.
fn append(s: *BuilderState, verb: PathVerb, count: usize, first: Point, second: Point, third: Point) -> err {
    if s.verb_count >= s.verbs.len || s.point_count + count > s.points.len { ret TooLarge }
    s.verbs[s.verb_count] = verb
    s.verb_count += 1usize
    if count >= 1usize { s.points[s.point_count] = first }
    if count >= 2usize { s.points[s.point_count + 1usize] = second }
    if count >= 3usize { s.points[s.point_count + 2usize] = third }
    s.point_count += count
    ret ok
}

fn move_to(b: *PathBuilder, p: Point) -> err {
    let s = mem.cast[*BuilderState](b.state)
    let append_error = append(s, .Move, 1usize, p, p, p)
    if append_error != ok { ret append_error }
    s.open = true
    ret ok
}

fn line_to(b: *PathBuilder, p: Point) -> err {
    let s = mem.cast[*BuilderState](b.state)
    if !s.open { ret Invalid }
    ret append(s, .Line, 1usize, p, p, p)
}

fn quad_to(b: *PathBuilder, control: Point, end: Point) -> err {
    let s = mem.cast[*BuilderState](b.state)
    if !s.open { ret Invalid }
    ret append(s, .Quad, 2usize, control, end, end)
}

fn cubic_to(b: *PathBuilder, first: Point, second: Point, end: Point) -> err {
    let s = mem.cast[*BuilderState](b.state)
    if !s.open { ret Invalid }
    ret append(s, .Cubic, 3usize, first, second, end)
}

fn close_path(b: *PathBuilder) -> err {
    let s = mem.cast[*BuilderState](b.state)
    if !s.open { ret Invalid }
    let append_error = append(s, .Close, 0usize, zero, zero, zero)
    if append_error != ok { ret append_error }
    s.open = false
    ret ok
}

fn finish(b: *PathBuilder) -> Path {
    let s = mem.cast[*BuilderState](b.state)
    ret Path { verbs: s.verbs[..s.verb_count], points: s.points[..s.point_count] }
}
