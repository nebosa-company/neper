// Planar geometry over `f64` points and caller storage: predicates, segment
// intersection, polygon area, convexity and containment, convex hulls (chain,
// Jarvis, Graham, quickhull), closest and farthest pairs, calipers, the
// smallest enclosing circle and bounding rectangle, Pick's lattice count and
// Morton codes; then Delaunay (Bowyer-Watson, Lawson flips, constraints), the
// Voronoi dual with Lloyd relaxation and the largest empty circle, convex
// clipping, Minkowski sums, polygon booleans and offsets, pairwise segment
// crossings and monotone triangulation. Line clipping, ear clipping and
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

// ---------------------------------------------------------------------------
// Convex clipping, two more hulls, calipers, Delaunay and Voronoi, Minkowski
// sums, polygon booleans and offsets, segment intersections and monotone
// triangulation. Triangulations are flat index triples: `triangles[..written]`
// holds three entries per counter-clockwise triangle.

type Op = enum u8 { Union, Intersection, Difference }
type Node = struct { p: Point, alpha: f64, crossing: bool, entry: bool, visited: bool, after: usize, before: usize, neighbor: usize }

// Sutherland-Hodgman: `subject` clipped to a convex counter-clockwise `window`;
// `out` and `scratch` need `2 * subject.len + window.len` points. Answers the
// clipped vertex count. (`e.algo.geom.clip.clip_convex` is the same algorithm;
// it imports this module, so the code cannot be shared.)
fn clip_polygon(subject: []const Point, window: []const Point, out: []Point, scratch: []Point) -> (usize, err) {
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
            let current_inside = orient(a, b, current) >= 0.0f64
            let previous_inside = orient(a, b, previous) >= 0.0f64
            if current_inside != previous_inside {
                out[count] = line_intersection(previous, current, a, b)
                count += 1usize
            }
            if current_inside {
                out[count] = current
                count += 1usize
            }
            i += 1usize
        }
        e += 1usize
    }
    ret (count, ok)
}

// The intersection of the infinite lines through `a b` and `c d` (`a` when parallel).
fn line_intersection(a: Point, b: Point, c: Point, d: Point) -> Point {
    let denominator = (b.x - a.x) * (d.y - c.y) - (b.y - a.y) * (d.x - c.x)
    if denominator == 0.0f64 { ret a }
    let t = ((c.x - a.x) * (d.y - c.y) - (c.y - a.y) * (d.x - c.x)) / denominator
    ret Point { x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y) }
}

// Graham scan: the hull counter-clockwise from the lowest-leftmost point (the
// polygon `hull` answers); `points` is sorted in place by angle around it.
fn hull_graham(points: []Point, out: []Point) -> (usize, err) {
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
    var pivot = 0usize
    var i = 1usize
    while i < n {
        if points[i].x < points[pivot].x || (points[i].x == points[pivot].x && points[i].y < points[pivot].y) { pivot = i }
        i += 1usize
    }
    let first = points[pivot]
    points[pivot] = points[0usize]
    points[0usize] = first
    i = 2usize
    while i < n {
        var j = i
        while j > 1usize && angle_before(first, points[j], points[j - 1usize]) {
            let swap = points[j]
            points[j] = points[j - 1usize]
            points[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
    var m = 0usize
    i = 0usize
    while i < n {
        while m >= 2usize && orient(out[m - 2usize], out[m - 1usize], points[i]) <= 0.0f64 { m -= 1usize }
        out[m] = points[i]
        m += 1usize
        i += 1usize
    }
    ret (m, ok)
}

// Whether `a` comes before `b` counter-clockwise around `pivot` (nearer first on a ray).
fn angle_before(pivot: Point, a: Point, b: Point) -> bool {
    let o = orient(pivot, a, b)
    if o != 0.0f64 { ret o > 0.0f64 }
    ret distance_squared(pivot, a) < distance_squared(pivot, b)
}

// Quickhull: the same counter-clockwise hull from the lowest-leftmost point,
// recursing on the point farthest from each chord; `out.len >= points.len`.
fn hull_quick(points: []const Point, out: []Point) -> (usize, err) {
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
    var lo = 0usize
    var hi = 0usize
    var i = 1usize
    while i < n {
        if points[i].x < points[lo].x || (points[i].x == points[lo].x && points[i].y < points[lo].y) { lo = i }
        if points[i].x > points[hi].x || (points[i].x == points[hi].x && points[i].y > points[hi].y) { hi = i }
        i += 1usize
    }
    out[0usize] = points[lo]
    var m = quick_side(points, points[lo], points[hi], out, 1usize)
    out[m] = points[hi]
    m = quick_side(points, points[hi], points[lo], out, m + 1usize)
    ret (m, ok)
}

// Writes the hull points strictly right of chord `a b`, in order, from `out[m]`.
fn quick_side(points: []const Point, a: Point, b: Point, out: []Point, m: usize) -> usize {
    var best = 0.0f64
    var found = false
    var c = a
    var i = 0usize
    while i < points.len {
        let o = orient(a, b, points[i])
        if o < 0.0f64 && (!found || o < best) {
            best = o
            found = true
            c = points[i]
        }
        i += 1usize
    }
    if !found { ret m }
    let k = quick_side(points, a, c, out, m)
    out[k] = c
    ret quick_side(points, c, b, out, k + 1usize)
}

// Rotating calipers over a counter-clockwise convex polygon: its minimum width
// (the least distance between parallel supporting lines) and its diameter.
fn rotating_calipers(hull_points: []const Point) -> (f64, f64, err) {
    let n = hull_points.len
    if n < 3usize { ret (0.0f64, 0.0f64, Invalid) }
    let (_, _, d2, e) = farthest_pair(hull_points)
    if e != ok { ret (0.0f64, 0.0f64, e) }
    var width = 0.0f64
    var j = 1usize
    var i = 0usize
    while i < n {
        let a = hull_points[i]
        let b = hull_points[(i + 1usize) % n]
        while true {
            let here = orient(a, b, hull_points[j])
            let after = orient(a, b, hull_points[(j + 1usize) % n])
            if after > here { j = (j + 1usize) % n } else { break }
        }
        let length = sqrt_f64(distance_squared(a, b))
        if length > 0.0f64 {
            let w = orient(a, b, hull_points[j]) / length
            if i == 0usize || w < width { width = w }
        }
        i += 1usize
    }
    ret (width, sqrt_f64(d2), ok)
}

// Bowyer-Watson with a ghost vertex (index `points.len`) standing for the
// outside, so no finite super triangle can lose hull triangles. `triangles`
// and `scratch` need `6 * points.len` entries; answers the number of indices
// written (three per counter-clockwise triangle). Points must be distinct and
// not all collinear.
fn delaunay(points: []const Point, triangles: []usize, scratch: []usize) -> (usize, err) {
    let n = points.len
    if triangles.len < 6usize * n || scratch.len < 6usize * n { ret (0usize, TooSmall) }
    if n < 3usize { ret (0usize, Invalid) }
    var third = 2usize
    while third < n && orient(points[0usize], points[1usize], points[third]) == 0.0f64 { third += 1usize }
    if third == n { ret (0usize, Invalid) }
    var b = 1usize
    var c = third
    if orient(points[0usize], points[b], points[c]) < 0.0f64 {
        b = third
        c = 1usize
    }
    // The first triangle and a ghost triangle behind each of its edges (each
    // ghost holds its real edge reversed, so adjacency stays consistent).
    triangles[0usize] = 0usize
    triangles[1usize] = b
    triangles[2usize] = c
    triangles[3usize] = b
    triangles[4usize] = 0usize
    triangles[5usize] = n
    triangles[6usize] = c
    triangles[7usize] = b
    triangles[8usize] = n
    triangles[9usize] = 0usize
    triangles[10usize] = c
    triangles[11usize] = n
    var count = 4usize
    var p = 2usize
    while p < n {
        if p != third {
            let (grown, e) = insert_point(points, triangles, scratch, count, p)
            if e != ok { ret (0usize, e) }
            count = grown
        }
        p += 1usize
    }
    var written = 0usize
    var t = 0usize
    while t < count {
        if triangles[3usize * t] != n && triangles[3usize * t + 1usize] != n && triangles[3usize * t + 2usize] != n {
            triangles[written] = triangles[3usize * t]
            triangles[written + 1usize] = triangles[3usize * t + 1usize]
            triangles[written + 2usize] = triangles[3usize * t + 2usize]
            written += 3usize
        }
        t += 1usize
    }
    ret (written, ok)
}

// Inserts `points[p]`: the triangles whose circumcircle holds it move to the
// tail, their cavity boundary goes to `scratch`, and a triangle per boundary
// edge replaces them. Answers the new triangle count.
fn insert_point(points: []const Point, triangles: []usize, scratch: []usize, count: usize, p: usize) -> (usize, err) {
    let q = points[p]
    var live = count
    var t = 0usize
    while t < live {
        if circle_holds(points, triangles, t, q) {
            live -= 1usize
            var k = 0usize
            while k < 3usize {
                let swap = triangles[3usize * t + k]
                triangles[3usize * t + k] = triangles[3usize * live + k]
                triangles[3usize * live + k] = swap
                k += 1usize
            }
        } else {
            t += 1usize
        }
    }
    if live == count { ret (count, Invalid) }
    var edges = 0usize
    t = live
    while t < count {
        var k = 0usize
        while k < 3usize {
            let a = triangles[3usize * t + k]
            let b = triangles[3usize * t + (k + 1usize) % 3usize]
            var inner = false
            var s = live
            while s < count && !inner {
                if s != t && has_edge(triangles, s, b, a) { inner = true }
                s += 1usize
            }
            if !inner {
                if 2usize * edges + 2usize > scratch.len { ret (count, TooSmall) }
                scratch[2usize * edges] = a
                scratch[2usize * edges + 1usize] = b
                edges += 1usize
            }
            k += 1usize
        }
        t += 1usize
    }
    if 3usize * (live + edges) > triangles.len { ret (count, TooSmall) }
    var e = 0usize
    while e < edges {
        triangles[3usize * (live + e)] = scratch[2usize * e]
        triangles[3usize * (live + e) + 1usize] = scratch[2usize * e + 1usize]
        triangles[3usize * (live + e) + 2usize] = p
        e += 1usize
    }
    ret (live + edges, ok)
}

// Whether the circumcircle of triangle `t` holds `q`: a ghost triangle's circle
// is the open half-plane beyond its real edge plus that edge; a point on a real
// triangle's edge counts too, so both neighbours of the edge are rebuilt.
fn circle_holds(points: []const Point, triangles: []const usize, t: usize, q: Point) -> bool {
    let ghost = points.len
    let a = triangles[3usize * t]
    let b = triangles[3usize * t + 1usize]
    let c = triangles[3usize * t + 2usize]
    if a == ghost { ret beyond(points[b], points[c], q) }
    if b == ghost { ret beyond(points[c], points[a], q) }
    if c == ghost { ret beyond(points[a], points[b], q) }
    if in_circle(points[a], points[b], points[c], q) { ret true }
    if orient(points[a], points[b], q) == 0.0f64 && on_segment(points[a], points[b], q) { ret true }
    if orient(points[b], points[c], q) == 0.0f64 && on_segment(points[b], points[c], q) { ret true }
    ret orient(points[c], points[a], q) == 0.0f64 && on_segment(points[c], points[a], q)
}

fn beyond(u: Point, v: Point, q: Point) -> bool {
    let o = orient(u, v, q)
    if o != 0.0f64 { ret o > 0.0f64 }
    ret on_segment(u, v, q)
}

// Whether triangle `t` has the directed edge `a b`.
fn has_edge(triangles: []const usize, t: usize, a: usize, b: usize) -> bool {
    var k = 0usize
    while k < 3usize {
        if triangles[3usize * t + k] == a && triangles[3usize * t + (k + 1usize) % 3usize] == b { ret true }
        k += 1usize
    }
    ret false
}

fn has_vertex(triangles: []const usize, t: usize, v: usize) -> bool {
    ret triangles[3usize * t] == v || triangles[3usize * t + 1usize] == v || triangles[3usize * t + 2usize] == v
}

fn make_ccw(points: []const Point, triangles: []usize, t: usize) {
    if orient(points[triangles[3usize * t]], points[triangles[3usize * t + 1usize]], points[triangles[3usize * t + 2usize]]) < 0.0f64 {
        let swap = triangles[3usize * t + 1usize]
        triangles[3usize * t + 1usize] = triangles[3usize * t + 2usize]
        triangles[3usize * t + 2usize] = swap
    }
}

// The edge triangles `i` and `j` share, as `(u, v, p, q, found)` with `p` the
// remaining vertex of `i` and `q` that of `j`.
fn shared_edge(triangles: []const usize, i: usize, j: usize) -> (usize, usize, usize, usize, bool) {
    var u = 0usize
    var v = 0usize
    var p = 0usize
    var found = 0usize
    var k = 0usize
    while k < 3usize {
        let x = triangles[3usize * i + k]
        if has_vertex(triangles, j, x) {
            if found == 0usize { u = x } else { v = x }
            found += 1usize
        } else {
            p = x
        }
        k += 1usize
    }
    if found != 2usize { ret (0usize, 0usize, 0usize, 0usize, false) }
    var q = 0usize
    k = 0usize
    while k < 3usize {
        let y = triangles[3usize * j + k]
        if y != u && y != v { q = y }
        k += 1usize
    }
    ret (u, v, p, q, true)
}

// Replaces the shared edge `u v` of triangles `i` and `j` by `p q` when the
// quadrilateral is strictly convex.
fn flip(points: []const Point, triangles: []usize, i: usize, j: usize, u: usize, v: usize, p: usize, q: usize) -> bool {
    if orient(points[p], points[q], points[u]) * orient(points[p], points[q], points[v]) >= 0.0f64 { ret false }
    triangles[3usize * i] = p
    triangles[3usize * i + 1usize] = u
    triangles[3usize * i + 2usize] = q
    make_ccw(points, triangles, i)
    triangles[3usize * j] = p
    triangles[3usize * j + 1usize] = q
    triangles[3usize * j + 2usize] = v
    make_ccw(points, triangles, j)
    ret true
}

fn is_fixed(fixed: []const usize, u: usize, v: usize) -> bool {
    var k = 0usize
    while 2usize * k + 1usize < fixed.len {
        if (fixed[2usize * k] == u && fixed[2usize * k + 1usize] == v) || (fixed[2usize * k] == v && fixed[2usize * k + 1usize] == u) { ret true }
        k += 1usize
    }
    ret false
}

// Lawson flips: makes any triangulation of `points` (flat index triples in
// either winding) Delaunay; answers the number of flips.
fn delaunay_flip(points: []const Point, triangles: []usize, written: usize) -> usize {
    ret lawson(points, triangles, written, triangles[..0usize])
}

// ponytail: every pass scans all triangle pairs for adjacency (quadratic in
// the triangle count); a neighbour table would make each flip constant time.
fn lawson(points: []const Point, triangles: []usize, written: usize, fixed: []const usize) -> usize {
    let count = written / 3usize
    var t = 0usize
    while t < count {
        make_ccw(points, triangles, t)
        t += 1usize
    }
    var flips = 0usize
    var changed = true
    var rounds = 0usize
    while changed && rounds < count * count + 4usize {
        changed = false
        rounds += 1usize
        var i = 0usize
        while i < count {
            var j = i + 1usize
            while j < count {
                let (u, v, p, q, adjacent) = shared_edge(triangles, i, j)
                if adjacent && !is_fixed(fixed, u, v) && in_circle(points[triangles[3usize * i]], points[triangles[3usize * i + 1usize]], points[triangles[3usize * i + 2usize]], points[q]) {
                    if flip(points, triangles, i, j, u, v, p, q) {
                        flips += 1usize
                        changed = true
                    }
                }
                j += 1usize
            }
            i += 1usize
        }
    }
    ret flips
}

// Whether segments `a b` and `c d` cross properly (no shared endpoints or touches).
fn crosses(a: Point, b: Point, c: Point, d: Point) -> bool {
    let o1 = orient(a, b, c)
    let o2 = orient(a, b, d)
    let o3 = orient(c, d, a)
    let o4 = orient(c, d, b)
    ret ((o1 > 0.0f64 && o2 < 0.0f64) || (o1 < 0.0f64 && o2 > 0.0f64)) && ((o3 > 0.0f64 && o4 < 0.0f64) || (o3 < 0.0f64 && o4 > 0.0f64))
}

// Constrained Delaunay: forces every `edges` pair (flat index pairs) into a
// triangulation of `points` by flipping the edges it crosses, then restores the
// Delaunay property everywhere else. `Invalid` when a constraint runs through
// a vertex or crosses another constraint.
fn delaunay_constrained(points: []const Point, triangles: []usize, written: usize, edges: []const usize) -> err {
    let count = written / 3usize
    var t = 0usize
    while t < count {
        make_ccw(points, triangles, t)
        t += 1usize
    }
    var e = 0usize
    while 2usize * e + 1usize < edges.len {
        let a = edges[2usize * e]
        let b = edges[2usize * e + 1usize]
        var rounds = 0usize
        var crossing = true
        while crossing && rounds < count * count + 4usize {
            crossing = false
            rounds += 1usize
            var i = 0usize
            while i < count {
                var j = i + 1usize
                while j < count {
                    let (u, v, p, q, adjacent) = shared_edge(triangles, i, j)
                    if adjacent && u != a && u != b && v != a && v != b && crosses(points[u], points[v], points[a], points[b]) {
                        crossing = true
                        let _ = flip(points, triangles, i, j, u, v, p, q)
                    }
                    j += 1usize
                }
                i += 1usize
            }
        }
        if crossing { ret Invalid }
        e += 1usize
    }
    let _ = lawson(points, triangles, written, edges)
    ret ok
}

// The circle through three points (collinear points get the circle on the two
// farthest apart).
fn circumcircle(a: Point, b: Point, c: Point) -> Circle { ret circle_three(a, b, c) }

// The largest circle holding no site whose centre lies inside the hull: over
// the Voronoi vertices (circumcentres of Delaunay `triangles`) covered by some
// triangle.
fn largest_empty_circle(points: []const Point, triangles: []const usize, written: usize) -> (Circle, err) {
    var best = Circle { center: Point { x: 0.0f64, y: 0.0f64 }, radius: 0.0f64 }
    var found = false
    var t = 0usize
    while 3usize * t + 2usize < written {
        let c = circle_three(points[triangles[3usize * t]], points[triangles[3usize * t + 1usize]], points[triangles[3usize * t + 2usize]])
        if c.radius > best.radius && covered(points, triangles, written, c.center) {
            best = c
            found = true
        }
        t += 1usize
    }
    if !found { ret (best, Invalid) }
    ret (best, ok)
}

// Whether some triangle holds `p` (boundary included).
fn covered(points: []const Point, triangles: []const usize, written: usize, p: Point) -> bool {
    var t = 0usize
    while 3usize * t + 2usize < written {
        let a = points[triangles[3usize * t]]
        let b = points[triangles[3usize * t + 1usize]]
        let c = points[triangles[3usize * t + 2usize]]
        let o1 = orient(a, b, p)
        let o2 = orient(b, c, p)
        let o3 = orient(c, a, p)
        if (o1 >= 0.0f64 && o2 >= 0.0f64 && o3 >= 0.0f64) || (o1 <= 0.0f64 && o2 <= 0.0f64 && o3 <= 0.0f64) { ret true }
        t += 1usize
    }
    ret false
}

// The other two vertices of triangle `t`, counter-clockwise after `site`.
fn fan_edges(triangles: []const usize, t: usize, site: usize) -> (usize, usize) {
    var k = 0usize
    while k < 3usize {
        if triangles[3usize * t + k] == site { ret (triangles[3usize * t + (k + 1usize) % 3usize], triangles[3usize * t + (k + 2usize) % 3usize]) }
        k += 1usize
    }
    ret (site, site)
}

// The triangle around `site` whose leading (or, `leading` false, trailing)
// fan vertex is `x`; `count` when there is none.
fn fan_find(triangles: []const usize, count: usize, site: usize, x: usize, leading: bool) -> usize {
    var t = 0usize
    while t < count {
        if has_vertex(triangles, t, site) {
            let (b, c) = fan_edges(triangles, t, site)
            if (leading && b == x) || (!leading && c == x) { ret t }
        }
        t += 1usize
    }
    ret count
}

// The Voronoi cell of `points[site]` from Delaunay `triangles`: the
// circumcentres of its fan in order, a hull site closed far out along its two
// bisector rays, clipped to the box `lo..hi`. `out.len` and `scratch.len` need
// `written + 16` points. Answers the cell's vertex count.
fn voronoi_cell(points: []const Point, triangles: []const usize, written: usize, site: usize, lo: Point, hi: Point, out: []Point, scratch: []Point) -> (usize, err) {
    let count = written / 3usize
    let s = points[site]
    var start = count
    var t = 0usize
    while t < count {
        if has_vertex(triangles, t, site) {
            if start == count { start = t }
            let (b, _) = fan_edges(triangles, t, site)
            if fan_find(triangles, count, site, b, false) == count { start = t }
        }
        t += 1usize
    }
    if start == count || scratch.len < count + 4usize { ret (0usize, Invalid) }
    var k = 1usize
    var cur = start
    var open = false
    while true {
        scratch[k] = circle_three(points[triangles[3usize * cur]], points[triangles[3usize * cur + 1usize]], points[triangles[3usize * cur + 2usize]]).center
        k += 1usize
        let (_, c) = fan_edges(triangles, cur, site)
        let following = fan_find(triangles, count, site, c, true)
        if following == count { open = true }
        if following == count || following == start || k > count + 1usize { break }
        cur = following
    }
    var from = 1usize
    if open {
        let (b_first, c_first) = fan_edges(triangles, start, site)
        let (b_last, c_last) = fan_edges(triangles, cur, site)
        let (n1x, n1y) = outward(s, points[b_first], points[c_first])
        let (n2x, n2y) = outward(s, points[c_last], points[b_last])
        let reach = 8.0f64 * (sqrt_f64(distance_squared(lo, hi)) + sqrt_f64(distance_squared(s, lo)) + sqrt_f64(distance_squared(s, scratch[1usize])) + sqrt_f64(distance_squared(s, scratch[k - 1usize])))
        scratch[0usize] = Point { x: scratch[1usize].x + reach * n1x, y: scratch[1usize].y + reach * n1y }
        scratch[k] = Point { x: scratch[k - 1usize].x + reach * n2x, y: scratch[k - 1usize].y + reach * n2y }
        k += 1usize
        let mx = n1x + n2x
        let my = n1y + n2y
        let ml = sqrt_f64(mx * mx + my * my)
        if ml > 0.0f64 {
            scratch[k] = Point { x: s.x + reach * mx / ml, y: s.y + reach * my / ml }
            k += 1usize
        }
        from = 0usize
    }
    var window: [4]Point = zero
    window[0usize] = lo
    window[1usize] = Point { x: hi.x, y: lo.y }
    window[2usize] = hi
    window[3usize] = Point { x: lo.x, y: hi.y }
    let (m, e) = clip_polygon(scratch[from..k], window[..], out, scratch[k..])
    ret (m, e)
}

// The unit normal of edge `s v` pointing away from `w`.
fn outward(s: Point, v: Point, w: Point) -> (f64, f64) {
    var nx = s.y - v.y
    var ny = v.x - s.x
    if nx * (w.x - s.x) + ny * (w.y - s.y) > 0.0f64 {
        nx = 0.0f64 - nx
        ny = 0.0f64 - ny
    }
    let length = sqrt_f64(nx * nx + ny * ny)
    if length == 0.0f64 { ret (0.0f64, 0.0f64) }
    ret (nx / length, ny / length)
}

// Every cell of the Delaunay dual: `cells[starts[i]..starts[i + 1]]` is site
// `i`'s cell clipped to the box; `starts.len >= points.len + 1`, `scratch` as
// for `voronoi_cell`.
fn voronoi_from_delaunay(points: []const Point, triangles: []const usize, written: usize, lo: Point, hi: Point, cells: []Point, starts: []usize, scratch: []Point) -> err {
    if starts.len < points.len + 1usize { ret TooSmall }
    var pos = 0usize
    var i = 0usize
    while i < points.len {
        starts[i] = pos
        let (m, e) = voronoi_cell(points, triangles, written, i, lo, hi, cells[pos..], scratch)
        if e != ok { ret e }
        pos += m
        i += 1usize
    }
    starts[points.len] = pos
    ret ok
}

// The Voronoi diagram of `points` clipped to the box: Delaunay (`triangles`
// and `scratch` of `6 * points.len`) then its dual into `cells`/`starts`.
fn voronoi(points: []const Point, lo: Point, hi: Point, cells: []Point, starts: []usize, triangles: []usize, scratch: []usize, cell_scratch: []Point) -> err {
    let (written, e) = delaunay(points, triangles, scratch)
    if e != ok { ret e }
    ret voronoi_from_delaunay(points, triangles, written, lo, hi, cells, starts, cell_scratch)
}

// One Lloyd iteration: `out[i]` is the centroid of site `i`'s cell clipped to
// the box (the site itself when the cell is empty). `scratch.len >= 2 * (6 * points.len + 16)`.
fn lloyd_relax(points: []const Point, lo: Point, hi: Point, out: []Point, triangles: []usize, tri_scratch: []usize, scratch: []Point) -> err {
    if out.len < points.len { ret TooSmall }
    let (written, e) = delaunay(points, triangles, tri_scratch)
    if e != ok { ret e }
    let half = scratch.len / 2usize
    var i = 0usize
    while i < points.len {
        let (m, ce) = voronoi_cell(points, triangles, written, i, lo, hi, scratch[..half], scratch[half..])
        if ce != ok { ret ce }
        out[i] = points[i]
        if polygon_area(scratch[..m]) > 0.0f64 { out[i] = polygon_centroid(scratch[..m]) }
        i += 1usize
    }
    ret ok
}

// The area centroid of a polygon (its first point when the area is zero).
fn polygon_centroid(polygon: []const Point) -> Point {
    var cx = 0.0f64
    var cy = 0.0f64
    var twice = 0.0f64
    var i = 0usize
    while i < polygon.len {
        let j = (i + 1usize) % polygon.len
        let w = polygon[i].x * polygon[j].y - polygon[j].x * polygon[i].y
        cx += (polygon[i].x + polygon[j].x) * w
        cy += (polygon[i].y + polygon[j].y) * w
        twice += w
        i += 1usize
    }
    if twice == 0.0f64 {
        if polygon.len == 0usize { ret Point { x: 0.0f64, y: 0.0f64 } }
        ret polygon[0usize]
    }
    ret Point { x: cx / (3.0f64 * twice), y: cy / (3.0f64 * twice) }
}

fn lowest(polygon: []const Point) -> usize {
    var best = 0usize
    var i = 1usize
    while i < polygon.len {
        if polygon[i].y < polygon[best].y || (polygon[i].y == polygon[best].y && polygon[i].x < polygon[best].x) { best = i }
        i += 1usize
    }
    ret best
}

// The Minkowski sum of two convex counter-clockwise polygons by merging their
// edges by angle, starting from the sum of their lowest points;
// `out.len >= a.len + b.len`.
fn minkowski_sum(a: []const Point, b: []const Point, out: []Point) -> (usize, err) {
    let na = a.len
    let nb = b.len
    if out.len < na + nb { ret (0usize, TooSmall) }
    if na < 3usize || nb < 3usize || !is_convex(a) || !is_convex(b) || polygon_area(a) <= 0.0f64 || polygon_area(b) <= 0.0f64 { ret (0usize, Invalid) }
    let ia = lowest(a)
    let ib = lowest(b)
    var i = 0usize
    var j = 0usize
    var m = 0usize
    while i < na || j < nb {
        let pa = a[(ia + i) % na]
        let pb = b[(ib + j) % nb]
        out[m] = Point { x: pa.x + pb.x, y: pa.y + pb.y }
        m += 1usize
        let qa = a[(ia + i + 1usize) % na]
        let qb = b[(ib + j + 1usize) % nb]
        let cross = (qa.x - pa.x) * (qb.y - pb.y) - (qa.y - pa.y) * (qb.x - pb.x)
        if i >= na {
            j += 1usize
        } else if j >= nb {
            i += 1usize
        } else {
            if cross >= 0.0f64 { i += 1usize }
            if cross <= 0.0f64 { j += 1usize }
        }
    }
    ret (m, ok)
}

fn reverse_points(points: []Point) {
    var i = 0usize
    var j = points.len
    while i + 1usize < j {
        j -= 1usize
        let swap = points[i]
        points[i] = points[j]
        points[j] = swap
        i += 1usize
    }
}

// Appends `polygon` counter-clockwise as component `count`; answers `count + 1`.
fn emit_polygon(polygon: []const Point, out: []Point, starts: []usize, count: usize) -> (usize, err) {
    let pos = starts[count]
    if pos + polygon.len > out.len || count + 1usize >= starts.len { ret (count, TooSmall) }
    var i = 0usize
    while i < polygon.len {
        out[pos + i] = polygon[i]
        i += 1usize
    }
    if polygon_area(polygon) < 0.0f64 { reverse_points(out[pos..pos + polygon.len]) }
    starts[count + 1usize] = pos + polygon.len
    ret (count + 1usize, ok)
}

// Links crossing `node` into the ring after vertex `head`, in parameter order.
fn link_after(nodes: []Node, head: usize, node: usize) {
    var cur = head
    while nodes[nodes[cur].after].crossing && nodes[nodes[cur].after].alpha < nodes[node].alpha { cur = nodes[cur].after }
    let following = nodes[cur].after
    nodes[node].after = following
    nodes[node].before = cur
    nodes[following].before = node
    nodes[cur].after = node
}

// Marks each crossing on the ring at `head` as an entry into `other` or an
// exit from it, alternating from whether the head vertex lies inside.
fn mark_entries(nodes: []Node, head: usize, other: []const Point, invert: bool) {
    var entry = !point_in_polygon(other, nodes[head].p)
    if invert { entry = !entry }
    var n = nodes[head].after
    while n != head {
        if nodes[n].crossing {
            nodes[n].entry = entry
            entry = !entry
        }
        n = nodes[n].after
    }
}

// Greiner-Hormann booleans of two simple polygons in either winding (no holes).
// Components come out counter-clockwise, concatenated in `out` with
// `starts[c]..starts[c + 1]` delimiting component `c`; answers their count.
// `nodes` needs a slot per input point plus two per crossing. Degenerate input
// (a vertex on the other boundary, collinear overlapping edges) is `Invalid`,
// as is a difference that would leave a hole; a union whose hole is a
// separate component comes out with that component reversed to
// counter-clockwise as well.
fn polygon_boolean(a: []const Point, b: []const Point, op: Op, out: []Point, starts: []usize, nodes: []Node) -> (usize, err) {
    let na = a.len
    let nb = b.len
    if na < 3usize || nb < 3usize { ret (0usize, Invalid) }
    if nodes.len < na + nb || starts.len < 1usize { ret (0usize, TooSmall) }
    var i = 0usize
    while i < na + nb {
        if i < na {
            nodes[i] = Node { p: a[i], alpha: 0.0f64, crossing: false, entry: false, visited: false, after: (i + 1usize) % na, before: (i + na - 1usize) % na, neighbor: i }
        } else {
            let k = i - na
            nodes[i] = Node { p: b[k], alpha: 0.0f64, crossing: false, entry: false, visited: false, after: na + (k + 1usize) % nb, before: na + (k + nb - 1usize) % nb, neighbor: i }
        }
        i += 1usize
    }
    var used = na + nb
    i = 0usize
    while i < na {
        let p = a[i]
        let q = a[(i + 1usize) % na]
        var j = 0usize
        while j < nb {
            let r = b[j]
            let s = b[(j + 1usize) % nb]
            let denominator = (q.x - p.x) * (s.y - r.y) - (q.y - p.y) * (s.x - r.x)
            if denominator == 0.0f64 {
                if segments_intersect(p, q, r, s) { ret (0usize, Invalid) }
            } else {
                let t = ((r.x - p.x) * (s.y - r.y) - (r.y - p.y) * (s.x - r.x)) / denominator
                let u = ((r.x - p.x) * (q.y - p.y) - (r.y - p.y) * (q.x - p.x)) / denominator
                if t >= 0.0f64 && t <= 1.0f64 && u >= 0.0f64 && u <= 1.0f64 {
                    if t == 0.0f64 || t == 1.0f64 || u == 0.0f64 || u == 1.0f64 { ret (0usize, Invalid) }
                    if used + 2usize > nodes.len { ret (0usize, TooSmall) }
                    let x = Point { x: p.x + t * (q.x - p.x), y: p.y + t * (q.y - p.y) }
                    nodes[used] = Node { p: x, alpha: t, crossing: true, entry: false, visited: false, after: 0usize, before: 0usize, neighbor: used + 1usize }
                    nodes[used + 1usize] = Node { p: x, alpha: u, crossing: true, entry: false, visited: false, after: 0usize, before: 0usize, neighbor: used }
                    link_after(nodes, i, used)
                    link_after(nodes, na + j, used + 1usize)
                    used += 2usize
                }
            }
            j += 1usize
        }
        i += 1usize
    }
    starts[0usize] = 0usize
    var count = 0usize
    if used == na + nb {
        let a_in_b = point_in_polygon(b, a[0usize])
        let b_in_a = point_in_polygon(a, b[0usize])
        var want_a = !a_in_b
        var want_b = false
        if op == .Union { want_b = !b_in_a }
        if op == .Intersection {
            want_a = a_in_b
            want_b = b_in_a
        }
        if op == .Difference && b_in_a { ret (0usize, Invalid) }
        if want_a {
            let (grown, e) = emit_polygon(a, out, starts, count)
            if e != ok { ret (0usize, e) }
            count = grown
        }
        if want_b {
            let (grown, e) = emit_polygon(b, out, starts, count)
            if e != ok { ret (0usize, e) }
            count = grown
        }
        ret (count, ok)
    }
    mark_entries(nodes, 0usize, b, op != .Intersection)
    mark_entries(nodes, na, a, op == .Union)
    var pos = 0usize
    var start = na + nb
    while start < used {
        if !nodes[start].visited {
            let first = pos
            var cur = start
            var guard = 0usize
            while guard < 2usize * used {
                guard += 1usize
                nodes[cur].visited = true
                nodes[nodes[cur].neighbor].visited = true
                let forward = nodes[cur].entry
                while true {
                    if forward { cur = nodes[cur].after } else { cur = nodes[cur].before }
                    if pos >= out.len { ret (0usize, TooSmall) }
                    out[pos] = nodes[cur].p
                    pos += 1usize
                    if nodes[cur].crossing { break }
                }
                cur = nodes[cur].neighbor
                if cur == start { break }
            }
            if count + 1usize >= starts.len { ret (0usize, TooSmall) }
            if polygon_area(out[first..pos]) < 0.0f64 { reverse_points(out[first..pos]) }
            count += 1usize
            starts[count] = pos
        }
        start += 1usize
    }
    ret (count, ok)
}

// The unit normal of edge `a b` on the outside of a polygon whose winding has
// `sign` (`1` counter-clockwise, `-1` clockwise).
fn edge_normal(a: Point, b: Point, sign: f64) -> (f64, f64, bool) {
    let ex = b.x - a.x
    let ey = b.y - a.y
    let length = sqrt_f64(ex * ex + ey * ey)
    if length == 0.0f64 { ret (0.0f64, 0.0f64, false) }
    ret (ey / length * sign, (0.0f64 - ex) / length * sign, true)
}

// Offsets a simple polygon by `d` (outward when positive, in either winding)
// with miter joins; `out.len >= polygon.len`. `Invalid` on a zero-length edge
// or a vertex folding straight back on itself.
// ponytail: no self-intersection cleanup; insets past half a feature's width
// cross themselves (a Vatti/Clipper union would remove those loops).
fn polygon_offset(polygon: []const Point, d: f64, out: []Point) -> (usize, err) {
    let n = polygon.len
    if n < 3usize { ret (0usize, Invalid) }
    if out.len < n { ret (0usize, TooSmall) }
    var sign = 1.0f64
    if polygon_area(polygon) < 0.0f64 { sign = 0.0f64 - 1.0f64 }
    var i = 0usize
    while i < n {
        let p0 = polygon[(i + n - 1usize) % n]
        let p1 = polygon[i]
        let p2 = polygon[(i + 1usize) % n]
        let (n0x, n0y, fine0) = edge_normal(p0, p1, sign)
        let (n1x, n1y, fine1) = edge_normal(p1, p2, sign)
        let k = 1.0f64 + n0x * n1x + n0y * n1y
        if !fine0 || !fine1 || k < 0.000000000001f64 { ret (0usize, Invalid) }
        out[i] = Point { x: p1.x + d * (n0x + n1x) / k, y: p1.y + d * (n0y + n1y) / k }
        i += 1usize
    }
    ret (n, ok)
}

// Every pair of `segments` (consecutive point pairs) that meet: `pairs` gets
// the two segment indices, `crossings` the meeting point (an overlapping
// endpoint for collinear pairs); answers the count.
// ponytail: O(n^2) pairwise tests; a Bentley-Ottmann sweep reaches O((n + k) log n).
fn segment_intersections(segments: []const Point, pairs: []usize, crossings: []Point) -> (usize, err) {
    let n = segments.len / 2usize
    var count = 0usize
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let a = segments[2usize * i]
            let b = segments[2usize * i + 1usize]
            let c = segments[2usize * j]
            let d = segments[2usize * j + 1usize]
            if segments_intersect(a, b, c, d) {
                if 2usize * count + 2usize > pairs.len || count >= crossings.len { ret (count, TooSmall) }
                let (x, crossed) = segment_intersection(a, b, c, d)
                var meeting = x
                if !crossed {
                    meeting = a
                    if on_segment(a, b, c) { meeting = c } else if on_segment(a, b, d) { meeting = d }
                }
                pairs[2usize * count] = i
                pairs[2usize * count + 1usize] = j
                crossings[count] = meeting
                count += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (count, ok)
}

// The sweep order: `p` above `q` by y, ties to the left.
fn above(p: Point, q: Point) -> bool { ret p.y > q.y || (p.y == q.y && p.x < q.x) }

// Whether `polygon` is y-monotone: exactly one local top and one local bottom
// along its boundary.
fn is_monotone(polygon: []const Point) -> bool {
    let n = polygon.len
    if n < 3usize { ret false }
    var tops = 0usize
    var bottoms = 0usize
    var i = 0usize
    while i < n {
        let a = polygon[(i + n - 1usize) % n]
        let b = polygon[i]
        let c = polygon[(i + 1usize) % n]
        if above(b, a) && above(b, c) { tops += 1usize }
        if above(a, b) && above(c, b) { bottoms += 1usize }
        i += 1usize
    }
    ret tops == 1usize && bottoms == 1usize
}

fn emit_triangle(points: []const Point, triangles: []usize, written: usize, a: usize, b: usize, c: usize) -> usize {
    triangles[written] = a
    triangles[written + 1usize] = b
    triangles[written + 2usize] = c
    if orient(points[a], points[b], points[c]) < 0.0f64 {
        triangles[written + 1usize] = c
        triangles[written + 2usize] = b
    }
    ret written + 3usize
}

// Triangulates a counter-clockwise y-monotone polygon in linear time after
// merging its two chains by height: `triangles` gets `3 * (n - 2)` indices,
// `scratch.len >= 2 * n`. Answers the count written.
fn triangulate_monotone(polygon: []const Point, triangles: []usize, scratch: []usize) -> (usize, err) {
    let n = polygon.len
    if n < 3usize || !is_monotone(polygon) || polygon_area(polygon) <= 0.0f64 { ret (0usize, Invalid) }
    if triangles.len < 3usize * (n - 2usize) || scratch.len < 2usize * n { ret (0usize, TooSmall) }
    var top = 0usize
    var bottom = 0usize
    var i = 1usize
    while i < n {
        if above(polygon[i], polygon[top]) { top = i }
        if above(polygon[bottom], polygon[i]) { bottom = i }
        i += 1usize
    }
    // The left chain runs forward from the top, the right chain backward.
    scratch[0usize] = top
    var filled = 1usize
    var l = (top + 1usize) % n
    var r = (top + n - 1usize) % n
    while l != bottom || r != bottom {
        if r == bottom || (l != bottom && above(polygon[l], polygon[r])) {
            scratch[filled] = l
            l = (l + 1usize) % n
        } else {
            scratch[filled] = r
            r = (r + n - 1usize) % n
        }
        filled += 1usize
    }
    scratch[filled] = bottom
    let left_span = (bottom + n - top) % n
    // `scratch[n..]` is the reflex chain stack.
    scratch[n] = scratch[0usize]
    scratch[n + 1usize] = scratch[1usize]
    var depth = 2usize
    var written = 0usize
    var j = 2usize
    while j + 1usize < n {
        let u = scratch[j]
        let u_left = (u + n - top) % n < left_span
        let top_left = (scratch[n + depth - 1usize] + n - top) % n < left_span
        if u_left != top_left {
            while depth >= 2usize {
                written = emit_triangle(polygon, triangles, written, u, scratch[n + depth - 1usize], scratch[n + depth - 2usize])
                depth -= 1usize
            }
            scratch[n] = scratch[j - 1usize]
            scratch[n + 1usize] = u
            depth = 2usize
        } else {
            var a = scratch[n + depth - 1usize]
            depth -= 1usize
            while depth > 0usize {
                let b = scratch[n + depth - 1usize]
                let o = orient(polygon[u], polygon[a], polygon[b])
                if (u_left && o < 0.0f64) || (!u_left && o > 0.0f64) {
                    written = emit_triangle(polygon, triangles, written, u, a, b)
                    a = b
                    depth -= 1usize
                } else {
                    break
                }
            }
            scratch[n + depth] = a
            scratch[n + depth + 1usize] = u
            depth += 2usize
        }
        j += 1usize
    }
    let last = scratch[n - 1usize]
    var k = 0usize
    while k + 1usize < depth {
        written = emit_triangle(polygon, triangles, written, last, scratch[n + k], scratch[n + k + 1usize])
        k += 1usize
    }
    ret (written, ok)
}
