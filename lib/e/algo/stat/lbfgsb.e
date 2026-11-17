// R's optim(method = "L-BFGS-B"): the limited-memory BFGS with box bounds of Byrd, Lu, Nocedal and Zhu (the version R
// ships): generalised Cauchy point, subspace minimisation with a step back to the box, and the More-Thuente line search
// (ftol 1e-3, gtol 0.9, xtol 0.1). The compact matrices of the original are formed densely, which gives the same
// iterates up to rounding. `lbfgsb_fd_gradient` is optim's finite-difference gradient that keeps both probes inside the
// bounds.
//
// A bound with |v| >= 1e300 is no bound. factr 1e7, pgtol 0, m 5 and maxit 100 are optim's defaults.

use e.math
use e.mem

type LbS = struct {
    n: usize, m: usize, col: usize, theta: f64,
    ws: []f64, wy: []f64, minv: []f64,
    lo: []const f64, up: []const f64, nbd: []usize, iw: []usize,
    dv: []f64, pv: []f64, cv: []f64, vv: []f64, wbp: []f64, tb: []f64, iord: []usize
}

// iwhere codes: 0 free, 1 at lower, 2 at upper, 3 always fixed, 8 free with zero direction, 9 unbounded
fn lb_is_free(iw: usize) -> bool { ret iw == 0usize || iw >= 8usize }

// Gaussian elimination with partial pivoting; am is n x n row-major, b is replaced by the solution
fn lb_solve(am: []f64, b: []f64, n: usize) -> bool {
    var c = 0usize
    while c < n {
        var pv = c
        var best = math.abs[f64](am[c * n + c])
        var r = c + 1usize
        while r < n {
            if math.abs[f64](am[r * n + c]) > best {
                best = math.abs[f64](am[r * n + c])
                pv = r
            }
            r += 1usize
        }
        if !(best > 0.0f64) { ret false }
        if pv != c {
            var k = 0usize
            while k < n {
                let t0 = am[c * n + k]
                am[c * n + k] = am[pv * n + k]
                am[pv * n + k] = t0
                k += 1usize
            }
            let tb0 = b[c]
            b[c] = b[pv]
            b[pv] = tb0
        }
        r = c + 1usize
        while r < n {
            let f = am[r * n + c] / am[c * n + c]
            if f != 0.0f64 {
                var k = c
                while k < n {
                    am[r * n + k] -= f * am[c * n + k]
                    k += 1usize
                }
                b[r] -= f * b[c]
            }
            r += 1usize
        }
        c += 1usize
    }
    var ri = n
    while ri > 0usize {
        let q = ri - 1usize
        var s = b[q]
        var k = q + 1usize
        while k < n {
            s -= am[q * n + k] * b[k]
            k += 1usize
        }
        b[q] = s / am[q * n + q]
        ri -= 1usize
    }
    ret true
}

// minv = inverse of [[-D, L'], [L, theta S'S]]; false when singular
fn lb_form_minv(ar: *mem.Arena, s: *LbS) -> bool {
    let col = s.col
    let c2 = 2usize * col
    let n = s.n
    let st = mem.mark(ar)
    let (am, e1) = mem.alloc[f64](ar, c2 * c2)
    let (aw, e2) = mem.alloc[f64](ar, c2 * c2)
    let (bv, e3) = mem.alloc[f64](ar, c2)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var i = 0usize
    while i < col {
        var j = 0usize
        while j < col {
            var sy = 0.0f64
            var ss = 0.0f64
            var q = 0usize
            while q < n {
                sy += s.ws[i * n + q] * s.wy[j * n + q]
                ss += s.ws[i * n + q] * s.ws[j * n + q]
                q += 1usize
            }
            // upper-left -D, upper-right L' (entry (i, col + j) = s_j . y_i for j > i), lower-left L, lower-right theta S'S
            var dd = 0.0f64
            if i == j { dd = 0.0f64 - sy }
            am[i * c2 + j] = dd
            if i > j { am[(col + i) * c2 + j] = sy } else { am[(col + i) * c2 + j] = 0.0f64 }
            if j > i {
                var sy2 = 0.0f64
                q = 0usize
                while q < n {
                    sy2 += s.ws[j * n + q] * s.wy[i * n + q]
                    q += 1usize
                }
                am[i * c2 + col + j] = sy2
            } else {
                am[i * c2 + col + j] = 0.0f64
            }
            am[(col + i) * c2 + col + j] = s.theta * ss
            j += 1usize
        }
        i += 1usize
    }
    var good = true
    var cidx = 0usize
    while cidx < c2 && good {
        i = 0usize
        while i < c2 * c2 {
            aw[i] = am[i]
            i += 1usize
        }
        i = 0usize
        while i < c2 {
            bv[i] = 0.0f64
            i += 1usize
        }
        bv[cidx] = 1.0f64
        good = lb_solve(aw, bv, c2)
        if good {
            i = 0usize
            while i < c2 {
                s.minv[i * c2 + cidx] = bv[i]
                i += 1usize
            }
        }
        cidx += 1usize
    }
    mem.reset(ar, st)
    ret good
}

// vout = M vin over the 2 col leading entries
fn lb_mv(s: *LbS, vin: []const f64, vout: []f64) {
    let c2 = 2usize * s.col
    var i = 0usize
    while i < c2 {
        var t = 0.0f64
        var j = 0usize
        while j < c2 {
            t += s.minv[i * c2 + j] * vin[j]
            j += 1usize
        }
        vout[i] = t
        i += 1usize
    }
}

fn lb_dot(a1: []const f64, a2: []const f64, n: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < n {
        t += a1[i] * a2[i]
        i += 1usize
    }
    ret t
}

// the generalised Cauchy point along the projected steepest descent path; xcp is the answer, iw is updated
fn lb_cauchy(s: *LbS, x: []const f64, g: []const f64, sbgnrm: f64, xcp: []f64) {
    let n = s.n
    let col = s.col
    let col2 = 2usize * col
    let theta = s.theta
    var i = 0usize
    while i < n {
        xcp[i] = x[i]
        i += 1usize
    }
    if sbgnrm <= 0.0f64 { ret }
    var bnded = true
    var nunb = 0usize
    var nbreak = 0usize
    var bkmin = 0.0f64
    var f1 = 0.0f64
    i = 0usize
    while i < col2 {
        s.pv[i] = 0.0f64
        s.cv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let neggi = 0.0f64 - g[i]
        var tl = 0.0f64
        var tu = 0.0f64
        if s.iw[i] != 3usize && s.iw[i] != 9usize {
            if s.nbd[i] <= 2usize { tl = x[i] - s.lo[i] }
            if s.nbd[i] >= 2usize { tu = s.up[i] - x[i] }
            let xlower = s.nbd[i] <= 2usize && tl <= 0.0f64
            let xupper = s.nbd[i] >= 2usize && tu <= 0.0f64
            s.iw[i] = 0usize
            if xlower {
                if neggi <= 0.0f64 { s.iw[i] = 1usize }
            } else if xupper {
                if neggi >= 0.0f64 { s.iw[i] = 2usize }
            } else {
                if math.abs[f64](neggi) <= 0.0f64 { s.iw[i] = 8usize }
            }
        }
        if s.iw[i] != 0usize && s.iw[i] != 9usize {
            s.dv[i] = 0.0f64
        } else {
            s.dv[i] = neggi
            f1 -= neggi * neggi
            var j = 0usize
            while j < col {
                s.pv[j] += s.wy[j * n + i] * neggi
                s.pv[col + j] += s.ws[j * n + i] * neggi
                j += 1usize
            }
            if s.nbd[i] <= 2usize && s.nbd[i] != 0usize && neggi < 0.0f64 {
                s.tb[nbreak] = tl / (0.0f64 - neggi)
                s.iord[nbreak] = i
                if nbreak == 0usize || s.tb[nbreak] < bkmin { bkmin = s.tb[nbreak] }
                nbreak += 1usize
            } else if s.nbd[i] >= 2usize && neggi > 0.0f64 {
                s.tb[nbreak] = tu / neggi
                s.iord[nbreak] = i
                if nbreak == 0usize || s.tb[nbreak] < bkmin { bkmin = s.tb[nbreak] }
                nbreak += 1usize
            } else {
                nunb += 1usize
                if math.abs[f64](neggi) > 0.0f64 { bnded = false }
            }
        }
        i += 1usize
    }
    if theta != 1.0f64 {
        i = 0usize
        while i < col {
            s.pv[col + i] *= theta
            i += 1usize
        }
    }
    if nbreak == 0usize && nunb == 0usize { ret }
    var f2 = 0.0f64 - theta * f1
    let f2org = f2
    if col > 0usize {
        lb_mv(s, s.pv, s.vv)
        f2 -= lb_dot(s.vv, s.pv, col2)
    }
    var dtm = 0.0f64 - f1 / f2
    var tsum = 0.0f64
    var go = nbreak > 0usize
    var nleft = nbreak
    var tj = 0.0f64
    while go {
        let tj0 = tj
        var bi = 0usize
        var q = 1usize
        while q < nleft {
            if s.tb[q] < s.tb[bi] { bi = q }
            q += 1usize
        }
        tj = s.tb[bi]
        let ibp = s.iord[bi]
        s.tb[bi] = s.tb[nleft - 1usize]
        s.iord[bi] = s.iord[nleft - 1usize]
        let dt = tj - tj0
        if dtm < dt {
            go = false
        } else {
            tsum += dt
            nleft -= 1usize
            let dibp = s.dv[ibp]
            s.dv[ibp] = 0.0f64
            var zibp = 0.0f64
            if dibp > 0.0f64 {
                zibp = s.up[ibp] - x[ibp]
                xcp[ibp] = s.up[ibp]
                s.iw[ibp] = 2usize
            } else {
                zibp = s.lo[ibp] - x[ibp]
                xcp[ibp] = s.lo[ibp]
                s.iw[ibp] = 1usize
            }
            if nleft == 0usize && nbreak == n {
                dtm = dt
                go = false
                // all variables are fixed: xcp is final
                ret
            }
            let dibp2 = dibp * dibp
            f1 = f1 + dt * f2 + dibp2 - theta * dibp * zibp
            f2 -= theta * dibp2
            if col > 0usize {
                var j = 0usize
                while j < col2 {
                    s.cv[j] += dt * s.pv[j]
                    j += 1usize
                }
                j = 0usize
                while j < col {
                    s.wbp[j] = s.wy[j * n + ibp]
                    s.wbp[col + j] = theta * s.ws[j * n + ibp]
                    j += 1usize
                }
                lb_mv(s, s.wbp, s.vv)
                let wmc = lb_dot(s.cv, s.vv, col2)
                let wmp = lb_dot(s.pv, s.vv, col2)
                let wmw = lb_dot(s.wbp, s.vv, col2)
                j = 0usize
                while j < col2 {
                    s.pv[j] -= dibp * s.wbp[j]
                    j += 1usize
                }
                f1 += dibp * wmc
                f2 = f2 + 2.0f64 * dibp * wmp - dibp2 * wmw
            }
            let f2min = 2.220446049250313e-16f64 * f2org
            if f2 < f2min { f2 = f2min }
            if nleft > 0usize {
                dtm = 0.0f64 - f1 / f2
            } else if bnded {
                f1 = 0.0f64
                f2 = 0.0f64
                dtm = 0.0f64
                go = false
            } else {
                dtm = 0.0f64 - f1 / f2
                go = false
            }
        }
    }
    if dtm <= 0.0f64 { dtm = 0.0f64 }
    tsum += dtm
    i = 0usize
    while i < n {
        xcp[i] += tsum * s.dv[i]
        i += 1usize
    }
}

// the subspace minimisation over the free variables from the Cauchy point z, backtracked into the box; false if singular
fn lb_subsm(ar: *mem.Arena, s: *LbS, x: []const f64, g: []const f64, z: []f64) -> bool {
    let n = s.n
    let col = s.col
    let col2 = 2usize * col
    let theta = s.theta
    var nsub = 0usize
    var i = 0usize
    while i < n {
        if lb_is_free(s.iw[i]) { nsub += 1usize }
        i += 1usize
    }
    if nsub == 0usize { ret true }
    let st = mem.mark(ar)
    let (idx, e1) = mem.alloc[usize](ar, nsub)
    let (rr, e2) = mem.alloc[f64](ar, nsub)
    let (bff, e3) = mem.alloc[f64](ar, nsub * nsub)
    let (mc, e4) = mem.alloc[f64](ar, col2)
    let (mwj, e5) = mem.alloc[f64](ar, col2)
    let (wj, e6) = mem.alloc[f64](ar, col2)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret false }
    var k = 0usize
    i = 0usize
    while i < n {
        if lb_is_free(s.iw[i]) {
            idx[k] = i
            k += 1usize
        }
        i += 1usize
    }
    // c = W'(z - x), then M c
    var j = 0usize
    while j < col {
        var t1 = 0.0f64
        var t2 = 0.0f64
        i = 0usize
        while i < n {
            t1 += s.wy[j * n + i] * (z[i] - x[i])
            t2 += s.ws[j * n + i] * (z[i] - x[i])
            i += 1usize
        }
        s.cv[j] = t1
        s.cv[col + j] = theta * t2
        j += 1usize
    }
    lb_mv(s, s.cv, mc)
    i = 0usize
    while i < nsub {
        let q = idx[i]
        var wmc = 0.0f64
        j = 0usize
        while j < col {
            wmc += s.wy[j * n + q] * mc[j] + theta * s.ws[j * n + q] * mc[col + j]
            j += 1usize
        }
        rr[i] = 0.0f64 - (g[q] + theta * (z[q] - x[q]) - wmc)
        i += 1usize
    }
    // reduced Hessian theta I - Zf' W M W' Zf
    var jj = 0usize
    while jj < nsub {
        let q2 = idx[jj]
        j = 0usize
        while j < col {
            wj[j] = s.wy[j * n + q2]
            wj[col + j] = theta * s.ws[j * n + q2]
            j += 1usize
        }
        lb_mv(s, wj, mwj)
        i = 0usize
        while i < nsub {
            let q1 = idx[i]
            var t = 0.0f64
            j = 0usize
            while j < col {
                t += s.wy[j * n + q1] * mwj[j] + theta * s.ws[j * n + q1] * mwj[col + j]
                j += 1usize
            }
            var dd = 0.0f64
            if i == jj { dd = theta }
            bff[i * nsub + jj] = dd - t
            i += 1usize
        }
        jj += 1usize
    }
    let solved = lb_solve(bff, rr, nsub)
    if !solved {
        mem.reset(ar, st)
        ret false
    }
    // step back into the box
    var alpha = 1.0f64
    var temp1 = alpha
    var ibd = 0usize
    i = 0usize
    while i < nsub {
        let q = idx[i]
        let dk = rr[i]
        if s.nbd[q] != 0usize {
            if dk < 0.0f64 && s.nbd[q] <= 2usize {
                let temp2 = z[q] - s.lo[q]
                if temp2 <= 0.0f64 {
                    alpha = 0.0f64
                } else if dk * alpha < 0.0f64 - temp2 {
                    alpha = (0.0f64 - temp2) / dk
                }
            } else if dk > 0.0f64 && s.nbd[q] >= 2usize {
                let temp2 = s.up[q] - z[q]
                if temp2 <= 0.0f64 {
                    alpha = 0.0f64
                } else if dk * alpha > temp2 {
                    alpha = temp2 / dk
                }
            }
            if alpha < temp1 {
                temp1 = alpha
                ibd = i
            }
        }
        i += 1usize
    }
    if alpha < 1.0f64 {
        let dk = rr[ibd]
        let q = idx[ibd]
        if dk > 0.0f64 {
            z[q] = s.up[q]
            rr[ibd] = 0.0f64
        } else if dk < 0.0f64 {
            z[q] = s.lo[q]
            rr[ibd] = 0.0f64
        }
    }
    i = 0usize
    while i < nsub {
        z[idx[i]] += alpha * rr[i]
        i += 1usize
    }
    mem.reset(ar, st)
    ret true
}

// optim's gradient for L-BFGS-B: central differences with ndeps steps, each probe clipped to the bounds
fn lbfgsb_fd_gradient[Ctx: type](c: *Ctx, f_: fn(*Ctx, []const f64) -> f64, x: []f64, lo: []const f64, up: []const f64, ndeps: f64, g: []f64) -> bool {
    let n = x.len
    var good = true
    var i = 0usize
    while i < n {
        let keep = x[i]
        var eps = ndeps
        var epsused = eps
        var t = keep + eps
        if t > up[i] {
            t = up[i]
            epsused = t - keep
        }
        x[i] = t
        let v1 = f_(c, x)
        t = keep - eps
        if t < lo[i] {
            t = lo[i]
            eps = keep - t
        }
        x[i] = t
        let v2 = f_(c, x)
        g[i] = (v1 - v2) / (epsused + eps)
        if !(g[i] - g[i] == 0.0f64) { good = false }
        x[i] = keep
        i += 1usize
    }
    ret good
}

// min f over lo <= x <= up from x (the answer is left in x); returns (minimum, fail) with optim's codes: 0 converged,
// 1 iteration limit, 51 warning, 52 error (also a non-finite function value)
fn lbfgsb[Ctx: type](ar: *mem.Arena, c: *Ctx, f_: fn(*Ctx, []const f64) -> f64, gr: fn(*Ctx, []const f64, []f64), x: []f64, lo: []const f64, up: []const f64, factr: f64, pgtol: f64, mem_m: usize, maxit: usize) -> (f64, i64) {
    let n = x.len
    let epsmch = 2.220446049250313e-16f64
    let mm = mem_m
    var s: LbS = zero
    let (ws, e1) = mem.alloc[f64](ar, n * mm)
    let (wy, e2) = mem.alloc[f64](ar, n * mm)
    let (minv, e3) = mem.alloc[f64](ar, 4usize * mm * mm)
    let (nbd, e4) = mem.alloc[usize](ar, n)
    let (iw, e5) = mem.alloc[usize](ar, n)
    let (dv, e6) = mem.alloc[f64](ar, n)
    let (pv, e7) = mem.alloc[f64](ar, 2usize * mm)
    let (cv, e8) = mem.alloc[f64](ar, 2usize * mm)
    let (vv, e9) = mem.alloc[f64](ar, 2usize * mm)
    let (wbp, e10) = mem.alloc[f64](ar, 2usize * mm)
    let (tb, e11) = mem.alloc[f64](ar, n)
    let (iord, e12) = mem.alloc[usize](ar, n)
    let (g, e13) = mem.alloc[f64](ar, n)
    let (told, e14) = mem.alloc[f64](ar, n)
    let (gold, e15) = mem.alloc[f64](ar, n)
    let (z, e16) = mem.alloc[f64](ar, n)
    let (dd, e17) = mem.alloc[f64](ar, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok { ret (0.0f64 / 0.0f64, 52i64) }
    s = LbS{ n: n, m: mm, col: 0usize, theta: 1.0f64, ws: ws, wy: wy, minv: minv, lo: lo, up: up, nbd: nbd, iw: iw, dv: dv, pv: pv, cv: cv, vv: vv, wbp: wbp, tb: tb, iord: iord }
    // bounds, projection of x, iwhere
    var cnstnd = false
    var boxed = true
    var i = 0usize
    while i < n {
        let finlo = math.abs[f64](lo[i]) < 1.0e300f64
        let finup = math.abs[f64](up[i]) < 1.0e300f64
        nbd[i] = 0usize
        if finlo && finup { nbd[i] = 2usize }
        if finlo && !finup { nbd[i] = 1usize }
        if !finlo && finup { nbd[i] = 3usize }
        if nbd[i] > 0usize {
            if nbd[i] <= 2usize && x[i] <= lo[i] {
                x[i] = lo[i]
            } else if nbd[i] >= 2usize && x[i] >= up[i] {
                x[i] = up[i]
            }
        }
        if nbd[i] != 2usize { boxed = false }
        if nbd[i] == 0usize {
            iw[i] = 9usize
        } else {
            cnstnd = true
            iw[i] = 0usize
            if nbd[i] == 2usize && up[i] - lo[i] <= 0.0f64 { iw[i] = 3usize }
        }
        i += 1usize
    }
    var f = f_(c, x)
    if !(f - f == 0.0f64) { ret (f, 52i64) }
    gr(c, x, g)
    var theta = 1.0f64
    var col = 0usize
    var iter = 0usize
    var drv = 0usize
    var fail = 0i64
    var done = false
    var sbgnrm = lb_projgr(s.nbd, x, lo, up, g, n)
    if sbgnrm <= pgtol { done = true }
    while !done {
        // refresh points restart here
        var restart = true
        while restart && !done {
            restart = false
            s.col = col
            s.theta = theta
            var minv_ok = true
            if col > 0usize { minv_ok = lb_form_minv(ar, &s) }
            if !minv_ok {
                col = 0usize
                theta = 1.0f64
                restart = true
            } else {
                i = 0usize
                while i < n {
                    z[i] = x[i]
                    i += 1usize
                }
                if !(!cnstnd && col > 0usize) {
                    lb_cauchy(&s, x, g, sbgnrm, z)
                } else {
                    // unconstrained: the free set is everything
                    i = 0usize
                    while i < n {
                        iw[i] = 9usize
                        i += 1usize
                    }
                }
                var nfree = 0usize
                i = 0usize
                while i < n {
                    if lb_is_free(iw[i]) { nfree += 1usize }
                    i += 1usize
                }
                var sub_ok = true
                if nfree > 0usize && col > 0usize { sub_ok = lb_subsm(ar, &s, x, g, z) }
                if !sub_ok {
                    col = 0usize
                    theta = 1.0f64
                    restart = true
                } else {
                    i = 0usize
                    while i < n {
                        dd[i] = z[i] - x[i]
                        i += 1usize
                    }
                    // line search
                    let dtd = lb_dot(dd, dd, n)
                    let dnorm = math.sqrt[f64](dtd)
                    var stpmx = 1.0e10f64
                    if cnstnd {
                        if iter == 0usize {
                            stpmx = 1.0f64
                        } else {
                            i = 0usize
                            while i < n {
                                let a1 = dd[i]
                                if nbd[i] != 0usize {
                                    if a1 < 0.0f64 && nbd[i] <= 2usize {
                                        let a2 = lo[i] - x[i]
                                        if a2 >= 0.0f64 {
                                            stpmx = 0.0f64
                                        } else if a1 * stpmx < a2 {
                                            stpmx = a2 / a1
                                        }
                                    } else if a1 > 0.0f64 && nbd[i] >= 2usize {
                                        let a2 = up[i] - x[i]
                                        if a2 <= 0.0f64 {
                                            stpmx = 0.0f64
                                        } else if a1 * stpmx > a2 {
                                            stpmx = a2 / a1
                                        }
                                    }
                                }
                                i += 1usize
                            }
                        }
                    }
                    var stp = 1.0f64
                    if iter == 0usize && !boxed {
                        stp = 1.0f64 / dnorm
                        if stpmx < stp { stp = stpmx }
                    }
                    i = 0usize
                    while i < n {
                        told[i] = x[i]
                        gold[i] = g[i]
                        i += 1usize
                    }
                    let fold = f
                    var gd = lb_dot(g, dd, n)
                    let gdold = gd
                    var lsfail = false
                    var info = 0i64
                    if gd >= 0.0f64 {
                        lsfail = true
                        info = 0i64 - 4i64
                    }
                    var ls = LbLs{ brackt: false, stage: 1usize, finit: f, ginit: gd, gtest: 1.0e-3f64 * gd, gx: gd, gy: gd, fx: f, fy: f, stx: 0.0f64, sty: 0.0f64, stmin: 0.0f64, stmax: stp + 4.0f64 * stp, width: stpmx, width1: 2.0f64 * stpmx }
                    var ifun = 0usize
                    var lsdone = false
                    var nonfinite = false
                    while !lsfail && !lsdone {
                        ifun += 1usize
                        if ifun - 1usize >= 20usize {
                            lsfail = true
                        } else {
                            if stp == 1.0f64 {
                                i = 0usize
                                while i < n {
                                    x[i] = z[i]
                                    i += 1usize
                                }
                            } else {
                                i = 0usize
                                while i < n {
                                    x[i] = stp * dd[i] + told[i]
                                    i += 1usize
                                }
                            }
                            f = f_(c, x)
                            if !(f - f == 0.0f64) {
                                nonfinite = true
                                lsfail = true
                            } else {
                                gr(c, x, g)
                                gd = lb_dot(g, dd, n)
                                let (nstp, status) = lb_dcsrch(&ls, f, gd, stp, 0.0f64, stpmx)
                                stp = nstp
                                if status != 0usize { lsdone = true }
                            }
                        }
                    }
                    if nonfinite {
                        i = 0usize
                        while i < n {
                            x[i] = told[i]
                            i += 1usize
                        }
                        f = fold
                        fail = 52i64
                        done = true
                    } else if lsfail {
                        i = 0usize
                        while i < n {
                            x[i] = told[i]
                            g[i] = gold[i]
                            i += 1usize
                        }
                        f = fold
                        if col == 0usize {
                            fail = 52i64
                            done = true
                        } else {
                            col = 0usize
                            theta = 1.0f64
                            restart = true
                        }
                    } else {
                        iter += 1usize
                        sbgnrm = lb_projgr(nbd, x, lo, up, g, n)
                        drv += 1usize
                        if drv > maxit {
                            fail = 1i64
                            done = true
                        } else if sbgnrm <= pgtol {
                            done = true
                        } else {
                            var ddum = math.abs[f64](fold)
                            if math.abs[f64](f) > ddum { ddum = math.abs[f64](f) }
                            if 1.0f64 > ddum { ddum = 1.0f64 }
                            if fold - f <= epsmch * factr * ddum {
                                done = true
                            } else {
                                // L-BFGS update from d = newx - oldx and r = newg - oldg
                                var rr = 0.0f64
                                i = 0usize
                                while i < n {
                                    gold[i] = g[i] - gold[i]
                                    rr += gold[i] * gold[i]
                                    i += 1usize
                                }
                                var dr = 0.0f64
                                var ddum2 = 0.0f64
                                if stp == 1.0f64 {
                                    dr = gd - gdold
                                    ddum2 = 0.0f64 - gdold
                                } else {
                                    dr = (gd - gdold) * stp
                                    ddum2 = 0.0f64 - gdold * stp
                                    i = 0usize
                                    while i < n {
                                        dd[i] = stp * dd[i]
                                        i += 1usize
                                    }
                                }
                                if dr > epsmch * ddum2 {
                                    if col == mm {
                                        var k = 1usize
                                        while k < mm {
                                            i = 0usize
                                            while i < n {
                                                ws[(k - 1usize) * n + i] = ws[k * n + i]
                                                wy[(k - 1usize) * n + i] = wy[k * n + i]
                                                i += 1usize
                                            }
                                            k += 1usize
                                        }
                                        col -= 1usize
                                    }
                                    i = 0usize
                                    while i < n {
                                        ws[col * n + i] = dd[i]
                                        wy[col * n + i] = gold[i]
                                        i += 1usize
                                    }
                                    col += 1usize
                                    theta = rr / dr
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ret (f, fail)
}

fn lb_projgr(nbd: []const usize, x: []const f64, lo: []const f64, up: []const f64, g: []const f64, n: usize) -> f64 {
    var sb = 0.0f64
    var i = 0usize
    while i < n {
        var gi = g[i]
        if nbd[i] != 0usize {
            if gi < 0.0f64 {
                if nbd[i] >= 2usize {
                    let t = x[i] - up[i]
                    if t > gi { gi = t }
                }
            } else {
                if nbd[i] <= 2usize {
                    let t = x[i] - lo[i]
                    if t < gi { gi = t }
                }
            }
        }
        if math.abs[f64](gi) > sb { sb = math.abs[f64](gi) }
        i += 1usize
    }
    ret sb
}

type LbLs = struct { brackt: bool, stage: usize, finit: f64, ginit: f64, gtest: f64, gx: f64, gy: f64, fx: f64, fy: f64, stx: f64, sty: f64, stmin: f64, stmax: f64, width: f64, width1: f64 }

fn lb_max3(a1: f64, a2: f64, a3: f64) -> f64 {
    var r = a1
    if a2 > r { r = a2 }
    if a3 > r { r = a3 }
    ret r
}

// MINPACK-2 dcstep: updates the bracket and returns the new step
fn lb_dcstep(ls: *LbLs, stp: f64, fp: f64, dp: f64, stpmin: f64, stpmax: f64) -> f64 {
    let sgnd = dp * (ls.gx / math.abs[f64](ls.gx))
    var stpf = 0.0f64
    if fp > ls.fx {
        let theta = 3.0f64 * (ls.fx - fp) / (stp - ls.stx) + ls.gx + dp
        let s = lb_max3(math.abs[f64](theta), math.abs[f64](ls.gx), math.abs[f64](dp))
        var gamma = s * math.sqrt[f64]((theta / s) * (theta / s) - (ls.gx / s) * (dp / s))
        if stp < ls.stx { gamma = 0.0f64 - gamma }
        let p = (gamma - ls.gx) + theta
        let q = ((gamma - ls.gx) + gamma) + dp
        let r = p / q
        let stpc = ls.stx + r * (stp - ls.stx)
        let stpq = ls.stx + ((ls.gx / ((ls.fx - fp) / (stp - ls.stx) + ls.gx)) / 2.0f64) * (stp - ls.stx)
        if math.abs[f64](stpc - ls.stx) < math.abs[f64](stpq - ls.stx) {
            stpf = stpc
        } else {
            stpf = stpc + (stpq - stpc) / 2.0f64
        }
        ls.brackt = true
    } else if sgnd < 0.0f64 {
        let theta = 3.0f64 * (ls.fx - fp) / (stp - ls.stx) + ls.gx + dp
        let s = lb_max3(math.abs[f64](theta), math.abs[f64](ls.gx), math.abs[f64](dp))
        var gamma = s * math.sqrt[f64]((theta / s) * (theta / s) - (ls.gx / s) * (dp / s))
        if stp > ls.stx { gamma = 0.0f64 - gamma }
        let p = (gamma - dp) + theta
        let q = ((gamma - dp) + gamma) + ls.gx
        let r = p / q
        let stpc = stp + r * (ls.stx - stp)
        let stpq = stp + (dp / (dp - ls.gx)) * (ls.stx - stp)
        if math.abs[f64](stpc - stp) > math.abs[f64](stpq - stp) {
            stpf = stpc
        } else {
            stpf = stpq
        }
        ls.brackt = true
    } else if math.abs[f64](dp) < math.abs[f64](ls.gx) {
        let theta = 3.0f64 * (ls.fx - fp) / (stp - ls.stx) + ls.gx + dp
        let s = lb_max3(math.abs[f64](theta), math.abs[f64](ls.gx), math.abs[f64](dp))
        var disc = (theta / s) * (theta / s) - (ls.gx / s) * (dp / s)
        if disc < 0.0f64 { disc = 0.0f64 }
        var gamma = s * math.sqrt[f64](disc)
        if stp > ls.stx { gamma = 0.0f64 - gamma }
        let p = (gamma - dp) + theta
        let q = (gamma + (ls.gx - dp)) + gamma
        let r = p / q
        var stpc = stpmin
        if r < 0.0f64 && gamma != 0.0f64 {
            stpc = stp + r * (ls.stx - stp)
        } else if stp > ls.stx {
            stpc = stpmax
        }
        let stpq = stp + (dp / (dp - ls.gx)) * (ls.stx - stp)
        if ls.brackt {
            if math.abs[f64](stpc - stp) < math.abs[f64](stpq - stp) {
                stpf = stpc
            } else {
                stpf = stpq
            }
            if stp > ls.stx {
                let cap = stp + 0.66f64 * (ls.sty - stp)
                if cap < stpf { stpf = cap }
            } else {
                let cap = stp + 0.66f64 * (ls.sty - stp)
                if cap > stpf { stpf = cap }
            }
        } else {
            if math.abs[f64](stpc - stp) > math.abs[f64](stpq - stp) {
                stpf = stpc
            } else {
                stpf = stpq
            }
            if stpmax < stpf { stpf = stpmax }
            if stpmin > stpf { stpf = stpmin }
        }
    } else {
        if ls.brackt {
            let theta = 3.0f64 * (fp - ls.fy) / (ls.sty - stp) + ls.gy + dp
            let s = lb_max3(math.abs[f64](theta), math.abs[f64](ls.gy), math.abs[f64](dp))
            var gamma = s * math.sqrt[f64]((theta / s) * (theta / s) - (ls.gy / s) * (dp / s))
            if stp > ls.sty { gamma = 0.0f64 - gamma }
            let p = (gamma - dp) + theta
            let q = ((gamma - dp) + gamma) + ls.gy
            let r = p / q
            stpf = stp + r * (ls.sty - stp)
        } else if stp > ls.stx {
            stpf = stpmax
        } else {
            stpf = stpmin
        }
    }
    if fp > ls.fx {
        ls.sty = stp
        ls.fy = fp
        ls.gy = dp
    } else {
        if sgnd < 0.0f64 {
            ls.sty = ls.stx
            ls.fy = ls.fx
            ls.gy = ls.gx
        }
        ls.stx = stp
        ls.fx = fp
        ls.gx = dp
    }
    ret stpf
}

// MINPACK-2 dcsrch after START: given f and g at stp, returns (next step, status); status 0 asks for another
// evaluation, 1 is convergence and 2 a warning (the search ends either way)
fn lb_dcsrch(ls: *LbLs, f: f64, g: f64, stp0: f64, stpmin: f64, stpmax: f64) -> (f64, usize) {
    let ftol = 1.0e-3f64
    let gtol = 0.9f64
    let xtol = 0.1f64
    var stp = stp0
    let ftest = ls.finit + stp * ls.gtest
    if ls.stage == 1usize && f <= ftest && g >= 0.0f64 { ls.stage = 2usize }
    var status = 0usize
    if ls.brackt && (stp <= ls.stmin || stp >= ls.stmax) { status = 2usize }
    if ls.brackt && ls.stmax - ls.stmin <= xtol * ls.stmax { status = 2usize }
    if stp == stpmax && f <= ftest && g <= ls.gtest { status = 2usize }
    if stp == stpmin && (f > ftest || g >= ls.gtest) { status = 2usize }
    if f <= ftest && math.abs[f64](g) <= gtol * (0.0f64 - ls.ginit) { status = 1usize }
    if status != 0usize { ret (stp, status) }
    if ls.stage == 1usize && f <= ls.fx && f > ftest {
        let fm = f - stp * ls.gtest
        let gm = g - ls.gtest
        ls.fx = ls.fx - ls.stx * ls.gtest
        ls.fy = ls.fy - ls.sty * ls.gtest
        ls.gx = ls.gx - ls.gtest
        ls.gy = ls.gy - ls.gtest
        stp = lb_dcstep(ls, stp, fm, gm, ls.stmin, ls.stmax)
        ls.fx = ls.fx + ls.stx * ls.gtest
        ls.fy = ls.fy + ls.sty * ls.gtest
        ls.gx = ls.gx + ls.gtest
        ls.gy = ls.gy + ls.gtest
    } else {
        stp = lb_dcstep(ls, stp, f, g, ls.stmin, ls.stmax)
    }
    if ls.brackt {
        if math.abs[f64](ls.sty - ls.stx) >= 0.66f64 * ls.width1 { stp = ls.stx + 0.5f64 * (ls.sty - ls.stx) }
        ls.width1 = ls.width
        ls.width = math.abs[f64](ls.sty - ls.stx)
    }
    if ls.brackt {
        if ls.stx < ls.sty {
            ls.stmin = ls.stx
            ls.stmax = ls.sty
        } else {
            ls.stmin = ls.sty
            ls.stmax = ls.stx
        }
    } else {
        ls.stmin = stp + 1.1f64 * (stp - ls.stx)
        ls.stmax = stp + 4.0f64 * (stp - ls.stx)
    }
    if stp < stpmin { stp = stpmin }
    if stp > stpmax { stp = stpmax }
    if (ls.brackt && (stp <= ls.stmin || stp >= ls.stmax)) || (ls.brackt && ls.stmax - ls.stmin <= xtol * ls.stmax) { stp = ls.stx }
    ret (stp, 0usize)
}
