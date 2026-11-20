// lpSolveAPI's model object: make.lp, set.objfn, add.constraint, set.rhs, set.constr.type, set.bounds, set.type, lp.control(sense =), solve and the get.* readers, over the simplex of
// e.math.opt and the branch and bound of lpsolvepkg. solve answers lp_solve's status codes (0 optimal, 2 infeasible, 3 unbounded). A variable with a lower bound l is shifted
// to x - l, one with only an upper bound is reflected, a free one is split in two; the model is then a maximisation with <= rows. Integer variables need integer lower bounds.

use e.algo.stat.lpsolvepkg as lp
use e.mem
use e.math.opt as opt

error Full

type Model = struct {
    n: usize,
    m: usize,
    cap: usize,
    maximise: bool,
    obj: []f64,
    a: []f64,
    rel: []usize,
    rhs: []f64,
    lo: []f64,
    hi: []f64,
    kind: []usize,
    x: []f64,
    cons: []f64,
    value: f64,
}

// make.lp(nrow, ncol): nrow empty <= rows with right-hand side 0, every variable real in [0, Inf)
fn make_lp(a: *mem.Arena, nrow: usize, ncol: usize) -> (Model, err) {
    let cap = nrow + 256usize
    let (obj, e0) = mem.alloc[f64](a, ncol)
    let (am, e1) = mem.alloc[f64](a, cap * ncol)
    let (rel, e2) = mem.alloc[usize](a, cap)
    let (rhs, e3) = mem.alloc[f64](a, cap)
    let (lo, e4) = mem.alloc[f64](a, ncol)
    let (hi, e5) = mem.alloc[f64](a, ncol)
    let (kind, e6) = mem.alloc[usize](a, ncol)
    let (x, e7) = mem.alloc[f64](a, ncol)
    let (cons, e8) = mem.alloc[f64](a, cap)
    var md = Model { n: ncol, m: nrow, cap: cap, maximise: false, obj: obj, a: am, rel: rel, rhs: rhs, lo: lo, hi: hi, kind: kind, x: x, cons: cons, value: 0.0f64 }
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (md, Full) }
    var i = 0usize
    while i < cap * ncol {
        am[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < cap {
        rel[i] = 0usize
        rhs[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ncol {
        obj[i] = 0.0f64
        lo[i] = 0.0f64
        hi[i] = 1.0e30f64
        kind[i] = 0usize
        i += 1usize
    }
    ret (md, ok)
}

// set.objfn(lprec, obj)
fn set_objfn(md: *Model, c: []const f64) {
    var j = 0usize
    while j < md.n {
        md.obj[j] = c[j]
        j += 1usize
    }
}

// lp.control(lprec, sense = "max") when maximise, "min" otherwise
fn set_sense(md: *Model, maximise: bool) { md.maximise = maximise }

// add.constraint(lprec, xt, type, rhs): rel is 0 for <=, 1 for >=, 2 for =; answers the new row's index (1-based, as R)
fn add_constraint(md: *Model, row: []const f64, rel: usize, rhs: f64) -> usize {
    let i = md.m
    var j = 0usize
    while j < md.n {
        md.a[i * md.n + j] = row[j]
        j += 1usize
    }
    md.rel[i] = rel
    md.rhs[i] = rhs
    md.m += 1usize
    ret md.m
}

// set.rhs(lprec, rhs, constraints = row), 1-based
fn set_rhs(md: *Model, row: usize, rhs: f64) { md.rhs[row - 1usize] = rhs }

// set.constr.type(lprec, type, constraints = row), 1-based
fn set_constr_type(md: *Model, row: usize, rel: usize) { md.rel[row - 1usize] = rel }

// set.row(lprec, row, xt), 1-based
fn set_row(md: *Model, row: usize, xt: []const f64) {
    var j = 0usize
    while j < md.n {
        md.a[(row - 1usize) * md.n + j] = xt[j]
        j += 1usize
    }
}

// set.bounds(lprec, lower, upper, columns = col), 1-based; 1e30 and -1e30 stand for Inf and -Inf
fn set_bounds(md: *Model, col: usize, lower: f64, upper: f64) {
    md.lo[col - 1usize] = lower
    md.hi[col - 1usize] = upper
}

// set.type(lprec, col, type): 0 real, 1 integer, 2 binary (integer in [0, 1])
fn set_type(md: *Model, col: usize, kind: usize) {
    md.kind[col - 1usize] = kind
    if kind == 2usize {
        md.lo[col - 1usize] = 0.0f64
        md.hi[col - 1usize] = 1.0f64
    }
}

// solve(lprec): 0 optimal, 2 infeasible, 3 unbounded, 1 when memory runs out
fn solve(a: *mem.Arena, md: *Model) -> usize {
    let n = md.n
    let m = md.m
    let big = 1.0e29f64
    // column map: y[p[j]] with sign s[j] and offset o[j], plus y[q[j]] with the opposite sign for a free variable
    let (p, e0) = mem.alloc[usize](a, n)
    let (q, e1) = mem.alloc[usize](a, n)
    let (sg, e2) = mem.alloc[f64](a, n)
    let (off, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret 1usize }
    var nv = 0usize
    var nub = 0usize
    var j = 0usize
    while j < n {
        q[j] = n * 4usize + 8usize
        p[j] = nv
        nv += 1usize
        if md.lo[j] > 0.0f64 - big {
            sg[j] = 1.0f64
            off[j] = md.lo[j]
            if md.hi[j] < big { nub += 1usize }
        } else {
            if md.hi[j] < big {
                sg[j] = 0.0f64 - 1.0f64
                off[j] = md.hi[j]
            } else {
                sg[j] = 1.0f64
                off[j] = 0.0f64
                q[j] = nv
                nv += 1usize
            }
        }
        j += 1usize
    }
    var rows = nub
    var i = 0usize
    while i < m {
        rows += 1usize
        if md.rel[i] == 2usize { rows += 1usize }
        i += 1usize
    }
    let (am, e4) = mem.alloc[f64](a, rows * nv)
    let (b, e5) = mem.alloc[f64](a, rows)
    let (cc, e6) = mem.alloc[f64](a, nv)
    let (isint, e7) = mem.alloc[bool](a, nv)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret 1usize }
    i = 0usize
    while i < rows * nv {
        am[i] = 0.0f64
        i += 1usize
    }
    var sc = 1.0f64
    if !md.maximise { sc = 0.0f64 - 1.0f64 }
    j = 0usize
    while j < nv {
        cc[j] = 0.0f64
        isint[j] = false
        j += 1usize
    }
    j = 0usize
    while j < n {
        cc[p[j]] = sc * sg[j] * md.obj[j]
        if q[j] < nv { cc[q[j]] = 0.0f64 - sc * md.obj[j] }
        if md.kind[j] != 0usize {
            isint[p[j]] = true
            if q[j] < nv { isint[q[j]] = true }
        }
        j += 1usize
    }
    var r = 0usize
    i = 0usize
    while i < m {
        var shift = 0.0f64
        j = 0usize
        while j < n {
            shift += md.a[i * n + j] * off[j]
            j += 1usize
        }
        var pass = 0usize
        let eq = md.rel[i] == 2usize
        while pass < 2usize {
            var s = 1.0f64
            if md.rel[i] == 1usize { s = 0.0f64 - 1.0f64 }
            if eq && pass == 1usize { s = 0.0f64 - 1.0f64 }
            j = 0usize
            while j < n {
                am[r * nv + p[j]] = s * sg[j] * md.a[i * n + j]
                if q[j] < nv { am[r * nv + q[j]] = 0.0f64 - s * md.a[i * n + j] }
                j += 1usize
            }
            b[r] = s * (md.rhs[i] - shift)
            r += 1usize
            pass += 1usize
            if !eq { pass = 2usize }
        }
        i += 1usize
    }
    j = 0usize
    while j < n {
        if md.lo[j] > 0.0f64 - big && md.hi[j] < big {
            am[r * nv + p[j]] = 1.0f64
            b[r] = md.hi[j] - md.lo[j]
            r += 1usize
        }
        j += 1usize
    }
    let (y, e8) = mem.alloc[f64](a, nv)
    let (tab, e9) = mem.alloc[f64](a, (rows + 2usize) * (nv + rows + 2usize))
    let (bas, e10) = mem.alloc[usize](a, rows)
    if e8 != ok || e9 != ok || e10 != ok { ret 1usize }
    let (v, es) = opt.simplex(cc, am, b, rows, nv, y, tab, bas)
    if es == opt.Infeasible { ret 2usize }
    if es == opt.Unbounded { ret 3usize }
    if es != ok { ret 1usize }
    var anyint = false
    j = 0usize
    while j < nv {
        if isint[j] { anyint = true }
        j += 1usize
    }
    if anyint {
        let (vi, ei) = lp.lp_int(a, cc, am, b, rows, nv, isint, y)
        if ei != ok { ret 2usize }
        let _ = vi
    }
    let _ = v
    var z = 0.0f64
    j = 0usize
    while j < n {
        var xv = off[j] + sg[j] * y[p[j]]
        if q[j] < nv { xv = xv - y[q[j]] }
        md.x[j] = xv
        z += md.obj[j] * xv
        j += 1usize
    }
    md.value = z
    i = 0usize
    while i < m {
        var s = 0.0f64
        j = 0usize
        while j < n {
            s += md.a[i * n + j] * md.x[j]
            j += 1usize
        }
        md.cons[i] = s
        i += 1usize
    }
    ret 0usize
}

// get.objective, get.variables and get.constraints after a solve
fn get_objective(md: *const Model) -> f64 { ret md.value }
fn get_variable(md: *const Model, j: usize) -> f64 { ret md.x[j - 1usize] }
fn get_constraint(md: *const Model, i: usize) -> f64 { ret md.cons[i - 1usize] }

// get.mat(lprec, row, col), 1-based; row 0 is the objective
fn get_mat(md: *const Model, row: usize, col: usize) -> f64 {
    if row == 0usize { ret md.obj[col - 1usize] }
    ret md.a[(row - 1usize) * md.n + col - 1usize]
}

// set.mat(lprec, row, col, value), 1-based; row 0 is the objective
fn set_mat(md: *Model, row: usize, col: usize, v: f64) {
    if row == 0usize {
        md.obj[col - 1usize] = v
        ret
    }
    md.a[(row - 1usize) * md.n + col - 1usize] = v
}

// get.rhs(lprec): the right-hand side of row, 1-based
fn get_rhs(md: *const Model, row: usize) -> f64 { ret md.rhs[row - 1usize] }

// get.constr.type(lprec, row) as a code: 0 <=, 1 >=, 2 =
fn get_constr_type(md: *const Model, row: usize) -> usize { ret md.rel[row - 1usize] }

// get.type(lprec, col): 0 real, 1 integer, 2 binary
fn get_type(md: *const Model, col: usize) -> usize { ret md.kind[col - 1usize] }

// get.bounds(lprec, columns = col): lower and upper, 1e30 standing for Inf
fn get_lower(md: *const Model, col: usize) -> f64 { ret md.lo[col - 1usize] }
fn get_upper(md: *const Model, col: usize) -> f64 { ret md.hi[col - 1usize] }

// set.column(lprec, col, x, indices = 1..m): replaces the whole column, so the objective coefficient becomes 0 (as lpSolveAPI does)
fn set_column(md: *Model, col: usize, xt: []const f64) {
    md.obj[col - 1usize] = 0.0f64
    var i = 0usize
    while i < md.m {
        md.a[i * md.n + col - 1usize] = xt[i]
        i += 1usize
    }
}

// delete.constraint(lprec, row), 1-based: the rows below move up
fn delete_constraint(md: *Model, row: usize) {
    var i = row - 1usize
    while i + 1usize < md.m {
        var j = 0usize
        while j < md.n {
            md.a[i * md.n + j] = md.a[(i + 1usize) * md.n + j]
            j += 1usize
        }
        md.rel[i] = md.rel[i + 1usize]
        md.rhs[i] = md.rhs[i + 1usize]
        i += 1usize
    }
    md.m -= 1usize
}

// delete.column(lprec, col), 1-based: the columns to the right move left and the row stride shrinks
fn delete_column(md: *Model, col: usize) {
    let n = md.n
    let c0 = col - 1usize
    var i = 0usize
    while i < md.cap {
        var k = 0usize
        var j = 0usize
        while j < n {
            if j != c0 {
                md.a[i * (n - 1usize) + k] = md.a[i * n + j]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    var j = c0
    while j + 1usize < n {
        md.obj[j] = md.obj[j + 1usize]
        md.lo[j] = md.lo[j + 1usize]
        md.hi[j] = md.hi[j + 1usize]
        md.kind[j] = md.kind[j + 1usize]
        j += 1usize
    }
    md.n = n - 1usize
}

// add.column(lprec, x, indices = 1..m): a new last column, real in [0, Inf) with objective coefficient 0
fn add_column(a: *mem.Arena, md: *Model, xt: []const f64) -> err {
    let n = md.n
    let (am, e0) = mem.alloc[f64](a, md.cap * (n + 1usize))
    let (obj, e1) = mem.alloc[f64](a, n + 1usize)
    let (lo, e2) = mem.alloc[f64](a, n + 1usize)
    let (hi, e3) = mem.alloc[f64](a, n + 1usize)
    let (kind, e4) = mem.alloc[usize](a, n + 1usize)
    let (x, e5) = mem.alloc[f64](a, n + 1usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret Full }
    var i = 0usize
    while i < md.cap {
        var j = 0usize
        while j < n {
            am[i * (n + 1usize) + j] = md.a[i * n + j]
            j += 1usize
        }
        am[i * (n + 1usize) + n] = 0.0f64
        if i < md.m { am[i * (n + 1usize) + n] = xt[i] }
        i += 1usize
    }
    var j = 0usize
    while j < n {
        obj[j] = md.obj[j]
        lo[j] = md.lo[j]
        hi[j] = md.hi[j]
        kind[j] = md.kind[j]
        j += 1usize
    }
    obj[n] = 0.0f64
    lo[n] = 0.0f64
    hi[n] = 1.0e30f64
    kind[n] = 0usize
    md.a = am
    md.obj = obj
    md.lo = lo
    md.hi = hi
    md.kind = kind
    md.x = x
    md.n = n + 1usize
    ret ok
}

// get.sensitivity.rhs (duals, dualsfrom, dualstill: m rows then n variables) and get.sensitivity.obj (objfrom, objtill: n) of a model of real variables in [0, Inf); get.dual.solution is 1
// then duals and get.primal.solution(orig = TRUE) is the m row values then x. Models with bounds or integer columns answer an error.
fn sensitivity(a: *mem.Arena, md: *const Model, x: []f64, duals: []f64, dfrom: []f64, dto: []f64, cfrom: []f64, cto: []f64) -> err {
    var j = 0usize
    while j < md.n {
        if md.lo[j] != 0.0f64 || md.hi[j] < 1.0e29f64 || md.kind[j] != 0usize { ret lp.Malformed }
        j += 1usize
    }
    let (v, e) = lp.lp_sens(a, md.obj, md.a, md.rhs, md.rel, md.m, md.n, md.maximise, x, duals, dfrom, dto, cfrom, cto)
    let _ = v
    ret e
}
