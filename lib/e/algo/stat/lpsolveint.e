// lp(..., int.vec = isint, binary.vec = isbin, compute.sens = 1) with <= rows: lpSolve reports the duals of the last linear program of its branch and bound, in which every integer variable
// sits at its value in the optimum (x* from lp_general). So the constraint prices are those of the program over the continuous variables with the integer part moved to the right-hand
// side (zero when every variable is integer), and an integer variable's reduced cost is c_j - sum_i duals_i a_ij. duals receive the m constraint prices then the n reduced costs; the
// answer is the optimum. With >= or = rows lp_solve's last program keeps some integer variables basic and its choice is not reproduced; neither are the right-hand-side and coefficient ranges.

use e.algo.stat.lpsolvepkg as lps
use e.mem

error Malformed

fn lp_sens_int(a: *mem.Arena, c: []const f64, am: []const f64, b: []const f64, rel: []const usize, m: usize, n: usize, maximise: bool, isint: []const bool, isbin: []const bool, duals: []f64) -> (f64, err) {
    var nb = 0usize
    var j = 0usize
    while j < n {
        if isbin[j] { nb += 1usize }
        j += 1usize
    }
    let mm = m + nb
    let (ae, e0) = mem.alloc[f64](a, mm * n)
    let (be, e1) = mem.alloc[f64](a, mm)
    let (re, e2) = mem.alloc[usize](a, mm)
    let (ia, e3) = mem.alloc[bool](a, n)
    let (xs, e4) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < mm * n {
        ae[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        j = 0usize
        while j < n {
            ae[i * n + j] = am[i * n + j]
            j += 1usize
        }
        be[i] = b[i]
        re[i] = rel[i]
        i += 1usize
    }
    var r = m
    j = 0usize
    while j < n {
        ia[j] = isint[j] || isbin[j]
        if isbin[j] {
            ae[r * n + j] = 1.0f64
            be[r] = 1.0f64
            re[r] = 0usize
            r += 1usize
        }
        j += 1usize
    }
    let (v, st) = lps.lp_general(a, maximise, c, ae, re, be, mm, n, ia, xs)
    if st != 0usize { ret (0.0f64, Malformed) }
    var nc = 0usize
    j = 0usize
    while j < n {
        if !ia[j] { nc += 1usize }
        j += 1usize
    }
    i = 0usize
    while i < m + n {
        duals[i] = 0.0f64
        i += 1usize
    }
    if nc > 0usize {
        let (cq, f0) = mem.alloc[f64](a, nc)
        let (aq, f1) = mem.alloc[f64](a, m * nc)
        let (bq, f2) = mem.alloc[f64](a, m)
        let (xq, f3) = mem.alloc[f64](a, nc)
        let (dq, f4) = mem.alloc[f64](a, m + nc)
        let (s1, f5) = mem.alloc[f64](a, m + nc)
        let (s2, f6) = mem.alloc[f64](a, m + nc)
        let (s3, f7) = mem.alloc[f64](a, nc)
        let (s4, f8) = mem.alloc[f64](a, nc)
        if f0 != ok || f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok { ret (0.0f64, mem.Full) }
        i = 0usize
        while i < m {
            bq[i] = b[i]
            var q = 0usize
            j = 0usize
            while j < n {
                if ia[j] {
                    bq[i] = bq[i] - am[i * n + j] * xs[j]
                } else {
                    aq[i * nc + q] = am[i * n + j]
                    q += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        var q = 0usize
        j = 0usize
        while j < n {
            if !ia[j] {
                cq[q] = c[j]
                q += 1usize
            }
            j += 1usize
        }
        let (v2, es) = lps.lp_sens(a, cq, aq, bq, rel, m, nc, maximise, xq, dq, s1, s2, s3, s4)
        let _ = v2
        if es != ok { ret (0.0f64, es) }
        i = 0usize
        while i < m {
            duals[i] = dq[i]
            i += 1usize
        }
        q = 0usize
        j = 0usize
        while j < n {
            if !ia[j] {
                duals[m + j] = dq[m + q]
                q += 1usize
            }
            j += 1usize
        }
    }
    j = 0usize
    while j < n {
        if ia[j] {
            var z = 0.0f64
            i = 0usize
            while i < m {
                z += duals[i] * am[i * n + j]
                i += 1usize
            }
            duals[m + j] = c[j] - z
        }
        j += 1usize
    }
    ret (v, ok)
}
