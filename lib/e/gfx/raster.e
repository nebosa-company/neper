// Scan conversion into caller pixel lists, nothing drawn: every routine appends
// the pixels it would touch to `out` and answers how many, or `TooSmall` with
// `out` full and the count so far lost. `line` is Bresenham in every octant,
// walked from `(x0, y0)` to `(x1, y1)`; `line_aa` is Xiaolin Wu over sub-pixel
// end points, each pixel with its coverage in `0..1` (the two pixels beside the
// line at each step, and the end-point pairs weighted by the gap to the pixel
// centre); `circle` and `ellipse` are the midpoint walks, eight and four
// symmetric pixels per step, with the pixels the symmetry would repeat (on
// an axis, on a diagonal) written once. `fill_triangle` samples pixel centres
// `(x + 0.5, y + 0.5)` inside the bounding box with edge functions under the
// top-left rule, so two triangles sharing an edge never both own a pixel on it
// and never both leave one; the winding does not matter.

type Pixel = struct { x: i32, y: i32 }
type Coverage = struct { x: i32, y: i32, coverage: f64 }
error TooSmall

fn push(out: []Pixel, n: *usize, x: i32, y: i32) -> err {
    if *n >= out.len { ret TooSmall }
    out[*n] = Pixel { x: x, y: y }
    *n += 1usize
    ret ok
}

fn abs32(v: i32) -> i32 {
    if v < 0i32 { ret 0i32 - v }
    ret v
}

fn line(x0: i32, y0: i32, x1: i32, y1: i32, out: []Pixel) -> (usize, err) {
    var n = 0usize
    let dx = abs32(x1 - x0)
    let dy = 0i32 - abs32(y1 - y0)
    var sx = 1i32
    if x0 > x1 { sx = -1i32 }
    var sy = 1i32
    if y0 > y1 { sy = -1i32 }
    var x = x0
    var y = y0
    var e = dx + dy
    while true {
        if push(out, &n, x, y) != ok { ret (0usize, TooSmall) }
        if x == x1 && y == y1 { ret (n, ok) }
        let e2 = 2i32 * e
        if e2 >= dy {
            e += dy
            x += sx
        }
        if e2 <= dx {
            e += dx
            y += sy
        }
    }
    ret (n, ok)
}

fn push_aa(out: []Coverage, n: *usize, x: i32, y: i32, c: f64) -> err {
    if *n >= out.len { ret TooSmall }
    out[*n] = Coverage { x: x, y: y, coverage: c }
    *n += 1usize
    ret ok
}

fn floor64(v: f64) -> f64 {
    var f = f64(i64(v))
    if f > v { f = f - 1.0f64 }
    ret f
}

fn round64(v: f64) -> f64 { ret floor64(v + 0.5f64) }

fn fpart(v: f64) -> f64 { ret v - floor64(v) }

fn rfpart(v: f64) -> f64 { ret 1.0f64 - fpart(v) }

// Writes the pair of pixels at major coordinate `major` (an integer) straddling
// minor coordinate `minor`, weighted by `gap`; `steep` swaps the axes back.
fn pair(out: []Coverage, n: *usize, steep: bool, major: f64, minor: f64, gap: f64) -> err {
    let lo = floor64(minor)
    let a = rfpart(minor) * gap
    let b = fpart(minor) * gap
    let m = i32(i64(major))
    let l = i32(i64(lo))
    if steep {
        let first = push_aa(out, n, l, m, a)
        if first != ok { ret first }
        ret push_aa(out, n, l + 1i32, m, b)
    }
    let first = push_aa(out, n, m, l, a)
    if first != ok { ret first }
    ret push_aa(out, n, m, l + 1i32, b)
}

fn line_aa(x0: f64, y0: f64, x1: f64, y1: f64, out: []Coverage) -> (usize, err) {
    var n = 0usize
    var ax = x0
    var ay = y0
    var bx = x1
    var by = y1
    var adx = bx - ax
    if adx < 0.0f64 { adx = 0.0f64 - adx }
    var ady = by - ay
    if ady < 0.0f64 { ady = 0.0f64 - ady }
    let steep = ady > adx
    if steep {
        var t = ax
        ax = ay
        ay = t
        t = bx
        bx = by
        by = t
    }
    if ax > bx {
        var t = ax
        ax = bx
        bx = t
        t = ay
        ay = by
        by = t
    }
    let dx = bx - ax
    let dy = by - ay
    var gradient = 1.0f64
    if dx != 0.0f64 { gradient = dy / dx }
    let xend0 = round64(ax)
    let yend0 = ay + gradient * (xend0 - ax)
    let xgap0 = rfpart(ax + 0.5f64)
    if pair(out, &n, steep, xend0, yend0, xgap0) != ok { ret (0usize, TooSmall) }
    var intery = yend0 + gradient
    let xend1 = round64(bx)
    let yend1 = by + gradient * (xend1 - bx)
    let xgap1 = fpart(bx + 0.5f64)
    var x = xend0 + 1.0f64
    while x <= xend1 - 1.0f64 {
        if pair(out, &n, steep, x, intery, 1.0f64) != ok { ret (0usize, TooSmall) }
        intery += gradient
        x += 1.0f64
    }
    if pair(out, &n, steep, xend1, yend1, xgap1) != ok { ret (0usize, TooSmall) }
    ret (n, ok)
}

// The eight symmetric pixels of `(x, y)` about the centre, duplicates on the
// axes and diagonals written once.
fn octants(out: []Pixel, n: *usize, cx: i32, cy: i32, x: i32, y: i32) -> err {
    if push(out, n, cx + x, cy + y) != ok { ret TooSmall }
    if y != 0i32 {
        if push(out, n, cx + x, cy - y) != ok { ret TooSmall }
    }
    if x != 0i32 {
        if push(out, n, cx - x, cy + y) != ok { ret TooSmall }
        if y != 0i32 {
            if push(out, n, cx - x, cy - y) != ok { ret TooSmall }
        }
    }
    if x == y { ret ok }
    if push(out, n, cx + y, cy + x) != ok { ret TooSmall }
    if x != 0i32 {
        if push(out, n, cx + y, cy - x) != ok { ret TooSmall }
    }
    if y != 0i32 {
        if push(out, n, cx - y, cy + x) != ok { ret TooSmall }
        if x != 0i32 {
            if push(out, n, cx - y, cy - x) != ok { ret TooSmall }
        }
    }
    ret ok
}

fn circle(cx: i32, cy: i32, radius: i32, out: []Pixel) -> (usize, err) {
    var n = 0usize
    if radius < 0i32 { ret (0usize, ok) }
    var x = radius
    var y = 0i32
    var d = 1i32 - radius
    while x >= y {
        if octants(out, &n, cx, cy, x, y) != ok { ret (0usize, TooSmall) }
        y += 1i32
        if d < 0i32 {
            d += 2i32 * y + 1i32
        } else {
            x -= 1i32
            d += 2i32 * (y - x) + 1i32
        }
    }
    ret (n, ok)
}

// The four symmetric pixels of `(x, y)`, duplicates on the axes written once.
fn quadrants(out: []Pixel, n: *usize, cx: i32, cy: i32, x: i32, y: i32) -> err {
    if push(out, n, cx + x, cy + y) != ok { ret TooSmall }
    if x != 0i32 {
        if push(out, n, cx - x, cy + y) != ok { ret TooSmall }
    }
    if y != 0i32 {
        if push(out, n, cx + x, cy - y) != ok { ret TooSmall }
        if x != 0i32 {
            if push(out, n, cx - x, cy - y) != ok { ret TooSmall }
        }
    }
    ret ok
}

fn ellipse(cx: i32, cy: i32, rx: i32, ry: i32, out: []Pixel) -> (usize, err) {
    var n = 0usize
    if rx < 0i32 || ry < 0i32 { ret (0usize, ok) }
    let a2 = i64(rx) * i64(rx)
    let b2 = i64(ry) * i64(ry)
    var x = 0i64
    var y = i64(ry)
    // Region 1: the slope is above -1, x advances every step.
    var d1 = b2 - a2 * i64(ry) + a2 / 4i64
    var dx = 0i64
    var dy = 2i64 * a2 * y
    while dx < dy {
        if quadrants(out, &n, cx, cy, i32(x), i32(y)) != ok { ret (0usize, TooSmall) }
        x += 1i64
        dx += 2i64 * b2
        if d1 < 0i64 {
            d1 += dx + b2
        } else {
            y -= 1i64
            dy -= 2i64 * a2
            d1 += dx - dy + b2
        }
    }
    // Region 2: y advances every step.
    var d2 = b2 * (x * x + x) + b2 / 4i64 + a2 * (y - 1i64) * (y - 1i64) - a2 * b2
    while y >= 0i64 {
        if quadrants(out, &n, cx, cy, i32(x), i32(y)) != ok { ret (0usize, TooSmall) }
        y -= 1i64
        dy -= 2i64 * a2
        if d2 > 0i64 {
            d2 += a2 - dy
        } else {
            x += 1i64
            dx += 2i64 * b2
            d2 += dx - dy + a2
        }
    }
    ret (n, ok)
}

fn edge(ax: f64, ay: f64, bx: f64, by: f64, px: f64, py: f64) -> f64 {
    ret (bx - ax) * (py - ay) - (by - ay) * (px - ax)
}

// Whether the edge from `a` to `b` is a top or left edge of a counter-clockwise
// triangle in a y-down frame: left when it goes up, top when it is flat and goes right.
fn top_left(ax: f64, ay: f64, bx: f64, by: f64) -> bool {
    ret (by < ay) || (by == ay && bx > ax)
}

fn fill_triangle(x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64, out: []Pixel) -> (usize, err) {
    var n = 0usize
    var ax = x0
    var ay = y0
    var bx = x1
    var by = y1
    let cx = x2
    let cy = y2
    let area = edge(ax, ay, bx, by, cx, cy)
    if area == 0.0f64 { ret (0usize, ok) }
    if area < 0.0f64 {
        var t = ax
        ax = bx
        bx = t
        t = ay
        ay = by
        by = t
    }
    var min_x = ax
    if bx < min_x { min_x = bx }
    if cx < min_x { min_x = cx }
    var max_x = ax
    if bx > max_x { max_x = bx }
    if cx > max_x { max_x = cx }
    var min_y = ay
    if by < min_y { min_y = by }
    if cy < min_y { min_y = cy }
    var max_y = ay
    if by > max_y { max_y = by }
    if cy > max_y { max_y = cy }
    let tl0 = top_left(ax, ay, bx, by)
    let tl1 = top_left(bx, by, cx, cy)
    let tl2 = top_left(cx, cy, ax, ay)
    var y = i64(floor64(min_y))
    let y_end = i64(floor64(max_y))
    let x_start = i64(floor64(min_x))
    let x_end = i64(floor64(max_x))
    while y <= y_end {
        let py = f64(y) + 0.5f64
        var x = x_start
        while x <= x_end {
            let px = f64(x) + 0.5f64
            let w0 = edge(ax, ay, bx, by, px, py)
            let w1 = edge(bx, by, cx, cy, px, py)
            let w2 = edge(cx, cy, ax, ay, px, py)
            let in0 = w0 > 0.0f64 || (w0 == 0.0f64 && tl0)
            let in1 = w1 > 0.0f64 || (w1 == 0.0f64 && tl1)
            let in2 = w2 > 0.0f64 || (w2 == 0.0f64 && tl2)
            if in0 && in1 && in2 {
                if push(out, &n, i32(x), i32(y)) != ok { ret (0usize, TooSmall) }
            }
            x += 1i64
        }
        y += 1i64
    }
    ret (n, ok)
}
