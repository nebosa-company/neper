// clue::solve_LSAP and cl_membership: the linear sum assignment problem over a rectangular cost matrix, with the maximum option, and the membership matrix of a hard partition.
// solve_LSAP is clue's own assignment.c (the Hungarian method with preprocess, preassign, cover and reduce), so ties are broken as R breaks them.

use e.mem

error Malformed

// one step of the cover phase: answers true when an augmenting path was found (clue's NOREDUCE), false when the reduce step is due
fn lsap_cover(n: usize, c: []f64, s: []usize, f: []usize, ri: []bool, ci: []bool, mr: []bool, na: *usize) -> bool {
    let w = n + 1usize
    var i = 1usize
    while i <= n {
        ci[i] = false
        mr[i] = false
        ri[i] = true
        if s[i] == 0usize {
            ri[i] = false
            mr[i] = true
        }
        i += 1usize
    }
    while true {
        var r = 0usize
        i = 1usize
        while i <= n {
            if mr[i] {
                r = i
                break
            }
            i += 1usize
        }
        if r == 0usize { break }
        i = 1usize
        while i <= n {
            if c[r * w + i] == 0.0f64 && !ci[i] {
                if f[i] != 0usize {
                    ri[f[i]] = false
                    mr[f[i]] = true
                    ci[i] = true
                } else {
                    if s[r] == 0usize { *na = *na + 1usize }
                    f[s[r]] = 0usize
                    f[i] = r
                    s[r] = i
                    ret true
                }
            }
            i += 1usize
        }
        mr[r] = false
    }
    ret false
}

fn lsap_reduce(n: usize, c: []f64, ri: []const bool, ci: []const bool) {
    let w = n + 1usize
    var lo = 1.7976931348623157e308f64
    var i = 1usize
    while i <= n {
        var j = 1usize
        while j <= n {
            if !ri[i] && !ci[j] && c[i * w + j] < lo { lo = c[i * w + j] }
            j += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i <= n {
        var j = 1usize
        while j <= n {
            if !ri[i] && !ci[j] { c[i * w + j] = c[i * w + j] - lo }
            if ri[i] && ci[j] { c[i * w + j] = c[i * w + j] + lo }
            j += 1usize
        }
        i += 1usize
    }
}

// solve_LSAP(x, maximum) for an nr by nc cost matrix with nr <= nc (row-major): the column of each row in assign (0-based) and the total cost of the matching. As in R the
// rows are padded to a square with 2 * sum(x) and, for maximum, the matrix becomes max - x before clue's C solver runs.
fn solve_lsap(a: *mem.Arena, x: []const f64, nr: usize, nc: usize, maximum: bool, assign: []usize) -> (f64, err) {
    if nr > nc { ret (0.0f64, Malformed) }
    let n = nc
    let w = n + 1usize
    let (c, e0) = mem.alloc[f64](a, w * w)
    let (s, e1) = mem.alloc[usize](a, w)
    let (f, e2) = mem.alloc[usize](a, w)
    let (ri, e3) = mem.alloc[bool](a, w)
    let (ci, e4) = mem.alloc[bool](a, w)
    let (mr, e5) = mem.alloc[bool](a, w)
    let (rz, e6) = mem.alloc[usize](a, w)
    let (cz, e7) = mem.alloc[usize](a, w)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (0.0f64, mem.Full) }
    var sum = 0.0f64
    var k = 0usize
    while k < nr * nc {
        sum += x[k]
        k += 1usize
    }
    var i = 1usize
    while i <= n {
        var j = 1usize
        while j <= n {
            if i <= nr {
                c[i * w + j] = x[(i - 1usize) * nc + j - 1usize]
            } else {
                c[i * w + j] = 2.0f64 * sum
            }
            j += 1usize
        }
        s[i] = 0usize
        f[i] = 0usize
        i += 1usize
    }
    s[0usize] = 0usize
    f[0usize] = 0usize
    if maximum {
        var top = c[w + 1usize]
        i = 1usize
        while i <= n {
            var j = 1usize
            while j <= n {
                if c[i * w + j] > top { top = c[i * w + j] }
                j += 1usize
            }
            i += 1usize
        }
        i = 1usize
        while i <= n {
            var j = 1usize
            while j <= n {
                c[i * w + j] = top - c[i * w + j]
                j += 1usize
            }
            i += 1usize
        }
    }
    // preprocess: subtract row minima, then column minima
    i = 1usize
    while i <= n {
        var lo = c[i * w + 1usize]
        var j = 2usize
        while j <= n {
            if c[i * w + j] < lo { lo = c[i * w + j] }
            j += 1usize
        }
        j = 1usize
        while j <= n {
            c[i * w + j] = c[i * w + j] - lo
            j += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i <= n {
        var lo = c[w + i]
        var j = 2usize
        while j <= n {
            if c[j * w + i] < lo { lo = c[j * w + i] }
            j += 1usize
        }
        j = 1usize
        while j <= n {
            c[j * w + i] = c[j * w + i] - lo
            j += 1usize
        }
        i += 1usize
    }
    // preassign: rows with the fewest zeros first, the column with the fewest zeros in that row
    var na = 0usize
    i = 1usize
    while i <= n {
        ri[i] = false
        ci[i] = false
        var cnt = 0usize
        var j = 1usize
        while j <= n {
            if c[i * w + j] == 0.0f64 { cnt += 1usize }
            j += 1usize
        }
        rz[i] = cnt
        cnt = 0usize
        j = 1usize
        while j <= n {
            if c[j * w + i] == 0.0f64 { cnt += 1usize }
            j += 1usize
        }
        cz[i] = cnt
        i += 1usize
    }
    while true {
        var lo = 1000000000usize
        var r = 0usize
        i = 1usize
        while i <= n {
            if rz[i] > 0usize && rz[i] < lo && !ri[i] {
                lo = rz[i]
                r = i
            }
            i += 1usize
        }
        if r == 0usize { break }
        var col = 0usize
        lo = 1000000000usize
        i = 1usize
        while i <= n {
            if c[r * w + i] == 0.0f64 && cz[i] < lo && !ci[i] {
                lo = cz[i]
                col = i
            }
            i += 1usize
        }
        if col != 0usize {
            na += 1usize
            s[r] = col
            f[col] = r
            ri[r] = true
            ci[col] = true
            cz[col] = 0usize
            i = 1usize
            while i <= n {
                if c[i * w + col] == 0.0f64 { rz[i] = rz[i] - 1usize }
                i += 1usize
            }
        }
    }
    while na < n {
        if !lsap_cover(n, c, s, f, ri, ci, mr, &na) { lsap_reduce(n, c, ri, ci) }
    }
    var total = 0.0f64
    i = 1usize
    while i <= nr {
        assign[i - 1usize] = s[i] - 1usize
        total += x[(i - 1usize) * nc + s[i] - 1usize]
        i += 1usize
    }
    ret (total, ok)
}

// cl_membership of a hard partition: the n by k indicator matrix (row-major, zeroed here) of the class labels cx in 1..k
fn membership_hard(cx: []const usize, n: usize, k: usize, out: []f64) {
    var i = 0usize
    while i < n * k {
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i * k + cx[i] - 1usize] = 1.0f64
        i += 1usize
    }
}

// cl_membership(x, k) of a soft partition: the n by k0 membership matrix u (row-major) padded with zero columns to k >= k0
fn membership_soft(u: []const f64, n: usize, k0: usize, k: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            var v = 0.0f64
            if j < k0 { v = u[i * k0 + j] }
            out[i * k + j] = v
            j += 1usize
        }
        i += 1usize
    }
}
