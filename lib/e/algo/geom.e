// Planar geometry over `f64` points and caller storage: predicates, segment
// intersection, polygon area, convexity and containment, convex hulls, closest
// and farthest pairs, the smallest enclosing circle and bounding rectangle,
// Pick's lattice count and Morton codes. Clipping, triangulation and
// simplification live in `e.algo.geom.clip`.
//
// Polygons are point slices in either winding; `polygon_area` is signed
// (positive counter-clockwise). Predicates use plain floating point; callers
// needing exactness scale to integer coordinates below `2^26` so the products
// stay exact.

type Point = struct { x: f64, y: f64 }
type Circle = struct { center: Point, radius: f64 }
error TooSmall
error Invalid

fn point(x: f64, y: f64) -> Point { ret Point { x: x, y: y } }

// Twice the signed area of `a b c`: positive for a counter-clockwise turn.
fn orient(a: Point, b: Point, c: Point) -> f64 {
    ret (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

fn distance_squared(a: Point, b: Point) -> f64 {
    ret (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
}

// Whether `d` lies inside the circle through `a`, `b`, `c` (counter-clockwise).
fn in_circle(a: Point, b: Point, c: Point, d: Point) -> bool {
    let adx = a.x - d.x
    let ady = a.y - d.y
    let bdx = b.x - d.x
    let bdy = b.y - d.y
    let cdx = c.x - d.x
    let cdy = c.y - d.y
    let det = (adx * adx + ady * ady) * (bdx * cdy - cdx * bdy) - (bdx * bdx + bdy * bdy) * (adx * cdy - cdx * ady) + (cdx * cdx + cdy * cdy) * (adx * bdy - bdx * ady)
    ret det > 0.0f64
}

fn on_segment(a: Point, b: Point, p: Point) -> bool {
    var lo_x = a.x
    var hi_x = b.x
    if lo_x > hi_x {
        lo_x = b.x
        hi_x = a.x
    }
    var lo_y = a.y
    var hi_y = b.y
    if lo_y > hi_y {
        lo_y = b.y
        hi_y = a.y
    }
    ret p.x >= lo_x && p.x <= hi_x && p.y >= lo_y && p.y <= hi_y
}

// Whether segments `a b` and `c d` share a point, touching included.
fn segments_intersect(a: Point, b: Point, c: Point, d: Point) -> bool {
    let o1 = orient(a, b, c)
    let o2 = orient(a, b, d)
    let o3 = orient(c, d, a)
    let o4 = orient(c, d, b)
    if ((o1 > 0.0f64 && o2 < 0.0f64) || (o1 < 0.0f64 && o2 > 0.0f64)) && ((o3 > 0.0f64 && o4 < 0.0f64) || (o3 < 0.0f64 && o4 > 0.0f64)) { ret true }
    if o1 == 0.0f64 && on_segment(a, b, c) { ret true }
    if o2 == 0.0f64 && on_segment(a, b, d) { ret true }
    if o3 == 0.0f64 && on_segment(c, d, a) { ret true }
    if o4 == 0.0f64 && on_segment(c, d, b) { ret true }
    ret false
}

// The crossing point of two non-parallel segments, when they cross.
fn segment_intersection(a: Point, b: Point, c: Point, d: Point) -> (Point, bool) {
    let denominator = (b.x - a.x) * (d.y - c.y) - (b.y - a.y) * (d.x - c.x)
    if denominator == 0.0f64 { ret (a, false) }
    let t = ((c.x - a.x) * (d.y - c.y) - (c.y - a.y) * (d.x - c.x)) / denominator
    let u = ((c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)) / denominator
    if t < 0.0f64 || t > 1.0f64 || u < 0.0f64 || u > 1.0f64 { ret (a, false) }
    ret (Point { x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y) }, true)
}

// The shoelace formula: positive for a counter-clockwise polygon.
fn polygon_area(polygon: []const Point) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < polygon.len {
        let j = (i + 1usize) % polygon.len
        sum += polygon[i].x * polygon[j].y - polygon[j].x * polygon[i].y
        i += 1usize
    }
    ret sum / 2.0f64
}

// Whether every turn has the same sign (collinear runs allowed).
fn is_convex(polygon: []const Point) -> bool {
    if polygon.len < 3usize { ret false }
    var sign = 0i32
    var i = 0usize
    while i < polygon.len {
        let o = orient(polygon[i], polygon[(i + 1usize) % polygon.len], polygon[(i + 2usize) % polygon.len])
        if o != 0.0f64 {
            var here = 1i32
            if o < 0.0f64 { here = 0i32 - 1i32 }
            if sign == 0i32 { sign = here } else if sign != here { ret false }
        }
        i += 1usize
    }
    ret true
}

// Crossing number: whether `p` is inside; a point on the boundary counts as inside.
fn point_in_polygon(polygon: []const Point, p: Point) -> bool {
    var inside = false
    var i = 0usize
    var j = polygon.len
    if j == 0usize { ret false }
    j -= 1usize
    while i < polygon.len {
        let a = polygon[i]
        let b = polygon[j]
        if orient(a, b, p) == 0.0f64 && on_segment(a, b, p) { ret true }
        if (a.y > p.y) != (b.y > p.y) {
            let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
            if p.x < x { inside = !inside }
        }
        j = i
        i += 1usize
    }
    ret inside
}

// The winding number of `polygon` around `p`: 0 outside, nonzero inside.
fn winding_number(polygon: []const Point, p: Point) -> i32 {
    var winding = 0i32
    var i = 0usize
    while i < polygon.len {
        let a = polygon[i]
        let b = polygon[(i + 1usize) % polygon.len]
        if a.y <= p.y {
            if b.y > p.y && orient(a, b, p) > 0.0f64 { winding += 1i32 }
        } else {
            if b.y <= p.y && orient(a, b, p) < 0.0f64 { winding -= 1i32 }
        }
        i += 1usize
    }
    ret winding
}

// Andrew's monotone chain: the convex hull counter-clockwise, collinear boundary
// points dropped; `points` is sorted in place and `out.len >= points.len + 1`.
// Answers how many hull points were written.
fn hull(points: []Point, out: []Point) -> (usize, err) {
    let n = points.len
    if out.len < n + 1usize { ret (0usize, TooSmall) }
    if n < 3usize {
        var k = 0usize
        while k < n {
            out[k] = points[k]
            k += 1usize
        }
        ret (n, ok)
    }
    sort_points(points)
    var m = 0usize
    var i = 0usize
    while i < n {
        while m >= 2usize && orient(out[m - 2usize], out[m - 1usize], points[i]) <= 0.0f64 { m -= 1usize }
        out[m] = points[i]
        m += 1usize
        i += 1usize
    }
    let lower = m + 1usize
    i = n - 1usize
    while i > 0usize {
        i -= 1usize
        while m >= lower && orient(out[m - 2usize], out[m - 1usize], points[i]) <= 0.0f64 { m -= 1usize }
        out[m] = points[i]
        m += 1usize
    }
    ret (m - 1usize, ok)
}

// Insertion sort by x then y (hull inputs are usually small; larger ones
// should be pre-sorted with `e.algo.sort`).
fn sort_points(points: []Point) {
    var i = 1usize
    while i < points.len {
        var j = i
        while j > 0usize && (points[j].x < points[j - 1usize].x || (points[j].x == points[j - 1usize].x && points[j].y < points[j - 1usize].y)) {
            let swap = points[j]
            points[j] = points[j - 1usize]
            points[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
}

// Jarvis march (gift wrapping): the hull counter-clockwise in `O(n h)`.
fn hull_jarvis(points: []const Point, out: []Point) -> (usize, err) {
    let n = points.len
    if out.len < n { ret (0usize, TooSmall) }
    if n < 3usize {
        var k = 0usize
        while k < n {
            out[k] = points[k]
            k += 1usize
        }
        ret (n, ok)
    }
    var start = 0usize
    var i = 1usize
    while i < n {
        if points[i].x < points[start].x || (points[i].x == points[start].x && points[i].y < points[start].y) { start = i }
        i += 1usize
    }
    var m = 0usize
    var current = start
    while true {
        out[m] = points[current]
        m += 1usize
        var candidate = (current + 1usize) % n
        i = 0usize
        while i < n {
            let o = orient(points[current], points[candidate], points[i])
            if o < 0.0f64 || (o == 0.0f64 && distance_squared(points[current], points[i]) > distance_squared(points[current], points[candidate])) { candidate = i }
            i += 1usize
        }
        current = candidate
        if current == start || m >= n { break }
    }
    ret (m, ok)
}

// The closest pair by the plane sweep over x with a strip check; `points` is
// sorted in place. Answers the two indices (into the sorted slice) and the
// squared distance.
fn closest_pair(points: []Point) -> (usize, usize, f64, err) {
    if points.len < 2usize { ret (0usize, 0usize, 0.0f64, Invalid) }
    sort_points(points)
    var best = distance_squared(points[0usize], points[1usize])
    var best_a = 0usize
    var best_b = 1usize
    var i = 0usize
    while i < points.len {
        var j = i + 1usize
        while j < points.len {
            let dx = points[j].x - points[i].x
            if dx * dx > best { break }
            let d = distance_squared(points[i], points[j])
            if d < best {
                best = d
                best_a = i
                best_b = j
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (best_a, best_b, best, ok)
}

// The farthest pair of a convex hull by rotating calipers: two hull indices and
// the squared distance. The hull must be counter-clockwise.
fn farthest_pair(hull_points: []const Point) -> (usize, usize, f64, err) {
    let n = hull_points.len
    if n < 2usize { ret (0usize, 0usize, 0.0f64, Invalid) }
    if n == 2usize { ret (0usize, 1usize, distance_squared(hull_points[0usize], hull_points[1usize]), ok) }
    var best = 0.0f64
    var best_a = 0usize
    var best_b = 0usize
    var j = 1usize
    var i = 0usize
    while i < n {
        let next = (i + 1usize) % n
        // Advance the antipodal point while the triangle area keeps growing.
        while true {
            let here = orient(hull_points[i], hull_points[next], hull_points[j])
            let after = orient(hull_points[i], hull_points[next], hull_points[(j + 1usize) % n])
            if after > here { j = (j + 1usize) % n } else { break }
        }
        let d1 = distance_squared(hull_points[i], hull_points[j])
        if d1 > best {
            best = d1
            best_a = i
            best_b = j
        }
        let d2 = distance_squared(hull_points[next], hull_points[j])
        if d2 > best {
            best = d2
            best_a = next
            best_b = j
        }
        i += 1usize
    }
    ret (best_a, best_b, best, ok)
}

// The smallest-area rectangle around a counter-clockwise convex hull: one edge is
// collinear with a hull edge. Answers the four corners in `out` (at least 4) and
// the area.
fn min_bounding_rect(hull_points: []const Point, out: []Point) -> (f64, err) {
    let n = hull_points.len
    if out.len < 4usize { ret (0.0f64, TooSmall) }
    if n < 3usize { ret (0.0f64, Invalid) }
    var best_area = 0.0f64
    var first = true
    var i = 0usize
    while i < n {
        let a = hull_points[i]
        let b = hull_points[(i + 1usize) % n]
        let ex = b.x - a.x
        let ey = b.y - a.y
        let length = sqrt_f64(ex * ex + ey * ey)
        if length > 0.0f64 {
            let ux = ex / length
            let uy = ey / length
            // Project every point onto the edge direction and its normal.
            var min_u = 0.0f64
            var max_u = 0.0f64
            var min_v = 0.0f64
            var max_v = 0.0f64
            var k = 0usize
            while k < n {
                let px = hull_points[k].x - a.x
                let py = hull_points[k].y - a.y
                let u = px * ux + py * uy
                let v = 0.0f64 - px * uy + py * ux
                if k == 0usize || u < min_u { min_u = u }
                if k == 0usize || u > max_u { max_u = u }
                if k == 0usize || v < min_v { min_v = v }
                if k == 0usize || v > max_v { max_v = v }
                k += 1usize
            }
            let area = (max_u - min_u) * (max_v - min_v)
            if first || area < best_area {
                first = false
                best_area = area
                out[0usize] = Point { x: a.x + min_u * ux - min_v * uy, y: a.y + min_u * uy + min_v * ux }
                out[1usize] = Point { x: a.x + max_u * ux - min_v * uy, y: a.y + max_u * uy + min_v * ux }
                out[2usize] = Point { x: a.x + max_u * ux - max_v * uy, y: a.y + max_u * uy + max_v * ux }
                out[3usize] = Point { x: a.x + min_u * ux - max_v * uy, y: a.y + min_u * uy + max_v * ux }
            }
        }
        i += 1usize
    }
    ret (best_area, ok)
}

// Newton's square root, so the module needs nothing from `e.math`.
fn sqrt_f64(x: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    var r = x
    if r > 1.0f64 { r = x / 2.0f64 }
    var i = 0usize
    while i < 60usize {
        let next = (r + x / r) / 2.0f64
        if next == r { break }
        r = next
        i += 1usize
    }
    ret r
}

// Welzl's smallest enclosing circle, iterative with random restarts avoided by
// the deterministic incremental form (expected `O(n)` on shuffled input).
fn enclosing_circle(points: []const Point) -> Circle {
    if points.len == 0usize { ret Circle { center: Point { x: 0.0f64, y: 0.0f64 }, radius: 0.0f64 } }
    var c = Circle { center: points[0usize], radius: 0.0f64 }
    var i = 1usize
    while i < points.len {
        if !circle_contains(c, points[i]) {
            c = Circle { center: points[i], radius: 0.0f64 }
            var j = 0usize
            while j < i {
                if !circle_contains(c, points[j]) {
                    c = circle_two(points[i], points[j])
                    var k = 0usize
                    while k < j {
                        if !circle_contains(c, points[k]) { c = circle_three(points[i], points[j], points[k]) }
                        k += 1usize
                    }
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    ret c
}

fn circle_contains(c: Circle, p: Point) -> bool {
    ret distance_squared(c.center, p) <= c.radius * c.radius * (1.0f64 + 0.000000000001f64) + 0.000000000001f64
}

fn circle_two(a: Point, b: Point) -> Circle {
    let center = Point { x: (a.x + b.x) / 2.0f64, y: (a.y + b.y) / 2.0f64 }
    ret Circle { center: center, radius: sqrt_f64(distance_squared(center, a)) }
}

fn circle_three(a: Point, b: Point, c: Point) -> Circle {
    let bx = b.x - a.x
    let by = b.y - a.y
    let cx = c.x - a.x
    let cy = c.y - a.y
    let d = 2.0f64 * (bx * cy - by * cx)
    if d == 0.0f64 {
        // Collinear: the circle on the two farthest apart.
        var far = circle_two(a, b)
        let ac = circle_two(a, c)
        let bc = circle_two(b, c)
        if ac.radius > far.radius { far = ac }
        if bc.radius > far.radius { far = bc }
        ret far
    }
    let ux = (cy * (bx * bx + by * by) - by * (cx * cx + cy * cy)) / d
    let uy = (bx * (cx * cx + cy * cy) - cx * (bx * bx + by * by)) / d
    let center = Point { x: a.x + ux, y: a.y + uy }
    ret Circle { center: center, radius: sqrt_f64(ux * ux + uy * uy) }
}

// Pick's theorem: the interior lattice points of a lattice polygon from its area
// and boundary count (gcd of the edge deltas).
fn lattice_points(polygon: []const Point) -> (i64, i64) {
    var boundary = 0i64
    var i = 0usize
    while i < polygon.len {
        let j = (i + 1usize) % polygon.len
        var dx = i64(polygon[j].x) - i64(polygon[i].x)
        var dy = i64(polygon[j].y) - i64(polygon[i].y)
        if dx < 0i64 { dx = 0i64 - dx }
        if dy < 0i64 { dy = 0i64 - dy }
        var a = u64(dx)
        var b = u64(dy)
        while b != 0u64 {
            let r = a % b
            a = b
            b = r
        }
        boundary += i64(a)
        i += 1usize
    }
    var twice_area = 0i64
    i = 0usize
    while i < polygon.len {
        let j = (i + 1usize) % polygon.len
        twice_area += i64(polygon[i].x) * i64(polygon[j].y) - i64(polygon[j].x) * i64(polygon[i].y)
        i += 1usize
    }
    if twice_area < 0i64 { twice_area = 0i64 - twice_area }
    // A = I + B/2 - 1, so I = (2A - B + 2) / 2.
    ret ((twice_area - boundary + 2i64) / 2i64, boundary)
}

// Interleaves the low 32 bits of `x` and `y` into a Morton (Z-order) code.
fn morton_encode(x: u32, y: u32) -> u64 { ret spread(x) | (spread(y) << 1u64) }

fn spread(v: u32) -> u64 {
    var x = u64(v)
    x = (x | (x << 16u64)) & 281470681808895u64
    x = (x | (x << 8u64)) & 71777214294589695u64
    x = (x | (x << 4u64)) & 1085102592571150095u64
    x = (x | (x << 2u64)) & 3689348814741910323u64
    x = (x | (x << 1u64)) & 6148914691236517205u64
    ret x
}

fn morton_decode(code: u64) -> (u32, u32) { ret (compact(code), compact(code >> 1u64)) }

fn compact(v: u64) -> u32 {
    var x = v & 6148914691236517205u64
    x = (x | (x >> 1u64)) & 3689348814741910323u64
    x = (x | (x >> 2u64)) & 1085102592571150095u64
    x = (x | (x >> 4u64)) & 71777214294589695u64
    x = (x | (x >> 8u64)) & 281470681808895u64
    x = (x | (x >> 16u64)) & 4294967295u64
    ret u32(x)
}
