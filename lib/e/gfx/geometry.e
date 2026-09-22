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
//
// `flatten` rewrites a path as `Move`/`Line`/`Close` verbs over caller storage, cutting
// each curve into the chord count its second derivative bounds under a tolerance;
// `stroke` turns such a flat path into closed polygons -- one per segment, join and
// cap, all wound the same way -- whose non-zero union is the stroked outline. Round
// joins and caps are whole circles, which is the exact Minkowski sum of the polyline
// and a disc; a miter past `miter_limit` falls back to a bevel.

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
type Cap = enum u8 { Butt, Round, Square }
type Join = enum u8 { Miter, Round, Bevel }
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

fn lerp(a: Point, b: Point, t: f32) -> Point {
    ret Point { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t }
}

fn distance(a: Point, b: Point) -> f32 {
    let dx = b.x - a.x
    let dy = b.y - a.y
    ret math.sqrt[f32](dx * dx + dy * dy)
}

// The chord count whose largest deviation, `bound / (8 n^2)` for a curve whose second
// derivative is at most `bound`, stays under `tolerance`.
fn chord_count(bound: f32, tolerance: f32) -> usize {
    let n = math.ceil[f32](math.sqrt[f32](bound / (8.0 * tolerance)))
    if n < 1.0 { ret 1usize }
    ret usize(i64(n))
}

fn flatten(path: Path, tolerance: f32, verbs: []PathVerb, points: []Point) -> (Path, err) {
    if !(tolerance > 0.0) { ret (zero, Invalid) }
    var s = BuilderState { verbs: verbs, points: points, verb_count: 0usize, point_count: 0usize, open: false }
    var current: Point = zero
    var first: Point = zero
    var pi = 0usize
    var vi = 0usize
    while vi < path.verbs.len {
        let verb = path.verbs[vi]
        var e: err = ok
        if verb == .Move {
            current = path.points[pi]
            first = current
            pi += 1usize
            e = append(&s, .Move, 1usize, current, current, current)
        } else if verb == .Line {
            current = path.points[pi]
            pi += 1usize
            e = append(&s, .Line, 1usize, current, current, current)
        } else if verb == .Quad {
            let c = path.points[pi]
            let end = path.points[pi + 1usize]
            pi += 2usize
            let ddx = current.x - 2.0 * c.x + end.x
            let ddy = current.y - 2.0 * c.y + end.y
            let n = chord_count(2.0 * math.sqrt[f32](ddx * ddx + ddy * ddy), tolerance)
            var k = 1usize
            while k <= n && e == ok {
                let t = f32(k) / f32(n)
                let p = lerp(lerp(current, c, t), lerp(c, end, t), t)
                e = append(&s, .Line, 1usize, p, p, p)
                k += 1usize
            }
            current = end
        } else if verb == .Cubic {
            let c1 = path.points[pi]
            let c2 = path.points[pi + 1usize]
            let end = path.points[pi + 2usize]
            pi += 3usize
            let d1 = distance(Point { x: 2.0 * c1.x - c2.x, y: 2.0 * c1.y - c2.y }, current)
            let d2 = distance(Point { x: 2.0 * c2.x - c1.x, y: 2.0 * c2.y - c1.y }, end)
            var bound = d1
            if d2 > bound { bound = d2 }
            let n = chord_count(6.0 * bound, tolerance)
            var k = 1usize
            while k <= n && e == ok {
                let t = f32(k) / f32(n)
                let a = lerp(current, c1, t)
                let b = lerp(c1, c2, t)
                let c = lerp(c2, end, t)
                let p = lerp(lerp(a, b, t), lerp(b, c, t), t)
                e = append(&s, .Line, 1usize, p, p, p)
                k += 1usize
            }
            current = end
        } else {
            e = append(&s, .Close, 0usize, zero, zero, zero)
            current = first
        }
        if e != ok { ret (zero, e) }
        vi += 1usize
    }
    ret (Path { verbs: verbs[..s.verb_count], points: points[..s.point_count] }, ok)
}

// Appends one closed polygon, reversed when its shoelace area is positive, so every
// polygon `stroke` emits winds the same way and their non-zero union never cancels.
fn emit_polygon(s: *BuilderState, pts: []const Point) -> err {
    var area: f32 = 0.0
    var i = 0usize
    while i < pts.len {
        var j = i + 1usize
        if j == pts.len { j = 0usize }
        area += pts[i].x * pts[j].y - pts[j].x * pts[i].y
        i += 1usize
    }
    i = 0usize
    while i < pts.len {
        var k = i
        if area > 0.0 { k = pts.len - 1usize - i }
        var verb: PathVerb = .Line
        if i == 0usize { verb = .Move }
        let e = append(s, verb, 1usize, pts[k], pts[k], pts[k])
        if e != ok { ret e }
        i += 1usize
    }
    ret append(s, .Close, 0usize, zero, zero, zero)
}

// A circle of radius `hw` as the fewest chords (8 to 64) whose sagitta stays under `tolerance`.
fn emit_circle(s: *BuilderState, center: Point, hw: f32, tolerance: f32) -> err {
    var n = 8usize
    while n < 64usize && hw * (1.0 - math.cos[f32](3.14159265 / f32(n))) > tolerance { n += 1usize }
    var ring: [64]Point = zero
    var i = 0usize
    while i < n {
        let angle = 6.2831853 * f32(i) / f32(n)
        ring[i] = Point { x: center.x + hw * math.cos[f32](angle), y: center.y + hw * math.sin[f32](angle) }
        i += 1usize
    }
    ret emit_polygon(s, ring[..n])
}

fn unit_normal(from: Point, to: Point) -> Point {
    let len = distance(from, to)
    ret Point { x: (from.y - to.y) / len, y: (to.x - from.x) / len }
}

fn offset(p: Point, n: Point, k: f32) -> Point {
    ret Point { x: p.x + n.x * k, y: p.y + n.y * k }
}

fn stroke_segment(s: *BuilderState, p: Point, q: Point, hw: f32) -> err {
    let n = unit_normal(p, q)
    let quad = [4]Point{ offset(p, n, hw), offset(q, n, hw), offset(q, n, 0.0 - hw), offset(p, n, 0.0 - hw) }
    ret emit_polygon(s, quad[..])
}

// The join at `p` between the segments `a -> p` and `p -> b`.
fn stroke_join(s: *BuilderState, a: Point, p: Point, b: Point, hw: f32, join: Join, miter_limit: f32, tolerance: f32) -> err {
    if join == .Round { ret emit_circle(s, p, hw, tolerance) }
    let n1 = unit_normal(a, p)
    let n2 = unit_normal(p, b)
    let cross = (p.x - a.x) * (b.y - p.y) - (p.y - a.y) * (b.x - p.x)
    if cross == 0.0 { ret ok }
    var side = hw
    if cross > 0.0 { side = 0.0 - hw }
    let outer1 = offset(p, n1, side)
    let outer2 = offset(p, n2, side)
    let dot = n1.x * n2.x + n1.y * n2.y
    if join == .Miter && dot > -1.0 && 2.0 / (1.0 + dot) <= miter_limit * miter_limit {
        let k = side / (1.0 + dot)
        let tip = Point { x: p.x + (n1.x + n2.x) * k, y: p.y + (n1.y + n2.y) * k }
        let quad = [4]Point{ p, outer1, tip, outer2 }
        ret emit_polygon(s, quad[..])
    }
    let tri = [3]Point{ p, outer1, outer2 }
    ret emit_polygon(s, tri[..])
}

// The cap at `p`, the end of the segment `from -> p`.
fn stroke_cap(s: *BuilderState, from: Point, p: Point, hw: f32, cap: Cap, tolerance: f32) -> err {
    if cap == .Butt { ret ok }
    if cap == .Round { ret emit_circle(s, p, hw, tolerance) }
    let n = unit_normal(from, p)
    let d = Point { x: 0.0 - n.y, y: n.x }
    let far = offset(p, d, hw)
    let quad = [4]Point{ offset(p, n, hw), offset(far, n, hw), offset(far, n, 0.0 - hw), offset(p, n, 0.0 - hw) }
    ret emit_polygon(s, quad[..])
}

fn stroke_contour(s: *BuilderState, pts: []const Point, closed: bool, hw: f32, cap: Cap, join: Join, miter_limit: f32, tolerance: f32) -> err {
    // Coincident neighbours would give a normal of nothing: keep the distinct run.
    var kept: [256]Point = zero
    var n = 0usize
    var i = 0usize
    while i < pts.len {
        if n == 0usize || distance(kept[n - 1usize], pts[i]) > 0.0 {
            if n == 256usize { ret TooLarge }
            kept[n] = pts[i]
            n += 1usize
        }
        i += 1usize
    }
    if closed && n > 1usize && distance(kept[n - 1usize], kept[0usize]) == 0.0 { n -= 1usize }
    if n < 2usize { ret ok }
    i = 0usize
    while i + 1usize < n {
        let e = stroke_segment(s, kept[i], kept[i + 1usize], hw)
        if e != ok { ret e }
        i += 1usize
    }
    i = 1usize
    while i + 1usize < n {
        let e = stroke_join(s, kept[i - 1usize], kept[i], kept[i + 1usize], hw, join, miter_limit, tolerance)
        if e != ok { ret e }
        i += 1usize
    }
    if closed && n > 2usize {
        let e = stroke_segment(s, kept[n - 1usize], kept[0usize], hw)
        if e != ok { ret e }
        let e1 = stroke_join(s, kept[n - 2usize], kept[n - 1usize], kept[0usize], hw, join, miter_limit, tolerance)
        if e1 != ok { ret e1 }
        ret stroke_join(s, kept[n - 1usize], kept[0usize], kept[1usize], hw, join, miter_limit, tolerance)
    }
    let e = stroke_cap(s, kept[1usize], kept[0usize], hw, cap, tolerance)
    if e != ok { ret e }
    ret stroke_cap(s, kept[n - 2usize], kept[n - 1usize], hw, cap, tolerance)
}

// Strokes a flat path (`Move`/`Line`/`Close` only, else `Invalid`) of `width` into
// closed polygons over caller storage; `tolerance` bounds the chords of round joins
// and caps. A contour of one distinct point emits nothing.
// ponytail: a contour keeps at most 256 distinct points on the stack; stream the
// segments when glyph outlines outgrow it.
fn stroke(path: Path, width: f32, cap: Cap, join: Join, miter_limit: f32, tolerance: f32, verbs: []PathVerb, points: []Point) -> (Path, err) {
    if !(width > 0.0) || !(tolerance > 0.0) { ret (zero, Invalid) }
    var s = BuilderState { verbs: verbs, points: points, verb_count: 0usize, point_count: 0usize, open: false }
    let hw = width / 2.0
    var start = 0usize
    var count = 0usize
    var vi = 0usize
    var pi = 0usize
    while vi < path.verbs.len {
        let verb = path.verbs[vi]
        if verb == .Quad || verb == .Cubic { ret (zero, Invalid) }
        if verb == .Move {
            if count > 0usize {
                let e = stroke_contour(&s, path.points[start..start + count], false, hw, cap, join, miter_limit, tolerance)
                if e != ok { ret (zero, e) }
            }
            start = pi
            count = 1usize
            pi += 1usize
        } else if verb == .Line {
            count += 1usize
            pi += 1usize
        } else {
            let e = stroke_contour(&s, path.points[start..start + count], true, hw, cap, join, miter_limit, tolerance)
            if e != ok { ret (zero, e) }
            count = 0usize
        }
        vi += 1usize
    }
    if count > 0usize {
        let e = stroke_contour(&s, path.points[start..start + count], false, hw, cap, join, miter_limit, tolerance)
        if e != ok { ret (zero, e) }
    }
    ret (Path { verbs: verbs[..s.verb_count], points: points[..s.point_count] }, ok)
}
