// Field of view, line of sight and fog of war (D249).
//
// Recursive shadowcasting over eight octants. A slope is a pair of integers compared by
// cross-multiplication and never divided, so who can see what is identical on every
// machine -- which lockstep requires, since a disagreement about visibility desynchronises
// a session as surely as a disagreement about position.
//
// Two bitsets carry the three states section 4 of any fog implementation needs: `visible`
// is recomputed each tick, `explored` is sticky, and a cell in neither is unseen. One bit
// per cell per state, so a 512x512 map costs 64 KB for both.
//
// Line of sight is here rather than in the AI because both want the same question
// answered the same way: an enemy that can see you and a tile you can see must agree.

use e.mem
use e.math.fixed
use e.game.tilemap

type Cell = enum u8 { Unseen, Explored, Visible }

type Field = struct {
    width: u32,
    height: u32,
    visible: []u64,
    explored: []u64,
}

error Bounds
error Size

// The eight octants, as the transform from (column, row) into a map offset. Walking all
// eight with one scanner is what keeps the shadow rules in a single place.
const OCTANTS: usize = 8usize

fn octant_xx(octant: usize) -> i32 {
    if octant == 0usize { ret 1i32 }
    if octant == 1usize { ret 0i32 }
    if octant == 2usize { ret 0i32 }
    if octant == 3usize { ret -1i32 }
    if octant == 4usize { ret -1i32 }
    if octant == 5usize { ret 0i32 }
    if octant == 6usize { ret 0i32 }
    ret 1i32
}

fn octant_xy(octant: usize) -> i32 {
    if octant == 0usize { ret 0i32 }
    if octant == 1usize { ret 1i32 }
    if octant == 2usize { ret -1i32 }
    if octant == 3usize { ret 0i32 }
    if octant == 4usize { ret 0i32 }
    if octant == 5usize { ret -1i32 }
    if octant == 6usize { ret 1i32 }
    ret 0i32
}

fn octant_yx(octant: usize) -> i32 {
    if octant == 0usize { ret 0i32 }
    if octant == 1usize { ret 1i32 }
    if octant == 2usize { ret 1i32 }
    if octant == 3usize { ret 0i32 }
    if octant == 4usize { ret 0i32 }
    if octant == 5usize { ret -1i32 }
    if octant == 6usize { ret -1i32 }
    ret 0i32
}

fn octant_yy(octant: usize) -> i32 {
    if octant == 0usize { ret 1i32 }
    if octant == 1usize { ret 0i32 }
    if octant == 2usize { ret 0i32 }
    if octant == 3usize { ret 1i32 }
    if octant == 4usize { ret -1i32 }
    if octant == 5usize { ret 0i32 }
    if octant == 6usize { ret 0i32 }
    ret -1i32
}

fn init(f: *Field, width: u32, height: u32, visible: []u64, explored: []u64) -> err {
    if width == 0u32 || height == 0u32 { ret Size }
    let words = (usize(width) * usize(height) + 63usize) / 64usize
    if visible.len < words || explored.len < words { ret Size }
    var at = 0usize
    while at < words {
        visible[at] = 0u64
        explored[at] = 0u64
        at += 1usize
    }
    f.width = width
    f.height = height
    f.visible = visible
    f.explored = explored
    ret ok
}

fn inside(f: Field, x: i32, y: i32) -> bool {
    if x < 0i32 || y < 0i32 { ret false }
    ret u32(x) < f.width && u32(y) < f.height
}

fn index_of(f: Field, x: i32, y: i32) -> usize {
    ret usize(y) * usize(f.width) + usize(x)
}

fn bit_test(words: []const u64, index: usize) -> bool {
    ret (words[index / 64usize] & (1u64 << u32(index % 64usize))) != 0u64
}

fn bit_set(words: []u64, index: usize) {
    words[index / 64usize] = words[index / 64usize] | (1u64 << u32(index % 64usize))
}

fn clear_visible(f: *Field) -> err {
    var at = 0usize
    while at < f.visible.len {
        f.visible[at] = 0u64
        at += 1usize
    }
    ret ok
}

fn is_visible(f: Field, x: i32, y: i32) -> bool {
    if !inside(f, x, y) { ret false }
    ret bit_test(f.visible, index_of(f, x, y))
}

fn is_explored(f: Field, x: i32, y: i32) -> bool {
    if !inside(f, x, y) { ret false }
    ret bit_test(f.explored, index_of(f, x, y))
}

fn cell(f: Field, x: i32, y: i32) -> Cell {
    if is_visible(f, x, y) { ret .Visible }
    if is_explored(f, x, y) { ret .Explored }
    ret .Unseen
}

fn reveal(f: *Field, x: i32, y: i32) {
    if !inside(*f, x, y) { ret }
    let index = index_of(*f, x, y)
    bit_set(f.visible, index)
    bit_set(f.explored, index)
}

// Cross-multiplication only orders two rationals correctly when both denominators are
// positive. Every octant scans with a negative row, so the sign is normalised first --
// without this the comparisons invert and the scan reveals nothing at all.
fn slope_greater(a_num: i64, a_den: i64, b_num: i64, b_den: i64) -> bool {
    var an = a_num
    var ad = a_den
    var bn = b_num
    var bd = b_den
    if ad < 0i64 {
        an = 0i64 - an
        ad = 0i64 - ad
    }
    if bd < 0i64 {
        bn = 0i64 - bn
        bd = 0i64 - bd
    }
    ret an * bd > bn * ad
}

fn slope_less(a_num: i64, a_den: i64, b_num: i64, b_den: i64) -> bool {
    ret slope_greater(b_num, b_den, a_num, a_den)
}

// One octant, one row at a time. `start` and `end` bound the arc still unshadowed; an
// opaque cell splits that arc, and the part above it is scanned by a deeper call while
// this one carries on below.
fn scan(f: *Field, m: tilemap.Map, ox: i32, oy: i32, radius: u32, row: u32, start_num: i64, start_den: i64, end_num: i64, end_den: i64, octant: usize) {
    if !slope_greater(start_num, start_den, end_num, end_den) { ret }
    let xx = octant_xx(octant)
    let xy = octant_xy(octant)
    let yx = octant_yx(octant)
    let yy = octant_yy(octant)
    var blocked = false
    var running_start_num = start_num
    var running_start_den = start_den
    var current_num = start_num
    var current_den = start_den
    var distance = row
    while distance <= radius {
        let dy = 0i32 - i32(distance)
        var dx = 0i32 - i32(distance)
        while dx <= 0i32 {
            let x = ox + dx * xx + dy * xy
            let y = oy + dx * yx + dy * yy
            // The cell's near and far edges, as slopes from the origin.
            let left_num = i64(dx) * 2i64 - 1i64
            let left_den = i64(dy) * 2i64 + 1i64
            let right_num = i64(dx) * 2i64 + 1i64
            let right_den = i64(dy) * 2i64 - 1i64
            if slope_less(current_num, current_den, right_num, right_den) {
                dx += 1i32
                continue
            }
            if slope_greater(end_num, end_den, left_num, left_den) { break }
            if i64(dx) * i64(dx) + i64(dy) * i64(dy) <= i64(radius) * i64(radius) {
                reveal(f, x, y)
            }
            let solid = tilemap.is_opaque(m, x, y)
            if blocked {
                if solid {
                    running_start_num = right_num
                    running_start_den = right_den
                } else {
                    blocked = false
                    current_num = running_start_num
                    current_den = running_start_den
                }
            } else {
                if solid && distance < radius {
                    blocked = true
                    scan(f, m, ox, oy, radius, distance + 1u32, current_num, current_den, left_num, left_den, octant)
                    running_start_num = right_num
                    running_start_den = right_den
                }
            }
            dx += 1i32
        }
        if blocked { ret }
        distance += 1u32
    }
}

// Everything within `radius` that the opaque tiles do not hide, unioned into the field.
// The origin always sees itself.
fn cast(f: *Field, m: tilemap.Map, x: i32, y: i32, radius: u32) -> err {
    reveal(f, x, y)
    var octant = 0usize
    while octant < OCTANTS {
        scan(f, m, x, y, radius, 1u32, 1i64, 1i64, 0i64, 1i64, octant)
        octant += 1usize
    }
    ret ok
}

// Whether one cell can see another, by the same rule the fog uses: a sightline is blocked
// by an opaque cell between the two, and neither endpoint blocks itself.
fn line_of_sight(m: tilemap.Map, x0: i32, y0: i32, x1: i32, y1: i32) -> bool {
    var dx = x1 - x0
    var dy = y1 - y0
    var step_x = 1i32
    var step_y = 1i32
    if dx < 0i32 {
        dx = 0i32 - dx
        step_x = -1i32
    }
    if dy < 0i32 {
        dy = 0i32 - dy
        step_y = -1i32
    }
    var x = x0
    var y = y0
    if dx >= dy {
        var error_term = dx / 2i32
        while x != x1 {
            error_term = error_term - dy
            if error_term < 0i32 {
                y = y + step_y
                error_term = error_term + dx
            }
            x = x + step_x
            if x == x1 && y == y1 { ret true }
            if tilemap.is_opaque(m, x, y) { ret false }
        }
        ret true
    }
    var error_term = dy / 2i32
    while y != y1 {
        error_term = error_term - dx
        if error_term < 0i32 {
            x = x + step_x
            error_term = error_term + dy
        }
        y = y + step_y
        if x == x1 && y == y1 { ret true }
        if tilemap.is_opaque(m, x, y) { ret false }
    }
    ret true
}

// Shared vision: what either field has seen, both now and ever.
fn merge(dst: *Field, src: Field) -> err {
    if dst.width != src.width || dst.height != src.height { ret Size }
    var at = 0usize
    while at < dst.visible.len && at < src.visible.len {
        dst.visible[at] = dst.visible[at] | src.visible[at]
        dst.explored[at] = dst.explored[at] | src.explored[at]
        at += 1usize
    }
    ret ok
}

fn visible_count(f: Field) -> usize {
    var total = 0usize
    var y = 0i32
    while u32(y) < f.height {
        var x = 0i32
        while u32(x) < f.width {
            if bit_test(f.visible, index_of(f, x, y)) { total += 1usize }
            x += 1i32
        }
        y += 1i32
    }
    ret total
}
