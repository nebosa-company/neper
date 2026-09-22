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
use e.bytes

type Agent = struct { x: fixed.Fx, y: fixed.Fx, vx: fixed.Fx, vy: fixed.Fx, max_speed: fixed.Fx }

type Steer = struct { x: fixed.Fx, y: fixed.Fx }

type Kind = enum u8 { Sequence, Selector, Invert, Condition, Action }
type Status = enum u8 { Running, Success, Failure }

// A node's children are a run in the same array, so a tree is one flat table a game can
// author as a constant.
type Behavior = struct { kind: Kind, first_child: u16, child_count: u16, id: u16 }

// The search's working memory, sized by the caller to the map it will search.
type Scratch = struct { came_from: []u32, cost: []u32, heap: []u32, heap_f: []u32, heap_count: usize, seen: []u64 }

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

// --- game-tree search -----------------------------------------------------------------------
//
// Contract. A game is a record of function pointers over the caller's context. States are
// `u32` ids into a pool the caller owns: `apply(ctx, state, move)` copies `state`, plays
// `move` and answers the id of the copy; `release(ctx, id)` gives it back. Every search
// releases ids in the reverse order it obtained them, so a stack pool (release = pop back
// to `id`) is enough. `moves(ctx, state, out)` writes the legal moves into `out` in a fixed
// order, never more than `out.len`, and answers how many; a non-terminal state has at least
// one. `evaluate(ctx, state)` scores a state for the SIDE TO MOVE (negamax: a lost terminal
// is negative for the player who would move next). `is_terminal` ends a line.
// `is_capture(ctx, state, move)` marks the moves quiescence follows past the horizon.
// `chance_outcomes(ctx, state, out_states, out_weights)` answers how many outcomes a chance
// state has (0 for a decision state), each a fresh id like `apply`, with relative integer
// weights; the side to move is unchanged across a chance node and flips only across
// `apply`. `zobrist(ctx, state)` keys the transposition table. A game without chance,
// captures or a table passes functions answering 0 / false / 0.
//
// Scores are `i32`; `INF` bounds the window. Node budgets abort a search (`Budget`), which
// is what `iterative_deepening` relies on: it keeps the last depth that finished.

type Game[Ctx: type] = struct { ctx: *Ctx, moves: fn(*Ctx, u32, []u32) -> usize, apply: fn(*Ctx, u32, u32) -> u32, release: fn(*Ctx, u32), evaluate: fn(*Ctx, u32) -> i32, is_terminal: fn(*Ctx, u32) -> bool, is_capture: fn(*Ctx, u32, u32) -> bool, chance_outcomes: fn(*Ctx, u32, []u32, []i32) -> usize, zobrist: fn(*Ctx, u32) -> u64 }

type TtFlag = enum u8 { Empty, Exact, Lower, Upper }
type TtEntry = struct { key: u64, depth: u32, score: i32, flag: TtFlag, best: u32 }
type Tt = struct { entries: []TtEntry }

// `moves` and `weights` are slabs of `max_moves` per ply: a search at depth d needs
// `(d + 1) * max_moves` entries (quiescence and rollouts go deeper than `depth`). `tt`
// with no entries means no table.
type Search = struct { moves: []u32, weights: []i32, max_moves: usize, nodes: u64, budget: u64, aborted: bool, overflow: bool, best: u32, tt: Tt }

error Budget

const INF: i32 = 2000000000i32

fn transposition_table(entries: []TtEntry) -> Tt {
    var i = 0usize
    while i < entries.len {
        entries[i] = TtEntry { key: 0u64, depth: 0u32, score: 0i32, flag: .Empty, best: NONE }
        i += 1usize
    }
    ret Tt { entries: entries }
}

fn tt_probe(t: *const Tt, key: u64) -> (TtEntry, bool) {
    if t.entries.len == 0usize { ret (zero, false) }
    let entry = t.entries[usize(key % u64(t.entries.len))]
    if entry.flag == .Empty || entry.key != key { ret (zero, false) }
    ret (entry, true)
}

// Replace if the slot is empty, holds the same position, or the new entry is at least as
// deep; a shallower search of a different position never evicts a deeper one.
fn tt_store(t: *Tt, key: u64, depth: u32, score: i32, flag: TtFlag, best: u32) {
    if t.entries.len == 0usize { ret }
    let slot = usize(key % u64(t.entries.len))
    let held = t.entries[slot]
    if held.flag == .Empty || held.key == key || depth >= held.depth {
        t.entries[slot] = TtEntry { key: key, depth: depth, score: score, flag: flag, best: best }
    }
}

fn begin(s: *Search) {
    s.nodes = 0u64
    s.aborted = false
    s.overflow = false
    s.best = NONE
}

fn verdict(s: *const Search) -> err {
    if s.overflow { ret Size }
    if s.aborted { ret Budget }
    ret ok
}

// Count a node against the budget; false once the search is dead.
fn visit(s: *Search) -> bool {
    if s.aborted || s.overflow { ret false }
    s.nodes += 1u64
    if s.budget != 0u64 && s.nodes > s.budget { s.aborted = true }
    ret !s.aborted
}

fn slab(s: *Search, ply: u32) -> []u32 {
    let lo = usize(ply) * s.max_moves
    if lo + s.max_moves > s.moves.len {
        s.overflow = true
        ret s.moves[0usize..0usize]
    }
    ret s.moves[lo..lo + s.max_moves]
}

fn weight_slab(s: *Search, ply: u32) -> []i32 {
    let lo = usize(ply) * s.max_moves
    if lo + s.max_moves > s.weights.len {
        s.overflow = true
        ret s.weights[0usize..0usize]
    }
    ret s.weights[lo..lo + s.max_moves]
}

// Full-width negamax: every line to `depth`. The answer is (score, principal move, err).
fn minimax[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32) -> (i32, u32, err) {
    begin(s)
    let value = minimax_rec[Ctx](g, s, state, depth, 0u32)
    ret (value, s.best, verdict(s))
}

fn minimax_rec[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32, ply: u32) -> i32 {
    if !visit(s) { ret 0i32 }
    if g.is_terminal(g.ctx, state) || depth == 0u32 { ret g.evaluate(g.ctx, state) }
    let ms = slab(s, ply)
    if s.overflow { ret 0i32 }
    let count = g.moves(g.ctx, state, ms)
    var best = 0i32 - INF
    var best_move = NONE
    var i = 0usize
    while i < count {
        let child = g.apply(g.ctx, state, ms[i])
        let value = 0i32 - minimax_rec[Ctx](g, s, child, depth - 1u32, ply + 1u32)
        g.release(g.ctx, child)
        if s.aborted || s.overflow { ret 0i32 }
        if value > best {
            best = value
            best_move = ms[i]
        }
        i += 1usize
    }
    if ply == 0u32 { s.best = best_move }
    ret best
}

// Alpha-beta negamax, fail-soft, with the transposition table when `s.tt` has entries:
// the stored move is tried first and a deep enough entry answers or narrows the window.
fn alpha_beta[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32) -> (i32, u32, err) {
    begin(s)
    let value = alpha_beta_rec[Ctx](g, s, state, depth, 0u32, 0i32 - INF, INF)
    ret (value, s.best, verdict(s))
}

fn alpha_beta_rec[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32, ply: u32, alpha_in: i32, beta_in: i32) -> i32 {
    if !visit(s) { ret 0i32 }
    if g.is_terminal(g.ctx, state) || depth == 0u32 { ret g.evaluate(g.ctx, state) }
    var alpha = alpha_in
    var beta = beta_in
    var hint = NONE
    var key = 0u64
    if s.tt.entries.len > 0usize {
        key = g.zobrist(g.ctx, state)
        let (entry, hit) = tt_probe(&s.tt, key)
        if hit {
            hint = entry.best
            if entry.depth >= depth {
                if entry.flag == .Exact {
                    if ply == 0u32 { s.best = entry.best }
                    ret entry.score
                }
                if entry.flag == .Lower && entry.score > alpha { alpha = entry.score }
                if entry.flag == .Upper && entry.score < beta { beta = entry.score }
                if alpha >= beta {
                    if ply == 0u32 { s.best = entry.best }
                    ret entry.score
                }
            }
        }
    }
    let ms = slab(s, ply)
    if s.overflow { ret 0i32 }
    let count = g.moves(g.ctx, state, ms)
    if hint != NONE { hint_first(ms, count, hint) }
    var best = 0i32 - INF
    var best_move = NONE
    var i = 0usize
    while i < count {
        let child = g.apply(g.ctx, state, ms[i])
        let value = 0i32 - alpha_beta_rec[Ctx](g, s, child, depth - 1u32, ply + 1u32, 0i32 - beta, 0i32 - alpha)
        g.release(g.ctx, child)
        if s.aborted || s.overflow { ret 0i32 }
        if value > best {
            best = value
            best_move = ms[i]
        }
        if value > alpha { alpha = value }
        if alpha >= beta { break }
        i += 1usize
    }
    if s.tt.entries.len > 0usize {
        var flag = TtFlag.Exact
        if best <= alpha_in { flag = .Upper }
        if best > alpha_in && best >= beta { flag = .Lower }
        tt_store(&s.tt, key, depth, best, flag, best_move)
    }
    if ply == 0u32 { s.best = best_move }
    ret best
}

// Swap `hint` to the front of the move list, if it is there.
fn hint_first(ms: []u32, count: usize, hint: u32) {
    var i = 0usize
    while i < count {
        if ms[i] == hint {
            ms[i] = ms[0usize]
            ms[0usize] = hint
            ret
        }
        i += 1usize
    }
}

// Principal variation search (NegaScout): the first move gets the full window, the rest a
// null window, re-searched only when they beat alpha.
fn pvs[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32) -> (i32, u32, err) {
    begin(s)
    let value = pvs_rec[Ctx](g, s, state, depth, 0u32, 0i32 - INF, INF)
    ret (value, s.best, verdict(s))
}

fn pvs_rec[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32, ply: u32, alpha_in: i32, beta: i32) -> i32 {
    if !visit(s) { ret 0i32 }
    if g.is_terminal(g.ctx, state) || depth == 0u32 { ret g.evaluate(g.ctx, state) }
    var alpha = alpha_in
    let ms = slab(s, ply)
    if s.overflow { ret 0i32 }
    let count = g.moves(g.ctx, state, ms)
    var best = 0i32 - INF
    var best_move = NONE
    var i = 0usize
    while i < count {
        let child = g.apply(g.ctx, state, ms[i])
        var value = 0i32
        if i == 0usize {
            value = 0i32 - pvs_rec[Ctx](g, s, child, depth - 1u32, ply + 1u32, 0i32 - beta, 0i32 - alpha)
        } else {
            value = 0i32 - pvs_rec[Ctx](g, s, child, depth - 1u32, ply + 1u32, 0i32 - alpha - 1i32, 0i32 - alpha)
            if alpha < value && value < beta {
                value = 0i32 - pvs_rec[Ctx](g, s, child, depth - 1u32, ply + 1u32, 0i32 - beta, 0i32 - value)
            }
        }
        g.release(g.ctx, child)
        if s.aborted || s.overflow { ret 0i32 }
        if value > best {
            best = value
            best_move = ms[i]
        }
        if value > alpha { alpha = value }
        if alpha >= beta { break }
        i += 1usize
    }
    if ply == 0u32 { s.best = best_move }
    ret best
}

// Alpha-beta whose horizon is soft: at depth 0 a non-terminal state stands pat on its
// evaluation and then follows capture moves only, until none is left.
fn quiescence[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32) -> (i32, u32, err) {
    begin(s)
    let value = quiescence_rec[Ctx](g, s, state, depth, 0u32, 0i32 - INF, INF)
    ret (value, s.best, verdict(s))
}

fn quiescence_rec[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32, ply: u32, alpha_in: i32, beta: i32) -> i32 {
    if !visit(s) { ret 0i32 }
    if g.is_terminal(g.ctx, state) { ret g.evaluate(g.ctx, state) }
    var alpha = alpha_in
    var best = 0i32 - INF
    var best_move = NONE
    let quiet = depth == 0u32
    if quiet {
        let stand = g.evaluate(g.ctx, state)
        if stand >= beta { ret stand }
        best = stand
        if stand > alpha { alpha = stand }
    }
    let ms = slab(s, ply)
    if s.overflow { ret 0i32 }
    let count = g.moves(g.ctx, state, ms)
    var next_depth = 0u32
    if !quiet { next_depth = depth - 1u32 }
    var i = 0usize
    while i < count {
        if quiet && !g.is_capture(g.ctx, state, ms[i]) {
            i += 1usize
            continue
        }
        let child = g.apply(g.ctx, state, ms[i])
        let value = 0i32 - quiescence_rec[Ctx](g, s, child, next_depth, ply + 1u32, 0i32 - beta, 0i32 - alpha)
        g.release(g.ctx, child)
        if s.aborted || s.overflow { ret 0i32 }
        if value > best {
            best = value
            best_move = ms[i]
        }
        if value > alpha { alpha = value }
        if alpha >= beta { break }
        i += 1usize
    }
    if ply == 0u32 { s.best = best_move }
    ret best
}

// Expectimax: a chance state is worth the weight-averaged value of its outcomes (integer
// division, truncating), a decision state the best move. Both count one level of depth.
fn expectimax[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32) -> (i32, u32, err) {
    begin(s)
    let value = expectimax_rec[Ctx](g, s, state, depth, 0u32)
    ret (value, s.best, verdict(s))
}

fn expectimax_rec[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, depth: u32, ply: u32) -> i32 {
    if !visit(s) { ret 0i32 }
    if g.is_terminal(g.ctx, state) || depth == 0u32 { ret g.evaluate(g.ctx, state) }
    let ms = slab(s, ply)
    let ws = weight_slab(s, ply)
    if s.overflow { ret 0i32 }
    let outcomes = g.chance_outcomes(g.ctx, state, ms, ws)
    if outcomes > 0usize {
        var total = 0i64
        var acc = 0i64
        var o = 0usize
        while o < outcomes {
            let value = expectimax_rec[Ctx](g, s, ms[o], depth - 1u32, ply + 1u32)
            acc = acc + i64(ws[o]) * i64(value)
            total = total + i64(ws[o])
            o += 1usize
        }
        while o > 0usize {
            o = o - 1usize
            g.release(g.ctx, ms[o])
        }
        if s.aborted || s.overflow || total == 0i64 { ret 0i32 }
        ret i32(acc / total)
    }
    let count = g.moves(g.ctx, state, ms)
    var best = 0i32 - INF
    var best_move = NONE
    var i = 0usize
    while i < count {
        let child = g.apply(g.ctx, state, ms[i])
        let value = 0i32 - expectimax_rec[Ctx](g, s, child, depth - 1u32, ply + 1u32)
        g.release(g.ctx, child)
        if s.aborted || s.overflow { ret 0i32 }
        if value > best {
            best = value
            best_move = ms[i]
        }
        i += 1usize
    }
    if ply == 0u32 { s.best = best_move }
    ret best
}

// Alpha-beta at depth 1, 2, ... `max_depth`, sharing `s.tt` between iterations so each
// one orders by the last. `budget` nodes in total (0 = unlimited): the iteration that
// exhausts it is discarded and the answer is the last complete one, with its depth. The
// error is `Budget` only when not even depth 1 finished.
fn iterative_deepening[Ctx: type](g: *const Game[Ctx], s: *Search, state: u32, max_depth: u32, budget: u64) -> (i32, u32, u32, err) {
    begin(s)
    s.budget = budget
    var score = 0i32
    var best_move = NONE
    var done = 0u32
    var depth = 1u32
    while depth <= max_depth {
        let value = alpha_beta_rec[Ctx](g, s, state, depth, 0u32, 0i32 - INF, INF)
        if s.overflow { ret (score, best_move, done, Size) }
        if s.aborted { break }
        score = value
        best_move = s.best
        done = depth
        depth += 1u32
    }
    if done == 0u32 { ret (0i32, NONE, 0u32, Budget) }
    ret (score, best_move, done, ok)
}

// --- Monte Carlo tree search --------------------------------------------------------------
//
// UCT with an integer UCB1: exploitation is mean reward in Q16, exploration is
// `c * sqrt(ln(N) / n)` in Q16 through `log2_fx`, so two machines pick the same child.
// Expansion takes the untried moves in the order `moves` lists them; the rollout plays
// moves drawn from the caller's generator to a terminal state. Rewards are +1/0/-1 for the
// player who moved INTO a node (the sign of `evaluate` at the terminal, flipped back up
// the rollout and the tree). Tree states are released in reverse when the search ends;
// the root is the caller's. The best move is the root child with the most visits.

type MctsNode = struct { state: u32, parent: u32, move: u32, first_child: u32, next_sibling: u32, child_count: u32, visits: u32, wins: i32 }

// `moves` holds one move list (max moves of any state); `rollout` holds the ids of one
// playout (the longest game); `c` is the exploration weight in Q16 (sqrt 2 = 92682).
type Mcts = struct { nodes: []MctsNode, count: usize, moves: []u32, rollout: []u32, c: fixed.Fx }

// Q16 log2 of `n >= 1`, by repeated squaring of the mantissa.
fn log2_fx(n: u64) -> i64 {
    var x = n
    var whole = 0u32
    while x >= 2u64 {
        x = x >> 1u32
        whole += 1u32
    }
    var y = (n << 16u32) >> whole
    var frac = 0u64
    var i = 0u32
    while i < 16u32 {
        y = (y * y) >> 16u32
        if y >= 131072u64 {
            y = y >> 1u32
            frac = frac | (1u64 << (15u32 - i))
        }
        i += 1u32
    }
    ret i64((u64(whole) << 16u32) | frac)
}

fn ln_fx(n: u64) -> i64 {
    ret (log2_fx(n) * 45426i64) >> 16u32
}

fn sign_of(v: i32) -> i32 {
    if v > 0i32 { ret 1i32 }
    if v < 0i32 { ret -1i32 }
    ret 0i32
}

fn select_child(m: *Mcts, n: usize) -> usize {
    let ln_n = ln_fx(u64(m.nodes[n].visits))
    var best = 0i64
    var best_child = NONE
    var ch = m.nodes[n].first_child
    while ch != NONE {
        let c = m.nodes[usize(ch)]
        let exploit = (i64(c.wins) * 65536i64) / i64(c.visits)
        let (root, root_error) = fixed.sqrt(i32(ln_n / i64(c.visits)))
        let explore = i64(fixed.mul(m.c, root))
        let ucb = exploit + explore
        if best_child == NONE || ucb > best {
            best = ucb
            best_child = ch
        }
        ch = c.next_sibling
    }
    ret usize(best_child)
}

fn release_tree[Ctx: type](g: *const Game[Ctx], m: *Mcts) {
    var k = m.count
    while k > 1usize {
        k = k - 1usize
        g.release(g.ctx, m.nodes[k].state)
    }
}

fn mcts[Ctx: type](g: *const Game[Ctx], m: *Mcts, root: u32, iterations: u32, r: *rand.Pcg64) -> (u32, err) {
    if m.nodes.len == 0usize { ret (NONE, Size) }
    m.nodes[0usize] = MctsNode { state: root, parent: NONE, move: NONE, first_child: NONE, next_sibling: NONE, child_count: 0u32, visits: 0u32, wins: 0i32 }
    m.count = 1usize
    var it = 0u32
    while it < iterations {
        // Selection: down the tree while every move is already a child.
        var n = 0usize
        while true {
            let st = m.nodes[n].state
            if g.is_terminal(g.ctx, st) { break }
            let count = g.moves(g.ctx, st, m.moves)
            if usize(m.nodes[n].child_count) < count { break }
            n = select_child(m, n)
        }
        // Expansion: the next untried move becomes a child.
        var st = m.nodes[n].state
        if !g.is_terminal(g.ctx, st) {
            if m.count >= m.nodes.len {
                release_tree[Ctx](g, m)
                ret (NONE, Size)
            }
            let count = g.moves(g.ctx, st, m.moves)
            let mv = m.moves[usize(m.nodes[n].child_count)]
            let ci = m.count
            m.nodes[ci] = MctsNode { state: g.apply(g.ctx, st, mv), parent: u32(n), move: mv, first_child: NONE, next_sibling: NONE, child_count: 0u32, visits: 0u32, wins: 0i32 }
            m.count = ci + 1usize
            if m.nodes[n].first_child == NONE {
                m.nodes[n].first_child = u32(ci)
            } else {
                var tail = usize(m.nodes[n].first_child)
                while m.nodes[tail].next_sibling != NONE { tail = usize(m.nodes[tail].next_sibling) }
                m.nodes[tail].next_sibling = u32(ci)
            }
            m.nodes[n].child_count = m.nodes[n].child_count + 1u32
            n = ci
            st = m.nodes[n].state
        }
        // Rollout.
        var length = 0usize
        var cur = st
        while !g.is_terminal(g.ctx, cur) {
            if length >= m.rollout.len {
                while length > 0usize {
                    length = length - 1usize
                    g.release(g.ctx, m.rollout[length])
                }
                release_tree[Ctx](g, m)
                ret (NONE, Size)
            }
            let count = g.moves(g.ctx, cur, m.moves)
            let pick = m.moves[usize(rand.pcg64_bounded(r, u64(count)))]
            cur = g.apply(g.ctx, cur, pick)
            m.rollout[length] = cur
            length += 1usize
        }
        var v = sign_of(g.evaluate(g.ctx, cur))
        var k = length
        while k > 0usize {
            k = k - 1usize
            g.release(g.ctx, m.rollout[k])
        }
        if length % 2usize == 1usize { v = 0i32 - v }
        // Backpropagation.
        var reward = 0i32 - v
        var walk = u32(n)
        while walk != NONE {
            m.nodes[usize(walk)].visits = m.nodes[usize(walk)].visits + 1u32
            m.nodes[usize(walk)].wins = m.nodes[usize(walk)].wins + reward
            reward = 0i32 - reward
            walk = m.nodes[usize(walk)].parent
        }
        it += 1u32
    }
    var best_move = NONE
    var best_visits = 0u32
    var ch = m.nodes[0usize].first_child
    while ch != NONE {
        let c = m.nodes[usize(ch)]
        if best_move == NONE || c.visits > best_visits {
            best_visits = c.visits
            best_move = c.move
        }
        ch = c.next_sibling
    }
    release_tree[Ctx](g, m)
    ret (best_move, ok)
}

// --- behaviour trees with resumption ------------------------------------------------------
//
// Unlike `run`, a `BtNode` tree calls a leaf function and remembers, per node in `state`
// (one `u16` per node, zero to start), which child was running so the next tick resumes
// there. `Repeat` runs its child `limit` times (0 = forever, one pass per tick).

type BtKind = enum u8 { Sequence, Selector, Inverter, Succeeder, Repeat, Leaf }
type BtNode = struct { kind: BtKind, first_child: u16, child_count: u16, id: u16, limit: u16 }

fn behavior_tick[Ctx: type](tree: []const BtNode, state: []u16, node: u16, ctx: *Ctx, leaf: fn(*Ctx, u16) -> Status) -> Status {
    let slot = usize(node)
    if slot >= tree.len || slot >= state.len { ret .Failure }
    let n = tree[slot]
    if n.kind == .Leaf { ret leaf(ctx, n.id) }
    if n.kind == .Inverter {
        let inner = behavior_tick[Ctx](tree, state, n.first_child, ctx, leaf)
        if inner == .Success { ret .Failure }
        if inner == .Failure { ret .Success }
        ret .Running
    }
    if n.kind == .Succeeder {
        let inner = behavior_tick[Ctx](tree, state, n.first_child, ctx, leaf)
        if inner == .Running { ret .Running }
        ret .Success
    }
    if n.kind == .Repeat {
        while true {
            let inner = behavior_tick[Ctx](tree, state, n.first_child, ctx, leaf)
            if inner == .Running { ret .Running }
            if inner == .Failure {
                state[slot] = 0u16
                ret .Failure
            }
            state[slot] = state[slot] + 1u16
            if n.limit == 0u16 { ret .Running }
            if state[slot] >= n.limit {
                state[slot] = 0u16
                ret .Success
            }
        }
    }
    // Sequence stops at the first failure, selector at the first success.
    var stop = Status.Failure
    if n.kind == .Selector { stop = .Success }
    var i = state[slot]
    while i < n.child_count {
        let r = behavior_tick[Ctx](tree, state, n.first_child + i, ctx, leaf)
        if r == .Running {
            state[slot] = i
            ret .Running
        }
        if r == stop {
            state[slot] = 0u16
            ret r
        }
        i += 1u16
    }
    state[slot] = 0u16
    if n.kind == .Sequence { ret .Success }
    ret .Failure
}

// --- goal-oriented action planning -------------------------------------------------------
//
// World state is a bitmask; an action applies when `(state & pre_mask) == pre_value` and
// yields `(state & ~effect_mask) | effect_value`. A* from `start` to any state matching
// the goal, heuristic = goal bits still wrong (admissible while no action sets more goal
// bits than its cost). The plan is written into `out` as action indices.

type GoapAction = struct { pre_mask: u32, pre_value: u32, effect_mask: u32, effect_value: u32, cost: u32 }
type GoapScratch = struct { states: []u32, cost: []u32, parent: []u32, action: []u32, closed: []u8 }

fn goap_find(s: *GoapScratch, count: usize, state: u32) -> usize {
    var i = 0usize
    while i < count {
        if s.states[i] == state { ret i }
        i += 1usize
    }
    ret count
}

// ponytail: open set and duplicate check are linear scans; a heap and a hash would
// matter past a few hundred reachable states.
fn goap_plan(start: u32, goal_mask: u32, goal_value: u32, actions: []const GoapAction, s: *GoapScratch, out: []u32) -> (usize, u32, err) {
    let cap = s.states.len
    if cap == 0usize || s.cost.len < cap || s.parent.len < cap || s.action.len < cap || s.closed.len < cap { ret (0usize, 0u32, Size) }
    s.states[0usize] = start
    s.cost[0usize] = 0u32
    s.parent[0usize] = NONE
    s.action[0usize] = NONE
    s.closed[0usize] = 0u8
    var count = 1usize
    while true {
        var best_f = 0u32
        var best = NONE
        var i = 0usize
        while i < count {
            if s.closed[i] == 0u8 {
                let f = s.cost[i] + bytes.count_ones[u32]((s.states[i] ^ goal_value) & goal_mask)
                if best == NONE || f < best_f {
                    best_f = f
                    best = u32(i)
                }
            }
            i += 1usize
        }
        if best == NONE { ret (0usize, 0u32, Unreachable) }
        let current = usize(best)
        s.closed[current] = 1u8
        let here = s.states[current]
        if (here & goal_mask) == (goal_value & goal_mask) {
            var length = 0usize
            var walk = current
            while s.parent[walk] != NONE {
                if length == out.len { ret (0usize, 0u32, Size) }
                out[length] = s.action[walk]
                length += 1usize
                walk = usize(s.parent[walk])
            }
            var lo = 0usize
            var hi = length
            while lo + 1usize < hi {
                hi = hi - 1usize
                let held = out[lo]
                out[lo] = out[hi]
                out[hi] = held
                lo += 1usize
            }
            ret (length, s.cost[current], ok)
        }
        var a = 0usize
        while a < actions.len {
            let act = actions[a]
            a += 1usize
            if (here & act.pre_mask) != (act.pre_value & act.pre_mask) { continue }
            let next_state = (here & ~act.effect_mask) | (act.effect_value & act.effect_mask)
            let next_cost = s.cost[current] + act.cost
            let found = goap_find(s, count, next_state)
            if found == count {
                if count >= cap { ret (0usize, 0u32, Size) }
                s.states[count] = next_state
                s.cost[count] = next_cost
                s.parent[count] = u32(current)
                s.action[count] = u32(a - 1usize)
                s.closed[count] = 0u8
                count += 1usize
            } else if next_cost < s.cost[found] && s.closed[found] == 0u8 {
                s.cost[found] = next_cost
                s.parent[found] = u32(current)
                s.action[found] = u32(a - 1usize)
            }
        }
    }
    ret (0usize, 0u32, Unreachable)
}

// --- utility AI ---------------------------------------------------------------------------
//
// Each choice is a run of considerations; each maps a normalised input (Q16, 0..ONE)
// through a curve, clamped to 0..ONE, and the choice scores their product. Curves, with
// `d = x - c`: Linear `m*d + b`, Quadratic `m*d*d + b`, Logistic `b + m / (1 + exp(-k*d))`.

type Curve = enum u8 { Linear, Quadratic, Logistic }
type Consideration = struct { curve: Curve, input: u16, m: fixed.Fx, k: fixed.Fx, b: fixed.Fx, c: fixed.Fx }
type Choice = struct { first: u16, count: u16 }

// Q16 exp by range reduction to ln 2 and eight Taylor terms; the argument is clamped to
// +-16 so the result fits.
fn exp_fx(x_in: i64) -> i64 {
    var x = x_in
    if x < -1048576i64 { x = -1048576i64 }
    if x > 1048576i64 { x = 1048576i64 }
    let n = x / 45426i64
    let r = x - n * 45426i64
    var term = 65536i64
    var acc = 65536i64
    var k = 1i64
    while k <= 8i64 {
        term = (term * r) / 65536i64
        term = term / k
        acc = acc + term
        k += 1i64
    }
    if n >= 0i64 { ret acc << u32(n) }
    ret acc >> u32(0i64 - n)
}

fn consider(con: Consideration, x: fixed.Fx) -> fixed.Fx {
    let d = x - con.c
    var y = 0i32
    if con.curve == .Linear { y = fixed.mul(con.m, d) + con.b }
    if con.curve == .Quadratic { y = fixed.mul(con.m, fixed.mul(d, d)) + con.b }
    if con.curve == .Logistic {
        let e = exp_fx(0i64 - i64(fixed.mul(con.k, d)))
        y = con.b + i32((i64(con.m) << 16u32) / (65536i64 + e))
    }
    ret fixed.clamp(y, 0i32, fixed.ONE)
}

// The best-scoring choice, earliest on ties; (index, score).
fn utility_select(choices: []const Choice, considerations: []const Consideration, inputs: []const fixed.Fx) -> (usize, fixed.Fx) {
    var best = 0i32
    var best_choice = 0usize
    var i = 0usize
    while i < choices.len {
        let ch = choices[i]
        var score = fixed.ONE
        var j = usize(ch.first)
        while j < usize(ch.first) + usize(ch.count) && j < considerations.len {
            let con = considerations[j]
            var x = 0i32
            if usize(con.input) < inputs.len { x = inputs[usize(con.input)] }
            score = fixed.mul(score, consider(con, x))
            j += 1usize
        }
        if i == 0usize || score > best {
            best = score
            best_choice = i
        }
        i += 1usize
    }
    ret (best_choice, best)
}

// --- boids ----------------------------------------------------------------------------------

// Reynolds flocking for `flock[which]`: separation from everything inside `radius`
// (`separate`), alignment toward the neighbours' mean velocity and cohesion toward their
// centre (`seek`), each weighted in Q16 and summed with `combine`.
fn boids(flock: []const Agent, which: usize, radius: fixed.Fx, w_separate: fixed.Fx, w_align: fixed.Fx, w_cohere: fixed.Fx) -> Steer {
    let a = flock[which]
    var parts: [3]Steer = zero
    var weights: [3]fixed.Fx = zero
    parts[0usize] = separate(a, flock, radius)
    weights[0usize] = w_separate
    weights[1usize] = w_align
    weights[2usize] = w_cohere
    var near = 0i32
    var sum_vx = 0i32
    var sum_vy = 0i32
    var sum_x = 0i32
    var sum_y = 0i32
    var i = 0usize
    while i < flock.len {
        if i != which {
            let o = flock[i]
            if fixed.length(a.x - o.x, a.y - o.y) < radius {
                near += 1i32
                sum_vx = sum_vx + o.vx
                sum_vy = sum_vy + o.vy
                sum_x = sum_x + o.x
                sum_y = sum_y + o.y
            }
        }
        i += 1usize
    }
    if near > 0i32 {
        let (unit_x, unit_y) = fixed.normalize(sum_vx / near, sum_vy / near)
        parts[1usize] = Steer { x: fixed.mul(unit_x, a.max_speed) - a.vx, y: fixed.mul(unit_y, a.max_speed) - a.vy }
        parts[2usize] = seek(a, sum_x / near, sum_y / near)
    }
    ret combine(parts[..], weights[..])
}
