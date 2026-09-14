// Swept boxes, tile rays and a broadphase grid (D249).
//
// Every collision here is an axis-aligned box against another box or against the solid
// bits of a tilemap, resolved by the Minkowski trick: grow the target by the mover's half
// extents and the problem becomes a ray against a box. The answer is a time along the
// motion in Q16, so a caller advances to the moment of contact rather than stepping and
// testing, which is what stops a fast mover tunnelling through a wall.
//
// The arithmetic is integer throughout, so two machines resolving the same motion agree
// on the contact time to the bit -- necessary, since a rollback that disagrees about
// where a body stopped diverges immediately.

use e.mem
use e.math.fixed
use e.game.tilemap

type Aabb = struct {
    x: fixed.Fx,
    y: fixed.Fx,
    half_w: fixed.Fx,
    half_h: fixed.Fx,
}

type Hit = struct {
    hit: bool,
    time: fixed.Fx,
    normal_x: i32,
    normal_y: i32,
}

// A uniform grid of linked lists: `heads` is one entry per cell, `next` one per body, and
// a body is threaded onto every cell it touches. It holds indices rather than boxes, so
// the caller keeps its own array and nothing here allocates.
type Grid = struct {
    heads: []u32,
    next: []u32,
    width: u32,
    height: u32,
    cell: fixed.Fx,
}

error Bounds
error Size

const NONE: u32 = 4294967295u32
// Beyond any time a sweep can produce, standing in for an axis the motion never crosses.
const FOREVER: i64 = 1099511627776i64

fn aabb(x: fixed.Fx, y: fixed.Fx, half_w: fixed.Fx, half_h: fixed.Fx) -> Aabb {
    ret Aabb { x: x, y: y, half_w: half_w, half_h: half_h }
}

fn miss() -> Hit {
    ret Hit { hit: false, time: 0i32, normal_x: 0i32, normal_y: 0i32 }
}

fn overlaps(a: Aabb, b: Aabb) -> bool {
    if fixed.abs(a.x - b.x) >= a.half_w + b.half_w { ret false }
    if fixed.abs(a.y - b.y) >= a.half_h + b.half_h { ret false }
    ret true
}

fn min64(a: i64, b: i64) -> i64 {
    if a < b { ret a }
    ret b
}

fn max64(a: i64, b: i64) -> i64 {
    if a > b { ret a }
    ret b
}

// Where the motion enters and leaves one axis of the grown box, as Q16 times. A motion
// with no component on the axis either never leaves it or never enters it at all.
fn axis_span(origin: i64, delta: i64, centre: i64, half: i64) -> (i64, i64, bool) {
    if delta == 0i64 {
        if origin <= centre - half || origin >= centre + half { ret (0i64, 0i64, false) }
        ret (0i64 - FOREVER, FOREVER, true)
    }
    let first = (((centre - half) - origin) << 16u32) / delta
    let second = (((centre + half) - origin) << 16u32) / delta
    ret (min64(first, second), max64(first, second), true)
}

// The time along the motion at which `a` first touches `b`, and the face it touches.
// A mover already overlapping reports time zero; `overlaps` is the test for that case.
fn sweep(a: Aabb, dx: fixed.Fx, dy: fixed.Fx, b: Aabb) -> Hit {
    let grown_w = i64(b.half_w) + i64(a.half_w)
    let grown_h = i64(b.half_h) + i64(a.half_h)
    let (near_x, far_x, crosses_x) = axis_span(i64(a.x), i64(dx), i64(b.x), grown_w)
    if !crosses_x { ret miss() }
    let (near_y, far_y, crosses_y) = axis_span(i64(a.y), i64(dy), i64(b.y), grown_h)
    if !crosses_y { ret miss() }
    let near = max64(near_x, near_y)
    let far = min64(far_x, far_y)
    if near > far { ret miss() }
    if far <= 0i64 { ret miss() }
    if near >= 65536i64 { ret miss() }
    var contact = near
    if contact < 0i64 { contact = 0i64 }
    // The axis that entered last is the face that was struck.
    if near_x > near_y {
        var normal = 1i32
        if dx > 0i32 { normal = -1i32 }
        ret Hit { hit: true, time: i32(contact), normal_x: normal, normal_y: 0i32 }
    }
    var normal = 1i32
    if dy > 0i32 { normal = -1i32 }
    ret Hit { hit: true, time: i32(contact), normal_x: 0i32, normal_y: normal }
}

fn earlier(current: Hit, candidate: Hit) -> Hit {
    if !candidate.hit { ret current }
    if !current.hit { ret candidate }
    if candidate.time < current.time { ret candidate }
    ret current
}

// Sweep against every solid tile the motion could reach. The span is taken from the
// box before and after the motion, so a fast mover is tested against the tiles it passes
// through rather than only the ones it ends on.
fn sweep_tiles(a: Aabb, dx: fixed.Fx, dy: fixed.Fx, m: tilemap.Map) -> Hit {
    let half_w = i64(a.half_w)
    let half_h = i64(a.half_h)
    let start_x = min64(i64(a.x), i64(a.x) + i64(dx))
    let start_y = min64(i64(a.y), i64(a.y) + i64(dy))
    let end_x = max64(i64(a.x), i64(a.x) + i64(dx))
    let end_y = max64(i64(a.y), i64(a.y) + i64(dy))
    let (first_x, first_y) = tilemap.to_tile(m, i32(start_x - half_w), i32(start_y - half_h))
    let (last_x, last_y) = tilemap.to_tile(m, i32(end_x + half_w), i32(end_y + half_h))
    let tile_half_w = i32((i64(m.tile_w) << 16u32) / 2i64)
    let tile_half_h = i32((i64(m.tile_h) << 16u32) / 2i64)
    var best = miss()
    var ty = first_y
    while ty <= last_y {
        var tx = first_x
        while tx <= last_x {
            if tilemap.is_solid(m, tx, ty) {
                let (wx, wy) = tilemap.to_world(m, tx, ty)
                let block = Aabb { x: wx + tile_half_w, y: wy + tile_half_h, half_w: tile_half_w, half_h: tile_half_h }
                best = earlier(best, sweep(a, dx, dy, block))
            }
            tx += 1i32
        }
        ty += 1i32
    }
    ret best
}

// A ray against the solid bits, stepped one tile boundary at a time. The stepping is the
// usual grid traversal: advance whichever axis reaches its next boundary first, so no
// tile on the line is skipped and none is visited twice.
fn ray_tiles(m: tilemap.Map, x: fixed.Fx, y: fixed.Fx, dx: fixed.Fx, dy: fixed.Fx, limit: fixed.Fx) -> Hit {
    if dx == 0i32 && dy == 0i32 { ret miss() }
    var (tile_x, tile_y) = tilemap.to_tile(m, x, y)
    if tilemap.is_solid(m, tile_x, tile_y) { ret Hit { hit: true, time: 0i32, normal_x: 0i32, normal_y: 0i32 } }
    let width = i64(m.tile_w) << 16u32
    let height = i64(m.tile_h) << 16u32
    var travelled = 0i64
    let ceiling = i64(limit)
    var guard = 0usize
    while travelled <= ceiling && guard < 4096usize {
        guard += 1usize
        // Distance to the next boundary on each axis, as a time along the ray.
        var time_x = FOREVER
        if dx != 0i32 {
            var edge = (i64(tile_x) + 1i64) * width
            if dx < 0i32 { edge = i64(tile_x) * width }
            time_x = ((edge - i64(x)) << 16u32) / i64(dx)
        }
        var time_y = FOREVER
        if dy != 0i32 {
            var edge = (i64(tile_y) + 1i64) * height
            if dy < 0i32 { edge = i64(tile_y) * height }
            time_y = ((edge - i64(y)) << 16u32) / i64(dy)
        }
        var normal_x = 0i32
        var normal_y = 0i32
        if time_x <= time_y {
            travelled = time_x
            if dx > 0i32 { tile_x += 1i32 } else { tile_x -= 1i32 }
            if dx > 0i32 { normal_x = -1i32 } else { normal_x = 1i32 }
        } else {
            travelled = time_y
            if dy > 0i32 { tile_y += 1i32 } else { tile_y -= 1i32 }
            if dy > 0i32 { normal_y = -1i32 } else { normal_y = 1i32 }
        }
        if travelled > ceiling { ret miss() }
        if tilemap.is_solid(m, tile_x, tile_y) {
            ret Hit { hit: true, time: i32(travelled), normal_x: normal_x, normal_y: normal_y }
        }
    }
    ret miss()
}

fn grid_init(g: *Grid, heads: []u32, next: []u32, width: u32, height: u32, cell: fixed.Fx) -> err {
    if cell <= 0i32 || width == 0u32 || height == 0u32 { ret Size }
    if heads.len < usize(width) * usize(height) { ret Size }
    g.heads = heads
    g.next = next
    g.width = width
    g.height = height
    g.cell = cell
    ret grid_clear(g)
}

fn grid_clear(g: *Grid) -> err {
    var at = 0usize
    while at < g.heads.len {
        g.heads[at] = NONE
        at += 1usize
    }
    at = 0usize
    while at < g.next.len {
        g.next[at] = NONE
        at += 1usize
    }
    ret ok
}

fn cell_of(g: Grid, value: fixed.Fx) -> i64 {
    var quotient = i64(value) / i64(g.cell)
    if (i64(value) % i64(g.cell) != 0i64) && (value < 0i32) { quotient = quotient - 1i64 }
    ret quotient
}

fn clamp_cell(value: i64, limit: u32) -> i64 {
    if value < 0i64 { ret 0i64 }
    if value >= i64(limit) { ret i64(limit) - 1i64 }
    ret value
}

// A body goes on every cell its box touches, so a query against one cell finds it whether
// it is centred there or merely overlapping.
fn grid_insert(g: *Grid, id: u32, box: Aabb) -> err {
    if usize(id) >= g.next.len { ret Bounds }
    let first_x = clamp_cell(cell_of(*g, box.x - box.half_w), g.width)
    let last_x = clamp_cell(cell_of(*g, box.x + box.half_w), g.width)
    let first_y = clamp_cell(cell_of(*g, box.y - box.half_h), g.height)
    let last_y = clamp_cell(cell_of(*g, box.y + box.half_h), g.height)
    // One thread per body, so a body spanning several cells is reachable from the first
    // of them; a broadphase is allowed to answer a superset and does.
    let index = usize(first_y) * usize(g.width) + usize(first_x)
    g.next[usize(id)] = g.heads[index]
    g.heads[index] = id
    ret ok
}

// Every body threaded on a cell the box touches. A broadphase answers a superset: the
// caller still tests the pairs it gets back.
fn grid_near(g: Grid, box: Aabb, out: []u32) -> (usize, err) {
    let first_x = clamp_cell(cell_of(g, box.x - box.half_w), g.width)
    let last_x = clamp_cell(cell_of(g, box.x + box.half_w), g.width)
    let first_y = clamp_cell(cell_of(g, box.y - box.half_h), g.height)
    let last_y = clamp_cell(cell_of(g, box.y + box.half_h), g.height)
    var count = 0usize
    var cy = first_y
    while cy <= last_y {
        var cx = first_x
        while cx <= last_x {
            var walker = g.heads[usize(cy) * usize(g.width) + usize(cx)]
            while walker != NONE {
                if count == out.len { ret (count, Bounds) }
                out[count] = walker
                count += 1usize
                walker = g.next[usize(walker)]
            }
            cx += 1i64
        }
        cy += 1i64
    }
    ret (count, ok)
}
