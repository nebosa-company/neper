// Steering, behaviour trees and grid pathfinding (D249).
//
// `e.algo.graph` is deliberately *not* used here. Its shortest-path answers carry `f64`
// distances, and a float comparison that lands differently on two machines sends two
// agents down two paths, which desynchronises a lockstep session exactly the way a float
// position would. So the search below is A* with integer costs, written against the
// tilemap directly -- the duplication is the price of the determinism the rest of this
// core is built on.
//
// Nothing here allocates: every buffer is the caller's, as in the rest of `e.game`.

use e.mem
use e.math.fixed
use e.algo.rand
use e.game.tilemap

type Agent = struct {
    x: fixed.Fx,
    y: fixed.Fx,
    vx: fixed.Fx,
    vy: fixed.Fx,
    max_speed: fixed.Fx,
}

type Steer = struct {
    x: fixed.Fx,
    y: fixed.Fx,
}

type Kind = enum u8 { Sequence, Selector, Invert, Condition, Action }
type Status = enum u8 { Running, Success, Failure }

// A node's children are a run in the same array, so a tree is one flat table a game can
// author as a constant.
type Behavior = struct {
    kind: Kind,
    first_child: u16,
    child_count: u16,
    id: u16,
}

// The search's working memory, sized by the caller to the map it will search.
type Scratch = struct {
    came_from: []u32,
    cost: []u32,
    heap: []u32,
    heap_f: []u32,
    heap_count: usize,
    seen: []u64,
}

error Unreachable
error Size
error Bounds

const NONE: u32 = 4294967295u32

// --- steering -------------------------------------------------------------------------

fn steer(x: fixed.Fx, y: fixed.Fx) -> Steer {
    ret Steer { x: x, y: y }
}

// Toward the target at full speed, as a desired velocity minus the current one -- the
// difference, not the direction, so an agent already moving that way is not pushed again.
fn seek(a: Agent, tx: fixed.Fx, ty: fixed.Fx) -> Steer {
    let (dx, dy) = fixed.normalize(tx - a.x, ty - a.y)
    ret Steer { x: fixed.mul(dx, a.max_speed) - a.vx, y: fixed.mul(dy, a.max_speed) - a.vy }
}

fn flee(a: Agent, tx: fixed.Fx, ty: fixed.Fx) -> Steer {
    let away = seek(a, tx, ty)
    ret Steer { x: 0i32 - away.x, y: 0i32 - away.y }
}

// Seek, but scale the speed down inside `slow_radius` so the agent settles rather than
// orbiting the target forever.
fn arrive(a: Agent, tx: fixed.Fx, ty: fixed.Fx, slow_radius: fixed.Fx) -> Steer {
    let distance = fixed.length(tx - a.x, ty - a.y)
    if distance == 0i32 { ret Steer { x: 0i32 - a.vx, y: 0i32 - a.vy } }
    var speed = a.max_speed
    if slow_radius > 0i32 && distance < slow_radius {
        let (share, share_error) = fixed.div(distance, slow_radius)
        if share_error == ok { speed = fixed.mul(a.max_speed, share) }
    }
    let (dx, dy) = fixed.normalize(tx - a.x, ty - a.y)
    ret Steer { x: fixed.mul(dx, speed) - a.vx, y: fixed.mul(dy, speed) - a.vy }
}

// A nudge in a direction drawn from the caller's generator, so a wander replays.
fn wander(a: Agent, state: *rand.Pcg64, jitter: fixed.Fx) -> Steer {
    if jitter <= 0i32 { ret Steer { x: 0i32, y: 0i32 } }
    let span = u64(jitter) * 2u64 + 1u64
    let dx = i32(i64(rand.pcg64_bounded(state, span)) - i64(jitter))
    let dy = i32(i64(rand.pcg64_bounded(state, span)) - i64(jitter))
    ret Steer { x: dx, y: dy }
}

// Push away from every neighbour inside `radius`, harder the closer it is. The weight is
// the overlap rather than the reciprocal of the distance, which keeps it finite when two
// agents occupy the same point.
fn separate(a: Agent, others: []const Agent, radius: fixed.Fx) -> Steer {
    if radius <= 0i32 { ret Steer { x: 0i32, y: 0i32 } }
    var sum_x = 0i32
    var sum_y = 0i32
    var at = 0usize
    while at < others.len {
        let dx = a.x - others[at].x
        let dy = a.y - others[at].y
        let distance = fixed.length(dx, dy)
        if distance < radius && distance > 0i32 {
            let (unit_x, unit_y) = fixed.normalize(dx, dy)
            let weight = radius - distance
            sum_x = sum_x + fixed.mul(unit_x, weight)
            sum_y = sum_y + fixed.mul(unit_y, weight)
        }
        at += 1usize
    }
    ret Steer { x: sum_x, y: sum_y }
}

// Weighted sum, weights in Q16. Blending is left to the caller because what a game wants
// from "avoid and chase at once" is a tuning decision, not a library one.
fn combine(parts: []const Steer, weights: []const fixed.Fx) -> Steer {
    var sum_x = 0i32
    var sum_y = 0i32
    var at = 0usize
    while at < parts.len && at < weights.len {
        sum_x = sum_x + fixed.mul(parts[at].x, weights[at])
        sum_y = sum_y + fixed.mul(parts[at].y, weights[at])
        at += 1usize
    }
    ret Steer { x: sum_x, y: sum_y }
}

// Clamp a steering force to what the agent can actually apply.
fn limit(s: Steer, most: fixed.Fx) -> Steer {
    let size = fixed.length(s.x, s.y)
    if size <= most || size == 0i32 { ret s }
    let (unit_x, unit_y) = fixed.normalize(s.x, s.y)
    ret Steer { x: fixed.mul(unit_x, most), y: fixed.mul(unit_y, most) }
}

// --- behaviour trees --------------------------------------------------------------------

// Conditions are answered by the caller before the tick, and an action node names itself
// rather than running: `run` reports which action the tree arrived at and the caller
// performs it. That keeps the tree pure data and needs no function pointers, at the cost
// of the caller evaluating every condition whether the tree reaches it or not.
fn run(tree: []const Behavior, at: u16, conditions: []const bool, action: *u16) -> Status {
    if usize(at) >= tree.len { ret .Failure }
    let node = tree[usize(at)]
    if node.kind == .Condition {
        if usize(node.id) >= conditions.len { ret .Failure }
        if conditions[usize(node.id)] { ret .Success }
        ret .Failure
    }
    if node.kind == .Action {
        *action = node.id
        ret .Running
    }
    if node.kind == .Invert {
        if node.child_count == 0u16 { ret .Failure }
        let inner = run(tree, node.first_child, conditions, action)
        if inner == .Success { ret .Failure }
        if inner == .Failure { ret .Success }
        ret .Running
    }
    if node.kind == .Sequence {
        var child = 0u16
        while child < node.child_count {
            let outcome = run(tree, node.first_child + child, conditions, action)
            if outcome != .Success { ret outcome }
            child += 1u16
        }
        ret .Success
    }
    // Selector: the first child that does not fail.
    var child = 0u16
    while child < node.child_count {
        let outcome = run(tree, node.first_child + child, conditions, action)
        if outcome != .Failure { ret outcome }
        child += 1u16
    }
    ret .Failure
}

// --- grid pathfinding ---------------------------------------------------------------------

fn index_of(m: tilemap.Map, x: i32, y: i32) -> u32 {
    ret u32(y) * tilemap.width(m) + u32(x)
}

fn bit_test(words: []const u64, index: usize) -> bool {
    ret (words[index / 64usize] & (1u64 << u32(index % 64usize))) != 0u64
}

fn bit_set(words: []u64, index: usize) {
    words[index / 64usize] = words[index / 64usize] | (1u64 << u32(index % 64usize))
}

// Manhattan, which is admissible for four-way movement at unit cost and therefore keeps
// A* optimal. A diagonal-capable grid would need a different one.
fn heuristic(x: i32, y: i32, gx: i32, gy: i32) -> u32 {
    var dx = gx - x
    var dy = gy - y
    if dx < 0i32 { dx = 0i32 - dx }
    if dy < 0i32 { dy = 0i32 - dy }
    ret u32(dx + dy)
}

fn heap_push(s: *Scratch, node: u32, f: u32) -> err {
    if s.heap_count == s.heap.len { ret Size }
    var at = s.heap_count
    s.heap[at] = node
    s.heap_f[at] = f
    s.heap_count = s.heap_count + 1usize
    while at > 0usize {
        let parent = (at - 1usize) / 2usize
        if s.heap_f[parent] <= s.heap_f[at] { break }
        let swap_node = s.heap[parent]
        let swap_f = s.heap_f[parent]
        s.heap[parent] = s.heap[at]
        s.heap_f[parent] = s.heap_f[at]
        s.heap[at] = swap_node
        s.heap_f[at] = swap_f
        at = parent
    }
    ret ok
}

fn heap_pop(s: *Scratch) -> (u32, bool) {
    if s.heap_count == 0usize { ret (0u32, false) }
    let best = s.heap[0usize]
    s.heap_count = s.heap_count - 1usize
    s.heap[0usize] = s.heap[s.heap_count]
    s.heap_f[0usize] = s.heap_f[s.heap_count]
    var at = 0usize
    while true {
        let left = at * 2usize + 1usize
        let right = left + 1usize
        var smallest = at
        if left < s.heap_count && s.heap_f[left] < s.heap_f[smallest] { smallest = left }
        if right < s.heap_count && s.heap_f[right] < s.heap_f[smallest] { smallest = right }
        if smallest == at { break }
        let swap_node = s.heap[smallest]
        let swap_f = s.heap_f[smallest]
        s.heap[smallest] = s.heap[at]
        s.heap_f[smallest] = s.heap_f[at]
        s.heap[at] = swap_node
        s.heap_f[at] = swap_f
        at = smallest
    }
    ret (best, true)
}

// A* over the open tiles, four-connected at unit cost. The answer is written into `out`
// from start to goal inclusive, as packed `y * width + x` indices.
fn path_grid(m: tilemap.Map, sx: i32, sy: i32, gx: i32, gy: i32, s: *Scratch, out: []u32) -> (usize, err) {
    let cells = usize(tilemap.width(m)) * usize(tilemap.height(m))
    if s.came_from.len < cells || s.cost.len < cells { ret (0usize, Size) }
    if s.seen.len < (cells + 63usize) / 64usize { ret (0usize, Size) }
    if !tilemap.in_bounds(m, sx, sy) || !tilemap.in_bounds(m, gx, gy) { ret (0usize, Bounds) }
    if tilemap.is_solid(m, sx, sy) || tilemap.is_solid(m, gx, gy) { ret (0usize, Unreachable) }
    var at = 0usize
    while at < cells {
        s.came_from[at] = NONE
        s.cost[at] = NONE
        at += 1usize
    }
    at = 0usize
    while at < s.seen.len {
        s.seen[at] = 0u64
        at += 1usize
    }
    s.heap_count = 0usize
    let start = index_of(m, sx, sy)
    let goal = index_of(m, gx, gy)
    s.cost[usize(start)] = 0u32
    try_push(s, start, heuristic(sx, sy, gx, gy))
    while true {
        let (current, more) = heap_pop(s)
        if !more { ret (0usize, Unreachable) }
        if current == goal {
            let (length, unwind_error) = unwind(s, start, goal, out)
            ret (length, unwind_error)
        }
        if bit_test(s.seen, usize(current)) { continue }
        bit_set(s.seen, usize(current))
        let cx = i32(current % tilemap.width(m))
        let cy = i32(current / tilemap.width(m))
        var direction = 0usize
        while direction < 4usize {
            var nx = cx
            var ny = cy
            if direction == 0usize { nx = cx + 1i32 }
            if direction == 1usize { nx = cx - 1i32 }
            if direction == 2usize { ny = cy + 1i32 }
            if direction == 3usize { ny = cy - 1i32 }
            direction += 1usize
            if !tilemap.in_bounds(m, nx, ny) { continue }
            if tilemap.is_solid(m, nx, ny) { continue }
            let next = index_of(m, nx, ny)
            let stepped = s.cost[usize(current)] + 1u32
            if stepped < s.cost[usize(next)] {
                s.cost[usize(next)] = stepped
                s.came_from[usize(next)] = current
                try_push(s, next, stepped + heuristic(nx, ny, gx, gy))
            }
        }
    }
    ret (0usize, Unreachable)
}

// A push that cannot grow the heap drops the candidate rather than failing the search:
// the path found is then possibly not the shortest, which is better than no path at all
// when a caller has sized its scratch too small.
fn try_push(s: *Scratch, node: u32, f: u32) {
    let pushed = heap_push(s, node, f)
}

// Walk the parents back from the goal, then reverse in place, so the caller reads the
// path forwards.
fn unwind(s: *Scratch, start: u32, goal: u32, out: []u32) -> (usize, err) {
    var count = 0usize
    var walk = goal
    while true {
        if count == out.len { ret (0usize, Size) }
        out[count] = walk
        count += 1usize
        if walk == start { break }
        walk = s.came_from[usize(walk)]
        if walk == NONE { ret (0usize, Unreachable) }
    }
    var front = 0usize
    var back = count - 1usize
    while front < back {
        let held = out[front]
        out[front] = out[back]
        out[back] = held
        front += 1usize
        back = back - 1usize
    }
    ret (count, ok)
}
