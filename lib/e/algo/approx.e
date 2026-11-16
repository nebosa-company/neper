// Approximation algorithms with their proven ratios: 2-approximate vertex cover by a maximal matching, list scheduling (2 - 1/m) and LPT (4/3 - 1/(3m)) for makespan, the knapsack FPTAS ((1 - eps) of the optimum) and a local-search 1/2-approximate max-cut. Instances are caller-owned slices.
//
// Set cover, bin packing and the travelling salesman are in e.algo.combopt (set_cover_greedy, bin_pack_ffd, the tsp_ routines) and are not repeated here.

use e.algo.combopt as combopt
use e.mem

error Shape
error NoMemory

// edges holds endpoint pairs (u0, v0, u1, v1, ...) of vertices 0 .. n - 1; marks cover[v] for a vertex cover no larger than twice the optimum (both ends of a greedily built maximal matching); returns the cover size
fn vertex_cover(edges: []const usize, n: usize, cover: []bool) -> usize {
    var v = 0usize
    while v < n {
        cover[v] = false
        v += 1usize
    }
    var count = 0usize
    var e = 0usize
    while e + 1usize < edges.len {
        let u = edges[e]
        let w = edges[e + 1usize]
        if !cover[u] && !cover[w] {
            cover[u] = true
            cover[w] = true
            count += 2usize
        }
        e += 2usize
    }
    ret count
}

fn vertex_cover_ratio() -> f64 { ret 2.0f64 }

// list scheduling in the given order on m machines: job j goes to the least loaded machine; assign[j] is its machine, loads the machine loads; returns the makespan, at most (2 - 1/m) times the optimum
fn list_schedule(jobs: []const f64, m: usize, assign: []usize, loads: []f64) -> f64 {
    var i = 0usize
    while i < m {
        loads[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < jobs.len {
        var best = 0usize
        i = 1usize
        while i < m {
            if loads[i] < loads[best] { best = i }
            i += 1usize
        }
        assign[j] = best
        loads[best] += jobs[j]
        j += 1usize
    }
    var mk = 0.0f64
    i = 0usize
    while i < m {
        if loads[i] > mk { mk = loads[i] }
        i += 1usize
    }
    ret mk
}

fn list_schedule_ratio(m: usize) -> f64 { ret 2.0f64 - 1.0f64 / f64(m) }

// longest processing time first: the jobs sorted by decreasing length (order receives their indices), then list scheduling; at most (4/3 - 1/(3m)) times the optimum
fn lpt(jobs: []const f64, m: usize, order: []usize, assign: []usize, loads: []f64) -> f64 {
    var j = 0usize
    while j < jobs.len {
        order[j] = j
        j += 1usize
    }
    j = 1usize
    while j < jobs.len {
        let v = order[j]
        var k = j
        while k > 0usize && jobs[order[k - 1usize]] < jobs[v] {
            order[k] = order[k - 1usize]
            k -= 1usize
        }
        order[k] = v
        j += 1usize
    }
    var i = 0usize
    while i < m {
        loads[i] = 0.0f64
        i += 1usize
    }
    j = 0usize
    while j < jobs.len {
        let job = order[j]
        var best = 0usize
        i = 1usize
        while i < m {
            if loads[i] < loads[best] { best = i }
            i += 1usize
        }
        assign[job] = best
        loads[best] += jobs[job]
        j += 1usize
    }
    var mk = 0.0f64
    i = 0usize
    while i < m {
        if loads[i] > mk { mk = loads[i] }
        i += 1usize
    }
    ret mk
}

fn lpt_ratio(m: usize) -> f64 { ret 4.0f64 / 3.0f64 - 1.0f64 / (3.0f64 * f64(m)) }

// 0/1 knapsack FPTAS: values scaled down by eps * vmax / n and a minimum-weight dynamic programme over the scaled value; take[i] marks the chosen items; returns their true value, at least (1 - eps) times the optimum
fn knapsack_fptas(a: *mem.Arena, values: []const f64, weights: []const f64, cap: f64, eps: f64, take: []bool) -> (f64, err) {
    let n = values.len
    if weights.len != n || take.len < n { ret (0.0f64, Shape) }
    var vmax = 0.0f64
    var i = 0usize
    while i < n {
        take[i] = false
        if weights[i] <= cap && values[i] > vmax { vmax = values[i] }
        i += 1usize
    }
    if vmax <= 0.0f64 { ret (0.0f64, ok) }
    let k = eps * vmax / f64(n)
    let (sv, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (0.0f64, NoMemory) }
    var total = 0usize
    i = 0usize
    while i < n {
        sv[i] = usize(values[i] / k)
        total += sv[i]
        i += 1usize
    }
    let width = total + 1usize
    let (dp, e2) = mem.alloc[f64](a, width)
    let (pick, e3) = mem.alloc[bool](a, n * width)
    if e2 != ok || e3 != ok { ret (0.0f64, NoMemory) }
    let inf = 1.0e300f64
    var p = 0usize
    while p < width {
        dp[p] = inf
        p += 1usize
    }
    dp[0usize] = 0.0f64
    i = 0usize
    while i < n {
        p = 0usize
        while p < width {
            pick[i * width + p] = false
            p += 1usize
        }
        p = width
        while p > 0usize {
            p -= 1usize
            if p >= sv[i] && dp[p - sv[i]] < inf {
                let w = dp[p - sv[i]] + weights[i]
                if w < dp[p] {
                    dp[p] = w
                    pick[i * width + p] = true
                }
            }
        }
        i += 1usize
    }
    var best = 0usize
    p = 0usize
    while p < width {
        if dp[p] <= cap { best = p }
        p += 1usize
    }
    // walk the choices back from the best scaled value
    var at = best
    var item = n
    while item > 0usize {
        item -= 1usize
        if pick[item * width + at] {
            take[item] = true
            at -= sv[item]
        }
    }
    var val = 0.0f64
    i = 0usize
    while i < n {
        if take[i] { val += values[i] }
        i += 1usize
    }
    ret (val, ok)
}

// local-search max-cut: side[v] is the part of vertex v; every vertex is moved while that cuts more edges, so at least half of the edges are cut; returns the cut size
fn max_cut(edges: []const usize, n: usize, side: []bool) -> usize {
    var v = 0usize
    while v < n {
        side[v] = false
        v += 1usize
    }
    var improved = true
    while improved {
        improved = false
        v = 0usize
        while v < n {
            var same = 0usize
            var other = 0usize
            var e = 0usize
            while e + 1usize < edges.len {
                var nb = n
                if edges[e] == v { nb = edges[e + 1usize] }
                if edges[e + 1usize] == v { nb = edges[e] }
                if nb < n && nb != v {
                    if side[nb] == side[v] { same += 1usize } else { other += 1usize }
                }
                e += 2usize
            }
            if same > other {
                side[v] = !side[v]
                improved = true
            }
            v += 1usize
        }
    }
    var cut = 0usize
    var e = 0usize
    while e + 1usize < edges.len {
        if side[edges[e]] != side[edges[e + 1usize]] { cut += 1usize }
        e += 2usize
    }
    ret cut
}

fn max_cut_ratio() -> f64 { ret 0.5f64 }

// set cover by the greedy rule of e.algo.combopt; its ratio is the harmonic number H(universe), at most ln(universe) + 1
fn set_cover(membership: []const u8, sets: usize, universe: usize, chosen: []usize, covered: []u8) -> (usize, err) {
    let (count, e) = combopt.set_cover_greedy(membership, sets, universe, chosen, covered)
    ret (count, e)
}

fn set_cover_ratio(universe: usize) -> f64 {
    var h = 0.0f64
    var i = 1usize
    while i <= universe {
        h += 1.0f64 / f64(i)
        i += 1usize
    }
    ret h
}

// bin packing by first-fit decreasing from e.algo.combopt: at most 11/9 OPT + 6/9 bins, and since OPT >= the total size over the capacity, a checkable bound follows
fn bin_pack(sizes: []const f64, capacity: f64, bins: []usize, loads: []f64, order: []usize) -> (usize, err) {
    let (count, e) = combopt.bin_pack_ffd(sizes, capacity, bins, loads, order)
    ret (count, e)
}

fn bin_pack_ratio(opt: usize) -> f64 { ret 11.0f64 / 9.0f64 * f64(opt) + 6.0f64 / 9.0f64 }
