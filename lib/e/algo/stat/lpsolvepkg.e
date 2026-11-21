// lpSolve's integer programs: lp("max", ..., int.vec = ...) as a depth-first branch and bound over the simplex of e.math.opt (A x <= b, x >= 0), branching on the lowest
// indexed fractional integer variable and cutting a branch whose relaxation cannot beat the incumbent. The optimum value is unique, so that is what agrees with lpSolve;
// the solution returned is the first optimal one found.

use e.math
use e.math.opt as opt
use e.mem

error Malformed

type Best = struct { obj: f64, found: bool }

// the relaxation at a node: the rows of am (m by n) and b, then x_j <= hi[j] for finite hi and -x_j <= -lo[j] for a positive lo; m is the number of original rows
fn node(a: *mem.Arena, cc: []const f64, am: []const f64, b: []const f64, m: usize, n: usize, isint: []const bool, lo: []const f64, hi: []const f64, best: *Best, bx: []f64) -> err {
    var extra = 0usize
    var j = 0usize
    while j < n {
        if hi[j] < 1.0e30f64 { extra += 1usize }
        if lo[j] > 0.0f64 { extra += 1usize }
        j += 1usize
    }
    let mm = m + extra
    let (a2, e0) = mem.alloc[f64](a, mm * n)
    let (b2, e1) = mem.alloc[f64](a, mm)
    if e0 != ok || e1 != ok { ret mem.Full }
    var i = 0usize
    while i < m * n {
        a2[i] = am[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        b2[i] = b[i]
        i += 1usize
    }
    var r = m
    j = 0usize
    while j < n {
        if hi[j] < 1.0e30f64 {
            var q = 0usize
            while q < n {
                a2[r * n + q] = 0.0f64
                q += 1usize
            }
            a2[r * n + j] = 1.0f64
            b2[r] = hi[j]
            r += 1usize
        }
        if lo[j] > 0.0f64 {
            var q = 0usize
            while q < n {
                a2[r * n + q] = 0.0f64
                q += 1usize
            }
            a2[r * n + j] = 0.0f64 - 1.0f64
            b2[r] = 0.0f64 - lo[j]
            r += 1usize
        }
        j += 1usize
    }
    let (sol, e2) = mem.alloc[f64](a, n)
    let (tab, e3) = mem.alloc[f64](a, (mm + 2usize) * (n + mm + 2usize))
    let (bas, e4) = mem.alloc[usize](a, mm)
    if e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let (obj, es) = opt.simplex(cc, a2, b2, mm, n, sol, tab, bas)
    if es != ok { ret ok }
    if best.found && obj <= best.obj + 0.000000001f64 { ret ok }
    // the lowest indexed fractional integer variable
    var branch = n
    j = 0usize
    while j < n && branch == n {
        if isint[j] {
            let f = sol[j] - math.floor[f64](sol[j])
            if f > 0.0000001f64 && f < 1.0f64 - 0.0000001f64 { branch = j }
        }
        j += 1usize
    }
    if branch == n {
        best.obj = obj
        best.found = true
        j = 0usize
        while j < n {
            bx[j] = sol[j]
            j += 1usize
        }
        ret ok
    }
    let fl = math.floor[f64](sol[branch])
    // the up branch first (lpSolve's default is the ceiling), then the down branch
    let old_lo = lo[branch]
    let old_hi = hi[branch]
    let (lo2, e5) = mem.alloc[f64](a, n)
    let (hi2, e6) = mem.alloc[f64](a, n)
    if e5 != ok || e6 != ok { ret mem.Full }
    j = 0usize
    while j < n {
        lo2[j] = lo[j]
        hi2[j] = hi[j]
        j += 1usize
    }
    lo2[branch] = fl + 1.0f64
    let eu = node(a, cc, am, b, m, n, isint, lo2, hi2, best, bx)
    if eu != ok { ret eu }
    lo2[branch] = old_lo
    hi2[branch] = fl
    let ed = node(a, cc, am, b, m, n, isint, lo2, hi2, best, bx)
    let _ = old_hi
    ret ed
}

// maximise cc x subject to am x <= b (m rows, n variables), x >= 0, x_j integer where isint[j]; answers (optimum, error): Malformed when there is no feasible integer point
fn lp_int(a: *mem.Arena, cc: []const f64, am: []const f64, b: []const f64, m: usize, n: usize, isint: []const bool, x: []f64) -> (f64, err) {
    let (lo, e0) = mem.alloc[f64](a, n)
    let (hi, e1) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok { ret (0.0f64, mem.Full) }
    var j = 0usize
    while j < n {
        lo[j] = 0.0f64
        hi[j] = 1.0e300f64
        j += 1usize
    }
    var best = Best { obj: 0.0f64, found: false }
    let e = node(a, cc, am, b, m, n, isint, lo, hi, &best, x)
    if e != ok { ret (0.0f64, e) }
    if !best.found { ret (0.0f64, Malformed) }
    ret (best.obj, ok)
}

// lp(direction, c, A, rel, b, int.vec) over x >= 0 with the row codes 0 (<=), 1 (>=) and 2 (=): answers (optimum, status) with lpSolve's status codes
// 0 optimal, 2 infeasible, 3 unbounded; x receives the solution
fn lp_general(a: *mem.Arena, maximise: bool, cc: []const f64, am: []const f64, rel: []const usize, b: []const f64, m: usize, n: usize, isint: []const bool, x: []f64) -> (f64, usize) {
    var rows = m
    var i = 0usize
    while i < m {
        if rel[i] == 2usize { rows += 1usize }
        i += 1usize
    }
    let (a2, e0) = mem.alloc[f64](a, rows * n)
    let (b2, e1) = mem.alloc[f64](a, rows)
    let (c2, e2) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret (0.0f64, 9usize) }
    var j = 0usize
    while j < n {
        c2[j] = cc[j]
        if !maximise { c2[j] = 0.0f64 - cc[j] }
        j += 1usize
    }
    var r = 0usize
    i = 0usize
    while i < m {
        var pass = 0usize
        while pass < 2usize {
            var sg = 1.0f64
            if rel[i] == 1usize { sg = 0.0f64 - 1.0f64 }
            if rel[i] == 2usize && pass == 1usize { sg = 0.0f64 - 1.0f64 }
            j = 0usize
            while j < n {
                a2[r * n + j] = sg * am[i * n + j]
                j += 1usize
            }
            b2[r] = sg * b[i]
            r += 1usize
            pass += 1usize
            if rel[i] != 2usize { pass = 2usize }
        }
        i += 1usize
    }
    let (tab, e3) = mem.alloc[f64](a, (rows + 2usize) * (n + rows + 2usize))
    let (bas, e4) = mem.alloc[usize](a, rows)
    if e3 != ok || e4 != ok { ret (0.0f64, 9usize) }
    let (v, es) = opt.simplex(c2, a2, b2, rows, n, x, tab, bas)
    if es == opt.Infeasible { ret (0.0f64, 2usize) }
    if es == opt.Unbounded { ret (0.0f64, 3usize) }
    if es != ok { ret (0.0f64, 9usize) }
    var any_int = false
    j = 0usize
    while j < n {
        if isint[j] { any_int = true }
        j += 1usize
    }
    var obj = v
    if any_int {
        let (vi, ei) = lp_int(a, c2, a2, b2, rows, n, isint, x)
        if ei != ok { ret (0.0f64, 2usize) }
        obj = vi
    }
    if maximise { ret (obj, 0usize) }
    ret (0.0f64 - obj, 0usize)
}

// lp.transport(cost.mat, direction, row.signs, row.rhs, col.signs, col.rhs): the transportation problem over m supply rows and n demand columns, every shipment x_ij >= 0;
// a sign is 0 for <=, 1 for >=, 2 for =. Solved as a linear program with the simplex (an equality is a <= row and a negated >= row). Answers the optimal cost (the maximum
// when maximise); the shipments go to x (m by n, row-major). Infeasible problems answer an error.
fn transport(a: *mem.Arena, cost: []const f64, m: usize, n: usize, maximise: bool, rsign: []const usize, rrhs: []const f64, csign: []const usize, crhs: []const f64, x: []f64) -> (f64, err) {
    let nv = m * n
    var rows = 0usize
    var i = 0usize
    while i < m {
        rows += 1usize
        if rsign[i] == 2usize { rows += 1usize }
        i += 1usize
    }
    var j = 0usize
    while j < n {
        rows += 1usize
        if csign[j] == 2usize { rows += 1usize }
        j += 1usize
    }
    let (am, e0) = mem.alloc[f64](a, rows * nv)
    let (b, e1) = mem.alloc[f64](a, rows)
    let (cc, e2) = mem.alloc[f64](a, nv)
    if e0 != ok || e1 != ok || e2 != ok { ret (0.0f64, mem.Full) }
    var k = 0usize
    while k < rows * nv {
        am[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < nv {
        cc[k] = cost[k]
        if !maximise { cc[k] = 0.0f64 - cost[k] }
        k += 1usize
    }
    var r = 0usize
    i = 0usize
    while i < m {
        var pass = 0usize
        let eq = rsign[i] == 2usize
        while pass < 2usize {
            var sg = 1.0f64
            if rsign[i] == 1usize { sg = 0.0f64 - 1.0f64 }
            if eq && pass == 1usize { sg = 0.0f64 - 1.0f64 }
            var q = 0usize
            while q < n {
                am[r * nv + i * n + q] = sg
                q += 1usize
            }
            b[r] = sg * rrhs[i]
            r += 1usize
            pass += 1usize
            if !eq { pass = 2usize }
        }
        i += 1usize
    }
    j = 0usize
    while j < n {
        var pass = 0usize
        let eq = csign[j] == 2usize
        while pass < 2usize {
            var sg = 1.0f64
            if csign[j] == 1usize { sg = 0.0f64 - 1.0f64 }
            if eq && pass == 1usize { sg = 0.0f64 - 1.0f64 }
            var q = 0usize
            while q < m {
                am[r * nv + q * n + j] = sg
                q += 1usize
            }
            b[r] = sg * crhs[j]
            r += 1usize
            pass += 1usize
            if !eq { pass = 2usize }
        }
        j += 1usize
    }
    let (tab, e3) = mem.alloc[f64](a, (rows + 2usize) * (nv + rows + 2usize))
    let (bas, e4) = mem.alloc[usize](a, rows)
    if e3 != ok || e4 != ok { ret (0.0f64, mem.Full) }
    let (v, es) = opt.simplex(cc, am, b, rows, nv, x, tab, bas)
    if es != ok { ret (0.0f64, es) }
    if maximise { ret (v, ok) }
    ret (0.0f64 - v, ok)
}

// lp(direction, c, A, dir, b, compute.sens = 1) over x >= 0 with the row codes 0 (<=), 1 (>=) and 2 (=): the sensitivity output of lpSolve from the optimal basis of the maximisation form (min is c -> -c,
// a >= row is negated; an equality row keeps a slack that never enters the basis). The basis is read off the optimum: the positive variables and the positive slacks, padded with zero
// columns in index order when the program is degenerate. duals receive the m constraint prices then the n reduced costs; dfrom / dto the right-hand-side ranges (+-1e30 where lpSolve reports none),
// the variable entries ranging the variable's value; cfrom / cto the objective coefficient ranges. The answer is the optimum value.
fn lp_sens(a: *mem.Arena, c: []const f64, am: []const f64, b: []const f64, rel: []const usize, m: usize, n: usize, maximise: bool, x: []f64, duals: []f64, dfrom: []f64, dto: []f64, cfrom: []f64, cto: []f64) -> (f64, err) {
    let (isint, e7) = mem.alloc[bool](a, n)
    let (fx, e8) = mem.alloc[bool](a, n)
    if e7 != ok || e8 != ok { ret (0.0f64, mem.Full) }
    var j = 0usize
    while j < n {
        isint[j] = false
        fx[j] = false
        j += 1usize
    }
    let (lv, st) = lp_general(a, maximise, c, am, rel, b, m, n, isint, x)
    let _ = lv
    if st != 0usize { ret (0.0f64, Malformed) }
    let (ov, oe) = lp_sens_at(a, c, am, b, rel, m, n, maximise, x, fx, duals, dfrom, dto, cfrom, cto)
    ret (ov, oe)
}

// The same at a given point x: the columns flagged in fx are nonbasic wherever x puts them (an integer variable held at a bound by branching), the basic values come from b less what those columns carry.
fn lp_sens_at(a: *mem.Arena, c: []const f64, am: []const f64, b: []const f64, rel: []const usize, m: usize, n: usize, maximise: bool, x: []f64, fx: []const bool, duals: []f64, dfrom: []f64, dto: []f64, cfrom: []f64, cto: []f64) -> (f64, err) {
    let big = 1.0e30f64
    var sc = 1.0f64
    if !maximise { sc = 0.0f64 - 1.0f64 }
    let width = n + m + 2usize
    let (c2, e0) = mem.alloc[f64](a, n + m)
    let (tab, e3) = mem.alloc[f64](a, (m + 2usize) * width)
    let (basis, e4) = mem.alloc[usize](a, m)
    let (sg, e5) = mem.alloc[f64](a, m)
    let (inb, e8) = mem.alloc[bool](a, n + m)
    let (rowdone, e9) = mem.alloc[bool](a, m)
    if e0 != ok || e3 != ok || e4 != ok || e5 != ok || e8 != ok || e9 != ok { ret (0.0f64, mem.Full) }
    var j = 0usize
    while j < n + m {
        c2[j] = 0.0f64
        inb[j] = false
        j += 1usize
    }
    j = 0usize
    while j < n {
        c2[j] = sc * c[j]
        j += 1usize
    }
    // the tableau [A2 | I | b2] with A2 and b2 the rows in the maximisation form (a >= row negated)
    var i = 0usize
    while i < m {
        sg[i] = 1.0f64
        if rel[i] == 1usize { sg[i] = 0.0f64 - 1.0f64 }
        rowdone[i] = false
        j = 0usize
        while j < n + m + 2usize {
            tab[i * width + j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < n {
            tab[i * width + j] = sg[i] * am[i * n + j]
            j += 1usize
        }
        tab[i * width + n + i] = 1.0f64
        var bi = b[i]
        j = 0usize
        while j < n {
            if fx[j] { bi = bi - am[i * n + j] * x[j] }
            j += 1usize
        }
        tab[i * width + width - 1usize] = sg[i] * bi
        i += 1usize
    }
    j = 0usize
    while j < n {
        if x[j] > 1.0e-9f64 && !fx[j] { inb[j] = true }
        j += 1usize
    }
    i = 0usize
    while i < m {
        if rel[i] != 2usize {
            var ax = 0.0f64
            j = 0usize
            while j < n {
                ax += am[i * n + j] * x[j]
                j += 1usize
            }
            var sl = sg[i] * (b[i] - ax)
            if sl < 0.0f64 { sl = 0.0f64 - sl }
            var ab = b[i]
            if ab < 0.0f64 { ab = 0.0f64 - ab }
            if sl > 1.0e-9f64 * (1.0f64 + ab) { inb[n + i] = true }
        }
        i += 1usize
    }
    // pivot the basis columns in, each to the unassigned row where it is largest; a degenerate program takes zero columns in index order until m are basic
    var assigned = 0usize
    var pass = 0usize
    var cq = 0usize
    while pass < 3usize {
        var ci = 0usize
        while ci < n + m && assigned < m {
            cq = ci
            if pass >= 1usize && ci >= n { cq = n + m - 1usize - (ci - n) }
            var want = inb[cq]
            if pass >= 1usize {
                want = !inb[cq]
                if cq >= n && rel[cq - n] == 2usize && pass == 1usize { want = false }
                if cq < n && pass == 2usize { want = false }
            }
            if want {
                var best = m
                var bv = 1.0e-9f64
                var r = 0usize
                while r < m {
                    if !rowdone[r] {
                        var v = tab[r * width + cq]
                        if v < 0.0f64 { v = 0.0f64 - v }
                        if v > bv {
                            bv = v
                            best = r
                        }
                    }
                    r += 1usize
                }
                if best < m {
                    let pv = tab[best * width + cq]
                    var t = 0usize
                    while t < width {
                        if t != n + m { tab[best * width + t] = tab[best * width + t] / pv }
                        t += 1usize
                    }
                    r = 0usize
                    while r < m {
                        if r != best {
                            let f = tab[r * width + cq]
                            if f != 0.0f64 {
                                t = 0usize
                                while t < width {
                                    if t != n + m { tab[r * width + t] = tab[r * width + t] - f * tab[best * width + t] }
                                    t += 1usize
                                }
                            }
                        }
                        r += 1usize
                    }
                    rowdone[best] = true
                    basis[best] = cq
                    inb[cq] = true
                    assigned += 1usize
                }
            }
            ci += 1usize
        }
        pass += 1usize
    }
    if assigned < m { ret (0.0f64, Malformed) }
    // the objective row: z_q - c_q
    cq = 0usize
    while cq < n + m {
        var z = 0.0f64
        i = 0usize
        while i < m {
            z += c2[basis[i]] * tab[i * width + cq]
            i += 1usize
        }
        tab[m * width + cq] = z - c2[cq]
        cq += 1usize
    }
    let rhs = width - 1usize
    var obj = 0.0f64
    j = 0usize
    while j < n {
        obj += c[j] * x[j]
        j += 1usize
    }
    i = 0usize
    while i < m {
        duals[i] = sc * sg[i] * tab[m * width + n + i]
        i += 1usize
    }
    j = 0usize
    while j < n {
        var z = 0.0f64
        i = 0usize
        while i < m {
            z += duals[i] * am[i * n + j]
            i += 1usize
        }
        duals[m + j] = c[j] - z
        j += 1usize
    }
    // which column is basic in which row
    let (rowof, e6) = mem.alloc[usize](a, n + m)
    if e6 != ok { ret (0.0f64, mem.Full) }
    j = 0usize
    while j < n + m {
        rowof[j] = m
        j += 1usize
    }
    i = 0usize
    while i < m {
        rowof[basis[i]] = i
        i += 1usize
    }
    // objective coefficient ranges
    j = 0usize
    while j < n {
        if rowof[j] == m {
            // nonbasic: the coefficient may move away from the optimum by its reduced cost only
            let zj = c[j] - duals[m + j]
            // held at an upper bound by branching (its reduced cost pays to raise it) the range lies on the other side
            let upb = fx[j] && x[j] > 1.0e-9f64 && ((maximise && duals[m + j] > 1.0e-12f64) || (!maximise && duals[m + j] < 0.0f64 - 1.0e-12f64))
            if maximise != upb {
                cfrom[j] = 0.0f64 - big
                cto[j] = zj
            } else {
                cfrom[j] = zj
                cto[j] = big
            }
        } else {
            let r = rowof[j]
            var lo = 0.0f64 - big
            var hi = big
            var q = 0usize
            while q < n + m {
                if rowof[q] == m && !(q >= n && rel[q - n] == 2usize) {
                    let tq = tab[r * width + q]
                    let dq = tab[m * width + q]
                    let fl = q < n && fx[q] && x[q] > 1.0e-9f64 && dq < 0.0f64 - 1.0e-12f64
                    let tp = tq > 1.0e-12f64
                    let tn = tq < 0.0f64 - 1.0e-12f64
                    if tp && fl && 0.0f64 - dq / tq < hi { hi = 0.0f64 - dq / tq }
                    if tn && fl && 0.0f64 - dq / tq > lo { lo = 0.0f64 - dq / tq }
                    if tp && !fl && 0.0f64 - dq / tq > lo { lo = 0.0f64 - dq / tq }
                    if tn && !fl && 0.0f64 - dq / tq < hi { hi = 0.0f64 - dq / tq }
                }
                q += 1usize
            }
            if sc > 0.0f64 {
                cfrom[j] = c[j] + lo
                cto[j] = c[j] + hi
                if lo <= 0.0f64 - big { cfrom[j] = 0.0f64 - big }
                if hi >= big { cto[j] = big }
            } else {
                cfrom[j] = c[j] - hi
                cto[j] = c[j] - lo
                if hi >= big { cfrom[j] = 0.0f64 - big }
                if lo <= 0.0f64 - big { cto[j] = big }
            }
        }
        j += 1usize
    }
    // right-hand-side ranges of the constraints and value ranges of the nonbasic variables
    var k = 0usize
    while k < m + n {
        dfrom[k] = 0.0f64 - big
        dto[k] = big
        let col = k
        var cl = n + k
        if k >= m { cl = k - m }
        if rowof[cl] == m {
            var lo = 0.0f64 - big
            var hi = big
            var r = 0usize
            while r < m {
                let tv = tab[r * width + cl]
                let xb = tab[r * width + rhs]
                if k < m {
                    // x_B + delta' * column >= 0
                    if tv > 1.0e-12f64 && 0.0f64 - xb / tv > lo { lo = 0.0f64 - xb / tv }
                    if tv < 0.0f64 - 1.0e-12f64 && xb / (0.0f64 - tv) < hi { hi = xb / (0.0f64 - tv) }
                } else {
                    // x_B - delta * column >= 0
                    if tv < 0.0f64 - 1.0e-12f64 && xb / tv > lo { lo = xb / tv }
                    if tv > 1.0e-12f64 && xb / tv < hi { hi = xb / tv }
                }
                r += 1usize
            }
            if k < m {
                if sg[col] > 0.0f64 {
                    if lo > 0.0f64 - big { dfrom[k] = b[k] + lo }
                    if hi < big { dto[k] = b[k] + hi }
                } else {
                    if hi < big { dfrom[k] = b[k] - hi }
                    if lo > 0.0f64 - big { dto[k] = b[k] - lo }
                }
            } else {
                if lo > 0.0f64 - big { dfrom[k] = lo + x[k - m] }
                if hi < big { dto[k] = hi + x[k - m] }
            }
        }
        k += 1usize
    }
    ret (obj, ok)
}
