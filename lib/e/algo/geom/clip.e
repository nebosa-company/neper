// Clipping, triangulation and simplification of planar polygons and polylines,
// over `e.algo.geom`'s points: Sutherland-Hodgman polygon clipping to a convex
// window, Cohen-Sutherland and Liang-Barsky line clipping, ear clipping, and
// Douglas-Peucker and Visvalingam-Whyatt simplification.

use e.algo.geom

type Rect = struct { min: geom.Point, max: geom.Point }
error TooSmall
error Invalid

// Sutherland-Hodgman: `subject` clipped to a convex counter-clockwise `window`.
// `out` and `scratch` need `2 * subject.len + window.len` points; answers the
// clipped polygon's vertex count.
fn clip_convex(subject: []const geom.Point, window: []const geom.Point, out: []geom.Point, scratch: []geom.Point) -> (usize, err) {
    let room = 2usize * subject.len + window.len
    if out.len < room || scratch.len < room || window.len < 3usize { ret (0usize, TooSmall) }
    var count = subject.len
    var i = 0usize
    while i < count {
        out[i] = subject[i]
        i += 1usize
    }
    var e = 0usize
    while e < window.len {
        let a = window[e]
        let b = window[(e + 1usize) % window.len]
        // Copy the current polygon into scratch and rebuild `out`.
        i = 0usize
        while i < count {
            scratch[i] = out[i]
            i += 1usize
        }
        let input_count = count
        count = 0usize
        if input_count == 0usize { ret (0usize, ok) }
        i = 0usize
        while i < input_count {
            let current = scratch[i]
            let previous = scratch[(i + input_count - 1usize) % input_count]
            let current_inside = geom.orient(a, b, current) >= 0.0f64
            let previous_inside = geom.orient(a, b, previous) >= 0.0f64
            if current_inside {
                if !previous_inside {
                    let (crossing, _) = line_intersection(previous, current, a, b)
                    out[count] = crossing
                    count += 1usize
                }
                out[count] = current
                count += 1usize
            } else if previous_inside {
                let (crossing, _) = line_intersection(previous, current, a, b)
                out[count] = crossing
                count += 1usize
            }
            i += 1usize
        }
        e += 1usize
    }
    ret (count, ok)
}

// The intersection of the infinite lines through `a b` and `c d`.
fn line_intersection(a: geom.Point, b: geom.Point, c: geom.Point, d: geom.Point) -> (geom.Point, bool) {
    let denominator = (b.x - a.x) * (d.y - c.y) - (b.y - a.y) * (d.x - c.x)
    if denominator == 0.0f64 { ret (a, false) }
    let t = ((c.x - a.x) * (d.y - c.y) - (c.y - a.y) * (d.x - c.x)) / denominator
    ret (geom.Point { x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y) }, true)
}

fn outcode(r: Rect, p: geom.Point) -> u32 {
    var code = 0u32
    if p.x < r.min.x { code = code | 1u32 }
    if p.x > r.max.x { code = code | 2u32 }
    if p.y < r.min.y { code = code | 4u32 }
    if p.y > r.max.y { code = code | 8u32 }
    ret code
}

// Cohen-Sutherland: the part of segment `a b` inside `r`, if any.
fn clip_line(r: Rect, a: geom.Point, b: geom.Point) -> (geom.Point, geom.Point, bool) {
    var p = a
    var q = b
    var code_p = outcode(r, p)
    var code_q = outcode(r, q)
    var rounds = 0usize
    while rounds < 8usize {
        if (code_p | code_q) == 0u32 { ret (p, q, true) }
        if (code_p & code_q) != 0u32 { ret (a, b, false) }
        var code = code_p
        if code == 0u32 { code = code_q }
        var x = 0.0f64
        var y = 0.0f64
        if (code & 8u32) != 0u32 {
            x = p.x + (q.x - p.x) * (r.max.y - p.y) / (q.y - p.y)
            y = r.max.y
        } else if (code & 4u32) != 0u32 {
            x = p.x + (q.x - p.x) * (r.min.y - p.y) / (q.y - p.y)
            y = r.min.y
        } else if (code & 2u32) != 0u32 {
            y = p.y + (q.y - p.y) * (r.max.x - p.x) / (q.x - p.x)
            x = r.max.x
        } else {
            y = p.y + (q.y - p.y) * (r.min.x - p.x) / (q.x - p.x)
            x = r.min.x
        }
        if code == code_p {
            p = geom.Point { x: x, y: y }
            code_p = outcode(r, p)
        } else {
            q = geom.Point { x: x, y: y }
            code_q = outcode(r, q)
        }
        rounds += 1usize
    }
    ret (a, b, false)
}

// Liang-Barsky: the same clip by parametric distances.
fn clip_line_liang_barsky(r: Rect, a: geom.Point, b: geom.Point) -> (geom.Point, geom.Point, bool) {
    let dx = b.x - a.x
    let dy = b.y - a.y
    var t0 = 0.0f64
    var t1 = 1.0f64
    var side = 0usize
    while side < 4usize {
        var p = 0.0f64
        var q = 0.0f64
        if side == 0usize {
            p = 0.0f64 - dx
            q = a.x - r.min.x
        } else if side == 1usize {
            p = dx
            q = r.max.x - a.x
        } else if side == 2usize {
            p = 0.0f64 - dy
            q = a.y - r.min.y
        } else {
            p = dy
            q = r.max.y - a.y
        }
        if p == 0.0f64 {
            if q < 0.0f64 { ret (a, b, false) }
        } else {
            let t = q / p
            if p < 0.0f64 {
                if t > t1 { ret (a, b, false) }
                if t > t0 { t0 = t }
            } else {
                if t < t0 { ret (a, b, false) }
                if t < t1 { t1 = t }
            }
        }
        side += 1usize
    }
    ret (geom.Point { x: a.x + t0 * dx, y: a.y + t0 * dy }, geom.Point { x: a.x + t1 * dx, y: a.y + t1 * dy }, true)
}

// Ear clipping of a simple polygon in either winding: `triangles` receives
// `3 * (n - 2)` vertex indices; `scratch.len >= n` holds the remaining ring.
fn triangulate_ear_clip(polygon: []const geom.Point, triangles: []usize, scratch: []usize) -> (usize, err) {
    let n = polygon.len
    if n < 3usize { ret (0usize, Invalid) }
    if triangles.len < 3usize * (n - 2usize) || scratch.len < n { ret (0usize, TooSmall) }
    let ccw = geom.polygon_area(polygon) > 0.0f64
    var remaining = n
    var i = 0usize
    while i < n {
        if ccw { scratch[i] = i } else { scratch[i] = n - 1usize - i }
        i += 1usize
    }
    var written = 0usize
    var guard = 0usize
    while remaining > 3usize && guard < 4usize * n * n {
        guard += 1usize
        var found = false
        i = 0usize
        while i < remaining && !found {
            let ia = scratch[(i + remaining - 1usize) % remaining]
            let ib = scratch[i]
            let ic = scratch[(i + 1usize) % remaining]
            if geom.orient(polygon[ia], polygon[ib], polygon[ic]) > 0.0f64 {
                var empty = true
                var k = 0usize
                while k < remaining && empty {
                    let ik = scratch[k]
                    if ik != ia && ik != ib && ik != ic {
                        if geom.orient(polygon[ia], polygon[ib], polygon[ik]) >= 0.0f64 && geom.orient(polygon[ib], polygon[ic], polygon[ik]) >= 0.0f64 && geom.orient(polygon[ic], polygon[ia], polygon[ik]) >= 0.0f64 { empty = false }
                    }
                    k += 1usize
                }
                if empty {
                    triangles[written] = ia
                    triangles[written + 1usize] = ib
                    triangles[written + 2usize] = ic
                    written += 3usize
                    var m = i
                    while m + 1usize < remaining {
                        scratch[m] = scratch[m + 1usize]
                        m += 1usize
                    }
                    remaining -= 1usize
                    found = true
                }
            }
            i += 1usize
        }
        if !found { ret (written, Invalid) }
    }
    if remaining == 3usize {
        triangles[written] = scratch[0usize]
        triangles[written + 1usize] = scratch[1usize]
        triangles[written + 2usize] = scratch[2usize]
        written += 3usize
    }
    ret (written, ok)
}

// Douglas-Peucker: keeps the points of a polyline farther than `tolerance` from
// the chord, writing `keep[i] = 1` for kept points; `stack.len >= 2 * points.len`.
fn simplify_douglas_peucker(points: []const geom.Point, tolerance: f64, keep: []u8, stack: []usize) -> err {
    let n = points.len
    if keep.len < n || stack.len < 2usize * n { ret TooSmall }
    var i = 0usize
    while i < n {
        keep[i] = 0u8
        i += 1usize
    }
    if n == 0usize { ret ok }
    keep[0usize] = 1u8
    keep[n - 1usize] = 1u8
    var top = 0usize
    stack[0usize] = 0usize
    stack[1usize] = n - 1usize
    top = 2usize
    let tolerance2 = tolerance * tolerance
    while top >= 2usize {
        top -= 2usize
        let first = stack[top]
        let last = stack[top + 1usize]
        if last <= first + 1usize { continue }
        var farthest = first
        var farthest_d = 0.0f64
        i = first + 1usize
        while i < last {
            let d = point_segment_distance_squared(points[i], points[first], points[last])
            if d > farthest_d {
                farthest_d = d
                farthest = i
            }
            i += 1usize
        }
        if farthest_d > tolerance2 {
            keep[farthest] = 1u8
            if top + 4usize > stack.len { ret TooSmall }
            stack[top] = first
            stack[top + 1usize] = farthest
            stack[top + 2usize] = farthest
            stack[top + 3usize] = last
            top += 4usize
        }
    }
    ret ok
}

fn point_segment_distance_squared(p: geom.Point, a: geom.Point, b: geom.Point) -> f64 {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let length2 = dx * dx + dy * dy
    if length2 == 0.0f64 { ret geom.distance_squared(p, a) }
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2
    if t < 0.0f64 { t = 0.0f64 }
    if t > 1.0f64 { t = 1.0f64 }
    ret geom.distance_squared(p, geom.Point { x: a.x + t * dx, y: a.y + t * dy })
}

// Visvalingam-Whyatt: repeatedly drops the interior point whose triangle with
// its neighbours has the least area, until every remaining one exceeds
// `min_area`; `keep[i] = 1` for kept points. Quadratic; polylines here are short.
fn simplify_visvalingam(points: []const geom.Point, min_area: f64, keep: []u8) -> err {
    let n = points.len
    if keep.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        keep[i] = 1u8
        i += 1usize
    }
    while true {
        var least = 0.0f64
        var least_at = n
        var before = n
        i = 0usize
        while i < n {
            if keep[i] == 1u8 {
                if before != n && i + 1usize < n {
                    // The following kept point after i.
                    var following = i + 1usize
                    while following < n && keep[following] == 0u8 { following += 1usize }
                    if following < n {
                        var area = geom.orient(points[before], points[i], points[following]) / 2.0f64
                        if area < 0.0f64 { area = 0.0f64 - area }
                        if least_at == n || area < least {
                            least = area
                            least_at = i
                        }
                    }
                }
                before = i
            }
            i += 1usize
        }
        if least_at == n || least >= min_area { break }
        keep[least_at] = 0u8
    }
    ret ok
}

