// Square, isometric and hex coordinates over one integer vocabulary (D249).
//
// Isometric is not a rendering mode, it is a coordinate transform plus a depth order,
// which is most of what 2.5D means in practice. So one `Coord` -- axial `q`, `r` -- and
// one set of operations answer for all four shapes, and a game changes its look by
// changing the `Shape` it passes rather than its map, its pathfinding or its AI.
//
// Everything is integer. `to_world` answers in Q16 world units; `from_world` takes them
// and floors, hex through cube rounding, so the tile under a point is the same tile on
// every machine.
//
// Square and isometric share a grid: four neighbours, Manhattan distance, and rings that
// are diamonds. Hex has six neighbours and hex distance. The two are kept consistent --
// a ring is always the cells at exactly `radius`, under whichever distance the shape
// uses -- rather than mixing Manhattan distance with a square ring.

use e.mem
use e.math.fixed

type Shape = enum u8 { Square, IsoDiamond, HexPointy, HexFlat }

type Coord = struct {
    q: i32,
    r: i32,
}

error Bounds

fn coord(q: i32, r: i32) -> Coord {
    ret Coord { q: q, r: r }
}

fn equal(a: Coord, b: Coord) -> bool {
    ret a.q == b.q && a.r == b.r
}

fn hexed(s: Shape) -> bool {
    ret s == .HexPointy || s == .HexFlat
}

// Truncating division rounds toward zero, which would fold the tile left of the origin
// onto the tile right of it. Tiles run in both directions, so the floor is what is meant.
fn floor_div(a: i64, b: i64) -> i64 {
    if b == 0i64 { ret 0i64 }
    var quotient = a / b
    if (a % b != 0i64) && ((a < 0i64) != (b < 0i64)) { quotient = quotient - 1i64 }
    ret quotient
}

fn abs64(v: i64) -> i64 {
    if v < 0i64 { ret 0i64 - v }
    ret v
}

// A Q16 value to the whole number below it, and to the nearest.
fn q16_floor(v: i64) -> i64 {
    ret v >> 16u32
}

fn q16_round(v: i64) -> i64 {
    ret (v + 32768i64) >> 16u32
}

fn to_world(s: Shape, c: Coord, tile_w: u32, tile_h: u32) -> (fixed.Fx, fixed.Fx) {
    let width = i64(tile_w)
    let height = i64(tile_h)
    let q = i64(c.q)
    let r = i64(c.r)
    if s == .Square {
        ret (i32((q * width) << 16u32), i32((r * height) << 16u32))
    }
    if s == .IsoDiamond {
        // The diamond: one step in q goes right and down, one in r goes left and down.
        ret (i32(((q - r) * width << 16u32) / 2i64), i32(((q + r) * height << 16u32) / 2i64))
    }
    if s == .HexPointy {
        // Rows overlap by a quarter of a hex, and every other row is offset by a half.
        ret (i32((width * (q * 2i64 + r) << 16u32) / 2i64), i32((height * r * 3i64 << 16u32) / 4i64))
    }
    ret (i32((width * q * 3i64 << 16u32) / 4i64), i32((height * (r * 2i64 + q) << 16u32) / 2i64))
}

// Cube coordinates sum to zero. Rounding each of the three independently can break that,
// so the one that moved furthest is recomputed from the other two.
fn cube_round(qf: i64, rf: i64) -> Coord {
    let sf = 0i64 - qf - rf
    var rq = q16_round(qf)
    var rr = q16_round(rf)
    var rs = q16_round(sf)
    let dq = abs64((rq << 16u32) - qf)
    let dr = abs64((rr << 16u32) - rf)
    let ds = abs64((rs << 16u32) - sf)
    if dq > dr && dq > ds {
        rq = 0i64 - rr - rs
    } else {
        if dr > ds { rr = 0i64 - rq - rs }
    }
    ret Coord { q: i32(rq), r: i32(rr) }
}

fn from_world(s: Shape, wx: fixed.Fx, wy: fixed.Fx, tile_w: u32, tile_h: u32) -> Coord {
    let width = i64(tile_w)
    let height = i64(tile_h)
    if width == 0i64 || height == 0i64 { ret Coord { q: 0i32, r: 0i32 } }
    let x = i64(wx)
    let y = i64(wy)
    if s == .Square {
        ret Coord { q: i32(floor_div(x, width << 16u32)), r: i32(floor_div(y, height << 16u32)) }
    }
    if s == .IsoDiamond {
        // Undo the diamond: halve-widths along each axis, then rotate back.
        let along = floor_div(x * 2i64 << 16u32, width << 16u32)
        let down = floor_div(y * 2i64 << 16u32, height << 16u32)
        ret Coord { q: i32(q16_floor((along + down) / 2i64)), r: i32(q16_floor((down - along) / 2i64)) }
    }
    if s == .HexPointy {
        let rf = floor_div(y * 4i64 << 16u32, height * 3i64 << 16u32)
        let qf = floor_div(x << 16u32, width << 16u32) - rf / 2i64
        ret cube_round(qf, rf)
    }
    let qf = floor_div(x * 4i64 << 16u32, width * 3i64 << 16u32)
    let rf = floor_div(y << 16u32, height << 16u32) - qf / 2i64
    ret cube_round(qf, rf)
}

// Four for a square or a diamond, six for a hex, always in the same order so a walk is
// the same walk everywhere.
fn neighbours(s: Shape, c: Coord, out: []Coord) -> (usize, err) {
    if hexed(s) {
        if out.len < 6usize { ret (0usize, Bounds) }
        out[0usize] = Coord { q: c.q + 1i32, r: c.r }
        out[1usize] = Coord { q: c.q + 1i32, r: c.r - 1i32 }
        out[2usize] = Coord { q: c.q, r: c.r - 1i32 }
        out[3usize] = Coord { q: c.q - 1i32, r: c.r }
        out[4usize] = Coord { q: c.q - 1i32, r: c.r + 1i32 }
        out[5usize] = Coord { q: c.q, r: c.r + 1i32 }
        ret (6usize, ok)
    }
    if out.len < 4usize { ret (0usize, Bounds) }
    out[0usize] = Coord { q: c.q + 1i32, r: c.r }
    out[1usize] = Coord { q: c.q, r: c.r + 1i32 }
    out[2usize] = Coord { q: c.q - 1i32, r: c.r }
    out[3usize] = Coord { q: c.q, r: c.r - 1i32 }
    ret (4usize, ok)
}

fn distance(s: Shape, a: Coord, b: Coord) -> u32 {
    let dq = i64(b.q) - i64(a.q)
    let dr = i64(b.r) - i64(a.r)
    if hexed(s) {
        ret u32((abs64(dq) + abs64(dq + dr) + abs64(dr)) / 2i64)
    }
    ret u32(abs64(dq) + abs64(dr))
}

// The painter's key: larger is drawn later. The row (or the diagonal, for a diamond)
// decides, and elevation breaks ties inside it, so a raised tile sits in front of the
// flat ground it shares a row with.
fn depth(s: Shape, c: Coord, elevation: u8) -> i32 {
    var base = c.r
    if s == .IsoDiamond { base = c.q + c.r }
    if s == .HexFlat { base = c.q }
    ret base * 256i32 + i32(elevation)
}

fn step_toward(value: i32, goal: i32) -> i32 {
    if value < goal { ret value + 1i32 }
    if value > goal { ret value - 1i32 }
    ret value
}

// Tile counts, not fixed-point values, so this rather than `fixed.abs`.
fn abs32(v: i32) -> i32 {
    if v < 0i32 { ret 0i32 - v }
    ret v
}

// Both endpoints included. A square or diamond walks the axes, a hex interpolates in
// cube space and rounds, which is the only way to keep the line on the lattice.
fn line(s: Shape, a: Coord, b: Coord, out: []Coord) -> (usize, err) {
    let steps = usize(distance(s, a, b))
    if out.len < steps + 1usize { ret (0usize, Bounds) }
    if steps == 0usize {
        out[0usize] = a
        ret (1usize, ok)
    }
    if hexed(s) {
        var at = 0usize
        while at <= steps {
            let t = (i64(at) << 16u32) / i64(steps)
            let qf = (i64(a.q) << 16u32) + (((i64(b.q) - i64(a.q)) * t))
            let rf = (i64(a.r) << 16u32) + (((i64(b.r) - i64(a.r)) * t))
            out[at] = cube_round(qf, rf)
            at += 1usize
        }
        ret (steps + 1usize, ok)
    }
    var cursor = a
    var at = 0usize
    while at <= steps {
        out[at] = cursor
        if cursor.q != b.q {
            cursor = Coord { q: step_toward(cursor.q, b.q), r: cursor.r }
        } else {
            cursor = Coord { q: cursor.q, r: step_toward(cursor.r, b.r) }
        }
        at += 1usize
    }
    ret (steps + 1usize, ok)
}

// Exactly `radius` away, under whichever distance the shape uses.
fn ring(s: Shape, centre: Coord, radius: u32, out: []Coord) -> (usize, err) {
    if radius == 0u32 {
        if out.len < 1usize { ret (0usize, Bounds) }
        out[0usize] = centre
        ret (1usize, ok)
    }
    var count = 0usize
    let reach = i32(radius)
    if hexed(s) {
        var cursor = Coord { q: centre.q - reach, r: centre.r + reach }
        var side = 0usize
        var deltas: [12]i32 = zero
        deltas[0usize] = 1i32
        deltas[1usize] = 0i32
        deltas[2usize] = 1i32
        deltas[3usize] = -1i32
        deltas[4usize] = 0i32
        deltas[5usize] = -1i32
        deltas[6usize] = -1i32
        deltas[7usize] = 0i32
        deltas[8usize] = -1i32
        deltas[9usize] = 1i32
        deltas[10usize] = 0i32
        deltas[11usize] = 1i32
        while side < 6usize {
            var step = 0i32
            while step < reach {
                if count == out.len { ret (0usize, Bounds) }
                out[count] = cursor
                count += 1usize
                cursor = Coord { q: cursor.q + deltas[side * 2usize], r: cursor.r + deltas[side * 2usize + 1usize] }
                step += 1i32
            }
            side += 1usize
        }
        ret (count, ok)
    }
    var dq = 0i32 - reach
    while dq <= reach {
        let remaining = reach - abs32(dq)
        var dr = 0i32 - remaining
        while dr <= remaining {
            if abs32(dq) + abs32(dr) == reach {
                if count == out.len { ret (0usize, Bounds) }
                out[count] = Coord { q: centre.q + dq, r: centre.r + dr }
                count += 1usize
            }
            dr += 1i32
        }
        dq += 1i32
    }
    ret (count, ok)
}

// Everything within `radius`, centre included, in a stable order.
fn area(s: Shape, centre: Coord, radius: u32, out: []Coord) -> (usize, err) {
    var count = 0usize
    let reach = i32(radius)
    var dq = 0i32 - reach
    while dq <= reach {
        var dr = 0i32 - reach
        while dr <= reach {
            let candidate = Coord { q: centre.q + dq, r: centre.r + dr }
            if distance(s, centre, candidate) <= radius {
                if count == out.len { ret (0usize, Bounds) }
                out[count] = candidate
                count += 1usize
            }
            dr += 1i32
        }
        dq += 1i32
    }
    ret (count, ok)
}
