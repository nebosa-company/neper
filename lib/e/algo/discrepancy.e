// Discrepancy and derandomisation: the Beck-Fiala colouring (a +-1 assignment of the elements of a set system in which every element lies in at most t sets, each set with discrepancy below 2t), greedy vector balancing (the signed sum keeps its squared norm at most the sum of squared norms), and the conditional-expectation max-cut (a cut of at least half the edges).
//
// Not here: Spencer's six-standard-deviations bound (existential, via partial colouring and entropy), the Lovett-Meka algorithm, and weighted or hypergraph cuts.

use e.math
use e.mem

error Shape
error NoMemory

// sets is an m by n 0/1 incidence matrix (row-major); every column must have at most t ones; colour[j] receives -1 or +1; returns the largest absolute set sum, which is below 2 t
fn beck_fiala(a: *mem.Arena, sets: []const u8, m: usize, n: usize, t: usize, colour: []f64) -> (f64, err) {
    if sets.len < m * n || colour.len < n { ret (0.0f64, Shape) }
    let (mat, e1) = mem.alloc[f64](a, m * n)
    let (active, e2) = mem.alloc[bool](a, n)
    let (y, e3) = mem.alloc[f64](a, n)
    let (rows, e4) = mem.alloc[usize](a, m)
    let (pivcol, e5) = mem.alloc[usize](a, m)
    let (cols, e6) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0.0f64, NoMemory) }
    var j = 0usize
    while j < n {
        colour[j] = 0.0f64
        active[j] = true
        j += 1usize
    }
    var guard = 0usize
    while guard < n + 1usize {
        guard += 1usize
        var na = 0usize
        j = 0usize
        while j < n {
            if active[j] {
                cols[na] = j
                na += 1usize
            }
            j += 1usize
        }
        if na == 0usize { break }
        // the sets with more than t active elements are the constraints
        var nr = 0usize
        var s = 0usize
        while s < m {
            var cnt = 0usize
            j = 0usize
            while j < na {
                if sets[s * n + cols[j]] != 0u8 { cnt += 1usize }
                j += 1usize
            }
            if cnt > t {
                rows[nr] = s
                nr += 1usize
            }
            s += 1usize
        }
        var r = 0usize
        while r < nr {
            j = 0usize
            while j < na {
                mat[r * na + j] = f64(sets[rows[r] * n + cols[j]])
                j += 1usize
            }
            r += 1usize
        }
        // reduced row echelon form of the constraint matrix
        var rank = 0usize
        var c = 0usize
        while c < na && rank < nr {
            var best = rank
            r = rank + 1usize
            while r < nr {
                if math.abs[f64](mat[r * na + c]) > math.abs[f64](mat[best * na + c]) { best = r }
                r += 1usize
            }
            if math.abs[f64](mat[best * na + c]) > 1.0e-10f64 {
                if best != rank {
                    j = 0usize
                    while j < na {
                        let tmp = mat[rank * na + j]
                        mat[rank * na + j] = mat[best * na + j]
                        mat[best * na + j] = tmp
                        j += 1usize
                    }
                }
                let pv = mat[rank * na + c]
                j = 0usize
                while j < na {
                    mat[rank * na + j] = mat[rank * na + j] / pv
                    j += 1usize
                }
                r = 0usize
                while r < nr {
                    if r != rank {
                        let f = mat[r * na + c]
                        if f != 0.0f64 {
                            j = 0usize
                            while j < na {
                                mat[r * na + j] -= f * mat[rank * na + j]
                                j += 1usize
                            }
                        }
                    }
                    r += 1usize
                }
                pivcol[rank] = c
                rank += 1usize
            }
            c += 1usize
        }
        // a free column gives a null vector: 1 there, minus the reduced entries on the pivots
        var free = na
        c = 0usize
        while c < na {
            var is_pivot = false
            r = 0usize
            while r < rank {
                if pivcol[r] == c { is_pivot = true }
                r += 1usize
            }
            if !is_pivot {
                free = c
                break
            }
            c += 1usize
        }
        if free == na { break }
        j = 0usize
        while j < na {
            y[j] = 0.0f64
            j += 1usize
        }
        y[free] = 1.0f64
        r = 0usize
        while r < rank {
            y[pivcol[r]] = 0.0f64 - mat[r * na + free]
            r += 1usize
        }
        // the largest step that keeps every active element inside [-1, 1]
        var lam = 1.0e300f64
        j = 0usize
        while j < na {
            if y[j] > 1.0e-12f64 {
                let st = (1.0f64 - colour[cols[j]]) / y[j]
                if st < lam { lam = st }
            }
            if y[j] < 0.0f64 - 1.0e-12f64 {
                let st = (0.0f64 - 1.0f64 - colour[cols[j]]) / y[j]
                if st < lam { lam = st }
            }
            j += 1usize
        }
        j = 0usize
        while j < na {
            colour[cols[j]] += lam * y[j]
            if colour[cols[j]] > 1.0f64 - 1.0e-9f64 {
                colour[cols[j]] = 1.0f64
                active[cols[j]] = false
            }
            if colour[cols[j]] < 0.0f64 - 1.0f64 + 1.0e-9f64 {
                colour[cols[j]] = 0.0f64 - 1.0f64
                active[cols[j]] = false
            }
            j += 1usize
        }
    }
    var worst = 0.0f64
    var s2 = 0usize
    while s2 < m {
        var sum = 0.0f64
        j = 0usize
        while j < n {
            if sets[s2 * n + j] != 0u8 { sum += colour[j] }
            j += 1usize
        }
        if math.abs[f64](sum) > worst { worst = math.abs[f64](sum) }
        s2 += 1usize
    }
    ret (worst, ok)
}

// greedy vector balancing: signs[i] = +-1 chosen so the inner product with the running sum is not positive; the squared norm of the signed sum is then at most the sum of squared norms; vectors are an n by d row-major matrix; returns the squared norm of the signed sum
fn balance(vectors: []const f64, n: usize, d: usize, signs: []f64, sum: []f64) -> f64 {
    var k = 0usize
    while k < d {
        sum[k] = 0.0f64
        k += 1usize
    }
    var i = 0usize
    while i < n {
        var dot = 0.0f64
        k = 0usize
        while k < d {
            dot += sum[k] * vectors[i * d + k]
            k += 1usize
        }
        var sg = 1.0f64
        if dot > 0.0f64 { sg = 0.0f64 - 1.0f64 }
        signs[i] = sg
        k = 0usize
        while k < d {
            sum[k] += sg * vectors[i * d + k]
            k += 1usize
        }
        i += 1usize
    }
    var sq = 0.0f64
    k = 0usize
    while k < d {
        sq += sum[k] * sum[k]
        k += 1usize
    }
    ret sq
}

// max-cut by the method of conditional expectations: vertices in order go to the side that keeps the expected cut (undecided edges count one half) largest; edges are endpoint pairs of vertices 0 .. n - 1 (n at most 128); side[v] receives 0 or 1; returns the cut size, at least half the edges
fn max_cut(edges: []const usize, n: usize, side: []u8) -> usize {
    var decided: [128]bool = zero
    var v = 0usize
    while v < n {
        var to0 = 0usize
        var to1 = 0usize
        var e = 0usize
        while e + 1usize < edges.len {
            var other = n
            if edges[e] == v { other = edges[e + 1usize] }
            if edges[e + 1usize] == v { other = edges[e] }
            if other < n && other != v && decided[other] {
                // placing v opposite to a decided neighbour cuts that edge
                if side[other] == 0u8 { to1 += 1usize } else { to0 += 1usize }
            }
            e += 2usize
        }
        if to1 >= to0 { side[v] = 1u8 } else { side[v] = 0u8 }
        decided[v] = true
        v += 1usize
    }
    var cut = 0usize
    var e2 = 0usize
    while e2 + 1usize < edges.len {
        if side[edges[e2]] != side[edges[e2 + 1usize]] { cut += 1usize }
        e2 += 2usize
    }
    ret cut
}
