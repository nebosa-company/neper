// 2-d motion planners over caller storage: `rrt`, `rrt_star` (rewiring within
// a fixed radius), `rrt_connect` (two trees), `rrt_informed` (ellipsoidal
// sampling once a solution exists), `rrt_kinodynamic` (x, y, theta states
// grown by sampled (v, omega) controls), `prm` (sample, link k nearest,
// Dijkstra), `hybrid_astar` (x, y, heading bins over three fixed-arc
// primitives) and `state_lattice` (Dijkstra over snapped primitives on a
// heading lattice). Obstacles are circles; nodes live in a caller `Pool`
// (`xs`, `ys`, optional `th`, `parent`, `cost`); `path_extract` walks a node
// back to its root.
//
// Random-number order, so a replica with the same PCG stream grows the same
// tree: each RRT iteration draws one f64 for the goal bias, then x, then y
// (nothing more when the bias fires); informed sampling draws the bias, then
// (u, v) pairs until one lies in the unit disc; connect draws x then y;
// kinodynamic draws v then omega per control sample; PRM draws x then y per
// candidate node until a free one comes. Nearest is a linear scan from node
// 0 taking the first strict minimum; steer stops at `step`; a tie in a heap
// keeps the earlier push.

use e.algo.rand
use e.math

type Circle = struct { x: f64, y: f64, r: f64 }
type Pool = struct { xs: []f64, ys: []f64, th: []f64, parent: []u32, cost: []f64, used: usize }
// `radius` is the RRT* rewiring radius; `iterations` bounds the sampling loops.
type Config = struct { min_x: f64, min_y: f64, max_x: f64, max_y: f64, step: f64, radius: f64, goal_bias: f64, goal_tolerance: f64, iterations: usize }
type Kino = struct { v_min: f64, v_max: f64, omega_max: f64, dt: f64, substeps: usize, controls: usize }
// A grid of `w` x `h` cells of size `cell` from (`min_x`, `min_y`) with `headings` bins;
// primitives are arcs of length `arc` at curvature 0 and +-1/`radius`, collision-checked
// in `substeps` pieces.
type Grid = struct { cell: f64, w: usize, h: usize, headings: usize, arc: f64, radius: f64, substeps: usize }
type Heap = struct { key: []f64, node: []u32, used: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn two_pi() -> f64 { ret 6.283185307179586f64 }

// A pool without headings; `th` is empty.
fn pool(xs: []f64, ys: []f64, parent: []u32, cost: []f64) -> Pool {
    ret Pool { xs: xs, ys: ys, th: xs[..0usize], parent: parent, cost: cost, used: 0usize }
}

// A pool with a heading per node, for the kinodynamic, hybrid A* and lattice planners.
fn pool_th(xs: []f64, ys: []f64, th: []f64, parent: []u32, cost: []f64) -> Pool {
    ret Pool { xs: xs, ys: ys, th: th, parent: parent, cost: cost, used: 0usize }
}

fn add_node(p: *Pool, x: f64, y: f64, th: f64, parent: u32, cost: f64) -> (u32, err) {
    if p.used >= p.xs.len || p.used >= p.ys.len || p.used >= p.parent.len || p.used >= p.cost.len { ret (NONE, TooSmall) }
    if p.th.len > 0usize {
        if p.used >= p.th.len { ret (NONE, TooSmall) }
        p.th[p.used] = th
    }
    let id = p.used
    p.used += 1usize
    p.xs[id] = x
    p.ys[id] = y
    p.parent[id] = parent
    p.cost[id] = cost
    ret (u32(id), ok)
}

fn distance(x0: f64, y0: f64, x1: f64, y1: f64) -> f64 {
    let dx = x1 - x0
    let dy = y1 - y0
    ret math.sqrt[f64](dx * dx + dy * dy)
}

// True when the segment keeps clear of every circle (touching counts as a hit).
fn collision_free(x0: f64, y0: f64, x1: f64, y1: f64, obstacles: []const Circle) -> bool {
    let dx = x1 - x0
    let dy = y1 - y0
    let len2 = dx * dx + dy * dy
    var i = 0usize
    while i < obstacles.len {
        let o = obstacles[i]
        var t = 0.0f64
        if len2 > 0.0f64 {
            t = ((o.x - x0) * dx + (o.y - y0) * dy) / len2
            if t < 0.0f64 { t = 0.0f64 }
            if t > 1.0f64 { t = 1.0f64 }
        }
        let cx = x0 + t * dx - o.x
        let cy = y0 + t * dy - o.y
        if cx * cx + cy * cy <= o.r * o.r { ret false }
        i += 1usize
    }
    ret true
}

fn point_free(x: f64, y: f64, obstacles: []const Circle) -> bool { ret collision_free(x, y, x, y, obstacles) }

// The node nearest (x, y) by Euclidean distance; `NONE` for an empty pool.
fn nearest(p: *const Pool, x: f64, y: f64) -> u32 {
    var best = NONE
    var best_d = 0.0f64
    var i = 0usize
    while i < p.used {
        let dx = p.xs[i] - x
        let dy = p.ys[i] - y
        let d = dx * dx + dy * dy
        if best == NONE || d < best_d {
            best = u32(i)
            best_d = d
        }
        i += 1usize
    }
    ret best
}

fn sample(cfg: *const Config, rng: *rand.Pcg64, gx: f64, gy: f64) -> (f64, f64) {
    if rand.pcg64_f64(rng) < cfg.goal_bias { ret (gx, gy) }
    let x = cfg.min_x + rand.pcg64_f64(rng) * (cfg.max_x - cfg.min_x)
    let y = cfg.min_y + rand.pcg64_f64(rng) * (cfg.max_y - cfg.min_y)
    ret (x, y)
}

// From node `n` toward (sx, sy) by at most `step`; answers the point and its distance from `n`.
fn steer(p: *const Pool, n: u32, sx: f64, sy: f64, step: f64) -> (f64, f64, f64) {
    let x0 = p.xs[usize(n)]
    let y0 = p.ys[usize(n)]
    let d = distance(x0, y0, sx, sy)
    if d <= step { ret (sx, sy, d) }
    let x = x0 + (sx - x0) / d * step
    let y = y0 + (sy - y0) / d * step
    ret (x, y, distance(x0, y0, x, y))
}

// #559 RRT: answers the first node within `goal_tolerance` of the goal, or `NONE`.
fn rrt(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, gx: f64, gy: f64) -> (u32, err) {
    p.used = 0usize
    let (_, root_error) = add_node(p, sx, sy, 0.0f64, NONE, 0.0f64)
    if root_error != ok { ret (NONE, root_error) }
    var it = 0usize
    while it < cfg.iterations {
        it += 1usize
        let (qx, qy) = sample(cfg, rng, gx, gy)
        let near = nearest(p, qx, qy)
        let (nx, ny, d) = steer(p, near, qx, qy, cfg.step)
        if !collision_free(p.xs[usize(near)], p.ys[usize(near)], nx, ny, obstacles) { continue }
        let (node, node_error) = add_node(p, nx, ny, 0.0f64, near, p.cost[usize(near)] + d)
        if node_error != ok { ret (NONE, node_error) }
        if distance(nx, ny, gx, gy) <= cfg.goal_tolerance { ret (node, ok) }
    }
    ret (NONE, ok)
}

// Re-derive every cost from its parent after a rewire, until nothing moves.
// ponytail: O(n * depth) per rewire; a child list would make it one subtree walk.
fn propagate(p: *Pool) {
    var changed = true
    while changed {
        changed = false
        var i = 1usize
        while i < p.used {
            let q = usize(p.parent[i])
            let c = p.cost[q] + distance(p.xs[q], p.ys[q], p.xs[i], p.ys[i])
            if c != p.cost[i] {
                p.cost[i] = c
                changed = true
            }
            i += 1usize
        }
    }
}

// The cheapest node within `goal_tolerance` of the goal, or `NONE`.
fn best_goal(p: *const Pool, gx: f64, gy: f64, tolerance: f64) -> u32 {
    var best = NONE
    var i = 0usize
    while i < p.used {
        if distance(p.xs[i], p.ys[i], gx, gy) <= tolerance && (best == NONE || p.cost[i] < p.cost[usize(best)]) { best = u32(i) }
        i += 1usize
    }
    ret best
}

// A point of the ellipse with foci start and goal and major axis `c_best`, clamped to the bounds.
fn sample_ellipse(cfg: *const Config, rng: *rand.Pcg64, sx: f64, sy: f64, gx: f64, gy: f64, c_min: f64, c_best: f64) -> (f64, f64) {
    if rand.pcg64_f64(rng) < cfg.goal_bias { ret (gx, gy) }
    var u = 0.0f64
    var v = 0.0f64
    while true {
        u = 2.0f64 * rand.pcg64_f64(rng) - 1.0f64
        v = 2.0f64 * rand.pcg64_f64(rng) - 1.0f64
        if u * u + v * v <= 1.0f64 { break }
    }
    let a = c_best / 2.0f64
    var b = 0.0f64
    if c_best > c_min { b = math.sqrt[f64](c_best * c_best - c_min * c_min) / 2.0f64 }
    var cs = 1.0f64
    var sn = 0.0f64
    if c_min > 0.0f64 {
        cs = (gx - sx) / c_min
        sn = (gy - sy) / c_min
    }
    let ex = a * u
    let ey = b * v
    var x = (sx + gx) / 2.0f64 + cs * ex - sn * ey
    var y = (sy + gy) / 2.0f64 + sn * ex + cs * ey
    if x < cfg.min_x { x = cfg.min_x }
    if x > cfg.max_x { x = cfg.max_x }
    if y < cfg.min_y { y = cfg.min_y }
    if y > cfg.max_y { y = cfg.max_y }
    ret (x, y)
}

fn rrt_star_run(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, gx: f64, gy: f64, informed: bool) -> (u32, err) {
    p.used = 0usize
    let (_, root_error) = add_node(p, sx, sy, 0.0f64, NONE, 0.0f64)
    if root_error != ok { ret (NONE, root_error) }
    let c_min = distance(sx, sy, gx, gy)
    var best = NONE
    var it = 0usize
    while it < cfg.iterations {
        it += 1usize
        var qx = 0.0f64
        var qy = 0.0f64
        if informed && best != NONE {
            let (ex, ey) = sample_ellipse(cfg, rng, sx, sy, gx, gy, c_min, p.cost[usize(best)])
            qx = ex
            qy = ey
        } else {
            let (ux, uy) = sample(cfg, rng, gx, gy)
            qx = ux
            qy = uy
        }
        let near = nearest(p, qx, qy)
        let (nx, ny, d) = steer(p, near, qx, qy, cfg.step)
        if !collision_free(p.xs[usize(near)], p.ys[usize(near)], nx, ny, obstacles) { continue }
        var parent = near
        var parent_cost = p.cost[usize(near)] + d
        var i = 0usize
        while i < p.used {
            if u32(i) != near {
                let di = distance(p.xs[i], p.ys[i], nx, ny)
                if di <= cfg.radius {
                    let c = p.cost[i] + di
                    if c < parent_cost && collision_free(p.xs[i], p.ys[i], nx, ny, obstacles) {
                        parent = u32(i)
                        parent_cost = c
                    }
                }
            }
            i += 1usize
        }
        let (node, node_error) = add_node(p, nx, ny, 0.0f64, parent, parent_cost)
        if node_error != ok { ret (NONE, node_error) }
        var rewired = false
        i = 0usize
        while i + 1usize < p.used {
            if u32(i) != parent {
                let di = distance(p.xs[i], p.ys[i], nx, ny)
                if di <= cfg.radius {
                    let c = parent_cost + di
                    if c < p.cost[i] && collision_free(nx, ny, p.xs[i], p.ys[i], obstacles) {
                        p.parent[i] = node
                        p.cost[i] = c
                        rewired = true
                    }
                }
            }
            i += 1usize
        }
        if rewired { propagate(p) }
        best = best_goal(p, gx, gy, cfg.goal_tolerance)
    }
    ret (best, ok)
}

// #560 RRT*: every iteration runs; answers the cheapest node within `goal_tolerance`.
fn rrt_star(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, gx: f64, gy: f64) -> (u32, err) {
    let (node, e) = rrt_star_run(cfg, obstacles, rng, p, sx, sy, gx, gy, false)
    ret (node, e)
}

// #1836 Informed RRT*: RRT* whose samples come from the solution ellipse once one exists.
fn rrt_informed(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, gx: f64, gy: f64) -> (u32, err) {
    let (node, e) = rrt_star_run(cfg, obstacles, rng, p, sx, sy, gx, gy, true)
    ret (node, e)
}

// One step of tree `t` toward (qx, qy): the new node or `NONE` when blocked, and whether it reached q.
fn extend(cfg: *const Config, obstacles: []const Circle, t: *Pool, qx: f64, qy: f64) -> (u32, bool, err) {
    let near = nearest(t, qx, qy)
    let (nx, ny, d) = steer(t, near, qx, qy, cfg.step)
    if !collision_free(t.xs[usize(near)], t.ys[usize(near)], nx, ny, obstacles) { ret (NONE, false, ok) }
    let (node, node_error) = add_node(t, nx, ny, 0.0f64, near, t.cost[usize(near)] + d)
    if node_error != ok { ret (NONE, false, node_error) }
    ret (node, nx == qx && ny == qy, ok)
}

// Extend `t` toward q until it arrives or is blocked; answers the node that arrived and whether it did.
fn connect_toward(cfg: *const Config, obstacles: []const Circle, t: *Pool, qx: f64, qy: f64) -> (u32, bool, err) {
    while true {
        let (node, reached, e) = extend(cfg, obstacles, t, qx, qy)
        if e != ok { ret (NONE, false, e) }
        if node == NONE { ret (NONE, false, ok) }
        if reached { ret (node, true, ok) }
    }
    ret (NONE, false, ok)
}

// #1835 RRT-Connect: trees `a` from the start and `b` from the goal, extended in turn (a on odd
// iterations); answers the meeting nodes (one per tree, at the same point) or (`NONE`, `NONE`).
fn rrt_connect(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, a: *Pool, b: *Pool, sx: f64, sy: f64, gx: f64, gy: f64) -> (u32, u32, err) {
    a.used = 0usize
    b.used = 0usize
    let (_, a_error) = add_node(a, sx, sy, 0.0f64, NONE, 0.0f64)
    if a_error != ok { ret (NONE, NONE, a_error) }
    let (_, b_error) = add_node(b, gx, gy, 0.0f64, NONE, 0.0f64)
    if b_error != ok { ret (NONE, NONE, b_error) }
    var it = 0usize
    while it < cfg.iterations {
        it += 1usize
        let qx = cfg.min_x + rand.pcg64_f64(rng) * (cfg.max_x - cfg.min_x)
        let qy = cfg.min_y + rand.pcg64_f64(rng) * (cfg.max_y - cfg.min_y)
        if it % 2usize == 1usize {
            let (na, _, ea) = extend(cfg, obstacles, a, qx, qy)
            if ea != ok { ret (NONE, NONE, ea) }
            if na != NONE {
                let (nb, met, eb) = connect_toward(cfg, obstacles, b, a.xs[usize(na)], a.ys[usize(na)])
                if eb != ok { ret (NONE, NONE, eb) }
                if met { ret (na, nb, ok) }
            }
        } else {
            let (nb, _, eb) = extend(cfg, obstacles, b, qx, qy)
            if eb != ok { ret (NONE, NONE, eb) }
            if nb != NONE {
                let (na, met, ea) = connect_toward(cfg, obstacles, a, b.xs[usize(nb)], b.ys[usize(nb)])
                if ea != ok { ret (NONE, NONE, ea) }
                if met { ret (na, nb, ok) }
            }
        }
    }
    ret (NONE, NONE, ok)
}

// Integrate (v, omega) from node `n` for `dt` in `substeps` Euler steps, collision-checked per step.
fn roll_out(kino: *const Kino, obstacles: []const Circle, x0: f64, y0: f64, th0: f64, v: f64, omega: f64) -> (bool, f64, f64, f64) {
    let h = kino.dt / f64(kino.substeps)
    var x = x0
    var y = y0
    var th = th0
    var s = 0usize
    while s < kino.substeps {
        let px = x
        let py = y
        th = th + omega * h
        x = x + v * math.cos[f64](th) * h
        y = y + v * math.sin[f64](th) * h
        if !collision_free(px, py, x, y, obstacles) { ret (false, x, y, th) }
        s += 1usize
    }
    ret (true, x, y, th)
}

// #1834 Kinodynamic RRT over (x, y, theta): each iteration samples a point, takes its nearest
// node and tries `controls` random (v, omega) pairs for `dt`, keeping the free roll-out that
// ends closest to the sample; the cost is |v| * dt. The pool needs `th`.
fn rrt_kinodynamic(cfg: *const Config, kino: *const Kino, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, sth: f64, gx: f64, gy: f64) -> (u32, err) {
    if p.th.len == 0usize || kino.substeps == 0usize { ret (NONE, Invalid) }
    p.used = 0usize
    let (_, root_error) = add_node(p, sx, sy, sth, NONE, 0.0f64)
    if root_error != ok { ret (NONE, root_error) }
    var it = 0usize
    while it < cfg.iterations {
        it += 1usize
        let (qx, qy) = sample(cfg, rng, gx, gy)
        let near = usize(nearest(p, qx, qy))
        var found = false
        var bx = 0.0f64
        var by = 0.0f64
        var bth = 0.0f64
        var bv = 0.0f64
        var bd = 0.0f64
        var k = 0usize
        while k < kino.controls {
            let v = kino.v_min + rand.pcg64_f64(rng) * (kino.v_max - kino.v_min)
            let omega = (2.0f64 * rand.pcg64_f64(rng) - 1.0f64) * kino.omega_max
            let (free, x, y, th) = roll_out(kino, obstacles, p.xs[near], p.ys[near], p.th[near], v, omega)
            if free {
                let d = distance(x, y, qx, qy)
                if !found || d < bd {
                    found = true
                    bx = x
                    by = y
                    bth = th
                    bv = v
                    bd = d
                }
            }
            k += 1usize
        }
        if !found { continue }
        let (node, node_error) = add_node(p, bx, by, bth, u32(near), p.cost[near] + math.abs[f64](bv) * kino.dt)
        if node_error != ok { ret (NONE, node_error) }
        if distance(bx, by, gx, gy) <= cfg.goal_tolerance { ret (node, ok) }
    }
    ret (NONE, ok)
}

// --- PRM ---------------------------------------------------------------------------------

fn node_distance(p: *const Pool, a: usize, b: usize) -> f64 { ret distance(p.xs[a], p.ys[a], p.xs[b], p.ys[b]) }

// The k nearest of nodes 0..n to node `who` (ties to the lower index), blocked edges as `NONE`.
fn link(obstacles: []const Circle, p: *const Pool, n: usize, k: usize, who: usize, adj: []u32) {
    let base = who * k
    var count = 0usize
    var j = 0usize
    while j < n {
        if j != who {
            let d = node_distance(p, who, j)
            var pos = count
            while pos > 0usize && d < node_distance(p, who, usize(adj[base + pos - 1usize])) { pos -= 1usize }
            if pos < k {
                var m = count
                if m == k { m = k - 1usize }
                while m > pos {
                    adj[base + m] = adj[base + m - 1usize]
                    m -= 1usize
                }
                adj[base + pos] = u32(j)
                if count < k { count += 1usize }
            }
        }
        j += 1usize
    }
    var e = 0usize
    while e < k {
        if e >= count {
            adj[base + e] = NONE
        } else {
            let other = usize(adj[base + e])
            if !collision_free(p.xs[who], p.ys[who], p.xs[other], p.ys[other], obstacles) { adj[base + e] = NONE }
        }
        e += 1usize
    }
}

// #1833 PRM roadmap: `n` free samples linked to their `k` nearest; `adj` holds `k` entries per
// node and needs room for `n + 2` nodes (the query adds the start and the goal), as does `p`.
fn prm_build(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, n: usize, k: usize, adj: []u32) -> err {
    if adj.len < (n + 2usize) * k || k == 0usize { ret TooSmall }
    p.used = 0usize
    var i = 0usize
    while i < n {
        var x = 0.0f64
        var y = 0.0f64
        while true {
            x = cfg.min_x + rand.pcg64_f64(rng) * (cfg.max_x - cfg.min_x)
            y = cfg.min_y + rand.pcg64_f64(rng) * (cfg.max_y - cfg.min_y)
            if point_free(x, y, obstacles) { break }
        }
        let (_, e) = add_node(p, x, y, 0.0f64, NONE, 0.0f64)
        if e != ok { ret e }
        i += 1usize
    }
    i = 0usize
    while i < n {
        link(obstacles, p, n, k, i, adj)
        i += 1usize
    }
    ret ok
}

fn heap_push(h: *Heap, key: f64, node: u32) -> err {
    if h.used >= h.key.len || h.used >= h.node.len { ret TooSmall }
    var i = h.used
    h.used += 1usize
    h.key[i] = key
    h.node[i] = node
    while i > 0usize {
        let q = (i - 1usize) / 2usize
        if h.key[q] <= h.key[i] { break }
        let held_key = h.key[q]
        let held_node = h.node[q]
        h.key[q] = h.key[i]
        h.node[q] = h.node[i]
        h.key[i] = held_key
        h.node[i] = held_node
        i = q
    }
    ret ok
}

fn heap_pop(h: *Heap) -> (f64, u32) {
    let top_key = h.key[0usize]
    let top_node = h.node[0usize]
    h.used -= 1usize
    h.key[0usize] = h.key[h.used]
    h.node[0usize] = h.node[h.used]
    var i = 0usize
    while true {
        let l = 2usize * i + 1usize
        let r = l + 1usize
        var s = i
        if l < h.used && h.key[l] < h.key[s] { s = l }
        if r < h.used && h.key[r] < h.key[s] { s = r }
        if s == i { break }
        let held_key = h.key[s]
        let held_node = h.node[s]
        h.key[s] = h.key[i]
        h.node[s] = h.node[i]
        h.key[i] = held_key
        h.node[i] = held_node
        i = s
    }
    ret (top_key, top_node)
}

fn relax(p: *Pool, h: *Heap, u: usize, v: usize) -> err {
    let c = p.cost[u] + node_distance(p, u, v)
    if c < p.cost[v] {
        p.cost[v] = c
        p.parent[v] = u32(u)
        try heap_push(h, c, u32(v))
    }
    ret ok
}

// PRM query: the start becomes node `n`, the goal node `n + 1`, each linked to its `k`
// nearest samples (plus the direct edge when free); Dijkstra answers the goal node or
// `NONE`. `closed` needs `n + 2` bytes, the heap room for every relaxation.
fn prm_query(obstacles: []const Circle, p: *Pool, n: usize, k: usize, adj: []u32, sx: f64, sy: f64, gx: f64, gy: f64, heap_key: []f64, heap_node: []u32, closed: []u8) -> (u32, err) {
    if closed.len < n + 2usize || adj.len < (n + 2usize) * k { ret (NONE, TooSmall) }
    p.used = n
    let (start, start_error) = add_node(p, sx, sy, 0.0f64, NONE, 0.0f64)
    if start_error != ok { ret (NONE, start_error) }
    let (goal, goal_error) = add_node(p, gx, gy, 0.0f64, NONE, 0.0f64)
    if goal_error != ok { ret (NONE, goal_error) }
    link(obstacles, p, n, k, usize(start), adj)
    link(obstacles, p, n, k, usize(goal), adj)
    let direct = collision_free(sx, sy, gx, gy, obstacles)
    var i = 0usize
    while i < n + 2usize {
        p.cost[i] = 1.0e300f64
        p.parent[i] = NONE
        closed[i] = 0u8
        i += 1usize
    }
    p.cost[usize(start)] = 0.0f64
    var h = Heap { key: heap_key, node: heap_node, used: 0usize }
    let push_error = heap_push(&h, 0.0f64, start)
    if push_error != ok { ret (NONE, push_error) }
    while h.used > 0usize {
        let (_, popped) = heap_pop(&h)
        let u = usize(popped)
        if closed[u] != 0u8 { continue }
        closed[u] = 1u8
        if u == usize(goal) { ret (goal, ok) }
        var e = 0usize
        while e < k {
            let v = adj[u * k + e]
            if v != NONE && closed[usize(v)] == 0u8 {
                let relax_error = relax(p, &h, u, usize(v))
                if relax_error != ok { ret (NONE, relax_error) }
            }
            e += 1usize
        }
        var into_goal = u == usize(start) && direct
        e = 0usize
        while e < k {
            if adj[usize(goal) * k + e] == popped { into_goal = true }
            e += 1usize
        }
        if into_goal {
            let goal_relax = relax(p, &h, u, usize(goal))
            if goal_relax != ok { ret (NONE, goal_relax) }
        }
    }
    ret (NONE, ok)
}

// --- hybrid A* and the state lattice -----------------------------------------------------

// Follow an arc of `length` at `curvature` (0 is straight, 1/r turns left).
fn advance(x: f64, y: f64, th: f64, length: f64, curvature: f64) -> (f64, f64, f64) {
    if curvature == 0.0f64 { ret (x + length * math.cos[f64](th), y + length * math.sin[f64](th), th) }
    let th2 = th + length * curvature
    let r = 1.0f64 / curvature
    ret (x + r * (math.sin[f64](th2) - math.sin[f64](th)), y - r * (math.cos[f64](th2) - math.cos[f64](th)), th2)
}

// One primitive of `grid.arc` in `grid.substeps` pieces, each chord collision-checked.
fn trace(grid: *const Grid, obstacles: []const Circle, x0: f64, y0: f64, th0: f64, curvature: f64) -> (bool, f64, f64, f64) {
    let piece = grid.arc / f64(grid.substeps)
    var x = x0
    var y = y0
    var th = th0
    var s = 0usize
    while s < grid.substeps {
        let (nx, ny, nth) = advance(x, y, th, piece, curvature)
        if !collision_free(x, y, nx, ny, obstacles) { ret (false, nx, ny, nth) }
        x = nx
        y = ny
        th = nth
        s += 1usize
    }
    ret (true, x, y, th)
}

fn wrap_heading(th: f64) -> f64 {
    var t = th
    while t < 0.0f64 { t += two_pi() }
    while t >= two_pi() { t -= two_pi() }
    ret t
}

// The cell of (x, y, th): (iy * w + ix) * headings + ih, and whether it lies on the grid.
fn cell_of(cfg: *const Config, grid: *const Grid, x: f64, y: f64, th: f64) -> (usize, bool) {
    let ix = i64(math.floor[f64]((x - cfg.min_x) / grid.cell))
    let iy = i64(math.floor[f64]((y - cfg.min_y) / grid.cell))
    if ix < 0i64 || iy < 0i64 || ix >= i64(grid.w) || iy >= i64(grid.h) { ret (0usize, false) }
    var ih = usize(i64(math.floor[f64](wrap_heading(th) / (two_pi() / f64(grid.headings)))))
    if ih >= grid.headings { ih = grid.headings - 1usize }
    ret ((usize(iy) * grid.w + usize(ix)) * grid.headings + ih, true)
}

fn curvature_of(grid: *const Grid, which: usize) -> f64 {
    if which == 0usize { ret 0.0f64 }
    if which == 1usize { ret 1.0f64 / grid.radius }
    ret 0.0f64 - 1.0f64 / grid.radius
}

fn search_ready(p: *Pool, grid: *const Grid, closed: []u8, cell_node: []u32) -> err {
    if p.th.len == 0usize || grid.substeps == 0usize || grid.headings == 0usize { ret Invalid }
    if closed.len < p.xs.len || cell_node.len < grid.w * grid.h * grid.headings { ret TooSmall }
    var c = 0usize
    while c < grid.w * grid.h * grid.headings {
        cell_node[c] = NONE
        c += 1usize
    }
    p.used = 0usize
    ret ok
}

// Record a successor state in cell `c` at cost `g`: a new node, or a better one for the cell.
fn offer(p: *Pool, h: *Heap, closed: []u8, cell_node: []u32, c: usize, x: f64, y: f64, th: f64, parent: u32, g: f64, priority: f64) -> err {
    let existing = cell_node[c]
    if existing != NONE {
        let e = usize(existing)
        if closed[e] != 0u8 || g >= p.cost[e] { ret ok }
        p.xs[e] = x
        p.ys[e] = y
        p.th[e] = th
        p.parent[e] = parent
        p.cost[e] = g
        try heap_push(h, priority, existing)
        ret ok
    }
    let (node, node_error) = add_node(p, x, y, th, parent, g)
    if node_error != ok { ret node_error }
    closed[usize(node)] = 0u8
    cell_node[c] = node
    try heap_push(h, priority, node)
    ret ok
}

// #1837 Hybrid A*: continuous (x, y, theta) states binned into `grid` cells, three primitives
// of `grid.arc` (straight, left, right) per expansion, Euclidean heuristic; answers the first
// node within `goal_tolerance` of the goal, whose `cost` is the path length. `closed` is one
// byte per pool node, `cell_node` one `u32` per cell.
fn hybrid_astar(cfg: *const Config, grid: *const Grid, obstacles: []const Circle, p: *Pool, closed: []u8, cell_node: []u32, heap_key: []f64, heap_node: []u32, sx: f64, sy: f64, sth: f64, gx: f64, gy: f64) -> (u32, err) {
    let ready = search_ready(p, grid, closed, cell_node)
    if ready != ok { ret (NONE, ready) }
    let (c0, inside) = cell_of(cfg, grid, sx, sy, sth)
    if !inside { ret (NONE, Invalid) }
    var h = Heap { key: heap_key, node: heap_node, used: 0usize }
    let start_error = offer(p, &h, closed, cell_node, c0, sx, sy, sth, NONE, 0.0f64, distance(sx, sy, gx, gy))
    if start_error != ok { ret (NONE, start_error) }
    while h.used > 0usize {
        let (_, popped) = heap_pop(&h)
        let u = usize(popped)
        if closed[u] != 0u8 { continue }
        closed[u] = 1u8
        if distance(p.xs[u], p.ys[u], gx, gy) <= cfg.goal_tolerance { ret (popped, ok) }
        var which = 0usize
        while which < 3usize {
            let (free, nx, ny, nth) = trace(grid, obstacles, p.xs[u], p.ys[u], p.th[u], curvature_of(grid, which))
            which += 1usize
            if !free { continue }
            let (c, on_grid) = cell_of(cfg, grid, nx, ny, nth)
            if !on_grid { continue }
            let g = p.cost[u] + grid.arc
            let offer_error = offer(p, &h, closed, cell_node, c, nx, ny, nth, popped, g, g + distance(nx, ny, gx, gy))
            if offer_error != ok { ret (NONE, offer_error) }
        }
    }
    ret (NONE, ok)
}

// The lattice primitive table: for heading bin `ih` and primitive `which` (0 straight, 1 left,
// 2 right), `prims[(ih * 3 + which) * 3 ..]` holds the end offset in cells (dx, dy) and the
// heading change (0, +1, -1). Arcs turn exactly one heading bin, so their curvature is
// (2 pi / headings) / arc, and the end point snaps to the nearest cell.
fn lattice_primitives(grid: *const Grid, prims: []i64) -> err {
    if grid.headings == 0usize || grid.cell <= 0.0f64 { ret Invalid }
    if prims.len < grid.headings * 9usize { ret TooSmall }
    let turn = two_pi() / f64(grid.headings)
    var ih = 0usize
    while ih < grid.headings {
        let th = f64(ih) * turn
        var which = 0usize
        while which < 3usize {
            var curvature = 0.0f64
            var dh = 0i64
            if which == 1usize {
                curvature = turn / grid.arc
                dh = 1i64
            }
            if which == 2usize {
                curvature = 0.0f64 - turn / grid.arc
                dh = 0i64 - 1i64
            }
            let (ex, ey, _) = advance(0.0f64, 0.0f64, th, grid.arc, curvature)
            let base = (ih * 3usize + which) * 3usize
            prims[base] = i64(math.floor[f64](ex / grid.cell + 0.5f64))
            prims[base + 1usize] = i64(math.floor[f64](ey / grid.cell + 0.5f64))
            prims[base + 2usize] = dh
            which += 1usize
        }
        ih += 1usize
    }
    ret ok
}

fn lattice_centre(cfg: *const Config, grid: *const Grid, ix: usize, iy: usize) -> (f64, f64) {
    ret (cfg.min_x + (f64(ix) + 0.5f64) * grid.cell, cfg.min_y + (f64(iy) + 0.5f64) * grid.cell)
}

// #1838 State lattice: Dijkstra over cells (ix, iy, ih) joined by the `lattice_primitives`
// table, each move costing `grid.arc` and collision-checked along the chord between the
// cell centres; the start snaps to its cell centre at heading bin `sh`. Answers the first
// cell within `goal_tolerance` of the goal; node `th` holds the bin's angle.
// ponytail: chord collision check; sample the arc when obstacles are thinner than a cell.
fn state_lattice(cfg: *const Config, grid: *const Grid, obstacles: []const Circle, prims: []const i64, p: *Pool, closed: []u8, cell_node: []u32, heap_key: []f64, heap_node: []u32, sx: f64, sy: f64, sh: usize, gx: f64, gy: f64) -> (u32, err) {
    let ready = search_ready(p, grid, closed, cell_node)
    if ready != ok { ret (NONE, ready) }
    if prims.len < grid.headings * 9usize { ret (NONE, TooSmall) }
    let turn = two_pi() / f64(grid.headings)
    let (c0, inside) = cell_of(cfg, grid, sx, sy, f64(sh) * turn)
    if !inside || sh >= grid.headings { ret (NONE, Invalid) }
    let (x0, y0) = lattice_centre(cfg, grid, (c0 / grid.headings) % grid.w, c0 / grid.headings / grid.w)
    var h = Heap { key: heap_key, node: heap_node, used: 0usize }
    let start_error = offer(p, &h, closed, cell_node, c0, x0, y0, f64(sh) * turn, NONE, 0.0f64, 0.0f64)
    if start_error != ok { ret (NONE, start_error) }
    while h.used > 0usize {
        let (_, popped) = heap_pop(&h)
        let u = usize(popped)
        if closed[u] != 0u8 { continue }
        closed[u] = 1u8
        if distance(p.xs[u], p.ys[u], gx, gy) <= cfg.goal_tolerance { ret (popped, ok) }
        let cell = usize(cell_node_of(cfg, grid, p, u))
        let ih = cell % grid.headings
        let ix = (cell / grid.headings) % grid.w
        let iy = cell / grid.headings / grid.w
        var which = 0usize
        while which < 3usize {
            let base = (ih * 3usize + which) * 3usize
            which += 1usize
            let nx = i64(ix) + prims[base]
            let ny = i64(iy) + prims[base + 1usize]
            if nx < 0i64 || ny < 0i64 || nx >= i64(grid.w) || ny >= i64(grid.h) { continue }
            let nh = (i64(ih) + prims[base + 2usize] + i64(grid.headings)) % i64(grid.headings)
            let (cx, cy) = lattice_centre(cfg, grid, usize(nx), usize(ny))
            if !collision_free(p.xs[u], p.ys[u], cx, cy, obstacles) { continue }
            let c = (usize(ny) * grid.w + usize(nx)) * grid.headings + usize(nh)
            let g = p.cost[u] + grid.arc
            let offer_error = offer(p, &h, closed, cell_node, c, cx, cy, f64(nh) * turn, popped, g, g)
            if offer_error != ok { ret (NONE, offer_error) }
        }
    }
    ret (NONE, ok)
}

fn cell_node_of(cfg: *const Config, grid: *const Grid, p: *const Pool, u: usize) -> u32 {
    let (c, _) = cell_of(cfg, grid, p.xs[u], p.ys[u], p.th[u])
    ret u32(c)
}

// --- paths -------------------------------------------------------------------------------

fn path_length(xs: []const f64, ys: []const f64, n: usize) -> f64 {
    var length = 0.0f64
    var i = 1usize
    while i < n {
        length += distance(xs[i - 1usize], ys[i - 1usize], xs[i], ys[i])
        i += 1usize
    }
    ret length
}

// The nodes from the root to `node`, root first; answers (count, chord length).
fn path_extract(p: *const Pool, node: u32, out_x: []f64, out_y: []f64) -> (usize, f64, err) {
    var n = 0usize
    var cur = node
    while cur != NONE {
        n += 1usize
        cur = p.parent[usize(cur)]
    }
    if out_x.len < n || out_y.len < n { ret (n, 0.0f64, TooSmall) }
    var i = n
    cur = node
    while cur != NONE {
        i -= 1usize
        out_x[i] = p.xs[usize(cur)]
        out_y[i] = p.ys[usize(cur)]
        cur = p.parent[usize(cur)]
    }
    ret (n, path_length(out_x, out_y, n), ok)
}

// The RRT-Connect path: `a`'s root to `a_node`, then `b_node`'s ancestors up to `b`'s root
// (`b_node` itself sits on `a_node`, so it is skipped).
fn path_join(a: *const Pool, a_node: u32, b: *const Pool, b_node: u32, out_x: []f64, out_y: []f64) -> (usize, f64, err) {
    if a_node == NONE || b_node == NONE { ret (0usize, 0.0f64, Invalid) }
    let (na, _, a_error) = path_extract(a, a_node, out_x, out_y)
    if a_error != ok { ret (na, 0.0f64, a_error) }
    var i = na
    var cur = b.parent[usize(b_node)]
    while cur != NONE {
        if i >= out_x.len || i >= out_y.len { ret (i, 0.0f64, TooSmall) }
        out_x[i] = b.xs[usize(cur)]
        out_y[i] = b.ys[usize(cur)]
        i += 1usize
        cur = b.parent[usize(cur)]
    }
    ret (i, path_length(out_x, out_y, i), ok)
}


// --- #1833 PRM in one call: build the roadmap, then query it.
fn prm(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, n: usize, k: usize, adj: []u32, sx: f64, sy: f64, gx: f64, gy: f64, heap_key: []f64, heap_node: []u32, closed: []u8) -> (u32, err) {
    let build_error = prm_build(cfg, obstacles, rng, p, n, k, adj)
    if build_error != ok { ret (NONE, build_error) }
    let (goal, query_error) = prm_query(obstacles, p, n, k, adj, sx, sy, gx, gy, heap_key, heap_node, closed)
    ret (goal, query_error)
}

// --- Incremental search on a `w` x `h` grid (#92, #93, #1840): four unit
// moves between unblocked cells (`blocked[cell] != 0` is a wall), the
// `g`/`rhs` machinery of LPA* (Koenig & Likhachev 2004) with a lazy binary
// heap of `(k1, k2)` keys. `root` is the node whose `rhs` is 0 and `focus`
// the one the keys point at with the Manhattan heuristic: LPA* roots the
// start and focuses the goal, D* Lite roots the goal and focuses the robot,
// whose `km` grows as it moves so old keys stay lower bounds. A path is read
// from `focus` toward `root` by the neighbour of least `g + 1`.

type Incremental = struct { w: usize, h: usize, blocked: []u8, g: []f64, rhs: []f64, heap_k1: []f64, heap_k2: []f64, heap_node: []u32, heap_used: usize, root: usize, focus: usize, km: f64, expansions: usize }

fn infinite() -> f64 { ret 1.0e300f64 }

fn manhattan(w: usize, a: usize, b: usize) -> f64 {
    let ax = i64(a % w)
    let ay = i64(a / w)
    let bx = i64(b % w)
    let by = i64(b / w)
    var dx = ax - bx
    if dx < 0i64 { dx = 0i64 - dx }
    var dy = ay - by
    if dy < 0i64 { dy = 0i64 - dy }
    ret f64(dx + dy)
}

fn key_less(a1: f64, a2: f64, b1: f64, b2: f64) -> bool {
    if a1 < b1 { ret true }
    if a1 > b1 { ret false }
    ret a2 < b2
}

fn key_of(s: *const Incremental, u: usize) -> (f64, f64) {
    var m = s.g[u]
    if s.rhs[u] < m { m = s.rhs[u] }
    if m >= infinite() { ret (infinite(), infinite()) }
    ret (m + manhattan(s.w, u, s.focus) + s.km, m)
}

fn ikey_push(s: *Incremental, k1: f64, k2: f64, node: u32) -> err {
    if s.heap_used >= s.heap_k1.len || s.heap_used >= s.heap_k2.len || s.heap_used >= s.heap_node.len { ret TooSmall }
    var i = s.heap_used
    s.heap_used += 1usize
    s.heap_k1[i] = k1
    s.heap_k2[i] = k2
    s.heap_node[i] = node
    while i > 0usize {
        let q = (i - 1usize) / 2usize
        if !key_less(s.heap_k1[i], s.heap_k2[i], s.heap_k1[q], s.heap_k2[q]) { ret ok }
        let hk1 = s.heap_k1[q]
        let hk2 = s.heap_k2[q]
        let hn = s.heap_node[q]
        s.heap_k1[q] = s.heap_k1[i]
        s.heap_k2[q] = s.heap_k2[i]
        s.heap_node[q] = s.heap_node[i]
        s.heap_k1[i] = hk1
        s.heap_k2[i] = hk2
        s.heap_node[i] = hn
        i = q
    }
    ret ok
}

fn ikey_pop(s: *Incremental) -> (f64, f64, u32) {
    let top1 = s.heap_k1[0usize]
    let top2 = s.heap_k2[0usize]
    let top_node = s.heap_node[0usize]
    s.heap_used -= 1usize
    s.heap_k1[0usize] = s.heap_k1[s.heap_used]
    s.heap_k2[0usize] = s.heap_k2[s.heap_used]
    s.heap_node[0usize] = s.heap_node[s.heap_used]
    var i = 0usize
    while true {
        let l = 2usize * i + 1usize
        let r = l + 1usize
        var m = i
        if l < s.heap_used && key_less(s.heap_k1[l], s.heap_k2[l], s.heap_k1[m], s.heap_k2[m]) { m = l }
        if r < s.heap_used && key_less(s.heap_k1[r], s.heap_k2[r], s.heap_k1[m], s.heap_k2[m]) { m = r }
        if m == i { ret (top1, top2, top_node) }
        let hk1 = s.heap_k1[m]
        let hk2 = s.heap_k2[m]
        let hn = s.heap_node[m]
        s.heap_k1[m] = s.heap_k1[i]
        s.heap_k2[m] = s.heap_k2[i]
        s.heap_node[m] = s.heap_node[i]
        s.heap_k1[i] = hk1
        s.heap_k2[i] = hk2
        s.heap_node[i] = hn
        i = m
    }
    ret (top1, top2, top_node)
}

// The four grid neighbours of `u` in the order right, down, left, up.
fn grid_neighbour(w: usize, h: usize, u: usize, k: usize) -> (usize, bool) {
    let x = u % w
    let y = u / w
    if k == 0usize {
        if x + 1usize < w { ret (u + 1usize, true) }
        ret (0usize, false)
    }
    if k == 1usize {
        if y + 1usize < h { ret (u + w, true) }
        ret (0usize, false)
    }
    if k == 2usize {
        if x > 0usize { ret (u - 1usize, true) }
        ret (0usize, false)
    }
    if y > 0usize { ret (u - w, true) }
    ret (0usize, false)
}

fn update_vertex(s: *Incremental, u: usize) -> err {
    if u != s.root {
        var best = infinite()
        if s.blocked[u] == 0u8 {
            var k = 0usize
            while k < 4usize {
                let (v, has) = grid_neighbour(s.w, s.h, u, k)
                if has && s.blocked[v] == 0u8 && s.g[v] + 1.0f64 < best { best = s.g[v] + 1.0f64 }
                k += 1usize
            }
        }
        s.rhs[u] = best
    }
    if s.g[u] != s.rhs[u] {
        let (k1, k2) = key_of(s, u)
        ret ikey_push(s, k1, k2, u32(u))
    }
    ret ok
}

fn incremental(w: usize, h: usize, blocked: []u8, g: []f64, rhs: []f64, heap_k1: []f64, heap_k2: []f64, heap_node: []u32, root: usize, focus: usize) -> (Incremental, err) {
    let total = w * h
    if blocked.len < total || g.len < total || rhs.len < total || root >= total || focus >= total { ret (zero, TooSmall) }
    var s = Incremental { w: w, h: h, blocked: blocked, g: g, rhs: rhs, heap_k1: heap_k1, heap_k2: heap_k2, heap_node: heap_node, heap_used: 0usize, root: root, focus: focus, km: 0.0f64, expansions: 0usize }
    var i = 0usize
    while i < total {
        g[i] = infinite()
        rhs[i] = infinite()
        i += 1usize
    }
    rhs[root] = 0.0f64
    let (k1, k2) = key_of(&s, root)
    let push_error = ikey_push(&s, k1, k2, u32(root))
    if push_error != ok { ret (zero, push_error) }
    ret (s, ok)
}

// #93 LPA*: rooted at `start`, keys toward `goal`; `incremental_compute`
// answers the shortest path, `incremental_block` changes a cell, and the
// next `incremental_compute` repairs only what the change touched.
fn lpa_star(w: usize, h: usize, blocked: []u8, g: []f64, rhs: []f64, heap_k1: []f64, heap_k2: []f64, heap_node: []u32, start: usize, goal: usize) -> (Incremental, err) {
    let (s, e) = incremental(w, h, blocked, g, rhs, heap_k1, heap_k2, heap_node, start, goal)
    ret (s, e)
}

// #92 / #1840 D* Lite: rooted at `goal`, keys toward the robot at `start`;
// `incremental_move` follows the robot, `incremental_block` reports what
// its sensors found, `incremental_compute` replans.
fn dstar_lite(w: usize, h: usize, blocked: []u8, g: []f64, rhs: []f64, heap_k1: []f64, heap_k2: []f64, heap_node: []u32, start: usize, goal: usize) -> (Incremental, err) {
    let (s, e) = incremental(w, h, blocked, g, rhs, heap_k1, heap_k2, heap_node, goal, start)
    ret (s, e)
}

// ComputeShortestPath: expand until the focus is consistent and nothing in
// the queue keys below it. Answers `g[focus]` (`infinite()` when cut off).
fn incremental_compute(s: *Incremental) -> (f64, err) {
    while s.heap_used > 0usize {
        let (f1, f2) = key_of(s, s.focus)
        let top1 = s.heap_k1[0usize]
        let top2 = s.heap_k2[0usize]
        if !key_less(top1, top2, f1, f2) && s.rhs[s.focus] == s.g[s.focus] { ret (s.g[s.focus], ok) }
        let (k1, k2, popped) = ikey_pop(s)
        let u = usize(popped)
        if s.g[u] == s.rhs[u] { continue }
        let (n1, n2) = key_of(s, u)
        if key_less(k1, k2, n1, n2) {
            let repush = ikey_push(s, n1, n2, popped)
            if repush != ok { ret (infinite(), repush) }
            continue
        }
        s.expansions += 1usize
        if s.g[u] > s.rhs[u] {
            s.g[u] = s.rhs[u]
        } else {
            s.g[u] = infinite()
            let self_error = update_vertex(s, u)
            if self_error != ok { ret (infinite(), self_error) }
        }
        var k = 0usize
        while k < 4usize {
            let (v, has) = grid_neighbour(s.w, s.h, u, k)
            if has {
                let update_error = update_vertex(s, v)
                if update_error != ok { ret (infinite(), update_error) }
            }
            k += 1usize
        }
    }
    ret (s.g[s.focus], ok)
}

// A cell becomes a wall or open ground: its own and its neighbours' `rhs`
// are recomputed and queued.
fn incremental_block(s: *Incremental, cell: usize, wall: bool) -> err {
    if cell >= s.w * s.h { ret Invalid }
    if wall { s.blocked[cell] = 1u8 } else { s.blocked[cell] = 0u8 }
    try update_vertex(s, cell)
    var k = 0usize
    while k < 4usize {
        let (v, has) = grid_neighbour(s.w, s.h, cell, k)
        if has { try update_vertex(s, v) }
        k += 1usize
    }
    ret ok
}

// D* Lite: the robot now stands on `cell`; `km` grows by the heuristic
// distance moved so every queued key stays a lower bound.
fn incremental_move(s: *Incremental, cell: usize) -> err {
    if cell >= s.w * s.h { ret Invalid }
    s.km += manhattan(s.w, s.focus, cell)
    s.focus = cell
    ret ok
}

// The path from `focus` to `root` by descending `g` (`focus` first), into
// `out`; 0 cells when `focus` is cut off. `out.len` bounds the walk.
fn incremental_path(s: *const Incremental, out: []u32) -> (usize, err) {
    if s.g[s.focus] >= infinite() || s.blocked[s.focus] != 0u8 { ret (0usize, ok) }
    var n = 0usize
    var cur = s.focus
    while true {
        if n >= out.len { ret (n, TooSmall) }
        out[n] = u32(cur)
        n += 1usize
        if cur == s.root { ret (n, ok) }
        var best = cur
        var best_g = infinite()
        var k = 0usize
        while k < 4usize {
            let (v, has) = grid_neighbour(s.w, s.h, cur, k)
            if has && s.blocked[v] == 0u8 && s.g[v] < best_g {
                best_g = s.g[v]
                best = v
            }
            k += 1usize
        }
        if best == cur || best_g >= s.g[cur] { ret (0usize, Invalid) }
        cur = best
    }
    ret (n, ok)
}
