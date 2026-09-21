// `e.algo.combopt`: on eight random cities the nearest-neighbour tour is
// improved by 2-opt and Or-opt and Held-Karp reaches the brute-force
// optimum (223.342); greedy set cover, first-fit-decreasing bin packing,
// Clarke-Wright routing, knapsack branch and bound, the generic branch and
// bound on a tiny assignment, and large neighbourhood search on a toy all
// answer as expected. Each check exits with its own code.

use e.algo.combopt as combopt
use e.algo.rand
use e.io
use e.math
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

// A tiny assignment problem for the generic branch and bound: 3 workers to 3 jobs.
type Assign = struct { cost: [9]f64, chosen: [3]usize, used: [3]bool, best: [3]usize }

fn leaf_depth(s: *Assign) -> usize { ret 3usize }
fn choices(s: *Assign, depth: usize) -> usize { ret 3usize }
fn bound(s: *Assign, depth: usize) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < depth {
        if s.chosen[i] >= 3usize { ret 1.0e300f64 }
        total += s.cost[i * 3usize + s.chosen[i]]
        i += 1usize
    }
    // Remaining workers each pay at least their cheapest free job.
    i = depth
    while i < 3usize {
        var least = 1.0e300f64
        var j = 0usize
        while j < 3usize {
            if !s.used[j] && s.cost[i * 3usize + j] < least { least = s.cost[i * 3usize + j] }
            j += 1usize
        }
        total += least
        i += 1usize
    }
    ret total
}
fn branch(s: *Assign, depth: usize, i: usize) {
    s.chosen[depth] = i
    if s.used[i] { s.chosen[depth] = 3usize } else { s.used[i] = true }
}
fn undo(s: *Assign, depth: usize, i: usize) {
    if s.chosen[depth] == i { s.used[i] = false }
}
fn record(s: *Assign) {
    var i = 0usize
    while i < 3usize {
        s.best[i] = s.chosen[i]
        i += 1usize
    }
}

// The LNS toy: a vector whose cost is the sum of squares; destroy zeroes a
// random entry and repair sets it to its neighbour mean plus noise.
type Toy = struct { values: [8]f64, backup: [8]f64, at: usize }

fn destroy(t: *Toy, r: *rand.Pcg64) {
    var i = 0usize
    while i < 8usize {
        t.backup[i] = t.values[i]
        i += 1usize
    }
    t.at = usize(rand.pcg64_bounded(r, 8u64))
}
fn repair(t: *Toy, r: *rand.Pcg64) -> f64 {
    t.values[t.at] = t.values[t.at] * (rand.pcg64_f64(r) - 0.2f64)
    var total = 0.0f64
    var i = 0usize
    while i < 8usize {
        total += t.values[i] * t.values[i]
        i += 1usize
    }
    ret total
}
fn accept(t: *Toy) { t.at = 0usize }
fn restore(t: *Toy) {
    var i = 0usize
    while i < 8usize {
        t.values[i] = t.backup[i]
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: tours on eight cities.
    let coordinates = "57 71 99 59 57 65 75 24 23 65 60 80 78 23 12 57"
    var xs: [8]f64 = zero
    var ys: [8]f64 = zero
    var at = 0usize
    var k = 0usize
    while at < coordinates.len {
        var value = 0.0f64
        while at < coordinates.len && coordinates[at] != 32u8 {
            value = value * 10.0f64 + f64(coordinates[at] - 48u8)
            at += 1usize
        }
        at += 1usize
        if k % 2usize == 0usize { xs[k / 2usize] = value } else { ys[k / 2usize] = value }
        k += 1usize
    }
    var d: [64]f64 = zero
    var i = 0usize
    while i < 8usize {
        var j = 0usize
        while j < 8usize {
            let dx = xs[i] - xs[j]
            let dy = ys[i] - ys[j]
            d[i * 8usize + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
    var tour: [8]usize = zero
    var visited: [8]u8 = zero
    var scratch: [8]usize = zero
    let (nn, nn_error) = combopt.tsp_nearest_neighbor(d[..], 8usize, 0usize, tour[..], visited[..])
    if nn_error != ok || nn < 223.342f64 { os.exit(1i32) }
    let (two, two_moves, two_error) = combopt.tsp_two_opt(d[..], 8usize, tour[..])
    if two_error != ok || two > nn + 0.000001f64 { os.exit(1i32) }
    let (three, _, or_error) = combopt.tsp_or_opt(d[..], 8usize, tour[..], scratch[..])
    if or_error != ok || three > two + 0.000001f64 || three < 223.342f64 - 0.001f64 { os.exit(1i32) }
    // The tour is a permutation.
    i = 0usize
    while i < 8usize {
        visited[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        visited[tour[i]] += 1u8
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        if visited[i] != 1u8 { os.exit(1i32) }
        i += 1usize
    }
    let (table, table_error) = mem.alloc[f64](a, 256usize * 8usize)
    if table_error != ok { ret table_error }
    let (parent, parent_error) = mem.alloc[usize](a, 256usize * 8usize)
    if parent_error != ok { ret parent_error }
    let (optimum, hk_error) = combopt.tsp_held_karp(d[..], 8usize, tour[..], table, parent)
    if hk_error != ok || !near(optimum, 223.34199984523676f64, 0.000001f64) || tour[0usize] != 0usize { os.exit(1i32) }
    if !near(combopt.tour_length(d[..], 8usize, tour[..]), optimum, 0.000001f64) { os.exit(1i32) }
    let (_, hk_invalid) = combopt.tsp_held_karp(d[..], 17usize, tour[..], table, parent)
    if hk_invalid != combopt.Invalid { os.exit(1i32) }
    let (_, nn_invalid) = combopt.tsp_nearest_neighbor(d[..], 8usize, 9usize, tour[..], visited[..])
    if nn_invalid != combopt.Invalid { os.exit(1i32) }

    // 2: set cover, bin packing, routing.
    var membership: [24]u8 = zero
    // Sets over 6 elements: {0,1,2}, {3,4,5}, {0,3}, {1,4,5}.
    membership[0usize] = 1u8
    membership[1usize] = 1u8
    membership[2usize] = 1u8
    membership[9usize] = 1u8
    membership[10usize] = 1u8
    membership[11usize] = 1u8
    membership[12usize] = 1u8
    membership[15usize] = 1u8
    membership[19usize] = 1u8
    membership[22usize] = 1u8
    membership[23usize] = 1u8
    var chosen: [4]usize = zero
    var covered: [6]u8 = zero
    let (sets, cover_error) = combopt.set_cover_greedy(membership[..], 4usize, 6usize, chosen[..], covered[..])
    if cover_error != ok || sets != 2usize || chosen[0usize] != 0usize || chosen[1usize] != 1usize { os.exit(2i32) }
    var sizes: [9]f64 = zero
    sizes[0usize] = 0.5f64
    sizes[1usize] = 0.7f64
    sizes[2usize] = 0.5f64
    sizes[3usize] = 0.2f64
    sizes[4usize] = 0.4f64
    sizes[5usize] = 0.2f64
    sizes[6usize] = 0.5f64
    sizes[7usize] = 0.1f64
    sizes[8usize] = 0.6f64
    var bins: [9]usize = zero
    var loads: [9]f64 = zero
    var order: [9]usize = zero
    let (bin_count, pack_error) = combopt.bin_pack_ffd(sizes[..], 1.0f64, bins[..], loads[..], order[..])
    if pack_error != ok || bin_count != 4usize || bins[1usize] != 0usize || !near(loads[0usize], 1.0f64, 0.000001f64) { os.exit(2i32) }
    sizes[0usize] = 1.5f64
    let (_, pack_invalid) = combopt.bin_pack_ffd(sizes[..], 1.0f64, bins[..], loads[..], order[..])
    if pack_invalid != combopt.Invalid { os.exit(2i32) }
    // Routing: depot 0 and four customers on a line at 1, 2, 10, 11 with demands 1; capacity 2.
    var line: [5]f64 = zero
    line[1usize] = 1.0f64
    line[2usize] = 2.0f64
    line[3usize] = 10.0f64
    line[4usize] = 11.0f64
    var dist: [25]f64 = zero
    i = 0usize
    while i < 5usize {
        var j = 0usize
        while j < 5usize {
            var t = line[i] - line[j]
            if t < 0.0f64 { t = 0.0f64 - t }
            dist[i * 5usize + j] = t
            j += 1usize
        }
        i += 1usize
    }
    var demand: [5]f64 = zero
    demand[1usize] = 1.0f64
    demand[2usize] = 1.0f64
    demand[3usize] = 1.0f64
    demand[4usize] = 1.0f64
    var route: [5]usize = zero
    var next: [5]usize = zero
    var previous: [5]usize = zero
    var load: [5]f64 = zero
    var savings: [25]f64 = zero
    var pairs: [25]usize = zero
    let (routes, vrp_error) = combopt.vrp_savings(dist[..], 5usize, demand[..], 2.0f64, route[..], next[..], previous[..], load[..], savings[..], pairs[..])
    if vrp_error != ok || routes != 2usize || route[1usize] != route[2usize] || route[3usize] != route[4usize] || route[1usize] == route[3usize] { os.exit(2i32) }
    if load[route[1usize]] != 2.0f64 || load[route[3usize]] != 2.0f64 { os.exit(2i32) }

    // 3: knapsack and the generic branch and bound.
    var weights: [3]f64 = zero
    weights[0usize] = 10.0f64
    weights[1usize] = 20.0f64
    weights[2usize] = 30.0f64
    var values: [3]f64 = zero
    values[0usize] = 60.0f64
    values[1usize] = 100.0f64
    values[2usize] = 120.0f64
    var taken: [3]u8 = zero
    var current: [3]u8 = zero
    let (best, knapsack_error) = combopt.knapsack_branch_and_bound(weights[..], values[..], 50.0f64, taken[..], order[..3usize], current[..])
    if knapsack_error != ok || best != 220.0f64 || taken[0usize] != 0u8 || taken[1usize] != 1u8 || taken[2usize] != 1u8 { os.exit(3i32) }
    var assign = Assign { cost: zero, chosen: zero, used: zero, best: zero }
    let costs = "9 2 7 6 4 3 8 8 1"
    at = 0usize
    k = 0usize
    while at < costs.len {
        if costs[at] != 32u8 {
            assign.cost[k] = f64(costs[at] - 48u8)
            k += 1usize
        }
        at += 1usize
    }
    let (assignment_cost, leaves) = combopt.branch_and_bound[Assign](&assign, leaf_depth, choices, bound, branch, undo, record, 1.0e300f64)
    // Optimal: worker 0 -> job 1 (2), worker 1 -> job 0 (6), worker 2 -> job 2 (1): 9.
    if assignment_cost != 9.0f64 || leaves == 0usize || assign.best[0usize] != 1usize || assign.best[1usize] != 0usize || assign.best[2usize] != 2usize { os.exit(3i32) }

    // 4: large neighbourhood search shrinks the toy.
    var toy = Toy { values: zero, backup: zero, at: 0usize }
    i = 0usize
    while i < 8usize {
        toy.values[i] = 10.0f64
        i += 1usize
    }
    var r = rand.pcg64(4u64, 4u64)
    let (final_cost, improvements) = combopt.large_neighborhood_search[Toy](&toy, &r, 400usize, 800.0f64, destroy, repair, accept, restore)
    if final_cost >= 100.0f64 || improvements < 20usize { os.exit(4i32) }
    var check = 0.0f64
    i = 0usize
    while i < 8usize {
        check += toy.values[i] * toy.values[i]
        i += 1usize
    }
    if !near(check, final_cost, 0.000001f64) { os.exit(4i32) }

    try io.print("algo combopt ok\n")
    ret ok
}
