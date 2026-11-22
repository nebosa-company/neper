// R kernlab ksvm: the bound-constrained and multi-class solvers of kernlab's svm.cpp, which come from BSVM. Solver_B with its working sets of
// ten variables and TRON on the subproblems (kernlabtron) for C-bsvc and eps-bsvr, Solver_B_linear for C-bsvc with vanilladot, Solver_MB for
// kbb-svc, and Solver_SPOC for spoc-svc. The kernel matrix is held as 32-bit floats the way the Q classes build it: BSVC_Q holds
// float(y_i y_j (K + 1)), BSVR_Q and BONE_CLASS_Q float(float(K) + 1), ONE_CLASS_Q float(K). Data are row-major, n by nf, in the order ksvm hands
// them to the solver.
//
// Not here: eps-bsvr with vanilladot (kernlab's linear branch overruns its alpha buffer), class weights on the multi-class solvers, the sparse
// and kernel-matrix input paths.

use e.algo.stat.kernlabsvm as ks
use e.algo.stat.kernlabtron as tr
use e.math
use e.mem

error Fail

type B = struct { mode: usize, l: usize, m: usize, nf: usize, nr: usize, x: []const f64, xi: []usize, base: []const f32, y: []i64, yy: []i64, ri: []usize, g: []f64, gbar: []f64, alpha: []f64, b: []f64, st: []u8, act: []usize, c: []f64, cp: f64, cn: f64, lin: f64, eps: f64, shrinking: bool, unshrunk: bool, active: usize, ws: []usize, ows: []usize, pm: []f64, ps: []usize, nq: usize, qs: usize, start1: []usize, start2: []usize, w: []f64, qx: []f64, qc: []f64, qq: []f64, qpp: []f64 }

fn imin(a: usize, b: usize) -> usize {
    if a < b { ret a }
    ret b
}

fn swapf(v: []f64, i: usize, j: usize) {
    let t = v[i]
    v[i] = v[j]
    v[j] = t
}

fn swapi(v: []i64, i: usize, j: usize) {
    let t = v[i]
    v[i] = v[j]
    v[j] = t
}

fn swapu(v: []usize, i: usize, j: usize) {
    let t = v[i]
    v[i] = v[j]
    v[j] = t
}

fn swapb(v: []u8, i: usize, j: usize) {
    let t = v[i]
    v[i] = v[j]
    v[j] = t
}

fn get_c(s: *const B, i: usize) -> f64 {
    if s.mode == 3usize { ret s.c[usize(s.y[i])] }
    if s.y[i] > 0i64 { ret s.cp }
    ret s.cn
}

// 0 lower, 1 upper, 2 free
fn update_status(s: *B, i: usize) {
    if s.alpha[i] >= get_c(s, i) {
        s.st[i] = 1u8
    } else {
        if s.alpha[i] <= 0.0f64 {
            s.st[i] = 0u8
        } else {
            s.st[i] = 2u8
        }
    }
}

// Q(i, j) of the plain solvers at the current positions
fn qv(s: *const B, i: usize, j: usize) -> f64 {
    ret f64(s.y[i]) * f64(s.y[j]) * f64(s.base[(s.act[i] % s.m) * s.m + s.act[j] % s.m])
}

fn f3(s: *const B, r: usize, c: usize) -> f64 {
    ret f64(s.base[r * s.m + c])
}

// the sparse dot of the linear solver: the dense sum over the features of rows i and j in order
fn dotp(s: *const B, i: usize, j: usize) -> f64 {
    var sum = 0.0f64
    var k = 0usize
    while k < s.nf {
        sum += s.x[s.xi[i] * s.nf + k] * s.x[s.xi[j] * s.nf + k]
        k += 1usize
    }
    ret sum
}

fn wdot(s: *const B, i: usize) -> f64 {
    var sum = 0.0f64
    var k = 0usize
    while k < s.nf {
        sum += s.w[k] * s.x[s.xi[i] * s.nf + k]
        k += 1usize
    }
    sum += s.w[0usize]
    ret sum
}

fn swap_index(s: *B, i: usize, j: usize) {
    if s.mode == 3usize {
        if i == j { ret }
        swapi(s.y, i, j)
        swapi(s.yy, i, j)
        swapf(s.g, i, j)
        swapb(s.st, i, j)
        swapf(s.alpha, i, j)
        swapu(s.act, i, j)
        swapu(s.ri, i, j)
        swapf(s.gbar, i, j)
        ret
    }
    swapi(s.y, i, j)
    swapf(s.g, i, j)
    swapb(s.st, i, j)
    swapf(s.alpha, i, j)
    swapf(s.b, i, j)
    swapu(s.act, i, j)
    if s.mode == 2usize {
        swapu(s.xi, i, j)
    } else {
        swapf(s.gbar, i, j)
    }
}

// target[start[idx] .. start[idx + 1]) += coef * Q(row, real_i[j])
fn rng(s: *B, tgt: []f64, st: []const usize, idx: usize, coef: f64, row: usize) {
    var j = st[idx]
    let ub = st[idx + 1usize]
    while j < ub {
        tgt[j] = tgt[j] + coef * f3(s, row, s.ri[j])
        j += 1usize
    }
}

// the six ranges of Solver_MB: (yy, y) + t, (y, yy) - t, and for every other class k (k, y) + d, (yy, k) + d, (y, k) - d, (k, yy) - d, all times sign
fn mb_apply(s: *B, tgt: []f64, st: []const usize, y_: usize, yy_: usize, row: usize, t: f64, d: f64, sign: f64) {
    let nr = s.nr
    rng(s, tgt, st, yy_ * nr + y_, sign * t, row)
    rng(s, tgt, st, y_ * nr + yy_, 0.0f64 - sign * t, row)
    var k = 0usize
    while k < nr {
        if k != y_ && k != yy_ {
            rng(s, tgt, st, k * nr + y_, sign * d, row)
            rng(s, tgt, st, yy_ * nr + k, sign * d, row)
            rng(s, tgt, st, y_ * nr + k, 0.0f64 - sign * d, row)
            rng(s, tgt, st, k * nr + yy_, 0.0f64 - sign * d, row)
        }
        k += 1usize
    }
}

fn reconstruct_gradient(s: *B) {
    if s.mode == 2usize {
        var i = s.active
        while i < s.l {
            s.g[i] = f64(s.y[i]) * wdot(s, i) + s.b[i]
            i += 1usize
        }
        ret
    }
    if s.active == s.l { ret }
    if s.mode == 3usize {
        var i = s.active
        while i < s.l {
            s.g[i] = s.gbar[i] + s.lin
            i += 1usize
        }
        i = 0usize
        while i < s.active {
            if s.st[i] == 2u8 {
                let ai = s.alpha[i]
                mb_apply(s, s.g, s.start2, usize(s.y[i]), usize(s.yy[i]), s.ri[i], 2.0f64 * ai, ai, 1.0f64)
            }
            i += 1usize
        }
        ret
    }
    var i = s.active
    while i < s.l {
        s.g[i] = s.gbar[i] + s.b[i]
        i += 1usize
    }
    i = 0usize
    while i < s.active {
        if s.st[i] == 2u8 {
            let ai = s.alpha[i]
            var j = s.active
            while j < s.l {
                s.g[j] += ai * qv(s, i, j)
                j += 1usize
            }
        }
        i += 1usize
    }
}

// the maximal violation; the working set is left in ws, its size in nq
fn select_ws(s: *B) -> f64 {
    let inf = ks.inf()
    var q2 = s.qs / 2usize
    var maxvio = 0.0f64
    var i = 0usize
    s.nq = 0usize
    while i < q2 {
        s.pm[i] = inf
        i += 1usize
    }
    i = 0usize
    while i < s.active {
        if s.st[i] == 2u8 {
            let v = math.abs[f64](s.g[i])
            if v < s.pm[0usize] {
                var j = 1usize
                while j < q2 {
                    if v >= s.pm[j] { break }
                    s.pm[j - 1usize] = s.pm[j]
                    s.ps[j - 1usize] = s.ps[j]
                    j += 1usize
                }
                s.pm[j - 1usize] = v
                s.ps[j - 1usize] = i
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < q2 {
        if s.pm[i] != inf {
            s.ws[s.nq] = s.ps[i]
            s.nq += 1usize
        }
        i += 1usize
    }
    var max0 = 0.0f64
    if s.nq > 0usize { max0 = s.pm[0usize] }
    q2 = s.qs - s.nq
    i = 0usize
    while i < q2 {
        s.pm[i] = 0.0f64 - inf
        i += 1usize
    }
    i = 0usize
    while i < s.active {
        let v = math.abs[f64](s.g[i])
        var skip = false
        if s.st[i] == 2u8 && v <= max0 { skip = true }
        if !skip {
            if s.st[i] == 1u8 {
                if s.g[i] < 0.0f64 { skip = true }
            } else {
                if s.st[i] == 0u8 {
                    if s.g[i] > 0.0f64 { skip = true }
                }
            }
        }
        if !skip && v > s.pm[0usize] {
            var j = 1usize
            while j < q2 {
                if v <= s.pm[j] { break }
                s.pm[j - 1usize] = s.pm[j]
                s.ps[j - 1usize] = s.ps[j]
                j += 1usize
            }
            s.pm[j - 1usize] = v
            s.ps[j - 1usize] = i
        }
        i += 1usize
    }
    i = 0usize
    while i < q2 {
        if s.pm[i] != 0.0f64 - inf {
            s.ws[s.nq] = s.ps[i]
            s.nq += 1usize
            if s.pm[i] > maxvio { maxvio = s.pm[i] }
        }
        i += 1usize
    }
    ret maxvio
}

fn shrink_one(s: *B, k: usize) {
    if s.mode != 3usize {
        swap_index(s, k, s.active)
        ret
    }
    let nr = s.nr
    let sx = usize(s.yy[k]) * nr + usize(s.y[k])
    let t = nr * nr
    var i = sx + 1usize
    while i <= t {
        s.start1[i] -= 1usize
        i += 1usize
    }
    i = 0usize
    while i <= sx {
        s.start2[i] -= 1usize
        i += 1usize
    }
    swap_index(s, k, s.start1[sx + 1usize])
    i = sx + 1usize
    while i < t {
        swap_index(s, s.start1[i], s.start1[i + 1usize])
        i += 1usize
    }
    i = 0usize
    while i < sx {
        swap_index(s, s.start2[i], s.start2[i + 1usize])
        i += 1usize
    }
}

fn unshrink_one(s: *B, k: usize) {
    if s.mode != 3usize {
        swap_index(s, k, s.active)
        ret
    }
    let nr = s.nr
    let sx = usize(s.yy[k]) * nr + usize(s.y[k])
    swap_index(s, k, s.start2[sx])
    var i = sx
    while i > 0usize {
        swap_index(s, s.start2[i], s.start2[i - 1usize])
        i -= 1usize
    }
    let t = sx + 1usize
    i = nr * nr
    while i > t {
        swap_index(s, s.start1[i], s.start1[i - 1usize])
        i -= 1usize
    }
    let tt = nr * nr
    i = sx + 1usize
    while i <= tt {
        s.start1[i] += 1usize
        i += 1usize
    }
    i = 0usize
    while i <= sx {
        s.start2[i] += 1usize
        i += 1usize
    }
}

fn do_shrinking(s: *B) {
    let gm = select_ws(s)
    if gm < s.eps { ret }
    var k = 0usize
    while k < s.active {
        var go = true
        if s.st[k] == 0u8 {
            if s.g[k] <= gm { go = false }
        } else {
            if s.st[k] == 1u8 {
                if s.g[k] >= 0.0f64 - gm { go = false }
            } else {
                go = false
            }
        }
        if go {
            s.active -= 1usize
            shrink_one(s, k)
        } else {
            k += 1usize
        }
    }
    if s.unshrunk || gm > s.eps * 10.0f64 { ret }
    s.unshrunk = true
    reconstruct_gradient(s)
    var kk = s.l
    while kk > s.active {
        let k2 = kk - 1usize
        var go = true
        if s.st[k2] == 0u8 {
            if s.g[k2] > gm { go = false }
        } else {
            if s.st[k2] == 1u8 {
                if s.g[k2] < 0.0f64 - gm { go = false }
            } else {
                go = false
            }
        }
        if go {
            unshrink_one(s, k2)
            s.active += 1usize
        } else {
            kk -= 1usize
        }
    }
}

fn yyy(yi: i64, yyi: i64, yj: i64, yyj: i64) -> f64 {
    var xx = 0i64
    if yi == yj { xx += 1i64 }
    if yyi == yyj { xx += 1i64 }
    if yi == yyj { xx -= 1i64 }
    if yj == yyi { xx -= 1i64 }
    ret f64(xx)
}

fn initial_index_table(s: *B, count: []const usize) {
    let nr = s.nr
    var p = 0usize
    var i = 0usize
    while i < nr {
        var q = 0usize
        var j = 0usize
        while j < nr {
            s.start1[i * nr + j] = p
            s.start2[i * nr + j] = s.l
            if i != j {
                var k = 0usize
                while k < count[j] {
                    s.yy[p] = i64(i)
                    s.ri[p] = q
                    s.act[p] = p
                    p += 1usize
                    q += 1usize
                    k += 1usize
                }
            } else {
                q += count[j]
            }
            j += 1usize
        }
        i += 1usize
    }
    s.start1[nr * nr] = s.l
    s.start2[nr * nr] = s.l
}

fn juggle(s: *B, a: *mem.Arena) -> err {
    let l = s.l
    let (t1, e1) = mem.alloc[i64](a, l)
    let (t2, e2) = mem.alloc[u8](a, l)
    let (t3, e3) = mem.alloc[f64](a, l)
    if e1 != ok || e2 != ok || e3 != ok { ret Fail }
    var i = 0usize
    while i < l {
        t1[i] = s.y[i]
        i += 1usize
    }
    i = 0usize
    while i < l {
        s.y[s.act[i]] = t1[i]
        i += 1usize
    }
    i = 0usize
    while i < l {
        t2[i] = s.st[i]
        i += 1usize
    }
    i = 0usize
    while i < l {
        s.st[s.act[i]] = t2[i]
        i += 1usize
    }
    i = 0usize
    while i < l {
        t3[i] = s.alpha[i]
        i += 1usize
    }
    i = 0usize
    while i < l {
        s.alpha[s.act[i]] = t3[i]
        i += 1usize
    }
    i = 0usize
    while i < l {
        t3[i] = s.g[i]
        i += 1usize
    }
    i = 0usize
    while i < l {
        s.g[s.act[i]] = t3[i]
        i += 1usize
    }
    i = 0usize
    while i < l {
        t3[i] = s.gbar[i]
        i += 1usize
    }
    i = 0usize
    while i < l {
        s.gbar[s.act[i]] = t3[i]
        i += 1usize
    }
    ret ok
}

// Solver_B::Solve, Solver_B_linear::Solve and Solver_MB::Solve; the arrays of s are set up by the caller. Answers the objective; alpha is left in
// position order (the caller maps it back through act).
fn run(a: *mem.Arena, s: *B, tw: *tr.W, count: []const usize) -> (f64, err) {
    let l = s.l
    let qs = s.qs
    var i = 0usize
    var j = 0usize
    while i < l {
        update_status(s, i)
        s.xi[i] = i
        i += 1usize
    }
    if s.mode == 3usize {
        i = 0usize
        while i < l {
            s.act[i] = i
            i += 1usize
        }
        initial_index_table(s, count)
    } else {
        i = 0usize
        while i < l {
            s.act[i] = i
            i += 1usize
        }
    }
    s.active = l
    var gtol = s.eps / 10.0f64
    if s.mode == 2usize { gtol = s.eps / 100.0f64 }
    i = 0usize
    while i < l {
        s.gbar[i] = 0.0f64
        s.g[i] = s.b[i]
        if s.mode == 3usize { s.g[i] = s.lin }
        i += 1usize
    }
    if s.mode == 2usize {
        var allzero = true
        i = 0usize
        while i < l {
            if s.st[i] != 0u8 { allzero = false }
            i += 1usize
        }
        if !allzero {
            i = 0usize
            while i < l {
                s.g[i] += f64(s.y[i]) * wdot(s, i)
                i += 1usize
            }
        }
    }
    if s.mode == 0usize || s.mode == 1usize {
        i = 0usize
        while i < l {
            if s.st[i] != 0u8 {
                let ci = get_c(s, i)
                let ai = s.alpha[i]
                j = 0usize
                while j < l {
                    s.g[j] += ai * qv(s, i, j)
                    j += 1usize
                }
                if s.shrinking && s.st[i] == 1u8 {
                    j = 0usize
                    while j < l {
                        s.gbar[j] += ci * qv(s, i, j)
                        j += 1usize
                    }
                }
            }
            i += 1usize
        }
    }
    if s.mode == 3usize {
        i = 0usize
        while i < l {
            if s.st[i] != 0u8 {
                let ai = s.alpha[i]
                let ci = get_c(s, i)
                let y_ = usize(s.y[i])
                let yy_ = usize(s.yy[i])
                let row = s.ri[i]
                mb_apply(s, s.g, s.start1, y_, yy_, row, ai, ai, 1.0f64)
                if s.shrinking && s.st[i] == 1u8 {
                    let nr = s.nr
                    rng(s, s.gbar, s.start1, yy_ * nr + y_, ci, row)
                    rng(s, s.gbar, s.start1, y_ * nr + yy_, ci, row)
                    var k = 0usize
                    while k < nr {
                        if k != y_ && k != yy_ {
                            rng(s, s.gbar, s.start1, k * nr + y_, ci, row)
                            rng(s, s.gbar, s.start1, yy_ * nr + k, ci, row)
                            rng(s, s.gbar, s.start1, y_ * nr + k, ci, row)
                            rng(s, s.gbar, s.start1, k * nr + yy_, ci, row)
                        }
                        k += 1usize
                    }
                }
            }
            i += 1usize
        }
    }
    var iter = 0usize
    let mx = imin(l * 2usize / qs, 2000usize / qs)
    var counter = mx + 1usize
    var done = false
    while !done {
        counter -= 1usize
        if counter == 0usize {
            counter = mx
            if s.shrinking { do_shrinking(s) }
        }
        var proceed = true
        if select_ws(s) < s.eps {
            reconstruct_gradient(s)
            s.active = l
            if select_ws(s) < s.eps {
                done = true
                proceed = false
            } else {
                counter = 1usize
                if s.mode == 3usize {
                    let e = juggle(s, a)
                    if e != ok { ret (0.0f64, e) }
                    initial_index_table(s, count)
                }
            }
        }
        if proceed && s.mode >= 2usize && counter == mx {
            var same = true
            i = 0usize
            while i < qs {
                if s.ows[i] != s.ws[i] {
                    same = false
                    break
                }
                i += 1usize
            }
            if same {
                done = true
                proceed = false
            }
        }
        if proceed {
            if s.mode >= 2usize {
                i = 0usize
                while i < qs {
                    s.ows[i] = s.ws[i]
                    i += 1usize
                }
            }
            iter += 1usize
            let q = s.nq
            // subproblem
            i = 0usize
            while i < q {
                s.qpp[i] = s.g[s.ws[i]]
                i += 1usize
            }
            i = 0usize
            while i < q {
                let bi = s.ws[i]
                s.qx[i] = s.alpha[bi]
                s.qc[i] = get_c(s, bi)
                if s.mode == 0usize || s.mode == 1usize {
                    s.qq[i * q + i] = qv(s, bi, bi)
                } else {
                    if s.mode == 2usize {
                        s.qq[i * q + i] = dotp(s, bi, bi) + 1.0f64
                    } else {
                        s.qq[i * q + i] = yyy(s.y[bi], s.yy[bi], s.y[bi], s.yy[bi]) * f3(s, s.ri[bi], s.ri[bi])
                    }
                }
                s.qpp[i] -= s.qq[i * q + i] * s.alpha[bi]
                j = i + 1usize
                while j < q {
                    let bj = s.ws[j]
                    var v = 0.0f64
                    if s.mode == 0usize || s.mode == 1usize {
                        v = qv(s, bi, bj)
                    } else {
                        if s.mode == 2usize {
                            v = f64(s.y[bi]) * f64(s.y[bj]) * (dotp(s, bi, bj) + 1.0f64)
                        } else {
                            v = yyy(s.y[bi], s.yy[bi], s.y[bj], s.yy[bj]) * f3(s, s.ri[bi], s.ri[bj])
                        }
                    }
                    s.qq[i * q + j] = v
                    s.qq[j * q + i] = v
                    s.qpp[i] -= s.qq[i * q + j] * s.alpha[bj]
                    s.qpp[j] -= s.qq[j * q + i] * s.alpha[bi]
                    j += 1usize
                }
                i += 1usize
            }
            tr.solvebqp(tw, q, s.qq, s.qpp, s.qx, s.qc, gtol)
            // update G
            if s.mode == 2usize {
                i = 0usize
                while i < q {
                    let bi = s.ws[i]
                    let d = s.qx[i] - s.alpha[bi]
                    if math.abs[f64](d) > 1e-12f64 {
                        s.alpha[bi] = s.qx[i]
                        update_status(s, bi)
                        let ya = f64(s.y[bi]) * d
                        var k = 0usize
                        while k < s.nf {
                            s.w[k] += ya * s.x[s.xi[bi] * s.nf + k]
                            k += 1usize
                        }
                        s.w[0usize] += ya
                    }
                    i += 1usize
                }
                j = 0usize
                while j < s.active {
                    s.g[j] = f64(s.y[j]) * wdot(s, j) + s.b[j]
                    j += 1usize
                }
            } else {
                // rows are read before any position changes: the plain Q is symmetric in the positions, the multi-class rows are by real index
                i = 0usize
                while i < q {
                    let bi = s.ws[i]
                    let d = s.qx[i] - s.alpha[bi]
                    if math.abs[f64](d) > 1e-12f64 {
                        s.alpha[bi] = s.qx[i]
                        if s.mode == 3usize {
                            mb_apply(s, s.g, s.start1, usize(s.y[bi]), usize(s.yy[bi]), s.ri[bi], 2.0f64 * d, d, 1.0f64)
                        } else {
                            j = 0usize
                            while j < s.active {
                                s.g[j] += d * qv(s, bi, j)
                                j += 1usize
                            }
                        }
                    }
                    i += 1usize
                }
                i = 0usize
                while i < q {
                    let bi = s.ws[i]
                    let u = s.st[bi] == 1u8
                    update_status(s, bi)
                    if s.shrinking && u != (s.st[bi] == 1u8) {
                        let ci = s.qc[i]
                        if s.mode == 3usize {
                            let y_ = usize(s.y[bi])
                            let yy_ = usize(s.yy[bi])
                            var sg = 1.0f64
                            if u { sg = 0.0f64 - 1.0f64 }
                            mb_apply(s, s.gbar, s.start1, y_, yy_, s.ri[bi], 2.0f64 * ci, ci, sg)
                            mb_apply(s, s.gbar, s.start2, y_, yy_, s.ri[bi], 2.0f64 * ci, ci, sg)
                        } else {
                            j = 0usize
                            while j < l {
                                if u {
                                    s.gbar[j] -= ci * qv(s, bi, j)
                                } else {
                                    s.gbar[j] += ci * qv(s, bi, j)
                                }
                                j += 1usize
                            }
                        }
                    }
                    i += 1usize
                }
            }
        }
    }
    var v = 0.0f64
    i = 0usize
    while i < l {
        if s.mode == 3usize {
            v += s.alpha[i] * (s.g[i] + s.lin)
        } else {
            v += s.alpha[i] * (s.g[i] + s.b[i])
        }
        i += 1usize
    }
    if s.mode == 3usize { ret (v / 4.0f64, ok) }
    ret (v / 2.0f64, ok)
}

fn new_w(a: *mem.Arena, qs: usize, lam: *f64) -> (tr.W, err) {
    let (pool, e1) = mem.alloc[f64](a, 20usize * qs + 3usize * qs * qs)
    let (fr, e2) = mem.alloc[usize](a, qs)
    let z = tr.W { n: qs, xl: pool[0usize..qs], xc: pool[qs..2usize * qs], s: pool[2usize * qs..3usize * qs], wa: pool[3usize * qs..4usize * qs], g: pool[4usize * qs..5usize * qs], bm: pool[5usize * qs..5usize * qs + qs * qs], lm: pool[5usize * qs + qs * qs..5usize * qs + 2usize * qs * qs], w: pool[5usize * qs + 2usize * qs * qs..6usize * qs + 2usize * qs * qs], wa2: pool[6usize * qs + 2usize * qs * qs..7usize * qs + 2usize * qs * qs], wsp: pool[7usize * qs + 2usize * qs * qs..8usize * qs + 2usize * qs * qs], wxl: pool[8usize * qs + 2usize * qs * qs..9usize * qs + 2usize * qs * qs], wxu: pool[9usize * qs + 2usize * qs * qs..10usize * qs + 2usize * qs * qs], gfree: pool[10usize * qs + 2usize * qs * qs..11usize * qs + 2usize * qs * qs], p: pool[11usize * qs + 2usize * qs * qs..12usize * qs + 2usize * qs * qs], q: pool[12usize * qs + 2usize * qs * qs..13usize * qs + 2usize * qs * qs], t: pool[13usize * qs + 2usize * qs * qs..14usize * qs + 2usize * qs * qs], r: pool[14usize * qs + 2usize * qs * qs..15usize * qs + 2usize * qs * qs], z: pool[15usize * qs + 2usize * qs * qs..16usize * qs + 2usize * qs * qs], wa1: pool[16usize * qs + 2usize * qs * qs..17usize * qs + 2usize * qs * qs], free: fr, nfev: 0usize, lam: lam }
    if e1 != ok || e2 != ok { ret (z, Fail) }
    ret (z, ok)
}

// the arrays of one Solver_B family run over l variables with m samples behind them
fn new_b(a: *mem.Arena, mode: usize, l: usize, m: usize, nf: usize, nr: usize, x: []const f64, base: []const f32, eps: f64, shrinking: bool) -> (B, err) {
    let qs = 10usize
    let (y, e1) = mem.alloc[i64](a, l)
    let (yy, e2) = mem.alloc[i64](a, l)
    let (ri, e3) = mem.alloc[usize](a, l)
    let (xi, e4) = mem.alloc[usize](a, l)
    let (g, e5) = mem.alloc[f64](a, l)
    let (gbar, e6) = mem.alloc[f64](a, l)
    let (alpha, e7) = mem.alloc[f64](a, l)
    let (bb, e8) = mem.alloc[f64](a, l)
    let (st, e9) = mem.alloc[u8](a, l)
    let (act, e10) = mem.alloc[usize](a, l)
    let (ws, e11) = mem.alloc[usize](a, qs)
    let (ows, e12) = mem.alloc[usize](a, qs)
    let (pm, e13) = mem.alloc[f64](a, qs)
    let (ps, e14) = mem.alloc[usize](a, qs)
    let (st1, e15) = mem.alloc[usize](a, nr * nr + 1usize)
    let (st2, e16) = mem.alloc[usize](a, nr * nr + 1usize)
    let (w, e17) = mem.alloc[f64](a, nf + 1usize)
    let (qx, e18) = mem.alloc[f64](a, qs)
    let (qc, e19) = mem.alloc[f64](a, qs)
    let (qq, e20) = mem.alloc[f64](a, qs * qs)
    let (qpp, e21) = mem.alloc[f64](a, qs)
    let (cc, e22) = mem.alloc[f64](a, nr + 1usize)
    var i = 0usize
    while i < qs {
        ws[i] = 0usize
        ows[i] = 18446744073709551615usize
        i += 1usize
    }
    i = 0usize
    while i < l {
        xi[i] = i
        i += 1usize
    }
    i = 0usize
    while i <= nf {
        w[i] = 0.0f64
        i += 1usize
    }
    let s = B { mode: mode, l: l, m: m, nf: nf, nr: nr, x: x, xi: xi, base: base, y: y, yy: yy, ri: ri, g: g, gbar: gbar, alpha: alpha, b: bb, st: st, act: act, c: cc, cp: 1.0f64, cn: 1.0f64, lin: 0.0f64, eps: eps, shrinking: shrinking, unshrunk: false, active: l, ws: ws, ows: ows, pm: pm, ps: ps, nq: 0usize, qs: qs, start1: st1, start2: st2, w: w, qx: qx, qc: qc, qq: qq, qpp: qpp }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (s, Fail) }
    if e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok { ret (s, Fail) }
    ret (s, ok)
}

fn sq_norms(a: *mem.Arena, x: []const f64, n: usize, nf: usize) -> ([]f64, err) {
    let (xsq, e) = mem.alloc[f64](a, n)
    if e != ok { ret (xsq, e) }
    var i = 0usize
    while i < n {
        var d = 0.0f64
        var k = 0usize
        while k < nf {
            d += x[i * nf + k] * x[i * nf + k]
            k += 1usize
        }
        xsq[i] = d
        i += 1usize
    }
    ret (xsq, ok)
}

// the n by n kernel matrix as floats: kind 0 float(K), 1 float(K + 1), 2 float(float(K) + 1)
fn kmat(a: *mem.Arena, x: []const f64, n: usize, nf: usize, par: *const ks.Param, kind: usize) -> ([]f32, err) {
    let (xsq, e1) = sq_norms(a, x, n, nf)
    let (base, e2) = mem.alloc[f32](a, n * n)
    if e1 != ok { ret (base, e1) }
    if e2 != ok { ret (base, e2) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let kv = ks.kval(par, x, nf, xsq, i, j)
            if kind == 0usize { base[i * n + j] = f32(kv) }
            if kind == 1usize { base[i * n + j] = f32(kv + 1.0f64) }
            if kind == 2usize { base[i * n + j] = f32(kv) + 1.0f32 }
            j += 1usize
        }
        i += 1usize
    }
    ret (base, ok)
}

// C-bsvc on one two-class problem: y of either sign (positive is +1), out receives alpha (>= 0). Answers the objective. A vanilladot kernel takes
// Solver_B_linear with the alpha seeding of tron_run (Cbegin 1, Cstep 2).
fn bsvc(a: *mem.Arena, x: []const f64, n: usize, nf: usize, y: []const f64, par: *const ks.Param, lam: *f64, out: []f64) -> (f64, err) {
    let (tw, ew) = new_w(a, 10usize, lam)
    if ew != ok { ret (0.0f64, ew) }
    var twv = tw
    var kd = 1usize
    if par.ktype == 0usize { kd = 0usize }
    let (base, eb) = kmat(a, x, n, nf, par, kd)
    if eb != ok { ret (0.0f64, eb) }
    let (s0, eo) = new_b(a, 0usize, n, n, nf, 1usize, x, base, par.tol, par.shrinking)
    if eo != ok { ret (0.0f64, eo) }
    var s = s0
    let noc = s.ows[0usize..0usize]
    var i = 0usize
    if par.ktype != 0usize {
        s.mode = 0usize
        s.cp = par.cp
        s.cn = par.cn
        i = 0usize
        while i < n {
            s.alpha[i] = 0.0f64
            s.b[i] = 0.0f64 - 1.0f64
            s.y[i] = 0i64 - 1i64
            if y[i] > 0.0f64 { s.y[i] = 1i64 }
            i += 1usize
        }
        let (obj, e) = run(a, &s, &twv, noc)
        i = 0usize
        while i < n {
            out[s.act[i]] = s.alpha[i]
            i += 1usize
        }
        ret (obj, e)
    }
    // linear
    s.mode = 2usize
    let cp = par.cp
    let cn = par.cn
    i = 0usize
    while i < n {
        out[i] = 0.0f64
        i += 1usize
    }
    let (yy, ey) = mem.alloc[i64](a, n)
    if ey != ok { ret (0.0f64, ey) }
    i = 0usize
    while i < n {
        yy[i] = 0i64 - 1i64
        if y[i] > 0.0f64 { yy[i] = 1i64 }
        i += 1usize
    }
    let cpj0 = 1.0f64
    var cpj = cpj0
    var cnj = cpj0 * cn / cp
    var obj = 0.0f64
    var e = ok
    var last = false
    while !last {
        var cpu = cpj
        var cnu = cnj
        last = !(cpj < cp)
        if last {
            cpu = cp
            cnu = cn
        }
        s.cp = cpu
        s.cn = cnu
        i = 0usize
        while i < n {
            s.alpha[i] = out[i]
            s.b[i] = 0.0f64 - 1.0f64
            s.y[i] = yy[i]
            i += 1usize
        }
        s.unshrunk = false
        let (o1, e1) = run(a, &s, &twv, noc)
        obj = o1
        e = e1
        if e != ok { ret (0.0f64, e) }
        i = 0usize
        while i < n {
            out[s.act[i]] = s.alpha[i]
            i += 1usize
        }
        if !last {
            if cpj * 2.0f64 >= cp {
                i = 0usize
                while i <= nf {
                    s.w[i] = 0.0f64
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    if yy[i] == 1i64 && out[i] >= cpj {
                        out[i] = cp
                    } else {
                        if yy[i] == 0i64 - 1i64 && out[i] >= cnj {
                            out[i] = cn
                        } else {
                            out[i] = out[i] * (cp / cpj)
                        }
                    }
                    let ya = f64(yy[i]) * out[i]
                    var k = 0usize
                    while k < nf {
                        s.w[k] += ya * x[i * nf + k]
                        k += 1usize
                    }
                    s.w[0usize] += ya
                    i += 1usize
                }
            } else {
                i = 0usize
                while i < n {
                    out[i] = out[i] * 2.0f64
                    i += 1usize
                }
                i = 0usize
                while i <= nf {
                    s.w[i] = s.w[i] * 2.0f64
                    i += 1usize
                }
            }
            cpj = cpj * 2.0f64
            cnj = cnj * 2.0f64
        }
    }
    ret (obj, e)
}

// eps-bsvr: y the targets, out receives alpha - alpha* (n values)
fn bsvr(a: *mem.Arena, x: []const f64, n: usize, nf: usize, y: []const f64, par: *const ks.Param, lam: *f64, out: []f64) -> (f64, err) {
    if par.ktype == 0usize { ret (0.0f64, Fail) }
    let (tw, ew) = new_w(a, 10usize, lam)
    if ew != ok { ret (0.0f64, ew) }
    var twv = tw
    let (base, eb) = kmat(a, x, n, nf, par, 2usize)
    if eb != ok { ret (0.0f64, eb) }
    let (s0, eo) = new_b(a, 1usize, 2usize * n, n, nf, 1usize, x, base, par.tol, par.shrinking)
    if eo != ok { ret (0.0f64, eo) }
    var s = s0
    s.cp = par.c
    s.cn = par.c
    let noc = s.ows[0usize..0usize]
    var i = 0usize
    while i < n {
        s.alpha[i] = 0.0f64
        s.b[i] = par.p - y[i]
        s.y[i] = 1i64
        s.alpha[i + n] = 0.0f64
        s.b[i + n] = par.p + y[i]
        s.y[i + n] = 0i64 - 1i64
        i += 1usize
    }
    let (obj, e) = run(a, &s, &twv, noc)
    let (res, er) = mem.alloc[f64](a, 2usize * n)
    if er != ok { ret (0.0f64, er) }
    i = 0usize
    while i < 2usize * n {
        res[s.act[i]] = s.alpha[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = res[i] - res[i + n]
        i += 1usize
    }
    ret (obj, e)
}

// kbb-svc: x sorted by class, cls the 0-based class of each row, count the class sizes, wc the cost per class. out receives n * (kc - 1) values in
// ksvm's layout (column k holds the coefficients against the other classes).
fn kbb(a: *mem.Arena, x: []const f64, n: usize, nf: usize, cls: []const usize, count: []const usize, kc: usize, par: *const ks.Param, wc: []const f64, lam: *f64, out: []f64) -> (f64, err) {
    let (tw, ew) = new_w(a, 10usize, lam)
    if ew != ok { ret (0.0f64, ew) }
    var twv = tw
    let (base, eb) = kmat(a, x, n, nf, par, 2usize)
    if eb != ok { ret (0.0f64, eb) }
    let ll = n * (kc - 1usize)
    let (s0, eo) = new_b(a, 3usize, ll, n, nf, kc, x, base, 2.0f64 * par.tol, par.shrinking)
    if eo != ok { ret (0.0f64, eo) }
    var s = s0
    var i = 0usize
    while i < kc {
        s.c[i] = wc[i]
        i += 1usize
    }
    s.lin = 0.0f64 - 2.0f64
    i = 0usize
    while i < ll {
        s.alpha[i] = 0.0f64
        i += 1usize
    }
    var p = 0usize
    i = 0usize
    while i < kc {
        var q = 0usize
        var j = 0usize
        while j < kc {
            if i != j {
                var k = 0usize
                while k < count[j] {
                    s.y[p] = i64(cls[q])
                    p += 1usize
                    q += 1usize
                    k += 1usize
                }
            } else {
                q += count[j]
            }
            j += 1usize
        }
        i += 1usize
    }
    let (obj, e) = run(a, &s, &twv, count)
    if e != ok { ret (0.0f64, e) }
    let (al2, e2) = mem.alloc[f64](a, ll)
    let (start, e3) = mem.alloc[usize](a, kc)
    let (start2, e4) = mem.alloc[usize](a, kc)
    if e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, Fail) }
    i = 0usize
    while i < ll {
        al2[s.act[i]] = s.alpha[i]
        i += 1usize
    }
    start[0usize] = 0usize
    start2[0usize] = 0usize
    i = 1usize
    while i < kc {
        start[i] = start[i - 1usize] + count[i - 1usize]
        start2[i] = start2[i - 1usize] + n - count[i - 1usize]
        i += 1usize
    }
    p = 0usize
    i = 0usize
    while i < kc {
        var jj = start[i]
        while jj < start[i] + count[i] {
            var k = 0usize
            while k < i {
                out[k * n + p] = al2[start2[k] + jj - count[k]]
                k += 1usize
            }
            k += 1usize
            while k < kc {
                out[(k - 1usize) * n + p] = al2[start2[k] + jj]
                k += 1usize
            }
            p += 1usize
            jj += 1usize
        }
        i += 1usize
    }
    // kernlab's tron_optim stores the objective, which Solver_MB never reports (uninitialised memory), over element n of this array
    if ll > n { out[n] = 0.0f64 }
    ret (obj, ok)
}

// spoc-svc: x sorted by class, cls the 0-based class, wc the cost per class. out receives the n by kc matrix of alpha (row-major, sample by class).
fn spoc(a: *mem.Arena, x: []const f64, n: usize, nf: usize, cls: []const usize, kc: usize, par: *const ks.Param, wc: []const f64, out: []f64) -> (f64, err) {
    let inf = ks.inf()
    let (base, eb) = kmat(a, x, n, nf, par, 0usize)
    if eb != ok { ret (0.0f64, eb) }
    let (y, e1) = mem.alloc[usize](a, n)
    let (act, e2) = mem.alloc[usize](a, n)
    let (g, e3) = mem.alloc[f64](a, n * kc)
    let (alpha, e4) = mem.alloc[f64](a, n * kc)
    let (ast, e5) = mem.alloc[bool](a, n * kc)
    let (bb, e6) = mem.alloc[f64](a, kc + 1usize)
    let (nu, e7) = mem.alloc[f64](a, kc)
    let (dd, e8) = mem.alloc[f64](a, kc + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (0.0f64, Fail) }
    let l = n
    var i = 0usize
    var m = 0usize
    while i < n {
        y[i] = cls[i]
        act[i] = i
        m = 0usize
        while m < kc {
            alpha[i * kc + m] = 0.0f64
            m += 1usize
        }
        i += 1usize
    }
    // status: true when alpha < C (free), false at the bound
    i = 0usize
    while i < l {
        m = 0usize
        while m < kc {
            var cm = 0.0f64
            if y[i] == m { cm = wc[m] }
            ast[i * kc + m] = !(alpha[i * kc + m] >= cm)
            m += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < l * kc {
        g[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < l {
        g[i * kc + y[i]] = 0.0f64
        i += 1usize
    }
    var active = l
    var unshrunk = false
    var iter = 0usize
    let eps = par.tol
    var counter = imin(l * 2usize, 2000usize) + 1usize
    let cmax = imin(l * 2usize, 2000usize)
    var old_q = l + 1usize
    var q = 0usize
    var done = false
    while !done {
        counter -= 1usize
        if counter == 0usize {
            if par.shrinking {
                // do_shrinking
                var vio = 0.0f64 - inf
                var jj = 0usize
                i = 0usize
                while i < active {
                    var lb = 0.0f64 - inf
                    var ub = inf
                    m = 0usize
                    while m < kc {
                        if g[jj] > lb { lb = g[jj] }
                        if ast[jj] {
                            if g[jj] < ub { ub = g[jj] }
                        }
                        m += 1usize
                        jj += 1usize
                    }
                    if lb - ub > vio {
                        q = i
                        vio = lb - ub
                    }
                    i += 1usize
                }
                let gm = vio
                if gm >= eps {
                    i = 0usize
                    while i < active {
                        let th = g[i * kc + y[i]] - gm / 2.0f64
                        var out_ = false
                        m = 0usize
                        while m < kc {
                            if m != y[i] {
                                if ast[i * kc + m] || g[i * kc + m] >= th {
                                    out_ = true
                                    break
                                }
                            }
                            m += 1usize
                        }
                        if !out_ {
                            active -= 1usize
                            spoc_swap(g, alpha, ast, y, act, kc, i, active)
                        } else {
                            i += 1usize
                        }
                    }
                    if !(unshrunk || gm > 10.0f64 * eps) {
                        unshrunk = true
                        spoc_recon(base, n, g, alpha, y, act, kc, active, l)
                        var ii = l
                        while ii > active {
                            let i2 = ii - 1usize
                            let th = g[i2 * kc + y[i2]] - gm / 2.0f64
                            var out_ = false
                            m = 0usize
                            while m < kc {
                                if m != y[i2] {
                                    if g[i2 * kc + m] >= th {
                                        out_ = true
                                        break
                                    }
                                }
                                m += 1usize
                            }
                            if !out_ {
                                spoc_swap(g, alpha, ast, y, act, kc, i2, active)
                                active += 1usize
                            } else {
                                ii -= 1usize
                            }
                        }
                    }
                }
            }
            counter = cmax
        }
        var vio = 0.0f64 - inf
        var jj = 0usize
        i = 0usize
        while i < active {
            var lb = 0.0f64 - inf
            var ub = inf
            m = 0usize
            while m < kc {
                if g[jj] > lb { lb = g[jj] }
                if ast[jj] {
                    if g[jj] < ub { ub = g[jj] }
                }
                m += 1usize
                jj += 1usize
            }
            if lb - ub > vio {
                q = i
                vio = lb - ub
            }
            i += 1usize
        }
        var proceed = true
        if vio < eps {
            spoc_recon(base, n, g, alpha, y, act, kc, active, l)
            active = l
            vio = 0.0f64 - inf
            jj = 0usize
            i = 0usize
            while i < active {
                var lb = 0.0f64 - inf
                var ub = inf
                m = 0usize
                while m < kc {
                    if g[jj] > lb { lb = g[jj] }
                    if ast[jj] {
                        if g[jj] < ub { ub = g[jj] }
                    }
                    m += 1usize
                    jj += 1usize
                }
                if lb - ub > vio {
                    q = i
                    vio = lb - ub
                }
                i += 1usize
            }
            if vio < eps {
                done = true
                proceed = false
            } else {
                counter = 1usize
            }
        }
        if proceed && counter == cmax && old_q == q {
            done = true
            proceed = false
        }
        if proceed {
            old_q = q
            iter += 1usize
            let aa = f64(base[(act[q]) * n + act[q]])
            m = 0usize
            while m < kc {
                bb[m] = g[q * kc + m] - aa * alpha[q * kc + m]
                m += 1usize
            }
            bb[y[q]] += aa * wc[y[q]]
            if math.abs[f64](aa) > 0.0f64 {
                // solve_sub_problem: sort B descending, then the threshold
                m = 0usize
                while m < kc {
                    dd[m] = bb[m]
                    m += 1usize
                }
                // insertion sort is stable and the values only matter as a multiset
                m = 1usize
                while m < kc {
                    let v = dd[m]
                    var jx = m
                    while jx > 0usize && dd[jx - 1usize] < v {
                        dd[jx] = dd[jx - 1usize]
                        jx -= 1usize
                    }
                    dd[jx] = v
                    m += 1usize
                }
                dd[kc] = 0.0f64 - inf
                var phi = dd[0usize] - aa * wc[y[q]]
                var r = 0usize
                while phi < f64(r + 1usize) * dd[r + 1usize] {
                    phi += dd[r + 1usize]
                    r += 1usize
                }
                phi = phi / f64(r + 1usize)
                m = 0usize
                while m < kc {
                    var t = phi - bb[m]
                    if t > 0.0f64 { t = 0.0f64 }
                    nu[m] = t / aa
                    m += 1usize
                }
            } else {
                var bi = 0usize
                m = 1usize
                while m < kc {
                    if bb[m] > bb[bi] { bi = m }
                    m += 1usize
                }
                nu[bi] = 0.0f64 - wc[y[q]]
            }
            nu[y[q]] += wc[y[q]]
            m = 0usize
            while m < kc {
                let d = nu[m] - alpha[q * kc + m]
                alpha[q * kc + m] = nu[m]
                var cm = 0.0f64
                if y[q] == m { cm = wc[m] }
                ast[q * kc + m] = !(alpha[q * kc + m] >= cm)
                i = 0usize
                while i < active {
                    g[i * kc + m] += d * f64(base[act[q] * n + act[i]])
                    i += 1usize
                }
                m += 1usize
            }
        }
    }
    var obj = 0.0f64
    i = 0usize
    while i < l * kc {
        obj += alpha[i] * (g[i] + 1.0f64)
        i += 1usize
    }
    i = 0usize
    while i < l {
        obj -= alpha[i * kc + y[i]]
        i += 1usize
    }
    obj = obj / 2.0f64
    i = 0usize
    while i < l {
        m = 0usize
        while m < kc {
            out[act[i] * kc + m] = alpha[i * kc + m]
            m += 1usize
        }
        i += 1usize
    }
    // the same overwrite as in kbb: element n (row-major) holds kernlab's unset objective, taken as zero
    out[n] = 0.0f64
    ret (obj, ok)
}

fn spoc_swap(g: []f64, alpha: []f64, ast: []bool, y: []usize, act: []usize, kc: usize, i: usize, j: usize) {
    swapu(y, i, j)
    swapu(act, i, j)
    var m = 0usize
    while m < kc {
        swapf(g, i * kc + m, j * kc + m)
        swapf(alpha, i * kc + m, j * kc + m)
        let t = ast[i * kc + m]
        ast[i * kc + m] = ast[j * kc + m]
        ast[j * kc + m] = t
        m += 1usize
    }
}

fn spoc_recon(base: []const f32, n: usize, g: []f64, alpha: []const f64, y: []const usize, act: []const usize, kc: usize, active: usize, l: usize) {
    if active == l { ret }
    var i = active * kc
    while i < l * kc {
        g[i] = 1.0f64
        i += 1usize
    }
    i = active
    while i < l {
        g[i * kc + y[i]] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < active {
        var m = 0usize
        while m < kc {
            if math.abs[f64](alpha[i * kc + m]) != 0.0f64 {
                let aim = alpha[i * kc + m]
                var j = active
                while j < l {
                    g[j * kc + m] += aim * f64(base[act[i] * n + act[j]])
                    j += 1usize
                }
            }
            m += 1usize
        }
        i += 1usize
    }
}
