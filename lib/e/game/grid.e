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
use e.math
use e.math.fixed

type Shape = enum u8 { Square, IsoDiamond, HexPointy, HexFlat }

type Coord = struct { q: i32, r: i32 }

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


// --- Pathfinding over a `w` x `h` square grid (#126, #1839, #1844) whose
// cells are `Coord { q: column, r: row }` in `[0, w) x [0, h)`; passability is
// a caller callback `passable(ctx, cell)`, and the per-cell arrays (`w * h`
// entries) come from the caller. `NONE` marks an unset parent.

const NONE: u32 = 4294967295u32

fn cell_index(w: usize, c: Coord) -> usize { ret usize(c.r) * w + usize(c.q) }

fn cell_of(w: usize, index: usize) -> Coord { ret Coord { q: i32(index % w), r: i32(index / w) } }

fn inside_grid(w: usize, h: usize, c: Coord) -> bool {
    ret c.q >= 0i32 && c.r >= 0i32 && usize(c.q) < w && usize(c.r) < h
}

// The parent chain from `goal` back to the root into `out`, root first.
fn unwind(w: usize, parent: []const u32, goal: usize, out: []Coord) -> (usize, err) {
    var n = 0usize
    var cur = goal
    while true {
        n += 1usize
        let p = usize(parent[cur])
        if p == cur { break }
        cur = p
    }
    if out.len < n { ret (n, Bounds) }
    var i = n
    cur = goal
    while true {
        i -= 1usize
        out[i] = cell_of(w, cur)
        let p = usize(parent[cur])
        if p == cur { break }
        cur = p
    }
    ret (n, ok)
}

// #126 Lee's algorithm: breadth-first over the four neighbours (in
// `neighbours` order) from `from` to `to`; the shortest path, both ends
// included, into `out`, or 0 cells when there is none. `parent` and
// `queue` need `w * h` entries.
fn path_bfs[Ctx: type](w: usize, h: usize, ctx: *Ctx, passable: fn(*Ctx, Coord) -> bool, from: Coord, to: Coord, parent: []u32, queue: []u32, out: []Coord) -> (usize, err) {
    let total = w * h
    if parent.len < total || queue.len < total { ret (0usize, Bounds) }
    if !inside_grid(w, h, from) || !inside_grid(w, h, to) { ret (0usize, Bounds) }
    if !passable(ctx, from) || !passable(ctx, to) { ret (0usize, ok) }
    var i = 0usize
    while i < total {
        parent[i] = NONE
        i += 1usize
    }
    let start = cell_index(w, from)
    let goal = cell_index(w, to)
    parent[start] = u32(start)
    queue[0usize] = u32(start)
    var head = 0usize
    var tail = 1usize
    while head < tail {
        let cur = usize(queue[head])
        head += 1usize
        if cur == goal {
            let (n, unwind_error) = unwind(w, parent, goal, out)
            ret (n, unwind_error)
        }
        var around: [4]Coord = zero
        let (count, _) = neighbours(.Square, cell_of(w, cur), around[0..])
        var k = 0usize
        while k < count {
            let next_cell = around[k]
            if inside_grid(w, h, next_cell) {
                let index = cell_index(w, next_cell)
                if parent[index] == NONE && passable(ctx, next_cell) {
                    parent[index] = u32(cur)
                    queue[tail] = u32(index)
                    tail += 1usize
                }
            }
            k += 1usize
        }
    }
    ret (0usize, ok)
}

// #1844 The cells a segment between the centres of `a` and `b` passes
// through, in order (Amanatides-Woo traversal; a corner crossing steps in
// `r` first). `|dq| + |dr| + 1` cells.
fn ray_cells(a: Coord, b: Coord, out: []Coord) -> (usize, err) {
    let dq = i64(b.q) - i64(a.q)
    let dr = i64(b.r) - i64(a.r)
    let nq = abs64(dq)
    let nr = abs64(dr)
    let total = usize(nq + nr) + 1usize
    if out.len < total { ret (0usize, Bounds) }
    var step_q = 1i32
    if dq < 0i64 { step_q = -1i32 }
    var step_r = 1i32
    if dr < 0i64 { step_r = -1i32 }
    // Times to the next boundary, scaled by 2 |dq| |dr|: the first crossing
    // sits half a cell away, each further one a whole cell.
    var t_q = nr
    var t_r = nq
    var cur = a
    var n = 0usize
    while n < total {
        out[n] = cur
        n += 1usize
        if n == total { ret (total, ok) }
        if nr == 0i64 || (nq != 0i64 && t_q < t_r) {
            cur = Coord { q: cur.q + step_q, r: cur.r }
            t_q += 2i64 * nr
        } else {
            cur = Coord { q: cur.q, r: cur.r + step_r }
            t_r += 2i64 * nq
        }
    }
    ret (total, ok)
}

// Whether every cell the segment `a`-`b` touches is passable.
fn line_of_sight[Ctx: type](ctx: *Ctx, passable: fn(*Ctx, Coord) -> bool, a: Coord, b: Coord, scratch: []Coord) -> bool {
    let (n, ray_error) = ray_cells(a, b, scratch)
    if ray_error != ok { ret false }
    var i = 0usize
    while i < n {
        if !passable(ctx, scratch[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn euclid(a: Coord, b: Coord) -> f64 {
    let dq = f64(i64(b.q) - i64(a.q))
    let dr = f64(i64(b.r) - i64(a.r))
    ret math.sqrt[f64](dq * dq + dr * dr)
}

fn heap_push(key: []f64, node: []u32, used: *usize, k: f64, v: u32) -> err {
    if *used >= key.len || *used >= node.len { ret Bounds }
    var i = *used
    *used += 1usize
    key[i] = k
    node[i] = v
    while i > 0usize {
        let p = (i - 1usize) / 2usize
        if key[p] <= key[i] { ret ok }
        let held_key = key[p]
        let held_node = node[p]
        key[p] = key[i]
        node[p] = node[i]
        key[i] = held_key
        node[i] = held_node
        i = p
    }
    ret ok
}

fn heap_pop(key: []f64, node: []u32, used: *usize) -> u32 {
    let top = node[0usize]
    *used -= 1usize
    key[0usize] = key[*used]
    node[0usize] = node[*used]
    var i = 0usize
    while true {
        let l = 2usize * i + 1usize
        let r = l + 1usize
        var s = i
        if l < *used && key[l] < key[s] { s = l }
        if r < *used && key[r] < key[s] { s = r }
        if s == i { ret top }
        let held_key = key[s]
        let held_node = node[s]
        key[s] = key[i]
        node[s] = node[i]
        key[i] = held_key
        node[i] = held_node
        i = s
    }
    ret top
}

fn delta_q(k: usize) -> i32 {
    if k == 0usize || k == 4usize || k == 7usize { ret 1i32 }
    if k == 2usize || k == 5usize || k == 6usize { ret -1i32 }
    ret 0i32
}

fn delta_r(k: usize) -> i32 {
    if k == 1usize || k == 4usize || k == 5usize { ret 1i32 }
    if k == 3usize || k == 6usize || k == 7usize { ret -1i32 }
    ret 0i32
}

// #1839 Theta*: A* over the eight neighbours with Euclidean costs where a
// cell whose parent's parent can see it (`line_of_sight` through
// `ray_cells`) hangs off that grandparent instead, so the path is a short
// list of corner waypoints, both ends included, into `out`; 0 cells when
// unreachable. `g`, `parent`, `closed` need `w * h` entries, the heap
// arrays room for every relaxation (`8 * w * h` is always enough), and
// `scratch` `w + h` cells. Answers (waypoints, length).
fn path_theta_star[Ctx: type](w: usize, h: usize, ctx: *Ctx, passable: fn(*Ctx, Coord) -> bool, from: Coord, to: Coord, g: []f64, parent: []u32, closed: []u8, heap_key: []f64, heap_node: []u32, scratch: []Coord, out: []Coord) -> (usize, f64, err) {
    let total = w * h
    if g.len < total || parent.len < total || closed.len < total || scratch.len < w + h { ret (0usize, 0.0f64, Bounds) }
    if !inside_grid(w, h, from) || !inside_grid(w, h, to) { ret (0usize, 0.0f64, Bounds) }
    if !passable(ctx, from) || !passable(ctx, to) { ret (0usize, 0.0f64, ok) }
    var i = 0usize
    while i < total {
        g[i] = 1.0e300f64
        parent[i] = NONE
        closed[i] = 0u8
        i += 1usize
    }
    let start = cell_index(w, from)
    let goal = cell_index(w, to)
    g[start] = 0.0f64
    parent[start] = u32(start)
    var used = 0usize
    let first_push = heap_push(heap_key, heap_node, &used, euclid(from, to), u32(start))
    if first_push != ok { ret (0usize, 0.0f64, first_push) }
    while used > 0usize {
        let cur = usize(heap_pop(heap_key, heap_node, &used))
        if closed[cur] != 0u8 { continue }
        closed[cur] = 1u8
        if cur == goal {
            let (n, unwind_error) = unwind(w, parent, goal, out)
            ret (n, g[goal], unwind_error)
        }
        let here = cell_of(w, cur)
        let grand = usize(parent[cur])
        let grand_cell = cell_of(w, grand)
        var k = 0usize
        while k < 8usize {
            let next_cell = Coord { q: here.q + delta_q(k), r: here.r + delta_r(k) }
            if inside_grid(w, h, next_cell) {
                let index = cell_index(w, next_cell)
                if closed[index] == 0u8 && passable(ctx, next_cell) {
                    var via = cur
                    var cost = g[cur] + euclid(here, next_cell)
                    if line_of_sight[Ctx](ctx, passable, grand_cell, next_cell, scratch) {
                        via = grand
                        cost = g[grand] + euclid(grand_cell, next_cell)
                    }
                    if cost < g[index] {
                        g[index] = cost
                        parent[index] = u32(via)
                        let push_error = heap_push(heap_key, heap_node, &used, cost + euclid(next_cell, to), u32(index))
                        if push_error != ok { ret (0usize, 0.0f64, push_error) }
                    }
                }
            }
            k += 1usize
        }
    }
    ret (0usize, 0.0f64, ok)
}
