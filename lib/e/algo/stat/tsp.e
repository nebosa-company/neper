// R TSP: the tour constructions and the improvement heuristic of the package on a full n by n distance matrix
// (row-major, d[i * n + j] the distance from city i to j; not symmetric for an ATSP), with the package's random
// choices drawn from R's stream: `nn` (nearest neighbour from a start), `repetitive_nn` (the best of all starts),
// nearest, farthest, cheapest and arbitrary insertion, `two_opt` (best-improvement 2-opt), `tour_length`, the ATSP
// to TSP reformulation `reformulate_ATSP_as_TSP`, and `cut_tour` for one cut. Cities are 0-based here (R's are 1-based).
//
// Not here: the exact solvers (concorde, linkern), or-opt and three-opt, labels, the multi-cut `cut_tour`.

use e.algo.rand.r as rng
use e.mem

fn tour_length(d: []const f64, n: usize, tour: []const usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i + 1usize < n {
        s += d[tour[i] * n + tour[i + 1usize]]
        i += 1usize
    }
    if n > 1usize { s += d[tour[n - 1usize] * n + tour[0usize]] }
    ret s
}

// R's sample(x, 1) of a vector with more than one element
fn pick(g: *rng.Rng, a: *mem.Arena, k: usize) -> usize {
    if k <= 1usize { ret 0usize }
    let (s, e) = rng.sample_int(a, g, i64(k), 1i64, false)
    if e != ok { ret 0usize }
    ret usize(s[0usize] - 1i64)
}

// nn: always to the nearest city not yet placed; ties are drawn
fn nn(a: *mem.Arena, g: *rng.Rng, d: []const f64, n: usize, start: usize, tour: []usize) {
    let (placed, e1) = mem.alloc[bool](a, n)
    let (cand, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret }
    var i = 0usize
    while i < n {
        placed[i] = false
        i += 1usize
    }
    var cur = start
    tour[0usize] = cur
    placed[cur] = true
    var at = 1usize
    while at < n {
        var best = 0.0f64
        var nc = 0usize
        i = 0usize
        while i < n {
            if !placed[i] {
                let x = d[cur * n + i]
                if nc == 0usize || x < best {
                    best = x
                    nc = 0usize
                    cand[nc] = i
                    nc = 1usize
                } else if x == best {
                    cand[nc] = i
                    nc += 1usize
                }
            }
            i += 1usize
        }
        cur = cand[pick(g, a, nc)]
        tour[at] = cur
        placed[cur] = true
        at += 1usize
    }
}

// the best nn tour over every start (the first when tied); ties inside nn use the given stream
fn repetitive_nn(a: *mem.Arena, g: *rng.Rng, d: []const f64, n: usize, tour: []usize) {
    let (t, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret }
    var best = 0.0f64
    var s = 0usize
    while s < n {
        nn(a, g, d, n, s, t)
        let l = tour_length(d, n, t)
        if s == 0usize || l < best {
            best = l
            var i = 0usize
            while i < n {
                tour[i] = t[i]
                i += 1usize
            }
        }
        s += 1usize
    }
}

// the insertion cost of city k between each consecutive pair of order (and the closing pair): cost[i] for the link after position i
fn insertion_cost(d: []const f64, n: usize, order: []const usize, len: usize, k: usize, cost: []f64) {
    if len == 1usize {
        cost[0usize] = d[order[0usize] * n + k]
        ret
    }
    var i = 0usize
    while i < len {
        let nx = order[(i + 1usize) % len]
        cost[i] = d[order[i] * n + k] + d[k * n + nx] - d[order[i] * n + nx]
        i += 1usize
    }
}

// type 0 nearest, 1 farthest, 2 cheapest, 3 arbitrary insertion from start; asym adds the transposed distances to the nearest/farthest choice
fn insertion(a: *mem.Arena, g: *rng.Rng, d: []const f64, n: usize, kind: u8, start: usize, asym: bool, order: []usize) {
    let (placed, e1) = mem.alloc[bool](a, n)
    let (ks, e2) = mem.alloc[usize](a, n)
    let (cost, e3) = mem.alloc[f64](a, n)
    let (cand, e4) = mem.alloc[usize](a, n)
    let (ds, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret }
    var i = 0usize
    while i < n {
        placed[i] = false
        i += 1usize
    }
    placed[start] = true
    order[0usize] = start
    var len = 1usize
    while len < n {
        var nk = 0usize
        i = 0usize
        while i < n {
            if !placed[i] {
                ks[nk] = i
                nk += 1usize
            }
            i += 1usize
        }
        var k = 0usize
        if kind < 2u8 {
            var q = 0usize
            while q < nk {
                var m = d[ks[q] * n + order[0usize]]
                var j = 0usize
                while j < len {
                    var x = d[ks[q] * n + order[j]]
                    if x < m { m = x }
                    if asym {
                        x = d[order[j] * n + ks[q]]
                        if x < m { m = x }
                    }
                    j += 1usize
                }
                ds[q] = m
                q += 1usize
            }
            var bv = ds[0usize]
            q = 1usize
            while q < nk {
                if kind == 0u8 { if ds[q] < bv { bv = ds[q] } } else { if ds[q] > bv { bv = ds[q] } }
                q += 1usize
            }
            var nc = 0usize
            q = 0usize
            while q < nk {
                if ds[q] == bv {
                    cand[nc] = q
                    nc += 1usize
                }
                q += 1usize
            }
            k = ks[cand[pick(g, a, nc)]]
        } else if kind == 2u8 {
            var q = 0usize
            while q < nk {
                insertion_cost(d, n, order, len, ks[q], cost)
                var m = cost[0usize]
                var j = 1usize
                while j < len {
                    if cost[j] < m { m = cost[j] }
                    j += 1usize
                }
                ds[q] = m
                q += 1usize
            }
            var bv = ds[0usize]
            q = 1usize
            while q < nk {
                if ds[q] < bv { bv = ds[q] }
                q += 1usize
            }
            var nc = 0usize
            q = 0usize
            while q < nk {
                if ds[q] == bv {
                    cand[nc] = q
                    nc += 1usize
                }
                q += 1usize
            }
            k = ks[cand[pick(g, a, nc)]]
        } else {
            k = ks[pick(g, a, nk)]
        }
        placed[k] = true
        if len == 1usize {
            order[1usize] = k
        } else {
            insertion_cost(d, n, order, len, k, cost)
            var bv = cost[0usize]
            var j = 1usize
            while j < len {
                if cost[j] < bv { bv = cost[j] }
                j += 1usize
            }
            var nc = 0usize
            j = 0usize
            while j < len {
                if cost[j] == bv {
                    cand[nc] = j
                    nc += 1usize
                }
                j += 1usize
            }
            let pos = cand[pick(g, a, nc)]
            // insert after position pos
            var q = len
            while q > pos + 1usize {
                order[q] = order[q - 1usize]
                q -= 1usize
            }
            order[pos + 1usize] = k
        }
        len += 1usize
    }
}

// two_opt on a copy of tour: the swap of largest improvement (above 1e-7) until none helps; also right for an ATSP
fn two_opt(d: []const f64, n: usize, t: []usize) {
    let eps = 1.0e-7f64
    while true {
        var swaps = 0usize
        var swap1 = 0usize
        var swap2 = 0usize
        var best = 0.0f64
        var i = 1usize
        while i + 1usize < n {
            var imp = d[t[i - 1usize] * n + t[i]]
            imp += d[t[i] * n + t[i + 1usize]]
            var j = i + 1usize
            while j + 1usize < n {
                imp += d[t[j] * n + t[j + 1usize]]
                imp -= d[t[j] * n + t[j - 1usize]]
                let tmp = imp - d[t[i - 1usize] * n + t[j]] - d[t[i] * n + t[j + 1usize]]
                if tmp > eps {
                    swaps += 1usize
                    if tmp > best {
                        best = tmp
                        swap1 = i
                        swap2 = j
                    }
                }
                j += 1usize
            }
            j = n - 1usize
            imp -= d[t[j] * n + t[j - 1usize]]
            let tmp2 = imp - d[t[i - 1usize] * n + t[j]] - d[t[i] * n + t[0usize]]
            if tmp2 > eps {
                swaps += 1usize
                if tmp2 > best {
                    best = tmp2
                    swap1 = i
                    swap2 = j
                }
            }
            i += 1usize
        }
        if swaps == 0usize { break }
        var q = 0usize
        while q < (swap2 - swap1 + 1usize) / 2usize {
            let tmp = t[swap1 + q]
            t[swap1 + q] = t[swap2 - q]
            t[swap2 - q] = tmp
            q += 1usize
        }
    }
}

// reformulate_ATSP_as_TSP: the 2n by 2n symmetric matrix of the package (row-major in out)
fn atsp_to_tsp(m: []const f64, n: usize, infeasible: f64, cheap: f64, out: []f64) {
    let n2 = 2usize * n
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var v = m[i * n + j]
            if i == j { v = cheap }
            // a dist object keeps no diagonal, so as.matrix answers 0 there
            if i == j { out[i * n2 + j] = 0.0f64
                out[(i + n) * n2 + (j + n)] = 0.0f64 } else {
                out[i * n2 + j] = infeasible
                out[(i + n) * n2 + (j + n)] = infeasible
            }
            // upper right is t(m) and lower left is m
            out[j * n2 + (i + n)] = v
            out[(i + n) * n2 + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

// cut_tour for one cut city, exclude_cut as R: the path that follows the city in tour order (c(x, x)[(cut + excl):(n + cut - 1)]); returns its length
fn cut_tour(tour: []const usize, n: usize, cut: usize, exclude_cut: bool, path: []usize) -> usize {
    var pos = 0usize
    var i = 0usize
    while i < n {
        if tour[i] == cut { pos = i + 1usize }
        i += 1usize
    }
    var ex = 0usize
    if exclude_cut { ex = 1usize }
    if exclude_cut && n <= 1usize { ret 0usize }
    let lo = pos + ex
    let hi = n + pos - 1usize
    var k = 0usize
    var q = lo
    while q <= hi {
        path[k] = tour[(q - 1usize) % n]
        k += 1usize
        q += 1usize
    }
    ret k
}
