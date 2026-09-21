// `e.robot.plan`: RRT, RRT*, informed RRT*, RRT-Connect, kinodynamic RRT and
// PRM on two maps match scratchpad/plan_ref.py (same PCG stream: tree sizes,
// found nodes, path costs and the first ten waypoints folded into one
// signature), hybrid A* and the state lattice match their path lengths
// exactly, and the storage errors come back. Each check exits with its own
// code.

use e.algo.rand
use e.math
use e.robot.plan as plan
use e.io
use e.mem
use e.os

fn quantized(x: f64) -> u64 { ret u64(i64(math.floor[f64](x * 1000000.0f64 + 0.5f64)) + 1000000000i64) }

fn hash_path(xs: []const f64, ys: []const f64, n: usize) -> u64 {
    var h = 0u64
    var i = 0usize
    while i < n && i < 10usize {
        h = h *% 31u64 +% quantized(xs[i])
        h = h *% 31u64 +% quantized(ys[i])
        i += 1usize
    }
    ret h
}

fn sig(used: usize, node: u32, count: usize, cost: f64, h: u64) -> u64 {
    var s = u64(used) *% 31u64 +% u64(node)
    s = s *% 31u64 +% u64(count)
    s = s *% 31u64 +% quantized(cost)
    ret s *% 31u64 +% h
}

fn circle(x: f64, y: f64, r: f64) -> plan.Circle { ret plan.Circle { x: x, y: y, r: r } }

fn config(max_x: f64, max_y: f64) -> plan.Config {
    ret plan.Config { min_x: 0.0f64, min_y: 0.0f64, max_x: max_x, max_y: max_y, step: 0.5f64, radius: 1.5f64, goal_bias: 0.05f64, goal_tolerance: 0.5f64, iterations: 600usize }
}

// The six sampling planners on one map; answers 0 or the failing check's offset (1..6).
fn map_checks(mi: usize, cfg: *const plan.Config, obs: []const plan.Circle, p: *plan.Pool, b: *plan.Pool, sx: f64, sy: f64, gx: f64, gy: f64, ox: []f64, oy: []f64, adj: []u32, heap_key: []f64, heap_node: []u32, closed: []u8, want: []const u64) -> i32 {
    let stream = u64(mi) + 1u64
    var r = rand.pcg64(11u64, stream)
    let (rrt_node, rrt_error) = plan.rrt(cfg, obs, &r, p, sx, sy, gx, gy)
    if rrt_error != ok || rrt_node == plan.NONE { ret 1i32 }
    let (rrt_count, rrt_length, _) = plan.path_extract(p, rrt_node, ox, oy)
    if sig(p.used, rrt_node, rrt_count, rrt_length, hash_path(ox, oy, rrt_count)) != want[0usize] { ret 1i32 }

    r = rand.pcg64(12u64, stream)
    let (star_node, star_error) = plan.rrt_star(cfg, obs, &r, p, sx, sy, gx, gy)
    if star_error != ok || star_node == plan.NONE { ret 2i32 }
    let (star_count, star_length, _) = plan.path_extract(p, star_node, ox, oy)
    if sig(p.used, star_node, star_count, star_length, hash_path(ox, oy, star_count)) != want[1usize] { ret 2i32 }

    r = rand.pcg64(13u64, stream)
    let (inf_node, inf_error) = plan.rrt_informed(cfg, obs, &r, p, sx, sy, gx, gy)
    if inf_error != ok || inf_node == plan.NONE { ret 3i32 }
    let (inf_count, inf_length, _) = plan.path_extract(p, inf_node, ox, oy)
    if sig(p.used, inf_node, inf_count, inf_length, hash_path(ox, oy, inf_count)) != want[2usize] { ret 3i32 }

    r = rand.pcg64(14u64, stream)
    let (na, nb, connect_error) = plan.rrt_connect(cfg, obs, &r, p, b, sx, sy, gx, gy)
    if connect_error != ok || na == plan.NONE { ret 4i32 }
    let (join_count, join_length, join_error) = plan.path_join(p, na, b, nb, ox, oy)
    if join_error != ok { ret 4i32 }
    if sig(p.used + 1000usize * b.used, na + 1000u32 * nb, join_count, join_length, hash_path(ox, oy, join_count)) != want[3usize] { ret 4i32 }

    r = rand.pcg64(15u64, stream)
    var kcfg = *cfg
    kcfg.goal_tolerance = 1.0f64
    kcfg.iterations = 800usize
    let kino = plan.Kino { v_min: 0.2f64, v_max: 1.0f64, omega_max: 1.5f64, dt: 1.0f64, substeps: 4usize, controls: 6usize }
    let (kino_node, kino_error) = plan.rrt_kinodynamic(&kcfg, &kino, obs, &r, p, sx, sy, 0.0f64, gx, gy)
    if kino_error != ok || kino_node == plan.NONE { ret 5i32 }
    let (kino_count, _, _) = plan.path_extract(p, kino_node, ox, oy)
    if sig(p.used, kino_node, kino_count, p.cost[usize(kino_node)], hash_path(ox, oy, kino_count)) != want[4usize] { ret 5i32 }

    r = rand.pcg64(16u64, stream)
    if plan.prm_build(cfg, obs, &r, p, 120usize, 6usize, adj) != ok { ret 6i32 }
    var free_edges = 0usize
    var e = 0usize
    while e < 720usize {
        if adj[e] != plan.NONE { free_edges += 1usize }
        e += 1usize
    }
    let (goal, prm_error) = plan.prm_query(obs, p, 120usize, 6usize, adj, sx, sy, gx, gy, heap_key, heap_node, closed)
    if prm_error != ok || goal != 121u32 { ret 6i32 }
    let (prm_count, _, _) = plan.path_extract(p, goal, ox, oy)
    if sig(free_edges, goal, prm_count, p.cost[usize(goal)], hash_path(ox, oy, prm_count)) != want[5usize] { ret 6i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var xs: [1024]f64 = zero
    var ys: [1024]f64 = zero
    var th: [1024]f64 = zero
    var parent: [1024]u32 = zero
    var cost: [1024]f64 = zero
    var bxs: [256]f64 = zero
    var bys: [256]f64 = zero
    var bparent: [256]u32 = zero
    var bcost: [256]f64 = zero
    var ox: [128]f64 = zero
    var oy: [128]f64 = zero
    var adj: [732]u32 = zero
    var heap_key: [4096]f64 = zero
    var heap_node: [4096]u32 = zero
    var closed: [1024]u8 = zero
    var cell_node: [6400]u32 = zero
    var p = plan.pool_th(xs[..], ys[..], th[..], parent[..], cost[..])
    var b = plan.pool(bxs[..], bys[..], bparent[..], bcost[..])

    // 1-6: map 0, a square with four round obstacles.
    var obs0: [4]plan.Circle = zero
    obs0[0usize] = circle(3.0f64, 3.0f64, 1.2f64)
    obs0[1usize] = circle(6.0f64, 6.5f64, 1.5f64)
    obs0[2usize] = circle(7.5f64, 2.5f64, 1.0f64)
    obs0[3usize] = circle(2.5f64, 7.5f64, 1.0f64)
    let cfg0 = config(10.0f64, 10.0f64)
    var want0: [6]u64 = zero
    want0[0usize] = 8203780714608507993u64
    want0[1usize] = 14703156449591510357u64
    want0[2usize] = 15717861397283005729u64
    want0[3usize] = 9560560986039005156u64
    want0[4usize] = 2856621670879354026u64
    want0[5usize] = 13863913387895266264u64
    let code0 = map_checks(0usize, &cfg0, obs0[..], &p, &b, 1.0f64, 1.0f64, 9.0f64, 9.0f64, ox[..], oy[..], adj[..], heap_key[..], heap_node[..], closed[..], want0[..])
    if code0 != 0i32 { os.exit(code0) }

    // 7-12: map 1, a wall with a gap and two more obstacles.
    var obs1: [6]plan.Circle = zero
    obs1[0usize] = circle(10.0f64, 1.0f64, 1.1f64)
    obs1[1usize] = circle(10.0f64, 3.0f64, 1.1f64)
    obs1[2usize] = circle(10.0f64, 5.0f64, 1.1f64)
    obs1[3usize] = circle(10.0f64, 9.0f64, 1.1f64)
    obs1[4usize] = circle(5.0f64, 8.0f64, 1.0f64)
    obs1[5usize] = circle(15.0f64, 2.0f64, 1.0f64)
    let cfg1 = config(20.0f64, 10.0f64)
    var want1: [6]u64 = zero
    want1[0usize] = 7610227544535967416u64
    want1[1usize] = 15463159572548659341u64
    want1[2usize] = 2837082539057196575u64
    want1[3usize] = 515942651855530069u64
    want1[4usize] = 10990028379380037797u64
    want1[5usize] = 10302297329380454057u64
    let code1 = map_checks(1usize, &cfg1, obs1[..], &p, &b, 1.0f64, 5.0f64, 19.0f64, 5.0f64, ox[..], oy[..], adj[..], heap_key[..], heap_node[..], closed[..], want1[..])
    if code1 != 0i32 { os.exit(code1 + 6i32) }

    // 13: hybrid A* on map 0: the path length is a whole number of arcs.
    let grid = plan.Grid { cell: 0.5f64, w: 20usize, h: 20usize, headings: 16usize, arc: 0.6f64, radius: 1.5f64, substeps: 3usize }
    let (hybrid_node, hybrid_error) = plan.hybrid_astar(&cfg0, &grid, obs0[..], &p, closed[..], cell_node[..], heap_key[..], heap_node[..], 1.0f64, 1.0f64, 0.0f64, 9.0f64, 9.0f64)
    if hybrid_error != ok || hybrid_node == plan.NONE { os.exit(13i32) }
    if p.cost[usize(hybrid_node)] != 11.999999999999996f64 { os.exit(13i32) }
    let (hybrid_count, hybrid_length, _) = plan.path_extract(&p, hybrid_node, ox[..], oy[..])
    if sig(p.used, hybrid_node, hybrid_count, hybrid_length, hash_path(ox[..], oy[..], hybrid_count)) != 15291648306737033936u64 { os.exit(13i32) }

    // 14: the state lattice: the primitive table, then Dijkstra over it.
    let lgrid = plan.Grid { cell: 0.5f64, w: 20usize, h: 20usize, headings: 8usize, arc: 1.0f64, radius: 0.0f64, substeps: 1usize }
    var prims: [72]i64 = zero
    if plan.lattice_primitives(&lgrid, prims[..]) != ok { os.exit(14i32) }
    var ph = 0u64
    var i = 0usize
    while i < 72usize {
        ph = ph *% 31u64 +% u64(prims[i] + 1000i64)
        i += 1usize
    }
    if ph != 12809468254036299008u64 { os.exit(14i32) }
    let (lattice_node, lattice_error) = plan.state_lattice(&cfg0, &lgrid, obs0[..], prims[..], &p, closed[..], cell_node[..], heap_key[..], heap_node[..], 1.0f64, 1.0f64, 2usize, 9.0f64, 9.0f64)
    if lattice_error != ok || lattice_node == plan.NONE { os.exit(14i32) }
    if p.cost[usize(lattice_node)] != 11.0f64 { os.exit(14i32) }
    let (lattice_count, lattice_length, _) = plan.path_extract(&p, lattice_node, ox[..], oy[..])
    if sig(p.used, lattice_node, lattice_count, lattice_length, hash_path(ox[..], oy[..], lattice_count)) != 8965121158113927994u64 { os.exit(14i32) }

    // 15: a full pool, a heading-less pool for the kinodynamic planner, a short path buffer.
    var small = plan.pool(xs[..2usize], ys[..2usize], parent[..2usize], cost[..2usize])
    var r = rand.pcg64(1u64, 1u64)
    let (_, full_error) = plan.rrt(&cfg0, obs0[..], &r, &small, 1.0f64, 1.0f64, 9.0f64, 9.0f64)
    if full_error != plan.TooSmall { os.exit(15i32) }
    let kino = plan.Kino { v_min: 0.2f64, v_max: 1.0f64, omega_max: 1.5f64, dt: 1.0f64, substeps: 4usize, controls: 6usize }
    let (_, flat_error) = plan.rrt_kinodynamic(&cfg0, &kino, obs0[..], &r, &b, 1.0f64, 1.0f64, 0.0f64, 9.0f64, 9.0f64)
    if flat_error != plan.Invalid { os.exit(15i32) }
    let (_, _, short_error) = plan.path_extract(&p, lattice_node, ox[..3usize], oy[..3usize])
    if short_error != plan.TooSmall { os.exit(15i32) }
    if plan.collision_free(0.0f64, 3.0f64, 6.0f64, 3.0f64, obs0[..]) { os.exit(15i32) }
    if !plan.collision_free(0.0f64, 0.0f64, 10.0f64, 0.0f64, obs0[..]) { os.exit(15i32) }

    try io.print("robot plan ok\n")
    ret ok
}
