// The viewport, and the ordered draw list (D249, D252).
//
// Two questions with one answer: what is on screen, and in what order must it be drawn.
// Deciding the order is engine logic -- a sort key per item and a stable sort over them --
// and drawing from it is not, so the drawing stays outside. `cull` and `order` are here
// together because culling that changed the order would break the painter's algorithm the
// order exists to serve.
//
// Everything is integer, including the shake, which draws from the caller's generator so
// a replay shakes the same way. A camera that wandered by a float would put every
// rollback frame a pixel off the one it is compared against.

use e.mem
use e.math.fixed
use e.algo.rand
use e.game.collide2d

type Camera = struct {
    x: fixed.Fx,
    y: fixed.Fx,
    zoom: fixed.Fx,
    width: fixed.Fx,
    height: fixed.Fx,
    dead_w: fixed.Fx,
    dead_h: fixed.Fx,
    shake: fixed.Fx,
    shake_ticks: u16,
    shake_x: fixed.Fx,
    shake_y: fixed.Fx,
}

type Bounds = struct {
    min_x: fixed.Fx,
    min_y: fixed.Fx,
    max_x: fixed.Fx,
    max_y: fixed.Fx,
}

// `sort` is the painter's key -- `e.game.grid.depth` produces one -- and `layer` outranks
// it, so a background never sorts in front of a foreground however deep it lies.
type Item = struct {
    id: u32,
    layer: i16,
    sort: fixed.Fx,
}

error Size
error Bounds

fn init(c: *Camera, width: fixed.Fx, height: fixed.Fx) -> err {
    if width <= 0i32 || height <= 0i32 { ret Size }
    c.x = 0i32
    c.y = 0i32
    c.zoom = fixed.ONE
    c.width = width
    c.height = height
    c.dead_w = 0i32
    c.dead_h = 0i32
    c.shake = 0i32
    c.shake_ticks = 0u16
    c.shake_x = 0i32
    c.shake_y = 0i32
    ret ok
}

fn set_deadzone(c: *Camera, width: fixed.Fx, height: fixed.Fx) -> err {
    if width < 0i32 || height < 0i32 { ret Size }
    c.dead_w = width
    c.dead_h = height
    ret ok
}

// Follow only once the target leaves the deadzone, and then only far enough to put it
// back on the edge of it. A camera that centred every frame would swing on every step a
// character takes, which is the usual reason a deadzone exists at all.
fn follow(c: *Camera, tx: fixed.Fx, ty: fixed.Fx) -> err {
    let half_w = c.dead_w / 2i32
    let half_h = c.dead_h / 2i32
    if tx > c.x + half_w { c.x = tx - half_w }
    if tx < c.x - half_w { c.x = tx + half_w }
    if ty > c.y + half_h { c.y = ty - half_h }
    if ty < c.y - half_h { c.y = ty + half_h }
    ret ok
}

// Keep the visible rectangle inside the world. A world smaller than the view is centred
// instead, since there is no position that satisfies both edges.
fn clamp_to(c: *Camera, b: Bounds) -> err {
    let half_w = view_half_width(*c)
    let half_h = view_half_height(*c)
    if b.max_x - b.min_x <= half_w * 2i32 {
        c.x = (b.min_x + b.max_x) / 2i32
    } else {
        if c.x - half_w < b.min_x { c.x = b.min_x + half_w }
        if c.x + half_w > b.max_x { c.x = b.max_x - half_w }
    }
    if b.max_y - b.min_y <= half_h * 2i32 {
        c.y = (b.min_y + b.max_y) / 2i32
    } else {
        if c.y - half_h < b.min_y { c.y = b.min_y + half_h }
        if c.y + half_h > b.max_y { c.y = b.max_y - half_h }
    }
    ret ok
}

fn view_half_width(c: Camera) -> fixed.Fx {
    if c.zoom <= 0i32 { ret c.width / 2i32 }
    let (scaled, scaled_error) = fixed.div(c.width, c.zoom)
    if scaled_error != ok { ret c.width / 2i32 }
    ret scaled / 2i32
}

fn view_half_height(c: Camera) -> fixed.Fx {
    if c.zoom <= 0i32 { ret c.height / 2i32 }
    let (scaled, scaled_error) = fixed.div(c.height, c.zoom)
    if scaled_error != ok { ret c.height / 2i32 }
    ret scaled / 2i32
}

fn set_zoom(c: *Camera, zoom: fixed.Fx) -> err {
    if zoom <= 0i32 { ret Size }
    c.zoom = zoom
    ret ok
}

fn shake(c: *Camera, amount: fixed.Fx, ticks: u16) -> err {
    c.shake = amount
    c.shake_ticks = ticks
    ret ok
}

// Decay the shake and draw this tick's offset. The offset is part of the camera rather
// than applied at draw time, so everything that asks where the camera is agrees.
fn step(c: *Camera, state: *rand.Pcg64) -> err {
    if c.shake_ticks == 0u16 {
        c.shake_x = 0i32
        c.shake_y = 0i32
        c.shake = 0i32
        ret ok
    }
    let span = i64(c.shake) * 2i64 + 1i64
    c.shake_x = i32(i64(rand.pcg64_bounded(state, u64(span))) - i64(c.shake))
    c.shake_y = i32(i64(rand.pcg64_bounded(state, u64(span))) - i64(c.shake))
    c.shake_ticks = c.shake_ticks - 1u16
    // Fade the amplitude out over the remaining ticks rather than stopping at full throw.
    c.shake = c.shake - c.shake / (i32(c.shake_ticks) + 1i32)
    ret ok
}

// World to screen, with a parallax factor: `fixed.ONE` moves with the world, `0` is
// pinned to the view, and between them is a background that drifts.
fn to_screen(c: Camera, wx: fixed.Fx, wy: fixed.Fx, parallax: fixed.Fx) -> (fixed.Fx, fixed.Fx) {
    let eye_x = fixed.mul(c.x + c.shake_x, parallax)
    let eye_y = fixed.mul(c.y + c.shake_y, parallax)
    let sx = fixed.mul(wx - eye_x, c.zoom) + c.width / 2i32
    let sy = fixed.mul(wy - eye_y, c.zoom) + c.height / 2i32
    ret (sx, sy)
}

fn to_world(c: Camera, sx: fixed.Fx, sy: fixed.Fx) -> (fixed.Fx, fixed.Fx) {
    if c.zoom <= 0i32 { ret (c.x, c.y) }
    let (ox, ox_error) = fixed.div(sx - c.width / 2i32, c.zoom)
    if ox_error != ok { ret (c.x, c.y) }
    let (oy, oy_error) = fixed.div(sy - c.height / 2i32, c.zoom)
    if oy_error != ok { ret (c.x, c.y) }
    ret (ox + c.x + c.shake_x, oy + c.y + c.shake_y)
}

fn visible(c: Camera, box: collide2d.Aabb) -> bool {
    let half_w = view_half_width(c)
    let half_h = view_half_height(c)
    let eye_x = c.x + c.shake_x
    let eye_y = c.y + c.shake_y
    if box.x + box.half_w < eye_x - half_w { ret false }
    if box.x - box.half_w > eye_x + half_w { ret false }
    if box.y + box.half_h < eye_y - half_h { ret false }
    if box.y - box.half_h > eye_y + half_h { ret false }
    ret true
}

// The indices of the boxes on screen, in the order they were given.
fn cull(c: Camera, boxes: []const collide2d.Aabb, out: []u32) -> (usize, err) {
    var count = 0usize
    var at = 0usize
    while at < boxes.len {
        if visible(c, boxes[at]) {
            if count == out.len { ret (count, Bounds) }
            out[count] = u32(at)
            count += 1usize
        }
        at += 1usize
    }
    ret (count, ok)
}

// Insertion sort, which is stable: two items with the same layer and key keep the order
// they were given, so a draw list does not flicker between frames that produce ties.
// It is also nearly free on an almost-sorted list, which a draw list is from one frame to
// the next.
fn order(items: []Item) -> err {
    var at = 1usize
    while at < items.len {
        let moving = items[at]
        var back = at
        while back > 0usize && after(items[back - 1usize], moving) {
            items[back] = items[back - 1usize]
            back = back - 1usize
        }
        items[back] = moving
        at += 1usize
    }
    ret ok
}

// Strictly after: equal items answer false, which is what keeps the sort stable.
fn after(a: Item, b: Item) -> bool {
    if a.layer != b.layer { ret a.layer > b.layer }
    ret a.sort > b.sort
}
