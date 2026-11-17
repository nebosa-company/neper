// R seriation, the TSP-based methods: seriate(d, "TSP") (TSP::solve_TSP on the dissimilarities with one dummy city
// at distance 0 from every object, the tour cut at the dummy) and BEA (the bond energy algorithm, seriation's
// BEA_TSP: cheapest insertion on max(c) - c of the row and column inner products). The insertion heuristics follow
// TSP 1.3.0's R code draw for draw (sample(), ties by sample), so under the same set.seed they give R's tour.
//
// The 2-opt refinement is TSP::tsp_two_opt, compiled C (R_two_opt) whose source is not on disk; two_opt below
// reproduces it from its answers (2000 random continuous cases and 300 with the dummy city, all equal). On
// dissimilarities with many exact ties the sums round differently from the C code and a tie can fall the other
// way (about 5 percent of cases built from integer-rounded points).
//
// Dissimilarities are a full symmetric n by n row-major matrix; orders are 0-based.

use e.algo.rand.r as rng
use e.math
use e.mem

// the cost of inserting city k after position p (0-based) of the first len entries of order, p = 0..len-1, the last one closing the cycle
fn insertion_cost(x: []const f64, m: usize, order: []const usize, len: usize, k: usize, p: usize) -> f64 {
    let o1 = order[p]
    var o2 = order[0usize]
    if p + 1usize < len { o2 = order[p + 1usize] }
    ret x[o1 * m + k] + x[k * m + o2] - x[o1 * m + o2]
}

fn draw_index(r: *rng.Rng, count: usize) -> usize {
    ret usize(rng.unif_index(r, f64(count)))
}

// TSP's choose1: one of the candidates, drawn by sample() when there are several
fn choose_one(r: *rng.Rng, cand: []const usize, count: usize) -> usize {
    if count > 1usize { ret cand[draw_index(r, count)] }
    ret cand[0usize]
}

fn tour_length(x: []const f64, m: usize, order: []const usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m {
        var nx = order[0usize]
        if i + 1usize < m { nx = order[i + 1usize] }
        s += x[order[i] * m + nx]
        i += 1usize
    }
    ret s
}

// tsp_insertion: kind 1 nearest, 2 farthest, 3 cheapest; out receives the m cities of the tour
fn insertion_tour(a: *mem.Arena, r: *rng.Rng, x: []const f64, m: usize, kind: usize, out: []usize) -> err {
    let (placed, e1) = mem.alloc[bool](a, m)
    let (ks, e2) = mem.alloc[usize](a, m)
    let (cand, e3) = mem.alloc[usize](a, m)
    let (ds, e4) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < m {
        placed[i] = false
        i += 1usize
    }
    // list(start = sample(n, 1), ...) is evaluated whether or not a start is given
    let start = draw_index(r, m)
    placed[start] = true
    out[0usize] = start
    var len = 1usize
    while len < m {
        var nk = 0usize
        i = 0usize
        while i < m {
            if !placed[i] {
                ks[nk] = i
                nk += 1usize
            }
            i += 1usize
        }
        var w = 0usize
        var q = 0usize
        while q < nk {
            let k = ks[q]
            if kind == 3usize {
                var best = 1.0e308f64
                var p = 0usize
                while p < len {
                    let c = insertion_cost(x, m, out, len, k, p)
                    if c < best { best = c }
                    p += 1usize
                }
                ds[q] = best
            } else {
                var best = 1.0e308f64
                var j = 0usize
                while j < m {
                    if placed[j] && x[k * m + j] < best { best = x[k * m + j] }
                    j += 1usize
                }
                ds[q] = best
            }
            q += 1usize
        }
        var goal = ds[0usize]
        q = 1usize
        while q < nk {
            if kind == 2usize {
                if ds[q] > goal { goal = ds[q] }
            } else {
                if ds[q] < goal { goal = ds[q] }
            }
            q += 1usize
        }
        var nc = 0usize
        q = 0usize
        while q < nk {
            if ds[q] == goal {
                cand[nc] = q
                nc += 1usize
            }
            q += 1usize
        }
        w = choose_one(r, cand, nc)
        let k = ks[w]
        placed[k] = true
        if len == 1usize {
            out[1usize] = k
        } else {
            var bestc = 1.0e308f64
            var p = 0usize
            while p < len {
                let c = insertion_cost(x, m, out, len, k, p)
                if c < bestc { bestc = c }
                p += 1usize
            }
            nc = 0usize
            p = 0usize
            while p < len {
                if insertion_cost(x, m, out, len, k, p) == bestc {
                    cand[nc] = p
                    nc += 1usize
                }
                p += 1usize
            }
            let pos = choose_one(r, cand, nc)
            // append(order, k, after = pos + 1): k lands at index pos + 1
            var s = len
            while s > pos + 1usize {
                out[s] = out[s - 1usize]
                s -= 1usize
            }
            out[pos + 1usize] = k
        }
        len += 1usize
    }
    ret ok
}

// tsp_insertion_arbitrary: a random order of the cities inserted one by one at the cheapest place (the first, by which.min)
fn arbitrary_tour(a: *mem.Arena, r: *rng.Rng, x: []const f64, m: usize, out: []usize) -> err {
    if m == 1usize {
        out[0usize] = 0usize
        ret ok
    }
    let (perm, pe) = rng.sample_int(a, r, i64(m), i64(m), false)
    if pe != ok { ret pe }
    if m == 2usize {
        out[0usize] = usize(perm[0usize]) - 1usize
        out[1usize] = usize(perm[1usize]) - 1usize
        ret ok
    }
    let (xr, e1) = mem.alloc[f64](a, m * m)
    let (ord, e2) = mem.alloc[usize](a, m)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            xr[i * m + j] = x[(usize(perm[i]) - 1usize) * m + usize(perm[j]) - 1usize]
            j += 1usize
        }
        i += 1usize
    }
    ord[0usize] = 0usize
    ord[1usize] = 1usize
    var len = 2usize
    while len < m {
        var bestc = 1.0e308f64
        var bp = 0usize
        var p = 0usize
        while p < len {
            let c = insertion_cost(xr, m, ord, len, len, p)
            if c < bestc {
                bestc = c
                bp = p
            }
            p += 1usize
        }
        var s = len
        while s > bp + 1usize {
            ord[s] = ord[s - 1usize]
            s -= 1usize
        }
        ord[bp + 1usize] = len
        len += 1usize
    }
    i = 0usize
    while i < m {
        out[i] = usize(perm[ord[i]]) - 1usize
        i += 1usize
    }
    ret ok
}

// TSP's R_two_opt, found by comparing against the compiled routine: best improvement over every pair of edges (first
// pair in row order on ties), the reversal of the inner segment; the pair that would drop the closing edge (the last
// city, then the first) counts only the new edges a-c and b-first and the dropped a-b, never the old closing edge.
fn two_opt(x: []const f64, m: usize, t: []usize) {
    if m < 4usize { ret }
    var more = true
    var guard = 0usize
    while more && guard < 100000usize {
        more = false
        guard += 1usize
        var best = 0.0f64
        var bi = 0usize
        var bj = 0usize
        var i = 0usize
        while i + 2usize < m {
            var j = i + 2usize
            while j < m {
                var g = 0.0f64
                if j + 1usize < m {
                    g = x[t[i] * m + t[i + 1usize]] + x[t[j] * m + t[j + 1usize]] - x[t[i] * m + t[j]] - x[t[i + 1usize] * m + t[j + 1usize]]
                } else {
                    g = x[t[i] * m + t[i + 1usize]] - x[t[i] * m + t[j]] - x[t[i + 1usize] * m + t[0usize]]
                }
                if g > best {
                    best = g
                    bi = i
                    bj = j
                    more = true
                }
                j += 1usize
            }
            i += 1usize
        }
        if more {
            var lo = bi + 1usize
            var hi = bj
            while lo < hi {
                let tmp = t[lo]
                t[lo] = t[hi]
                t[hi] = tmp
                lo += 1usize
                hi -= 1usize
            }
        }
    }
}

// solve_TSP on the m cities of x: method 1..3 insertion heuristics, 4 arbitrary insertion; opt applies two_opt; rep restarts from sampled seeds
fn solve_tsp(a: *mem.Arena, r: *rng.Rng, x: []const f64, m: usize, method: usize, opt: bool, rep: usize, out: []usize) -> err {
    if rep <= 1usize {
        var e = ok
        if method == 4usize { e = arbitrary_tour(a, r, x, m, out) } else { e = insertion_tour(a, r, x, m, method, out) }
        if e != ok { ret e }
        if opt { two_opt(x, m, out) }
        ret ok
    }
    let (seeds, se) = rng.sample_int(a, r, 2147483647i64, i64(rep), false)
    if se != ok { ret se }
    let (cur, e1) = mem.alloc[usize](a, m)
    if e1 != ok { ret e1 }
    var bestlen = 1.0e308f64
    var k = 0usize
    while k < rep {
        var rr: rng.Rng = zero
        rng.seed(&rr, seeds[k])
        var e = ok
        if method == 4usize { e = arbitrary_tour(a, &rr, x, m, cur) } else { e = insertion_tour(a, &rr, x, m, method, cur) }
        if e != ok { ret e }
        if opt { two_opt(x, m, cur) }
        let len = tour_length(x, m, cur)
        if len < bestlen {
            bestlen = len
            var i = 0usize
            while i < m {
                out[i] = cur[i]
                i += 1usize
            }
        }
        k += 1usize
    }
    ret ok
}

// seriate(d, "TSP", control = list(method, two_opt, rep)): a dummy city, the tour, cut at the dummy; method 4 is the default (arbitrary insertion with 2-opt, rep 1)
fn tsp_order(a: *mem.Arena, r: *rng.Rng, d: []const f64, n: usize, method: usize, opt: bool, rep: usize, out: []usize) -> err {
    if n < 2usize {
        out[0usize] = 0usize
        ret ok
    }
    let m = n + 1usize
    let (x, e1) = mem.alloc[f64](a, m * m)
    let (tour, e2) = mem.alloc[usize](a, m)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            x[i * m + j] = 0.0f64
            if i < n && j < n { x[i * m + j] = d[i * n + j] }
            j += 1usize
        }
        i += 1usize
    }
    let e = solve_tsp(a, r, x, m, method, opt, rep, tour)
    if e != ok { ret e }
    var cut = 0usize
    i = 0usize
    while i < m {
        if tour[i] == n { cut = i }
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = tour[(cut + 1usize + i) % m]
        i += 1usize
    }
    ret ok
}

// BEA of a nonnegative nr by nc matrix (row-major): the row order from cheapest insertion on max(c) - c of the row inner products, then the column order from the column ones
fn bea_order(a: *mem.Arena, r: *rng.Rng, x: []const f64, nr: usize, nc: usize, row_out: []usize, col_out: []usize) -> err {
    let sz = nr
    var side = 0usize
    while side < 2usize {
        var cnt = nr
        if side == 1usize { cnt = nc }
        if cnt == 1usize {
            if side == 0usize { row_out[0usize] = 0usize } else { col_out[0usize] = 0usize }
        } else {
            let (c, e1) = mem.alloc[f64](a, cnt * cnt)
            let (o, e2) = mem.alloc[usize](a, cnt)
            if e1 != ok || e2 != ok { ret mem.Full }
            var mx = -1.0e308f64
            var i = 0usize
            while i < cnt {
                var j = 0usize
                while j < cnt {
                    var s = 0.0f64
                    if side == 0usize {
                        var k = 0usize
                        while k < nc {
                            s += x[i * nc + k] * x[j * nc + k]
                            k += 1usize
                        }
                    } else {
                        var k = 0usize
                        while k < nr {
                            s += x[k * nc + i] * x[k * nc + j]
                            k += 1usize
                        }
                    }
                    c[i * cnt + j] = s
                    if i > j && s > mx { mx = s }
                    j += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < cnt {
                var j = 0usize
                while j < cnt {
                    c[i * cnt + j] = mx - c[i * cnt + j]
                    j += 1usize
                }
                c[i * cnt + i] = 0.0f64
                i += 1usize
            }
            let e = tsp_order(a, r, c, cnt, 3usize, false, 1usize, o)
            if e != ok { ret e }
            i = 0usize
            while i < cnt {
                if side == 0usize { row_out[i] = o[i] } else { col_out[i] = o[i] }
                i += 1usize
            }
        }
        side += 1usize
    }
    if sz == 0usize { ret mem.Full }
    ret ok
}
